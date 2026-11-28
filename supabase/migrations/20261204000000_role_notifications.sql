-- Request from the academy (2026-11-28): every role gets a notification (push + the bell)
-- for what concerns them. Whoever did the action is never notified.
--
--   مشرف الفئة  غياب مؤطر · ملاحظة مؤطر على حصة · ملاحظة على طفل · جواب ولي أمر ·
--               غياب طفل يسجله ولي الأمر (+ تراجع عنه)
--   مشرف عام    all of the above, plus every حصة / نشاط نوعي a مشرف الفئة adds, edits,
--               cancels or deletes
--   مؤطر        حصة / نشاط نوعي for their فئة · تعيينه (or no longer) مؤطراً في حصة ·
--               ملاحظة على حصة الفئة · ملاحظة على طفل من أطفال الفئة
--   ولي الأمر   رسالة من مشرف الفئة · واجب جديد / معدّل / ملغى / تذكير قبل يوم ·
--               حصة جديدة · نشاط نوعي · غياب طفله المسجّل في الحصة
--
-- Also: a حصة or نشاط deleted before it took place is announced like a cancellation.

-- Kinds ---------------------------------------------------------------------------------------

alter table public.notification_outbox drop constraint if exists notification_outbox_kind_check;
alter table public.notification_outbox add constraint notification_outbox_kind_check check (kind in (
  'session_created', 'session_changed', 'session_cancelled', 'absence_alert',
  'child_message', 'child_message_reply', 'child_message_like', 'instructor_absence',
  'session_reminder', 'activity_created', 'activity_changed', 'activity_cancelled', 'activity_reminder',
  'child_absence', 'homework_assigned',
  'session_assigned', 'session_unassigned', 'session_observation', 'child_note', 'child_absent',
  'child_absence_cancelled', 'instructor_absence_cancelled',
  'homework_changed', 'homework_cancelled', 'homework_reminder'));

-- Helpers -------------------------------------------------------------------------------------

-- One notification to each of [p_people], once each, except the caller and [p_except].
create or replace function public.queue_notification(p_people uuid[], p_kind text, p_title text, p_body text,
                                                     p_data jsonb default '{}', p_except uuid default null)
returns void
language sql
security definer
set search_path to 'public'
as $function$
  insert into notification_outbox (recipient_id, kind, title, body, data)
  select distinct x.p, p_kind, p_title, p_body, coalesce(p_data, '{}')
  from unnest(p_people) x(p)
  join people pe on pe.id = x.p
  where x.p is distinct from auth.uid() and x.p is distinct from p_except
$function$;
revoke all on function public.queue_notification(uuid[], text, text, text, jsonb, uuid) from public, anon, authenticated;

-- Every مشرف عام.
create or replace function public.advisor_ids() returns uuid[]
language sql stable security definer set search_path = public as $$
  select coalesce(array_agg(person_id), '{}') from person_roles where role = 'advisor'
$$;

-- Who runs session [s]: those picked for it, or the group's instructors when nobody was.
create or replace function public.session_runner_ids(s uuid) returns uuid[]
language sql stable security definer set search_path = public as $$
  select coalesce(array_agg(distinct r.person_id), '{}')
  from sessions x,
  lateral (
    select si.person_id from session_instructors si where si.session_id = x.id
    union
    select gi.person_id from group_instructors gi
    where gi.group_id = x.group_id and not exists (select 1 from session_instructors y where y.session_id = x.id)
  ) r
  where x.id = s
$$;

-- The instructors and supervisors of فئة [g].
create or replace function public.group_staff_ids(g uuid) returns uuid[]
language sql stable security definer set search_path = public as $$
  select coalesce(array_agg(distinct p), '{}') from (
    select person_id p from group_instructors where group_id = g
    union select person_id from group_supervisors where group_id = g
  ) x
$$;

-- The supervisors of فئة [g].
create or replace function public.group_supervisor_ids(g uuid) returns uuid[]
language sql stable security definer set search_path = public as $$
  select coalesce(array_agg(person_id), '{}') from group_supervisors where group_id = g
$$;

-- The supervisors of [s]'s فئة who do not run it (those who do hear as instructors).
create or replace function public.session_supervisor_ids(s uuid) returns uuid[]
language sql stable security definer set search_path = public as $$
  select coalesce(array_agg(gs.person_id), '{}')
  from sessions x join group_supervisors gs on gs.group_id = x.group_id
  where x.id = s and gs.person_id <> all(session_runner_ids(s))
