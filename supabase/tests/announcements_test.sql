-- Checks who receives and who can read إخبارات عامة (20261205000000_announcements.sql).
-- Run on a throwaway Postgres 16 after local_stubs.sql and every migration in order. Never
-- on the live database.
\set ON_ERROR_STOP 1
-- People: parent A, instructor I (teaches G1), supervisor-only S (instructor role, no فئة
-- taught), instructor+supervisor T (teaches and supervises G1), advisors G and H.
insert into auth.users(id) values
 ('00000000-0000-0000-0000-00000000000a'),('00000000-0000-0000-0000-000000000005'),
 ('00000000-0000-0000-0000-000000000007'),('00000000-0000-0000-0000-000000000006'),
 ('00000000-0000-0000-0000-000000000009'),('00000000-0000-0000-0000-000000000008');
insert into people(id, full_name, phone) values
 ('00000000-0000-0000-0000-00000000000a','A parent','+212600000001'),
 ('00000000-0000-0000-0000-000000000005','S supervisor','+212600000005'),
 ('00000000-0000-0000-0000-000000000006','T both','+212600000006'),
 ('00000000-0000-0000-0000-000000000007','I instructor','+212600000007'),
 ('00000000-0000-0000-0000-000000000008','H advisor','+212600000008'),
 ('00000000-0000-0000-0000-000000000009','G advisor','+212600000009');
insert into person_roles values ('00000000-0000-0000-0000-00000000000a','parent'),
 ('00000000-0000-0000-0000-000000000005','instructor'),('00000000-0000-0000-0000-000000000006','instructor'),
 ('00000000-0000-0000-0000-000000000007','instructor'),('00000000-0000-0000-0000-000000000008','advisor'),
 ('00000000-0000-0000-0000-000000000009','advisor');
insert into groups(id, name, logo_letter) values ('10000000-0000-0000-0000-000000000001','G1','ا');
insert into group_instructors(group_id, person_id) values
 ('10000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000007'),
 ('10000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000006');
insert into group_supervisors(group_id, person_id) values
 ('10000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000005'),
 ('10000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000006');

create function got(t text) returns text language sql security definer as $$
  select coalesce(string_agg(split_part(p.full_name, ' ', 1), ',' order by p.full_name), '-')
  from notification_outbox o join people p on p.id = o.recipient_id
  where o.kind = 'announcement' and o.title = 'إخبار عام: ' || t
$$;
create function check_eq(label text, actual text, expected text) returns text language plpgsql as $$
begin
  if actual is distinct from expected then raise exception '% : got %, expected %', label, actual, expected; end if;
  return 'ok  ' || label || ' = ' || actual;
end $$;

set role authenticated;
set test.uid = '00000000-0000-0000-0000-000000000009';
select check_eq('everyone count', publish_announcement('للجميع', 'نص', '{}')::text, '5');
select check_eq('everyone', got('للجميع'), 'A,H,I,S,T');
select check_eq('parents', publish_announcement('للأولياء', 'نص', array['parent'])::text, '1');
select check_eq('parents got', got('للأولياء'), 'A');
select publish_announcement('للمؤطرين', 'نص', array['instructor']);
select check_eq('instructors (not the supervisor-only S)', got('للمؤطرين'), 'I,T');
select publish_announcement('للمشرفين', 'نص', array['category_supervisor', 'advisor']);
select check_eq('supervisors + advisors', got('للمشرفين'), 'H,S,T');
select check_eq('two roles stored as picked',
  (select audience::text from announcements where title = 'للمشرفين'), '{category_supervisor,advisor}');
select publish_announcement('كل الأدوار', 'نص', array['parent', 'instructor', 'category_supervisor', 'advisor']);
select check_eq('all roles stored as everyone', (select audience::text from announcements where title = 'كل الأدوار'), '{}');

\echo '=== who reads what'
set test.uid = '00000000-0000-0000-0000-00000000000a';
select check_eq('parent reads', (select string_agg(title, ',' order by title) from announcements), 'كل الأدوار,للأولياء,للجميع');
set test.uid = '00000000-0000-0000-0000-000000000005';
select check_eq('supervisor reads', (select string_agg(title, ',' order by title) from announcements), 'كل الأدوار,للجميع,للمشرفين');
set test.uid = '00000000-0000-0000-0000-000000000008';
select check_eq('advisor reads all', (select count(*) from announcements)::text, '5');

\echo '=== only advisors publish or delete; nobody writes the table directly'
set test.uid = '00000000-0000-0000-0000-000000000007';
do $$ begin
  perform publish_announcement('x', 'y', '{}');
  raise exception 'instructor published';
exception when insufficient_privilege then raise notice 'ok  instructor cannot publish';
end $$;
do $$ begin
  insert into announcements(title, body) values ('x', 'y');
  raise exception 'direct insert allowed';
exception when insufficient_privilege then raise notice 'ok  no direct insert';
end $$;

set test.uid = '00000000-0000-0000-0000-000000000009';
select delete_announcement((select id from announcements where title = 'للأولياء'));
select check_eq('deleted from bells', got('للأولياء'), '-');
select check_eq('deleted from table', (select count(*) from announcements)::text, '4');
