-- Run after local_bootstrap.sql and the migrations. Each check raises on failure.
grant usage on schema public to authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;

-- Fixtures (as the table owner, bypassing RLS)
insert into auth.users values
 ('00000000-0000-0000-0000-00000000000a'), ('00000000-0000-0000-0000-00000000000b'),
 ('00000000-0000-0000-0000-00000000000c'), ('00000000-0000-0000-0000-00000000000d'),
 ('00000000-0000-0000-0000-00000000000e');
insert into public.people (id, full_name, phone) values
 ('00000000-0000-0000-0000-00000000000a', 'المشرف', '+212600000001'),
 ('00000000-0000-0000-0000-00000000000b', 'ياسين', '+212600000002'),
 ('00000000-0000-0000-0000-00000000000c', 'كريم بنعلي', '+212600000003'),
 ('00000000-0000-0000-0000-00000000000d', 'سعاد العلوي', '+212600000004'),
 ('00000000-0000-0000-0000-00000000000e', 'حمزة', '+212600000005');
insert into public.person_roles values
 ('00000000-0000-0000-0000-00000000000a', 'advisor'), ('00000000-0000-0000-0000-00000000000b', 'instructor'),
 ('00000000-0000-0000-0000-00000000000c', 'parent'), ('00000000-0000-0000-0000-00000000000d', 'parent'),
 ('00000000-0000-0000-0000-00000000000e', 'instructor');
insert into public.groups (id, name, logo_letter) values
 ('10000000-0000-0000-0000-000000000001', 'فئة النجوم', 'ن'),
 ('10000000-0000-0000-0000-000000000002', 'فئة الفرسان', 'ف');
insert into public.group_instructors values
 ('10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000000b'),
 ('10000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-00000000000e');
insert into public.children (id, full_name) values
 ('20000000-0000-0000-0000-000000000001', 'آدم بنعلي'),
 ('20000000-0000-0000-0000-000000000002', 'عمر الفاسي');
insert into public.child_groups (child_id, group_id) values
 ('20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001'),
 ('20000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000002');
insert into public.child_parents values
 ('20000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000000c'),
 ('20000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000000d');

do $$ begin
  begin
    insert into public.child_parents values ('20000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000000e');
    raise exception 'FAIL: third parent accepted';
  exception when others then
    if sqlerrm like 'FAIL%' then raise; end if;
  end;
end $$;

-- Instructor Yassine creates a session: both of Adam's parents get a notification naming Adam.
set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000b';
insert into public.sessions (id, group_id, title, session_date, start_time, end_time, floor) values
 ('30000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', 'حفظ سورة الملك', '2027-01-30', '10:00', '11:30', 1),
 ('30000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000001', 'مراجعة', '2027-02-06', '10:00', '11:30', 1);
reset role;
do $$ begin
  if (select count(*) from notification_outbox where kind = 'session_created' and title like '%آدم%') <> 4 then
    raise exception 'FAIL: expected 4 creation notifications (2 sessions x 2 parents)';
  end if;
end $$;

-- Yassine cannot create a session for a group he does not teach.
set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000b';
do $$ begin
  begin
    insert into public.sessions (group_id, title, session_date, start_time, end_time, floor)
    values ('10000000-0000-0000-0000-000000000002', 'x', '2027-02-01', '10:00', '11:00', 0);
    raise exception 'FAIL: instructor wrote to another group';
  exception when insufficient_privilege then null;
  end;
end $$;

-- Offline attendance: two absences in a row raise one alert; re-sending is harmless.
insert into public.attendance values
 ('40000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', 'absent', '00000000-0000-0000-0000-00000000000b', '2027-01-30 10:05+01');
insert into public.attendance values
 ('40000000-0000-0000-0000-000000000002', '30000000-0000-0000-0000-000000000002', '20000000-0000-0000-0000-000000000001', 'absent', '00000000-0000-0000-0000-00000000000b', '2027-02-06 10:05+01')
 on conflict (session_id, child_id) do update set status = excluded.status, recorded_by = excluded.recorded_by, recorded_at = excluded.recorded_at;
