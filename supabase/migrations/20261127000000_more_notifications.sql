-- Requests from the academy (2026-11-24):
-- 1. A reminder 5 hours before a session, switched on per session when it is planned. It
--    goes to the session's instructors and to the parents of the group's children.
-- 2. Instructors hear about sessions planned, changed or cancelled for them (until now
--    only parents did).
-- 3. An absence alert (a child absent twice in a row) is pushed to the group's instructors
--    and its category supervisors, who follow it up.

alter table public.sessions
  add column if not exists remind boolean not null default false,
  add column if not exists reminded_at timestamptz;

alter table public.notification_outbox drop constraint if exists notification_outbox_kind_check;
alter table public.notification_outbox add constraint notification_outbox_kind_check check (kind in (
  'session_created', 'session_changed', 'session_cancelled', 'absence_alert',
  'child_message', 'child_message_reply', 'child_message_like', 'instructor_absence',
  'session_reminder'));

-- One notification to each instructor who runs [p_session]: those picked for it, or, when
-- nobody was picked, the group's instructors. Not to whoever made the change.
create or replace function public.queue_staff_notification(p_session uuid, p_kind text, p_title text, p_body text)
returns void
language sql
security definer
set search_path to 'public'
as $function$
  insert into notification_outbox (recipient_id, kind, title, body, data)
  select distinct r.person_id, p_kind, p_title, p_body, jsonb_build_object('session_id', p_session)
  from sessions s,
  lateral (
    select si.person_id from session_instructors si where si.session_id = s.id
    union
    select gi.person_id from group_instructors gi
    where gi.group_id = s.group_id and not exists (select 1 from session_instructors x where x.session_id = s.id)
  ) r
  where s.id = p_session and r.person_id is distinct from auth.uid()
$function$;
revoke all on function public.queue_staff_notification(uuid, text, text, text) from public, anon, authenticated;

-- The planning functions: unchanged, except that they save the reminder switch and tell
-- the instructors once per call.

create or replace function public.create_sessions(
  p_group uuid, p_fields jsonb, p_dates date[], p_weekdays smallint[], p_materials jsonb default '[]',
  p_instructors uuid[] default null
)
returns uuid
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  r sessions;
  series uuid;
  first_id uuid;
  new_id uuid;
  d date;
  n int := coalesce(array_length(p_dates, 1), 0);
  gname text;
begin
  if not (has_role('advisor') or supervises_group(p_group)) then
    raise exception 'not_allowed' using errcode = '42501';
  end if;
  if n = 0 then
    raise exception 'no_dates' using errcode = '22023';
  end if;
  if p_instructors is not null then
    perform check_session_instructors(p_group, p_instructors);
  end if;
  r := jsonb_populate_record(null::sessions, p_fields);
  if p_weekdays is not null then
    insert into session_series (group_id, weekdays, start_date, end_date, created_by)
    values (p_group, p_weekdays, p_dates[1], p_dates[n], auth.uid())
    returning id into series;
  end if;
  if n > 1 then
    perform set_config('raeed.quiet', 'on', true);
  end if;
  foreach d in array p_dates loop
    insert into sessions (group_id, series_id, title, session_date, start_time, end_time, place, floor, address,
                          map_url, dropoff_place, dropoff_time, pickup_place, pickup_time, remind, created_by)
    values (p_group, series, r.title, d, r.start_time, r.end_time, r.place, r.floor, r.address,
            r.map_url, r.dropoff_place, r.dropoff_time, r.pickup_place, r.pickup_time, coalesce(r.remind, false),
            auth.uid())
    returning id into new_id;
    first_id := coalesce(first_id, new_id);
    if p_instructors is not null then
      insert into session_instructors (session_id, person_id)
      select new_id, p from unnest(p_instructors) p on conflict do nothing;
    end if;
  end loop;
  insert into materials (session_id, kind, url, label)
  select first_id, (m->>'kind')::material_kind, m->>'url', m->>'label'
  from jsonb_array_elements(coalesce(p_materials, '[]')) m;
  select name into gname from groups where id = p_group;
  if n > 1 then
    perform queue_group_notification(p_group, first_id, 'session_created', 'حصص جديدة',
      r.title || ' · أسبوعياً من ' || to_char(p_dates[1], 'DD/MM') || ' إلى ' || to_char(p_dates[n], 'DD/MM')
        || ' · ' || to_char(r.start_time, 'HH24:MI'));
    perform queue_staff_notification(first_id, 'session_created', 'حصص جديدة · ' || gname,
      r.title || ' · أسبوعياً من ' || to_char(p_dates[1], 'DD/MM') || ' إلى ' || to_char(p_dates[n], 'DD/MM')
        || ' · ' || to_char(r.start_time, 'HH24:MI'));
    perform set_config('raeed.quiet', 'off', true);
  else
    perform queue_staff_notification(first_id, 'session_created', 'حصة جديدة · ' || gname,
      r.title || ' · ' || to_char(p_dates[1], 'DD/MM') || ' · ' || to_char(r.start_time, 'HH24:MI'));
  end if;
  return first_id;
