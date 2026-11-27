import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../roles/app_role.dart';
import '../setup/setup_repository.dart';
import '../theme/raeed_theme.dart';

/// One notification sent to the signed-in person, kept so they can read it in the app
/// even when the push did not reach the phone.
class AppNotification {
  const AppNotification({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    required this.createdAt,
    this.read = false,
    this.childId,
  });

  final String id;
  final String kind;
  final String title;
  final String body;
  final DateTime createdAt;
  final bool read;

  /// The child it is about, when there is one.
  final String? childId;

  /// A note, reply or like in the channel between the مشرف الفئة and parents.
  bool get isMessage => kind.startsWith('child_message');

  AppNotification asRead() => AppNotification(
      id: id, kind: kind, title: title, body: body, createdAt: createdAt, read: true, childId: childId);

  IconData get icon => switch (kind) {
        'child_message' || 'child_message_reply' => Icons.forum,
        'child_message_like' => Icons.favorite,
        'session_cancelled' => Icons.event_busy,
        'session_reminder' => Icons.alarm,
        'session_created' || 'session_changed' => Icons.event,
        'absence_alert' => Icons.warning_amber_rounded,
        'instructor_absence' => Icons.person_off,
        'activity_cancelled' => Icons.event_busy,
        'activity_created' || 'activity_changed' || 'activity_reminder' => Icons.celebration,
        'homework_assigned' => Icons.assignment,
        _ => Icons.notifications,
      };

  /// The bottom tab of [role] that this notification is about, if any.
  int? tabFor(AppRole role) => switch ((role, kind)) {
        (AppRole.parent, 'child_message' || 'child_message_reply' || 'child_message_like') => 1,
        (AppRole.parent, 'homework_assigned') => 2,
        (AppRole.parent, _) => 0,
        (AppRole.supervisor, 'child_message' || 'child_message_reply' || 'child_message_like') => 2,
        (AppRole.supervisor, 'absence_alert') => 4,
        (AppRole.supervisor, 'instructor_absence') => 1,
        (AppRole.supervisor, _) => 0,
        (AppRole.instructor, 'absence_alert') => 3,
        (AppRole.instructor, _) => 1,
        (AppRole.advisor, 'session_cancelled' || 'session_created' || 'session_changed' || 'instructor_absence') => 1,
        (AppRole.advisor, 'activity_created' || 'activity_changed' || 'activity_cancelled' || 'activity_reminder') => 1,
        (AppRole.advisor, 'absence_alert') => 3,
        _ => null,
      };
}

/// The signed-in person's notifications. Every call throws [SetupError].
abstract interface class NotificationsRepository {
  /// Newest first.
  Future<List<AppNotification>> load();

  /// Marks [ids] read, or all of them when null.
  Future<void> markRead([List<String>? ids]);
}

class SupabaseNotificationsRepository implements NotificationsRepository {
  SupabaseNotificationsRepository(this._db);

  final SupabaseClient _db;

  @override
  Future<List<AppNotification>> load() => guardSupabase(() async {
        final me = _db.auth.currentUser?.id;
        if (me == null) return const [];
        final rows = await _db
            .from('notification_outbox')
            .select('id, kind, title, body, data, created_at, read_at')
            .eq('recipient_id', me)
            .order('created_at', ascending: false)
            .limit(100);
        return [
          for (final r in rows)
            AppNotification(
              id: r['id'] as String,
              kind: r['kind'] as String,
              title: r['title'] as String,
              body: r['body'] as String,
              createdAt: DateTime.parse(r['created_at'] as String).toLocal(),
              read: r['read_at'] != null,
              childId: (r['data'] as Map?)?['child_id'] as String?,
            ),
        ];
      });

  @override
  Future<void> markRead([List<String>? ids]) =>
      guardSupabase(() => _db.rpc<void>('mark_notifications_read', params: {'p_ids': ids}));
}

/// The list behind the bell, and its unread count.
class InboxStore extends ChangeNotifier {
  InboxStore(this._repo);

  final NotificationsRepository _repo;
  List<AppNotification> _items = const [];
  bool _loading = false;
  bool _failed = false;

  List<AppNotification> get items => _items;
  int get unread => _items.where((n) => !n.read).length;
  bool get loading => _loading;
  bool get failed => _failed;