$$;
revoke all on function public.session_supervisor_ids(uuid) from public, anon, authenticated;

-- The caller's first name, to say who did it.
create or replace function public.actor_name() returns text
language sql stable security definer set search_path = public as $$
  select coalesce(nullif(split_part(btrim(full_name), ' ', 1), ''), 'مشرف') from people where id = auth.uid()
$$;

create or replace function public.first_name(n text) returns text
language sql immutable as $$ select coalesce(nullif(split_part(btrim(n), ' ', 1), ''), '') $$;

revoke all on function public.advisor_ids(), public.session_runner_ids(uuid), public.group_staff_ids(uuid),
  public.group_supervisor_ids(uuid), public.actor_name() from public, anon, authenticated;

-- Parents: never the one who did it (a staff member can also be a parent) --------------------

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
  where cg.group_id = new.group_id and cg.to_date is null and cp.parent_id is distinct from auth.uid();

  return new;
end $function$;

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
  where cg.group_id = g and cg.to_date is null and cp.parent_id is distinct from auth.uid()
$function$;
revoke all on function public.queue_group_notification(uuid, uuid, text, text, text) from public, anon, authenticated;

create or replace function public.queue_activity_notification(p_activity uuid, p_kind text, p_verb text, p_body text,
                                                              p_advisors boolean default false)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  d jsonb := jsonb_build_object('activity_id', p_activity);
begin
  insert into notification_outbox (recipient_id, kind, title, body, data)
  select distinct cp.parent_id, p_kind, p_verb || ' · ' || split_part(c.full_name, ' ', 1), p_body,
         d || jsonb_build_object('child_id', c.id)
  from activity_groups ag
  join child_groups cg on cg.group_id = ag.group_id and cg.to_date is null
  join children c on c.id = cg.child_id
  join child_parents cp on cp.child_id = c.id
  where ag.activity_id = p_activity and cp.parent_id is distinct from auth.uid();

  insert into notification_outbox (recipient_id, kind, title, body, data)
  select r.person_id, p_kind, p_verb || ' · ' || (
           select string_agg(g.name, '، ' order by g.name)
           from activity_groups x join groups g on g.id = x.group_id where x.activity_id = p_activity),
         p_body, d
  from (
    select gi.person_id from activity_groups ag join group_instructors gi on gi.group_id = ag.group_id
    where ag.activity_id = p_activity
    union
    select gs.person_id from activity_groups ag join group_supervisors gs on gs.group_id = ag.group_id
    where ag.activity_id = p_activity
    union
    select pr.person_id from person_roles pr where p_advisors and pr.role = 'advisor'
  ) r
  where r.person_id is distinct from auth.uid();
end $function$;
revoke all on function public.queue_activity_notification(uuid, text, text, text, boolean) from public, anon, authenticated;

-- حصص: the مشرف عام hears of every one a مشرف الفئة plans or edits; instructors hear when
-- they are picked for a حصة, or no longer are -----------------------------------------------

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
  body text;
  picked boolean := coalesce(array_length(p_instructors, 1), 0) > 0;
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
    body := r.title || ' · أسبوعياً من ' || to_char(p_dates[1], 'DD/MM') || ' إلى ' || to_char(p_dates[n], 'DD/MM')
      || ' · ' || to_char(r.start_time, 'HH24:MI');
    perform queue_group_notification(p_group, first_id, 'session_created', 'حصص جديدة', body);
    perform queue_staff_notification(first_id,
      case when picked then 'session_assigned' else 'session_created' end,
      case when picked then 'تعيينك مؤطراً · ' else 'حصص جديدة · ' end || gname, body);
    perform set_config('raeed.quiet', 'off', true);
  else
    body := r.title || ' · ' || to_char(p_dates[1], 'DD/MM') || ' · ' || to_char(r.start_time, 'HH24:MI');
    perform queue_staff_notification(first_id,
      case when picked then 'session_assigned' else 'session_created' end,
      case when picked then 'تعيينك مؤطراً · ' else 'حصة جديدة · ' end || gname, body);
  end if;
  -- The فئة's supervisors, when someone else (the مشرف عام) plans for it.
  perform queue_notification(session_supervisor_ids(first_id), 'session_created',
    case when n > 1 then 'حصص جديدة · ' else 'حصة جديدة · ' end || gname, 'أضافها ' || actor_name() || ' · ' || body,
    jsonb_build_object('session_id', first_id, 'group_id', p_group));
  if not has_role('advisor') then
    perform queue_notification(advisor_ids(), 'session_created',
      case when n > 1 then 'حصص جديدة · ' else 'حصة جديدة · ' end || gname, 'أضافها ' || actor_name() || ' · ' || body,
      jsonb_build_object('session_id', first_id, 'group_id', p_group));
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
  when_text text;
  old_picked uuid[];
  old_runners uuid[];
  new_runners uuid[];
  live boolean;