end $function$;

create or replace function public.update_sessions(
  p_session uuid, p_fields jsonb, p_upcoming boolean, p_instructors uuid[] default null
)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  s sessions;
  r sessions;
  edited uuid[];
  series_path boolean;
  moved boolean;
  gname text;
begin
  select * into s from sessions where id = p_session;
  if s.id is null or not (has_role('advisor') or supervises_group(s.group_id)) then
    raise exception 'not_allowed' using errcode = '42501';
  end if;
  if p_instructors is not null then
    perform check_session_instructors(s.group_id, p_instructors);
  end if;
  r := jsonb_populate_record(null::sessions, p_fields);
  series_path := p_upcoming and s.series_id is not null;
  if series_path then
    perform set_config('raeed.quiet', 'on', true);
  end if;
  with changed as (
    update sessions t set
      title = r.title,
      session_date = case when series_path then t.session_date else r.session_date end,
      start_time = r.start_time, end_time = r.end_time, place = r.place, floor = r.floor, address = r.address,
      map_url = r.map_url, dropoff_place = r.dropoff_place, dropoff_time = r.dropoff_time,
      pickup_place = r.pickup_place, pickup_time = r.pickup_time,
      remind = coalesce(r.remind, t.remind),
      -- A session that moves gets its reminder again at the new time.
      reminded_at = case
        when t.start_time <> r.start_time or (not series_path and t.session_date <> r.session_date) then null
        else t.reminded_at end,
      status = case
        when t.status = 'cancelled' then t.status
        when (t.start_time, t.end_time, t.place, t.floor, t.address, t.pickup_place, t.pickup_time)
             is distinct from (r.start_time, r.end_time, r.place, r.floor, r.address, r.pickup_place, r.pickup_time)
          or (not series_path and t.session_date <> r.session_date)
          then 'changed'::session_status
        else t.status end,
      updated_at = now()
    where case when series_path
               then t.series_id = s.series_id and t.session_date >= s.session_date and t.status <> 'cancelled'
               else t.id = s.id end
    returning t.id
  )
  select array_agg(id) into edited from changed;
  if p_instructors is not null and edited is not null then
    delete from session_instructors where session_id = any(edited);
    insert into session_instructors (session_id, person_id)
    select e, p from unnest(edited) e cross join unnest(p_instructors) p on conflict do nothing;
  end if;
  moved := (s.start_time, s.end_time, s.place, s.floor, s.address, s.pickup_place, s.pickup_time)
           is distinct from (r.start_time, r.end_time, r.place, r.floor, r.address, r.pickup_place, r.pickup_time)
        or (not series_path and s.session_date <> r.session_date);
  select name into gname from groups where id = s.group_id;
  if series_path then
    if moved then
      perform queue_group_notification(s.group_id, s.id, 'session_changed', 'تغيير الحصص',
        r.title || ' · من ' || to_char(s.session_date, 'DD/MM') || ' · ' || to_char(r.start_time, 'HH24:MI'));
      perform queue_staff_notification(s.id, 'session_changed', 'تغيير الحصص · ' || gname,
        r.title || ' · من ' || to_char(s.session_date, 'DD/MM') || ' · ' || to_char(r.start_time, 'HH24:MI'));
    end if;
    perform set_config('raeed.quiet', 'off', true);
  elsif moved and s.status <> 'cancelled' then
    perform queue_staff_notification(s.id, 'session_changed', 'تغيير موعد · ' || gname,
      r.title || ' · ' || to_char(r.session_date, 'DD/MM') || ' · ' || to_char(r.start_time, 'HH24:MI')
        || case when r.start_time <> s.start_time then ' بدل ' || to_char(s.start_time, 'HH24:MI') else '' end);
  end if;
