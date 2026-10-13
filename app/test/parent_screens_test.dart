import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raeed_os/app.dart';
import 'package:raeed_os/auth/app_session.dart';
import 'package:raeed_os/instructor/instructor_store.dart';
import 'package:raeed_os/instructor/models.dart';
import 'package:raeed_os/notifications/push.dart';
import 'package:raeed_os/parent/parent_models.dart';
import 'package:raeed_os/roles/app_role.dart';
import 'package:raeed_os/setup/setup_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_auth.dart';
import 'fake_instructor.dart';
import 'fake_setup.dart';
import 'fake_stage4.dart';

const karim = '212612345678';
// Wednesday 10 February 2027, 12:20.
final now = DateTime(2027, 2, 10, 12, 20);

ParentSnapshot seededParent() => ParentSnapshot(
  children: const [
    ParentChild(id: 'adam', fullName: 'آدم بنعلي', group: starsGroup),
    ParentChild(id: 'salma', fullName: 'سلمى بنعلي', group: budsGroup),
  ],
  sessions: [
    Session(
      id: 'past',
      groupId: 'stars',
      title: 'مراجعة قديمة',
      date: DateTime(2027, 2, 6),
      start: 600,
      end: 690,
      floor: 1,
    ),
    Session(
      id: 'wed',
      groupId: 'stars',
      title: 'مراجعة الحفظ',
      date: DateTime(2027, 2, 10),
      start: 17 * 60 + 30,
      end: 19 * 60,
      floor: 1,
      status: SessionStatus.changed,
      originalDate: DateTime(2027, 2, 10),
      originalStart: 17 * 60,
      originalEnd: 18 * 60 + 30,
    ),
    Session(
      id: 'buds-thu',
      groupId: 'buds',
      title: 'قصص الأنبياء',
      date: DateTime(2027, 2, 11),
      start: 16 * 60,
      end: 17 * 60,
      floor: 0,
    ),
    Session(
      id: 'sat',
      groupId: 'stars',
      title: 'حفظ سورة الملك',
      date: DateTime(2027, 2, 13),
      start: 600,
      end: 690,
      floor: 1,
      materials: const [
        SessionMaterial(kind: 'youtube', url: 'https://youtube.com/watch?v=x', label: 'تلاوة سورة الملك'),
        SessionMaterial(kind: 'drive', url: 'https://drive.google.com/file/d/y', label: 'بطاقات الحفظ.pdf'),
      ],
    ),
    Session(
      id: 'trip',
      groupId: 'stars',
      title: 'نزهة تربوية',
      date: DateTime(2027, 2, 13),
      start: 15 * 60,
      end: 17 * 60,
      place: SessionPlace.away,
      address: 'حديقة الجامعة العربية',
      mapUrl: 'https://maps.google.com/?q=x',
      dropoffPlace: 'أمام جمعية سماء',
      dropoffTime: 14 * 60 + 45,
      pickupPlace: 'أمام جمعية سماء',
      pickupTime: 17 * 60 + 15,
    ),
    Session(
      id: 'cancel',
      groupId: 'stars',
      title: 'مراجعة الحفظ',
      date: DateTime(2027, 2, 17),
      start: 17 * 60,
      end: 18 * 60 + 30,
      floor: 1,
      status: SessionStatus.cancelled,
      cancelReason: 'عطلة منتصف الفصل',
    ),
  ],
  staffNames: const {
    'stars': ['سارة الإدريسي', 'ياسين'],
    'buds': ['حمزة'],
  },
  parents: const [
    ChildParent(childId: 'adam', parentId: karim, fullName: 'كريم بنعلي', notified: true),
    ChildParent(childId: 'adam', parentId: 'suad', fullName: 'سعاد العلوي', notified: true),
    ChildParent(childId: 'salma', parentId: karim, fullName: 'كريم بنعلي', notified: true),
  ],
);

class OpenedParent {
  OpenedParent(this.repo, this.push, this.session, this.auth);

