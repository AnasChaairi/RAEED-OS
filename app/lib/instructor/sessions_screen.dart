import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../setup/setup_repository.dart';
import '../setup/widgets.dart';
import '../theme/raeed_theme.dart';
import '../widgets/month_calendar.dart';
import 'activities_screen.dart';
import 'attendance_screen.dart';
import 'instructor_repository.dart';
import 'models.dart';
import 'observations.dart';
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
      // A category supervisor plans from فئتي, under the group's الحصص.
      // The advisor plans here: one + opens the choice of a حصة or a نشاط نوعي. A category
      // supervisor plans both from فئتي, under the group's الحصص.
      floatingActionButton: store.view != StaffView.all || store.data.groups.isEmpty
          ? null
          : FloatingActionButton(
              key: const Key('new-plan'),
              heroTag: 'new-plan',
              tooltip: 'إضافة',
              onPressed: () => _choosePlan(context),
              child: const Icon(Icons.add),
            ),
      body: InstructorLoadGate(
        builder: (context, data) {
          final days = <DateTime, List<Session>>{};
          for (final s in data.sessions) {
            if (s.date.isBefore(weekStart) || s.date.isAfter(weekEnd)) continue;
            days.putIfAbsent(s.date, () => []).add(s);
          }
          // أنشطة نوعية show on each day they cover, above that day's sessions.
          final activityDays = <DateTime, List<SpecialActivity>>{};
          for (var d = weekStart; !d.isAfter(weekEnd); d = DateTime(d.year, d.month, d.day + 1)) {
            final on = data.activitiesOn(d);
            if (on.isNotEmpty) activityDays[d] = on;
          }
          final dayList = {...days.keys, ...activityDays.keys}.toList()..sort();
          List<Widget> dayCards(BuildContext context, DateTime day) => [
            for (final a in data.activitiesOn(day)) ...[
              ActivityCard(
                activity: a,
                day: day,
                groupNames: activityGroupNames(a, data.groups),
                replaced: a.dayNumber(day) == 1 ? data.replacedSessions(a).length : 0,
                onTap: () => openActivity(context, a.id),
              ),
              const SizedBox(height: 8),
            ],
            for (final s in data.sessions.where((s) => s.date == day)) ...[
              SessionCard(session: s, data: data, onTap: () => openSession(context, s.id)),
              const SizedBox(height: 8),
            ],
          ];
          return ScheduleModeBuilder(
            builder: (context, mode) => ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
              children: [
                if (store.offline) const OfflineBanner(),
                if (data.groups.isNotEmpty) const ScheduleModeToggle(),
                if (mode == ScheduleMode.month && data.groups.isNotEmpty)
                  MonthCalendar(
                    now: now,
                    sessions: data.sessions,
                    activities: data.activities,
                    replacedBy: data.replacedBy,
                    dayItems: dayCards,
                    breaks: [
                      for (final b in data.breaks)
                        if (b.concerns(data.groups.map((g) => g.id))) b,
                    ],
                  )
                else ...[
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
                    _Hint(
                      store.view == StaffView.all
                          ? 'لا توجد فئات بعد. أنشئ فئة من تبويب الفئات ثم خطّط حصصها هنا.'
                          : 'لم تُسند إليك أي فئة بعد. تواصل مع المشرف العام.',
                    )
                  else if (dayList.isEmpty)
                    _Hint(
                      store.schedules
                          ? 'لا حصص هذا الأسبوع. أضف حصة بالزر في الأسفل.'
                          : 'لا حصص هذا الأسبوع. يخطّط المشرف العام الحصص وتظهر هنا.',
                    ),
                  for (final day in dayList) ...[
                    SectionLabel(dayLabel(day, now)),
                    for (final a in activityDays[day] ?? const <SpecialActivity>[]) ...[
                      ActivityCard(
                        activity: a,
                        day: day,
                        groupNames: activityGroupNames(a, data.groups),
                        replaced: a.dayNumber(day) == 1 ? data.replacedSessions(a).length : 0,
                        onTap: () => openActivity(context, a.id),
                      ),
                      const SizedBox(height: 8),
                    ],
                    for (final s in days[day] ?? const <Session>[]) ...[
                      SessionCard(session: s, data: data, onTap: () => openSession(context, s.id)),
                      const SizedBox(height: 8),
                    ],
                  ],
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

/// What the advisor's + adds: a حصة or a نشاط نوعي.
Future<void> _choosePlan(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  builder: (sheet) {
    final text = Theme.of(sheet).textTheme;
    Widget option({
      required Key key,
      required IconData icon,
      required Color fg,
      required Color bg,
      required String title,
      required String subtitle,
      required VoidCallback open,
    }) => ListTile(
      key: key,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
        child: Icon(icon, color: fg),
      ),
      title: Text(title, style: text.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle),
      onTap: () {
        Navigator.pop(sheet);
        open();
      },
    );
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text('إضافة', style: text.titleLarge),
            ),
            option(
              key: const Key('new-session'),
              icon: Icons.event_note_outlined,
              fg: RaeedColors.blue,
              bg: RaeedColors.surfaceAlt,
              title: 'حصة جديدة',
              subtitle: 'مرة واحدة أو أسبوعياً، لفئة واحدة',
              open: () => openSessionForm(context),
            ),
            option(
              key: const Key('new-activity'),
              icon: Icons.celebration_outlined,
              fg: const Color(0xFF8A4B00),
              bg: RaeedColors.starSoft,
              title: 'نشاط نوعي',
              subtitle: 'مخيم، مبيت، خرجة... لفئة أو أكثر، وله الأولوية على الحصص',
              open: () => openActivityForm(context),
            ),
          ],
        ),
      ),
    );
  },
);

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
    final mine = data.absenceOf(s.id, store.personId);
    final absences = data.absencesFor(s.id);
    final over = !s.endsAt.isAfter(store.now());
    final by = s.cancelled ? null : data.replacedBy(s);
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
                      if (s.remind && store.schedules) 'تذكير قبل 5 ساعات',
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
          if (by != null) ...[
            const SizedBox(height: 8),
            Card(
              key: const Key('session-replaced'),
              color: const Color(0xFFFDE8E3),
              child: ListTile(
                leading: Text(by.kind.emoji, style: const TextStyle(fontSize: 26)),
                title: Text(
                  by.replacesLabel,
                  style: text.titleSmall?.copyWith(color: RaeedColors.error, fontWeight: FontWeight.w700),
                ),
                subtitle: const Text('للنشاط النوعي الأولوية: لا يُسجَّل حضور هذه الحصة ولا يُحسب غياب للمؤطرين.'),
                trailing: const Icon(Icons.chevron_left),
                onTap: () => openActivity(context, by.id),
              ),
            ),
          ],
          if (s.materials.isNotEmpty) ...[
            const SectionLabel('المواد'),
            for (final m in s.materials) MaterialRow(material: m),
          ],
          if (absences.isNotEmpty && (store.schedules || mine == null)) ...[
            const SectionLabel('غياب المؤطرين'),
            for (final a in absences)
              Card(
                key: Key('absence-${a.personId}'),
                child: ListTile(
                  leading: const Icon(Icons.person_off_outlined, color: RaeedColors.error),
                  title: Text(data.staffNames[a.personId] ?? 'مؤطر'),
                  subtitle: Text(a.reason),
                ),
              ),
          ],
          if (store.canRecord(s) && !s.cancelled && mine != null) ...[
            const SizedBox(height: 12),
            Card(
              key: const Key('my-absence'),
              color: RaeedColors.starSoft,
              child: ListTile(
                leading: const Icon(Icons.person_off_outlined, color: RaeedColors.starEnd),
                title: const Text('أبلغت بغيابك عن هذه الحصة'),
                subtitle: Text(mine.reason),
                trailing: over
                    ? null
                    : TextButton(
                        key: const Key('withdraw-absence'),
                        onPressed: () => _withdraw(context, mine),
                        child: const Text('سأحضر'),
                      ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          if (store.canRecord(s) && !s.cancelled && started)
            FilledButton.icon(
              key: const Key('take-attendance'),
              onPressed: () => openAttendance(context, s.id),
              icon: const Icon(Icons.fact_check_outlined),
              label: Text(taken > 0 ? 'تعديل الحضور' : 'تسجيل الحضور'),
            ),
          if (store.canRecord(s) && !s.cancelled && !over && mine == null) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const Key('report-absence'),
              onPressed: () => _reportAbsence(context, s),
              icon: const Icon(Icons.person_off_outlined),
              label: const Text('سأتغيب عن هذه الحصة'),
            ),
          ],
          if (!store.schedules && !store.runs(s) && !s.cancelled)
            Text(
              'يسجّل الحضور المؤطرون المكلّفون بهذه الحصة.',
              key: const Key('not-your-session'),
              textAlign: TextAlign.center,
              style: text.bodySmall?.copyWith(color: RaeedColors.grey),
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
          if (store.schedules) ...[
            const SizedBox(height: 4),
            TextButton.icon(
              key: const Key('delete-session'),
              style: TextButton.styleFrom(foregroundColor: RaeedColors.error),
              onPressed: () => _delete(context, s),
              icon: const Icon(Icons.delete_outline),
              label: const Text('حذف الحصة'),
            ),
          ],
          if (store.runs(s) || store.schedules) SessionObservations(session: s),
        ],
      ),
    );
  }

  Future<void> _delete(BuildContext context, Session s) async {
    final store = InstructorScope.read(context);
    final upcoming = await showDialog<bool>(
      context: context,
      builder: (_) => _DeleteDialog(session: s, attendance: store.data.attendanceFor(s.id).length),
    );
    if (upcoming == null || !context.mounted) return;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await store.deleteSessions(s, upcoming: upcoming);
      navigator.pop();
      messenger.showSnackBar(SnackBar(content: Text(upcoming ? 'حُذفت الحصص.' : 'حُذفت الحصة.')));
    } on SetupError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(setupFailureMessage(e.failure))));
    }
  }

  Future<void> _reportAbsence(BuildContext context, Session s) => askAbsence(context, s);

  Future<void> _withdraw(BuildContext context, InstructorAbsence a) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await InstructorScope.read(context).withdrawAbsence(a);
    } on SetupError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(setupFailureMessage(e.failure))));
    }
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

