import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raeed_os/app.dart';
import 'package:raeed_os/auth/app_session.dart';
import 'package:raeed_os/instructor/instructor_store.dart';
import 'package:raeed_os/instructor/models.dart';
import 'package:raeed_os/instructor/session_form_screen.dart';
import 'package:raeed_os/roles/app_role.dart';
import 'package:raeed_os/setup/models.dart';
import 'package:raeed_os/setup/setup_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_auth.dart';
import 'fake_instructor.dart';
import 'fake_setup.dart';
import 'fake_stage4.dart';

const me = '212612345678';
final now = DateTime(2027, 2, 6, 9, 41);
final today = DateTime(2027, 2, 6);

class Opened {
  Opened(this.repo, this.store, this.auth, this.session);

  final FakeInstructorRepository repo;
  final InstructorStore store;
  final FakeAuthRepository auth;
  final AppSession session;
}

/// Signs in as an instructor of فئة النجوم on a tall phone, or as an advisor with [role].
/// Keeps what is already on the phone unless [fresh].
Future<Opened> openInstructor(
  WidgetTester tester, {
  FakeInstructorRepository? repo,
  bool fresh = true,
  bool offline = false,
  AppRole role = AppRole.instructor,
}) async {
  tester.view.physicalSize = const Size(1170, 2600);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  if (fresh) SharedPreferences.setMockInitialValues({});
  final auth = FakeAuthRepository(
    accounts: {
      me: FakeAccount(fullName: 'ياسين', password: 'secret-pass', roles: {role}),
    },
    signedInAs: me,
  )..offline = offline;
  repo ??= seededInstructorRepo(me: me, today: today);
  repo.offline = offline;
  final prefs = await SharedPreferences.getInstance();
  final session = AppSession(auth, prefs);
  final store = InstructorStore(repo, prefs, retryEvery: null, clock: () => now);
  final extra = stage4(prefs, clock: () => now);
  await tester.pumpWidget(
    RaeedApp(
      session: session,
      setup: SetupStore(FakeSetupRepository()),
      instructor: store,
      parent: extra.parent,
      stats: extra.stats,
      profiles: extra.profiles,
      push: extra.push,
    ),
  );
  await session.start();
  await tester.pumpAndSettle();
  return Opened(repo, store, auth, session);
}

