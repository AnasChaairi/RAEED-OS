-- The category supervisor's channel with parents: the supervisor picks a child and writes
-- an observation; both of the child's parents get a notification, and can like it or
-- reply. The supervisor reads the replies and can answer. Advisors can read everything.

create table if not exists public.child_messages (
  id uuid primary key default gen_random_uuid(),
  child_id uuid not null references public.children (id) on delete cascade,
  author_id uuid not null default auth.uid() references public.people (id) on delete cascade,
  body text not null check (char_length(btrim(body)) between 1 and 2000),
  created_at timestamptz not null default now()
);
create index if not exists child_messages_child on public.child_messages (child_id, created_at desc);

create table if not exists public.child_message_replies (
  id uuid primary key default gen_random_uuid(),
  message_id uuid not null references public.child_messages (id) on delete cascade,
  author_id uuid not null default auth.uid() references public.people (id) on delete cascade,
  body text not null check (char_length(btrim(body)) between 1 and 2000),
  created_at timestamptz not null default now()
);
create index if not exists child_message_replies_message on public.child_message_replies (message_id, created_at);

create table if not exists public.child_message_likes (
  message_id uuid not null references public.child_messages (id) on delete cascade,
  person_id uuid not null default auth.uid() references public.people (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (message_id, person_id)
);

-- Who reads a child's messages: their parents, the supervisor of their فئة, advisors.
create or replace function public.reads_child_messages(c uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select has_role('advisor') or supervises_child(c) or parent_of_child(c)
$$;

create or replace function public.reads_message(m uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from child_messages x where x.id = m and reads_child_messages(x.child_id))
$$;

-- Someone who wrote in a conversation the caller reads: parents see the supervisor's
-- name, and each other's.
create or replace function public.wrote_to_me(p uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from child_messages m where m.author_id = p and reads_child_messages(m.child_id))
      or exists (select 1 from child_message_replies r join child_messages m on m.id = r.message_id
                 where r.author_id = p and reads_child_messages(m.child_id))
      or exists (select 1 from child_message_likes l join child_messages m on m.id = l.message_id
                 where l.person_id = p and reads_child_messages(m.child_id))
$$;

revoke execute on function public.reads_child_messages(uuid), public.reads_message(uuid), public.wrote_to_me(uuid)
  from public, anon;
grant execute on function public.reads_child_messages(uuid), public.reads_message(uuid), public.wrote_to_me(uuid)
  to authenticated;

alter table public.child_messages enable row level security;
alter table public.child_message_replies enable row level security;
alter table public.child_message_likes enable row level security;

drop policy if exists cm_read on public.child_messages;
create policy cm_read on public.child_messages for select using (reads_child_messages(child_id));
drop policy if exists cm_insert on public.child_messages;
create policy cm_insert on public.child_messages for insert with check (
  author_id = auth.uid() and (supervises_child(child_id) or has_role('advisor')));
drop policy if exists cm_delete on public.child_messages;
create policy cm_delete on public.child_messages for delete using (author_id = auth.uid());

drop policy if exists cmr_read on public.child_message_replies;
create policy cmr_read on public.child_message_replies for select using (reads_message(message_id));
drop policy if exists cmr_insert on public.child_message_replies;
create policy cmr_insert on public.child_message_replies for insert with check (
  author_id = auth.uid() and reads_message(message_id));
drop policy if exists cmr_delete on public.child_message_replies;
create policy cmr_delete on public.child_message_replies for delete using (author_id = auth.uid());

drop policy if exists cml_read on public.child_message_likes;
create policy cml_read on public.child_message_likes for select using (reads_message(message_id));
drop policy if exists cml_insert on public.child_message_likes;
create policy cml_insert on public.child_message_likes for insert with check (
  person_id = auth.uid() and reads_message(message_id));
drop policy if exists cml_delete on public.child_message_likes;
create policy cml_delete on public.child_message_likes for delete using (person_id = auth.uid());

grant select, insert, delete on public.child_messages, public.child_message_replies, public.child_message_likes
  to authenticated;

drop policy if exists people_message_read on public.people;
create policy people_message_read on public.people for select using (wrote_to_me(id));

-- Notifications --------------------------------------------------------------------------------

alter table public.notification_outbox drop constraint if exists notification_outbox_kind_check;
alter table public.notification_outbox add constraint notification_outbox_kind_check check (kind in (
  'session_created', 'session_changed', 'session_cancelled', 'absence_alert',
  'child_message', 'child_message_reply', 'child_message_like'));

-- A new observation: one notification to each parent of the child.
create or replace function public.notify_child_message() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into notification_outbox (recipient_id, kind, title, body, data)
  select cp.parent_id, 'child_message',
         'ملاحظة جديدة عن ' || split_part(c.full_name, ' ', 1),
         left(new.body, 180),
         jsonb_build_object('message_id', new.id, 'child_id', c.id)
  from child_parents cp join children c on c.id = cp.child_id
  where cp.child_id = new.child_id and cp.parent_id <> new.author_id;
  return new;
end $$;
drop trigger if exists child_messages_notify on public.child_messages;
create trigger child_messages_notify after insert on public.child_messages
  for each row execute function public.notify_child_message();

-- A reply: everyone else in the conversation (the author of the observation, the child's
-- parents and whoever already replied).
create or replace function public.notify_child_message_reply() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  m child_messages;
  who text;
begin
  select * into m from child_messages where id = new.message_id;
  select split_part(full_name, ' ', 1) into who from people where id = new.author_id;
  insert into notification_outbox (recipient_id, kind, title, body, data)
  select distinct r.id, 'child_message_reply',
         'ردّ ' || coalesce(who, '') || ' على ملاحظة ' || split_part(c.full_name, ' ', 1),
         left(new.body, 180),
         jsonb_build_object('message_id', m.id, 'child_id', m.child_id)
  from children c,
       lateral (
         select m.author_id as id
         union select cp.parent_id from child_parents cp where cp.child_id = m.child_id
         union select x.author_id from child_message_replies x where x.message_id = m.id
       ) r
  where c.id = m.child_id and r.id <> new.author_id;
  return new;
end $$;
drop trigger if exists child_message_replies_notify on public.child_message_replies;
create trigger child_message_replies_notify after insert on public.child_message_replies
  for each row execute function public.notify_child_message_reply();

-- A like: the author of the observation.
create or replace function public.notify_child_message_like() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  m child_messages;
  who text;
begin
  select * into m from child_messages where id = new.message_id;
  if m.author_id = new.person_id then
    return new;
  end if;
  select split_part(full_name, ' ', 1) into who from people where id = new.person_id;
  insert into notification_outbox (recipient_id, kind, title, body, data)
  select m.author_id, 'child_message_like',
         'أعجب ' || coalesce(who, '') || ' بملاحظتك عن ' || split_part(c.full_name, ' ', 1),
         left(m.body, 180),
         jsonb_build_object('message_id', m.id, 'child_id', m.child_id)
  from children c where c.id = m.child_id;
  return new;
end $$;
drop trigger if exists child_message_likes_notify on public.child_message_likes;
create trigger child_message_likes_notify after insert on public.child_message_likes
  for each row execute function public.notify_child_message_like();

revoke execute on function public.notify_child_message(), public.notify_child_message_reply(),
  public.notify_child_message_like() from public, anon, authenticated;
