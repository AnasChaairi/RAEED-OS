import 'package:flutter/material.dart';

import '../setup/setup_repository.dart';
import '../setup/widgets.dart';
import '../theme/raeed_theme.dart';
import 'models.dart';
import 'widgets.dart';

/// The attendance sheet. Everyone starts as present, so the instructor taps only the
/// exceptions. Saving writes to the phone first and sends when there is a connection.
class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key, required this.sessionId});

  final String sessionId;

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  Map<String, AttendanceStatus>? _statuses;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final store = InstructorScope.of(context);
    final data = store.data;
    final session = data.session(widget.sessionId);
    if (session == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('لم تعد هذه الحصة موجودة.')),
      );
    }
    final group = data.group(session.groupId);
    final kids = data.childrenIn(session.groupId);
    final existing = data.attendanceFor(session.id);
    final statuses = _statuses ??= {for (final c in kids) c.id: existing[c.id]?.status ?? AttendanceStatus.present};
    final text = Theme.of(context).textTheme;
    final waiting = store.waitingSessions.contains(session.id);

    String savedLine() {
      if (existing.isEmpty) return 'لم يُسجَّل بعد · يراه مؤطرو الفئة الآخرون بعد الحفظ';
      final last = existing.values.reduce((a, b) => a.recordedAt.isAfter(b.recordedAt) ? a : b);
      final who = last.recordedBy == store.personId ? 'أنت' : (data.staffNames[last.recordedBy] ?? 'مؤطر');
      final when = '${longDay(last.recordedAt)} ${formatTime(last.recordedAt.hour * 60 + last.recordedAt.minute)}';
      return waiting ? 'محفوظ على هاتفك · $when · في انتظار الإرسال' : 'سجّله $who · $when';
    }

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 68,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('الحضور · ${group?.name ?? ''}'),
            Text(
              '${session.title} · ${dayLabel(session.date, store.now())}',
              style: text.bodySmall?.copyWith(color: RaeedColors.grey),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          if (store.offline)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: OfflineBanner(text: 'لا يوجد إنترنت. الحضور يُحفظ على هاتفك ويُرسل تلقائياً عند عودة الاتصال.'),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final s in AttendanceStatus.values)
                  _CountChip(status: s, count: statuses.values.where((v) => v == s).length),
              ],
            ),
          ),
          Expanded(
            child: kids.isEmpty
                ? const Center(
                    child: Text('لا يوجد أطفال في هذه الفئة بعد.', style: TextStyle(color: RaeedColors.grey)),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    itemCount: kids.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final kid = kids[i];
                      return _KidRow(
                        child: kid,
                        status: statuses[kid.id] ?? AttendanceStatus.present,
                        onChanged: (s) => setState(() => statuses[kid.id] = s),
                      );
                    },
                  ),
          ),
          Material(
            color: RaeedColors.surface,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      savedLine(),
                      key: const Key('saved-line'),
                      textAlign: TextAlign.center,
                      style: text.bodySmall?.copyWith(color: RaeedColors.grey),
                    ),
                    const SizedBox(height: 6),
                    FilledButton(
                      key: const Key('save-attendance'),
                      onPressed: _busy || kids.isEmpty ? null : () => _save(statuses),
                      child: const Text('حفظ الحضور'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _save(Map<String, AttendanceStatus> statuses) async {
    setState(() => _busy = true);
    final store = InstructorScope.read(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await store.saveAttendance(widget.sessionId, Map.of(statuses));
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            store.waitingSessions.contains(widget.sessionId)
                ? 'تم الحفظ على الهاتف ✓ سيُرسل عند عودة الاتصال.'
                : 'تم حفظ الحضور ✓',
          ),
        ),
      );
    } on SetupError catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('حُفظ على الهاتف، لكن الإرسال فشل: ${setupFailureMessage(e.failure)}')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _CountChip extends StatelessWidget {
  const _CountChip({required this.status, required this.count});

  final AttendanceStatus status;
  final int count;

  @override
  Widget build(BuildContext context) {
    final (fg, bg) = statusColors(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
      child: Text(
        '${status.label} $count',
        key: Key('count-${status.name}'),
        style: TextStyle(color: fg, fontWeight: FontWeight.w600, fontSize: 13),
      ),
    );
  }
}