begin
  select * into s from sessions where id = p_session;
  if s.id is null or not (has_role('advisor') or supervises_group(s.group_id)) then
    raise exception 'not_allowed' using errcode = '42501';
  end if;
  if p_instructors is not null then
    perform check_session_instructors(s.group_id, p_instructors);
  end if;
  old_picked := array(select person_id from session_instructors where session_id = s.id);
  old_runners := session_runner_ids(s.id);
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
  when_text := case when series_path
    then r.title || ' · من ' || to_char(s.session_date, 'DD/MM') || ' · ' || to_char(r.start_time, 'HH24:MI')
    else r.title || ' · ' || to_char(r.session_date, 'DD/MM') || ' · ' || to_char(r.start_time, 'HH24:MI') end;
  if series_path then
    if moved then
      perform queue_group_notification(s.group_id, s.id, 'session_changed', 'تغيير الحصص', when_text);
      perform queue_staff_notification(s.id, 'session_changed', 'تغيير الحصص · ' || gname, when_text);
    end if;
    perform set_config('raeed.quiet', 'off', true);
  elsif moved and s.status <> 'cancelled' then
    perform queue_staff_notification(s.id, 'session_changed', 'تغيير موعد · ' || gname,
      when_text || case when r.start_time <> s.start_time then ' بدل ' || to_char(s.start_time, 'HH24:MI') else '' end);
  end if;

  -- Who runs it now, for a حصة that is still to come.
  live := s.status <> 'cancelled'
      and (series_path or (r.session_date + r.end_time) at time zone 'Africa/Casablanca' > now());
  if live and p_instructors is not null and edited is not null then
    new_runners := session_runner_ids(s.id);
    perform queue_notification(
      array(select p from unnest(p_instructors) p where p <> all(old_picked)),
      'session_assigned', 'تعيينك مؤطراً · ' || gname, when_text,
      jsonb_build_object('session_id', s.id));
    perform queue_notification(
      array(select p from unnest(old_runners) p where p <> all(new_runners)),
      'session_unassigned', 'لم تعد مؤطراً لهذه الحصة · ' || gname, when_text,
      jsonb_build_object('session_id', s.id));
  end if;

  if edited is not null then
    perform queue_notification(session_supervisor_ids(s.id) || case when has_role('advisor') then '{}'::uuid[] else advisor_ids() end,
      'session_changed',
      case when series_path then 'تعديل الحصص · ' else 'تعديل حصة · ' end || gname,
      'عدّلها ' || actor_name() || ' · ' || when_text,
      jsonb_build_object('session_id', s.id, 'group_id', s.group_id));
  end if;
end $function$;

-- Cancelling: unchanged, except that the فئة's supervisors hear of it when someone else
-- (the مشرف عام) cancels.
create or replace function public.cancel_sessions(p_session uuid, p_reason text, p_upcoming boolean)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  s sessions;
  gname text;
  body text;
begin
  select * into s from sessions where id = p_session;
  if s.id is null or not (has_role('advisor') or supervises_group(s.group_id)) then
    raise exception 'not_allowed' using errcode = '42501';
  end if;
  select name into gname from groups where id = s.group_id;
  if p_upcoming and s.series_id is not null then
    body := s.title || ' · ابتداءً من ' || to_char(s.session_date, 'DD/MM');
    perform set_config('raeed.quiet', 'on', true);
    update sessions set status = 'cancelled', cancel_reason = p_reason, updated_at = now()
    where series_id = s.series_id and session_date >= s.session_date and status <> 'cancelled';
    perform queue_group_notification(s.group_id, s.id, 'session_cancelled', 'حصص ملغاة', body);
    perform queue_staff_notification(s.id, 'session_cancelled', 'حصص ملغاة · ' || gname, body);
    perform queue_notification(session_supervisor_ids(s.id) || advisor_ids(), 'session_cancelled', 'حصص ملغاة · ' || gname,
      body || coalesce(' · ' || nullif(btrim(p_reason), ''), '') || ' · ألغاها ' || actor_name(),
      jsonb_build_object('session_id', s.id));
    perform set_config('raeed.quiet', 'off', true);
  else
    body := s.title || ' · ' || to_char(s.session_date, 'DD/MM') || ' · ' || to_char(s.start_time, 'HH24:MI');
    update sessions set status = 'cancelled', cancel_reason = p_reason, updated_at = now() where id = s.id;
    perform queue_staff_notification(s.id, 'session_cancelled', 'حصة ملغاة · ' || gname, body);
    perform queue_notification(session_supervisor_ids(s.id) || advisor_ids(), 'session_cancelled', 'حصة ملغاة · ' || gname,
      body || coalesce(' · ' || nullif(btrim(p_reason), ''), '') || ' · ألغاها ' || actor_name(),
      jsonb_build_object('session_id', s.id));
  end if;
