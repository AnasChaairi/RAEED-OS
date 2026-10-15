-- Testers asked that the advisor picks who runs each session: one or more of the instructors
-- of its group. The group's other instructors still see the session and can take attendance.
-- Sessions planned before this change have no rows here.

create table if not exists public.session_instructors (
  session_id uuid not null references public.sessions (id) on delete cascade,
  person_id uuid not null references public.people (id) on delete cascade,
  primary key (session_id, person_id)
);
create index if not exists session_instructors_person on public.session_instructors (person_id);

alter table public.session_instructors enable row level security;

drop policy if exists si_read on public.session_instructors;
create policy si_read on public.session_instructors for select using (exists (
  select 1 from sessions s where s.id = session_id
  and (has_role('advisor') or teaches_group(s.group_id) or parent_in_group(s.group_id))));
drop policy if exists si_write on public.session_instructors;
create policy si_write on public.session_instructors for all
  using (has_role('advisor')) with check (has_role('advisor'));

grant select, insert, update, delete on public.session_instructors to authenticated;

-- Raises unless [p_people] is one or more of the instructors of [p_group].
create or replace function public.check_session_instructors(p_group uuid, p_people uuid[])
returns void
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
begin
  if coalesce(cardinality(p_people), 0) = 0 then
    raise exception 'no_instructors' using errcode = '22023';
  end if;
  if exists (
    select 1 from unnest(p_people) p
    where not exists (select 1 from group_instructors gi where gi.group_id = p_group and gi.person_id = p)
  ) then
    raise exception 'not_group_instructor' using errcode = '22023';
  end if;
end $function$;

-- The functions gain p_instructors. Older apps leave it out and the sessions get no names.
drop function if exists public.create_sessions(uuid, jsonb, date[], smallint[], jsonb);
drop function if exists public.update_sessions(uuid, jsonb, boolean);

-- Creates one session, or a weekly series with one row per date. Materials go on the
-- first session; the instructors on every one. Returns the first session's id.
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
begin
  if not has_role('advisor') then
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
                          map_url, dropoff_place, dropoff_time, pickup_place, pickup_time, created_by)
    values (p_group, series, r.title, d, r.start_time, r.end_time, r.place, r.floor, r.address,
            r.map_url, r.dropoff_place, r.dropoff_time, r.pickup_place, r.pickup_time, auth.uid())
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
  if n > 1 then
    perform queue_group_notification(p_group, first_id, 'session_created', 'حصص جديدة',
      r.title || ' · أسبوعياً من ' || to_char(p_dates[1], 'DD/MM') || ' إلى ' || to_char(p_dates[n], 'DD/MM')
        || ' · ' || to_char(r.start_time, 'HH24:MI'));
    perform set_config('raeed.quiet', 'off', true);
  end if;
  return first_id;
end $function$;

-- Edits one session, or this one and the later ones of its series (date excepted). A new
-- time or place marks the session as changed. With p_instructors, they replace the
-- instructors of every session edited.
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
begin
  select * into s from sessions where id = p_session;
  if s.id is null or not has_role('advisor') then
    raise exception 'not_allowed' using errcode = '42501';
  end if;
  if p_instructors is not null then
    perform check_session_instructors(s.group_id, p_instructors);
  end if;
  r := jsonb_populate_record(null::sessions, p_fields);
  if p_upcoming and s.series_id is not null then
    perform set_config('raeed.quiet', 'on', true);
  end if;
  with changed as (
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
               else t.id = s.id end
    returning t.id
  )
  select array_agg(id) into edited from changed;
  if p_instructors is not null and edited is not null then
    delete from session_instructors where session_id = any(edited);
    insert into session_instructors (session_id, person_id)
    select e, p from unnest(edited) e cross join unnest(p_instructors) p on conflict do nothing;
  end if;
  if p_upcoming and s.series_id is not null then
    if (s.start_time, s.end_time, s.place, s.floor, s.address, s.pickup_place, s.pickup_time)
       is distinct from (r.start_time, r.end_time, r.place, r.floor, r.address, r.pickup_place, r.pickup_time) then
      perform queue_group_notification(s.group_id, s.id, 'session_changed', 'تغيير الحصص',
        r.title || ' · من ' || to_char(s.session_date, 'DD/MM') || ' · ' || to_char(r.start_time, 'HH24:MI'));
    end if;
    perform set_config('raeed.quiet', 'off', true);
  end if;
end $function$;

revoke all on function public.check_session_instructors(uuid, uuid[]) from public, anon;
revoke all on function public.create_sessions(uuid, jsonb, date[], smallint[], jsonb, uuid[]) from public, anon;
revoke all on function public.update_sessions(uuid, jsonb, boolean, uuid[]) from public, anon;
grant execute on function public.check_session_instructors(uuid, uuid[]) to authenticated;
grant execute on function public.create_sessions(uuid, jsonb, date[], smallint[], jsonb, uuid[]) to authenticated;
grant execute on function public.update_sessions(uuid, jsonb, boolean, uuid[]) to authenticated;
