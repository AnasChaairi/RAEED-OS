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

-- The advisor creates sessions for Adam's group: both of Adam's parents get a notification naming Adam.
set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
insert into public.sessions (id, group_id, title, session_date, start_time, end_time, floor) values
 ('30000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', 'حفظ سورة الملك', '2027-01-30', '10:00', '11:30', 1),
 ('30000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000001', 'مراجعة', '2027-02-06', '10:00', '11:30', 1);
reset role;
do $$ begin
  if (select count(*) from notification_outbox where kind = 'session_created' and title like '%آدم%') <> 4 then
    raise exception 'FAIL: expected 4 creation notifications (2 sessions x 2 parents)';
  end if;
end $$;

-- Only advisors plan sessions: Yassine cannot create, move or cancel one, even in his own group.
set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000b';
do $$ begin
  begin
    insert into public.sessions (group_id, title, session_date, start_time, end_time, floor)
    values ('10000000-0000-0000-0000-000000000001', 'x', '2027-02-01', '10:00', '11:00', 0);
    raise exception 'FAIL: instructor created a session';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.create_sessions('10000000-0000-0000-0000-000000000001',
      '{"title": "x", "start_time": "10:00", "end_time": "11:00", "floor": 0}', array['2027-02-01'::date], null);
    raise exception 'FAIL: instructor created sessions through the function';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.cancel_sessions('30000000-0000-0000-0000-000000000001', 'x', false);
    raise exception 'FAIL: instructor cancelled a session';
  exception when insufficient_privilege then null;
  end;
  update public.sessions set start_time = '09:00' where id = '30000000-0000-0000-0000-000000000001';
  if (select start_time from sessions where id = '30000000-0000-0000-0000-000000000001') <> '10:00' then
    raise exception 'FAIL: instructor moved a session'; end if;
  begin
    insert into public.materials (session_id, kind, url, label)
    values ('30000000-0000-0000-0000-000000000001', 'youtube', 'https://youtube.com/watch?v=y', 'x');
    raise exception 'FAIL: instructor added material';
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
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
insert into public.materials (session_id, kind, url, label) values ('30000000-0000-0000-0000-000000000001', 'youtube', 'https://youtube.com/watch?v=x', 'تلاوة');
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000b';
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
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
update public.sessions set status = 'cancelled', cancel_reason = 'عطلة' where id = '30000000-0000-0000-0000-000000000002';
reset role;
do $$ begin
  if (select count(*) from notification_outbox where kind = 'session_cancelled') <> 2 then
    raise exception 'FAIL: cancellation should notify both parents'; end if;
end $$;

-- A parent can clear their own first-sign-in flag but cannot edit their own row directly.
set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000c';
update public.people set phone = '+212699999999' where id = '00000000-0000-0000-0000-00000000000c';
select public.mark_password_changed();
reset role;
do $$ begin
  if (select phone from people where id = '00000000-0000-0000-0000-00000000000c') <> '+212600000003' then
    raise exception 'FAIL: person changed their own phone number'; end if;
  if (select must_change_password from people where id = '00000000-0000-0000-0000-00000000000c') then
    raise exception 'FAIL: password-changed flag not cleared'; end if;
end $$;

-- Stage 4: a moved session remembers its first time, and parents see who is notified.
set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
update public.sessions set start_time = '10:30' where id = '30000000-0000-0000-0000-000000000001';
update public.sessions set start_time = '10:45' where id = '30000000-0000-0000-0000-000000000001';
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000d';
select public.register_device('token-soad', 'android');
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000c';
do $$ begin
  if (select original_start from sessions where id = '30000000-0000-0000-0000-000000000001') <> '10:00' then
    raise exception 'FAIL: a moved session should keep its first start time'; end if;
  if (select count(*) from my_children_parents()) <> 2 then raise exception 'FAIL: parent should see both parents'; end if;
  if (select full_name from my_children_parents() limit 1) <> 'كريم بنعلي' then
    raise exception 'FAIL: the caller should come first'; end if;
  if (select string_agg(notified::text, ',') from my_children_parents()) <> 'false,true' then
    raise exception 'FAIL: notification status per parent'; end if;
