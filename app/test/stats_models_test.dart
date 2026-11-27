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

  group('follow-up indicators', () {
    // Adam: 4 sessions in the last 30 days, absent 3 times, late never. Omar: late 3 times.
    StatsData followUp({List<StatActivity> activities = const [], Set<String> absences = const {}}) => StatsData(
      groups: const [
        Group(id: 'stars', name: 'النجوم', logoLetter: 'ن', logoColor: 1, instructorIds: ['yassine']),
        Group(id: 'knights', name: 'الفرسان', logoLetter: 'ف', logoColor: 2, instructorIds: ['hamza']),
      ],
      staffNames: const {'yassine': 'ياسين', 'hamza': 'حمزة', 'sara': 'سارة'},
      children: const [
        StatChild(id: 'adam', fullName: 'آدم', groupId: 'stars'),
        StatChild(id: 'omar', fullName: 'عمر', groupId: 'stars'),
      ],
      sessions: [
        s('dec', 'stars', DateTime(2026, 12, 12)),
        s('jan', 'stars', DateTime(2027, 1, 30)),
        s('feb6', 'stars', DateTime(2027, 2, 6)),
        s('feb13', 'stars', DateTime(2027, 2, 13)),
        s('feb20', 'stars', DateTime(2027, 2, 20)),
        StatSession(id: 'k-feb18', groupId: 'knights', date: DateTime(2027, 2, 18), start: 600, end: 660),
        StatSession(
          id: 'k-feb19',
          groupId: 'knights',
          date: DateTime(2027, 2, 19),
          start: 600,
          end: 660,
          instructorIds: const ['sara'],
        ),
        s('feb27', 'stars', DateTime(2027, 2, 27)),
      ],
      marks: [
        m('dec', 'adam', AttendanceStatus.present),
        m('dec', 'omar', AttendanceStatus.present),
        for (final id in ['jan', 'feb6', 'feb13', 'feb20']) ...[
          m(id, 'adam', id == 'feb6' ? AttendanceStatus.present : AttendanceStatus.absent),
          m(id, 'omar', id == 'jan' ? AttendanceStatus.present : AttendanceStatus.late),
        ],
      ],
      activities: activities,
      absences: absences,
      seasonStart: DateTime(2026, 11, 1),
    );

    test('children over 25% absence in the period, and repeated absence and lateness in 30 days', () {
      final stats = followUp().compute(StatsPeriod.term, now);
      expect(stats.overThreshold.map((c) => (c.child.id, c.count, c.of)), [('adam', 3, 5)]);
      expect(stats.repeatedAbsence.map((c) => (c.child.id, c.count)), [('adam', 3)]);
      expect(stats.repeatedLate.map((c) => (c.child.id, c.count)), [('omar', 3)]);
      // This month only feb6, feb13, feb20 are held: Adam missed 2 of 3.
      expect(followUp().compute(StatsPeriod.month, now).overThreshold.single.of, 3);
    });

    test('a حصة replaced by a نشاط نوعي is left out everywhere', () {
      final camp = StatActivity(
        groupIds: const ['stars'],
        startsAt: DateTime(2027, 2, 13, 8),
        endsAt: DateTime(2027, 2, 14, 18),
      );
      final stats = followUp(activities: [camp]).compute(StatsPeriod.month, now);
      expect(stats.repeatedAbsence, isEmpty, reason: 'feb13 no longer counts: 2 absences');
      expect(stats.repeatedLate, isEmpty);
      final stars = stats.groups.firstWhere((g) => g.group.id == 'stars');
      expect((stars.sessions, stars.programmed), (2, 3), reason: 'feb6, feb20 held; feb27 still to come');
    });

    test('programmed counts the whole period, completed the held ones with attendance', () {
      final stats = followUp().compute(StatsPeriod.month, now);
      final stars = stats.groups.firstWhere((g) => g.group.id == 'stars');
      final knights = stats.groups.firstWhere((g) => g.group.id == 'knights');
      expect((stars.recorded, stars.programmed), (3, 4));
      expect((knights.recorded, knights.programmed), (0, 2));
      expect(stats.programmed, 6);
    });

    test('instructors who did not record: the picked ones, else the فئة\'s, not those who said they were absent', () {
      expect(
        followUp()
            .compute(StatsPeriod.month, now)
            .unrecorded
            .map((g) => (g.name, g.sessions.map((s) => s.id).join(','))),
        [('حمزة', 'k-feb18'), ('سارة', 'k-feb19')],
      );
      final excused = followUp(absences: {'k-feb19/sara'}).compute(StatsPeriod.month, now);
      expect(excused.unrecorded.map((g) => g.personId), ['hamza']);
    });

    test('the monthly trend runs from the season start and says if it improves', () {
      final stats = followUp().compute(StatsPeriod.month, now);
      expect(stats.months.map((x) => x.month), [
        DateTime(2026, 11),
        DateTime(2026, 12),
        DateTime(2027, 1),
        DateTime(2027, 2),
      ]);
      expect(stats.months.map((x) => x.rate), [null, 1.0, 0.5, 4 / 6]);
      expect(stats.months[3].sessions, 3);
      expect(stats.monthChange, 17);
    });
  });
}
