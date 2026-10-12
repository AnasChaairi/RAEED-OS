-- Stage 3: sessions, attendance and absence follow-up.

-- A follow-up call that got no answer keeps the alert open; the last try is shown on it.
alter table public.absence_alerts
  add column last_attempt_at timestamptz,
  add column last_attempt_by uuid references public.people(id);

-- Bulk session writes (a weekly series, "all upcoming") queue one notification per parent
-- themselves and silence the per-row trigger with this transaction-local flag.
create or replace function public.queue_session_notification()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  kind text;
  verb text;
begin
  if coalesce(current_setting('raeed.quiet', true), '') = 'on' then
    return new;
  end if;
  if tg_op = 'INSERT' then
    kind := 'session_created'; verb := 'حصة جديدة';
  elsif new.status = 'cancelled' and old.status <> 'cancelled' then
    kind := 'session_cancelled'; verb := 'حصة ملغاة';
  elsif (new.session_date, new.start_time, new.end_time, new.place, new.floor, new.address, new.pickup_time, new.pickup_place)
        is distinct from
        (old.session_date, old.start_time, old.end_time, old.place, old.floor, old.address, old.pickup_time, old.pickup_place) then
    kind := 'session_changed'; verb := 'تغيير موعد';
  else
    return new;
  end if;

  insert into notification_outbox (recipient_id, kind, title, body, data)
  select cp.parent_id, kind,
         verb || ' · ' || split_part(c.full_name, ' ', 1),
         new.title || ' · ' || to_char(new.session_date, 'DD/MM') || ' · ' || to_char(new.start_time, 'HH24:MI')
           || case when tg_op = 'UPDATE' and kind = 'session_changed' and new.start_time <> old.start_time
                   then ' بدل ' || to_char(old.start_time, 'HH24:MI') else '' end,
         jsonb_build_object('session_id', new.id, 'child_id', c.id)
  from child_groups cg
  join children c on c.id = cg.child_id
  join child_parents cp on cp.child_id = c.id
  where cg.group_id = new.group_id and cg.to_date is null;

  return new;
end $function$;

-- One notification per parent of the group's children, for a bulk change.
create or replace function public.queue_group_notification(g uuid, s uuid, kind text, verb text, body text)
returns void
language sql
security definer
set search_path to 'public'
as $function$
  insert into notification_outbox (recipient_id, kind, title, body, data)
  select cp.parent_id, kind, verb || ' · ' || split_part(c.full_name, ' ', 1), body,
         jsonb_build_object('session_id', s, 'child_id', c.id)
  from child_groups cg
  join children c on c.id = cg.child_id
  join child_parents cp on cp.child_id = c.id
  where cg.group_id = g and cg.to_date is null
$function$;
revoke all on function public.queue_group_notification(uuid, uuid, text, text, text) from public, anon, authenticated;

-- Creates one session, or a weekly series with one row per date. Materials go on the
-- first session. Returns the first session's id.
create or replace function public.create_sessions(
  p_group uuid, p_fields jsonb, p_dates date[], p_weekdays smallint[], p_materials jsonb default '[]'
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
  d date;
  n int := coalesce(array_length(p_dates, 1), 0);
begin
  if not teaches_group(p_group) then
    raise exception 'not_allowed' using errcode = '42501';
  end if;
  if n = 0 then
    raise exception 'no_dates' using errcode = '22023';
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
                          map_url, dropoff_place, dropoff_time, pickup_place, pickup_time, created_by)
    values (p_group, series, r.title, d, r.start_time, r.end_time, r.place, r.floor, r.address,
            r.map_url, r.dropoff_place, r.dropoff_time, r.pickup_place, r.pickup_time, auth.uid())
    returning coalesce(first_id, id) into first_id;
  end loop;
  insert into materials (session_id, kind, url, label)
  select first_id, (m->>'kind')::material_kind, m->>'url', m->>'label'
  from jsonb_array_elements(coalesce(p_materials, '[]')) m;
  if n > 1 then
    perform queue_group_notification(p_group, first_id, 'session_created', 'حصص جديدة',
      r.title || ' · أسبوعياً من ' || to_char(p_dates[1], 'DD/MM') || ' إلى ' || to_char(p_dates[n], 'DD/MM')
        || ' · ' || to_char(r.start_time, 'HH24:MI'));
    perform set_config('raeed.quiet', 'off', true);
  end if;
  return first_id;
end $function$;

-- Edits one session, or this one and the later ones of its series (date excepted). A new
-- time or place marks the session as changed.
create or replace function public.update_sessions(p_session uuid, p_fields jsonb, p_upcoming boolean)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  s sessions;
  r sessions;
