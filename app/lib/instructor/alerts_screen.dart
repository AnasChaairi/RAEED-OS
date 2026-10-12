import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../auth/phone.dart';
import '../setup/setup_repository.dart';
import '../setup/widgets.dart';
import '../theme/raeed_theme.dart';
import '../widgets/form_error.dart';
import 'models.dart';
import 'widgets.dart';

/// The التنبيهات tab: open alerts first, each with its next action, then the ones closed
/// this month. Shared between co-instructors, so whoever calls first closes it for both.
class AlertsTab extends StatelessWidget {
  const AlertsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return InstructorLoadGate(
      builder: (context, data) {
        final store = InstructorScope.of(context);
        final open = data.openAlerts;
        final closed = data.alerts.where((a) => !a.open).toList();
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            if (store.offline) const OfflineBanner(text: 'لا يوجد إنترنت. التنبيهات المعروضة من آخر اتصال.'),
            const SectionLabel('مفتوحة'),
            if (open.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  'لا توجد تنبيهات مفتوحة.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: RaeedColors.grey),
                ),
              ),
            for (final a in open) ...[AlertCard(alert: a, data: data), const SizedBox(height: 8)],
            if (closed.isNotEmpty) ...[
              const SectionLabel('مغلقة هذا الشهر'),
              for (final a in closed) ...[_ClosedRow(alert: a, data: data), const SizedBox(height: 8)],
            ],
          ],
        );
      },
    );
  }
}

/// The two missed sessions: "30 يناير و 6 فبراير".
String missedDays(AbsenceAlert a, InstructorSnapshot data) {
  final days = [
    for (final id in a.sessionIds.reversed)
      if (data.session(id) case final s?) '${s.date.day} ${monthNames[s.date.month - 1]}',
  ];
  return days.join(' و ');
}

/// An open alert, as on the Alerts and Today tabs.
class AlertCard extends StatelessWidget {
  const AlertCard({super.key, required this.alert, required this.data});

  final AbsenceAlert alert;
  final InstructorSnapshot data;

  @override
  Widget build(BuildContext context) {
    final store = InstructorScope.of(context);
    final text = Theme.of(context).textTheme;
    final child = data.child(alert.childId);
    final tried = alert.lastAttemptAt != null;
    final who = alert.lastAttemptBy == store.personId
        ? 'اتصلت'
        : 'اتصل ${data.staffNames[alert.lastAttemptBy] ?? 'مؤطر'}';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: RaeedColors.starSoft, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${child?.fullName ?? ''} · ${tried ? 'لم يرد ولي الأمر' : 'غياب حصتين'}',
                  style: text.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              Text(
                daysAgo(tried ? alert.lastAttemptAt! : alert.createdAt, store.now()),
                style: text.bodySmall?.copyWith(color: RaeedColors.grey),
              ),
            ],
          ),
          Text(
            tried
                ? '$who ${daysAgo(alert.lastAttemptAt!, store.now())}، يبقى التنبيه مفتوحاً'
                : '${missedDays(alert, data)} بدون عذر',
            style: text.bodySmall,
          ),
          const SizedBox(height: 8),
          FilledButton(
            key: Key('follow-up-${alert.id}'),
            onPressed: () =>
                Navigator.push(context, MaterialPageRoute<void>(builder: (_) => FollowUpScreen(alertId: alert.id))),
            child: Text(tried ? 'حاول مرة أخرى' : 'تتبّع الآن'),
          ),
        ],
      ),
    );
  }
}

class _ClosedRow extends StatelessWidget {
  const _ClosedRow({required this.alert, required this.data});

  final AbsenceAlert alert;
  final InstructorSnapshot data;

  @override
  Widget build(BuildContext context) {
    final by = data.staffNames[alert.closedBy] ?? '';
    return SetupRow(
      leading: InitialAvatar(data.child(alert.childId)?.fullName ?? ''),
      title: data.child(alert.childId)?.fullName ?? '',
      lines: [
        'تم التواصل: ${alert.reason ?? ''}${by.isEmpty ? '' : ' · $by'}',
        if (alert.closedAt != null) '${alert.closedAt!.day} ${monthNames[alert.closedAt!.month - 1]}',
      ],
      trailing: Icon(Icons.check_circle, color: const Color(0xFF1C7A55).withValues(alpha: 0.8), size: 20),
    );
  }
}

/// Call the parent, then log the outcome. Reaching them closes the alert with the
/// reason; "no answer" keeps it open.
class FollowUpScreen extends StatefulWidget {
  const FollowUpScreen({super.key, required this.alertId});