end $function$;

-- Deleting حصص that are still to come: announced like a cancellation, one notification per
-- person for the whole series. Not when a whole فئة is deleted.
create or replace function public.notify_sessions_deleted() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  x record;
  body text;
  plural boolean;
  gname text;
begin
  if coalesce(current_setting('raeed.quiet', true), '') = 'on' then
    return null;
  end if;
  for x in
    select g.group_id, count(*) n, min(g.session_date) d0, max(g.session_date) d1,
           (array_agg(g.title order by g.session_date, g.start_time))[1] t,
           (array_agg(g.start_time order by g.session_date, g.start_time))[1] st
    from gone g
    where g.status <> 'cancelled' and (g.session_date + g.end_time) at time zone 'Africa/Casablanca' > now()
    group by g.group_id
  loop
    select name into gname from groups where id = x.group_id;
    if gname is null then
      continue;
    end if;
    plural := x.n > 1;
    body := case when plural
      then x.t || ' · ' || x.n || ' حصص من ' || to_char(x.d0, 'DD/MM') || ' إلى ' || to_char(x.d1, 'DD/MM')
      else x.t || ' · ' || to_char(x.d0, 'DD/MM') || ' · ' || to_char(x.st, 'HH24:MI') end;
    insert into notification_outbox (recipient_id, kind, title, body, data)
    select cp.parent_id, 'session_cancelled',
           case when plural then 'حصص ملغاة · ' else 'حصة ملغاة · ' end || split_part(c.full_name, ' ', 1),
           body, jsonb_build_object('child_id', c.id)
    from child_groups cg
    join children c on c.id = cg.child_id
    join child_parents cp on cp.child_id = c.id
    where cg.group_id = x.group_id and cg.to_date is null and cp.parent_id is distinct from auth.uid();
    perform queue_notification(
      group_staff_ids(x.group_id) || case when has_role('advisor') then '{}'::uuid[] else advisor_ids() end,
      'session_cancelled', case when plural then 'حصص محذوفة · ' else 'حصة محذوفة · ' end || gname,
      body || coalesce(' · حذفها ' || actor_name(), ''),
      jsonb_build_object('group_id', x.group_id));
  end loop;
  return null;
end $$;
revoke execute on function public.notify_sessions_deleted() from public, anon, authenticated;
drop trigger if exists sessions_deleted_notify on public.sessions;
create trigger sessions_deleted_notify after delete on public.sessions
  referencing old table as gone for each statement execute function public.notify_sessions_deleted();

-- Unchanged, except that deleting a فئة tells nobody about its حصص and واجبات.
create or replace function public.delete_group(g uuid) returns text
language plpgsql security definer set search_path = public as $$
declare
  logo text;
begin
  if not has_role('advisor') then
    raise exception 'advisors only' using errcode = '42501';
  end if;
  select logo_path into logo from groups where id = g;
  if not found then return null; end if;
  perform set_config('raeed.quiet', 'on', true);
  delete from sessions where group_id = g;
  delete from session_series where group_id = g;
  delete from absence_alerts where group_id = g;
  delete from homework where group_id = g;
  delete from child_groups where group_id = g;
  delete from groups where id = g;
  perform set_config('raeed.quiet', 'off', true);
  return logo;
end $$;

-- أنشطة نوعية: the مشرف عام hears of any edit by a مشرف الفئة; deleting a coming one is
-- announced like a cancellation --------------------------------------------------------------

create or replace function public.update_activity(p_activity uuid, p_fields jsonb, p_groups uuid[])
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  old special_activities;
  r special_activities;
  a special_activities;
  old_groups uuid[];
