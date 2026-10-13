import 'package:flutter_test/flutter_test.dart';
import 'package:raeed_os/advisor/stats_models.dart';
import 'package:raeed_os/instructor/models.dart';
import 'package:raeed_os/setup/models.dart';

// Saturday 20 February 2027, 18:00.
final now = DateTime(2027, 2, 20, 18);

StatSession s(String id, String group, DateTime date, {bool cancelled = false}) =>
    StatSession(id: id, groupId: group, date: date, end: 11 * 60, cancelled: cancelled);

StatMark m(String session, String child, AttendanceStatus status) =>
    StatMark(sessionId: session, childId: child, status: status);

StatsData seeded() => StatsData(
  groups: const [
    Group(id: 'stars', name: 'النجوم', logoLetter: 'ن', logoColor: 1, instructorIds: ['yassine']),
    Group(id: 'knights', name: 'الفرسان', logoLetter: 'ف', logoColor: 2, instructorIds: ['hamza', 'sara']),
    Group(id: 'new', name: 'الجدد', logoLetter: 'ج', logoColor: 3),
  ],
  staffNames: const {'yassine': 'ياسين', 'hamza': 'حمزة', 'sara': 'سارة'},
  instructorCount: 3,
  children: const [
    StatChild(id: 'adam', fullName: 'آدم', groupId: 'stars'),
    StatChild(id: 'omar', fullName: 'عمر', groupId: 'stars'),
    StatChild(id: 'reda', fullName: 'رضا', groupId: 'knights'),
  ],
  sessions: [
    s('jan', 'stars', DateTime(2027, 1, 30)),
    s('feb6', 'stars', DateTime(2027, 2, 6)),
    s('feb13', 'stars', DateTime(2027, 2, 13)),
    s('feb20', 'stars', DateTime(2027, 2, 20)),
    s('k-feb20', 'knights', DateTime(2027, 2, 20)),
    s('k-feb18', 'knights', DateTime(2027, 2, 18)),
    s('k-cancel', 'knights', DateTime(2027, 2, 17), cancelled: true),
  ],
  marks: [
    m('jan', 'adam', AttendanceStatus.absent),
    m('feb6', 'adam', AttendanceStatus.present),
    m('feb6', 'omar', AttendanceStatus.late),
    m('feb20', 'adam', AttendanceStatus.absent),
    m('feb20', 'omar', AttendanceStatus.present),
    m('k-feb20', 'reda', AttendanceStatus.excused),
  ],
  openAlertGroups: const ['knights'],
  termStart: DateTime(2027, 1, 5),
);

void main() {
  test('this month counts late as attended and leaves cancelled sessions out', () {
    final stats = seeded().compute(StatsPeriod.month, now);
    expect(stats.from, DateTime(2027, 2));
    // feb6: 2 of 2, feb20: 1 of 2, k-feb20: 0 of 1.
    expect(stats.rate, 3 / 5);
    expect(stats.sessionsHeld, 5);
    expect(stats.sessionsWithoutAttendance, 2, reason: 'feb13 and k-feb18');
    expect(stats.openAlerts, 1);
    expect([stats.groupCount, stats.instructorCount, stats.childCount], [3, 3, 3]);
  });

  test('groups are sorted weakest first, with their instructors and recorded sessions', () {
    final stats = seeded().compute(StatsPeriod.month, now);
    expect(stats.groups.map((g) => g.group.id), ['knights', 'stars', 'new']);
    final knights = stats.groups.first;
    expect(knights.rate, 0);
    expect(knights.instructors, ['حمزة', 'سارة']);
    expect((knights.recorded, knights.sessions, knights.openAlerts), (1, 2, 1));
    expect(stats.groups.last.rate, isNull);
  });

  test('the week and the term cover their own days', () {
    final data = seeded();
    expect(data.compute(StatsPeriod.week, now).from, DateTime(2027, 2, 14));
    expect(data.compute(StatsPeriod.week, now).rate, 1 / 3);
    expect(data.compute(StatsPeriod.term, now).rate, 3 / 6);
  });

  test('the trend has five weeks, oldest first, empty weeks blank', () {
    final weeks = seeded().compute(StatsPeriod.month, now).weeks;
    expect(weeks, [null, 0.0, 1.0, null, 1 / 3]);
  });

  test('a child rate for the period', () {
    final data = seeded();
    expect(data.childRate('adam', StatsPeriod.month, now), 0.5);
    expect(data.childRate('adam', StatsPeriod.term, now), 1 / 3);
    expect(data.childRate('reda', StatsPeriod.week, now), 0);
  });

  test('a session that has not ended yet is not counted', () {
    final stats = seeded().compute(StatsPeriod.week, DateTime(2027, 2, 20, 10, 30));
    expect(stats.sessionsHeld, 1, reason: 'only k-feb18 has ended');
  });
}
