import 'package:flutter/material.dart';

import '../setup/setup_repository.dart';
import '../setup/widgets.dart';
import '../theme/raeed_theme.dart';
import '../widgets/form_error.dart';
import 'inbox.dart';

/// Who a إخبار عام is for. None picked means everyone.
enum AnnouncementAudience {
  parent('parent', 'أولياء الأمور'),
  instructor('instructor', 'المؤطرون'),
  supervisor('category_supervisor', 'مشرفو الفئات'),
  advisor('advisor', 'المشرفون العامون');

  const AnnouncementAudience(this.dbName, this.label);

  final String dbName;
  final String label;

  static AnnouncementAudience? fromDb(String value) {
    for (final a in values) {
      if (a.dbName == value) return a;
    }
    return null;
  }
}

/// A إخبار عام: news from the academy, published by a مشرف عام.
class Announcement {
  const Announcement({
    required this.id,
    required this.title,
    required this.body,
    required this.createdAt,
    this.audience = const {},
    this.authorName,
    this.recipients = 0,
  });

  factory Announcement.fromRow(Map<String, dynamic> r) => Announcement(
        id: r['id'] as String,
        title: r['title'] as String,
        body: r['body'] as String,
        createdAt: DateTime.parse(r['created_at'] as String).toLocal(),
        audience: {
          for (final v in (r['audience'] as List? ?? const []))
            if (AnnouncementAudience.fromDb(v as String) case final a?) a,
        },
        authorName: (r['author'] as Map?)?['full_name'] as String?,
        recipients: (r['recipients'] as num?)?.toInt() ?? 0,
      );

  final String id;
  final String title;
  final String body;
  final DateTime createdAt;

  /// Empty: everyone.
  final Set<AnnouncementAudience> audience;
  final String? authorName;

  /// How many people it was sent to.
  final int recipients;

  String get audienceLabel => audience.isEmpty
      ? 'الجميع'
      : [for (final a in AnnouncementAudience.values) if (audience.contains(a)) a.label].join('، ');
}

/// The «الإخبارات العامة» tab of the notifications screen.
class AnnouncementsList extends StatelessWidget {
  const AnnouncementsList({super.key, required this.canPublish, this.fresh = const {}});

  final bool canPublish;

  /// Notification ids that were unread when the screen opened.
  final Set<String> fresh;