end $$;
-- The same phone signed in as Karim moves the token to him.
select public.register_device('token-soad', 'android');
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000e';
do $$ begin
  if (select count(*) from my_children_parents()) <> 0 then raise exception 'FAIL: instructor sees parents through my_children_parents'; end if;
  begin
    perform public.claim_notifications(10);
    raise exception 'FAIL: app can claim notifications';
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;
do $$ begin
  if (select person_id from devices where push_token = 'token-soad') <> '00000000-0000-0000-0000-00000000000c' then
    raise exception 'FAIL: token should move to whoever signed in'; end if;
  if (select count(*) from claim_notifications(100)) = 0 then raise exception 'FAIL: claim returns nothing'; end if;
  if (select count(*) from claim_notifications(100)) <> 0 then raise exception 'FAIL: claimed rows claimed twice'; end if;
end $$;

-- Stage 5: usage is logged by its owner only, and only advisors read it or the pilot metrics.
set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
insert into public.sessions (id, group_id, title, session_date, start_time, end_time, floor) values
 ('30000000-0000-0000-0000-000000000003', '10000000-0000-0000-0000-000000000001', 'حصة سابقة', '2026-09-01', '10:00', '11:00', 1),
 ('30000000-0000-0000-0000-000000000004', '10000000-0000-0000-0000-000000000001', 'حصة سابقة', '2026-09-08', '10:00', '11:00', 1);
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000b';
insert into public.attendance (id, session_id, child_id, status, recorded_by, recorded_at) values
 ('40000000-0000-0000-0000-000000000003', '30000000-0000-0000-0000-000000000003', '20000000-0000-0000-0000-000000000001',
  'present', '00000000-0000-0000-0000-00000000000b', '2026-09-01 12:00+01'),
 ('40000000-0000-0000-0000-000000000004', '30000000-0000-0000-0000-000000000004', '20000000-0000-0000-0000-000000000001',
  'present', '00000000-0000-0000-0000-00000000000b', '2026-09-10 12:00+01');
insert into public.usage_events (kind, session_id, seconds) values
 ('attendance_sheet', '30000000-0000-0000-0000-000000000003', 100),
 ('attendance_sheet', '30000000-0000-0000-0000-000000000004', 200);
do $$ begin
  begin
    insert into public.usage_events (person_id, kind) values ('00000000-0000-0000-0000-00000000000a', 'stats_view');
    raise exception 'FAIL: logged usage as someone else';
  exception when insufficient_privilege then null;
  end;
  if (select count(*) from usage_events) <> 0 then raise exception 'FAIL: instructor reads usage'; end if;
  begin
    perform public.pilot_metrics('2026-09-01', '2026-09-30');
    raise exception 'FAIL: instructor reads pilot metrics';
  exception when insufficient_privilege then null;
  end;
end $$;
-- Karim asks for his account to be deleted; Soad cannot see or withdraw his request.
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000c';
insert into public.account_deletion_requests default values;
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000d';
delete from public.account_deletion_requests;
do $$ begin
  if (select count(*) from account_deletion_requests) <> 0 then raise exception 'FAIL: parent sees another''s deletion request'; end if;
end $$;
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
insert into public.usage_events (kind) values ('stats_view');
do $$
declare m jsonb := public.pilot_metrics('2026-09-01', '2026-09-30');
begin
  if (select count(*) from account_deletion_requests) <> 1 then raise exception 'FAIL: advisor should see the deletion request'; end if;
  if (select count(*) from usage_events) <> 3 then raise exception 'FAIL: advisor should read usage'; end if;
  if (m->>'sessions_held')::int <> 2 or (m->>'recorded_within_24h')::int <> 1 or (m->>'recorded_late')::int <> 1 then
    raise exception 'FAIL: pilot sessions %', m; end if;
  if (m->>'median_sheet_seconds')::numeric <> 150 then raise exception 'FAIL: median sheet time %', m; end if;
  if (m->>'families')::int <> 1 or (m->>'families_signed_in')::int <> 1 then raise exception 'FAIL: families %', m; end if;
  if jsonb_array_length(m->'advisors') <> 1 then raise exception 'FAIL: advisors %', m; end if;
