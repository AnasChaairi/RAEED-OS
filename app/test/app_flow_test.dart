import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raeed_os/app.dart';
import 'package:raeed_os/auth/app_session.dart';
import 'package:raeed_os/roles/app_role.dart';
import 'package:raeed_os/instructor/instructor_store.dart';
import 'package:raeed_os/setup/setup_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_auth.dart';
import 'fake_instructor.dart';
import 'fake_setup.dart';
import 'fake_stage4.dart';

const advisorPhone = '212691015402';
const multiPhone = '212612345678';
const newPhone = '212698765432';

FakeAuthRepository fakeAuth() => FakeAuthRepository(accounts: {
      advisorPhone: FakeAccount(fullName: 'أنس', password: 'secret-pass', roles: {AppRole.advisor}),
      multiPhone: FakeAccount(
        fullName: 'ياسين',
        password: 'secret-pass',
        roles: {AppRole.instructor, AppRole.parent},
      ),
      newPhone: FakeAccount(
        fullName: 'كريم بنعلي',
        password: 'temp1234',
        roles: {AppRole.parent},
        mustChangePassword: true,
      ),
    });

Future<AppSession> pumpApp(WidgetTester tester, FakeAuthRepository auth, {Map<String, Object> prefs = const {}}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final preferences = await SharedPreferences.getInstance();
  final session = AppSession(auth, preferences);
  final extra = stage4(preferences);
  await tester.pumpWidget(RaeedApp(
    session: session,
    setup: SetupStore(FakeSetupRepository()),
    instructor: InstructorStore(FakeInstructorRepository(), preferences, retryEvery: null),
    parent: extra.parent,
    stats: extra.stats,
    profiles: extra.profiles,
    push: extra.push,
  ));
  await session.start();
  await tester.pumpAndSettle();
  return session;
}

Future<void> signIn(WidgetTester tester, String phone, String password) async {
  await tester.enterText(find.byKey(const Key('phone')), phone);
  await tester.enterText(find.byKey(const Key('password')), password);
  await tester.tap(find.byKey(const Key('sign-in')));
  await tester.pumpAndSettle();
}

List<String> tabLabels(WidgetTester tester) => tester
    .widgetList<NavigationDestination>(find.byType(NavigationDestination))
    .map((d) => d.label)
    .toList();