begin
  select * into old from special_activities where id = p_activity;
  if old.id is null or not can_manage_activity(p_activity) then
    raise exception 'not_allowed' using errcode = '42501';
  end if;
  perform check_activity_groups(p_groups);
  select array_agg(group_id order by group_id) into old_groups from activity_groups where activity_id = p_activity;
  r := jsonb_populate_record(null::special_activities, p_fields);
  update special_activities set
    kind = r.kind, custom_label = nullif(btrim(r.custom_label), ''), title = btrim(r.title), place = btrim(r.place),
    map_url = nullif(btrim(r.map_url), ''), meeting_place = nullif(btrim(r.meeting_place), ''),
    details = nullif(btrim(r.details), ''),
    start_date = r.start_date, start_time = r.start_time, end_date = r.end_date, end_time = r.end_time,
    -- Moved: reminded again the day before the new start.
    reminded_at = case
      when (old.start_date, old.start_time) is distinct from (r.start_date, r.start_time)
        then case when (r.start_date + r.start_time) at time zone 'Africa/Casablanca' < now() + interval '24 hours'
                  then now() end
      else old.reminded_at end,
    updated_at = now()
  where id = p_activity
  returning * into a;
  delete from activity_groups where activity_id = p_activity and group_id <> all(p_groups);
  insert into activity_groups (activity_id, group_id)
  select p_activity, g from unnest(p_groups) g on conflict do nothing;
  if a.status = 'planned' and (
       (old.start_date, old.start_time, old.end_date, old.end_time, old.place, old.meeting_place)
         is distinct from (a.start_date, a.start_time, a.end_date, a.end_time, a.place, a.meeting_place)
       or old_groups is distinct from (select array_agg(g order by g) from (select distinct unnest(p_groups) g) x)) then
    perform queue_activity_notification(a.id, 'activity_changed', 'تغيير نشاط', activity_summary(a),
                                        not has_role('advisor'));
  elsif not has_role('advisor') then
    -- Title, details or map only: just the مشرف عام.
    perform queue_notification(advisor_ids(), 'activity_changed', 'تعديل نشاط · ' || actor_name(),
      activity_summary(a), jsonb_build_object('activity_id', a.id));
  end if;
end $function$;

create or replace function public.delete_activity(p_activity uuid)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  a special_activities;
begin
  if not can_manage_activity(p_activity) then
    raise exception 'not_allowed' using errcode = '42501';
  end if;
  select * into a from special_activities where id = p_activity;
  if a.status = 'planned' and (a.end_date + a.end_time) at time zone 'Africa/Casablanca' > now() then
    perform queue_activity_notification(a.id, 'activity_cancelled', 'نشاط ملغى',
      activity_kind_label(a) || ': ' || a.title || ' · ' || to_char(a.start_date, 'DD/MM') || ' · الحصص المبرمجة في موعدها',
      not has_role('advisor'));
  end if;
  delete from special_activities where id = p_activity;
end $function$;

-- Observations on a حصة: every instructor of the فئة reads them now, not only those who run
-- it. Instructors of the فئة, its supervisors and the مشرف عام are notified ------------------

drop policy if exists observations_read on public.session_observations;
create policy observations_read on public.session_observations for select using (
  author_id = auth.uid() or has_role('advisor') or runs_session(session_id)
  or exists (select 1 from sessions s where s.id = session_id
             and (supervises_group(s.group_id) or teaches_group(s.group_id))));

create or replace function public.notify_session_observation() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  s sessions;
  gname text;
  who text;
begin
  select * into s from sessions where id = new.session_id;
  select name into gname from groups where id = s.group_id;
  select first_name(full_name) into who from people where id = new.author_id;
  if s.id is null then
    return new;
  end if;
  perform queue_notification(session_runner_ids(s.id) || group_staff_ids(s.group_id) || advisor_ids(),
    'session_observation', 'ملاحظة على حصة ' || gname || coalesce(' · ' || nullif(who, ''), ''),
    s.title || ' · ' || to_char(s.session_date, 'DD/MM') || ' · ' || left(new.body, 140),
    jsonb_build_object('session_id', s.id, 'group_id', s.group_id, 'observation_id', new.id),
    new.author_id);
  return new;
end $$;
revoke execute on function public.notify_session_observation() from public, anon, authenticated;
drop trigger if exists session_observations_notify on public.session_observations;
create trigger session_observations_notify after insert on public.session_observations
  for each row execute function public.notify_session_observation();

-- Notes on a child (staff only, never parents): the instructors and supervisors of the
-- child's فئة and the مشرف عام -----------------------------------------------------------------

create or replace function public.notify_child_note() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  kid text;
  who text;
  staff uuid[];
