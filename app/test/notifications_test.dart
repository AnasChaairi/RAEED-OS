import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raeed_os/notifications/announcements.dart';
import 'package:raeed_os/notifications/inbox.dart';
import 'package:raeed_os/roles/app_role.dart';

class FakeNotificationsRepository implements NotificationsRepository {
  final items = <AppNotification>[];
  int markCalls = 0;

  @override
  Future<List<AppNotification>> load() async => List.of(items);

  @override
  Future<void> markRead([List<String>? ids]) async {
    markCalls++;
    for (var i = 0; i < items.length; i++) {
      if (ids == null || ids.contains(items[i].id)) items[i] = items[i].asRead();
    }
  }

  final news = <Announcement>[];
  final published = <({String title, String body, Set<AnnouncementAudience> audience})>[];

  @override
  Future<List<Announcement>> loadAnnouncements() async => List.of(news);

  @override
  Future<int> publishAnnouncement(
      {required String title, required String body, required Set<AnnouncementAudience> audience}) async {
    published.add((title: title, body: body, audience: audience));
    news.insert(0, Announcement(id: 'n${news.length}', title: title, body: body, createdAt: DateTime.now(), audience: audience, recipients: 42));
    return 42;
  }

  @override
  Future<void> deleteAnnouncement(String id) async => news.removeWhere((a) => a.id == id);
}

AppNotification note(String id, String kind, {bool read = false, String? child, String? announcement}) => AppNotification(
      id: id,
      kind: kind,
      title: 'عنوان $id',
      body: 'نص $id',
      createdAt: DateTime.now().subtract(const Duration(minutes: 5)),
      read: read,
      childId: child,
      announcementId: announcement,
    );

