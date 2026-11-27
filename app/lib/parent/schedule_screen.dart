import 'dart:io' show Platform;

import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../instructor/activities_screen.dart' show ActivityCard, activityColors;
import '../instructor/models.dart';
import '../instructor/widgets.dart' show OfflineBanner, dayLabel;
import '../setup/widgets.dart';
import '../theme/raeed_theme.dart';
import 'parent_models.dart';
import 'parent_store.dart';

const _star = Color(0xFFB45F00);
const _starSoft = Color(0xFFFFF4DA);

/// The parent's جدول أطفالي tab: one child's coming sessions, read-only.
class ParentScheduleTab extends StatelessWidget {
  const ParentScheduleTab({super.key});

  @override
  Widget build(BuildContext context) {
    final store = ParentScope.of(context);
    if (!store.loaded) {
      if (store.loadFailure != null && !store.loading) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(setupFailureMessage(store.loadFailure!), textAlign: TextAlign.center),
                const SizedBox(height: 12),
                FilledButton(onPressed: store.refresh, child: const Text('حاول مرة أخرى')),
              ],
            ),
          ),
        );
      }
      return const Center(child: CircularProgressIndicator());
    }
    final data = store.data;
    final now = store.now();
    final childId = store.childId;
    final text = Theme.of(context).textTheme;
    final sessions = childId == null ? const <Session>[] : data.upcomingFor(childId, now);
    final next = childId == null ? null : data.nextFor(childId, now);
    final changes = childId == null ? const <Session>[] : data.changesFor(childId, now);
    final activities = childId == null ? const <SpecialActivity>[] : data.activitiesFor(childId, now);
    final nextActivity = childId == null ? null : data.nextActivityFor(childId, now);
    final days = <DateTime, List<Session>>{};
    for (final s in sessions) {
      (days[s.date] ??= []).add(s);
    }
    // Each activity shows on every day it covers, from today on, above that day's sessions.
    final activityDays = <DateTime, List<SpecialActivity>>{};
    for (final a in activities) {
      for (var d = a.startDate; !d.isAfter(a.endDate); d = DateTime(d.year, d.month, d.day + 1)) {
        if (d.isBefore(dayOnly(now))) continue;
        (activityDays[d] ??= []).add(a);
      }
    }
    final dayList = {...days.keys, ...activityDays.keys}.toList()..sort();
    void openActivity(SpecialActivity a) => Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => ParentActivityScreen(activityId: a.id, childId: childId!)),
    );
    return RefreshIndicator(
      onRefresh: store.refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          if (store.offline) ...[
            const OfflineBanner(text: 'لا يوجد إنترنت. هذا آخر جدول وصل إلى هاتفك.'),
            const SizedBox(height: 8),
          ],
          if (data.children.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Text(
                'لا يوجد طفل مرتبط بحسابك بعد. تواصل مع المشرف العام.',
                textAlign: TextAlign.center,
                style: TextStyle(color: RaeedColors.grey),
              ),
            ),
          if (data.children.length > 1) ...[
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final c in data.children)
                  ChoiceChip(
                    key: Key('child-${c.id}'),
                    label: Text([c.firstName, ?c.group?.name].join(' · ')),
                    selected: c.id == childId,
                    onSelected: (_) => store.showChild(c.id),
                  ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          if (childId != null && data.child(childId)!.group == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'لم يُسجَّل طفلك في فئة بعد. تواصل مع المشرف العام.',
                textAlign: TextAlign.center,
                style: TextStyle(color: RaeedColors.grey),
              ),
            )
          else if (childId != null && sessions.isEmpty && activities.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'لا حصص مبرمجة في الأسابيع القادمة.',
                textAlign: TextAlign.center,
                style: TextStyle(color: RaeedColors.grey),
              ),
            ),
          if (nextActivity != null && nextActivity.startDate.isBefore(dayOnly(now).add(const Duration(days: 31))))
            _ActivityBanner(
              activity: nextActivity,
              now: now,
              replaced: sessions.where(nextActivity.replaces).length,
              onTap: () => openActivity(nextActivity),
            ),
          if (changes.isNotEmpty)
            Container(
              key: const Key('changes-summary'),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: _starSoft, borderRadius: BorderRadius.circular(12)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${countLabel(changes.length, one: 'تغيير واحد', two: 'تغييران', few: 'تغييرات', many: 'تغييراً')} هذا الأسبوع',
                    style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  for (final s in changes) Text(_changeLine(s, data.replacedBy(s)), style: text.bodySmall),
                ],
              ),
            ),
          for (final day in dayList) ...[
            SectionLabel(dayLabel(day, now)),
            for (final a in activityDays[day] ?? const <SpecialActivity>[]) ...[
              ActivityCard(activity: a, day: day, groupNames: const [], onTap: () => openActivity(a)),
              const SizedBox(height: 8),
            ],
            for (final s in days[day] ?? const <Session>[]) ...[
              ParentSessionCard(
                session: s,
                isNext: s.id == next?.id,
                replacedBy: s.cancelled ? null : data.replacedBy(s),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => ParentSessionScreen(sessionId: s.id, childId: childId!),
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ],
        ],
      ),
    );
  }

  static String _changeLine(Session s, SpecialActivity? by) {
    if (!s.cancelled && by != null) return 'حصة ${longDay(s.date)} ${by.replacesLabel}';
    if (s.cancelled) {
      return 'حصة ${longDay(s.date)} ملغاة${s.cancelReason == null || s.cancelReason!.isEmpty ? '' : ': ${s.cancelReason}'}';
    }
    final from = s.movedFrom;
    return 'موعد ${longDay(s.date)} تغيّر${from == null ? '' : ' ($from)'}';
  }
}