begin
  select first_name(full_name) into kid from children where id = new.child_id;
  select first_name(full_name) into who from people where id = new.author_id;
  select coalesce(array_agg(distinct p), '{}') into staff
  from child_groups cg, lateral unnest(group_staff_ids(cg.group_id)) p
  where cg.child_id = new.child_id and cg.to_date is null;
  perform queue_notification(staff || advisor_ids(), 'child_note',
    'ملاحظة على ' || coalesce(kid, 'طفل') || coalesce(' · ' || nullif(who, ''), ''),
    left(new.body, 180),
    jsonb_build_object('child_id', new.child_id, 'note_id', new.id),
    new.author_id);
  return new;
end $$;
revoke execute on function public.notify_child_note() from public, anon, authenticated;
drop trigger if exists notes_notify on public.notes;
create trigger notes_notify after insert on public.notes
  for each row execute function public.notify_child_note();

-- A parent's reply: also the مشرف عام. Otherwise unchanged -------------------------------------

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
         union select gs.person_id from child_groups cg join group_supervisors gs on gs.group_id = cg.group_id
               where cg.child_id = m.child_id and cg.to_date is null
         union select pr.person_id from person_roles pr
               where pr.role = 'advisor'
                 and exists (select 1 from child_parents y where y.child_id = m.child_id and y.parent_id = new.author_id)
       ) r
  where c.id = m.child_id and r.id is not null and r.id <> new.author_id;
  return new;
end $$;
revoke execute on function public.notify_child_message_reply() from public, anon, authenticated;

-- A parent reports a child's absence, or takes it back: the session's instructors, the
-- فئة's supervisors and the مشرف عام ------------------------------------------------------------

create or replace function public.notify_child_absence() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  s sessions;
  gname text;
  kid text;
begin
  select * into s from sessions where id = new.session_id;
  select name into gname from groups where id = s.group_id;
  select first_name(full_name) into kid from children where id = new.child_id;
  if s.id is null then
    return new;
  end if;
  perform queue_notification(session_runner_ids(s.id) || group_supervisor_ids(s.group_id) || advisor_ids(),
    'child_absence', 'غياب ' || coalesce(nullif(kid, ''), 'طفل') || ' عن حصة ' || gname,
    s.title || ' · ' || to_char(s.session_date, 'DD/MM') || ' ' || to_char(s.start_time, 'HH24:MI')
      || ' · ' || left(new.reason, 140),
    jsonb_build_object('session_id', s.id, 'group_id', s.group_id, 'child_id', new.child_id),
    new.reported_by);
  return new;
end $$;
revoke execute on function public.notify_child_absence() from public, anon, authenticated;

create or replace function public.notify_child_absence_cancelled() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  s sessions;
  gname text;
  kid text;
begin
  select * into s from sessions where id = old.session_id;
  -- Gone with its حصة or child, or already started: nothing to say.
  if s.id is null or s.status = 'cancelled'
     or (s.session_date + s.start_time) at time zone 'Africa/Casablanca' <= now() then
    return old;
  end if;
  select name into gname from groups where id = s.group_id;
  select first_name(full_name) into kid from children where id = old.child_id;
  if kid is null then
    return old;
  end if;
  perform queue_notification(session_runner_ids(s.id) || group_supervisor_ids(s.group_id) || advisor_ids(),
    'child_absence_cancelled', 'سيحضر ' || coalesce(nullif(kid, ''), 'طفل') || ' حصة ' || gname,
    s.title || ' · ' || to_char(s.session_date, 'DD/MM') || ' ' || to_char(s.start_time, 'HH24:MI')
      || ' · تراجع ولي الأمر عن الغياب',
    jsonb_build_object('session_id', s.id, 'group_id', s.group_id, 'child_id', old.child_id));
  return old;
end $$;
revoke execute on function public.notify_child_absence_cancelled() from public, anon, authenticated;
drop trigger if exists child_absence_reports_cancel_notify on public.child_absence_reports;
create trigger child_absence_reports_cancel_notify after delete on public.child_absence_reports
  for each row execute function public.notify_child_absence_cancelled();

-- An instructor takes back a notice of absence: the فئة's supervisors and the مشرف عام -------

create or replace function public.notify_instructor_absence_cancelled() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  s sessions;
  gname text;
  who text;
