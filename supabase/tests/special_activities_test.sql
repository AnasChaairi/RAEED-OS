-- Checks who plans and sees أنشطة نوعية, which حصص they replace, attendance on them and
-- who is notified. Run on a throwaway Postgres 16 after local_stubs.sql and every
-- migration in order. Never on the live database.
\set ON_ERROR_STOP 1
-- People: supervisor S (of G1), instructor I (G1), parents A (kid1 in G1), C (kid3 in G2), advisor G.
insert into auth.users(id) values
 ('00000000-0000-0000-0000-00000000000a'),('00000000-0000-0000-0000-00000000000c'),
 ('00000000-0000-0000-0000-000000000005'),('00000000-0000-0000-0000-000000000007'),('00000000-0000-0000-0000-000000000009');
insert into people(id, full_name, phone) values
 ('00000000-0000-0000-0000-00000000000a','Parent A','+212600000001'),
 ('00000000-0000-0000-0000-00000000000c','Parent C','+212600000003'),
 ('00000000-0000-0000-0000-000000000005','Supervisor S','+212600000005'),
 ('00000000-0000-0000-0000-000000000007','Instructor I','+212600000007'),
 ('00000000-0000-0000-0000-000000000009','General G','+212600000009');
insert into person_roles values ('00000000-0000-0000-0000-00000000000a','parent'),('00000000-0000-0000-0000-00000000000c','parent'),
 ('00000000-0000-0000-0000-000000000005','instructor'),('00000000-0000-0000-0000-000000000007','instructor'),
 ('00000000-0000-0000-0000-000000000009','advisor');
insert into groups(id, name, logo_letter) values ('10000000-0000-0000-0000-000000000001','G1','ا'),('10000000-0000-0000-0000-000000000002','G2','ب');
insert into group_instructors(group_id, person_id) values ('10000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000007');
insert into children(id, full_name) values ('20000000-0000-0000-0000-000000000001','Kid One'),('20000000-0000-0000-0000-000000000003','Kid Three');
insert into child_groups(child_id, group_id) values ('20000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001'),
 ('20000000-0000-0000-0000-000000000003','10000000-0000-0000-0000-000000000002');
insert into child_parents(child_id, parent_id) values ('20000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-00000000000a'),
 ('20000000-0000-0000-0000-000000000003','00000000-0000-0000-0000-00000000000c');
insert into group_supervisors(group_id, person_id) values ('10000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000005');
-- G1 sessions: one on the camp's second day (replaced), one the week after (kept).
insert into sessions(id, group_id, title, session_date, start_time, end_time, floor, remind) values
 ('40000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','حصة السبت', current_date + 11, '10:00','11:30', 0, true),
 ('40000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000001','حصة بعدها', current_date + 18, '10:00','11:30', 0, true);

set role authenticated;
\echo '--- S plans a camp for G1 (expect ok)'
set test.uid = '00000000-0000-0000-0000-000000000005';
select create_activity(jsonb_build_object('kind','camp','title','مخيم الربيع','place','غابة المعمورة',
  'start_date', current_date + 10, 'start_time','09:00','end_date', current_date + 12, 'end_time','17:00'),
  array['10000000-0000-0000-0000-000000000001']::uuid[]) is not null as s_created;
\echo '--- S plans for G1 and G2 (expect refused)'
do $$ begin perform create_activity(jsonb_build_object('kind','outing','title','x','place','y',
  'start_date', current_date + 3, 'start_time','09:00','end_date', current_date + 3, 'end_time','12:00'),
  array['10000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000002']::uuid[]);
  raise notice 'S OTHER GROUP ALLOWED (bad)'; exception when others then raise notice 'S other group refused: %', sqlerrm; end $$;
\echo '--- custom kind without a name (expect refused)'
do $$ begin perform create_activity(jsonb_build_object('kind','custom','title','x','place','y',
  'start_date', current_date + 3, 'start_time','09:00','end_date', current_date + 3, 'end_time','12:00'),
  array['10000000-0000-0000-0000-000000000001']::uuid[]);
  raise notice 'CUSTOM WITHOUT LABEL ALLOWED (bad)'; exception when others then raise notice 'custom without label refused: %', sqlerrm; end $$;
