-- Request from the academy (2026-11-28): the مشرف العام publishes إخبارات عامة (the
-- academy's news) for everyone in the app, or only for some roles: أولياء الأمور, المؤطرون,
-- مشرفو الفئات, المشرفون العامون. Each one is a push notification plus an entry in the bell's
-- «الإخبارات العامة» tab, where it stays readable, also for people who join later.

-- Kinds ---------------------------------------------------------------------------------------

alter table public.notification_outbox drop constraint if exists notification_outbox_kind_check;
alter table public.notification_outbox add constraint notification_outbox_kind_check check (kind in (
  'session_created', 'session_changed', 'session_cancelled', 'absence_alert',
  'child_message', 'child_message_reply', 'child_message_like', 'instructor_absence',
  'session_reminder', 'activity_created', 'activity_changed', 'activity_cancelled', 'activity_reminder',
  'child_absence', 'homework_assigned',
  'session_assigned', 'session_unassigned', 'session_observation', 'child_note', 'child_absent',
  'child_absence_cancelled', 'instructor_absence_cancelled',
  'homework_changed', 'homework_cancelled', 'homework_reminder',
  'announcement'));

-- Table ---------------------------------------------------------------------------------------

-- audience: the roles it is for, any of 'parent', 'instructor', 'category_supervisor',
-- 'advisor'. Empty means everyone.
create table if not exists public.announcements (
  id uuid primary key default gen_random_uuid(),
  title text not null check (length(btrim(title)) between 1 and 120),
  body text not null check (length(btrim(body)) between 1 and 4000),
  audience text[] not null default '{}'
    check (audience <@ array['parent', 'instructor', 'category_supervisor', 'advisor']),
  author_id uuid references public.people (id) on delete set null,
  recipients int not null default 0,
  created_at timestamptz not null default now()
);
create index if not exists announcements_created on public.announcements (created_at desc);

-- The audience roles person [p] belongs to. An account that is مؤطر only so that it can be a
-- مشرف فئة (it teaches no فئة) counts as مشرف فئة, not as مؤطر.
create or replace function public.audience_roles(p uuid) returns text[]
language sql stable security definer set search_path = public as $$
  select array_remove(array[
    case when exists (select 1 from person_roles where person_id = p and role = 'parent') then 'parent' end,
    case when exists (select 1 from person_roles where person_id = p and role = 'instructor')
          and (exists (select 1 from group_instructors where person_id = p)
               or not exists (select 1 from group_supervisors where person_id = p))
         then 'instructor' end,
    case when exists (select 1 from group_supervisors where person_id = p) then 'category_supervisor' end,
    case when exists (select 1 from person_roles where person_id = p and role = 'advisor') then 'advisor' end
  ], null)
$$;
revoke execute on function public.audience_roles(uuid) from public, anon, authenticated;

-- The caller's own audience roles, for the read policy.
create or replace function public.my_audience_roles() returns text[]
language sql stable security definer set search_path = public as $$
  select audience_roles(auth.uid())
$$;
revoke execute on function public.my_audience_roles() from public, anon;
grant execute on function public.my_audience_roles() to authenticated;

-- Read: the مشرف العام sees them all; everyone else those meant for one of their roles.
alter table public.announcements enable row level security;
drop policy if exists announcements_read on public.announcements;
create policy announcements_read on public.announcements for select using (
  has_role('advisor') or audience = '{}' or audience && my_audience_roles());
grant select on public.announcements to authenticated;
-- Writes go through publish_announcement / delete_announcement only.

-- Publish -------------------------------------------------------------------------------------

-- Publishes an announcement and queues it for everyone in [p_audience] (empty: everyone),
-- except its author. Returns the number of people it was sent to.
create or replace function public.publish_announcement(p_title text, p_body text, p_audience text[] default '{}')
returns int
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  a_id uuid;
  aud text[] := coalesce(p_audience, '{}');
  people_ids uuid[];
  n int;
  url text;
begin
  if not has_role('advisor') then
    raise exception 'only a general supervisor can publish announcements' using errcode = '42501';
  end if;
  -- Picking every role is the same as everyone.
  if aud @> array['parent', 'instructor', 'category_supervisor', 'advisor'] then aud := '{}'; end if;

  select coalesce(array_agg(p.id), '{}') into people_ids
  from people p
  where p.id is distinct from auth.uid()
    and (aud = '{}' and exists (select 1 from person_roles r where r.person_id = p.id)
         or aud <> '{}' and aud && audience_roles(p.id));
  n := cardinality(people_ids);

  insert into announcements (title, body, audience, author_id, recipients)
  values (btrim(p_title), btrim(p_body), aud, auth.uid(), n)
  returning id into a_id;

  perform queue_notification(people_ids, 'announcement', 'إخبار عام: ' || btrim(p_title),
    left(btrim(p_body), 300), jsonb_build_object('announcement_id', a_id));

  -- The insert woke the sender once, and each run sends 200: wake it once more for every
  -- further 200, so a big audience gets the news now rather than over the next half hour.
  -- Runs claim their rows with skip locked, so they never send the same one twice.
  url := notification_sender_url();
  if n > 200 and url is not null and exists (select 1 from pg_extension where extname = 'pg_net') then
    for i in 1 .. (n - 1) / 200 loop
      execute $q$select net.http_post(url := $1, body := '{}'::jsonb,
        headers := '{"Content-Type": "application/json"}'::jsonb)$q$ using url;
    end loop;
  end if;
  return n;
end $function$;
revoke execute on function public.publish_announcement(text, text, text[]) from public, anon;
grant execute on function public.publish_announcement(text, text, text[]) to authenticated;

-- Removes an announcement from the tab, and its notifications from every bell.
create or replace function public.delete_announcement(p_id uuid)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  if not has_role('advisor') then
    raise exception 'only a general supervisor can delete announcements' using errcode = '42501';
  end if;
  delete from notification_outbox where kind = 'announcement' and data->>'announcement_id' = p_id::text;
  delete from announcements where id = p_id;
end $function$;
revoke execute on function public.delete_announcement(uuid) from public, anon;
grant execute on function public.delete_announcement(uuid) to authenticated;
