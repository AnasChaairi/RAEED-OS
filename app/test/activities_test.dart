import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raeed_os/instructor/models.dart';
import 'package:raeed_os/parent/parent_models.dart';
import 'package:raeed_os/roles/app_role.dart';

import 'fake_instructor.dart';
import 'fake_stage4.dart';
import 'instructor_screens_test.dart' show openInstructor, tab, today, me;
import 'parent_screens_test.dart' show openParent, seededParent;

/// A camp of فئة النجوم from yesterday to this evening, over today's 10:00 session (today
/// is Saturday 6 February 2027, the last day of the week).
SpecialActivity camp({String id = 'camp', bool cancelled = false, List<String> groups = const ['stars']}) =>
    SpecialActivity(
      id: id,
      kind: ActivityKind.camp,
      title: 'مخيم الربيع',
      place: 'غابة المعمورة',
      startDate: today.subtract(const Duration(days: 1)),
      start: 9 * 60,
      endDate: today,
      end: 17 * 60,
      cancelled: cancelled,
      groupIds: groups,
    );

void main() {
  group('replaces', () {
    final s = Session(id: 's', groupId: 'stars', title: 'حصة', date: DateTime(2027, 2, 6), start: 600, end: 690);

    test('a planned activity of the same فئة that overlaps the session', () {
      expect(camp().replaces(s), isTrue);
      expect(camp(cancelled: true).replaces(s), isFalse, reason: 'cancelled: the session takes place');
      expect(camp(groups: ['buds']).replaces(s), isFalse, reason: 'another فئة');
    });

    test('touching the session is not overlapping it', () {
      final before = SpecialActivity(
        id: 'b',
        kind: ActivityKind.outing,
        title: 'خرجة',
        place: 'الحديقة',
        startDate: DateTime(2027, 2, 6),
        start: 8 * 60,
        endDate: DateTime(2027, 2, 6),
        end: 600,
        groupIds: const ['stars'],
      );
      expect(before.replaces(s), isFalse);
      expect(before.dayCount, 1);
      expect(camp().dayCount, 2);
      expect(camp().dayNumber(today), 2);
    });

    test('a custom kind shows its own name', () {
      final a = SpecialActivity(
        id: 'c',
        kind: ActivityKind.custom,
        customLabel: 'زيارة',
        title: 'زيارة المتحف',
        place: 'الرباط',
        startDate: _day,
        start: 600,
        endDate: _day,
        end: 700,
      );
      expect(a.kindLabel, 'زيارة');
      expect(a.replacesLabel, 'ملغاة بسبب: ⭐ زيارة · زيارة المتحف');
      expect(SpecialActivity.fromJson(a.toJson()).kindLabel, 'زيارة');
    });
  });

  testWidgets('an instructor sees the camp and today\'s session cancelled because of it', (tester) async {
    final repo = seededInstructorRepo(me: me, today: today);
    repo.activities.add(camp());
    await openInstructor(tester, repo: repo);
    expect(find.byKey(const Key('today-hero')), findsNothing, reason: 'no attendance on a replaced session');
    expect(find.text('أنشطة نوعية قادمة'), findsOneWidget);

    await tab(tester, 'الحصص');
    expect(find.byKey(const Key('activity-camp-2027-02-05')), findsOneWidget);
    expect(find.byKey(const Key('activity-camp-2027-02-06')), findsOneWidget, reason: 'shown on each of its days');
    expect(find.textContaining('اليوم 2 من 2'), findsOneWidget);
    expect(find.byKey(const Key('replaced-by-today')), findsOneWidget);
    expect(find.text('ملغاة بسبب: ⛺ مخيم · مخيم الربيع'), findsOneWidget);

    await tester.tap(find.byKey(const Key('replaced-by-today')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('session-replaced')), findsOneWidget);
    expect(find.byKey(const Key('take-attendance')), findsNothing);
    expect(find.byKey(const Key('report-absence')), findsNothing);
  });

  testWidgets('an instructor takes the attendance of the camp', (tester) async {
    final repo = seededInstructorRepo(me: me, today: today);
    repo.activities.add(camp());
    await openInstructor(tester, repo: repo);
    await tab(tester, 'الحصص');
    await tester.tap(find.byKey(const Key('activity-camp-2027-02-06')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('edit-activity')), findsNothing, reason: 'instructors do not plan');
    expect(find.byKey(const Key('replaced-today')), findsOneWidget);
    await tester.tap(find.byKey(const Key('activity-attendance')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('activity-status-omar-absent')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('save-activity-attendance')));
    await tester.pumpAndSettle();
    expect(repo.calls, contains('saveActivityAttendance camp 3'));
    expect(repo.activityAttendance['camp/omar']!.status, AttendanceStatus.absent);
    expect(find.text('تعديل الحضور (3)'), findsOneWidget);
  });

  testWidgets('a category supervisor sees the replaced sessions when editing, and cancels the camp', (tester) async {
    final repo = seededInstructorRepo(me: 'someone-else', today: today);
    repo.groups[0] = repo.groups[0].withInstructors(['sara'], supervisors: [me]);
    repo.activities.add(camp());
    await openInstructor(tester, repo: repo, role: AppRole.supervisor);
    expect(find.byKey(const Key('new-plan')), findsNothing, reason: 'planned from فئتي, under الحصص');

    await tester.tap(find.byKey(const Key('activity-camp-2027-02-06')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('edit-activity')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('activity-title')), 'مخيم الصيف');
    await tester.dragUntilVisible(
      find.byKey(const Key('activity-conflicts')),
      find.byType(ListView).last,
      const Offset(0, -300),
    );
    expect(find.textContaining('ستظهر حصة واحدة ملغاة بسببه'), findsOneWidget);
    await tester.dragUntilVisible(
      find.byKey(const Key('save-activity')),
      find.byType(ListView).last,
      const Offset(0, -300),
    );
    await tester.tap(find.byKey(const Key('save-activity')));
    await tester.pumpAndSettle();
    expect(repo.calls, contains('updateActivity camp مخيم الصيف'));

    await tester.dragUntilVisible(
      find.byKey(const Key('cancel-activity')),
      find.byType(ListView).last,
      const Offset(0, -300),
    );
    await tester.tap(find.byKey(const Key('cancel-activity')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('cancel-activity-reason')), 'الطقس');
    await tester.tap(find.byKey(const Key('confirm-cancel-activity')));
    await tester.pumpAndSettle();
    expect(repo.calls, contains('cancelActivity camp الطقس'));
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('replaced-by-today')), findsNothing, reason: 'the session is back');
  });

  testWidgets('a supervisor cannot change an activity that also covers a فئة they do not supervise', (tester) async {
    final repo = seededInstructorRepo(me: 'someone-else', today: today);
    repo.groups[0] = repo.groups[0].withInstructors(['sara'], supervisors: [me]);
    repo.activities.add(camp(groups: ['stars', 'buds']));
    await openInstructor(tester, repo: repo, role: AppRole.supervisor);
    await tester.tap(find.byKey(const Key('activity-camp-2027-02-06')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('edit-activity')), findsNothing);
    expect(find.byKey(const Key('delete-activity')), findsNothing);
  });

  testWidgets('a parent sees the coming camp on top and the session it replaces', (tester) async {
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
            details: 'غطاء ووسادة',
            startDate: saturday,
            start: 9 * 60,
            endDate: saturday.add(const Duration(days: 1)),
            end: 12 * 60,
            groupIds: const ['stars'],
          ),
        ],
      );
    await openParent(tester, repo: repo);
    expect(find.byKey(const Key('activity-banner')), findsOneWidget);
    expect(find.text('نشاط قادم · بعد 3 أيام'), findsOneWidget);
    expect(find.textContaining('يعوّض حصتين'), findsOneWidget, reason: 'the 10:00 session and the trip');
    await tester.scrollUntilVisible(find.byKey(const Key('parent-replaced-sat')), 300);
    expect(find.text('ملغاة بسبب: 🌙 مبيت · مبيت الحفظ'), findsWidgets);

    await tester.drag(find.byType(ListView).first, const Offset(0, 3000));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('activity-banner')));
    await tester.pumpAndSettle();
    expect(find.text('غطاء ووسادة'), findsOneWidget);
    expect(find.byKey(const Key('activity-to-calendar')), findsOneWidget);
  });
}

final _day = DateTime(2027, 3, 1);