  final FakeParentRepository repo;
  final FakeAuthRepository auth;
  final FakePush push;
  final AppSession session;
}

Future<OpenedParent> openParent(
  WidgetTester tester, {
  FakeParentRepository? repo,
  bool fresh = true,
  PushState pushState = PushState.on,
}) async {
  tester.view.physicalSize = const Size(1170, 2600);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  if (fresh) SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final auth = FakeAuthRepository(
    accounts: {
      karim: FakeAccount(fullName: 'كريم بنعلي', password: 'secret-pass', roles: {AppRole.parent}),
    },
    signedInAs: karim,
  );
  repo ??= FakeParentRepository()..data = seededParent();
  final push = FakePush()..current = pushState;
  final session = AppSession(auth, prefs)..beforeSignOut = push.unregister;
  final extra = stage4(prefs, parent: repo, push: push, clock: () => now);
  await tester.pumpWidget(
    RaeedApp(
      session: session,
      setup: SetupStore(FakeSetupRepository()),
      instructor: InstructorStore(FakeInstructorRepository(), prefs, retryEvery: null),
      parent: extra.parent,
      stats: extra.stats,
      profiles: extra.profiles,
      push: extra.push,
    ),
  );
  await session.start();
  await tester.pumpAndSettle();
  return OpenedParent(repo, push, session, auth);
}