end $function$;

create or replace function public.cancel_sessions(p_session uuid, p_reason text, p_upcoming boolean)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  s sessions;
  gname text;
begin
  select * into s from sessions where id = p_session;
  if s.id is null or not (has_role('advisor') or supervises_group(s.group_id)) then
    raise exception 'not_allowed' using errcode = '42501';
  end if;
  select name into gname from groups where id = s.group_id;
  if p_upcoming and s.series_id is not null then
    perform set_config('raeed.quiet', 'on', true);
    update sessions set status = 'cancelled', cancel_reason = p_reason, updated_at = now()
    where series_id = s.series_id and session_date >= s.session_date and status <> 'cancelled';
    perform queue_group_notification(s.group_id, s.id, 'session_cancelled', 'حصص ملغاة',
      s.title || ' · ابتداءً من ' || to_char(s.session_date, 'DD/MM'));
    perform queue_staff_notification(s.id, 'session_cancelled', 'حصص ملغاة · ' || gname,
      s.title || ' · ابتداءً من ' || to_char(s.session_date, 'DD/MM'));
    perform set_config('raeed.quiet', 'off', true);
  else
    update sessions set status = 'cancelled', cancel_reason = p_reason, updated_at = now() where id = s.id;
    perform queue_staff_notification(s.id, 'session_cancelled', 'حصة ملغاة · ' || gname,
      s.title || ' · ' || to_char(s.session_date, 'DD/MM') || ' · ' || to_char(s.start_time, 'HH24:MI'));
  end if;
end $function$;

-- Reminders ---------------------------------------------------------------------------------

-- Queues the reminder of every session with the switch on that starts within 5 hours and
-- has not been reminded yet. Run every 5 minutes. Returns how many sessions it reminded.
create or replace function public.queue_session_reminders()
returns int
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  n int := 0;
  s record;
begin
  for s in
    update sessions x set reminded_at = now()
    from groups g
    where g.id = x.group_id and x.remind and x.reminded_at is null and x.status <> 'cancelled'
      and (x.session_date + x.start_time) at time zone 'Africa/Casablanca'
          between now() and now() + interval '5 hours'
    returning x.id, x.group_id, x.title, x.start_time, g.name as gname
  loop
    insert into notification_outbox (recipient_id, kind, title, body, data)
    select cp.parent_id, 'session_reminder', 'تذكير بحصة · ' || split_part(c.full_name, ' ', 1),
           s.title || ' · على الساعة ' || to_char(s.start_time, 'HH24:MI'),
           jsonb_build_object('session_id', s.id, 'child_id', c.id)
    from child_groups cg
    join children c on c.id = cg.child_id
    join child_parents cp on cp.child_id = c.id
    where cg.group_id = s.group_id and cg.to_date is null;
    perform queue_staff_notification(s.id, 'session_reminder', 'تذكير بحصة · ' || s.gname,
      s.title || ' · على الساعة ' || to_char(s.start_time, 'HH24:MI'));
    n := n + 1;
  end loop;
  return n;
end $function$;
revoke execute on function public.queue_session_reminders() from public, anon, authenticated;

do $$ begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule('session-reminders', '*/5 * * * *', 'select public.queue_session_reminders()');
  end if;
end $$;

-- Absence alerts ----------------------------------------------------------------------------

create or replace function public.notify_absence_alert() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into notification_outbox (recipient_id, kind, title, body, data)
  select distinct r.person_id, 'absence_alert',
         'غياب مرتين متتاليتين · ' || split_part(c.full_name, ' ', 1),
         g.name || ' · تواصل مع ولي الأمر',
         jsonb_build_object('alert_id', new.id, 'child_id', new.child_id)
  from children c
  join groups g on g.id = new.group_id,
  lateral (
    select gi.person_id from group_instructors gi where gi.group_id = new.group_id
    union
    select gs.person_id from group_supervisors gs where gs.group_id = new.group_id
  ) r
  where c.id = new.child_id;
  return new;
end $$;
drop trigger if exists absence_alerts_notify on public.absence_alerts;
create trigger absence_alerts_notify after insert on public.absence_alerts
  for each row execute function public.notify_absence_alert();
revoke execute on function public.notify_absence_alert() from public, anon, authenticated;
