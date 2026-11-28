-- Checks who is notified of what, for every role (20261204000000_role_notifications.sql).
-- Run on a throwaway Postgres 16 after local_stubs.sql and every migration in order. Never
-- on the live database. Each step prints the notifications it queued: name, kind, title.
\set ON_ERROR_STOP 1
-- People: supervisor S (G1), instructors I and J (G1), parent A (kid1 in G1), advisor G.
insert into auth.users(id) values
 ('00000000-0000-0000-0000-00000000000a'),('00000000-0000-0000-0000-000000000005'),
 ('00000000-0000-0000-0000-000000000007'),('00000000-0000-0000-0000-000000000008'),('00000000-0000-0000-0000-000000000009');
insert into people(id, full_name, phone) values
 ('00000000-0000-0000-0000-00000000000a','A parent','+212600000001'),
 ('00000000-0000-0000-0000-000000000005','S supervisor','+212600000005'),
 ('00000000-0000-0000-0000-000000000007','I instructor','+212600000007'),
 ('00000000-0000-0000-0000-000000000008','J instructor','+212600000008'),
 ('00000000-0000-0000-0000-000000000009','G advisor','+212600000009');
insert into person_roles values ('00000000-0000-0000-0000-00000000000a','parent'),
 ('00000000-0000-0000-0000-000000000005','instructor'),('00000000-0000-0000-0000-000000000007','instructor'),
 ('00000000-0000-0000-0000-000000000008','instructor'),('00000000-0000-0000-0000-000000000009','advisor');
insert into groups(id, name, logo_letter) values ('10000000-0000-0000-0000-000000000001','G1','ا');
insert into group_instructors(group_id, person_id) values
 ('10000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000007'),
 ('10000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000008');
insert into group_supervisors(group_id, person_id) values ('10000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000005');
insert into children(id, full_name) values ('20000000-0000-0000-0000-000000000001','Kid One');
insert into child_groups(child_id, group_id) values ('20000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001');
insert into child_parents(child_id, parent_id) values ('20000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-00000000000a');

create view pending as
  select split_part(p.full_name, ' ', 1) as who, o.kind, o.title, o.body
  from notification_outbox o join people p on p.id = o.recipient_id
  where o.read_at is null order by 1, 2, 3;
grant select on pending to authenticated;
-- Prints what was queued since the last step, then forgets it.
create function step() returns setof pending language sql security definer as $$
  with x as (select * from pending), d as (update notification_outbox set read_at = now() where read_at is null)
  select * from x
$$;

set role authenticated;

\echo '=== S plans a حصة, picking I (expect A session_created, I session_assigned, G session_created; not S, not J)'
set test.uid = '00000000-0000-0000-0000-000000000005';
select create_sessions('10000000-0000-0000-0000-000000000001',
  jsonb_build_object('title','حصة 1','start_time','10:00','end_time','11:30','floor',0,'place','samae'),
  array[current_date + 3], null, '[]', array['00000000-0000-0000-0000-000000000007']::uuid[]) as s1 \gset
select * from step();

\echo '=== S swaps I for J (expect J session_assigned, I session_unassigned, G session_changed)'
select update_sessions(:'s1', jsonb_build_object('title','حصة 1','session_date', current_date + 3,
  'start_time','10:00','end_time','11:30','floor',0,'place','samae'), false, array['00000000-0000-0000-0000-000000000008']::uuid[]);
select * from step();

\echo '=== G (advisor) plans a series for the whole فئة (expect A, I, J, S session_created; not G)'
set test.uid = '00000000-0000-0000-0000-000000000009';
select create_sessions('10000000-0000-0000-0000-000000000001',
  jsonb_build_object('title','سلسلة','start_time','15:00','end_time','16:00','floor',0,'place','samae'),
  array[current_date + 4, current_date + 11], array[1]::smallint[], '[]', null) as s2 \gset
select * from step();

\echo '=== J writes an observation on s1 (expect I, S, G session_observation; not J)'
set test.uid = '00000000-0000-0000-0000-000000000008';
insert into session_observations(session_id, author_id, body) values (:'s1', '00000000-0000-0000-0000-000000000008', 'الأطفال متحمسون');
select * from step();
\echo '--- I (not picked for s1) can read it now (expect 1)'
set test.uid = '00000000-0000-0000-0000-000000000007';
select count(*) from session_observations;

\echo '=== I writes a note on Kid One (expect J, S, G child_note; never A)'
insert into notes(child_id, author_id, body) values ('20000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000007','يحتاج متابعة');
select * from step();

\echo '=== S writes to the parents, A replies (expect A child_message; then S, G child_message_reply)'
set test.uid = '00000000-0000-0000-0000-000000000005';
insert into child_messages(id, child_id, author_id, body) values
 ('30000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000005','أحسن اليوم');
