-- Checks who may report a child's absence, who sees it and who is notified. Run on a
-- throwaway Postgres 16 after local_stubs.sql and every migration in order. Never on the live database.
\set ON_ERROR_STOP 1
-- Parents A (kid1), B (kid2), instructor I and supervisor S of G1, instructor J of G2, advisor G.
insert into auth.users(id) values
 ('00000000-0000-0000-0000-00000000000a'),('00000000-0000-0000-0000-00000000000b'),
 ('00000000-0000-0000-0000-000000000001'),('00000000-0000-0000-0000-000000000002'),
 ('00000000-0000-0000-0000-000000000005'),('00000000-0000-0000-0000-000000000009');
insert into people(id, full_name, phone) values
 ('00000000-0000-0000-0000-00000000000a','Parent A','+212600000001'),
 ('00000000-0000-0000-0000-00000000000b','Parent B','+212600000002'),
 ('00000000-0000-0000-0000-000000000001','Instructor I','+212600000011'),
 ('00000000-0000-0000-0000-000000000002','Instructor J','+212600000012'),
 ('00000000-0000-0000-0000-000000000005','Supervisor S','+212600000005'),
 ('00000000-0000-0000-0000-000000000009','General G','+212600000009');
insert into person_roles values ('00000000-0000-0000-0000-00000000000a','parent'),('00000000-0000-0000-0000-00000000000b','parent'),
 ('00000000-0000-0000-0000-000000000001','instructor'),('00000000-0000-0000-0000-000000000002','instructor'),
 ('00000000-0000-0000-0000-000000000005','instructor'),('00000000-0000-0000-0000-000000000009','advisor');
insert into groups(id, name, logo_letter) values ('10000000-0000-0000-0000-000000000001','G1','ا'),('10000000-0000-0000-0000-000000000002','G2','ب');
insert into group_instructors(group_id, person_id) values ('10000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000001'),
 ('10000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000002');
insert into group_supervisors(group_id, person_id) values ('10000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000005');
insert into children(id, full_name) values ('20000000-0000-0000-0000-000000000001','آدم بنعلي'),('20000000-0000-0000-0000-000000000002','Kid Two');
insert into child_groups(child_id, group_id) values ('20000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001'),
 ('20000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000001');
insert into child_parents(child_id, parent_id) values ('20000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-00000000000a'),
 ('20000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-00000000000b');
-- Sessions: s1 G1 tomorrow, s2 G1 yesterday, s3 G2 tomorrow, s4 G1 tomorrow cancelled.
insert into sessions(id, group_id, title, session_date, start_time, end_time, floor, status) values
 ('40000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','حفظ', current_date + 1, '10:00', '11:00', 1, 'planned'),
 ('40000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000001','حفظ', current_date - 1, '10:00', '11:00', 1, 'planned'),
 ('40000000-0000-0000-0000-000000000003','10000000-0000-0000-0000-000000000002','حفظ', current_date + 1, '10:00', '11:00', 1, 'planned'),
 ('40000000-0000-0000-0000-000000000004','10000000-0000-0000-0000-000000000001','حفظ', current_date + 1, '12:00', '13:00', 1, 'cancelled');
delete from notification_outbox;

set role authenticated;
set test.uid = '00000000-0000-0000-0000-00000000000a';
insert into child_absence_reports(session_id, child_id, reported_by, reason)
  values ('40000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-00000000000a','موعد طبي');
\echo '--- A reported kid1 for s1: OK'

create or replace function pg_temp.must_fail(q text) returns text language plpgsql as $$
begin execute q; return 'ALLOWED (wrong)'; exception when others then return 'refused'; end $$;
select 'A for kid2 (not their child)', pg_temp.must_fail($q$insert into child_absence_reports(session_id, child_id, reported_by, reason)
  values ('40000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-00000000000a','x')$q$);
select 'A for past session', pg_temp.must_fail($q$insert into child_absence_reports(session_id, child_id, reported_by, reason)
  values ('40000000-0000-0000-0000-000000000002','20000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-00000000000a','x')$q$);
select 'A for other group session', pg_temp.must_fail($q$insert into child_absence_reports(session_id, child_id, reported_by, reason)
  values ('40000000-0000-0000-0000-000000000003','20000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-00000000000a','x')$q$);
select 'A for cancelled session', pg_temp.must_fail($q$insert into child_absence_reports(session_id, child_id, reported_by, reason)
  values ('40000000-0000-0000-0000-000000000004','20000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-00000000000a','x')$q$);
select 'A with blank reason', pg_temp.must_fail($q$insert into child_absence_reports(session_id, child_id, reported_by, reason)
  values ('40000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-00000000000a','  ')$q$);
select 'A as someone else', pg_temp.must_fail($q$insert into child_absence_reports(session_id, child_id, reported_by, reason)
  values ('40000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-00000000000b','x')$q$);
set test.uid = '00000000-0000-0000-0000-000000000001';
select 'Instructor I reports', pg_temp.must_fail($q$insert into child_absence_reports(session_id, child_id, reported_by, reason)
  values ('40000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000001','x')$q$);

\echo '--- who sees the report (expect A 1, B 0, I 1, J 0, S 1, G 1)'
set test.uid = '00000000-0000-0000-0000-00000000000a'; select 'A sees', count(*) from child_absence_reports;
set test.uid = '00000000-0000-0000-0000-00000000000b'; select 'B sees', count(*) from child_absence_reports;
set test.uid = '00000000-0000-0000-0000-000000000001'; select 'I sees', count(*) from child_absence_reports;
set test.uid = '00000000-0000-0000-0000-000000000002'; select 'J sees', count(*) from child_absence_reports;
set test.uid = '00000000-0000-0000-0000-000000000005'; select 'S sees', count(*) from child_absence_reports;
set test.uid = '00000000-0000-0000-0000-000000000009'; select 'G sees', count(*) from child_absence_reports;

\echo '--- I and S may not delete it; B neither'
set test.uid = '00000000-0000-0000-0000-000000000001'; delete from child_absence_reports; 
set test.uid = '00000000-0000-0000-0000-00000000000b'; delete from child_absence_reports;
reset role;
select 'still there', count(*) from child_absence_reports;
\echo '--- notified (expect Instructor I and Supervisor S, not A)'
select p.full_name, n.kind, n.title, n.body from notification_outbox n join people p on p.id = n.recipient_id order by 1;

set role authenticated;
set test.uid = '00000000-0000-0000-0000-00000000000a'; delete from child_absence_reports;
reset role;
select 'after A takes it back', count(*) from child_absence_reports;
