import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../auth/phone.dart';
import '../profile/child_profile_screen.dart';
import '../setup/models.dart';
import '../setup/widgets.dart';
import '../theme/raeed_theme.dart';
import '../widgets/month_calendar.dart';
import 'activities_screen.dart';
import 'models.dart';
import 'session_form_screen.dart';
import 'sessions_screen.dart';
import 'widgets.dart';

/// The فئاتي tab.
class MyGroupsTab extends StatelessWidget {
  const MyGroupsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return InstructorLoadGate(
      builder: (context, data) {
        final store = InstructorScope.of(context);
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            if (store.offline) const OfflineBanner(),
            if (data.groups.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Text(
                  'لم تُسند إليك أي فئة بعد. تواصل مع المشرف العام.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: RaeedColors.grey),
                ),
              ),
            for (final g in data.groups) ...[
              _GroupRow(group: g, data: data, now: store.now(), me: store.personId, supervising: store.schedules),
              const SizedBox(height: 8),
            ],
          ],
        );
      },
    );
  }
}

class _GroupRow extends StatelessWidget {
  const _GroupRow({
    required this.group,
    required this.data,
    required this.now,
    required this.me,
    this.supervising = false,
  });

  final Group group;
  final InstructorSnapshot data;
  final DateTime now;
  final String? me;
  final bool supervising;

  @override
  Widget build(BuildContext context) {
    final others = [
      for (final id in group.instructorIds)
        if (id != me) data.staffNames[id],
    ].nonNulls.join('، ');
    final next = data.nextSession(now, groupId: group.id);
    final count = data.childrenIn(group.id).length;
    return SetupRow(
      key: Key('my-group-${group.id}'),
      leading: GroupLogo.of(group),
      title: group.name,
      lines: [
        [
          ?group.ageLabel,
          countLabel(count, one: 'طفل واحد', two: 'طفلان', few: 'أطفال', many: 'طفلاً'),
          if (others.isNotEmpty) supervising ? 'المؤطرون: $others' : 'معك: $others',
        ].join(' · '),
        next == null ? 'لا حصة قادمة' : 'الحصة القادمة: ${dayLabel(next.date, now)} ${formatTime(next.start)}',
      ],
      onTap: () =>
          Navigator.push(context, MaterialPageRoute<void>(builder: (_) => GroupDetailScreen(groupId: group.id))),
    );
  }
}

/// A فئة: its children with this term's attendance, and its sessions.
class GroupDetailScreen extends StatefulWidget {
  const GroupDetailScreen({super.key, required this.groupId});

  final String groupId;

  @override
  State<GroupDetailScreen> createState() => _GroupDetailScreenState();
}

