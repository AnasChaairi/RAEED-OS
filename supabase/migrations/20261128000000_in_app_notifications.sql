-- Requests from the academy (2026-11-25):
-- 1. A parent's reply to an observation did not reach the مشرف الفئة. The reply now goes
--    to the observation's author and to every current supervisor of the child's فئة, and
--    every notification is also kept in the app (the bell), so it is seen even when the
--    phone's push did not arrive (another account signed in on the phone, push off...).
-- 2. The مشرف عام (role advisor) gets notifications: an instructor reports an absence, a
--    child is absent twice in a row, or someone else cancels a session.
-- 3. A bell with the unread count at the top of the app, for every role: everyone reads
--    their own rows of notification_outbox and marks them read.

-- In-app list ---------------------------------------------------------------------------------

alter table public.notification_outbox add column if not exists read_at timestamptz;
create index if not exists notification_outbox_recipient
  on public.notification_outbox (recipient_id, created_at desc);

drop policy if exists outbox_own_read on public.notification_outbox;
create policy outbox_own_read on public.notification_outbox for select using (recipient_id = auth.uid());
grant select on public.notification_outbox to authenticated;

-- Marks the caller's notifications read: [p_ids], or all of them when null.
create or replace function public.mark_notifications_read(p_ids uuid[] default null)
returns void
language sql
security definer
set search_path to 'public'
as $function$
  update notification_outbox set read_at = now()
  where recipient_id = auth.uid() and read_at is null and (p_ids is null or id = any(p_ids))
$function$;
revoke execute on function public.mark_notifications_read(uuid[]) from public, anon;
grant execute on function public.mark_notifications_read(uuid[]) to authenticated;

-- General supervisors ------------------------------------------------------------------------

-- One notification to each advisor, except whoever caused it.
create or replace function public.queue_advisor_notification(p_kind text, p_title text, p_body text, p_data jsonb,
                                                             p_except uuid default null)
returns void
language sql
security definer
set search_path to 'public'
as $function$
  insert into notification_outbox (recipient_id, kind, title, body, data)
  select pr.person_id, p_kind, p_title, p_body, coalesce(p_data, '{}')
  from person_roles pr
  where pr.role = 'advisor'
    and pr.person_id is distinct from coalesce(p_except, auth.uid())
$function$;
revoke all on function public.queue_advisor_notification(text, text, text, jsonb, uuid) from public, anon, authenticated;

-- A parent's reply (or the supervisor's answer): everyone else in the conversation, plus
-- the current supervisors of the child's فئة.
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
       ) r
  where c.id = m.child_id and r.id is not null and r.id <> new.author_id;
  return new;
end $$;
revoke execute on function public.notify_child_message_reply() from public, anon, authenticated;

-- An instructor's notice of absence: the فئة's supervisors, and the advisors.
create or replace function public.notify_instructor_absence() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  t text;
  b text;
  d jsonb;
begin
  select 'غياب ' || coalesce(split_part(p.full_name, ' ', 1), 'مؤطر') || ' عن حصة ' || g.name,
         s.title || ' · ' || to_char(s.session_date, 'DD/MM') || ' ' || to_char(s.start_time, 'HH24:MI')
           || ' · ' || left(new.reason, 140),
         jsonb_build_object('session_id', s.id, 'group_id', s.group_id, 'person_id', new.person_id)
  into t, b, d
  from sessions s
  join groups g on g.id = s.group_id
  left join people p on p.id = new.person_id
  where s.id = new.session_id;
  if t is null then
    return new;
  end if;
  insert into notification_outbox (recipient_id, kind, title, body, data)
  select gs.person_id, 'instructor_absence', t, b, d
  from sessions s join group_supervisors gs on gs.group_id = s.group_id
  where s.id = new.session_id and gs.person_id <> new.person_id;
  perform queue_advisor_notification('instructor_absence', t, b, d, new.person_id);
  return new;
end $$;
revoke execute on function public.notify_instructor_absence() from public, anon, authenticated;

-- A child absent twice in a row: the group's instructors and supervisors, and the advisors.
create or replace function public.notify_absence_alert() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  t text;
  b text;
  d jsonb;
begin
  select 'غياب مرتين متتاليتين · ' || split_part(c.full_name, ' ', 1), g.name || ' · تواصل مع ولي الأمر',
         jsonb_build_object('alert_id', new.id, 'child_id', new.child_id)
  into t, b, d
  from children c join groups g on g.id = new.group_id
  where c.id = new.child_id;
  if t is null then
    return new;
  end if;
  insert into notification_outbox (recipient_id, kind, title, body, data)
  select distinct r.person_id, 'absence_alert', t, b, d
  from (
    select gi.person_id from group_instructors gi where gi.group_id = new.group_id
    union
    select gs.person_id from group_supervisors gs where gs.group_id = new.group_id
  ) r;
  -- Advisors who also teach or supervise this group already have it.
  insert into notification_outbox (recipient_id, kind, title, body, data)
  select pr.person_id, 'absence_alert', t, b, d
  from person_roles pr
  where pr.role = 'advisor'
    and not exists (select 1 from group_instructors gi where gi.group_id = new.group_id and gi.person_id = pr.person_id)
    and not exists (select 1 from group_supervisors gs where gs.group_id = new.group_id and gs.person_id = pr.person_id);
  return new;
end $$;
revoke execute on function public.notify_absence_alert() from public, anon, authenticated;

-- Cancelling: unchanged, except that the advisors hear about it when someone else (a
-- مشرف الفئة) cancels.
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
    perform queue_advisor_notification('session_cancelled', 'حصص ملغاة · ' || gname,
      s.title || ' · ابتداءً من ' || to_char(s.session_date, 'DD/MM')
        || coalesce(' · ' || nullif(btrim(p_reason), ''), ''),
      jsonb_build_object('session_id', s.id));
    perform set_config('raeed.quiet', 'off', true);
  else
    update sessions set status = 'cancelled', cancel_reason = p_reason, updated_at = now() where id = s.id;
    perform queue_staff_notification(s.id, 'session_cancelled', 'حصة ملغاة · ' || gname,
      s.title || ' · ' || to_char(s.session_date, 'DD/MM') || ' · ' || to_char(s.start_time, 'HH24:MI'));
    perform queue_advisor_notification('session_cancelled', 'حصة ملغاة · ' || gname,
      s.title || ' · ' || to_char(s.session_date, 'DD/MM') || ' · ' || to_char(s.start_time, 'HH24:MI')
        || coalesce(' · ' || nullif(btrim(p_reason), ''), ''),
      jsonb_build_object('session_id', s.id));
  end if;
end $function$;
