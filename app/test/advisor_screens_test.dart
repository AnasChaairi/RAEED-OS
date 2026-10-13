import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raeed_os/advisor/stats_models.dart';
import 'package:raeed_os/app.dart';
import 'package:raeed_os/auth/app_session.dart';
import 'package:raeed_os/instructor/instructor_store.dart';
import 'package:raeed_os/instructor/models.dart';
import 'package:raeed_os/profile/profile_repository.dart';
import 'package:raeed_os/roles/app_role.dart';
import 'package:raeed_os/setup/models.dart';
import 'package:raeed_os/setup/setup_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_auth.dart';
import 'fake_instructor.dart';
import 'fake_setup.dart';
import 'fake_stage4.dart';

const anas = '212691015402';
// Saturday 20 February 2027, 18:00.
final now = DateTime(2027, 2, 20, 18);

StatsData seededStats() => StatsData(
  groups: const [
    Group(id: 'stars', name: 'فئة النجوم', logoLetter: 'ن', logoColor: 1, instructorIds: ['yassine', 'sara']),
    Group(id: 'knights', name: 'فئة الفرسان', logoLetter: 'ف', logoColor: 2, instructorIds: ['hamza']),
  ],
  staffNames: const {'yassine': 'ياسين', 'sara': 'سارة الإدريسي', 'hamza': 'حمزة'},
  instructorCount: 3,
  children: const [
    StatChild(id: 'adam', fullName: 'آدم بنعلي', groupId: 'stars'),
    StatChild(id: 'omar', fullName: 'عمر الفاسي', groupId: 'stars'),
    StatChild(id: 'reda', fullName: 'رضا العمراني', groupId: 'knights'),
  ],
  sessions: [
    StatSession(id: 'feb6', groupId: 'stars', date: DateTime(2027, 2, 6), end: 690),
    StatSession(id: 'feb20', groupId: 'stars', date: DateTime(2027, 2, 20), end: 690),
    StatSession(id: 'k-feb18', groupId: 'knights', date: DateTime(2027, 2, 18), end: 690),
    StatSession(id: 'k-feb20', groupId: 'knights', date: DateTime(2027, 2, 20), end: 690),
  ],
  marks: const [
    StatMark(sessionId: 'feb6', childId: 'adam', status: AttendanceStatus.present),
    StatMark(sessionId: 'feb6', childId: 'omar', status: AttendanceStatus.present),
    StatMark(sessionId: 'feb20', childId: 'adam', status: AttendanceStatus.absent),
    StatMark(sessionId: 'feb20', childId: 'omar', status: AttendanceStatus.late),
    StatMark(sessionId: 'k-feb20', childId: 'reda', status: AttendanceStatus.present),
  ],
  openAlertGroups: const ['stars'],
  termStart: DateTime(2027, 1, 5),
);

ChildProfile adamProfile() => ChildProfile(
  id: 'adam',
  fullName: 'آدم بنعلي',
  birthDate: DateTime(2017, 4, 9),
  stays: [
    GroupStay(groupName: 'فئة البراعم', from: DateTime(2024, 9, 15), to: DateTime(2026, 9, 1)),
    GroupStay(groupName: 'فئة النجوم', from: DateTime(2026, 9, 1)),
  ],
  parents: const [ParentContact(id: 'karim', fullName: 'كريم بنعلي', phone: '+212612345678')],
  marks: [
    ProfileMark(date: DateTime(2027, 1, 30), title: 'مراجعة', status: AttendanceStatus.present),
    ProfileMark(date: DateTime(2027, 2, 6), title: 'حفظ', status: AttendanceStatus.late),
    ProfileMark(date: DateTime(2027, 2, 13), title: 'حفظ', status: AttendanceStatus.absent),
    ProfileMark(date: DateTime(2027, 2, 20), title: 'حفظ', status: AttendanceStatus.absent),
  ],
  notes: [ChildNote(authorName: 'ياسين', body: 'متميز في التلاوة', createdAt: DateTime(2027, 1, 23))],
  alerts: [
    ProfileAlert(
      createdAt: DateTime(2027, 2, 20, 12),
      open: false,
      reason: 'سفر عائلي',
      closedAt: DateTime(2027, 2, 20, 16),
      closedByName: 'ياسين',
    ),
  ],
  termStart: DateTime(2027, 1, 5),
);

Future<FakeProfileRepository> openAdvisor(
  WidgetTester tester, {
  FakeStatsRepository? stats,
  FakeSetupRepository? setup,
}) async {
  tester.view.physicalSize = const Size(1170, 2600);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final auth = FakeAuthRepository(
    accounts: {
      anas: FakeAccount(fullName: 'أنس', password: 'secret-pass', roles: {AppRole.advisor}),
    },
    signedInAs: anas,
  );
  final profiles = FakeProfileRepository()..profiles['adam'] = adamProfile();
  final extra = stage4(prefs, stats: (stats ?? FakeStatsRepository())..data = seededStats(), profiles: profiles, clock: () => now);
  final session = AppSession(auth, prefs);
  await tester.pumpWidget(
    RaeedApp(
      session: session,
      setup: SetupStore((setup ?? FakeSetupRepository())..addPerson(anas, 'أنس', '0691015402', {AppRole.advisor})),
      instructor: InstructorStore(FakeInstructorRepository(), prefs, retryEvery: null, clock: () => now),
      parent: extra.parent,
      stats: extra.stats,
      profiles: extra.profiles,
      push: extra.push,
    ),
  );
  await session.start();
  await tester.pumpAndSettle();
  return profiles;
}

