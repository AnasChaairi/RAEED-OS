import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raeed_os/app.dart';
import 'package:raeed_os/auth/app_session.dart';
import 'package:raeed_os/roles/app_role.dart';
import 'package:raeed_os/setup/models.dart';
import 'package:raeed_os/instructor/instructor_store.dart';
import 'package:raeed_os/setup/setup_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_auth.dart';
import 'fake_instructor.dart';
import 'fake_setup.dart';
import 'fake_stage4.dart';

/// Signs in as an advisor on a tall phone and opens the given tab.
Future<FakeSetupRepository> openAdvisor(
  WidgetTester tester, {
  String tab = 'الإعدادات',
  Future<void> Function(FakeSetupRepository repo)? seed,
}) async {
  tester.view.physicalSize = const Size(1170, 2600);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  final auth = FakeAuthRepository(
    accounts: {'212691015402': FakeAccount(fullName: 'أنس', password: 'secret-pass', roles: {AppRole.advisor})},
    signedInAs: '212691015402',
  );
  final repo = FakeSetupRepository()
    ..addPerson('212691015402', 'أنس', '0691015402', {AppRole.advisor})
    ..addPerson('yassine', 'ياسين الإدريسي', '0611111111', {AppRole.instructor});
  await seed?.call(repo);
  final prefs = await SharedPreferences.getInstance();
  final session = AppSession(auth, prefs);
  final extra = stage4(prefs);
  await tester.pumpWidget(RaeedApp(
    session: session,
    setup: SetupStore(repo),
    instructor: InstructorStore(FakeInstructorRepository(), prefs, retryEvery: null),
    parent: extra.parent,
    stats: extra.stats,
    profiles: extra.profiles,
    push: extra.push,
  ));
  await session.start();
  await tester.pumpAndSettle();
  await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text(tab)));
  await tester.pumpAndSettle();
  return repo;
}

const stars = GroupDraft(name: 'فئة النجوم', logoLetter: 'ن', logoColor: 1);

void main() {
  testWidgets('the setup tab lists the four areas and warns before the season is set', (tester) async {
    await openAdvisor(tester);
    expect(find.text('الفئات'), findsWidgets);
    expect(find.text('المؤطرون والمشرفون'), findsOneWidget);
    expect(find.text('الأطفال وأولياء الأمور'), findsOneWidget);
    expect(find.text('الموسم والفصول'), findsOneWidget);
    expect(find.text('لم يُسجَّل الموسم وفصوله بعد.'), findsOneWidget);
  });

  testWidgets('a new group gets a suggested logo letter and its instructor', (tester) async {
    final repo = await openAdvisor(tester, tab: 'الفئات');
    await tester.tap(find.byKey(const Key('new-group')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('group-name')), 'فئة النجوم');
    await tester.pump();
    expect(find.widgetWithText(TextFormField, 'ن'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('age-min')), '8');
    await tester.enterText(find.byKey(const Key('age-max')), '10');
    await tester.tap(find.widgetWithText(FilterChip, 'ياسين الإدريسي'));
    await tester.tap(find.byKey(const Key('save-group')));
    await tester.pumpAndSettle();

    final group = repo.groups.values.single;
    expect(group.logoLetter, 'ن');
    expect(group.instructorIds, ['yassine']);
    expect(find.text('فئة النجوم'), findsOneWidget);
    expect(find.textContaining('من 8 إلى 10 سنوات'), findsOneWidget);
    expect(find.text('المؤطرون: ياسين الإدريسي'), findsOneWidget);
  });

  testWidgets('a duplicate group name is explained', (tester) async {
    await openAdvisor(tester, tab: 'الفئات', seed: (r) => r.saveGroup(stars));
    await tester.tap(find.byKey(const Key('new-group')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('group-name')), 'فئة النجوم');
    await tester.tap(find.byKey(const Key('save-group')));
    await tester.pumpAndSettle();
    expect(find.textContaining('يوجد اسم مطابق'), findsOneWidget);
  });

  testWidgets('a new instructor gets a temporary password to hand over', (tester) async {
    await openAdvisor(tester);
    await tester.tap(find.byKey(const Key('setup-staff')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('new-staff')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('staff-name')), 'سارة الإدريسي');
    await tester.enterText(find.byKey(const Key('staff-phone')), '06 22 22 22 22');
    await tester.tap(find.byKey(const Key('save-staff')));
    await tester.pumpAndSettle();

    expect(find.text('كلمات المرور المؤقتة'), findsOneWidget);
    expect(find.byKey(const Key('password-+212622222222')), findsOneWidget);
    await tester.tap(find.byKey(const Key('passwords-done')));
    await tester.pumpAndSettle();
    expect(find.text('سارة الإدريسي'), findsOneWidget);
  });

  testWidgets('a new child with a new parent: password shown, child listed under the group', (tester) async {
    final repo = await openAdvisor(tester, tab: 'الأطفال', seed: (r) => r.saveGroup(stars));
    await tester.tap(find.byKey(const Key('new-child')));
    await tester.pumpAndSettle();

    // No parent phone: refused before anything is sent.
    await tester.enterText(find.byKey(const Key('child-name')), 'آدم بنعلي');
    await tester.tap(find.byKey(const Key('save-child')));
    await tester.pumpAndSettle();
    expect(find.text('اكتب رقم الهاتف'), findsOneWidget);
    expect(repo.children, isEmpty);

    await tester.tap(find.byKey(const Key('child-group')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('فئة النجوم').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('parent-name-0')), 'كريم بنعلي');
    await tester.enterText(find.byKey(const Key('parent-phone-0')), '0612345678');
    await tester.tap(find.byKey(const Key('consent')));
    await tester.tap(find.byKey(const Key('save-child')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('password-+212612345678')), findsOneWidget);
    await tester.tap(find.byKey(const Key('passwords-done')));
    await tester.pumpAndSettle();

    final child = repo.children.values.single;
    expect(child.consentRecordedAt, isNotNull);
    expect(find.text('فئة النجوم · 1'), findsOneWidget);
    expect(find.text('آدم بنعلي'), findsOneWidget);
    expect(find.text('ولي الأمر: كريم بنعلي'), findsOneWidget);
  });

  testWidgets('typing the number of someone registered links the child to them', (tester) async {
    final repo = await openAdvisor(tester, tab: 'الأطفال');
    await tester.tap(find.byKey(const Key('new-child')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('child-name')), 'سلمى');
    await tester.enterText(find.byKey(const Key('parent-phone-0')), '0611111111');
    await tester.pump();
    expect(find.textContaining('مسجّل باسم ياسين الإدريسي'), findsOneWidget);
    await tester.tap(find.byKey(const Key('save-child')));
    await tester.pumpAndSettle();

    expect(find.text('كلمات المرور المؤقتة'), findsNothing);
    expect(repo.children.values.single.parentIds, ['yassine']);
    expect(repo.calls.where((c) => c.startsWith('createAccount')), isEmpty);
  });

  testWidgets('the season shows on the setup tab and its own screen', (tester) async {
    await openAdvisor(
      tester,
      seed: (r) => r.saveSeason(name: 'موسم 2026–2027', startsOn: DateTime(2026, 9, 1), endsOn: DateTime(2027, 6, 30)),
    );
    expect(find.text('موسم 2026–2027'), findsOneWidget);
    await tester.tap(find.byKey(const Key('setup-seasons')));
    await tester.pumpAndSettle();
    expect(find.text('موسم 2026–2027'), findsOneWidget);
    expect(find.text('لا توجد فصول بعد.'), findsOneWidget);
  });
}