class _KidRow extends StatelessWidget {
  const _KidRow({required this.child, required this.status, required this.onChanged});

  final RosterChild child;
  final AttendanceStatus status;
  final ValueChanged<AttendanceStatus> onChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          children: [
            Row(
              children: [
                InitialAvatar(child.fullName, size: 30),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    child.fullName,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                ),
                OutlinedButton(
                  key: Key('note-${child.id}'),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    minimumSize: const Size(0, 32),
                  ),
                  onPressed: () => showNoteSheet(context, child),
                  child: const Text('+ ملاحظة', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(color: RaeedColors.surfaceAlt, borderRadius: BorderRadius.circular(12)),
              child: Row(
                children: [
                  for (final s in AttendanceStatus.values)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 1.5),
                        child: _StatusButton(
                          key: Key('status-${child.id}-${s.name}'),
                          status: s,
                          selected: s == status,
                          onTap: () => onChanged(s),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusButton extends StatelessWidget {
  const _StatusButton({super.key, required this.status, required this.selected, required this.onTap});

  final AttendanceStatus status;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (fg, _) = statusColors(status);
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? fg : Colors.transparent,
        borderRadius: BorderRadius.circular(9),
        child: InkWell(
          borderRadius: BorderRadius.circular(9),
          onTap: onTap,
          child: SizedBox(
            height: 44,
            child: Center(
              child: Text(
                status.label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: selected ? Colors.white : RaeedColors.ink.withValues(alpha: 0.75),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A short, dated note on a child, seen only by the group's instructors and the advisors.
Future<void> showNoteSheet(BuildContext context, RosterChild child) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  builder: (_) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: _NoteSheet(child: child),
  ),
);

class _NoteSheet extends StatefulWidget {
  const _NoteSheet({required this.child});

  final RosterChild child;

  @override
  State<_NoteSheet> createState() => _NoteSheetState();
}

class _NoteSheetState extends State<_NoteSheet> {
  final _body = TextEditingController();
  late final Future<List<ChildNote>> _notes = InstructorScope.read(context).notesFor(widget.child.id);
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _body.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final body = _body.text.trim();
    if (body.isEmpty) return setState(() => _error = 'اكتب الملاحظة');
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final messenger = ScaffoldMessenger.of(context);
      await InstructorScope.read(context).addNote(widget.child.id, body);
      if (!mounted) return;
      Navigator.pop(context);
      messenger.showSnackBar(const SnackBar(content: Text('حُفظت الملاحظة ✓')));
    } on SetupError catch (e) {
      if (mounted) setState(() => _error = setupFailureMessage(e.failure));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final now = InstructorScope.read(context).now();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('ملاحظة على ${widget.child.fullName}', style: text.titleMedium),
            Text(
              'يراها مؤطرو الفئة والمشرفون فقط، ولا تصل لأولياء الأمور.',
              style: text.bodySmall?.copyWith(color: RaeedColors.grey),
            ),
            const SizedBox(height: 10),
            TextField(
              key: const Key('note-body'),
              controller: _body,
              maxLines: 3,
              maxLength: 2000,
              decoration: InputDecoration(hintText: 'مثلاً: تحسّن في الحفظ هذا الأسبوع', errorText: _error),
            ),
            FilledButton(
              key: const Key('save-note'),
              onPressed: _busy ? null : _save,
              child: const Text('حفظ الملاحظة'),
            ),
            const SizedBox(height: 8),
            FutureBuilder<List<ChildNote>>(
              future: _notes,
              builder: (context, snap) {
                if (snap.hasError) {
                  return Text(
                    'الملاحظات السابقة تحتاج اتصالاً بالإنترنت.',
                    style: text.bodySmall?.copyWith(color: RaeedColors.grey),
                  );
                }
                final notes = snap.data ?? const [];
                if (notes.isEmpty) return const SizedBox.shrink();
                return ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 220),
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      const SectionLabel('ملاحظات سابقة'),
                      for (final n in notes)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(n.body),
                              Text(
                                '${n.authorName} · ${daysAgo(n.createdAt, now)}',
                                style: text.bodySmall?.copyWith(color: RaeedColors.grey),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
