import 'package:flutter/material.dart';

import '../setup/widgets.dart';
import '../theme/raeed_theme.dart';
import 'activities_screen.dart';
import 'alerts_screen.dart';
import 'models.dart';
import 'sessions_screen.dart';
import 'widgets.dart';

/// The مواعدي tab: the session happening now with one button to take attendance, open
/// absence alerts, attendance still waiting to be sent, and the month's sessions this
/// instructor is given, where they can announce an absence with its reason.
class TodayTab extends StatelessWidget {
  const TodayTab({super.key});

  @override
  Widget build(BuildContext context) {
    return InstructorLoadGate(
      builder: (context, data) {
        final store = InstructorScope.of(context);
        final now = store.now();
        // The hero is the next session this instructor runs: only they take its attendance.
        final next = data.nextSession(now, where: store.runs);
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
                  'لم تُسند إليك أي فئة بعد. تواصل مع المشرف العام.',
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
            // أنشطة نوعية of their groups in the coming two weeks.
            if (_coming(data, now).isNotEmpty) ...[
              const SectionLabel('أنشطة نوعية قادمة'),
              for (final a in _coming(data, now)) ...[
                ActivityCard(
                  activity: a,
                  groupNames: activityGroupNames(a, data.groups),
                  onTap: () => openActivity(context, a.id),
                ),
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
            if (data.groups.isNotEmpty) _MonthAppointments(data: data, now: now),
          ],
        );
      },
    );
  }

  static List<SpecialActivity> _coming(InstructorSnapshot data, DateTime now) => [
    for (final a in data.activities)
      if (!a.cancelled && a.endsAt.isAfter(now) && a.startDate.isBefore(dayOnly(now).add(const Duration(days: 15)))) a,
  ];

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

/// The sessions this instructor is given, one month at a time, by day. A coming one can
/// be marked as an absence, with its reason, for the مشرف الفئة.
class _MonthAppointments extends StatefulWidget {
  const _MonthAppointments({required this.data, required this.now});

  final InstructorSnapshot data;
  final DateTime now;

  @override
  State<_MonthAppointments> createState() => _MonthAppointmentsState();
}

class _MonthAppointmentsState extends State<_MonthAppointments> {
  int _monthOffset = 0;

  @override
  Widget build(BuildContext context) {
    final store = InstructorScope.of(context);
    final data = widget.data;
    final now = widget.now;
    final text = Theme.of(context).textTheme;
    final month = DateTime(now.year, now.month + _monthOffset);
    final mine = [
      for (final s in data.sessions)
        if (s.date.year == month.year && s.date.month == month.month && store.runs(s)) s,
    ];
    final days = <DateTime, List<Session>>{};
    for (final s in mine) {
      days.putIfAbsent(s.date, () => []).add(s);
    }
    final coming = mine.where((s) => !s.cancelled && data.replacedBy(s) == null && s.endsAt.isAfter(now)).length;
    final away = mine.where((s) => data.absenceOf(s.id, store.personId) != null).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionLabel('مواعدي'),
        Row(
          children: [
            IconButton(
              key: const Key('previous-month'),
              tooltip: 'الشهر السابق',
              onPressed: () => setState(() => _monthOffset--),
              icon: const Icon(Icons.chevron_right),
            ),
            Expanded(
              child: Column(
                children: [
                  Text(
                    '${monthNames[month.month - 1]} ${month.year}',
                    key: const Key('month-label'),
                    style: text.titleSmall,
                  ),
                  Text(
                    [
                      countLabel(mine.length, one: 'حصة واحدة', two: 'حصتان', few: 'حصص', many: 'حصة'),
                      if (coming > 0) '$coming قادمة',
                      if (away > 0) 'غياب $away',
                    ].join(' · '),
                    style: text.bodySmall?.copyWith(color: RaeedColors.grey),
                  ),
                ],
              ),
            ),
            IconButton(
              key: const Key('next-month'),
              tooltip: 'الشهر التالي',
              onPressed: () => setState(() => _monthOffset++),
              icon: const Icon(Icons.chevron_left),
            ),
          ],
        ),
        if (days.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              'لم تُكلَّف بحصص في هذا الشهر.',
              textAlign: TextAlign.center,
              style: text.bodyMedium?.copyWith(color: RaeedColors.grey),
            ),
          )
        else
          Text(
            'اضغط على «غياب» لتُبلغ مشرف الفئة بغيابك عن حصة قادمة مع ذكر المبرر.',
            style: text.bodySmall?.copyWith(color: RaeedColors.grey),
          ),
        for (final e in days.entries) ...[
          SectionLabel(dayLabel(e.key, now)),
          for (final s in e.value) _Appointment(session: s, data: data, now: now),
        ],
      ],
    );
  }
}

class _Appointment extends StatelessWidget {
  const _Appointment({required this.session, required this.data, required this.now});

  final Session session;
  final InstructorSnapshot data;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final store = InstructorScope.of(context);
    final s = session;
    final group = data.group(s.groupId);
    final absence = data.absenceOf(s.id, store.personId);
    final by = s.cancelled ? null : data.replacedBy(s);
    final off = s.cancelled || by != null;
    final open = !off && s.endsAt.isAfter(now);
    final text = Theme.of(context).textTheme;
    return Card(
      key: Key('appointment-${s.id}'),
      child: ListTile(
        leading: group == null ? null : GroupLogo.of(group, size: 36),
        title: Text(
          '${formatTime(s.start)} · ${s.title}',
          style: TextStyle(decoration: off ? TextDecoration.lineThrough : null),
        ),
        subtitle: Text(
          [
            [?group?.name, s.placeLabel].join(' · '),
            if (s.cancelled) 'ملغاة',
            if (by != null) by.replacesLabel,
            if (absence != null) 'غيابك: ${absence.reason}',
          ].join('\n'),
          style: absence != null || off ? text.bodySmall?.copyWith(color: RaeedColors.error) : null,
        ),
        trailing: absence != null
            ? const Icon(Icons.person_off, color: RaeedColors.error, semanticLabel: 'غائب')
            : open && store.canRecord(s)
            ? TextButton(
                key: Key('absent-${s.id}'),
                style: TextButton.styleFrom(foregroundColor: RaeedColors.error),
                onPressed: () => askAbsence(context, s),
                child: const Text('غياب'),
              )
            : null,
        onTap: () => openSession(context, s.id),
      ),
    );
  }
}
