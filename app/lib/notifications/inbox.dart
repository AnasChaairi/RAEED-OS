import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../roles/app_role.dart';
import '../setup/setup_repository.dart';
import '../theme/raeed_theme.dart';
import 'announcements.dart';

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
    this.announcementId,
  });

  final String id;
  final String kind;
  final String title;
  final String body;
  final DateTime createdAt;
  final bool read;

  /// The child it is about, when there is one.
  final String? childId;

  /// The إخبار عام it announces, for kind 'announcement'.
  final String? announcementId;

  bool get isAnnouncement => kind == 'announcement';

  /// A note, reply or like in the channel between the مشرف الفئة and parents.
  bool get isMessage => kind.startsWith('child_message');

  AppNotification asRead() => AppNotification(
      id: id,
      kind: kind,
      title: title,
      body: body,
      createdAt: createdAt,
      read: true,
      childId: childId,
      announcementId: announcementId);

  IconData get icon => switch (kind) {
        'child_message' || 'child_message_reply' => Icons.forum,
        'child_message_like' => Icons.favorite,
        'session_cancelled' => Icons.event_busy,
        'session_reminder' => Icons.alarm,
        'session_created' || 'session_changed' => Icons.event,
        'session_assigned' => Icons.how_to_reg,
        'session_unassigned' => Icons.person_remove_outlined,
        'session_observation' => Icons.rate_review_outlined,
        'child_note' => Icons.sticky_note_2_outlined,
        'absence_alert' => Icons.warning_amber_rounded,
        'instructor_absence' => Icons.person_off,
        'instructor_absence_cancelled' || 'child_absence_cancelled' => Icons.event_available,
        'child_absence' || 'child_absent' => Icons.event_busy_outlined,
        'activity_cancelled' => Icons.event_busy,
        'activity_created' || 'activity_changed' || 'activity_reminder' => Icons.celebration,
        'homework_assigned' || 'homework_changed' => Icons.assignment,
        'homework_reminder' => Icons.alarm,
        'homework_cancelled' => Icons.assignment_late_outlined,
        'announcement' => Icons.campaign,
        _ => Icons.notifications,
      };

  /// The bottom tab of [role] that this notification is about, if any.
  int? tabFor(AppRole role) => switch ((role, kind)) {
        (AppRole.parent, 'child_message' || 'child_message_reply' || 'child_message_like') => 1,
        (AppRole.parent, 'homework_assigned' || 'homework_changed' || 'homework_reminder' || 'homework_cancelled') => 2,
        (AppRole.parent, _) => 0,
        (AppRole.supervisor, 'child_message' || 'child_message_reply' || 'child_message_like') => 2,
        (AppRole.supervisor, 'session_observation') => 3,
        (AppRole.supervisor, 'absence_alert') => 4,
        (AppRole.supervisor, 'instructor_absence' || 'instructor_absence_cancelled' || 'child_note') => 1,
        (AppRole.supervisor, 'homework_assigned') => 1,
        (AppRole.supervisor, _) => 0,
        (AppRole.instructor, 'absence_alert') => 3,
        (AppRole.instructor, 'session_assigned' || 'session_unassigned') => 0,
        (AppRole.instructor, 'child_note') => 2,
        (AppRole.instructor, _) => 1,
        (AppRole.advisor, 'child_note' || 'child_message_reply' || 'absence_alert') => 3,
        (AppRole.advisor, 'homework_assigned') => 2,
        (AppRole.advisor, _) => 1,
      };
}

/// The signed-in person's notifications. Every call throws [SetupError].
abstract interface class NotificationsRepository {
  /// Newest first.
  Future<List<AppNotification>> load();

  /// Marks [ids] read, or all of them when null.
  Future<void> markRead([List<String>? ids]);

  /// The إخبارات العامة this person may read, newest first.
  Future<List<Announcement>> loadAnnouncements();

  /// Publishes one for [audience] (empty: everyone). Returns how many people it was sent to.
  Future<int> publishAnnouncement({required String title, required String body, required Set<AnnouncementAudience> audience});

  Future<void> deleteAnnouncement(String id);
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
              announcementId: (r['data'] as Map?)?['announcement_id'] as String?,
            ),
        ];
      });

  @override
  Future<List<Announcement>> loadAnnouncements() => guardSupabase(() async {
        final rows = await _db
            .from('announcements')
            .select('id, title, body, audience, recipients, created_at, author:people!announcements_author_id_fkey(full_name)')
            .order('created_at', ascending: false)
            .limit(100);
        return [for (final r in rows) Announcement.fromRow(r)];
      });

  @override
  Future<int> publishAnnouncement(
          {required String title, required String body, required Set<AnnouncementAudience> audience}) =>
      guardSupabase(() async {
        final n = await _db.rpc<dynamic>('publish_announcement', params: {
          'p_title': title,
          'p_body': body,
          'p_audience': [for (final a in audience) a.dbName],
        });
        return (n as num?)?.toInt() ?? 0;
      });

  @override
  Future<void> deleteAnnouncement(String id) =>
      guardSupabase(() => _db.rpc<void>('delete_announcement', params: {'p_id': id}));

  @override
  Future<void> markRead([List<String>? ids]) =>
      guardSupabase(() => _db.rpc<void>('mark_notifications_read', params: {'p_ids': ids}));
}

/// The list behind the bell, and its unread count.
class InboxStore extends ChangeNotifier {
  InboxStore(this._repo);

  final NotificationsRepository _repo;
  List<AppNotification> _items = const [];
  List<Announcement> _announcements = const [];
  bool _announcementsLoaded = false;
  bool _announcementsFailed = false;
  bool _loading = false;
  bool _failed = false;