begin
  select * into s from sessions where id = old.session_id;
  if s.id is null or s.status = 'cancelled'
     or (s.session_date + s.end_time) at time zone 'Africa/Casablanca' <= now() then
    return old;
  end if;
  select name into gname from groups where id = s.group_id;
  select first_name(full_name) into who from people where id = old.person_id;
  if who is null then
    return old;
  end if;
  perform queue_notification(group_supervisor_ids(s.group_id) || advisor_ids(),
    'instructor_absence_cancelled', 'سيحضر ' || coalesce(nullif(who, ''), 'المؤطر') || ' حصة ' || gname,
    s.title || ' · ' || to_char(s.session_date, 'DD/MM') || ' ' || to_char(s.start_time, 'HH24:MI')
      || ' · تراجع عن الغياب',
    jsonb_build_object('session_id', s.id, 'group_id', s.group_id, 'person_id', old.person_id),
    old.person_id);
  return old;
end $$;
revoke execute on function public.notify_instructor_absence_cancelled() from public, anon, authenticated;
drop trigger if exists instructor_absences_cancel_notify on public.instructor_absences;
create trigger instructor_absences_cancel_notify after delete on public.instructor_absences
  for each row execute function public.notify_instructor_absence_cancelled();

-- A child marked غائب in the attendance: their parents. Not when the parent already reported
-- the absence, and not for old حصص synced late -------------------------------------------------

create or replace function public.notify_child_absent() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  s sessions;
  gname text;
begin
  if new.status <> 'absent' or (tg_op = 'UPDATE' and old.status = 'absent') then
    return new;
  end if;
  select * into s from sessions where id = new.session_id;
  if s.id is null or s.session_date < (now() at time zone 'Africa/Casablanca')::date - 1
     or exists (select 1 from child_absence_reports r where r.session_id = new.session_id and r.child_id = new.child_id) then
    return new;
  end if;
  select name into gname from groups where id = s.group_id;
  insert into notification_outbox (recipient_id, kind, title, body, data)
  select distinct cp.parent_id, 'child_absent', 'غياب ' || first_name(c.full_name) || ' عن الحصة',
         s.title || ' · ' || to_char(s.session_date, 'DD/MM') || ' ' || to_char(s.start_time, 'HH24:MI') || ' · ' || gname,
         jsonb_build_object('session_id', s.id, 'child_id', c.id)
  from children c join child_parents cp on cp.child_id = c.id
  where c.id = new.child_id and cp.parent_id is distinct from auth.uid() and cp.parent_id <> new.recorded_by;
  return new;
end $$;
revoke execute on function public.notify_child_absent() from public, anon, authenticated;
drop trigger if exists attendance_absent_notify on public.attendance;
create trigger attendance_absent_notify after insert or update of status on public.attendance
  for each row execute function public.notify_child_absent();

-- الواجبات: parents hear when one is changed or removed, and the evening before it is due
-- (unless already marked تم). The فئة's supervisors hear of homework the مشرف عام gives ------

alter table public.homework add column if not exists reminded_at timestamptz;