end $$;
-- The advisor plans and cancels a weekly series for any group through the app's functions.
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
do $$ declare first uuid; begin
  first := public.create_sessions('10000000-0000-0000-0000-000000000002',
    '{"title": "نادي", "start_time": "17:00", "end_time": "18:00", "place": "samae", "floor": 0}',
    array['2027-03-01', '2027-03-08']::date[], array[1]::smallint[]);
  perform public.update_sessions(first, '{"title": "نادي القراءة", "session_date": "2027-03-01", "start_time": "17:30", "end_time": "18:30", "place": "samae", "floor": 0}', true);
  perform public.cancel_sessions(first, 'عطلة', true);
  if (select count(*) from sessions where title = 'نادي القراءة' and status = 'cancelled') <> 2 then
    raise exception 'FAIL: advisor plans a series for any group'; end if;
end $$;
-- The advisor names who runs each session, among the group's instructors only.
do $$ declare first uuid; begin
  first := public.create_sessions('10000000-0000-0000-0000-000000000002',
    '{"title": "رسم", "start_time": "17:00", "end_time": "18:00", "place": "samae", "floor": 0}',
    array['2027-04-05', '2027-04-12']::date[], array[1]::smallint[], '[]',
    array['00000000-0000-0000-0000-00000000000e']::uuid[]);
  if (select count(*) from session_instructors si join sessions s on s.id = si.session_id where s.title = 'رسم') <> 2 then
    raise exception 'FAIL: instructors on every session of the series'; end if;
  begin
    perform public.create_sessions('10000000-0000-0000-0000-000000000002',
      '{"title": "x", "start_time": "17:00", "end_time": "18:00", "place": "samae", "floor": 0}',
      array['2027-04-05']::date[], null, '[]', array['00000000-0000-0000-0000-00000000000b']::uuid[]);
    raise exception 'FAIL: accepted an instructor from another group';
  exception when invalid_parameter_value then null;
  end;
  begin
    perform public.create_sessions('10000000-0000-0000-0000-000000000002',
      '{"title": "x", "start_time": "17:00", "end_time": "18:00", "place": "samae", "floor": 0}',
      array['2027-04-05']::date[], null, '[]', array[]::uuid[]);
    raise exception 'FAIL: accepted a session with no instructor';
  exception when invalid_parameter_value then null;
  end;
  insert into group_instructors values ('10000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-00000000000b');
  perform public.update_sessions(first, '{"title": "رسم", "session_date": "2027-04-05", "start_time": "17:00", "end_time": "18:00", "place": "samae", "floor": 0}',
    true, array['00000000-0000-0000-0000-00000000000b', '00000000-0000-0000-0000-00000000000e']::uuid[]);
  if (select count(*) from session_instructors si join sessions s on s.id = si.session_id where s.title = 'رسم') <> 4 then
    raise exception 'FAIL: update replaces the instructors of the series'; end if;
  delete from group_instructors where group_id = '10000000-0000-0000-0000-000000000002' and person_id = '00000000-0000-0000-0000-00000000000b';
end $$;
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000e';
do $$ begin
  if (select count(*) from session_instructors) <> 4 then raise exception 'FAIL: instructor reads who runs their sessions'; end if;
  begin
    delete from session_instructors;
    if (select count(*) from session_instructors) <> 4 then raise exception 'FAIL: instructor changed who runs a session'; end if;
  exception when insufficient_privilege then null;
  end;
end $$;
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
-- Gender: the advisor sets it on a child and a staff member; nothing else is accepted.
update public.children set gender = 'male' where id = '20000000-0000-0000-0000-000000000001';
update public.people set gender = 'female' where id = '00000000-0000-0000-0000-00000000000a';
do $$ begin
  if (select gender from children where id = '20000000-0000-0000-0000-000000000001') is distinct from 'male' then
    raise exception 'FAIL: advisor sets a child''s gender'; end if;
  begin
    update public.children set gender = 'x' where id = '20000000-0000-0000-0000-000000000002';
    raise exception 'FAIL: accepted an unknown gender';
  exception when check_violation then null;
  end;