/// A session in the parent's schedule: the time on the side, then what the child needs.
class ParentSessionCard extends StatelessWidget {
  const ParentSessionCard({super.key, required this.session, this.isNext = false, this.onTap, this.replacedBy});

  final Session session;
  final bool isNext;
  final VoidCallback? onTap;

  /// The نشاط نوعي that takes this session's place: it shows as cancelled because of it.
  final SpecialActivity? replacedBy;

  @override
  Widget build(BuildContext context) {
    final s = session;
    final by = replacedBy;
    final off = s.cancelled || by != null;
    final text = Theme.of(context).textTheme;
    final changed = s.status == SessionStatus.changed && !off;
    final flag = text.bodySmall?.copyWith(color: _star, fontWeight: FontWeight.w600);
    final muted = text.bodySmall?.copyWith(color: RaeedColors.grey);
    return Card(
      key: Key('parent-session-${s.id}'),
      color: changed ? _starSoft : null,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Opacity(
          opacity: off ? 0.75 : 1,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 58,
                  child: Column(
                    children: [
                      Text(formatTime(s.start), style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                      Text(off ? 'ملغاة' : 'حتى ${formatTime(s.end)}', style: muted),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (isNext)
                        Container(
                          margin: const EdgeInsets.only(bottom: 3),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
                          decoration: BoxDecoration(color: RaeedColors.blue, borderRadius: BorderRadius.circular(99)),
                          child: Text(
                            'الحصة القادمة',
                            style: text.labelSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
                          ),
                        ),
                      if (s.cancelled) Text('ملغاة', style: flag),
                      if (by != null)
                        Text(
                          by.replacesLabel,
                          key: Key('parent-replaced-${s.id}'),
                          style: text.bodySmall?.copyWith(color: RaeedColors.error, fontWeight: FontWeight.w600),
                        ),
                      if (changed)
                        Text(
                          s.movedFrom == null ? 'تغيّرت تفاصيل الحصة' : 'تغيّر الموعد · ${s.movedFrom}',
                          style: flag,
                        ),
                      Text(
                        s.title,
                        style: text.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          decoration: off ? TextDecoration.lineThrough : null,
                        ),
                      ),
                      if (by != null)
                        const SizedBox.shrink()
                      else if (s.cancelled) ...[
                        if (s.cancelReason != null && s.cancelReason!.isNotEmpty) Text(s.cancelReason!, style: muted),
                      ] else ...[
                        Text(s.placeLabel, style: muted),
                        if (s.away && s.dropoffTime != null)
                          Text(
                            'التسليم ${formatTime(s.dropoffTime!)}${s.dropoffPlace == null ? '' : ' ${s.dropoffPlace}'}',
                            style: flag,
                          ),
                        if (s.away && s.pickupTime != null)
                          Text(
                            'الاستلام ${formatTime(s.pickupTime!)}${s.pickupPlace == null ? '' : ' ${s.pickupPlace}'}',
                            style: flag,
                          ),
                        if (s.materials.isNotEmpty)
                          Text(
                            'مواد للمراجعة في البيت (${s.materials.length})',
                            style: text.bodySmall?.copyWith(color: RaeedColors.blue, fontWeight: FontWeight.w600),
                          ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// تفاصيل الحصة: when, where, who, the materials, and a button for the phone's calendar.
class ParentSessionScreen extends StatelessWidget {
  const ParentSessionScreen({super.key, required this.sessionId, required this.childId});

  final String sessionId;
  final String childId;

  @override
  Widget build(BuildContext context) {
    final store = ParentScope.of(context);
    final data = store.data;
    final s = data.session(sessionId);
    final child = data.child(childId);
    if (s == null || child == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('لم تعد هذه الحصة في الجدول.')),
      );
    }
    final text = Theme.of(context).textTheme;
    final muted = text.bodyMedium?.copyWith(color: RaeedColors.grey);
    final staff = data.staffNames[s.groupId] ?? const [];
    final by = s.cancelled ? null : data.replacedBy(s);
    final changed = s.status == SessionStatus.changed && !s.cancelled && by == null;
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 68,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.title),
            Text(
              [child.firstName, ?child.group?.name].join(' · '),
              style: text.bodySmall?.copyWith(color: RaeedColors.grey),
            ),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          if (by != null)
            Card(
              key: const Key('parent-session-replaced'),
              color: const Color(0xFFFDE8E3),
              child: ListTile(
                leading: Text(by.kind.emoji, style: const TextStyle(fontSize: 26)),
                title: Text(
                  by.replacesLabel,
                  style: text.titleSmall?.copyWith(color: RaeedColors.error, fontWeight: FontWeight.w700),
                ),
                subtitle: const Text('لا حصة في هذا الموعد: يشارك طفلك في النشاط. اضغط لتفاصيله.'),
                trailing: const Icon(Icons.chevron_left),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(builder: (_) => ParentActivityScreen(activityId: by.id, childId: childId)),
                ),
              ),
            ),
          if (s.cancelled || changed)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: s.cancelled ? const Color(0xFFFDE8E3) : _starSoft,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                s.cancelled
                    ? 'هذه الحصة ملغاة${s.cancelReason == null || s.cancelReason!.isEmpty ? '' : ': ${s.cancelReason}'}'
                    : 'تغيّر موعد هذه الحصة${s.movedFrom == null ? '' : ' · ${s.movedFrom}'}',
                style: text.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: s.cancelled ? RaeedColors.error : _star,
                ),
              ),
            ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    longDay(s.date),
                    style: text.headlineSmall?.copyWith(fontFamily: RaeedFonts.display, fontWeight: FontWeight.w700),
                  ),
                  Text(s.timeLabel, style: muted),
                  const SizedBox(height: 8),
                  Text(s.placeLabel, style: text.bodyLarge),
                  if (s.away && s.dropoffTime != null)
                    Text(
                      'التسليم: ${formatTime(s.dropoffTime!)}${s.dropoffPlace == null ? '' : ' · ${s.dropoffPlace}'}',
                      style: text.bodyMedium,
                    ),
                  if (s.away && s.pickupTime != null)
                    Text(
                      'الاستلام: ${formatTime(s.pickupTime!)}${s.pickupPlace == null ? '' : ' · ${s.pickupPlace}'}',
                      style: text.bodyMedium,
                    ),
                  if (s.away && s.mapUrl != null && s.mapUrl!.isNotEmpty)
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: TextButton.icon(
                        key: const Key('open-map'),
                        style: TextButton.styleFrom(padding: EdgeInsets.zero),
                        onPressed: () => launchUrl(Uri.parse(s.mapUrl!), mode: LaunchMode.externalApplication),
                        icon: const Icon(Icons.map_outlined),
                        label: const Text('فتح الخريطة'),
                      ),
                    ),
                  if (staff.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text('${staff.length == 1 ? 'المؤطر' : 'المؤطرون'}: ${staff.join('، ')}', style: muted),
                  ],
                ],
              ),
            ),
          ),
          if (s.materials.isNotEmpty) ...[
            const SectionLabel('للمراجعة في البيت'),
            for (final m in s.materials) ...[
              Card(
                child: ListTile(
                  leading: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      border: Border.all(color: RaeedColors.blue),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      m.kindLabel,
                      style: text.labelSmall?.copyWith(color: RaeedColors.blue, fontWeight: FontWeight.w700),
                    ),
                  ),
                  title: Text(m.label),
                  trailing: const Icon(Icons.chevron_left),
                  onTap: () => launchUrl(Uri.parse(m.url), mode: LaunchMode.externalApplication),
                ),
              ),
              const SizedBox(height: 6),
            ],
            Text('تُفتح الروابط في YouTube أو Google Drive.', style: text.bodySmall?.copyWith(color: RaeedColors.grey)),
          ],
          if (!s.cancelled && by == null) ...[
            const SizedBox(height: 20),
            FilledButton.icon(
              key: const Key('add-to-calendar'),
              onPressed: () => addToCalendar(s, child),
              icon: const Icon(Icons.event_available),
              label: const Text('إضافة إلى تقويم الهاتف'),
            ),
          ],
        ],
      ),
    );
  }
}

