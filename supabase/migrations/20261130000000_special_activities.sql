-- Request from the academy (2026-11-27): أنشطة نوعية (special activities) next to the
-- حصص: مخيم (camp), مبيت (sleepover), خرجة (outing), or a type the planner names. Each
-- has a title, one or more فئات, a place and a start and end that can span several days.
--
-- An activity has priority: a حصة of one of its فئات that overlaps it is replaced by it.
-- The حصة row is not touched. The app shows it crossed out ("ملغاة بسبب ..."), nobody
-- takes its attendance, and its 5-hour reminder is not sent. Cancelling or moving the
-- activity brings the حصة back by itself.
--
-- المشرف العام (role advisor) plans activities for any فئة, a مشرف الفئة only for the
-- فئات they supervise. Parents and the فئات' instructors and supervisors are notified
-- when an activity is planned, changed or cancelled, and reminded the day before.
-- Attendance is taken on the activity itself (activity_attendance).

-- Tables --------------------------------------------------------------------------------------

create table if not exists public.special_activities (
  id uuid primary key default gen_random_uuid(),
  -- camp = مخيم, overnight = مبيت, outing = خرجة, custom = custom_label.
  kind text not null check (kind in ('camp', 'overnight', 'outing', 'custom')),
  custom_label text,
  title text not null check (btrim(title) <> ''),
  place text not null check (btrim(place) <> ''),
  map_url text,
  -- Where the children are dropped off and picked up, when it is not the place itself.
  meeting_place text,
  -- What to bring, the cost, anything else the parents should know.
  details text,
  start_date date not null,
  start_time time not null,
  end_date date not null,
  end_time time not null,
  status text not null default 'planned' check (status in ('planned', 'cancelled')),
  cancel_reason text,
  reminded_at timestamptz,
  created_by uuid references public.people (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (kind <> 'custom' or btrim(coalesce(custom_label, '')) <> ''),
  check ((end_date + end_time) > (start_date + start_time))
);
create index if not exists special_activities_dates on public.special_activities (start_date, end_date);

create table if not exists public.activity_groups (
  activity_id uuid not null references public.special_activities (id) on delete cascade,
  group_id uuid not null references public.groups (id) on delete cascade,
  primary key (activity_id, group_id)
);
create index if not exists activity_groups_group on public.activity_groups (group_id);

create table if not exists public.activity_attendance (
  id uuid primary key default gen_random_uuid(),
  activity_id uuid not null references public.special_activities (id) on delete cascade,
  child_id uuid not null references public.children (id) on delete cascade,
  status public.attendance_status not null,
  recorded_by uuid not null references public.people (id),
  recorded_at timestamptz not null default now(),
  unique (activity_id, child_id)
);

-- Access helpers ------------------------------------------------------------------------------

-- The caller sees activity [a]: an advisor, or it is for a فئة they teach, supervise, or
-- have a child in.
create or replace function public.can_see_activity(a uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select has_role('advisor') or exists (
    select 1 from activity_groups ag
    where ag.activity_id = a
      and (teaches_group(ag.group_id) or supervises_group(ag.group_id) or parent_in_group(ag.group_id)))
$$;

-- The caller may change activity [a]: an advisor, or they supervise every فئة it is for.
create or replace function public.can_manage_activity(a uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select has_role('advisor') or (
    exists (select 1 from activity_groups where activity_id = a)
    and not exists (select 1 from activity_groups where activity_id = a and not supervises_group(group_id)))
$$;

-- The planned activity that replaces session [p_session], if any: one of the session's
-- فئة that overlaps it in time.
create or replace function public.session_activity(p_session uuid) returns uuid
language sql stable security definer set search_path = public as $$
  select a.id
  from sessions s
  join activity_groups ag on ag.group_id = s.group_id
  join special_activities a on a.id = ag.activity_id
  where s.id = p_session and a.status = 'planned'
    and (a.start_date + a.start_time) < (s.session_date + s.end_time)
    and (a.end_date + a.end_time) > (s.session_date + s.start_time)
  order by a.start_date, a.start_time
  limit 1
$$;

revoke execute on function public.can_see_activity(uuid), public.can_manage_activity(uuid),
  public.session_activity(uuid) from public, anon;
grant execute on function public.can_see_activity(uuid), public.can_manage_activity(uuid),
  public.session_activity(uuid) to authenticated;

-- Row-level security: read here, write through the functions below. -------------------------

alter table public.special_activities enable row level security;
alter table public.activity_groups enable row level security;
alter table public.activity_attendance enable row level security;

drop policy if exists activities_read on public.special_activities;
create policy activities_read on public.special_activities for select using (can_see_activity(id));
drop policy if exists activity_groups_read on public.activity_groups;
create policy activity_groups_read on public.activity_groups for select using (can_see_activity(activity_id));
grant select on public.special_activities, public.activity_groups to authenticated;

-- Attendance: the staff of the child's فئة (instructors, its supervisor) and advisors, for
-- a child of one of the activity's فئات. Parents do not read it, as for sessions.
create or replace function public.activity_has_child(a uuid, c uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from activity_groups ag
    join child_groups cg on cg.group_id = ag.group_id and cg.to_date is null
    where ag.activity_id = a and cg.child_id = c)
$$;
revoke execute on function public.activity_has_child(uuid, uuid) from public, anon;
grant execute on function public.activity_has_child(uuid, uuid) to authenticated;

drop policy if exists activity_attendance_read on public.activity_attendance;
create policy activity_attendance_read on public.activity_attendance for select using (
  has_role('advisor') or teaches_child(child_id) or supervises_child(child_id));
drop policy if exists activity_attendance_insert on public.activity_attendance;
create policy activity_attendance_insert on public.activity_attendance for insert with check (
  recorded_by = auth.uid() and activity_has_child(activity_id, child_id)
  and (has_role('advisor') or teaches_child(child_id) or supervises_child(child_id)));
drop policy if exists activity_attendance_update on public.activity_attendance;
create policy activity_attendance_update on public.activity_attendance for update
  using (has_role('advisor') or teaches_child(child_id) or supervises_child(child_id))
  with check (recorded_by = auth.uid() and activity_has_child(activity_id, child_id)
              and (has_role('advisor') or teaches_child(child_id) or supervises_child(child_id)));
grant select, insert, update on public.activity_attendance to authenticated;

-- Notifications -------------------------------------------------------------------------------

alter table public.notification_outbox drop constraint if exists notification_outbox_kind_check;
alter table public.notification_outbox add constraint notification_outbox_kind_check check (kind in (
  'session_created', 'session_changed', 'session_cancelled', 'absence_alert',
  'child_message', 'child_message_reply', 'child_message_like', 'instructor_absence',
  'session_reminder', 'activity_created', 'activity_changed', 'activity_cancelled', 'activity_reminder'));

-- مخيم, مبيت, خرجة, or the planner's own name for it.
create or replace function public.activity_kind_label(a special_activities) returns text
language sql immutable as $$
  select case a.kind
    when 'camp' then 'مخيم' when 'overnight' then 'مبيت' when 'outing' then 'خرجة'
    else coalesce(nullif(btrim(a.custom_label), ''), 'نشاط') end
$$;

-- "مخيم: مخيم الربيع · من 12/12 09:00 إلى 14/12 17:00 · غابة المعمورة"
create or replace function public.activity_summary(a special_activities) returns text
language sql immutable as $$
  select activity_kind_label(a) || ': ' || a.title || ' · '
    || case when a.start_date = a.end_date
         then to_char(a.start_date, 'DD/MM') || ' ' || to_char(a.start_time, 'HH24:MI') || '–' || to_char(a.end_time, 'HH24:MI')
         else 'من ' || to_char(a.start_date, 'DD/MM') || ' ' || to_char(a.start_time, 'HH24:MI')
              || ' إلى ' || to_char(a.end_date, 'DD/MM') || ' ' || to_char(a.end_time, 'HH24:MI') end
    || ' · ' || a.place
$$;
revoke execute on function public.activity_kind_label(special_activities), public.activity_summary(special_activities)
  from public, anon;

-- One notification to each parent of the activity's children (one per child), and one to
-- each instructor and supervisor of its فئات, except whoever made the change. With
-- [p_advisors], the advisors hear about it too (when a مشرف الفئة made the change).
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
  where ag.activity_id = p_activity;

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

-- Checks the فئات of an activity against the caller: at least one, and each one theirs
-- unless they are an advisor.
create or replace function public.check_activity_groups(p_groups uuid[]) returns void
language plpgsql stable security definer set search_path = public as $$
begin
  if coalesce(array_length(p_groups, 1), 0) = 0 then
    raise exception 'no_groups' using errcode = '22023';
  end if;
  if not has_role('advisor') and exists (select 1 from unnest(p_groups) g where not supervises_group(g)) then
    raise exception 'not_allowed' using errcode = '42501';
  end if;
end $$;
revoke all on function public.check_activity_groups(uuid[]) from public, anon, authenticated;

-- Planning ------------------------------------------------------------------------------------

-- A new activity for [p_groups]. [p_fields] holds the special_activities columns.
create or replace function public.create_activity(p_fields jsonb, p_groups uuid[])
returns uuid
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  r special_activities;
  a special_activities;
begin
  perform check_activity_groups(p_groups);
  r := jsonb_populate_record(null::special_activities, p_fields);
  insert into special_activities (kind, custom_label, title, place, map_url, meeting_place, details,
                                  start_date, start_time, end_date, end_time, created_by, reminded_at)
  values (r.kind, nullif(btrim(r.custom_label), ''), btrim(r.title), btrim(r.place), nullif(btrim(r.map_url), ''),
          nullif(btrim(r.meeting_place), ''), nullif(btrim(r.details), ''),
          r.start_date, r.start_time, r.end_date, r.end_time, auth.uid(),
          -- Planned less than a day ahead: the notification is the reminder.
          case when (r.start_date + r.start_time) at time zone 'Africa/Casablanca' < now() + interval '24 hours'
               then now() end)
  returning * into a;
  insert into activity_groups (activity_id, group_id)
  select a.id, g from unnest(p_groups) g on conflict do nothing;
  perform queue_activity_notification(a.id, 'activity_created', 'نشاط جديد', activity_summary(a),
                                      not has_role('advisor'));
  return a.id;
end $function$;

-- Edits activity [p_activity] and the فئات it is for.
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
  end if;
end $function$;

-- Cancels activity [p_activity]: the حصص it replaced take place again.
create or replace function public.cancel_activity(p_activity uuid, p_reason text)
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
  update special_activities set status = 'cancelled', cancel_reason = nullif(btrim(p_reason), ''), updated_at = now()
  where id = p_activity and status <> 'cancelled'
  returning * into a;
  if a.id is null then
    return;
  end if;
  perform queue_activity_notification(a.id, 'activity_cancelled', 'نشاط ملغى',
    activity_kind_label(a) || ': ' || a.title || ' · ' || to_char(a.start_date, 'DD/MM')
      || coalesce(' · ' || a.cancel_reason, '') || ' · الحصص المبرمجة في موعدها',
    not has_role('advisor'));
end $function$;

-- Deletes activity [p_activity] with its attendance. Nobody is notified.
create or replace function public.delete_activity(p_activity uuid)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  if not can_manage_activity(p_activity) then
    raise exception 'not_allowed' using errcode = '42501';
  end if;
  delete from special_activities where id = p_activity;
end $function$;

revoke all on function public.create_activity(jsonb, uuid[]), public.update_activity(uuid, jsonb, uuid[]),
  public.cancel_activity(uuid, text), public.delete_activity(uuid) from public, anon;
grant execute on function public.create_activity(jsonb, uuid[]), public.update_activity(uuid, jsonb, uuid[]),
  public.cancel_activity(uuid, text), public.delete_activity(uuid) to authenticated;

-- Reminders -----------------------------------------------------------------------------------

-- The day-before reminder of every planned activity that starts within 24 hours and has
-- not been reminded yet. Run every 15 minutes. Returns how many it reminded.
create or replace function public.queue_activity_reminders()
returns int
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  n int := 0;
  a special_activities;
begin
  for a in
    update special_activities x set reminded_at = now()
    where x.status = 'planned' and x.reminded_at is null
      and (x.start_date + x.start_time) at time zone 'Africa/Casablanca'
          between now() and now() + interval '24 hours'
    returning x.*
  loop
    perform queue_activity_notification(a.id, 'activity_reminder', 'تذكير بنشاط', activity_summary(a));
    n := n + 1;
  end loop;
  return n;
end $function$;
revoke execute on function public.queue_activity_reminders() from public, anon, authenticated;

do $$ begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule('activity-reminders', '*/15 * * * *', 'select public.queue_activity_reminders()');
  end if;
end $$;

-- A حصة replaced by an activity gets no 5-hour reminder. Otherwise unchanged.
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
      and session_activity(x.id) is null
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