  @override
  Widget build(BuildContext context) {
    final store = InboxScope.of(context)!;
    final text = Theme.of(context).textTheme;
    final list = store.announcements;
    final freshIds = {
      for (final n in store.items)
        if (n.isAnnouncement && fresh.contains(n.id)) n.announcementId,
    };
    return RefreshIndicator(
      onRefresh: store.loadAnnouncements,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          if (canPublish) ...[
            FilledButton.icon(
              key: const Key('new-announcement'),
              onPressed: () => Navigator.push<void>(
                context,
                MaterialPageRoute(builder: (_) => const ComposeAnnouncementScreen()),
              ),
              icon: const Icon(Icons.campaign),
              label: const Text('إخبار عام جديد'),
            ),
            const SizedBox(height: 16),
          ],
          if (list.isEmpty) ...[
            const SizedBox(height: 80),
            Icon(Icons.campaign_outlined, size: 56, color: RaeedColors.grey.withValues(alpha: 0.6)),
            const SizedBox(height: 12),
            Text(
              !store.announcementsLoaded
                  ? 'جارٍ التحميل…'
                  : store.announcementsFailed
                      ? 'تعذّر تحميل الإخبارات. اسحب للأسفل للمحاولة مجدداً.'
                      : 'لا توجد إخبارات عامة بعد.',
              textAlign: TextAlign.center,
              style: text.bodyMedium?.copyWith(color: RaeedColors.grey),
            ),
          ],
          for (final a in list) ...[
            AnnouncementCard(
              announcement: a,
              fresh: freshIds.contains(a.id),
              showAudience: canPublish,
              onTap: () => openAnnouncement(context, a, canDelete: canPublish),
            ),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

class AnnouncementCard extends StatelessWidget {
  const AnnouncementCard({
    super.key,
    required this.announcement,
    required this.onTap,
    this.fresh = false,
    this.showAudience = false,
  });

  final Announcement announcement;
  final VoidCallback onTap;
  final bool fresh;
  final bool showAudience;

  @override
  Widget build(BuildContext context) {
    final a = announcement;
    final text = Theme.of(context).textTheme;
    return Material(
      key: Key('announcement-${a.id}'),
      color: fresh ? RaeedColors.starSoft : RaeedColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: fresh ? RaeedColors.starStart : RaeedColors.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: const BoxDecoration(gradient: RaeedColors.star, shape: BoxShape.circle),
                    child: const Icon(Icons.campaign, color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(a.title, style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                        Text(
                          [notificationTime(a.createdAt), if (a.authorName != null) a.authorName!].join(' · '),
                          style: text.bodySmall?.copyWith(color: RaeedColors.grey),
                        ),
                      ],
                    ),
                  ),
                  if (fresh)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: RaeedColors.error, borderRadius: BorderRadius.circular(10)),
                      child: Text('جديد', style: text.labelSmall?.copyWith(color: Colors.white)),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Text(a.body, maxLines: 4, overflow: TextOverflow.ellipsis, style: text.bodyMedium),
              if (showAudience) ...[
                const SizedBox(height: 8),
                Text(
                  'إلى: ${a.audienceLabel} · أُرسل إلى ${a.recipients} شخصاً',
                  style: text.bodySmall?.copyWith(color: RaeedColors.blue),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Opens [a] in full and marks its notification read.
Future<void> openAnnouncement(BuildContext context, Announcement a, {bool canDelete = false}) {
  InboxScope.read(context)?.markAnnouncementRead(a.id);
  return Navigator.push<void>(
    context,
    MaterialPageRoute(builder: (_) => AnnouncementScreen(announcement: a, canDelete: canDelete)),
  );
}

class AnnouncementScreen extends StatefulWidget {
  const AnnouncementScreen({super.key, required this.announcement, this.canDelete = false});

  final Announcement announcement;
  final bool canDelete;

  @override
  State<AnnouncementScreen> createState() => _AnnouncementScreenState();
}

class _AnnouncementScreenState extends State<AnnouncementScreen> {
  bool _deleting = false;

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('حذف هذا الإخبار؟'),
        content: const Text('يختفي من الإخبارات العامة ومن إشعارات كل من وصله.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('إلغاء')),
          TextButton(
            key: const Key('confirm-delete-announcement'),
            style: TextButton.styleFrom(foregroundColor: RaeedColors.error),
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _deleting = true);
    try {
      await InboxScope.read(context)!.deleteAnnouncement(widget.announcement.id);
      if (mounted) Navigator.pop(context);
    } on SetupError catch (e) {
      if (!mounted) return;
      setState(() => _deleting = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(setupFailureMessage(e.failure))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.announcement;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('إخبار عام'),
        actions: [
          if (widget.canDelete)
            IconButton(
              key: const Key('delete-announcement'),
              tooltip: 'حذف',
              onPressed: _deleting ? null : _delete,
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(gradient: RaeedColors.star, shape: BoxShape.circle),
                child: const Icon(Icons.campaign, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(a.title, style: text.headlineSmall)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            [notificationTime(a.createdAt), if (a.authorName != null) a.authorName!].join(' · '),
            style: text.bodySmall?.copyWith(color: RaeedColors.grey),
          ),
          if (widget.canDelete) ...[
            const SizedBox(height: 4),
            Text(
              'إلى: ${a.audienceLabel} · أُرسل إلى ${a.recipients} شخصاً',
              style: text.bodySmall?.copyWith(color: RaeedColors.blue),
            ),
          ],
          const SizedBox(height: 20),
          SelectableText(a.body, style: text.bodyLarge?.copyWith(height: 1.6)),
        ],
      ),
    );
  }
}

/// The مشرف العام writes a إخبار عام and picks who gets it. Everyone by default.
class ComposeAnnouncementScreen extends StatefulWidget {
  const ComposeAnnouncementScreen({super.key});

  @override
  State<ComposeAnnouncementScreen> createState() => _ComposeAnnouncementScreenState();
}

class _ComposeAnnouncementScreenState extends State<ComposeAnnouncementScreen> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  final _form = GlobalKey<FormState>();
  final _audience = <AnnouncementAudience>{};
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  void _toggle(AnnouncementAudience a, bool on) => setState(() {
        on ? _audience.add(a) : _audience.remove(a);
        // Every role picked is everyone.
        if (_audience.length == AnnouncementAudience.values.length) _audience.clear();
      });

  Future<void> _send() async {
    if (!_form.currentState!.validate()) return;
    final who = _audience.isEmpty
        ? 'جميع مستخدمي التطبيق'
        : [for (final a in AnnouncementAudience.values) if (_audience.contains(a)) a.label].join('، ');
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('نشر الإخبار؟'),
        content: Text('يصل إشعار فوري إلى: $who.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('رجوع')),
          FilledButton(
            key: const Key('confirm-publish'),
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('نشر'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final n = await InboxScope.read(context)!.publishAnnouncement(
        title: _title.text.trim(),
        body: _body.text.trim(),
        audience: Set.of(_audience),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('نُشر الإخبار وأُرسل إلى $n شخصاً.')));
      Navigator.pop(context);
    } on SetupError catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = setupFailureMessage(e.failure);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('إخبار عام جديد')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              key: const Key('announcement-title'),
              controller: _title,
              maxLength: 120,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'العنوان', hintText: 'مثال: انطلاق الموسم الجديد'),
              validator: (v) => (v ?? '').trim().isEmpty ? 'اكتب عنواناً.' : null,
            ),
            const SizedBox(height: 8),
            TextFormField(
              key: const Key('announcement-body'),
              controller: _body,
              maxLength: 4000,
              minLines: 5,
              maxLines: 12,
              keyboardType: TextInputType.multiline,
              decoration: const InputDecoration(labelText: 'نص الإخبار', alignLabelWithHint: true),
              validator: (v) => (v ?? '').trim().isEmpty ? 'اكتب نص الإخبار.' : null,
            ),
            const SizedBox(height: 16),
            Text('إلى من؟', style: text.titleSmall),
            const SizedBox(height: 4),
            Text(
              'الافتراضي: الجميع. اختر فئة أو أكثر لتخصيص الإخبار.',
              style: text.bodySmall?.copyWith(color: RaeedColors.grey),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  key: const Key('audience-all'),
                  label: const Text('الجميع'),
                  selected: _audience.isEmpty,
                  onSelected: (_) => setState(_audience.clear),
                ),
                for (final a in AnnouncementAudience.values)
                  FilterChip(
                    key: Key('audience-${a.dbName}'),
                    label: Text(a.label),
                    selected: _audience.contains(a),
                    onSelected: (on) => _toggle(a, on),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            if (_error != null) ...[FormError(_error!), const SizedBox(height: 12)],
            FilledButton.icon(
              key: const Key('publish-announcement'),
              onPressed: _sending ? null : _send,
              icon: _sending ? const ButtonSpinner() : const Icon(Icons.send),
              label: const Text('نشر وإرسال الإشعار'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Above the tabs while a إخبار عام is unread: its title, to read it or put it aside.
class AnnouncementBanner extends StatelessWidget {
  const AnnouncementBanner({super.key, required this.canDelete});

  final bool canDelete;

  @override
  Widget build(BuildContext context) {
    final store = InboxScope.of(context);
    final unread = store?.unreadAnnouncements ?? const [];
    if (store == null || unread.isEmpty) return const SizedBox.shrink();
    final n = unread.first;
    final text = Theme.of(context).textTheme;
    return Material(
      key: const Key('announcement-banner'),
      color: RaeedColors.starSoft,
      child: InkWell(
        onTap: () async {
          await store.loadAnnouncements();
          if (!context.mounted) return;
          final a = store.announcement(n.announcementId);
          if (a != null) {
            await openAnnouncement(context, a, canDelete: canDelete);
          } else {
            await Navigator.push<void>(
              context,
              MaterialPageRoute(builder: (_) => NotificationsScreen(canPublish: canDelete, openAnnouncements: true)),
            );
          }
        },
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 10, 4, 10),
          child: Row(
            children: [
              const Icon(Icons.campaign, color: RaeedColors.starEnd),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      unread.length > 1 ? 'إخبارات عامة جديدة (${unread.length})' : 'إخبار عام جديد',
                      style: text.labelMedium?.copyWith(color: RaeedColors.starEnd, fontWeight: FontWeight.w700),
                    ),
                    Text(
                      n.title.replaceFirst('إخبار عام: ', ''),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              Text('قراءة', style: text.labelLarge?.copyWith(color: RaeedColors.blue)),
              IconButton(
                key: const Key('dismiss-announcement'),
                tooltip: 'لاحقاً',
                onPressed: () => store.markAnnouncementRead(n.announcementId),
                icon: const Icon(Icons.close, size: 20),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