select * from step();
set test.uid = '00000000-0000-0000-0000-00000000000a';
insert into child_message_replies(message_id, author_id, body) values
 ('30000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-00000000000a','شكراً');
select * from step();

\echo '=== A reports Kid One absent from s1, then takes it back (expect J, S, G child_absence; then child_absence_cancelled)'
insert into child_absence_reports(id, session_id, child_id, reported_by, reason) values
 ('50000000-0000-0000-0000-000000000001', :'s1','20000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-00000000000a','مريض');
select * from step();
delete from child_absence_reports where id = '50000000-0000-0000-0000-000000000001';
select * from step();

\echo '=== J reports an absence from s1, then takes it back (expect S, G instructor_absence; then instructor_absence_cancelled)'
set test.uid = '00000000-0000-0000-0000-000000000008';
insert into instructor_absences(id, session_id, person_id, reason) values
 ('60000000-0000-0000-0000-000000000001', :'s1','00000000-0000-0000-0000-000000000008','سفر');
select * from step();
delete from instructor_absences where id = '60000000-0000-0000-0000-000000000001';
select * from step();

\echo '=== J marks Kid One absent (expect A child_absent; nothing when saved again)'
reset role;
update sessions set session_date = current_date, start_time = '00:00', end_time = '00:01' where id = :'s1';
update notification_outbox set read_at = now() where read_at is null;
set role authenticated;
insert into attendance(id, session_id, child_id, status, recorded_by, recorded_at) values
 (gen_random_uuid(), :'s1','20000000-0000-0000-0000-000000000001','absent','00000000-0000-0000-0000-000000000008', now());
select * from step();
update attendance set recorded_at = now() where session_id = :'s1';
select * from step();

\echo '=== S plans, edits (title only) and deletes an activity (expect G hears of each; parents/staff of create and delete)'
set test.uid = '00000000-0000-0000-0000-000000000005';
select create_activity(jsonb_build_object('kind','outing','title','خرجة','place','الغابة',
  'start_date', current_date + 20, 'start_time','09:00','end_date', current_date + 20, 'end_time','17:00'),
  array['10000000-0000-0000-0000-000000000001']::uuid[]) as a1 \gset
select * from step();
select update_activity(:'a1', jsonb_build_object('kind','outing','title','خرجة الربيع','place','الغابة',
  'start_date', current_date + 20, 'start_time','09:00','end_date', current_date + 20, 'end_time','17:00'),
  array['10000000-0000-0000-0000-000000000001']::uuid[]);
select * from step();
select delete_activity(:'a1');
select * from step();

\echo '=== G cancels s1 (expect J session_cancelled, S session_cancelled, not G)'
set test.uid = '00000000-0000-0000-0000-000000000009';
reset role;
update sessions set session_date = current_date + 3 where id = :'s1';
set role authenticated;
select cancel_sessions(:'s1', 'مطر', false);
select * from step();
set test.uid = '00000000-0000-0000-0000-000000000005';

\echo '=== S deletes the coming series (expect one session_cancelled each for A, I, J, G; not S)'
delete from sessions where id = :'s2' or series_id = (select series_id from sessions where id = :'s2');
select * from step();

\echo '=== S gives homework due tomorrow, edits its due date, G gives one too (expect A homework_assigned, homework_changed; S homework_assigned from G)'
select create_homework(jsonb_build_object('group_id','10000000-0000-0000-0000-000000000001','template','wird',
  'fields', jsonb_build_object('amount','ثمن'), 'due_date', current_date + 1)) as h1 \gset
select * from step();
select update_homework(:'h1', jsonb_build_object('template','wird','fields', jsonb_build_object('amount','ربع'),
  'due_date', current_date + 1));
select * from step();
set test.uid = '00000000-0000-0000-0000-000000000009';
select create_homework(jsonb_build_object('group_id','10000000-0000-0000-0000-000000000001','template','wird',
  'fields', jsonb_build_object('amount','حزب'), 'due_date', current_date + 5)) as h2 \gset
select * from step();

\echo '=== Evening reminder (expect 0 at noon, 1 at 18:00, 0 again; A homework_reminder for h1 only)'
reset role;
update homework set created_at = now() - interval '2 days' where id = :'h1';
select queue_homework_reminders(((current_date + time '12:00') at time zone 'Africa/Casablanca')) as at_noon;
select queue_homework_reminders(((current_date + time '18:00') at time zone 'Africa/Casablanca')) as at_six;
select queue_homework_reminders(((current_date + time '18:15') at time zone 'Africa/Casablanca')) as again;
select * from step();

\echo '=== S deletes h2 (expect A homework_cancelled)'
set role authenticated;
set test.uid = '00000000-0000-0000-0000-000000000005';
delete from homework where id = :'h2';
select * from step();
