-- Stage 4: parents' schedule, push notifications, statistics and the child profile.

-- A moved session remembers when it was first planned, so parents see "كان 17:00".
alter table public.sessions
  add column original_date date,
  add column original_start time,
  add column original_end time;

create or replace function public.sessions_remember_original()
returns trigger
language plpgsql
set search_path to 'public'
as $function$
begin
  if (new.session_date, new.start_time, new.end_time) is distinct from (old.session_date, old.start_time, old.end_time)
     and old.original_date is null then
    new.original_date := old.session_date;
    new.original_start := old.start_time;
    new.original_end := old.end_time;
  end if;
  return new;
end $function$;

create trigger sessions_remember_original before update on public.sessions
  for each row execute function public.sessions_remember_original();
revoke execute on function public.sessions_remember_original() from public, anon, authenticated;

-- The parents of the caller's children, and whether each has a phone that receives
-- notifications. For the parent's account screen.
create or replace function public.my_children_parents()
returns table (child_id uuid, parent_id uuid, full_name text, notified boolean)
language sql
stable
security definer
set search_path to 'public'
as $function$
  select cp.child_id, p.id, p.full_name, exists (select 1 from devices d where d.person_id = p.id)
  from child_parents mine
  join child_parents cp on cp.child_id = mine.child_id
  join people p on p.id = cp.parent_id
  where mine.parent_id = auth.uid()
  order by p.id <> auth.uid(), p.full_name
$function$;
revoke execute on function public.my_children_parents() from public, anon;
grant execute on function public.my_children_parents() to authenticated;

-- Push notifications ------------------------------------------------------------------

-- A phone registers its push token for whoever is signed in on it. The same phone may
-- have belonged to someone else before (a shared family phone), so the token moves.
create or replace function public.register_device(p_token text, p_platform text)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  if auth.uid() is null then
    raise exception 'not signed in';
  end if;
  insert into devices (person_id, push_token, platform)
  values (auth.uid(), p_token, p_platform)
  on conflict (push_token) do update
    set person_id = excluded.person_id, platform = excluded.platform, updated_at = now();
end $function$;
revoke execute on function public.register_device(text, text) from public, anon;
grant execute on function public.register_device(text, text) to authenticated;

-- The send-notifications server function claims unsent rows, so two runs never send the
-- same one. A claim older than five minutes is retried. devices_reached is the sent log.
alter table public.notification_outbox
  add column claimed_at timestamptz,
  add column devices_reached smallint;

create or replace function public.claim_notifications(p_limit int default 100)
returns setof public.notification_outbox
language sql
security definer
set search_path to 'public'
as $function$
  update notification_outbox o set claimed_at = now()
  where o.id in (
    select id from notification_outbox
    where sent_at is null and (claimed_at is null or claimed_at < now() - interval '5 minutes')
    order by created_at
    limit p_limit
    for update skip locked)
  returning o.*
$function$;
revoke execute on function public.claim_notifications(int) from public, anon, authenticated;
grant execute on function public.claim_notifications(int) to service_role;

-- New rows wake the send-notifications function at once; a job every five minutes picks
-- up anything a failed run left behind. Both need pg_net and pg_cron, which exist on
-- Supabase but not on the plain Postgres the local tests use.
do $$ begin
  create extension if not exists pg_net;
  create extension if not exists pg_cron;
exception when others then
  raise notice 'pg_net or pg_cron unavailable: notifications are not sent from this database';
end $$;

create or replace function public.wake_notification_sender()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  if exists (select 1 from pg_extension where extname = 'pg_net') then
    execute $q$select net.http_post(
      url := 'https://ezqmiwqpiinxuqjvgiye.supabase.co/functions/v1/send-notifications',
      body := '{}'::jsonb,
      headers := '{"Content-Type": "application/json"}'::jsonb)$q$;
  end if;
  return null;
end $function$;
revoke execute on function public.wake_notification_sender() from public, anon, authenticated;

create trigger notification_outbox_wake after insert on public.notification_outbox
  for each statement execute function public.wake_notification_sender();

do $$ begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule('send-notifications', '*/5 * * * *', $q$
      select net.http_post(
        url := 'https://ezqmiwqpiinxuqjvgiye.supabase.co/functions/v1/send-notifications',
        body := '{}'::jsonb,
        headers := '{"Content-Type": "application/json"}'::jsonb)
      where exists (select 1 from public.notification_outbox where sent_at is null)$q$);
  end if;
end $$;