\echo '--- G plans an outing tomorrow morning for G2 (expect ok, already reminded)'
set test.uid = '00000000-0000-0000-0000-000000000009';
select create_activity(jsonb_build_object('kind','custom','custom_label','زيارة','title','زيارة المتحف','place','الرباط',
  'start_date', current_date + 1, 'start_time','09:00','end_date', current_date + 1, 'end_time','12:00'),
  array['10000000-0000-0000-0000-000000000002']::uuid[]) is not null as g_created;
\echo '--- who sees which activity (expect A: camp, C: زيارة, I: camp, S: camp, G: both)'
set test.uid = '00000000-0000-0000-0000-00000000000a'; select 'A sees', string_agg(title, ', ') from special_activities;
set test.uid = '00000000-0000-0000-0000-00000000000c'; select 'C sees', string_agg(title, ', ') from special_activities;
set test.uid = '00000000-0000-0000-0000-000000000007'; select 'I sees', string_agg(title, ', ') from special_activities;
set test.uid = '00000000-0000-0000-0000-000000000005'; select 'S sees', string_agg(title, ', ') from special_activities;
set test.uid = '00000000-0000-0000-0000-000000000009'; select 'G sees', string_agg(title, ', ' order by title) from special_activities;
\echo '--- direct writes are refused (expect 0 rows changed)'
set test.uid = '00000000-0000-0000-0000-000000000005';
update special_activities set title = 'hack'; select 'S direct update', count(*) from special_activities where title = 'hack';
\echo '--- the camp replaces the G1 session on its second day, not the one after'
select title, session_activity(id) is not null as replaced from sessions order by session_date;
\echo '--- S edits the زيارة of G2 (expect refused)'
do $$ declare v uuid; begin select id into v from special_activities where title = 'زيارة المتحف';
  perform cancel_activity(v, 'x'); raise notice 'S CANCEL OTHER ALLOWED (bad)'; exception when others then raise notice 'S cancel other refused: %', sqlerrm; end $$;
\echo '--- attendance on the camp: I for kid1 (ok), I for kid3 (refused)'
set test.uid = '00000000-0000-0000-0000-000000000007';
insert into activity_attendance(activity_id, child_id, status, recorded_by)
select id, '20000000-0000-0000-0000-000000000001', 'present', auth.uid() from special_activities where title = 'مخيم الربيع';
do $$ begin insert into activity_attendance(activity_id, child_id, status, recorded_by)
  select id, '20000000-0000-0000-0000-000000000003', 'present', auth.uid() from special_activities where title = 'مخيم الربيع';
  raise notice 'I OTHER CHILD ALLOWED (bad)'; exception when others then raise notice 'I other child refused: %', sqlerrm; end $$;
set test.uid = '00000000-0000-0000-0000-00000000000a'; select 'A reads attendance', count(*) from activity_attendance;
set test.uid = '00000000-0000-0000-0000-000000000005'; select 'S reads attendance', count(*) from activity_attendance;
\echo '--- S moves the camp a week later: the session after is replaced instead'
select update_activity(id, jsonb_build_object('kind','camp','title','مخيم الربيع','place','غابة المعمورة',
  'start_date', current_date + 17, 'start_time','09:00','end_date', current_date + 19, 'end_time','17:00'),
  array['10000000-0000-0000-0000-000000000001']::uuid[]) from special_activities where title = 'مخيم الربيع';
select title, session_activity(id) is not null as replaced from sessions order by session_date;
\echo '--- S cancels it: no session is replaced'
select cancel_activity(id, 'الطقس') from special_activities where title = 'مخيم الربيع';
select title, session_activity(id) is not null as replaced from sessions order by session_date;
reset role;
\echo '--- reminders: nothing is due (the زيارة was reminded at creation)'
select queue_activity_reminders() as reminded;
\echo '--- the same زيارة not yet reminded: one reminder to Parent C'
update special_activities set reminded_at = null where title = 'زيارة المتحف';
select queue_activity_reminders() as reminded;
\echo '--- all notifications (as server)'
select p.full_name, o.kind, o.title, o.body from notification_outbox o join people p on p.id = o.recipient_id order by o.created_at, p.full_name;
