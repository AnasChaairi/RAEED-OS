-- Checks who sees a ملاحظة and who gets notified. Run on a throwaway Postgres 16 after
-- local_stubs.sql and every migration in order (see the PR). Never on the live database.
\set ON_ERROR_STOP 1
-- People: supervisor S, parents A (of kid1), B (of kid2), C (of kid3, another group), advisor G
insert into auth.users(id) values
 ('00000000-0000-0000-0000-00000000000a'),('00000000-0000-0000-0000-00000000000b'),
 ('00000000-0000-0000-0000-00000000000c'),('00000000-0000-0000-0000-000000000005'),('00000000-0000-0000-0000-000000000009');
insert into people(id, full_name, phone) values
 ('00000000-0000-0000-0000-00000000000a','Parent A','+212600000001'),
 ('00000000-0000-0000-0000-00000000000b','Parent B','+212600000002'),
 ('00000000-0000-0000-0000-00000000000c','Parent C','+212600000003'),
 ('00000000-0000-0000-0000-000000000005','Supervisor S','+212600000005'),
 ('00000000-0000-0000-0000-000000000009','General G','+212600000009');
insert into person_roles values ('00000000-0000-0000-0000-00000000000a','parent'),('00000000-0000-0000-0000-00000000000b','parent'),
 ('00000000-0000-0000-0000-00000000000c','parent'),('00000000-0000-0000-0000-000000000005','instructor'),('00000000-0000-0000-0000-000000000009','advisor');
insert into groups(id, name, logo_letter) values ('10000000-0000-0000-0000-000000000001','G1','ا'),('10000000-0000-0000-0000-000000000002','G2','ب');
insert into children(id, full_name) values ('20000000-0000-0000-0000-000000000001','Kid One'),('20000000-0000-0000-0000-000000000002','Kid Two'),('20000000-0000-0000-0000-000000000003','Kid Three');
insert into child_groups(child_id, group_id) values ('20000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001'),
 ('20000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000001'),('20000000-0000-0000-0000-000000000003','10000000-0000-0000-0000-000000000002');
insert into child_parents(child_id, parent_id) values ('20000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-00000000000a'),
 ('20000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-00000000000b'),('20000000-0000-0000-0000-000000000003','00000000-0000-0000-0000-00000000000c');
insert into group_supervisors(group_id, person_id) values ('10000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000005');

set role authenticated;
-- S writes a note about Kid One
set test.uid = '00000000-0000-0000-0000-000000000005';
insert into child_messages(id, child_id, author_id, body) values ('30000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000005','ملاحظة عن الطفل الأول');
\echo '--- who can read the note (expect: A yes, B no, C no, S yes, G yes)'
set test.uid = '00000000-0000-0000-0000-00000000000a'; select 'A sees', count(*) from child_messages;
set test.uid = '00000000-0000-0000-0000-00000000000b'; select 'B sees', count(*) from child_messages;
set test.uid = '00000000-0000-0000-0000-00000000000c'; select 'C sees', count(*) from child_messages;
set test.uid = '00000000-0000-0000-0000-000000000005'; select 'S sees', count(*) from child_messages;
set test.uid = '00000000-0000-0000-0000-000000000009'; select 'G sees', count(*) from child_messages;
\echo '--- B tries to reply / like the note of another family (expect errors caught)'
set test.uid = '00000000-0000-0000-0000-00000000000b';
do $$ begin insert into child_message_replies(message_id, author_id, body) values ('30000000-0000-0000-0000-000000000001', auth.uid(), 'x'); raise notice 'B REPLY ALLOWED (bad)'; exception when others then raise notice 'B reply refused: %', sqlerrm; end $$;
do $$ begin insert into child_message_likes(message_id, person_id) values ('30000000-0000-0000-0000-000000000001', auth.uid()); raise notice 'B LIKE ALLOWED (bad)'; exception when others then raise notice 'B like refused: %', sqlerrm; end $$;
\echo '--- S tries to write about a child outside the فئة (expect refused)'
set test.uid = '00000000-0000-0000-0000-000000000005';
do $$ begin insert into child_messages(child_id, author_id, body) values ('20000000-0000-0000-0000-000000000003', auth.uid(), 'x'); raise notice 'S OUTSIDE ALLOWED (bad)'; exception when others then raise notice 'S outside refused: %', sqlerrm; end $$;
\echo '--- A replies'
set test.uid = '00000000-0000-0000-0000-00000000000a';
insert into child_message_replies(message_id, author_id, body) values ('30000000-0000-0000-0000-000000000001', auth.uid(), 'شكرا');
\echo '--- each person reads their own notifications (bell)'
set test.uid = '00000000-0000-0000-0000-00000000000a'; select 'A inbox', kind, title from notification_outbox;
set test.uid = '00000000-0000-0000-0000-00000000000b'; select 'B inbox', count(*) from notification_outbox;
set test.uid = '00000000-0000-0000-0000-00000000000c'; select 'C inbox', count(*) from notification_outbox;
set test.uid = '00000000-0000-0000-0000-000000000005'; select 'S inbox', kind, title from notification_outbox;
select mark_notifications_read(); select 'S unread after mark', count(*) from notification_outbox where read_at is null;
reset role;
\echo '--- all rows queued (as server)'
select p.full_name, o.kind from notification_outbox o join people p on p.id=o.recipient_id order by o.created_at;