/// Opens the phone's calendar with the session filled in, for the parent to save.
Future<void> addToCalendar(Session s, ParentChild child) => _openCalendar(
  title: '${s.title} · ${child.firstName}',
  begin: s.startsAt,
  end: s.endsAt,
  where: s.away ? (s.address ?? '') : 'جمعية سماء · الطابق ${floors[s.floor] ?? ''}',
  details: [
    if (s.away && s.dropoffTime != null) 'التسليم ${formatTime(s.dropoffTime!)} ${s.dropoffPlace ?? ''}',
    if (s.away && s.pickupTime != null) 'الاستلام ${formatTime(s.pickupTime!)} ${s.pickupPlace ?? ''}',
    for (final m in s.materials) '${m.label}: ${m.url}',
  ].join('\n'),
);

/// The same for an activity, over all its days.
Future<void> addActivityToCalendar(SpecialActivity a, ParentChild child) => _openCalendar(
  title: '${a.kindLabel}: ${a.title} · ${child.firstName}',
  begin: a.startsAt,
  end: a.endsAt,
  where: a.place,
  details: [
    if ((a.meetingPlace ?? '').isNotEmpty) 'التجمع والاستلام: ${a.meetingPlace}',
    ?a.details,
  ].join('\n'),
);

Future<void> _openCalendar({
  required String title,
  required DateTime begin,
  required DateTime end,
  required String where,
  required String details,
}) async {
  if (!kIsWeb && Platform.isAndroid) {
    try {
      await AndroidIntent(
        action: 'android.intent.action.INSERT',
        data: 'content://com.android.calendar/events',
        arguments: {
          'title': title,
          'beginTime': begin.millisecondsSinceEpoch,
          'endTime': end.millisecondsSinceEpoch,
          'eventLocation': where,
          'description': details,
        },
      ).launch();
      return;
    } catch (_) {
      // No calendar app: fall back to Google Calendar in the browser.
    }
  }
  String stamp(DateTime t) =>
      '${dbDay(t).replaceAll('-', '')}T${t.hour.toString().padLeft(2, '0')}${t.minute.toString().padLeft(2, '0')}00';
  final url = Uri.https('calendar.google.com', '/calendar/render', {
    'action': 'TEMPLATE',
    'text': title,
    'dates': '${stamp(begin)}/${stamp(end)}',
    'location': where,
    'details': details,
  });
  await launchUrl(url, mode: LaunchMode.externalApplication);
}

