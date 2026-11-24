-- Request from the academy (2026-11-24): an instructor reports that they will miss a
-- session, with a reason, and the category supervisor (مشرف الفئة) of its فئة is notified.
-- The supervisor sees each instructor's absences in their record.

create table if not exists public.instructor_absences (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references public.sessions (id) on delete cascade,
  person_id uuid not null references public.people (id) on delete cascade,
  reason text not null check (length(btrim(reason)) between 1 and 500),
  created_at timestamptz not null default now(),
  unique (session_id, person_id)
);
create index if not exists instructor_absences_person on public.instructor_absences (person_id);

alter table public.instructor_absences enable row level security;

-- Read: the instructor, the session's other instructors, the فئة's supervisors, advisors.
drop policy if exists ia_read on public.instructor_absences;
create policy ia_read on public.instructor_absences for select using (
  person_id = auth.uid()
  or has_role('advisor')
  or exists (select 1 from sessions s where s.id = session_id
             and (teaches_group(s.group_id) or supervises_group(s.group_id))));

-- Write: an instructor, for a session they run that has not ended yet.
drop policy if exists ia_insert on public.instructor_absences;
create policy ia_insert on public.instructor_absences for insert with check (
  person_id = auth.uid()
  and runs_session(session_id)
  and exists (select 1 from sessions s where s.id = session_id and s.status <> 'cancelled'
              and (s.session_date + s.end_time) at time zone 'Africa/Casablanca' > now()));

-- Taking it back: the instructor, before the session ends.
drop policy if exists ia_delete on public.instructor_absences;
create policy ia_delete on public.instructor_absences for delete using (
  person_id = auth.uid()
  and exists (select 1 from sessions s where s.id = session_id
              and (s.session_date + s.end_time) at time zone 'Africa/Casablanca' > now()));

grant select, insert, delete on public.instructor_absences to authenticated;

-- Notifications ---------------------------------------------------------------------------

alter table public.notification_outbox drop constraint if exists notification_outbox_kind_check;
alter table public.notification_outbox add constraint notification_outbox_kind_check check (kind in (
  'session_created', 'session_changed', 'session_cancelled', 'absence_alert',
  'child_message', 'child_message_reply', 'child_message_like', 'instructor_absence'));

-- A notice of absence: one notification to each supervisor of the session's فئة.
create or replace function public.notify_instructor_absence() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into notification_outbox (recipient_id, kind, title, body, data)
  select gs.person_id, 'instructor_absence',
         'غياب ' || coalesce(split_part(p.full_name, ' ', 1), 'مؤطر') || ' عن حصة ' || g.name,
         s.title || ' · ' || to_char(s.session_date, 'DD/MM') || ' ' || to_char(s.start_time, 'HH24:MI')
           || ' · ' || left(new.reason, 140),
         jsonb_build_object('session_id', s.id, 'group_id', s.group_id, 'person_id', new.person_id)
  from sessions s
  join groups g on g.id = s.group_id
  join group_supervisors gs on gs.group_id = s.group_id
  left join people p on p.id = new.person_id
  where s.id = new.session_id and gs.person_id <> new.person_id;
  return new;
end $$;
drop trigger if exists instructor_absences_notify on public.instructor_absences;
create trigger instructor_absences_notify after insert on public.instructor_absences
  for each row execute function public.notify_instructor_absence();

revoke execute on function public.notify_instructor_absence() from public, anon, authenticated;