create or replace function public.queue_homework_notification(p_homework uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  h homework;
begin
  select * into h from homework where id = p_homework;
  insert into notification_outbox (recipient_id, kind, title, body, data)
  select distinct cp.parent_id, 'homework_assigned', 'واجب جديد · ' || split_part(c.full_name, ' ', 1),
         left(homework_summary(h), 160) || ' · التسليم: ' || to_char(h.due_date, 'DD/MM'),
         jsonb_build_object('homework_id', h.id, 'child_id', c.id)
  from children c join child_parents cp on cp.child_id = c.id
  where homework_has_child(h.id, c.id) and cp.parent_id is distinct from auth.uid();
  perform queue_notification(group_supervisor_ids(h.group_id), 'homework_assigned',
    'واجب جديد · ' || (select name from groups where id = h.group_id),
    left(homework_summary(h), 160) || ' · التسليم: ' || to_char(h.due_date, 'DD/MM') || ' · كلّف به ' || actor_name(),
    jsonb_build_object('homework_id', h.id, 'group_id', h.group_id));
end $$;
revoke all on function public.queue_homework_notification(uuid) from public, anon, authenticated;

-- One notification per parent per child among [p_children], about homework [h].
create or replace function public.queue_homework_parents(h homework, p_children uuid[], p_kind text, p_verb text,
                                                         p_body text)
returns void
language sql security definer set search_path = public as $$
  insert into notification_outbox (recipient_id, kind, title, body, data)
  select distinct cp.parent_id, p_kind, p_verb || ' · ' || split_part(c.full_name, ' ', 1), p_body,
         jsonb_build_object('homework_id', h.id, 'child_id', c.id)
  from children c join child_parents cp on cp.child_id = c.id
  where c.id = any(p_children) and cp.parent_id is distinct from auth.uid()
$$;
revoke all on function public.queue_homework_parents(homework, uuid[], text, text, text) from public, anon, authenticated;

create or replace function public.homework_child_ids(h uuid) returns uuid[]
language sql stable security definer set search_path = public as $$
  select coalesce(array_agg(c.id), '{}') from children c where homework_has_child(h, c.id)
$$;
revoke all on function public.homework_child_ids(uuid) from public, anon, authenticated;

-- Unchanged, except: children newly concerned get «واجب جديد», the others «تعديل واجب» when
-- what to do or the due date changed.
create or replace function public.update_homework(p_id uuid, p_fields jsonb, p_children uuid[] default null)
returns void
language plpgsql security definer set search_path = public as $$
declare
  h homework;
  old homework;
  kids_before uuid[];
  kids_after uuid[];
  body text;
begin
  select * into h from homework where id = p_id;
  if h.id is null or not assigns_homework(h.group_id) then
    raise exception 'not_allowed' using errcode = '42501';
  end if;
  old := h;
  kids_before := homework_child_ids(p_id);
  update homework set
    template = p_fields ->> 'template',
    fields = coalesce(p_fields -> 'fields', '{}'::jsonb),
    details = nullif(btrim(p_fields ->> 'details'), ''),
    due_date = (p_fields ->> 'due_date')::date,
    whole_group = coalesce(array_length(p_children, 1), 0) = 0,
    reminded_at = case when due_date is distinct from (p_fields ->> 'due_date')::date then null else reminded_at end
  where id = p_id
  returning * into h;
  perform set_homework_children(h, p_children);
  delete from homework_status s where s.homework_id = p_id and not homework_has_child(p_id, s.child_id);
  kids_after := homework_child_ids(p_id);
  body := left(homework_summary(h), 160) || ' · التسليم: ' || to_char(h.due_date, 'DD/MM');
  perform queue_homework_parents(h, array(select c from unnest(kids_after) c where c <> all(kids_before)),
    'homework_assigned', 'واجب جديد', body);
  if (old.template, old.fields, old.details, old.due_date) is distinct from (h.template, h.fields, h.details, h.due_date) then
    perform queue_homework_parents(h, array(select c from unnest(kids_after) c where c = any(kids_before)),
      'homework_changed', 'تعديل واجب', body);
  end if;
end $$;

create or replace function public.notify_homework_deleted() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if coalesce(current_setting('raeed.quiet', true), '') <> 'on'
     and old.due_date >= (now() at time zone 'Africa/Casablanca')::date then
    perform queue_homework_parents(old, homework_child_ids(old.id), 'homework_cancelled', 'واجب ملغى',
      left(homework_summary(old), 160) || ' · كان التسليم: ' || to_char(old.due_date, 'DD/MM'));
  end if;
  return old;
end $$;
revoke execute on function public.notify_homework_deleted() from public, anon, authenticated;
-- Before the delete, while its children are still listed.
drop trigger if exists homework_deleted_notify on public.homework;
create trigger homework_deleted_notify before delete on public.homework
  for each row execute function public.notify_homework_deleted();

-- The evening before the due date (from 17:00, Morocco time), for homework given before
-- then: the parents of each concerned child not yet marked تم. Run every 15 minutes.
create or replace function public.queue_homework_reminders(p_now timestamptz default now())
returns int
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  n int := 0;
  h homework;
  now_local timestamp := p_now at time zone 'Africa/Casablanca';
begin
  if now_local::time < time '17:00' then
    return 0;
  end if;
  for h in
    update homework x set reminded_at = p_now
    where x.reminded_at is null and x.due_date = now_local::date + 1
      and x.created_at < (now_local::date + time '17:00') at time zone 'Africa/Casablanca'
    returning x.*
  loop
    perform queue_homework_parents(h,
      array(select c from unnest(homework_child_ids(h.id)) c
            where not exists (select 1 from homework_status s where s.homework_id = h.id and s.child_id = c and s.done)),
      'homework_reminder', 'تذكير بواجب', left(homework_summary(h), 160) || ' · التسليم غداً');
    n := n + 1;
  end loop;
  return n;
end $function$;
revoke execute on function public.queue_homework_reminders(timestamptz) from public, anon, authenticated;

do $$ begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule('homework-reminders', '*/15 * * * *', 'select public.queue_homework_reminders()');
  end if;
end $$;
