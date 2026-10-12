import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raeed_os/app.dart';
import 'package:raeed_os/auth/app_session.dart';
import 'package:raeed_os/instructor/instructor_store.dart';
import 'package:raeed_os/instructor/models.dart';
import 'package:raeed_os/roles/app_role.dart';
import 'package:raeed_os/setup/setup_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_auth.dart';
import 'fake_instructor.dart';
import 'fake_setup.dart';

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

/// Signs in as an instructor of فئة النجوم on a tall phone. Keeps what is already on the
/// phone unless [fresh].
Future<Opened> openInstructor(
  WidgetTester tester, {
  FakeInstructorRepository? repo,
  bool fresh = true,
  bool offline = false,
}) async {
  tester.view.physicalSize = const Size(1170, 2600);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  if (fresh) SharedPreferences.setMockInitialValues({});
  final auth = FakeAuthRepository(
    accounts: {
      me: FakeAccount(fullName: 'ياسين', password: 'secret-pass', roles: {AppRole.instructor}),
    },
    signedInAs: me,
  )..offline = offline;
  repo ??= seededInstructorRepo(me: me, today: today);
  repo.offline = offline;
  final prefs = await SharedPreferences.getInstance();
  final session = AppSession(auth, prefs);
  final store = InstructorStore(repo, prefs, retryEvery: null, clock: () => now);
  await tester.pumpWidget(RaeedApp(session: session, setup: SetupStore(FakeSetupRepository()), instructor: store));
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

  testWidgets('editing a weekly session asks this one or all upcoming', (tester) async {
    final o = await openInstructor(tester);
    await tab(tester, 'الحصص');
    await tester.tap(find.text('فئة النجوم · حفظ سورة الملك'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('edit-session')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('session-title')), 'حفظ سورة النبأ');
    await tester.pump();
    expect(find.textContaining('تغيير موعد · آدم'), findsOneWidget, reason: 'the parent notification preview');
    await tester.tap(find.byKey(const Key('save-session')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('scope-upcoming')));
    await tester.pumpAndSettle();
    expect(o.repo.calls, contains('updateSessions today upcoming'));
    expect(o.repo.sessions.where((s) => s.title == 'حفظ سورة النبأ').map((s) => s.id), ['today', 'next-week']);
  });

  testWidgets('a session is cancelled with a reason', (tester) async {
    final o = await openInstructor(tester);
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
}
