import 'package:flutter/material.dart';

import '../setup/widgets.dart';
import '../theme/raeed_theme.dart';
import 'alerts_screen.dart';
import 'models.dart';
import 'sessions_screen.dart';
import 'widgets.dart';

/// The اليوم tab: the session happening now with one button to take attendance, open
/// absence alerts, today's sessions, and attendance still waiting to be sent.
class TodayTab extends StatelessWidget {
  const TodayTab({super.key});

  @override
  Widget build(BuildContext context) {
    return InstructorLoadGate(
      builder: (context, data) {
        final store = InstructorScope.of(context);
        final now = store.now();
        final today = data.sessionsOn(now);
        final next = data.nextSession(now);
        final hero = next != null && next.date == dayOnly(now) ? next : null;
        final text = Theme.of(context).textTheme;
        final waiting = store.waitingSessions;
        final sentToday = store.sent.entries.where((e) => dayOnly(e.value) == dayOnly(now) && !waiting.contains(e.key));
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            if (store.offline) ...[const OfflineBanner(), const SizedBox(height: 10)],
            if (data.groups.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Text(
                  'لم تُسند إليك أي فئة بعد. تواصل مع المشرف.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: RaeedColors.grey),
                ),
              )
            else if (hero != null)
              _Hero(session: hero, data: data, now: now)
            else
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Text(
                    next == null
                        ? 'لا حصص اليوم ولا حصص قادمة. أضف حصة من تبويب الحصص.'
                        : 'لا حصص اليوم. الحصة القادمة: ${data.group(next.groupId)?.name ?? ''} · ${dayLabel(next.date, now)} ${formatTime(next.start)}',
                    style: text.bodyMedium,
                  ),
                ),
              ),
            for (final a in data.openAlerts.take(3)) ...[const SizedBox(height: 10), AlertCard(alert: a, data: data)],
            if (today.isNotEmpty) ...[
              const SectionLabel('حصص اليوم'),
              for (final s in today) ...[
                SessionCard(session: s, data: data, onTap: () => openSession(context, s.id)),
                const SizedBox(height: 8),
              ],
            ],
            if (waiting.isNotEmpty || sentToday.isNotEmpty) ...[
              const SectionLabel('إرسال الحضور'),
              for (final id in waiting) _QueueRow(label: _sessionName(data, id, now), waiting: true),
              for (final e in sentToday) _QueueRow(label: _sessionName(data, e.key, now), waiting: false),
              if (waiting.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  'تنبيهات الغياب تنطلق بعد الإرسال، وليس قبله.',
                  style: text.bodySmall?.copyWith(color: RaeedColors.grey),
                ),
                TextButton.icon(
                  key: const Key('send-now'),
                  onPressed: store.loading ? null : store.sendNow,
                  icon: const Icon(Icons.sync),
                  label: const Text('أرسل الآن'),
                ),
              ],
            ],
          ],
        );
      },
    );
  }

  static String _sessionName(InstructorSnapshot data, String id, DateTime now) {
    final s = data.session(id);
    if (s == null) return 'حضور حصة';
    return 'حضور ${s.title} · ${dayLabel(s.date, now)}';
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.session, required this.data, required this.now});

  final Session session;
  final InstructorSnapshot data;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final s = session;
    final group = data.group(s.groupId);
    final minutes = s.startsAt.difference(now).inMinutes;
    final when = minutes > 0
        ? (minutes < 60 ? 'تبدأ بعد $minutes دقيقة' : 'تبدأ على ${formatTime(s.start)}')
        : 'جارية الآن';
    final taken = data.attendanceFor(s.id).isNotEmpty;
    final text = Theme.of(context).textTheme;
    return Container(
      key: const Key('today-hero'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(gradient: RaeedColors.sky, borderRadius: BorderRadius.circular(20)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (group != null) GroupLogo.of(group, size: 42),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${group?.name ?? ''} · ${s.title}',
                      style: text.titleSmall?.copyWith(color: const Color(0xFF06213F), fontWeight: FontWeight.w700),
                    ),
                    Text(
                      '$when · ${s.timeLabel} · ${s.placeLabel}',
                      style: text.bodySmall?.copyWith(color: const Color(0xFF0B2E55)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          FilledButton(
            key: const Key('hero-attendance'),
            style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: RaeedColors.blue),
            onPressed: () => openAttendance(context, s.id),
            child: Text(taken ? 'تعديل الحضور' : 'تسجيل الحضور'),
          ),
        ],
      ),
    );
  }
}

class _QueueRow extends StatelessWidget {
  const _QueueRow({required this.label, required this.waiting});

  final String label;
  final bool waiting;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Expanded(child: Text(label, style: text.bodyMedium)),
            Text(
              waiting ? 'في الانتظار' : 'أُرسل ✓',
              style: text.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: waiting ? const Color(0xFFB45F00) : const Color(0xFF1C7A55),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
