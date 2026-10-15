import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../setup/setup_repository.dart';
import '../setup/widgets.dart';
import '../theme/raeed_theme.dart';
import 'attendance_screen.dart';
import 'models.dart';
import 'session_form_screen.dart';
import 'widgets.dart';

/// The الحصص tab: the week, Sunday to Saturday. Instructors see their groups' sessions;
/// the advisor sees every group's and is the one who plans them.
class SessionsTab extends StatefulWidget {
  const SessionsTab({super.key});

  @override
  State<SessionsTab> createState() => _SessionsTabState();
}

class _SessionsTabState extends State<SessionsTab> {
  int _weekOffset = 0;

  @override
  Widget build(BuildContext context) {
    final store = InstructorScope.of(context);
    final now = store.now();
    final today = dayOnly(now);
    final weekStart = today.subtract(Duration(days: dayOfWeek(today))).add(Duration(days: 7 * _weekOffset));
    final weekEnd = weekStart.add(const Duration(days: 6));
    final text = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: !store.schedules || store.data.groups.isEmpty
          ? null
          : FloatingActionButton.extended(
              key: const Key('new-session'),
              heroTag: 'new-session',
              onPressed: () => openSessionForm(context),
              icon: const Icon(Icons.add),
              label: const Text('حصة جديدة'),
            ),
      body: InstructorLoadGate(
        builder: (context, data) {
          final days = <DateTime, List<Session>>{};
          for (final s in data.sessions) {
            if (s.date.isBefore(weekStart) || s.date.isAfter(weekEnd)) continue;
            days.putIfAbsent(s.date, () => []).add(s);
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
            children: [
              if (store.offline) const OfflineBanner(),
              Row(
                children: [
                  IconButton(
                    key: const Key('previous-week'),
                    tooltip: 'الأسبوع السابق',
                    onPressed: () => setState(() => _weekOffset--),
                    icon: const Icon(Icons.chevron_right),
                  ),
                  Expanded(
                    child: Text(
                      '${_weekOffset == 0 ? 'هذا الأسبوع' : 'الأسبوع'} · من ${weekStart.day}'
                      '${weekStart.month == weekEnd.month ? '' : ' ${monthNames[weekStart.month - 1]}'}'
                      ' إلى ${weekEnd.day} ${monthNames[weekEnd.month - 1]}',
                      key: const Key('week-label'),
                      textAlign: TextAlign.center,
                      style: text.titleSmall,
                    ),
                  ),
                  IconButton(
                    key: const Key('next-week'),
                    tooltip: 'الأسبوع التالي',
                    onPressed: () => setState(() => _weekOffset++),
                    icon: const Icon(Icons.chevron_left),
                  ),
                ],
              ),
              if (data.groups.isEmpty)
                _Hint(store.schedules
                    ? 'لا توجد فئات بعد. أنشئ فئة من تبويب الفئات ثم خطّط حصصها هنا.'
                    : 'لم تُسند إليك أي فئة بعد. تواصل مع المشرف.')
              else if (days.isEmpty)
                _Hint(store.schedules
                    ? 'لا حصص هذا الأسبوع. أضف حصة بالزر في الأسفل.'
                    : 'لا حصص هذا الأسبوع. يخطّط المشرف الحصص وتظهر هنا.'),
              for (final e in days.entries) ...[
                SectionLabel(dayLabel(e.key, now)),
                for (final s in e.value) ...[
                  SessionCard(session: s, data: data, onTap: () => openSession(context, s.id)),
                  const SizedBox(height: 8),
                ],
              ],
            ],
          );
        },
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 40),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: const TextStyle(color: RaeedColors.grey),
    ),
  );
}

Future<void> openSession(BuildContext context, String id) =>
    Navigator.push(context, MaterialPageRoute<void>(builder: (_) => SessionDetailScreen(sessionId: id)));

Future<void> openAttendance(BuildContext context, String sessionId) =>
    Navigator.push(context, MaterialPageRoute<void>(builder: (_) => AttendanceScreen(sessionId: sessionId)));

/// One session: when, where, what is attached, and its actions.
class SessionDetailScreen extends StatelessWidget {
  const SessionDetailScreen({super.key, required this.sessionId});

  final String sessionId;