end $$;
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
-- Category supervisor (مشرف الفئة): Nadia supervises Hamza's group only. Rachid is a second
-- instructor of that group, not picked for the session.
reset role;
insert into auth.users values ('00000000-0000-0000-0000-00000000000f'), ('00000000-0000-0000-0000-000000000010');
insert into public.people (id, full_name, phone) values
 ('00000000-0000-0000-0000-00000000000f', 'نادية', '+212600000006'),
 ('00000000-0000-0000-0000-000000000010', 'رشيد', '+212600000007');
insert into public.person_roles values ('00000000-0000-0000-0000-000000000010', 'instructor');
insert into public.group_supervisors values ('10000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-00000000000f');
insert into public.group_instructors values ('10000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000010');
set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000f';
do $$ declare first uuid; begin
  if (select count(*) from groups) <> 1 then raise exception 'FAIL: supervisor sees other groups'; end if;
  if (select count(*) from children) <> 1 or not exists (select 1 from children where full_name = 'عمر الفاسي') then
    raise exception 'FAIL: supervisor sees their group''s children only'; end if;
  if not exists (select 1 from people where full_name = 'حمزة') then raise exception 'FAIL: supervisor sees their instructors'; end if;
  if exists (select 1 from people where full_name = 'ياسين') then raise exception 'FAIL: supervisor sees other instructors'; end if;
  first := public.create_sessions('10000000-0000-0000-0000-000000000002',
    '{"title": "نشاط مسرح", "start_time": "15:00", "end_time": "16:00", "place": "samae", "floor": 0}',
    array['2027-05-03']::date[], null, '[]', array['00000000-0000-0000-0000-00000000000e']::uuid[]);
  perform public.update_sessions(first, '{"title": "نشاط المسرح", "session_date": "2027-05-03", "start_time": "15:00", "end_time": "16:30", "place": "samae", "floor": 0}', false,
    array['00000000-0000-0000-0000-00000000000e']::uuid[]);
  insert into public.materials (session_id, kind, url, label) values (first, 'drive', 'https://drive.google.com/x', 'نص');
  begin
    perform public.create_sessions('10000000-0000-0000-0000-000000000001',
      '{"title": "x", "start_time": "10:00", "end_time": "11:00", "floor": 0}', array['2027-05-03'::date], null);
    raise exception 'FAIL: supervisor planned another group''s session';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.cancel_sessions('30000000-0000-0000-0000-000000000001', 'x', false);
    raise exception 'FAIL: supervisor cancelled another group''s session';
  exception when insufficient_privilege then null;
  end;
  begin
    insert into public.attendance (id, session_id, child_id, status, recorded_by, recorded_at)
    values (gen_random_uuid(), first, '20000000-0000-0000-0000-000000000002', 'present', auth.uid(), now());
    raise exception 'FAIL: supervisor recorded attendance';
  exception when insufficient_privilege then null;
  end;
end $$;
-- Rachid teaches the group but was not picked: no attendance, no observation.
set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000010';
do $$ declare s uuid := (select id from sessions where title = 'نشاط المسرح'); begin
  begin
    insert into public.attendance (id, session_id, child_id, status, recorded_by, recorded_at)
    values (gen_random_uuid(), s, '20000000-0000-0000-0000-000000000002', 'present', auth.uid(), now());
    raise exception 'FAIL: unpicked instructor recorded attendance';
  exception when insufficient_privilege then null;
  end;
  begin
    insert into public.session_observations (session_id, author_id, body) values (s, auth.uid(), 'x');
    raise exception 'FAIL: unpicked instructor wrote an observation';
  exception when insufficient_privilege then null;
  end;
end $$;
-- Hamza was picked: he records attendance and writes an observation.
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000e';
do $$ declare s uuid := (select id from sessions where title = 'نشاط المسرح'); begin
  insert into public.attendance (id, session_id, child_id, status, recorded_by, recorded_at)
  values ('40000000-0000-0000-0000-000000000077', s, '20000000-0000-0000-0000-000000000002', 'present', auth.uid(), now());
  update public.attendance set status = 'late', recorded_at = now() where id = '40000000-0000-0000-0000-000000000077';
  if (select status from attendance where id = '40000000-0000-0000-0000-000000000077') <> 'late' then
    raise exception 'FAIL: picked instructor corrects attendance'; end if;
  insert into public.session_observations (session_id, body) values (s, 'عمر شارك بحماس');