/// Asks why the instructor will miss the session. Pops the reason.
class _AbsenceDialog extends StatefulWidget {
  const _AbsenceDialog();

  @override
  State<_AbsenceDialog> createState() => _AbsenceDialogState();
}

class _AbsenceDialogState extends State<_AbsenceDialog> {
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ok = _reason.text.trim().isNotEmpty;
    return AlertDialog(
      title: const Text('الإبلاغ بالغياب'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('يصل إشعار إلى مشرف الفئة ليرتّب من يعوّضك.'),
          const SizedBox(height: 10),
          TextField(
            key: const Key('absence-reason'),
            controller: _reason,
            autofocus: true,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'السبب', hintText: 'مثلاً: موعد طبي'),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('رجوع')),
        FilledButton(
          key: const Key('confirm-absence'),
          onPressed: ok ? () => Navigator.pop(context, _reason.text.trim()) : null,
          child: const Text('إرسال'),
        ),
      ],
    );
  }
}

/// Confirms deleting a session. Pops whether the series' later sessions go too, or null.
class _DeleteDialog extends StatefulWidget {
  const _DeleteDialog({required this.session, required this.attendance});

  final Session session;
  final int attendance;

  @override
  State<_DeleteDialog> createState() => _DeleteDialogState();
}

class _DeleteDialogState extends State<_DeleteDialog> {
  bool _upcoming = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('حذف الحصة؟'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            [
              'تُحذف نهائياً مع موادها وملاحظاتها',
              if (widget.attendance > 0) ' وحضورها المسجّل (${widget.attendance})',
              '. لا يصل إشعار لأولياء الأمور، فإن كانوا ينتظرونها فالأفضل إلغاؤها.',
            ].join(),
          ),
          if (widget.session.seriesId != null) ...[
            const SizedBox(height: 10),
            SegmentedButton<bool>(
              key: const Key('delete-scope'),
              segments: const [
                ButtonSegment(value: false, label: Text('هذه الحصة فقط')),
                ButtonSegment(value: true, label: Text('وكل القادمة')),
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
          key: const Key('confirm-delete-session'),
          style: FilledButton.styleFrom(backgroundColor: RaeedColors.error),
          onPressed: () => Navigator.pop(context, _upcoming),
          child: const Text('حذف'),
        ),
      ],
    );
  }
}

/// Asks the instructor for the reason they will miss [s], and tells the مشرف الفئة.
Future<void> askAbsence(BuildContext context, Session s) async {
  final reason = await showDialog<String>(context: context, builder: (_) => const _AbsenceDialog());
  if (reason == null || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  try {
    await InstructorScope.read(context).reportAbsence(s, reason);
    messenger.showSnackBar(const SnackBar(content: Text('وصل إشعار بغيابك إلى مشرف الفئة.')));
  } on SetupError catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(setupFailureMessage(e.failure))));
  }
}