class _GroupDetailScreenState extends State<GroupDetailScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final store = InstructorScope.of(context);
    final data = store.data;
    final group = data.group(widget.groupId);
    if (group == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('لم تعد هذه الفئة من فئاتك.')),
      );
    }
    final kids = data.childrenIn(group.id);
    final now = store.now();
    final sessions = data.sessionsOf(group.id);
    final text = Theme.of(context).textTheme;
    final staff = [for (final id in group.instructorIds) data.staffNames[id]].nonNulls.join('، ');
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 72,
        title: Row(
          children: [
            GroupLogo.of(group, size: 42),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(group.name),
                  Text(
                    [?group.ageLabel, if (staff.isNotEmpty) staff].join(' · '),
                    style: text.bodySmall?.copyWith(color: RaeedColors.grey),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          SegmentedButton<int>(
            key: const Key('group-tabs'),
            showSelectedIcon: false,
            segments: [
              ButtonSegment(value: 0, label: Text('الأطفال ${kids.length}')),
              const ButtonSegment(value: 1, label: Text('الحصص')),
              if (store.schedules) const ButtonSegment(value: 2, label: Text('المؤطرون')),
            ],
            selected: {_tab},
            onSelectionChanged: (v) => setState(() => _tab = v.first),
          ),
          const SizedBox(height: 10),
          if (_tab == 0) ...[
            if (kids.isEmpty)
              const Text(
                'لا يوجد أطفال في هذه الفئة بعد. يضيفهم المشرف العام من الإعدادات.',
                style: TextStyle(color: RaeedColors.grey),
              )
            else
              Card(
                child: Column(
                  children: [for (final k in kids) _KidRate(child: k, rate: data.attendanceRate(k.id))],
                ),
              ),
            const SizedBox(height: 6),
            Text(
              data.termStart == null
                  ? 'نسبة الحضور في آخر 30 يوماً. اضغط على اسم لفتح ملف الطفل.'
                  : 'نسبة الحضور هذا الفصل. اضغط على اسم لفتح ملف الطفل.',
              style: text.bodySmall?.copyWith(color: RaeedColors.grey),
            ),
          ] else if (_tab == 2) ...[
            if (group.instructorIds.isEmpty)
              const Text('لا مؤطرين في هذه الفئة بعد.', style: TextStyle(color: RaeedColors.grey))
            else
              for (final id in group.instructorIds) ...[
                _InstructorWork(personId: id, group: group, data: data, now: now),
                const SizedBox(height: 8),
              ],
            Text(
              'الحصص المنتهية في آخر 30 يوماً التي كُلّف بها كل مؤطر، وهل سُجّل حضورها.',
              style: text.bodySmall?.copyWith(color: RaeedColors.grey),
            ),
          ] else ...[
            if (sessions.isEmpty && !data.activities.any((a) => a.groupIds.contains(group.id)))
              const Text('لا حصص بعد.', style: TextStyle(color: RaeedColors.grey))
            else
              _GroupSessions(sessions: sessions, data: data, now: now, groupId: group.id),
          ],
          if (store.schedules && _tab == 1) ...[
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const Key('new-session-for-group'),
              onPressed: () => openSessionForm(context, groupId: group.id),
              icon: const Icon(Icons.add),
              label: const Text('حصة جديدة لهذه الفئة'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const Key('new-activity-for-group'),
              onPressed: () => openActivityForm(context, groupId: group.id),
              icon: const Icon(Icons.celebration_outlined),
              label: const Text('نشاط نوعي لهذه الفئة'),
            ),
          ],
        ],
      ),
    );
  }
}

/// One instructor of the فئة, for its supervisor: their presence in the last 30 days and
/// the absences they announced.
class _InstructorWork extends StatelessWidget {
  const _InstructorWork({required this.personId, required this.group, required this.data, required this.now});

  final String personId;
  final Group group;
  final InstructorSnapshot data;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final monthAgo = dayOnly(now).subtract(const Duration(days: 30));
    final theirs = [
      for (final s in data.sessionsOf(group.id))
        if (!s.cancelled && data.replacedBy(s) == null && data.runs(s, personId)) s,
    ];
    final done = [
      for (final s in theirs)
        if (!s.endsAt.isAfter(now) && !s.date.isBefore(monthAgo)) s,
    ];
    final absentDone = done.where((s) => data.absenceOf(s.id, personId) != null).length;
    final rate = done.isEmpty ? null : (done.length - absentDone) / done.length;
    final comingAbsences = theirs.where((s) => s.endsAt.isAfter(now) && data.absenceOf(s.id, personId) != null).length;
    final name = data.staffNames[personId] ?? 'مؤطر';
    return Card(
      key: Key('instructor-work-$personId'),
      child: ListTile(
        leading: InitialAvatar(name, size: 36),
        title: Text(name),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              rate == null
                  ? const _Pill('لا حصص منتهية')
                  : _Pill('الحضور ${(rate * 100).round()}%', good: absentDone == 0, alert: rate < 0.8),
              if (absentDone > 0) _Pill('غاب $absentDone', alert: true),
              if (comingAbsences > 0) _Pill('غياب قادم $comingAbsences', alert: true),
            ],
          ),
        ),
        trailing: const Icon(Icons.chevron_left),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) => InstructorDetailScreen(personId: personId, groupId: group.id),
          ),
        ),
      ),
    );
  }
}

/// A short count on an instructor's card.
class _Pill extends StatelessWidget {
  const _Pill(this.label, {this.alert = false, this.good = false});

  final String label;
  final bool alert;
  final bool good;