Future<void> tab(WidgetTester tester, String label) async {
  await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text(label)));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Today opens on the session about to start, and attendance starts at all present', (tester) async {
    final o = await openInstructor(tester);
    expect(find.byKey(const Key('today-hero')), findsOneWidget);
    expect(find.textContaining('تبدأ بعد 19 دقيقة'), findsOneWidget);

    await tester.tap(find.byKey(const Key('hero-attendance')));
    await tester.pumpAndSettle();
    expect(find.text('حاضر 3'), findsOneWidget);
    expect(find.text('لم يُسجَّل بعد · يراه مؤطرو الفئة الآخرون بعد الحفظ'), findsOneWidget);

    await tester.tap(find.byKey(const Key('status-adam-absent')));
    await tester.tap(find.byKey(const Key('status-omar-late')));
    await tester.pump();
    expect(find.text('حاضر 1'), findsOneWidget);
    expect(find.text('غائب 1'), findsOneWidget);
    expect(find.text('متأخر 1'), findsOneWidget);

    await tester.tap(find.byKey(const Key('save-attendance')));
    await tester.pumpAndSettle();
    expect(find.text('تم حفظ الحضور ✓'), findsOneWidget);
    expect(find.textContaining('سجّله أنت'), findsOneWidget);
    expect(o.repo.attendance['today/adam']!.status, AttendanceStatus.absent);
    expect(o.repo.attendance['today/youssef']!.status, AttendanceStatus.present);
  });

  testWidgets('offline, the sheet is saved on the phone and sent when the connection is back', (tester) async {
    final o = await openInstructor(tester);
    o.repo.offline = true;
    await o.store.refresh();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('offline-banner')), findsOneWidget);

    await tester.tap(find.byKey(const Key('hero-attendance')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('status-adam-absent')));
    await tester.tap(find.byKey(const Key('save-attendance')));
    await tester.pumpAndSettle();
    expect(find.text('تم الحفظ على الهاتف ✓ سيُرسل عند عودة الاتصال.'), findsOneWidget);
    expect(find.textContaining('في انتظار الإرسال'), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('في الانتظار'), findsOneWidget);
    expect(o.repo.attendance, isEmpty);

    o.repo.offline = false;
    await tester.tap(find.byKey(const Key('send-now')));
    await tester.pumpAndSettle();
    expect(find.text('أُرسل ✓'), findsOneWidget);
    expect(find.byKey(const Key('offline-banner')), findsNothing);
    expect(o.repo.attendance['today/adam']!.status, AttendanceStatus.absent);
  });

  testWidgets('the app opens offline from what is on the phone', (tester) async {
    await openInstructor(tester);
    await openInstructor(tester, fresh: false, offline: true);
    expect(find.byKey(const Key('offline-banner')), findsOneWidget);
    expect(find.byKey(const Key('today-hero')), findsOneWidget);
  });

  testWidgets('two absences in a row: the alert is followed up and closed with the reason', (tester) async {
    final o = await openInstructor(tester);
    await o.store.saveAttendance('last-week', {'adam': AttendanceStatus.absent});
    await o.store.saveAttendance('today', {'adam': AttendanceStatus.absent});
    await tester.pumpAndSettle();
    expect(find.text('آدم بنعلي · غياب حصتين'), findsOneWidget, reason: 'shown on Today');

    await tab(tester, 'التنبيهات');
    expect(find.text('30 يناير و 6 فبراير بدون عذر'), findsOneWidget);
    await tester.tap(find.text('تتبّع الآن'));
    await tester.pumpAndSettle();
    expect(find.text('ولي الأمر: كريم بنعلي'), findsOneWidget);

    await tester.tap(find.byKey(const Key('save-follow-up')));
    await tester.pumpAndSettle();
    expect(find.text('اكتب السبب الذي ذكره ولي الأمر'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('follow-up-reason')), 'مرض');
    await tester.tap(find.byKey(const Key('save-follow-up')));
    await tester.pumpAndSettle();
    expect(o.repo.calls, contains('closeAlert alert-1 مرض'));
    expect(find.text('لا توجد تنبيهات مفتوحة.'), findsOneWidget);
    expect(find.text('تم التواصل: مرض'), findsOneWidget);
  });

  testWidgets('no answer keeps the alert open, with try again', (tester) async {
    final o = await openInstructor(tester);
    await o.store.saveAttendance('last-week', {'adam': AttendanceStatus.absent});
    await o.store.saveAttendance('today', {'adam': AttendanceStatus.absent});
    await tab(tester, 'التنبيهات');
    await tester.tap(find.text('تتبّع الآن'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('outcome-no-answer')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('save-follow-up')));
    await tester.pumpAndSettle();
    expect(o.repo.calls, contains('logAttempt alert-1'));
    expect(find.text('حاول مرة أخرى'), findsOneWidget);
  });

  testWidgets('instructors see their sessions and take attendance, but do not plan them', (tester) async {
    await openInstructor(tester);
    await tab(tester, 'الحصص');
    expect(find.byKey(const Key('new-session')), findsNothing);
    await tester.tap(find.text('فئة النجوم · حفظ سورة الملك'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('take-attendance')), findsOneWidget);
    expect(find.byKey(const Key('edit-session')), findsNothing);
    expect(find.byKey(const Key('cancel-session')), findsNothing);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tab(tester, 'فئاتي');
    await tester.tap(find.text('فئة النجوم'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('الحصص').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('new-session-for-group')), findsNothing);
  });

  testWidgets('the advisor plans the sessions of every group and leaves attendance to instructors', (tester) async {
    final repo = seededInstructorRepo(me: me, today: today);
    repo.groups.add(const Group(id: 'knights', name: 'فئة الفرسان', logoLetter: 'ف', logoColor: 2, instructorIds: ['hamza']));
    repo.sessions.add(
      Session(id: 'knights-today', groupId: 'knights', title: 'رياضة', date: today, start: 960, end: 1020, floor: 0),
    );
    final o = await openInstructor(tester, repo: repo, role: AppRole.advisor);
    expect(o.store.schedules, isTrue);
    await tab(tester, 'الحصص');
    expect(find.text('فئة الفرسان · رياضة'), findsOneWidget);
    expect(find.byKey(const Key('new-session')), findsOneWidget);
    await tester.tap(find.text('فئة النجوم · حفظ سورة الملك'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('take-attendance')), findsNothing);
    expect(find.byKey(const Key('edit-session')), findsOneWidget);
    expect(find.byKey(const Key('cancel-session')), findsOneWidget);
  });

  testWidgets('editing a weekly session asks this one or all upcoming', (tester) async {
    final o = await openInstructor(tester, role: AppRole.advisor);
    await tab(tester, 'الحصص');
    await tester.tap(find.text('فئة النجوم · حفظ سورة الملك'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('edit-session')));
    await tester.pumpAndSettle();
    final form = find.descendant(of: find.byType(SessionFormScreen), matching: find.byType(Scrollable)).first;
    await tester.enterText(find.byKey(const Key('session-title')), 'حفظ سورة النبأ');
    await tester.pump();
    expect(find.textContaining('تغيير موعد · آدم'), findsOneWidget, reason: 'the parent notification preview');
    await tester.scrollUntilVisible(find.byKey(const Key('save-session')), 300, scrollable: form);
    await tester.ensureVisible(find.byKey(const Key('save-session')));
    await tester.tap(find.byKey(const Key('save-session')));
    await tester.pumpAndSettle();
    expect(find.textContaining('اختر مؤطراً واحداً على الأقل'), findsWidgets, reason: 'an instructor must run it');
    expect(o.repo.calls, isNot(contains('updateSessions today upcoming')));
    await tester.scrollUntilVisible(find.byKey(const Key('instructor-sara')), -300, scrollable: form);
    await tester.tap(find.byKey(const Key('instructor-sara')));
    await tester.pump();
    await tester.scrollUntilVisible(find.byKey(const Key('save-session')), 300, scrollable: form);
    await tester.ensureVisible(find.byKey(const Key('save-session')));
    await tester.tap(find.byKey(const Key('save-session')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('scope-upcoming')));
    await tester.pumpAndSettle();
    expect(o.repo.calls, contains('updateSessions today upcoming'));
    final edited = o.repo.sessions.where((s) => s.title == 'حفظ سورة النبأ');
    expect(edited.map((s) => s.id), ['today', 'next-week']);
    expect(edited.map((s) => s.instructorIds), [
      ['sara'],
      ['sara'],
    ]);
    await tester.pumpAndSettle();
    expect(find.text('المؤطرون: سارة الإدريسي'), findsOneWidget);
  });

  testWidgets('a session is cancelled with a reason', (tester) async {
    final o = await openInstructor(tester, role: AppRole.advisor);
    await tab(tester, 'الحصص');
    await tester.tap(find.text('فئة النجوم · حفظ سورة الملك'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('cancel-session')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('cancel-reason')), 'عطلة');
    await tester.tap(find.byKey(const Key('confirm-cancel')));
    await tester.pumpAndSettle();
    expect(o.repo.calls, contains('cancelSessions today one'));
    expect(find.text('ملغاة: عطلة'), findsOneWidget);
  });

  testWidgets('my groups shows the co-instructor and the attendance rate', (tester) async {
    final o = await openInstructor(tester);
    await o.store.saveAttendance('last-week', {'adam': AttendanceStatus.absent, 'omar': AttendanceStatus.present});
    await tab(tester, 'فئاتي');
    expect(find.textContaining('معك: سارة الإدريسي'), findsOneWidget);
    await tester.tap(find.text('فئة النجوم'));
    await tester.pumpAndSettle();
    expect(find.text('0%'), findsOneWidget);
    expect(find.text('100%'), findsOneWidget);
  });

  testWidgets('a child in my group opens the child profile', (tester) async {
    await openInstructor(tester);
    await tab(tester, 'فئاتي');
    await tester.tap(find.text('فئة النجوم'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('kid-adam')));
    await tester.pumpAndSettle();
    expect(find.text('ملف الطفل'), findsNothing);
    expect(find.text('الملاحظات مرئية لمؤطري الطفل والمشرفين فقط'), findsOneWidget);
  });
}