  @override
  Widget build(BuildContext context) {
    final store = InstructorScope.of(context);
    final data = store.data;
    final s = data.session(sessionId);
    if (s == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('لم تعد هذه الحصة موجودة.')),
      );
    }
    final group = data.group(s.groupId);
    final text = Theme.of(context).textTheme;
    final started = !s.startsAt.isAfter(store.now().add(const Duration(minutes: 30)));
    final taken = data.attendanceFor(s.id).length;
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 68,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.title),
            Text(group?.name ?? '', style: text.bodySmall?.copyWith(color: RaeedColors.grey)),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(dayLabel(s.date, store.now()), style: text.headlineSmall),
                  Text(s.timeLabel, style: text.titleMedium?.copyWith(color: RaeedColors.grey)),
                  const SizedBox(height: 8),
                  Text(s.away ? 'خارج المقر' : 'جمعية سماء · الطابق ${floors[s.floor] ?? ''}'),
                  if (s.instructorIds.isNotEmpty)
                    Text(
                      'المؤطرون: ${[for (final id in s.instructorIds) data.staffNames[id] ?? 'مؤطر'].join('، ')}',
                      key: const Key('session-instructors'),
                    ),
                  if (s.away) ...[
                    if (s.address != null) Text(s.address!),
                    if (s.dropoffTime != null || s.dropoffPlace != null)
                      Text(
                        'التسليم: ${[if (s.dropoffTime != null) formatTime(s.dropoffTime!), ?s.dropoffPlace].join(' · ')}',
                      ),
                    if (s.pickupTime != null)
                      Text('الاستلام: ${[formatTime(s.pickupTime!), ?s.pickupPlace].join(' · ')}'),
                    if (s.mapUrl != null && s.mapUrl!.isNotEmpty)
                      TextButton.icon(
                        onPressed: () => launchUrl(Uri.parse(s.mapUrl!), mode: LaunchMode.externalApplication),
                        icon: const Icon(Icons.map_outlined),
                        label: const Text('فتح الخريطة'),
                      ),
                  ],
                  const SizedBox(height: 6),
                  Text(
                    [
                      s.seriesId == null ? 'مرة واحدة' : 'أسبوعي',
                      if (s.status == SessionStatus.changed) 'تغيّر الموعد',
                    ].join(' · '),
                    style: text.bodySmall?.copyWith(color: RaeedColors.grey),
                  ),
                  if (s.cancelled)
                    Text(
                      'ملغاة${(s.cancelReason ?? '').isEmpty ? '' : ': ${s.cancelReason}'}',
                      style: text.bodyMedium?.copyWith(color: RaeedColors.error, fontWeight: FontWeight.w600),
                    ),
                ],
              ),
            ),
          ),
          if (s.materials.isNotEmpty) ...[
            const SectionLabel('المواد'),
            for (final m in s.materials) MaterialRow(material: m),
          ],
          const SizedBox(height: 16),
          if (!store.schedules && !s.cancelled && started)
            FilledButton.icon(
              key: const Key('take-attendance'),
              onPressed: () => openAttendance(context, s.id),
              icon: const Icon(Icons.fact_check_outlined),
              label: Text(taken > 0 ? 'تعديل الحضور' : 'تسجيل الحضور'),
            ),
          if (store.schedules && !s.cancelled) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const Key('edit-session'),
              onPressed: () => openSessionForm(context, session: s),
              icon: const Icon(Icons.edit_outlined),
              label: const Text('تعديل الحصة'),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              key: const Key('cancel-session'),
              style: TextButton.styleFrom(foregroundColor: RaeedColors.error),
              onPressed: () => _cancel(context, s),
              icon: const Icon(Icons.event_busy_outlined),
              label: const Text('إلغاء الحصة'),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _cancel(BuildContext context, Session s) async {
    final result = await showDialog<(String, bool)>(
      context: context,
      builder: (_) => _CancelDialog(session: s),
    );
    if (result == null || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await InstructorScope.read(context).cancelSession(s, result.$1, upcoming: result.$2);
      messenger.showSnackBar(const SnackBar(content: Text('أُلغيت الحصة، وسيُشعَر أولياء الأمور.')));
    } on SetupError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(setupFailureMessage(e.failure))));
    }
  }
}

/// A material link that opens in YouTube, Drive or the browser.
class MaterialRow extends StatelessWidget {
  const MaterialRow({super.key, required this.material, this.onRemove});

  final SessionMaterial material;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        dense: true,
        leading: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(
            border: Border.all(color: RaeedColors.blue),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            material.kindLabel,
            style: const TextStyle(color: RaeedColors.blue, fontWeight: FontWeight.w700, fontSize: 11),
          ),
        ),
        title: Text(material.label),
        onTap: () => launchUrl(Uri.parse(material.url), mode: LaunchMode.externalApplication),
        trailing: onRemove == null
            ? const Icon(Icons.chevron_left)
            : IconButton(tooltip: 'حذف', onPressed: onRemove, icon: const Icon(Icons.close)),
      ),
    );
  }
}

/// For a session in a series: change this one only, or all upcoming ones. Null when
/// the person backs out.
Future<bool?> askSeriesScope(BuildContext context, {required String action}) => showDialog<bool>(
  context: context,
  builder: (d) => SimpleDialog(
    title: Text('$action حصة متكررة'),
    children: [
      SimpleDialogOption(
        key: const Key('scope-one'),
        onPressed: () => Navigator.pop(d, false),
        child: const Padding(padding: EdgeInsets.symmetric(vertical: 6), child: Text('هذه الحصة فقط')),
      ),
      SimpleDialogOption(
        key: const Key('scope-upcoming'),
        onPressed: () => Navigator.pop(d, true),
        child: const Padding(padding: EdgeInsets.symmetric(vertical: 6), child: Text('كل الحصص القادمة')),
      ),
    ],
  ),
);

class _CancelDialog extends StatefulWidget {
  const _CancelDialog({required this.session});

  final Session session;

  @override
  State<_CancelDialog> createState() => _CancelDialogState();
}

class _CancelDialogState extends State<_CancelDialog> {
  final _reason = TextEditingController();
  bool _upcoming = false;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('إلغاء الحصة؟'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('يصل إشعار بالإلغاء لأولياء أمور الفئة.'),
          const SizedBox(height: 10),
          TextField(
            key: const Key('cancel-reason'),
            controller: _reason,
            decoration: const InputDecoration(labelText: 'السبب (اختياري)', hintText: 'مثلاً: عطلة منتصف الفصل'),
          ),
          if (widget.session.seriesId != null) ...[
            const SizedBox(height: 8),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('هذه الحصة فقط')),
                ButtonSegment(value: true, label: Text('كل القادمة')),
              ],
              selected: {_upcoming},
              onSelectionChanged: (v) => setState(() => _upcoming = v.first),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('رجوع')),
        FilledButton(
          key: const Key('confirm-cancel'),
          style: FilledButton.styleFrom(backgroundColor: RaeedColors.error),
          onPressed: () => Navigator.pop(context, (_reason.text.trim(), _upcoming)),
          child: const Text('إلغاء الحصة'),
        ),
      ],
    );
  }
}