void main() {
  testWidgets('the schedule marks the next session, the changes, trips and materials', (tester) async {
    final o = await openParent(tester);
    expect(o.push.registered, 1, reason: 'the phone registers for notifications');
    expect(find.text('تغييران هذا الأسبوع'), findsOneWidget);
    expect(find.text('موعد الأربعاء 10 فبراير تغيّر (كان 17:00)'), findsOneWidget);
    expect(find.text('اليوم · الأربعاء 10 فبراير'), findsOneWidget);
    expect(find.text('تغيّر الموعد · كان 17:00'), findsOneWidget);
    expect(find.text('الحصة القادمة'), findsOneWidget);
    expect(find.text('مواد للمراجعة في البيت (2)'), findsOneWidget);
    expect(find.text('التسليم 14:45 أمام جمعية سماء'), findsOneWidget);
    expect(find.text('الاستلام 17:15 أمام جمعية سماء'), findsOneWidget);
    expect(find.text('حصة الأربعاء 17 فبراير ملغاة: عطلة منتصف الفصل'), findsOneWidget);
    await tester.scrollUntilVisible(find.byKey(const Key('parent-session-cancel')), 200);
    expect(find.text('عطلة منتصف الفصل'), findsOneWidget);
    await tester.drag(find.byType(ListView).first, const Offset(0, 2000));
    await tester.pumpAndSettle();
    expect(find.text('مراجعة قديمة'), findsNothing, reason: 'sessions that ended are not shown');
    expect(find.text('قصص الأنبياء'), findsNothing, reason: 'Salma\'s sessions wait for the switch');

    await tester.tap(find.byKey(const Key('child-salma')));
    await tester.pumpAndSettle();
    expect(find.text('غداً · الخميس 11 فبراير'), findsOneWidget);
    expect(find.text('قصص الأنبياء'), findsOneWidget);
    expect(find.byKey(const Key('changes-summary')), findsNothing);
  });

  testWidgets('a session opens with its instructors, materials and the calendar button', (tester) async {
    await openParent(tester);
    await tester.tap(find.text('حفظ سورة الملك'));
    await tester.pumpAndSettle();
    expect(find.text('السبت 13 فبراير'), findsOneWidget);
    expect(find.text('10:00 – 11:30'), findsOneWidget);
    expect(find.text('المؤطرون: سارة الإدريسي، ياسين'), findsOneWidget);
    expect(find.text('تلاوة سورة الملك'), findsOneWidget);
    expect(find.text('بطاقات الحفظ.pdf'), findsOneWidget);
    expect(find.byKey(const Key('add-to-calendar')), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('نزهة تربوية'));
    await tester.pumpAndSettle();
    expect(find.text('التسليم: 14:45 · أمام جمعية سماء'), findsOneWidget);
    expect(find.byKey(const Key('open-map')), findsOneWidget);
  });

  testWidgets('a cancelled session says so and has no calendar button', (tester) async {
    await openParent(tester);
    await tester.scrollUntilVisible(find.byKey(const Key('parent-session-cancel')), 200);
    await tester.tap(find.byKey(const Key('parent-session-cancel')));
    await tester.pumpAndSettle();
    expect(find.text('هذه الحصة ملغاة: عطلة منتصف الفصل'), findsOneWidget);
    expect(find.byKey(const Key('add-to-calendar')), findsNothing);
  });

  testWidgets('the schedule opens offline from the phone', (tester) async {
    await openParent(tester);
    final repo = FakeParentRepository()..offline = true;
    await openParent(tester, repo: repo, fresh: false);
    expect(find.byKey(const Key('offline-banner')), findsOneWidget);
    expect(find.text('حفظ سورة الملك'), findsOneWidget);
  });

  testWidgets('a notification while the app is open shows and refreshes the schedule', (tester) async {
    final o = await openParent(tester);
    final before = o.repo.loads;
    o.push.controller.add(const PushMessage(title: 'تغيير موعد · آدم', body: 'مراجعة الحفظ · 10/02 · 17:30 بدل 17:00'));
    await tester.pumpAndSettle();
    expect(find.textContaining('تغيير موعد · آدم'), findsOneWidget);
    expect(o.repo.loads, before + 1);
  });

  testWidgets('the account lists the children and both parents who are notified', (tester) async {
    final o = await openParent(tester);
    await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('حسابي')));
    await tester.pumpAndSettle();
    expect(find.text('آدم · فئة النجوم'), findsOneWidget);
    expect(find.text('سلمى · فئة البراعم'), findsOneWidget);
    expect(find.text('كريم بنعلي (أنت)'), findsOneWidget);
    expect(find.text('سعاد العلوي'), findsOneWidget);
    expect(find.text('مفعّل'), findsNWidgets(2));

    await tester.tap(find.byKey(const Key('parent-sign-out')));
    await tester.pumpAndSettle();
    expect(o.push.unregistered, 1, reason: 'this phone stops receiving the notifications');
    expect(find.byKey(const Key('sign-in')), findsOneWidget);
  });

  testWidgets('notifications turned off on this phone are shown as off', (tester) async {
    await openParent(tester, pushState: PushState.denied);
    await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('حسابي')));
    await tester.pumpAndSettle();
    expect(find.text('غير مفعّل'), findsOneWidget);
    expect(find.textContaining('فعّلها من إعدادات الهاتف'), findsOneWidget);
  });

  testWidgets('the password is changed from the account', (tester) async {
    await openParent(tester);
    await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('حسابي')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('change-password')));
    await tester.pumpAndSettle();
    expect(find.text('تغيير كلمة المرور'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('new-password')), 'new-secret-1');
    await tester.enterText(find.byKey(const Key('repeat-password')), 'new-secret-1');
    await tester.tap(find.byKey(const Key('save-password')));
    await tester.pumpAndSettle();
    expect(find.text('تم تغيير كلمة المرور ✓'), findsOneWidget);
    expect(find.text('من يتلقى الإشعارات'), findsOneWidget, reason: 'back on the account');
  });

  testWidgets('a parent asks for their account to be deleted, after confirming', (tester) async {
    final o = await openParent(tester);
    await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('حسابي')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byKey(const Key('request-deletion')), 200);
    await tester.tap(find.byKey(const Key('request-deletion')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('إلغاء'));
    await tester.pumpAndSettle();
    expect(o.auth.deletionRequests, isEmpty);

    await tester.tap(find.byKey(const Key('request-deletion')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-deletion')));
    await tester.pumpAndSettle();
    expect(o.auth.deletionRequests, {karim});
    expect(find.text('وصل طلبك إلى المشرف ✓'), findsOneWidget);
  });
}
