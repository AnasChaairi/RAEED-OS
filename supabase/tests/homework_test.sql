-- Checks who assigns and sees الواجبات, who marks them and who is notified. Run on a
-- throwaway Postgres 16 after local_stubs.sql and every migration in order. Never on
-- the live database.
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
-- A second child in G1 with parent C as well, for homework given to some children only.
insert into children(id, full_name) values ('20000000-0000-0000-0000-000000000002','Kid Two');
insert into child_groups(child_id, group_id) values ('20000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000001');
insert into child_parents(child_id, parent_id) values ('20000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-00000000000c');
set role authenticated;
\echo '--- S gives G1 a review (whole فئة, expect ok)'
set test.uid = '00000000-0000-0000-0000-000000000005';
select create_homework(jsonb_build_object('group_id','10000000-0000-0000-0000-000000000001','template','review',
  'fields', jsonb_build_object('surah','الملك','from','1','to','15'), 'due_date', current_date + 7)) is not null as review;
\echo '--- S gives kid2 only a custom homework (expect ok)'
select create_homework(jsonb_build_object('group_id','10000000-0000-0000-0000-000000000001','template','custom',
  'fields', jsonb_build_object('title','حفظ دعاء','amount','دعاءان'), 'details','دعاء الصباح والمساء', 'due_date', current_date + 3),
  array['20000000-0000-0000-0000-000000000002']::uuid[]) is not null as custom;
\echo '--- custom without a title (expect refused)'
do $$ begin perform create_homework(jsonb_build_object('group_id','10000000-0000-0000-0000-000000000001','template','custom',
  'fields', '{}'::jsonb, 'due_date', current_date + 3)); raise notice 'CUSTOM WITHOUT TITLE ALLOWED (bad)';
  exception when others then raise notice 'custom without title refused: %', sqlerrm; end $$;
\echo '--- S gives G2 homework (expect refused)'
do $$ begin perform create_homework(jsonb_build_object('group_id','10000000-0000-0000-0000-000000000002','template','wird',
  'fields', jsonb_build_object('amount','ثمن'), 'due_date', current_date + 3)); raise notice 'S OTHER GROUP ALLOWED (bad)';
  exception when others then raise notice 'S other group refused: %', sqlerrm; end $$;
\echo '--- S picks kid3 (not in G1) (expect refused)'
do $$ begin perform create_homework(jsonb_build_object('group_id','10000000-0000-0000-0000-000000000001','template','wird',
  'fields', jsonb_build_object('amount','ثمن'), 'due_date', current_date + 3), array['20000000-0000-0000-0000-000000000003']::uuid[]);
  raise notice 'CHILD OUTSIDE GROUP ALLOWED (bad)'; exception when others then raise notice 'child outside refused: %', sqlerrm; end $$;
\echo '--- I (instructor) assigns (expect refused)'
set test.uid = '00000000-0000-0000-0000-000000000007';
do $$ begin perform create_homework(jsonb_build_object('group_id','10000000-0000-0000-0000-000000000001','template','wird',
  'fields', jsonb_build_object('amount','ثمن'), 'due_date', current_date + 3)); raise notice 'I ASSIGN ALLOWED (bad)';
  exception when others then raise notice 'instructor refused: %', sqlerrm; end $$;
\echo '--- who sees what (expect A: review; C: both; I: both; S: both; G: both)'
set test.uid = '00000000-0000-0000-0000-00000000000a'; select 'A sees', string_agg(template, ', ' order by template) from homework;
set test.uid = '00000000-0000-0000-0000-00000000000c'; select 'C sees', string_agg(template, ', ' order by template) from homework;
set test.uid = '00000000-0000-0000-0000-000000000007'; select 'I sees', string_agg(template, ', ' order by template) from homework;
set test.uid = '00000000-0000-0000-0000-000000000005'; select 'S sees', string_agg(template, ', ' order by template) from homework;
set test.uid = '00000000-0000-0000-0000-000000000009'; select 'G sees', string_agg(template, ', ' order by template) from homework;
\echo '--- notifications (expect A: 1 review, C: review + custom for kid2)'
reset role;
select recipient_id, kind, title, body from notification_outbox where kind = 'homework_assigned' order by recipient_id, title;
set role authenticated;
\echo '--- A marks the review done for kid1 (ok), for kid2 (refused), the custom for kid1 (refused)'
set test.uid = '00000000-0000-0000-0000-00000000000a';
select set_homework_status(id, '20000000-0000-0000-0000-000000000001', true) from homework where template = 'review';
do $$ begin perform set_homework_status((select id from homework where template = 'review'), '20000000-0000-0000-0000-000000000002', true);
  raise notice 'A MARKS OTHER CHILD (bad)'; exception when others then raise notice 'A other child refused: %', sqlerrm; end $$;
set test.uid = '00000000-0000-0000-0000-00000000000c';
do $$ begin perform set_homework_status((select id from homework where template = 'custom'), '20000000-0000-0000-0000-000000000003', true);
  raise notice 'C MARKS KID3 FOR G1 HOMEWORK (bad)'; exception when others then raise notice 'not for kid3 refused: %', sqlerrm; end $$;
select set_homework_status(id, '20000000-0000-0000-0000-000000000002', false) from homework where template = 'custom';
\echo '--- A reads only kid1 marks (expect 1); S reads all (expect 2)'
set test.uid = '00000000-0000-0000-0000-00000000000a'; select 'A reads marks', count(*) from homework_status;
set test.uid = '00000000-0000-0000-0000-000000000005'; select 'S reads marks', count(*) from homework_status;
\echo '--- S changes the custom to kid1 only: kid2 mark is dropped (expect 0 for kid2)'
select update_homework(id, jsonb_build_object('template','custom','fields', jsonb_build_object('title','حفظ دعاء'),
  'due_date', current_date + 4), array['20000000-0000-0000-0000-000000000001']::uuid[]) from homework where template = 'custom';
select 'kid2 marks', count(*) from homework_status where child_id = '20000000-0000-0000-0000-000000000002';
\echo '--- direct writes refused; A cannot delete; S deletes the review'
do $$ begin insert into homework(group_id, template, due_date) values ('10000000-0000-0000-0000-000000000001','wird', current_date);
  raise notice 'S DIRECT INSERT (bad)'; exception when others then raise notice 'direct insert refused: %', sqlerrm; end $$;
set test.uid = '00000000-0000-0000-0000-00000000000a'; delete from homework; select 'after A delete', count(*) from homework;
set test.uid = '00000000-0000-0000-0000-000000000005'; delete from homework where template = 'review'; select 'after S delete', count(*) from homework;
reset role;
select 'summary', homework_summary(h) from homework h;
