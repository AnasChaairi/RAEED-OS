-- Testers asked that only advisors plan sessions: an advisor creates, edits and cancels the
-- sessions of any group, and the group's instructors see them and take attendance.
-- Attendance rules are unchanged. The three functions keep their bodies; only the check
-- at the top moves from "teaches this group" to "is an advisor".

drop policy series_write on public.session_series;
create policy series_write on public.session_series for all
  using (has_role('advisor')) with check (has_role('advisor'));

drop policy sessions_write on public.sessions;
create policy sessions_write on public.sessions for all
  using (has_role('advisor')) with check (has_role('advisor'));

drop policy materials_write on public.materials;
create policy materials_write on public.materials for all
  using (has_role('advisor')) with check (has_role('advisor'));

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
  if not has_role('advisor') then
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
  if s.id is null or not has_role('advisor') then
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
  if s.id is null or not has_role('advisor') then
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

