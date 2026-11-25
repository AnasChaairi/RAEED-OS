import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
      items[i] = items[i].asRead();
    }
  }
}

AppNotification note(String id, String kind, {bool read = false}) => AppNotification(
      id: id,
      kind: kind,
      title: 'عنوان $id',
      body: 'نص $id',
      createdAt: DateTime.now().subtract(const Duration(minutes: 5)),
      read: read,
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
  });
}