  @override
  Widget build(BuildContext context) {
    final color = alert ? RaeedColors.error : (good ? const Color(0xFF1C7A55) : RaeedColors.grey);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
      child: Text(
        label,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// A فئة's sessions: its weekly series in short, then one week at a time, so a long
/// series does not make an endless list.
class _GroupSessions extends StatefulWidget {
  const _GroupSessions({required this.sessions, required this.data, required this.now, required this.groupId});

  final String groupId;
  final List<Session> sessions;
  final InstructorSnapshot data;
  final DateTime now;

  @override
  State<_GroupSessions> createState() => _GroupSessionsState();
}

class _GroupSessionsState extends State<_GroupSessions> {
  int _weekOffset = 0;

  DateTime get _thisWeek {
    final today = dayOnly(widget.now);
    return today.subtract(Duration(days: dayOfWeek(today)));
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final now = widget.now;
    final weekStart = _thisWeek.add(Duration(days: 7 * _weekOffset));
    final weekEnd = weekStart.add(const Duration(days: 6));
    final days = <DateTime, List<Session>>{};
    for (final s in widget.sessions) {
      if (s.date.isBefore(weekStart) || s.date.isAfter(weekEnd)) continue;
      days.putIfAbsent(s.date, () => []).add(s);
    }
    final activityDays = <DateTime, List<SpecialActivity>>{};
    for (var d = weekStart; !d.isAfter(weekEnd); d = DateTime(d.year, d.month, d.day + 1)) {
      final on = [
        for (final a in widget.data.activitiesOn(d))
          if (a.groupIds.contains(widget.groupId)) a,
      ];
      if (on.isNotEmpty) activityDays[d] = on;
    }
    final dayList = {...days.keys, ...activityDays.keys}.toList()..sort();
    // Series with sessions still to come.
    final series = <String, List<Session>>{};
    for (final s in widget.sessions) {
      if (s.seriesId != null && !s.cancelled && s.endsAt.isAfter(now)) series.putIfAbsent(s.seriesId!, () => []).add(s);
    }
    final next = widget.sessions.where((s) => !s.cancelled && s.endsAt.isAfter(now)).firstOrNull;
    final weekLabel = switch (_weekOffset) {
      0 => 'هذا الأسبوع',
      1 => 'الأسبوع القادم',
      -1 => 'الأسبوع الماضي',
      _ => 'الأسبوع',
    };
    final groupActivities = [
      for (final a in widget.data.activities)
        if (a.groupIds.contains(widget.groupId)) a,
    ];
    List<Widget> dayCards(BuildContext context, DateTime day) => [
      for (final a in groupActivities)
        if (a.covers(day)) ...[
          ActivityCard(
            activity: a,
            day: day,
            groupNames: activityGroupNames(a, widget.data.groups),
            onTap: () => openActivity(context, a.id),
          ),
          const SizedBox(height: 8),
        ],
      for (final s in widget.sessions.where((s) => s.date == day)) ...[
        SessionCard(session: s, data: widget.data, showGroup: false, onTap: () => openSession(context, s.id)),
        const SizedBox(height: 8),
      ],
    ];
    return ScheduleModeBuilder(
      builder: (context, mode) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (series.isNotEmpty) ...[
            const SectionLabel('الحصص الأسبوعية'),
            for (final e in series.entries) _SeriesRow(sessions: e.value, now: now),
            const SizedBox(height: 4),
          ],
          const ScheduleModeToggle(),
          if (mode == ScheduleMode.month)
            MonthCalendar(
              now: now,
              sessions: widget.sessions,
              activities: groupActivities,
              replacedBy: widget.data.replacedBy,
              dayItems: dayCards,
              breaks: [
                for (final b in widget.data.breaks)
                  if (b.concerns([widget.groupId])) b,
              ],
            )
          else ...[
            Row(
              children: [
                IconButton(
                  key: const Key('group-previous-week'),
                  tooltip: 'الأسبوع السابق',
                  onPressed: () => setState(() => _weekOffset--),
                  icon: const Icon(Icons.chevron_right),
                ),
                Expanded(
                  child: Text(
                    '$weekLabel · من ${weekStart.day}'
                    '${weekStart.month == weekEnd.month ? '' : ' ${monthNames[weekStart.month - 1]}'}'
                    ' إلى ${weekEnd.day} ${monthNames[weekEnd.month - 1]}',
                    key: const Key('group-week-label'),
                    textAlign: TextAlign.center,
                    style: text.titleSmall,
                  ),
                ),
                IconButton(
                  key: const Key('group-next-week'),
                  tooltip: 'الأسبوع التالي',
                  onPressed: () => setState(() => _weekOffset++),
                  icon: const Icon(Icons.chevron_left),
                ),
              ],
            ),
            if (dayList.isEmpty) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'لا حصص في هذا الأسبوع.',
                  textAlign: TextAlign.center,
                  style: text.bodyMedium?.copyWith(color: RaeedColors.grey),
                ),
              ),
              if (next != null && (next.date.isBefore(weekStart) || next.date.isAfter(weekEnd)))
                TextButton(
                  key: const Key('group-jump-next'),
                  onPressed: () => setState(() => _weekOffset = next.date.difference(_thisWeek).inDays ~/ 7),
                  child: Text('الحصة القادمة: ${dayLabel(next.date, now)}'),
                ),
            ],
            for (final day in dayList) ...[
              SectionLabel(dayLabel(day, now)),
              for (final a in activityDays[day] ?? const <SpecialActivity>[]) ...[
                ActivityCard(
                  activity: a,
                  day: day,
                  groupNames: activityGroupNames(a, widget.data.groups),
                  onTap: () => openActivity(context, a.id),
                ),
                const SizedBox(height: 8),
              ],
              for (final s in days[day] ?? const <Session>[]) ...[
                SessionCard(session: s, data: widget.data, showGroup: false, onTap: () => openSession(context, s.id)),
                const SizedBox(height: 8),
              ],
            ],
          ],
        ],
      ),
    );
  }
}