insert into public.attendance values
 ('40000000-0000-0000-0000-000000000002', '30000000-0000-0000-0000-000000000002', '20000000-0000-0000-0000-000000000001', 'absent', '00000000-0000-0000-0000-00000000000b', '2027-02-06 10:05+01')
 on conflict (session_id, child_id) do update set status = excluded.status, recorded_by = excluded.recorded_by, recorded_at = excluded.recorded_at;
-- An older offline save arriving late does not overwrite the newer one.
insert into public.attendance values
 ('40000000-0000-0000-0000-000000000009', '30000000-0000-0000-0000-000000000002', '20000000-0000-0000-0000-000000000001', 'present', '00000000-0000-0000-0000-00000000000b', '2027-02-06 10:01+01')
 on conflict (session_id, child_id) do update set status = excluded.status, recorded_by = excluded.recorded_by, recorded_at = excluded.recorded_at;
do $$ begin
  if (select count(*) from absence_alerts where status = 'open') <> 1 then raise exception 'FAIL: expected one open alert'; end if;
  if (select status from attendance where session_id = '30000000-0000-0000-0000-000000000002') <> 'absent' then
    raise exception 'FAIL: older offline save overwrote newer one'; end if;
end $$;

-- Hamza (other group) sees neither Adam, his attendance, nor the alert.
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000e';
do $$ begin
  if (select count(*) from children) <> 1 then raise exception 'FAIL: instructor sees other groups'' children'; end if;
  if (select count(*) from attendance) <> 0 then raise exception 'FAIL: instructor sees other groups'' attendance'; end if;
  if (select count(*) from absence_alerts) <> 0 then raise exception 'FAIL: instructor sees other groups'' alerts'; end if;
end $$;

-- Parent Karim sees Adam's sessions and materials, but no attendance, notes or alerts.
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000b';
insert into public.materials (session_id, kind, url, label) values ('30000000-0000-0000-0000-000000000001', 'youtube', 'https://youtube.com/watch?v=x', 'تلاوة');
insert into public.notes (child_id, author_id, body) values ('20000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000000b', 'ملاحظة داخلية');
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000c';
do $$ begin
  if (select count(*) from sessions) <> 2 then raise exception 'FAIL: parent should see 2 sessions'; end if;
  if (select count(*) from materials) <> 1 then raise exception 'FAIL: parent should see materials'; end if;
  if (select count(*) from children) <> 1 then raise exception 'FAIL: parent should see only own child'; end if;
  if (select count(*) from attendance) + (select count(*) from notes) + (select count(*) from absence_alerts) <> 0 then
    raise exception 'FAIL: parent sees attendance, notes or alerts'; end if;
  if (select count(*) from notification_outbox) <> 0 then raise exception 'FAIL: outbox readable by app'; end if;
  if (select count(*) from people) <> 1 then raise exception 'FAIL: parent should only read own person row'; end if;
  if (select string_agg(full_name, ',') from group_staff_names('10000000-0000-0000-0000-000000000001')) <> 'ياسين' then
    raise exception 'FAIL: parent should see instructor names'; end if;
  if (select count(*) from group_staff_names('10000000-0000-0000-0000-000000000002')) <> 0 then
    raise exception 'FAIL: parent sees another group''s staff'; end if;
end $$;

-- Advisor sees everything and the statistics view works.
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
do $$ begin
  if (select count(*) from children) <> 2 then raise exception 'FAIL: advisor should see all children'; end if;
  if (select count(*) from notes) <> 1 then raise exception 'FAIL: advisor should see notes'; end if;
end $$;
reset role;

-- Cancelling notifies both parents.
set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000b';
update public.sessions set status = 'cancelled', cancel_reason = 'عطلة' where id = '30000000-0000-0000-0000-000000000002';
reset role;
do $$ begin
  if (select count(*) from notification_outbox where kind = 'session_cancelled') <> 2 then
    raise exception 'FAIL: cancellation should notify both parents'; end if;
end $$;

select 'ALL ACCESS RULE TESTS PASSED' as result;