begin
  select * into s from sessions where id = p_session;
  if s.id is null or not teaches_group(s.group_id) then
    raise exception 'not_allowed' using errcode = '42501';
  end if;
  r := jsonb_populate_record(null::sessions, p_fields);
  if p_upcoming and s.series_id is not null then
    perform set_config('raeed.quiet', 'on', true);
  end if;
  update sessions t set
    title = r.title,
    session_date = case when p_upcoming and s.series_id is not null then t.session_date else r.session_date end,
    start_time = r.start_time, end_time = r.end_time, place = r.place, floor = r.floor, address = r.address,
    map_url = r.map_url, dropoff_place = r.dropoff_place, dropoff_time = r.dropoff_time,
    pickup_place = r.pickup_place, pickup_time = r.pickup_time,
    status = case
      when t.status = 'cancelled' then t.status
      when (t.start_time, t.end_time, t.place, t.floor, t.address, t.pickup_place, t.pickup_time)
           is distinct from (r.start_time, r.end_time, r.place, r.floor, r.address, r.pickup_place, r.pickup_time)
        or (not (p_upcoming and s.series_id is not null) and t.session_date <> r.session_date)
        then 'changed'::session_status
      else t.status end,
    updated_at = now()
  where case when p_upcoming and s.series_id is not null
             then t.series_id = s.series_id and t.session_date >= s.session_date and t.status <> 'cancelled'
             else t.id = s.id end;
  if p_upcoming and s.series_id is not null then
    if (s.start_time, s.end_time, s.place, s.floor, s.address, s.pickup_place, s.pickup_time)
       is distinct from (r.start_time, r.end_time, r.place, r.floor, r.address, r.pickup_place, r.pickup_time) then
      perform queue_group_notification(s.group_id, s.id, 'session_changed', 'تغيير الحصص',
        r.title || ' · من ' || to_char(s.session_date, 'DD/MM') || ' · ' || to_char(r.start_time, 'HH24:MI'));
    end if;
    perform set_config('raeed.quiet', 'off', true);
  end if;
end $function$;

-- Cancels one session, or this one and the later ones of its series.
create or replace function public.cancel_sessions(p_session uuid, p_reason text, p_upcoming boolean)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  s sessions;
begin
  select * into s from sessions where id = p_session;
  if s.id is null or not teaches_group(s.group_id) then
    raise exception 'not_allowed' using errcode = '42501';
  end if;
  if p_upcoming and s.series_id is not null then
    perform set_config('raeed.quiet', 'on', true);
    update sessions set status = 'cancelled', cancel_reason = p_reason, updated_at = now()
    where series_id = s.series_id and session_date >= s.session_date and status <> 'cancelled';
    perform queue_group_notification(s.group_id, s.id, 'session_cancelled', 'حصص ملغاة',
      s.title || ' · ابتداءً من ' || to_char(s.session_date, 'DD/MM'));
    perform set_config('raeed.quiet', 'off', true);
  else
    update sessions set status = 'cancelled', cancel_reason = p_reason, updated_at = now() where id = s.id;
  end if;
end $function$;

revoke all on function public.create_sessions(uuid, jsonb, date[], smallint[], jsonb) from public, anon;
revoke all on function public.update_sessions(uuid, jsonb, boolean) from public, anon;
revoke all on function public.cancel_sessions(uuid, text, boolean) from public, anon;
grant execute on function public.create_sessions(uuid, jsonb, date[], smallint[], jsonb) to authenticated;
grant execute on function public.update_sessions(uuid, jsonb, boolean) to authenticated;
grant execute on function public.cancel_sessions(uuid, text, boolean) to authenticated;

-- Absence alerts: re-saving a sheet must not raise the same alert again after it was
-- closed, and correcting an absence removes the alert it raised if nobody acted on it yet.
create or replace function public.raise_absence_alert()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  g uuid;
  last_two record;
begin
  if new.status <> 'absent' then
    delete from absence_alerts
    where child_id = new.child_id and status = 'open' and new.session_id = any(session_ids)
      and last_attempt_at is null;
    return new;
  end if;
  select group_id into g from sessions where id = new.session_id;

  select array_agg(id order by session_date desc, start_time desc) as ids,
         bool_and(st = 'absent') as both_absent, count(*) as n
    into last_two
    from (
      select s.id, s.session_date, s.start_time, a.status as st
      from sessions s join attendance a on a.session_id = s.id and a.child_id = new.child_id
      where s.group_id = g and s.status <> 'cancelled'
      order by s.session_date desc, s.start_time desc
      limit 2
    ) recent;

  if last_two.n = 2 and last_two.both_absent
     and not exists (select 1 from absence_alerts where child_id = new.child_id and session_ids = last_two.ids) then
    insert into absence_alerts (child_id, group_id, session_ids)
    values (new.child_id, g, last_two.ids)
    on conflict (child_id) where status = 'open' do nothing;
  end if;
  return new;
end $function$;