/// One weekly series of a فئة, in one line: its day and time, how many are left, until when.
class _SeriesRow extends StatelessWidget {
  const _SeriesRow({required this.sessions, required this.now});

  /// Its coming sessions, in order.
  final List<Session> sessions;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final first = sessions.first;
    final last = sessions.last;
    final weekdays = {for (final s in sessions) dayOfWeek(s.date)}.toList()..sort();
    return Card(
      child: ListTile(
        key: Key('series-${first.seriesId}'),
        leading: const Icon(Icons.repeat, color: RaeedColors.blue),
        title: Text(first.title),
        subtitle: Text(
          [
            '${[for (final d in weekdays) weekdayNames[d]].join(' و')} ${formatTime(first.start)}',
            countLabel(sessions.length, one: 'حصة باقية', two: 'حصتان باقيتان', few: 'حصص باقية', many: 'حصة باقية'),
            'حتى ${last.date.day} ${monthNames[last.date.month - 1]}',
          ].join(' · '),
        ),
        trailing: const Icon(Icons.chevron_left),
        onTap: () => openSession(context, first.id),
      ),
    );
  }
}

class _KidRate extends StatelessWidget {
  const _KidRate({required this.child, required this.rate});

  final RosterChild child;
  final double? rate;

  @override
  Widget build(BuildContext context) {
    final low = rate != null && rate! < 0.8;
    return ListTile(
      key: Key('kid-${child.id}'),
      leading: InitialAvatar(child.fullName, size: 32),
      title: Text(child.fullName),
      trailing: Text(
        rate == null ? '—' : '${(rate! * 100).round()}%',
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: rate == null ? RaeedColors.grey : (low ? RaeedColors.error : const Color(0xFF1C7A55)),
        ),
      ),
      onTap: () => openChildProfile(context, child.id),
    );
  }
}

/// One instructor of a فئة, for its supervisor: how to reach them, and their presence on
/// each session they were given this term (or the last 30 days), with their absences.
class InstructorDetailScreen extends StatelessWidget {
  const InstructorDetailScreen({super.key, required this.personId, required this.groupId});

  final String personId;
  final String groupId;