end $$;
set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000010';
do $$ begin
  update public.attendance set status = 'absent' where id = '40000000-0000-0000-0000-000000000077';
  if (select count(*) from session_observations) <> 0 then raise exception 'FAIL: unpicked instructor reads observations'; end if;
end $$;
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000f';
do $$ begin
  if (select status from attendance where id = '40000000-0000-0000-0000-000000000077') <> 'late' then
    raise exception 'FAIL: unpicked instructor changed attendance'; end if;
  if (select count(*) from session_observations) <> 1 then raise exception 'FAIL: supervisor reads observations'; end if;
  delete from public.session_observations;
  if (select count(*) from session_observations) <> 1 then raise exception 'FAIL: supervisor deleted an observation'; end if;
end $$;
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000b';
do $$ begin
  if (select count(*) from session_observations) <> 0 then raise exception 'FAIL: other group reads observations'; end if;
  if (select count(*) from group_supervisors) <> 0 then raise exception 'FAIL: other group reads supervisors'; end if;
end $$;
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
do $$ begin
  if (select count(*) from session_observations) <> 1 then raise exception 'FAIL: advisor reads observations'; end if;
end $$;
reset role;

-- Category supervisor's channel with parents: Nadia writes about Omar; Leila, his mother,
-- gets a notification, likes it and replies; Nadia hears about both. Nobody else reads it.
reset role;
insert into auth.users values ('00000000-0000-0000-0000-000000000011');
insert into public.people (id, full_name, phone) values ('00000000-0000-0000-0000-000000000011', 'ليلى الفاسي', '+212600000008');
insert into public.person_roles values ('00000000-0000-0000-0000-000000000011', 'parent');
insert into public.child_parents values ('20000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000011');
set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000f';
do $$ begin
  insert into public.child_messages (id, child_id, body)
  values ('50000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000002', 'عمر شارك اليوم بحماس في المسرح');
  begin
    insert into public.child_messages (child_id, body) values ('20000000-0000-0000-0000-000000000001', 'x');
    raise exception 'FAIL: supervisor wrote about a child of another group';
  exception when insufficient_privilege then null;
  end;
end $$;
set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000011';
do $$ begin
  if (select count(*) from child_messages) <> 1 then raise exception 'FAIL: parent reads the message about their child'; end if;
  if not exists (select 1 from people where full_name = 'نادية') then raise exception 'FAIL: parent sees who wrote'; end if;
  insert into public.child_message_likes (message_id) values ('50000000-0000-0000-0000-000000000001');
  insert into public.child_message_replies (message_id, body) values ('50000000-0000-0000-0000-000000000001', 'شكراً لكم');
  begin
    insert into public.child_messages (child_id, body) values ('20000000-0000-0000-0000-000000000002', 'x');
    raise exception 'FAIL: parent started a message';
  exception when insufficient_privilege then null;
  end;
end $$;
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000c';
do $$ begin
  if (select count(*) from child_messages) + (select count(*) from child_message_replies) <> 0 then
    raise exception 'FAIL: another parent reads the message'; end if;
  begin
    insert into public.child_message_replies (message_id, body) values ('50000000-0000-0000-0000-000000000001', 'x');
    raise exception 'FAIL: another parent replied';
  exception when insufficient_privilege then null;
  end;
end $$;
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000e';
do $$ begin
  if (select count(*) from child_messages) <> 0 then raise exception 'FAIL: instructor reads the parents channel'; end if;
end $$;
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000f';
do $$ begin
  if (select count(*) from child_message_replies) <> 1 or (select count(*) from child_message_likes) <> 1 then
    raise exception 'FAIL: supervisor reads replies and likes'; end if;
  if not exists (select 1 from people where full_name = 'ليلى الفاسي') then raise exception 'FAIL: supervisor sees the parent'; end if;
