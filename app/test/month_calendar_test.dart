import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raeed_os/instructor/models.dart';
import 'package:raeed_os/parent/parent_models.dart';
import 'package:raeed_os/widgets/month_calendar.dart';

import 'activities_test.dart' show camp;
import 'fake_instructor.dart';
import 'fake_stage4.dart';
import 'instructor_screens_test.dart' show openInstructor, tab, today, me;
import 'parent_screens_test.dart' show openParent, seededParent;

Future<void> tapKey(WidgetTester tester, String key) async {
  await tester.ensureVisible(find.byKey(Key(key)));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => scheduleMode.value = ScheduleMode.list);

  testWidgets('a parent switches to the month and taps the days of a two-day مبيت', (tester) async {
    final data = seededParent();
    final saturday = DateTime(2027, 2, 13);
    final repo = FakeParentRepository()
      ..data = ParentSnapshot(
        children: data.children,
        sessions: data.sessions,
        staffNames: data.staffNames,
        parents: data.parents,
        activities: [
          SpecialActivity(
            id: 'camp',
            kind: ActivityKind.overnight,
            title: 'مبيت الحفظ',
            place: 'جمعية سماء',
            startDate: saturday,
            start: 9 * 60,
            endDate: saturday.add(const Duration(days: 1)),
            end: 12 * 60,
            groupIds: const ['stars'],
          ),
        ],
      );
    await openParent(tester, repo: repo);
    expect(find.byKey(const Key('month-calendar')), findsNothing);
    await tapKey(tester, 'mode-month');

    expect(find.byKey(const Key('month-calendar')), findsOneWidget);
    expect(find.text('فبراير 2027'), findsOneWidget);
    // The مبيت crosses the end of the week (Saturday 13 to Sunday 14): one bar on each row.
    expect(find.byKey(const Key('calendar-bar-camp')), findsNWidgets(2));
    // Today (Wednesday 10) is picked: its changed session is listed under the grid.
    expect(find.byKey(const Key('parent-session-wed')), findsOneWidget);
    // Saturday's sessions are red dots: the مبيت replaces them.
    expect(find.byKey(const Key('calendar-dot-sat')), findsOneWidget);

    await tapKey(tester, 'calendar-day-2027-02-13');
    expect(find.byKey(const Key('activity-camp-2027-02-13')), findsOneWidget);
    expect(find.byKey(const Key('parent-replaced-sat')), findsOneWidget);

    await tapKey(tester, 'calendar-day-2027-02-14');
    expect(find.byKey(const Key('activity-camp-2027-02-14')), findsOneWidget);
    expect(find.textContaining('اليوم 2 من 2'), findsOneWidget);

    await tapKey(tester, 'calendar-next-month');
    expect(find.text('مارس 2027'), findsOneWidget);

    // Back to the list of what is coming.
    await tester.drag(find.byType(ListView).first, const Offset(0, 3000));
    await tester.pumpAndSettle();
    await tapKey(tester, 'mode-list');
    expect(find.byKey(const Key('month-calendar')), findsNothing);
  });

  testWidgets('an instructor sees the camp and the session it replaces on the month', (tester) async {
    final repo = seededInstructorRepo(me: me, today: today);
    repo.activities.add(camp());
    await openInstructor(tester, repo: repo);
    await tab(tester, 'الحصص');
    await tapKey(tester, 'mode-month');

    expect(find.byKey(const Key('week-label')), findsNothing);
    expect(find.byKey(const Key('calendar-bar-camp')), findsOneWidget, reason: 'Friday and Saturday, one week row');
    expect(find.byKey(const Key('activity-camp-2027-02-06')), findsOneWidget, reason: 'today is picked');
    expect(find.byKey(const Key('replaced-by-today')), findsOneWidget);

    await tapKey(tester, 'calendar-day-2027-02-05');
    expect(find.byKey(const Key('activity-camp-2027-02-05')), findsOneWidget);
    expect(find.byKey(const Key('replaced-by-today')), findsNothing);

    // The choice stays for the other schedules.
    await tab(tester, 'فئاتي');
    expect(scheduleMode.value, ScheduleMode.month);
  });
}
