-- Requests from the academy's staff:
-- 1. A new role, مشرف الفئة (category supervisor): an advisor puts a staff member in charge
--    of one فئة. They see that فئة only, plan and edit its sessions (أنشطة), and follow
--    its instructors' work. Being in group_supervisors is what makes someone a category
--    supervisor: there is no new app_role value, so the manage-account function is unchanged.
-- 2. Only the instructors picked for a session take its attendance. Sessions planned before
--    instructors were picked (no session_instructors rows) stay open to the group's
--    instructors, as before.
-- 3. Instructors of a session write observations on it; the category supervisor and the
--    advisors read them.

-- Category supervisors ------------------------------------------------------------------

create table if not exists public.group_supervisors (
  group_id uuid not null references public.groups (id) on delete cascade,
  person_id uuid not null references public.people (id) on delete cascade,
  primary key (group_id, person_id)
);
create index if not exists group_supervisors_person on public.group_supervisors (person_id);

create or replace function public.supervises_group(g uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from group_supervisors where group_id = g and person_id = auth.uid())
$$;

create or replace function public.supervises_child(c uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from child_groups cg join group_supervisors gs on gs.group_id = cg.group_id
    where cg.child_id = c and cg.to_date is null and gs.person_id = auth.uid())
$$;

-- The person is picked to run session [s], or nobody was picked and they teach its group.
create or replace function public.runs_session(s uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select case
    when exists (select 1 from session_instructors where session_id = s)
      then exists (select 1 from session_instructors where session_id = s and person_id = auth.uid())
    else exists (select 1 from sessions x where x.id = s and teaches_group(x.group_id))
  end
$$;

revoke execute on function public.supervises_group(uuid), public.supervises_child(uuid), public.runs_session(uuid)
  from public, anon;
grant execute on function public.supervises_group(uuid), public.supervises_child(uuid), public.runs_session(uuid)
  to authenticated;

alter table public.group_supervisors enable row level security;
drop policy if exists gs_read on public.group_supervisors;
create policy gs_read on public.group_supervisors for select using (
  person_id = auth.uid() or has_role('advisor') or teaches_group(group_id) or supervises_group(group_id));
drop policy if exists gs_write on public.group_supervisors;
create policy gs_write on public.group_supervisors for all
  using (has_role('advisor')) with check (has_role('advisor'));
grant select, insert, update, delete on public.group_supervisors to authenticated;

-- What a category supervisor reads: their فئة, its children, parents, instructors, sessions,
-- attendance, notes and alerts. -----------------------------------------------------------

drop policy if exists people_supervisor_read on public.people;
create policy people_supervisor_read on public.people for select using (
  exists (select 1 from group_instructors gi where gi.person_id = people.id and supervises_group(gi.group_id))
  or exists (select 1 from child_parents cp where cp.parent_id = people.id and supervises_child(cp.child_id))
  -- Instructors see who supervises their groups.
  or exists (select 1 from group_supervisors gs where gs.person_id = people.id
             and (teaches_group(gs.group_id) or supervises_group(gs.group_id)))
);

drop policy groups_read on public.groups;
create policy groups_read on public.groups for select using (
  has_role('advisor') or teaches_group(id) or supervises_group(id) or parent_in_group(id));

drop policy gi_read on public.group_instructors;
create policy gi_read on public.group_instructors for select using (
  has_role('advisor') or teaches_group(group_id) or supervises_group(group_id) or parent_in_group(group_id));

drop policy children_read on public.children;
create policy children_read on public.children for select using (
  has_role('advisor') or teaches_child(id) or supervises_child(id) or parent_of_child(id));

drop policy cg_read on public.child_groups;
create policy cg_read on public.child_groups for select using (
  has_role('advisor') or teaches_child(child_id) or supervises_child(child_id) or parent_of_child(child_id));

drop policy cp_read on public.child_parents;
create policy cp_read on public.child_parents for select using (
  has_role('advisor') or teaches_child(child_id) or supervises_child(child_id) or parent_id = auth.uid());

drop policy attendance_read on public.attendance;
create policy attendance_read on public.attendance for select using (
  has_role('advisor') or teaches_child(child_id) or supervises_child(child_id));

drop policy notes_read on public.notes;
create policy notes_read on public.notes for select using (
  has_role('advisor') or teaches_child(child_id) or supervises_child(child_id));
drop policy notes_insert on public.notes;
create policy notes_insert on public.notes for insert with check (
  author_id = auth.uid() and (has_role('advisor') or teaches_child(child_id) or supervises_child(child_id)));

drop policy alerts_read on public.absence_alerts;
create policy alerts_read on public.absence_alerts for select using (
  has_role('advisor') or teaches_group(group_id) or supervises_group(group_id));
drop policy alerts_close on public.absence_alerts;
create policy alerts_close on public.absence_alerts for update using (
  has_role('advisor') or teaches_group(group_id) or supervises_group(group_id));

-- Planning: advisors for every فئة, a category supervisor for theirs. ---------------------

drop policy series_read on public.session_series;
create policy series_read on public.session_series for select using (
  has_role('advisor') or teaches_group(group_id) or supervises_group(group_id));
drop policy series_write on public.session_series;
create policy series_write on public.session_series for all
  using (has_role('advisor') or supervises_group(group_id))
  with check (has_role('advisor') or supervises_group(group_id));

drop policy sessions_read on public.sessions;
create policy sessions_read on public.sessions for select using (
  has_role('advisor') or teaches_group(group_id) or supervises_group(group_id) or parent_in_group(group_id));
drop policy sessions_write on public.sessions;
create policy sessions_write on public.sessions for all
  using (has_role('advisor') or supervises_group(group_id))
  with check (has_role('advisor') or supervises_group(group_id));

drop policy materials_read on public.materials;
create policy materials_read on public.materials for select using (exists (
  select 1 from sessions s where s.id = session_id
  and (has_role('advisor') or teaches_group(s.group_id) or supervises_group(s.group_id) or parent_in_group(s.group_id))));
drop policy materials_write on public.materials;
create policy materials_write on public.materials for all
  using (exists (select 1 from sessions s where s.id = session_id
                 and (has_role('advisor') or supervises_group(s.group_id))))
  with check (exists (select 1 from sessions s where s.id = session_id
                      and (has_role('advisor') or supervises_group(s.group_id))));

drop policy si_read on public.session_instructors;
create policy si_read on public.session_instructors for select using (exists (
  select 1 from sessions s where s.id = session_id
  and (has_role('advisor') or teaches_group(s.group_id) or supervises_group(s.group_id) or parent_in_group(s.group_id))));
drop policy si_write on public.session_instructors;
create policy si_write on public.session_instructors for all
  using (exists (select 1 from sessions s where s.id = session_id
                 and (has_role('advisor') or supervises_group(s.group_id))))
  with check (exists (select 1 from sessions s where s.id = session_id
                      and (has_role('advisor') or supervises_group(s.group_id))));

-- The three planning functions keep their bodies; only the check at the top changes from
-- "is an advisor" to "is an advisor, or supervises this فئة".

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
  if s.id is null or not (has_role('advisor') or supervises_group(s.group_id)) then
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
  if s.id is null or not (has_role('advisor') or supervises_group(s.group_id)) then
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

-- Attendance: only the instructors picked for the session. -----------------------------------

drop policy attendance_insert on public.attendance;
create policy attendance_insert on public.attendance for insert with check (
  recorded_by = auth.uid() and teaches_child(child_id) and runs_session(session_id));
drop policy attendance_update on public.attendance;
create policy attendance_update on public.attendance for update
  using (teaches_child(child_id) and runs_session(session_id))
  with check (recorded_by = auth.uid() and teaches_child(child_id) and runs_session(session_id));

-- Observations on a session -------------------------------------------------------------------

create table if not exists public.session_observations (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references public.sessions (id) on delete cascade,
  author_id uuid not null default auth.uid() references public.people (id) on delete cascade,
  body text not null check (char_length(btrim(body)) between 1 and 2000),
  created_at timestamptz not null default now()
);
create index if not exists session_observations_session on public.session_observations (session_id, created_at);

alter table public.session_observations enable row level security;

-- Read by the session's instructors, the category supervisor and advisors. Never parents.
drop policy if exists observations_read on public.session_observations;
create policy observations_read on public.session_observations for select using (
  author_id = auth.uid() or has_role('advisor') or runs_session(session_id)
  or exists (select 1 from sessions s where s.id = session_id and supervises_group(s.group_id)));
drop policy if exists observations_insert on public.session_observations;
create policy observations_insert on public.session_observations for insert with check (
  author_id = auth.uid() and runs_session(session_id));
drop policy if exists observations_delete on public.session_observations;
create policy observations_delete on public.session_observations for delete using (author_id = auth.uid());

grant select, insert, delete on public.session_observations to authenticated;
