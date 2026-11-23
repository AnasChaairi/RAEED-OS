import 'package:flutter/material.dart';

import '../profile/child_profile_screen.dart';
import '../setup/models.dart';
import '../setup/widgets.dart';
import '../theme/raeed_theme.dart';
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
                  'لم تُسند إليك أي فئة بعد. تواصل مع المشرف.',
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
    final upcoming = sessions.where((s) => s.endsAt.isAfter(now)).toList();
    final past = sessions.where((s) => !s.endsAt.isAfter(now)).toList().reversed.toList();
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
                'لا يوجد أطفال في هذه الفئة بعد. يضيفهم المشرف من الإعدادات.',
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
            if (upcoming.isEmpty && past.isEmpty) const Text('لا حصص بعد.', style: TextStyle(color: RaeedColors.grey)),
            if (upcoming.isNotEmpty) const SectionLabel('القادمة'),
            for (final s in upcoming.take(12)) ...[
              SessionCard(session: s, data: data, showGroup: false, onTap: () => openSession(context, s.id)),
              const SizedBox(height: 8),
            ],
            if (past.isNotEmpty) const SectionLabel('السابقة'),
            for (final s in past.take(12)) ...[
              SessionCard(session: s, data: data, showGroup: false, onTap: () => openSession(context, s.id)),
              const SizedBox(height: 8),
            ],
          ],
          if (store.schedules) ...[
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const Key('new-session-for-group'),
              onPressed: () => openSessionForm(context, groupId: group.id),
              icon: const Icon(Icons.add),
              label: const Text('حصة جديدة لهذه الفئة'),
            ),
          ],
        ],
      ),
    );
  }
}

/// One instructor of the فئة, for its supervisor: the sessions they ran in the last
/// 30 days, how many have their attendance, and what is coming.
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
        if (!s.cancelled && data.runs(s, personId)) s,
    ];
    final done = [
      for (final s in theirs)
        if (!s.endsAt.isAfter(now) && !s.date.isBefore(monthAgo)) s,
    ];
    final missing = done.where((s) => data.attendanceFor(s.id).isEmpty).length;
    final upcoming = theirs.where((s) => s.endsAt.isAfter(now)).length;
    final name = data.staffNames[personId] ?? 'مؤطر';
    return Card(
      key: Key('instructor-work-$personId'),
      child: ListTile(
        leading: InitialAvatar(name, size: 36),
        title: Text(name),
        subtitle: Text(
          [
            countLabel(
              done.length,
              one: 'حصة منتهية واحدة',
              two: 'حصتان منتهيتان',
              few: 'حصص منتهية',
              many: 'حصة منتهية',
            ),
            if (done.isNotEmpty) missing == 0 ? 'الحضور مسجّل في كلها' : 'بلا حضور: $missing',
            countLabel(upcoming, one: 'حصة قادمة واحدة', two: 'حصتان قادمتان', few: 'حصص قادمة', many: 'حصة قادمة'),
          ].join(' · '),
          style: TextStyle(color: missing > 0 ? RaeedColors.error : null),
        ),
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