end $$;
reset role;
do $$ begin
  if (select count(*) from notification_outbox where kind = 'child_message' and recipient_id = '00000000-0000-0000-0000-000000000011') <> 1 then
    raise exception 'FAIL: parent notified of the observation'; end if;
  if (select count(*) from notification_outbox where kind in ('child_message_reply', 'child_message_like')
      and recipient_id = '00000000-0000-0000-0000-00000000000f') <> 2 then
    raise exception 'FAIL: supervisor notified of the like and the reply'; end if;
  if exists (select 1 from notification_outbox where kind = 'child_message_reply' and recipient_id = '00000000-0000-0000-0000-000000000011') then
    raise exception 'FAIL: replier notified of their own reply'; end if;
end $$;

-- Instructor absences: Rachid (group 2) reports that he will miss a coming session, and
-- Nadia, its supervisor, is notified. Past sessions and other groups' sessions are refused.
reset role;
insert into public.sessions (id, group_id, title, session_date, start_time, end_time, floor) values
 ('30000000-0000-0000-0000-0000000000a1', '10000000-0000-0000-0000-000000000002', 'حصة قادمة',
  (now() at time zone 'Africa/Casablanca')::date + 3, '10:00', '11:30', 1),
 ('30000000-0000-0000-0000-0000000000a2', '10000000-0000-0000-0000-000000000002', 'حصة مضت',
  (now() at time zone 'Africa/Casablanca')::date - 3, '10:00', '11:30', 1);
set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000010';
do $$ begin
  insert into public.instructor_absences (session_id, person_id, reason)
    values ('30000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000010', 'موعد طبي');
  begin
    insert into public.instructor_absences (session_id, person_id, reason)
      values ('30000000-0000-0000-0000-0000000000a2', '00000000-0000-0000-0000-000000000010', 'x');
    raise exception 'FAIL: absence reported for a past session';
  exception when insufficient_privilege then null;
  end;
  begin
    insert into public.instructor_absences (session_id, person_id, reason)
      values ('30000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000000e', 'x');
    raise exception 'FAIL: absence reported for someone else';
  exception when insufficient_privilege then null;
  end;
end $$;
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000b';
do $$ begin
  begin
    insert into public.instructor_absences (session_id, person_id, reason)
      values ('30000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000000b', 'x');
    raise exception 'FAIL: absence reported on another group''s session';
  exception when insufficient_privilege then null;
  end;
  if (select count(*) from instructor_absences) <> 0 then raise exception 'FAIL: other group reads the absence'; end if;
end $$;
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000f';
do $$ begin
  if (select count(*) from instructor_absences) <> 1 then raise exception 'FAIL: supervisor reads the absence'; end if;
  if (select phone from people where id = '00000000-0000-0000-0000-000000000010') is null then
    raise exception 'FAIL: supervisor reads the instructor''s phone'; end if;
end $$;
reset role;
do $$ begin
  if (select count(*) from notification_outbox where kind = 'instructor_absence'
      and recipient_id = '00000000-0000-0000-0000-00000000000f') <> 1 then
    raise exception 'FAIL: supervisor notified of the absence'; end if;
  if exists (select 1 from notification_outbox where kind = 'instructor_absence'
      and recipient_id <> '00000000-0000-0000-0000-00000000000f') then
    raise exception 'FAIL: only the supervisor is notified of the absence'; end if;
end $$;
set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000010';
delete from public.instructor_absences where session_id = '30000000-0000-0000-0000-0000000000a1';
reset role;
do $$ begin
  if exists (select 1 from instructor_absences) then raise exception 'FAIL: instructor takes the absence back'; end if;
end $$;

-- Deleting sessions: Nadia deletes one of her group's sessions, not another group's; an
-- instructor deletes none.
set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000010';
delete from public.sessions where id = '30000000-0000-0000-0000-0000000000a2';
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000f';
delete from public.sessions where id = '30000000-0000-0000-0000-0000000000a2';
delete from public.sessions where group_id = '10000000-0000-0000-0000-000000000001';
reset role;
do $$ begin
  if exists (select 1 from sessions where id = '30000000-0000-0000-0000-0000000000a2') then
    raise exception 'FAIL: supervisor deletes their group''s session'; end if;
  if not exists (select 1 from sessions where group_id = '10000000-0000-0000-0000-000000000001') then
    raise exception 'FAIL: supervisor deleted another group''s sessions'; end if;