  List<AppNotification> get items => _items;
  int get unread => _items.where((n) => !n.read).length;
  bool get loading => _loading;
  bool get failed => _failed;

  /// The إخبارات العامة, newest first.
  List<Announcement> get announcements => _announcements;
  bool get announcementsLoaded => _announcementsLoaded;
  bool get announcementsFailed => _announcementsFailed;

  /// Unread notifications of a إخبار عام, newest first.
  List<AppNotification> get unreadAnnouncements => [for (final n in _items) if (!n.read && n.isAnnouncement) n];

  Announcement? announcement(String? id) {
    for (final a in _announcements) {
      if (a.id == id) return a;
    }
    return null;
  }

  /// Fetches the إخبارات العامة. Keeps the last list when offline.
  Future<void> loadAnnouncements() async {
    try {
      _announcements = await _repo.loadAnnouncements();
      _announcementsFailed = false;
    } catch (_) {
      _announcementsFailed = true;
    }
    _announcementsLoaded = true;
    notifyListeners();
  }

  /// Throws [SetupError]. Returns how many people it was sent to.
  Future<int> publishAnnouncement(
      {required String title, required String body, required Set<AnnouncementAudience> audience}) async {
    final n = await _repo.publishAnnouncement(title: title, body: body, audience: audience);
    await loadAnnouncements();
    return n;
  }

  /// Throws [SetupError].
  Future<void> deleteAnnouncement(String id) async {
    await _repo.deleteAnnouncement(id);
    _announcements = [for (final a in _announcements) if (a.id != id) a];
    _items = [for (final n in _items) if (n.announcementId != id) n];
    notifyListeners();
  }

  /// Marks the notifications of announcement [id] read.
  Future<void> markAnnouncementRead(String? id) =>
      _markRead([for (final n in _items) if (!n.read && n.isAnnouncement && n.announcementId == id) n.id]);

  Future<void> _markRead(List<String> ids) async {
    if (ids.isEmpty) return;
    _items = [for (final n in _items) ids.contains(n.id) ? n.asRead() : n];
    notifyListeners();
    try {
      await _repo.markRead(ids);
    } catch (_) {
      // Offline: they show as unread again on the next load.
    }
  }

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
    _announcements = const [];
    _announcementsLoaded = false;
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

/// The person's notifications, newest first, and the إخبارات العامة in a second tab. Opening
/// it marks the notifications read (with [keepMessages], all but the notes and replies).
/// Pops with the notification tapped, if any. With [canPublish] (the مشرف العام) the second
/// tab has the button for a new إخبار عام.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key, this.keepMessages = false, this.canPublish = false, this.openAnnouncements = false});

  final bool keepMessages;
  final bool canPublish;

  /// Start on the إخبارات العامة tab.
  final bool openAnnouncements;

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> with SingleTickerProviderStateMixin {
  /// Unread when the screen opened: they stay highlighted while it is open.
  late final Set<String> _fresh;
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    final store = InboxScope.read(context)!;
    _fresh = {for (final n in store.items) if (!n.read) n.id};
    final news = widget.openAnnouncements || store.unreadAnnouncements.isNotEmpty;
    _tabs = TabController(length: 2, vsync: this, initialIndex: news ? 1 : 0);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      unawaited(store.loadAnnouncements());
      await store.load();
      if (!mounted) return;
      setState(() => _fresh.addAll([for (final n in store.items) if (!n.read) n.id]));
      await store.markAllRead(keepMessages: widget.keepMessages);
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _tap(AppNotification n) async {
    if (!n.isAnnouncement) {
      Navigator.pop(context, n);
      return;
    }
    final store = InboxScope.read(context)!;
    final a = store.announcement(n.announcementId);
    if (a == null) {
      _tabs.animateTo(1);
      return;
    }
    await openAnnouncement(context, a, canDelete: widget.canPublish);
  }

  @override
  Widget build(BuildContext context) {
    final store = InboxScope.of(context)!;
    final text = Theme.of(context).textTheme;
    final items = store.items;
    final freshNews = [for (final n in items) if (n.isAnnouncement && _fresh.contains(n.id)) n].length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('الإشعارات'),
        bottom: TabBar(
          controller: _tabs,
          tabs: [
            const Tab(key: Key('tab-notifications'), text: 'الإشعارات'),
            Tab(
              key: const Key('tab-announcements'),
              child: Badge(
                isLabelVisible: freshNews > 0,
                backgroundColor: RaeedColors.error,
                label: Text('$freshNews'),
                offset: const Offset(14, -4),
                child: const Text('الإخبارات العامة'),
              ),
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          RefreshIndicator(
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
                      final color = n.isAnnouncement ? RaeedColors.starEnd : RaeedColors.blue;
                      return ListTile(
                        key: Key('notification-${n.id}'),
                        tileColor: fresh ? color.withValues(alpha: 0.07) : null,
                        leading: CircleAvatar(
                          backgroundColor: color.withValues(alpha: 0.14),
                          child: Icon(n.icon, color: color, size: 20),
                        ),
                        title: Text(n.title, style: fresh ? const TextStyle(fontWeight: FontWeight.w700) : null),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (n.body.isNotEmpty) Text(n.body, maxLines: 3, overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 2),
                            Text(notificationTime(n.createdAt), style: text.bodySmall?.copyWith(color: RaeedColors.grey)),
                          ],
                        ),
                        onTap: () => _tap(n),
                      );
                    },
                  ),
          ),
          AnnouncementsList(canPublish: widget.canPublish, fresh: _fresh),
        ],
      ),
    );
  }
}

/// When a notification arrived: «الآن», «قبل 5 د», «اليوم 14:30», «أمس 09:00» or «28/11 09:00».
String notificationTime(DateTime t) {
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
