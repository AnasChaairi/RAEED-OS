-- Request from the academy (2026-11-27): in جدول أطفالي, a parent opens a coming حصة and
-- reports that their child will miss it («تسجيل غياب»), with a reason. The session's
-- instructors and the فئة's category supervisors (مشرف الفئة) are notified; the attendance
-- sheet then starts that child as معذور with the reason shown, and staff can still change it.
-- The parent (or the child's other parent) can take the report back until the حصة starts.

create table if not exists public.child_absence_reports (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references public.sessions (id) on delete cascade,
  child_id uuid not null references public.children (id) on delete cascade,
  reported_by uuid not null references public.people (id) on delete cascade,
  reason text not null check (length(btrim(reason)) between 1 and 500),
  created_at timestamptz not null default now(),
  unique (session_id, child_id)
);
create index if not exists child_absence_reports_child on public.child_absence_reports (child_id);

alter table public.child_absence_reports enable row level security;

-- Read: the child's parents, the session group's instructors and supervisors, advisors.
drop policy if exists car_read on public.child_absence_reports;
create policy car_read on public.child_absence_reports for select using (
  parent_of_child(child_id)
  or has_role('advisor')
  or exists (select 1 from sessions s where s.id = session_id
             and (teaches_group(s.group_id) or supervises_group(s.group_id))));

-- Write: a parent of the child, for a session of the child's current فئة that is not
-- cancelled and has not started yet.
drop policy if exists car_insert on public.child_absence_reports;
create policy car_insert on public.child_absence_reports for insert with check (
  reported_by = auth.uid()
  and parent_of_child(child_id)
  and exists (select 1 from sessions s
              join child_groups cg on cg.group_id = s.group_id and cg.child_id = child_absence_reports.child_id
                                  and cg.to_date is null
              where s.id = session_id and s.status <> 'cancelled'
                and (s.session_date + s.start_time) at time zone 'Africa/Casablanca' > now()));

-- Taking it back: a parent of the child, before the session starts.
drop policy if exists car_delete on public.child_absence_reports;
create policy car_delete on public.child_absence_reports for delete using (
  parent_of_child(child_id)
  and exists (select 1 from sessions s where s.id = session_id
              and (s.session_date + s.start_time) at time zone 'Africa/Casablanca' > now()));

grant select, insert, delete on public.child_absence_reports to authenticated;

-- Notifications ---------------------------------------------------------------------------

alter table public.notification_outbox drop constraint if exists notification_outbox_kind_check;
alter table public.notification_outbox add constraint notification_outbox_kind_check check (kind in (
  'session_created', 'session_changed', 'session_cancelled', 'absence_alert',
  'child_message', 'child_message_reply', 'child_message_like', 'instructor_absence',
  'session_reminder', 'activity_created', 'activity_changed', 'activity_cancelled', 'activity_reminder',
  'child_absence', 'homework_assigned'));

-- One notification to each instructor who runs the session (those picked for it, or the
-- group's instructors when nobody was picked) and to each supervisor of its فئة.
create or replace function public.notify_child_absence() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into notification_outbox (recipient_id, kind, title, body, data)
  select distinct r.person_id, 'child_absence',
         'غياب ' || coalesce(nullif(split_part(btrim(c.full_name), ' ', 1), ''), 'طفل') || ' عن حصة ' || g.name,
         s.title || ' · ' || to_char(s.session_date, 'DD/MM') || ' ' || to_char(s.start_time, 'HH24:MI')
           || ' · ' || left(new.reason, 140),
         jsonb_build_object('session_id', s.id, 'group_id', s.group_id, 'child_id', new.child_id)
  from sessions s
  join groups g on g.id = s.group_id
  join children c on c.id = new.child_id,
  lateral (
    select si.person_id from session_instructors si where si.session_id = s.id
    union
    select gi.person_id from group_instructors gi
    where gi.group_id = s.group_id and not exists (select 1 from session_instructors x where x.session_id = s.id)
    union
    select gs.person_id from group_supervisors gs where gs.group_id = s.group_id
  ) r
  where s.id = new.session_id and r.person_id <> new.reported_by;
  return new;
end $$;
drop trigger if exists child_absence_reports_notify on public.child_absence_reports;
create trigger child_absence_reports_notify after insert on public.child_absence_reports
  for each row execute function public.notify_child_absence();

revoke execute on function public.notify_child_absence() from public, anon, authenticated;