end $$;
set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000010';
delete from public.sessions where id = '30000000-0000-0000-0000-0000000000a1';
reset role;
do $$ begin
  if not exists (select 1 from sessions where id = '30000000-0000-0000-0000-0000000000a1') then
    raise exception 'FAIL: instructor deleted a session'; end if;
end $$;

-- More notifications (20261127000000): instructors hear about planning, the 5-hour reminder
-- reaches instructors and parents, and absence alerts reach the group's staff.
reset role;
delete from notification_outbox;
set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
select public.create_sessions('10000000-0000-0000-0000-000000000001',
  '{"title": "تجويد", "start_time": "15:00", "end_time": "16:00", "place": "samae", "floor": 1, "remind": true}',
  array[((now() at time zone 'Africa/Casablanca')::date + 20)], null);
reset role;
do $$ begin
  if (select count(*) from notification_outbox where kind = 'session_created'
      and recipient_id = '00000000-0000-0000-0000-00000000000b') <> 1 then
    raise exception 'FAIL: instructor notified of a new session'; end if;
  if exists (select 1 from notification_outbox where recipient_id = '00000000-0000-0000-0000-00000000000a') then
    raise exception 'FAIL: the planner is not notified of their own session'; end if;
  if not (select remind from sessions where title = 'تجويد') then raise exception 'FAIL: reminder switch saved'; end if;
end $$;

delete from notification_outbox;
do $$
declare
  local timestamp := date_trunc('minute', (now() at time zone 'Africa/Casablanca') + interval '2 hours');
  later timestamp := date_trunc('minute', (now() at time zone 'Africa/Casablanca') + interval '8 hours');
begin
  insert into public.sessions (id, group_id, title, session_date, start_time, end_time, floor, remind) values
   ('30000000-0000-0000-0000-0000000000b1', '10000000-0000-0000-0000-000000000001', 'قريبة', local::date, local::time,
    case when local::time < '22:00' then local::time + interval '1 hour' else '23:59' end, 1, true),
   ('30000000-0000-0000-0000-0000000000b2', '10000000-0000-0000-0000-000000000001', 'بعيدة', later::date, later::time,
    case when later::time < '22:00' then later::time + interval '1 hour' else '23:59' end, 1, true),
   ('30000000-0000-0000-0000-0000000000b3', '10000000-0000-0000-0000-000000000001', 'بلا تذكير', local::date, local::time,
    case when local::time < '22:00' then local::time + interval '1 hour' else '23:59' end, 1, false);
end $$;
delete from notification_outbox;
do $$ begin
  if public.queue_session_reminders() <> 1 then raise exception 'FAIL: one session to remind'; end if;
  if (select count(*) from notification_outbox where kind = 'session_reminder'
      and recipient_id = '00000000-0000-0000-0000-00000000000b') <> 1 then
    raise exception 'FAIL: instructor reminded'; end if;
  if (select count(*) from notification_outbox where kind = 'session_reminder'
      and recipient_id in ('00000000-0000-0000-0000-00000000000c', '00000000-0000-0000-0000-00000000000d')) <> 2 then
    raise exception 'FAIL: both parents reminded'; end if;
  if public.queue_session_reminders() <> 0 then raise exception 'FAIL: reminded only once'; end if;
end $$;

delete from notification_outbox;
insert into public.absence_alerts (child_id, group_id, session_ids)
  select cg.child_id, cg.group_id, array[]::uuid[] from child_groups cg
  where cg.group_id = '10000000-0000-0000-0000-000000000002' and cg.to_date is null limit 1;
do $$ begin
  if (select count(*) from notification_outbox where kind = 'absence_alert') <> 3 then
    raise exception 'FAIL: absence alert to the two instructors and the supervisor, got %',
      (select count(*) from notification_outbox where kind = 'absence_alert'); end if;
end $$;

select 'ALL ACCESS RULE TESTS PASSED' as result;