  /// Quietly fetches the list again. Keeps the last list when offline.
  Future<void> load() async {
    if (_loading) return;
    _loading = true;
    notifyListeners();
    try {
      _items = await _repo.load();
      _failed = false;
    } catch (_) {
      _failed = true;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Unread notes, replies and likes, for one child or all.
  int unreadMessages({String? childId}) =>
      _items.where((n) => !n.read && n.isMessage && (childId == null || n.childId == childId)).length;

  /// Marks the unread notes, replies and likes read, for one child or all.
  Future<void> markMessagesRead({String? childId}) async {
    final ids = [
      for (final n in _items)
        if (!n.read && n.isMessage && (childId == null || n.childId == childId)) n.id,
    ];
    if (ids.isEmpty) return;
    _items = [for (final n in _items) ids.contains(n.id) ? n.asRead() : n];
    notifyListeners();
    try {
      await _repo.markRead(ids);
    } catch (_) {
      // Offline: they show as unread again on the next load.
    }
  }

  /// With [keepMessages], notes and replies stay unread until their conversation is opened.
  Future<void> markAllRead({bool keepMessages = false}) async {
    final ids = [for (final n in _items) if (!n.read && !(keepMessages && n.isMessage)) n.id];
    if (ids.isEmpty) return;
    _items = [for (final n in _items) ids.contains(n.id) ? n.asRead() : n];
    notifyListeners();
    try {
      await _repo.markRead(keepMessages ? ids : null);
    } catch (_) {
      // Offline: they show as unread again on the next load.
    }
  }

  /// Someone else signs in on this phone.
  void clear() {
    _items = const [];
    notifyListeners();
  }
}

class InboxScope extends InheritedNotifier<InboxStore> {
  const InboxScope({super.key, required InboxStore? store, required super.child}) : super(notifier: store);

  /// Null where the app was started without one (tests that do not cover notifications).
  static InboxStore? of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<InboxScope>()?.notifier;

  static InboxStore? read(BuildContext context) => context.getInheritedWidgetOfExactType<InboxScope>()?.notifier;
}

/// The bell at the top of every role's screens, with the unread count.
class NotificationBell extends StatelessWidget {
  const NotificationBell({super.key, required this.onOpen});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final store = InboxScope.of(context);
    if (store == null) return const SizedBox.shrink();
    final n = store.unread;
    return IconButton(
      key: const Key('notifications'),
      tooltip: 'الإشعارات',
      onPressed: onOpen,
      icon: Badge(
        isLabelVisible: n > 0,
        backgroundColor: RaeedColors.error,
        label: Text(n > 99 ? '99+' : '$n', key: const Key('notifications-count')),
        child: Icon(n > 0 ? Icons.notifications : Icons.notifications_none),
      ),
    );
  }
}

/// The person's notifications, newest first. Opening it marks them read (with
/// [keepMessages], all but the notes and replies). Pops with the notification tapped, if any.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key, this.keepMessages = false});

  final bool keepMessages;

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  /// Unread when the screen opened: they stay highlighted while it is open.
  late final Set<String> _fresh;

  @override
  void initState() {
    super.initState();
    final store = InboxScope.read(context)!;
    _fresh = {for (final n in store.items) if (!n.read) n.id};
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await store.load();
      if (!mounted) return;
      setState(() => _fresh.addAll([for (final n in store.items) if (!n.read) n.id]));
      await store.markAllRead(keepMessages: widget.keepMessages);
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = InboxScope.of(context)!;
    final text = Theme.of(context).textTheme;
    final items = store.items;
    return Scaffold(
      appBar: AppBar(title: const Text('الإشعارات')),
      body: RefreshIndicator(
        onRefresh: store.load,
        child: items.isEmpty
            ? ListView(
                children: [
                  const SizedBox(height: 120),
                  Icon(Icons.notifications_none, size: 56, color: RaeedColors.grey.withValues(alpha: 0.6)),
                  const SizedBox(height: 12),
                  Text(
                    store.loading
                        ? 'جارٍ التحميل…'
                        : store.failed
                            ? 'تعذّر تحميل الإشعارات. اسحب للأسفل للمحاولة مجدداً.'
                            : 'لا توجد إشعارات بعد.',
                    textAlign: TextAlign.center,
                    style: text.bodyMedium?.copyWith(color: RaeedColors.grey),
                  ),
                ],
              )
            : ListView.separated(
                itemCount: items.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final n = items[i];
                  final fresh = _fresh.contains(n.id);
                  return ListTile(
                    key: Key('notification-${n.id}'),
                    tileColor: fresh ? RaeedColors.blue.withValues(alpha: 0.06) : null,
                    leading: CircleAvatar(
                      backgroundColor: RaeedColors.blue.withValues(alpha: 0.12),
                      child: Icon(n.icon, color: RaeedColors.blue, size: 20),
                    ),
                    title: Text(n.title, style: fresh ? const TextStyle(fontWeight: FontWeight.w700) : null),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (n.body.isNotEmpty) Text(n.body, maxLines: 3, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 2),
                        Text(_when(n.createdAt), style: text.bodySmall?.copyWith(color: RaeedColors.grey)),
                      ],
                    ),
                    onTap: () => Navigator.pop(context, n),
                  );
                },
              ),
      ),
    );
  }

  static String _when(DateTime t) {
    final now = DateTime.now();
    final minutes = now.difference(t).inMinutes;
    if (minutes < 1) return 'الآن';
    if (minutes < 60) return 'قبل $minutes د';
    final hm = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(t.year, t.month, t.day);
    if (day == today) return 'اليوم $hm';
    if (day == today.subtract(const Duration(days: 1))) return 'أمس $hm';
    return '${t.day.toString().padLeft(2, '0')}/${t.month.toString().padLeft(2, '0')} $hm';
  }
}
