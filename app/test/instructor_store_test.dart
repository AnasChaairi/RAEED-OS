import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:raeed_os/instructor/instructor_repository.dart';
import 'package:raeed_os/instructor/instructor_store.dart';
import 'package:raeed_os/instructor/models.dart';
import 'package:raeed_os/setup/models.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_instructor.dart';

const me = 'yassine';
final now = DateTime(2027, 2, 6, 9, 41);
final today = DateTime(2027, 2, 6);

Future<InstructorStore> openStore(FakeInstructorRepository repo) async {
  final store = InstructorStore(repo, await SharedPreferences.getInstance(), retryEvery: null, clock: () => now);
  await store.start(me);
  return store;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('a weekly series has every chosen day up to the end date', () {
    final dates = seriesDates(DateTime(2027, 2, 6), DateTime(2027, 2, 20), {3, 6});
    expect(dates, [
      DateTime(2027, 2, 6),
      DateTime(2027, 2, 10),
      DateTime(2027, 2, 13),
      DateTime(2027, 2, 17),
      DateTime(2027, 2, 20),
    ]);
  });

  test('attendance is sent at once when online', () async {
    final repo = seededInstructorRepo(me: me, today: today);
    final store = await openStore(repo);
    await store.saveAttendance('today', {'adam': AttendanceStatus.absent, 'omar': AttendanceStatus.present});
    expect(store.pending, isEmpty);
    expect(repo.attendance['today/adam']!.status, AttendanceStatus.absent);
    expect(repo.attendance['today/adam']!.recordedBy, me);
    expect(store.sent.keys, ['today']);
  });

  test('a first recording is timed for the pilot, an edit is not', () async {
    final repo = seededInstructorRepo(me: me, today: today);
    final store = await openStore(repo);
    final opened = store.now().subtract(const Duration(seconds: 95));
    await store.saveAttendance('today', {'adam': AttendanceStatus.absent}, openedAt: opened);
    await store.saveAttendance('today', {'adam': AttendanceStatus.late}, openedAt: opened);
    expect(repo.sheets, ['today 95']);
  });

  test('offline, attendance waits on the phone and survives a restart, then is sent', () async {
    final repo = seededInstructorRepo(me: me, today: today);
    await openStore(repo);
    repo.offline = true;

    final store = await openStore(repo);
    expect(store.offline, isTrue);
    expect(store.loaded, isTrue, reason: 'the copy on the phone is shown');
    await store.saveAttendance('today', {'adam': AttendanceStatus.late});
    expect(store.pending, hasLength(1));
    expect(store.data.attendanceFor('today')['adam']!.status, AttendanceStatus.late);
    expect(repo.attendance, isEmpty);

    // The app is closed and reopened, still offline: the waiting record is still there.
    final reopened = await openStore(repo);
    expect(reopened.pending, hasLength(1));
    expect(reopened.waitingSessions, {'today'});

    repo.offline = false;
    expect(await reopened.sendNow(), isTrue);
    expect(reopened.pending, isEmpty);
    expect(reopened.offline, isFalse);
    expect(repo.attendance['today/adam']!.status, AttendanceStatus.late);
  });

  test('the same child saved twice keeps one record with the same id', () async {
    final repo = seededInstructorRepo(me: me, today: today);
    final store = await openStore(repo);
    await store.saveAttendance('today', {'adam': AttendanceStatus.absent});
    final first = repo.attendance['today/adam']!.id;
    await store.saveAttendance('today', {'adam': AttendanceStatus.excused});
    expect(repo.attendance['today/adam']!.id, first);
    expect(repo.attendance['today/adam']!.status, AttendanceStatus.excused);
  });

  test('two absences in a row bring an alert once the attendance arrives', () async {
    final repo = seededInstructorRepo(me: me, today: today);
    final store = await openStore(repo);
    await store.saveAttendance('last-week', {'adam': AttendanceStatus.absent});
    expect(store.data.openAlerts, isEmpty);
    await store.saveAttendance('today', {'adam': AttendanceStatus.absent});
    expect(store.data.openAlerts.single.childId, 'adam');
  });

  test('attendance rate counts late as attended', () async {
    final repo = seededInstructorRepo(me: me, today: today);
    final store = await openStore(repo);
    await store.saveAttendance('last-week', {'adam': AttendanceStatus.late, 'omar': AttendanceStatus.absent});
    await store.saveAttendance('today', {'adam': AttendanceStatus.absent, 'omar': AttendanceStatus.present});
    expect(store.data.attendanceRate('adam'), 0.5);
    expect(store.data.attendanceRate('omar'), 0.5);
    expect(store.data.attendanceRate('youssef'), isNull);
  });

  test('a snapshot survives the trip through the phone copy', () async {
    final repo = seededInstructorRepo(me: me, today: today);
    final store = await openStore(repo);
    final copy = InstructorSnapshot.fromJson(jsonDecode(jsonEncode(store.data.toJson())) as Map<String, dynamic>);
    expect(copy.sessions.map((s) => s.id), store.data.sessions.map((s) => s.id));
    expect(copy.children.first.parents.single.phone, '+212612345678');
    expect(copy.group('stars')!.instructorIds, [me, 'sara']);
  });

  test('only the instructors picked for a session take its attendance', () async {
    final repo = seededInstructorRepo(me: me, today: today);
    final i = repo.sessions.indexWhere((s) => s.id == 'today');
    final t = repo.sessions[i];
    repo.sessions[i] = Session(
      id: t.id,
      groupId: t.groupId,
      title: t.title,
      date: t.date,
      start: t.start,
      end: t.end,
      floor: t.floor,
      instructorIds: const ['sara'],
    );
    final store = await openStore(repo);
    final data = store.data;
    expect(store.canRecord(data.session('today')!), isFalse, reason: 'Sara was picked, not me');
    expect(store.canRecord(data.session('next-week')!), isTrue, reason: 'nobody picked: the group teaches it');
    expect(data.nextSession(now, where: store.runs)!.id, 'next-week');
  });

  test('attendance the server refuses for good does not hold back the rest', () async {
    final repo = seededInstructorRepo(me: me, today: today);
    final store = await openStore(repo);
    repo.offline = true;
    await store.saveAttendance('last-week', {'adam': AttendanceStatus.present});
    await store.saveAttendance('today', {'adam': AttendanceStatus.absent});
    expect(store.pending, hasLength(2));
    repo.offline = false;
    repo.refused.add('last-week');
    expect(await store.sendNow(), isTrue);
    expect(store.pending, isEmpty);
    expect(repo.attendance['today/adam']!.status, AttendanceStatus.absent);
    expect(repo.attendance.containsKey('last-week/adam'), isFalse);
  });

  test('a category supervisor sees the groups they supervise and plans, without taking attendance', () async {
    final repo = seededInstructorRepo(me: me, today: today);
    repo.groups
      ..[0] = repo.groups[0].withInstructors(['sara'], supervisors: ['nadia'])
      ..add(
        const Group(id: 'knights', name: 'فئة الفرسان', logoLetter: 'ف', logoColor: 2).withInstructors([me]),
      );
    final store = InstructorStore(repo, await SharedPreferences.getInstance(), retryEvery: null, clock: () => now);
    await store.start('nadia', view: StaffView.supervising);
    expect([for (final g in store.data.groups) g.id], ['stars']);
    expect(store.schedules, isTrue);
    expect(store.canRecord(store.data.session('today')!), isFalse);

    await store.addObservation('today', 'آدم كان متعباً');
    expect((await store.recentObservations()).single.body, 'آدم كان متعباً');
  });
}