void main() {
  testWidgets('statistics open on this month, with what needs attention', (tester) async {
    await openAdvisor(tester);
    expect(find.byKey(const Key('stats-rate')), findsOneWidget);
    // feb6 2/2, feb20 1/2, k-feb20 1/1.
    expect(tester.widget<Text>(find.byKey(const Key('stats-rate'))).data, '80%');
    expect(find.descendant(of: find.byKey(const Key('attention-alerts')), matching: find.text('1')), findsOneWidget);
    expect(
      find.descendant(of: find.byKey(const Key('attention-unrecorded')), matching: find.text('1')),
      findsOneWidget,
      reason: 'k-feb18 has no attendance',
    );

    await tester.tap(find.byKey(const Key('period-week')));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.byKey(const Key('stats-rate'))).data, '67%');
  });

  testWidgets('a group shows its instructors and children, and a child opens the profile', (tester) async {
    final profiles = await openAdvisor(tester);
    await tester.tap(find.byKey(const Key('stats-group-stars')));
    await tester.pumpAndSettle();
    expect(find.text('ياسين، سارة الإدريسي'), findsOneWidget);
    expect(find.text('2 / 2'), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('stats-kid-adam')), matching: find.text('50%')), findsOneWidget);

    await tester.tap(find.byKey(const Key('stats-kid-adam')));
    await tester.pumpAndSettle();
    expect(find.text('فئة النجوم · 9 سنوات · منذ 2024'), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('profile-rate'))).data, '50%');
    expect(find.text('تتبّع غياب · تم التواصل'), findsOneWidget);
    expect(find.text('سفر عائلي'), findsOneWidget);
    expect(find.text('متميز في التلاوة'), findsOneWidget);
    expect(find.text('الانتقال إلى فئة النجوم'), findsOneWidget);
    expect(find.text('من فئة البراعم'), findsOneWidget);

    await tester.tap(find.byKey(const Key('profile-add-note')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('profile-note')), 'يحتاج تشجيعاً');
    await tester.tap(find.byKey(const Key('save-profile-note')));
    await tester.pumpAndSettle();
    expect(profiles.added, ['يحتاج تشجيعاً']);
    expect(find.text('يحتاج تشجيعاً'), findsOneWidget);
  });

  testWidgets('the pilot measures show against their targets for the chosen period', (tester) async {
    final stats = FakeStatsRepository()
      ..pilot = PilotMetrics(
        sessionsHeld: 20,
        recordedWithin24h: 19,
        recordedLate: 1,
        groups: const [(groupId: 'stars', held: 12, onTime: 12), (groupId: 'knights', held: 8, onTime: 7)],
        medianSheetSeconds: 215,
        sheetsTimed: 18,
        alertsDue: 4,
        alertsFollowedUp: 3,
        families: 10,
        familiesSignedIn: 8,
        advisors: [(name: 'أنس', weeksOpened: 3, lastOpened: DateTime(2027, 2, 20, 9))],
      );
    await openAdvisor(tester, stats: stats);
    expect(stats.views, 1, reason: 'opening the statistics is counted');
    await tester.scrollUntilVisible(find.byKey(const Key('open-pilot')), 200);
    await tester.tap(find.byKey(const Key('open-pilot')));
    await tester.pumpAndSettle();
    expect(stats.pilotAsked.single, (DateTime(2027, 2), now));
    expect(find.descendant(of: find.byKey(const Key('pilot-on-time')), matching: find.text('95%')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('pilot-sheet-time')), matching: find.text('3:35')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('pilot-follow-up')), matching: find.text('75%')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('pilot-families')), matching: find.text('80%')), findsOneWidget);
    expect(find.text('7 من 8'), findsOneWidget);
    expect(find.text('3 أسابيع'), findsOneWidget);
  });

  testWidgets('the advisor sees deletion requests in setup and deletes the account', (tester) async {
    final setup = FakeSetupRepository()
      ..addPerson('suad', 'سعاد العلوي', '0612345679', {AppRole.parent})
      ..deletionRequests.add((personId: 'suad', requestedAt: DateTime(2027, 2, 19)));
    await openAdvisor(tester, setup: setup);
    await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('الإعدادات')));
    await tester.pumpAndSettle();
    expect(find.text('ولي أمر · طلب في 19/2/2027'), findsOneWidget);
    await tester.tap(find.byKey(const Key('delete-account-suad')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-delete-account')));
    await tester.pumpAndSettle();
    expect(setup.calls, contains('deleteAccount suad'));
    expect(find.byKey(const Key('deletion-suad')), findsNothing);
  });
}
