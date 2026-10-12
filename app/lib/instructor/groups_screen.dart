import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../auth/phone.dart';
import '../setup/models.dart';
import '../setup/widgets.dart';
import '../theme/raeed_theme.dart';
import 'attendance_screen.dart';
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
              _GroupRow(group: g, data: data, now: store.now(), me: store.personId),
              const SizedBox(height: 8),
            ],
          ],
        );
      },
    );
  }
}

class _GroupRow extends StatelessWidget {
  const _GroupRow({required this.group, required this.data, required this.now, required this.me});

  final Group group;
  final InstructorSnapshot data;
  final DateTime now;
  final String? me;

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
          if (others.isNotEmpty) 'معك: $others',
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
  bool _sessions = false;

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
          SegmentedButton<bool>(
            key: const Key('group-tabs'),
            segments: [
              ButtonSegment(value: false, label: Text('الأطفال ${kids.length}')),
              const ButtonSegment(value: true, label: Text('الحصص')),
            ],
            selected: {_sessions},
            onSelectionChanged: (v) => setState(() => _sessions = v.first),
          ),
          const SizedBox(height: 10),
          if (!_sessions) ...[
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
                  ? 'نسبة الحضور في آخر 30 يوماً. اضغط على اسم لرؤية أولياء الأمور والملاحظات.'
                  : 'نسبة الحضور هذا الفصل. اضغط على اسم لرؤية أولياء الأمور والملاحظات.',
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
          const SizedBox(height: 12),
          FilledButton.icon(
            key: const Key('new-session-for-group'),
            onPressed: () => openSessionForm(context, groupId: group.id),
            icon: const Icon(Icons.add),
            label: const Text('حصة جديدة لهذه الفئة'),
          ),
        ],
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
      onTap: () => _showChild(context, child),
    );
  }
}

/// The parents to call and the note button. The full child profile comes with the
/// statistics stage.
Future<void> _showChild(BuildContext context, RosterChild child) => showModalBottomSheet<void>(
  context: context,
  builder: (sheet) {
    final text = Theme.of(sheet).textTheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(child.fullName, style: text.titleLarge),
            const SectionLabel('أولياء الأمور'),
            if (child.parents.isEmpty) const Text('لا يوجد ولي أمر مسجّل.', style: TextStyle(color: RaeedColors.grey)),
            for (final p in child.parents)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(p.fullName),
                subtitle: Text(formatPhone(p.phone), textDirection: TextDirection.ltr, textAlign: TextAlign.end),
                trailing: IconButton(
                  tooltip: 'اتصال',
                  onPressed: () => launchUrl(Uri.parse('tel:${p.phone}')),
                  icon: const Icon(Icons.call, color: RaeedColors.blue),
                ),
              ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.pop(sheet);
                showNoteSheet(context, child);
              },
              icon: const Icon(Icons.note_add_outlined),
              label: const Text('ملاحظة'),
            ),
          ],
        ),
      ),
    );
  },
);