void main() {
  testWidgets('the whole app is right to left', (tester) async {
    await pumpApp(tester, fakeAuth());
    expect(Directionality.of(tester.element(find.text('مرحباً بك في رائد'))), TextDirection.rtl);
  });

  testWidgets('an advisor signs in with 06… and sees the advisor tabs', (tester) async {
    await pumpApp(tester, fakeAuth());
    await signIn(tester, '06 91 01 54 02', 'secret-pass');

    expect(tabLabels(tester), ['الإحصائيات', 'الحصص', 'الفئات', 'الأطفال', 'الإعدادات']);
    expect(find.text('مشرف · أنس'), findsOneWidget);

    await tester.tap(find.text('الأطفال'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'الأطفال'), findsOneWidget);
  });

  testWidgets('a wrong password shows a message and stays on sign-in', (tester) async {
    await pumpApp(tester, fakeAuth());
    await signIn(tester, '+212691015402', 'nope');
    expect(find.textContaining('رقم الهاتف أو كلمة المرور غير صحيحة'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('a number that is not Moroccan is caught before sending', (tester) async {
    final auth = fakeAuth();
    await pumpApp(tester, auth);
    await signIn(tester, '12345', 'secret-pass');
    expect(find.textContaining('رقم الهاتف غير صحيح'), findsOneWidget);
    expect(auth.signedInAs, isNull);
  });

  testWidgets('no connection is explained', (tester) async {
    final auth = fakeAuth()..offline = true;
    await pumpApp(tester, auth);
    await signIn(tester, '0691015402', 'secret-pass');
    expect(find.textContaining('لا يوجد اتصال بالإنترنت'), findsOneWidget);
  });

  testWidgets('first sign-in forces a new password, then opens the app', (tester) async {
    final auth = fakeAuth();
    await pumpApp(tester, auth);
    await signIn(tester, '0698765432', 'temp1234');
    expect(find.text('إنشاء كلمة المرور'), findsOneWidget);

    // Too short, then not matching: nothing is sent.
    await tester.enterText(find.byKey(const Key('new-password')), 'short');
    await tester.enterText(find.byKey(const Key('repeat-password')), 'short');
    await tester.tap(find.byKey(const Key('save-password')));
    await tester.pumpAndSettle();
    expect(find.textContaining('8 أحرف على الأقل'), findsWidgets);
    await tester.enterText(find.byKey(const Key('new-password')), 'my-new-pass');
    await tester.enterText(find.byKey(const Key('repeat-password')), 'my-new-pass2');
    await tester.tap(find.byKey(const Key('save-password')));
    await tester.pumpAndSettle();
    expect(find.text('كلمتا المرور غير متطابقتين'), findsOneWidget);
    expect(auth.changePasswordCalls, 0);

    await tester.enterText(find.byKey(const Key('repeat-password')), 'my-new-pass');
    await tester.tap(find.byKey(const Key('save-password')));
    await tester.pumpAndSettle();
    expect(auth.changePasswordCalls, 1);
    expect(auth.accounts[newPhone]!.mustChangePassword, isFalse);
    expect(tabLabels(tester), ['جدول أطفالي', 'حسابي']);
  });

  testWidgets('several roles: choose one, then switch from the avatar', (tester) async {
    await pumpApp(tester, fakeAuth());
    await signIn(tester, '0612345678', 'secret-pass');
    expect(find.text('اختر الحساب'), findsOneWidget);

    await tester.tap(find.byKey(const Key('role-parent')));
    await tester.tap(find.byKey(const Key('continue')));
    await tester.pumpAndSettle();
    expect(tabLabels(tester), ['جدول أطفالي', 'حسابي']);

    await tester.tap(find.byKey(const Key('account')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('role-instructor')));
    await tester.pumpAndSettle();
    expect(tabLabels(tester), ['اليوم', 'الحصص', 'فئاتي', 'التنبيهات']);
  });

  testWidgets('the last role is remembered on the next start', (tester) async {
    final auth = fakeAuth()..signedInAs = multiPhone;
    await pumpApp(tester, auth, prefs: {'last_role': 'instructor'});
    expect(tabLabels(tester), ['اليوم', 'الحصص', 'فئاتي', 'التنبيهات']);
  });

  testWidgets('a saved session skips sign-in', (tester) async {
    final auth = fakeAuth()..signedInAs = advisorPhone;
    await pumpApp(tester, auth);
    expect(tabLabels(tester), hasLength(5));
  });

  testWidgets('sign out returns to sign-in', (tester) async {
    final auth = fakeAuth()..signedInAs = advisorPhone;
    await pumpApp(tester, auth);
    await tester.tap(find.byKey(const Key('account')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sign-out')));
    await tester.pumpAndSettle();
    expect(find.text('مرحباً بك في رائد'), findsOneWidget);
    expect(auth.signedInAs, isNull);
  });

  testWidgets('an account with no profile row is signed out with a message', (tester) async {
    final auth = fakeAuth();
    auth.accounts['212611111111'] =
        FakeAccount(fullName: 'x', password: 'secret-pass', roles: {}, hasProfile: false);
    await pumpApp(tester, auth);
    await signIn(tester, '0611111111', 'secret-pass');
    expect(find.textContaining('غير مسجّل في الأكاديمية'), findsOneWidget);
    expect(auth.signedInAs, isNull);
  });

  testWidgets('an account with no role is told to contact the advisor', (tester) async {
    final auth = fakeAuth();
    auth.accounts['212611111111'] = FakeAccount(fullName: 'x', password: 'secret-pass', roles: {});
    await pumpApp(tester, auth);
    await signIn(tester, '0611111111', 'secret-pass');
    expect(find.textContaining('لم يُحدَّد له دور'), findsOneWidget);
  });
}