  final String alertId;

  @override
  State<FollowUpScreen> createState() => _FollowUpScreenState();
}

class _FollowUpScreenState extends State<FollowUpScreen> {
  final _reason = TextEditingController();
  bool _reached = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _save(AbsenceAlert alert) async {
    if (_reached && _reason.text.trim().isEmpty) return setState(() => _error = 'اكتب السبب الذي ذكره ولي الأمر');
    setState(() {
      _busy = true;
      _error = null;
    });
    final store = InstructorScope.read(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (_reached) {
        await store.closeAlert(alert, _reason.text.trim());
      } else {
        await store.logAttempt(alert);
      }
      if (!mounted) return;
      Navigator.pop(context);
      messenger.showSnackBar(
        SnackBar(content: Text(_reached ? 'أُغلق التنبيه ✓' : 'سُجّلت المحاولة. يبقى التنبيه مفتوحاً.')),
      );
    } on SetupError catch (e) {
      if (mounted) setState(() => _error = setupFailureMessage(e.failure));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = InstructorScope.of(context).data;
    final alert = data.alerts.where((a) => a.id == widget.alertId).firstOrNull;
    if (alert == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('أُغلق هذا التنبيه.')),
      );
    }
    final child = data.child(alert.childId);
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 68,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('تتبّع الغياب'),
            Text(data.group(alert.groupId)?.name ?? '', style: text.bodySmall?.copyWith(color: RaeedColors.grey)),
          ],
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(child?.fullName ?? '', style: text.titleLarge),
                    Text(
                      'غاب يوم ${missedDays(alert, data)} بدون عذر',
                      style: text.bodyMedium?.copyWith(color: RaeedColors.grey),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            if (child == null || child.parents.isEmpty)
              const WarningCard(title: 'لا يوجد ولي أمر مسجّل', lines: ['تواصل مع المشرف لإضافة رقم ولي الأمر.'])
            else
              for (final p in child.parents) ...[_ParentCard(parent: p), const SizedBox(height: 8)],
            const SectionLabel('نتيجة الاتصال'),
            RadioGroup<bool>(
              groupValue: _reached,
              onChanged: (v) => setState(() => _reached = v ?? true),
              child: Column(
                children: [
                  _Outcome(key: const Key('outcome-reached'), value: true, label: 'تم التواصل، السبب معروف'),
                  const SizedBox(height: 6),
                  _Outcome(key: const Key('outcome-no-answer'), value: false, label: 'لم يرد، يبقى التنبيه مفتوحاً'),
                ],
              ),
            ),
            if (_reached) ...[
              const SectionLabel('السبب'),
              TextField(
                key: const Key('follow-up-reason'),
                controller: _reason,
                maxLines: 3,
                decoration: const InputDecoration(hintText: 'مثلاً: مرض، سفر عائلي…'),
              ),
            ],
            if (_error != null) ...[const SizedBox(height: 12), FormError(_error!)],
            const SizedBox(height: 20),
            FilledButton(
              key: const Key('save-follow-up'),
              onPressed: _busy ? null : () => _save(alert),
              child: _busy ? const ButtonSpinner() : Text(_reached ? 'إغلاق التنبيه' : 'تسجيل المحاولة'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Outcome extends StatelessWidget {
  const _Outcome({super.key, required this.value, required this.label});

  final bool value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: RadioListTile<bool>(value: value, title: Text(label), dense: true),
    );
  }
}

class _ParentCard extends StatelessWidget {
  const _ParentCard({required this.parent});

  final ParentContact parent;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final digits = parent.phone.replaceAll(RegExp(r'[^0-9]'), '');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('ولي الأمر: ${parent.fullName}', style: text.titleSmall),
            Text(
              formatPhone(parent.phone),
              textDirection: TextDirection.ltr,
              textAlign: TextAlign.end,
              style: text.titleSmall?.copyWith(color: RaeedColors.blue, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => launchUrl(Uri.parse('tel:${parent.phone}')),
                    icon: const Icon(Icons.call),
                    label: const Text('اتصال'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: const Color(0xFF1C7A55)),
                    onPressed: () =>
                        launchUrl(Uri.parse('https://wa.me/$digits'), mode: LaunchMode.externalApplication),
                    icon: const Icon(Icons.chat),
                    label: const Text('واتساب'),
                  ),
                ),
              ],
            ),
            Text('بعد التواصل، سجّل النتيجة في الأسفل.', style: text.bodySmall?.copyWith(color: RaeedColors.grey)),
          ],
        ),
      ),
    );
  }
}