void main() {
  testWidgets('the bell shows the unread count and opening the list marks them read', (tester) async {
    final repo = FakeNotificationsRepository()
      ..items.addAll([note('a', 'child_message_reply'), note('b', 'session_cancelled'), note('c', 'absence_alert', read: true)]);
    final store = InboxStore(repo);
    await store.load();
    AppNotification? tapped;

    await tester.pumpWidget(
      InboxScope(
        store: store,
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              appBar: AppBar(
                actions: [
                  NotificationBell(
                    onOpen: () async {
                      tapped = await Navigator.push<AppNotification>(
                        context,
                        MaterialPageRoute(builder: (_) => const NotificationsScreen()),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('2'), findsOneWidget);
    await tester.tap(find.byKey(const Key('notifications')));
    await tester.pumpAndSettle();

    expect(find.text('عنوان a'), findsOneWidget);
    expect(find.text('عنوان c'), findsOneWidget);
    expect(repo.markCalls, 1);
    expect(store.unread, 0);

    await tester.tap(find.text('عنوان a'));
    await tester.pumpAndSettle();
    expect(tapped?.id, 'a');
    expect(find.byKey(const Key('notifications-count')), findsNothing);
  });

  test('a notification opens the matching tab of each role', () {
    expect(note('x', 'child_message_reply').tabFor(AppRole.supervisor), 2);
    expect(note('x', 'child_message_reply').tabFor(AppRole.parent), 1);
    expect(note('x', 'absence_alert').tabFor(AppRole.instructor), 3);
    expect(note('x', 'instructor_absence').tabFor(AppRole.advisor), 1);
    expect(note('x', 'session_observation').tabFor(AppRole.supervisor), 3);
    expect(note('x', 'child_note').tabFor(AppRole.supervisor), 1);
    expect(note('x', 'child_note').tabFor(AppRole.instructor), 2);
    expect(note('x', 'session_assigned').tabFor(AppRole.instructor), 0);
    expect(note('x', 'child_note').tabFor(AppRole.advisor), 3);
    expect(note('x', 'homework_reminder').tabFor(AppRole.parent), 2);
    expect(note('x', 'child_absent').tabFor(AppRole.parent), 0);
  });

  test('notes and replies count per child, and stay unread when the bell keeps them', () async {
    final repo = FakeNotificationsRepository()
      ..items.addAll([
        note('r1', 'child_message_reply', child: 'k1'),
        note('r2', 'child_message_like', child: 'k1'),
        note('r3', 'child_message_reply', child: 'k2'),
        note('s1', 'session_cancelled'),
      ]);
    final store = InboxStore(repo);
    await store.load();
    expect(store.unread, 4);
    expect(store.unreadMessages(), 3);
    expect(store.unreadMessages(childId: 'k1'), 2);

    await store.markAllRead(keepMessages: true);
    expect(store.unread, 3);
    expect(store.unreadMessages(), 3);

    await store.markMessagesRead(childId: 'k1');
    expect(store.unreadMessages(childId: 'k1'), 0);
    expect(store.unreadMessages(), 1);
  });

  testWidgets('the مشرف العام publishes a إخبار عام for some roles only', (tester) async {
    final repo = FakeNotificationsRepository();
    final store = InboxStore(repo);
    await tester.pumpWidget(InboxScope(
      store: store,
      child: const MaterialApp(home: NotificationsScreen(canPublish: true, openAnnouncements: true)),
    ));
    await tester.pumpAndSettle();
    expect(find.text('لا توجد إخبارات عامة بعد.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('new-announcement')));
    await tester.pumpAndSettle();
    // Everyone is picked until a role is.
    expect(tester.widget<ChoiceChip>(find.byKey(const Key('audience-all'))).selected, isTrue);
    await tester.tap(find.byKey(const Key('publish-announcement')));
    await tester.pump();
    expect(find.text('اكتب عنواناً.'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('announcement-title')), 'عطلة');
    await tester.enterText(find.byKey(const Key('announcement-body')), 'الأكاديمية مغلقة يوم السبت.');
    await tester.tap(find.byKey(const Key('audience-parent')));
    await tester.tap(find.byKey(const Key('audience-instructor')));
    await tester.pump();
    expect(tester.widget<ChoiceChip>(find.byKey(const Key('audience-all'))).selected, isFalse);
    await tester.tap(find.byKey(const Key('publish-announcement')));
    await tester.pumpAndSettle();
    expect(find.textContaining('أولياء الأمور، المؤطرون'), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirm-publish')));
    await tester.pumpAndSettle();

    expect(repo.published.single.audience, {AnnouncementAudience.parent, AnnouncementAudience.instructor});
    expect(find.text('عطلة'), findsOneWidget);
    expect(find.textContaining('إلى: أولياء الأمور، المؤطرون · أُرسل إلى 42'), findsOneWidget);
  });

  testWidgets('picking every role goes back to everyone', (tester) async {
    final store = InboxStore(FakeNotificationsRepository());
    await tester.pumpWidget(InboxScope(store: store, child: const MaterialApp(home: ComposeAnnouncementScreen())));
    for (final a in AnnouncementAudience.values) {
      await tester.tap(find.byKey(Key('audience-${a.dbName}')));
      await tester.pump();
    }
    expect(tester.widget<ChoiceChip>(find.byKey(const Key('audience-all'))).selected, isTrue);
  });

  testWidgets('an unread إخبار عام opens its tab and the banner reads it', (tester) async {
    final repo = FakeNotificationsRepository()
      ..news.add(Announcement(id: 'x1', title: 'حفل', body: 'حفل نهاية السنة', createdAt: DateTime.now()))
      ..items.add(note('o1', 'announcement', announcement: 'x1'));
    final store = InboxStore(repo);
    await store.load();
    await tester.pumpWidget(InboxScope(
      store: store,
      child: const MaterialApp(home: Scaffold(body: AnnouncementBanner(canDelete: false))),
    ));
    expect(find.byKey(const Key('announcement-banner')), findsOneWidget);
    await tester.tap(find.byKey(const Key('announcement-banner')));
    await tester.pumpAndSettle();
    expect(find.text('حفل نهاية السنة'), findsOneWidget);
    expect(store.unreadAnnouncements, isEmpty);
    expect(find.byKey(const Key('delete-announcement')), findsNothing);
  });
}