/// The child's next نشاط نوعي, on top of the schedule.
class _ActivityBanner extends StatelessWidget {
  const _ActivityBanner({required this.activity, required this.now, required this.replaced, required this.onTap});

  final SpecialActivity activity;
  final DateTime now;

  /// How many of the child's sessions it takes the place of.
  final int replaced;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final a = activity;
    final (fg, bg) = activityColors(a.kind);
    final text = Theme.of(context).textTheme;
    final days = dayOnly(a.startDate).difference(dayOnly(now)).inDays;
    final when = a.startsAt.isBefore(now)
        ? 'جارٍ الآن'
        : days == 0
        ? 'اليوم'
        : days == 1
        ? 'غداً'
        : 'بعد ${countLabel(days, one: 'يوم', two: 'يومين', few: 'أيام', many: 'يوماً')}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: bg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: fg, width: 1.6)),
        child: InkWell(
          key: const Key('activity-banner'),
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Text(a.kind.emoji, style: const TextStyle(fontSize: 34)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'نشاط قادم · $when',
                        style: text.labelMedium?.copyWith(color: fg, fontWeight: FontWeight.w700),
                      ),
                      Text(
                        '${a.kindLabel}: ${a.title}',
                        style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      Text(a.whenLabel, style: text.bodySmall),
                      Text(a.place, style: text.bodySmall),
                      if (replaced > 0)
                        Text(
                          'يعوّض ${countLabel(replaced, one: 'حصة واحدة', two: 'حصتين', few: 'حصص', many: 'حصة')} من حصص الفئة',
                          style: text.bodySmall?.copyWith(color: fg, fontWeight: FontWeight.w600),
                        ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_left),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// تفاصيل النشاط, for a parent: when, where, what to bring, and the phone's calendar.
class ParentActivityScreen extends StatelessWidget {
  const ParentActivityScreen({super.key, required this.activityId, required this.childId});

  final String activityId;
  final String childId;

  @override
  Widget build(BuildContext context) {
    final store = ParentScope.of(context);
    final data = store.data;
    final a = data.activity(activityId);
    final child = data.child(childId);
    if (a == null || child == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('لم يعد هذا النشاط في الجدول.')),
      );
    }
    final text = Theme.of(context).textTheme;
    final (fg, bg) = activityColors(a.kind);
    final replaced = data.upcomingFor(childId, DateTime(2000)).where((s) => !s.cancelled && a.replaces(s)).toList();
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 68,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(a.title),
            Text(
              ['نشاط نوعي · ${a.kindLabel}', child.firstName].join(' · '),
              style: text.bodySmall?.copyWith(color: RaeedColors.grey),
            ),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          if (a.cancelled)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: const Color(0xFFFDE8E3), borderRadius: BorderRadius.circular(12)),
              child: Text(
                'أُلغي هذا النشاط${(a.cancelReason ?? '').isEmpty ? '' : ': ${a.cancelReason}'}. الحصص في موعدها المعتاد.',
                style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600, color: RaeedColors.error),
              ),
            ),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: fg, width: 1.4),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(a.kind.emoji, style: const TextStyle(fontSize: 34)),
                const SizedBox(height: 4),
                Text(
                  a.whenLabel,
                  style: text.titleMedium?.copyWith(fontFamily: RaeedFonts.display, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Text('المكان: ${a.place}', style: text.bodyLarge),
                if ((a.meetingPlace ?? '').isNotEmpty) Text('التجمع والاستلام: ${a.meetingPlace}', style: text.bodyMedium),
                if ((a.mapUrl ?? '').isNotEmpty)
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton.icon(
                      style: TextButton.styleFrom(padding: EdgeInsets.zero),
                      onPressed: () => launchUrl(Uri.parse(a.mapUrl!), mode: LaunchMode.externalApplication),
                      icon: const Icon(Icons.map_outlined),
                      label: const Text('فتح الخريطة'),
                    ),
                  ),
              ],
            ),
          ),
          if ((a.details ?? '').isNotEmpty) ...[
            const SectionLabel('ما يجب معرفته'),
            Card(child: Padding(padding: const EdgeInsets.all(12), child: Text(a.details!))),
          ],
          if (!a.cancelled && replaced.isNotEmpty) ...[
            const SectionLabel('الحصص الملغاة بسبب النشاط'),
            for (final s in replaced)
              Text(
                '• ${s.title} · ${longDay(s.date)} ${formatTime(s.start)}',
                style: text.bodyMedium?.copyWith(decoration: TextDecoration.lineThrough),
              ),
          ],
          if (!a.cancelled) ...[
            const SizedBox(height: 20),
            FilledButton.icon(
              key: const Key('activity-to-calendar'),
              onPressed: () => addActivityToCalendar(a, child),
              icon: const Icon(Icons.event_available),
              label: const Text('إضافة إلى تقويم الهاتف'),
            ),
          ],
        ],
      ),
    );
  }
}