  @override
  Widget build(BuildContext context) {
    final store = InstructorScope.of(context);
    final data = store.data;
    final now = store.now();
    final text = Theme.of(context).textTheme;
    final name = data.staffNames[personId] ?? 'مؤطر';
    final phone = data.staffPhones[personId];
    final since = data.termStart ?? dayOnly(now).subtract(const Duration(days: 30));
    final theirs = [
      for (final s in data.sessionsOf(groupId))
        // A session replaced by a نشاط نوعي does not count for or against them.
        if (!s.cancelled && data.replacedBy(s) == null && data.runs(s, personId) && !s.date.isBefore(since)) s,
    ];
    final presence = {for (final s in theirs) s.id: data.presence(s, personId, now)};
    int count(InstructorPresence p) => presence.values.where((v) => v == p).length;
    final past = theirs.where((s) => !s.endsAt.isAfter(now)).toList().reversed.toList();
    // Their absences: coming ones first, then the past, newest first.
    final absences = [
      for (final s in theirs.where((s) => s.endsAt.isAfter(now)))
        if (presence[s.id] == InstructorPresence.absent) s,
      for (final s in past)
        if (presence[s.id] == InstructorPresence.absent) s,
    ];
    final held = count(InstructorPresence.present) + count(InstructorPresence.unrecorded);
    final pastAbsent = past.where((s) => presence[s.id] == InstructorPresence.absent).length;
    final rate = past.isEmpty ? null : held / past.length;
    return Scaffold(
      appBar: AppBar(title: const Text('المؤطر')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  InitialAvatar(name, size: 52),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, key: const Key('instructor-name'), style: text.titleMedium),
                        if (phone != null)
                          Text(
                            '\u2066${formatPhone(phone)}\u2069',
                            key: const Key('instructor-phone'),
                            style: text.bodyMedium?.copyWith(color: RaeedColors.grey),
                          ),
                      ],
                    ),
                  ),
                  if (phone != null)
                    IconButton.filledTonal(
                      key: const Key('call-instructor'),
                      tooltip: 'اتصال',
                      onPressed: () => launchUrl(Uri.parse('tel:$phone')),
                      icon: const Icon(Icons.call),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _Stat(
                key: const Key('instructor-rate'),
                value: rate == null ? '—' : '${(rate * 100).round()}%',
                label: 'نسبة الحضور',
              ),
              const SizedBox(width: 8),
              _Stat(key: const Key('instructor-held'), value: '$held', label: 'حضر'),
              const SizedBox(width: 8),
              _Stat(key: const Key('instructor-absent'), value: '$pastAbsent', label: 'غاب', alert: pastAbsent > 0),
              const SizedBox(width: 8),
              _Stat(
                key: const Key('instructor-unrecorded'),
                value: '${count(InstructorPresence.unrecorded)}',
                label: 'بلا حضور',
                alert: count(InstructorPresence.unrecorded) > 0,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            data.termStart == null ? 'منذ 30 يوماً.' : 'منذ بداية الفصل.',
            style: text.bodySmall?.copyWith(color: RaeedColors.grey),
          ),
          if (absences.isNotEmpty) const SectionLabel('الغيابات'),
          for (final s in absences) _PresenceRow(session: s, personId: personId, presence: presence[s.id]!, now: now),
          if (theirs.isNotEmpty && absences.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text('لا غياب في هذه الفترة ولا غياب قادم.', style: TextStyle(color: RaeedColors.grey)),
            ),
          if (theirs.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text('لم يُكلَّف بحصص في هذه الفترة.', style: TextStyle(color: RaeedColors.grey)),
            ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({super.key, required this.value, required this.label, this.alert = false});

  final String value;
  final String label;
  final bool alert;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          child: Column(
            children: [
              Text(
                value,
                style: text.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: alert ? RaeedColors.error : RaeedColors.blue,
                ),
              ),
              Text(
                label,
                style: text.bodySmall?.copyWith(color: RaeedColors.grey),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PresenceRow extends StatelessWidget {
  const _PresenceRow({required this.session, required this.personId, required this.presence, required this.now});

  final Session session;
  final String personId;
  final InstructorPresence presence;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final data = InstructorScope.of(context).data;
    final absence = data.absenceOf(session.id, personId);
    final color = switch (presence) {
      InstructorPresence.present => const Color(0xFF1C7A55),
      InstructorPresence.absent || InstructorPresence.unrecorded => RaeedColors.error,
      InstructorPresence.upcoming => RaeedColors.grey,
    };
    return Card(
      key: Key('presence-${session.id}'),
      child: ListTile(
        title: Text(session.title),
        subtitle: Text(
          [
            '${dayLabel(session.date, now)} · ${session.timeLabel}',
            if (absence != null) 'السبب: ${absence.reason}',
          ].join('\n'),
        ),
        trailing: Text(
          presence.label,
          style: TextStyle(color: color, fontWeight: FontWeight.w600),
        ),
        onTap: () => openSession(context, session.id),
      ),
    );
  }
}
