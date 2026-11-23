import 'package:flutter/material.dart';

import '../setup/setup_repository.dart';
import '../setup/widgets.dart';
import '../theme/raeed_theme.dart';
import 'models.dart';
import 'sessions_screen.dart';
import 'widgets.dart';

/// The ملاحظات of a session, under its details: the instructors who run it write them,
/// the category supervisor and the advisors read them.
class SessionObservations extends StatefulWidget {
  const SessionObservations({super.key, required this.session});

  final Session session;

  @override
  State<SessionObservations> createState() => _SessionObservationsState();
}

class _SessionObservationsState extends State<SessionObservations> {
  late Future<List<SessionObservation>> _items = _load();

  Future<List<SessionObservation>> _load() => InstructorScope.read(context).observationsFor(widget.session.id);

  void _reload() {
    final next = _load();
    setState(() {
      _items = next;
    });
  }

  Future<void> _add() async {
    final body = await showDialog<String>(context: context, builder: (_) => const _ObservationDialog());
    if (body == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await InstructorScope.read(context).addObservation(widget.session.id, body);
      messenger.showSnackBar(const SnackBar(content: Text('حُفظت الملاحظة، ويراها مشرف الفئة.')));
      _reload();
    } on SetupError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(setupFailureMessage(e.failure))));
    }
  }

  Future<void> _delete(SessionObservation o) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('حذف الملاحظة؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('رجوع')),
          FilledButton(
            key: const Key('confirm-delete-observation'),
            style: FilledButton.styleFrom(backgroundColor: RaeedColors.error),
            onPressed: () => Navigator.pop(d, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await InstructorScope.read(context).deleteObservation(o.id);
      _reload();
    } on SetupError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(setupFailureMessage(e.failure))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = InstructorScope.of(context);
    final canWrite = store.canRecord(widget.session) && !widget.session.cancelled;
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionLabel('ملاحظات المؤطرين'),
        FutureBuilder<List<SessionObservation>>(
          future: _items,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Padding(
                padding: EdgeInsets.all(12),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (snap.hasError) {
              final failure = snap.error is SetupError ? (snap.error! as SetupError).failure : SetupFailure.unknown;
              return Row(
                children: [
                  Expanded(
                    child: Text(setupFailureMessage(failure), style: const TextStyle(color: RaeedColors.grey)),
                  ),
                  TextButton(onPressed: _reload, child: const Text('إعادة المحاولة')),
                ],
              );
            }
            final items = snap.data!;
            if (items.isEmpty) {
              return Text(
                canWrite ? 'لا ملاحظات بعد. اكتب كيف مرّت الحصة.' : 'لا ملاحظات على هذه الحصة بعد.',
                style: text.bodyMedium?.copyWith(color: RaeedColors.grey),
              );
            }
            return Column(
              children: [
                for (final o in items)
                  ObservationCard(observation: o, onDelete: o.authorId == store.personId ? () => _delete(o) : null),
              ],
            );
          },
        ),
        if (canWrite) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const Key('add-observation'),
            onPressed: _add,
            icon: const Icon(Icons.rate_review_outlined),
            label: const Text('إضافة ملاحظة'),
          ),
        ],
      ],
    );
  }
}

/// One observation: who wrote it, when, and the text. With [session], the session it is
/// about, which opens on tap.
class ObservationCard extends StatelessWidget {
  const ObservationCard({super.key, required this.observation, this.session, this.groupName, this.onDelete});

  final SessionObservation observation;
  final Session? session;
  final String? groupName;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final o = observation;
    final text = Theme.of(context).textTheme;
    final when = '${longDay(o.createdAt)} ${formatTime(o.createdAt.hour * 60 + o.createdAt.minute)}';
    final s = session;
    return Card(
      key: Key('observation-${o.id}'),
      child: InkWell(
        onTap: s == null ? null : () => openSession(context, s.id),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 8, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      [o.authorName, when].join(' · '),
                      style: text.bodySmall?.copyWith(color: RaeedColors.grey),
                    ),
                  ),
                  if (onDelete != null)
                    IconButton(
                      tooltip: 'حذف',
                      visualDensity: VisualDensity.compact,
                      onPressed: onDelete,
                      icon: const Icon(Icons.delete_outline, size: 20),
                    ),
                ],
              ),
              if (s != null)
                Text([?groupName, s.title, dayLabel(s.date, DateTime.now())].join(' · '), style: text.titleSmall),
              const SizedBox(height: 4),
              Text(o.body, style: text.bodyMedium),
            ],
          ),
        ),
      ),
    );
  }
}

/// The الملاحظات tab of a category supervisor: what the instructors of their فئة wrote on
/// its sessions in the last two months, newest first.
class ObservationsTab extends StatefulWidget {
  const ObservationsTab({super.key});

  @override
  State<ObservationsTab> createState() => _ObservationsTabState();
}

class _ObservationsTabState extends State<ObservationsTab> {
  Future<List<SessionObservation>>? _items;
  String _groupsKey = '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final store = InstructorScope.of(context);
    // Load again once the groups are known, and when they change.
    final key = [for (final g in store.data.groups) g.id].join(',');
    if (_items == null || key != _groupsKey) {
      _groupsKey = key;
      _items = store.recentObservations();
    }
  }

  Future<void> _refresh() async {
    final store = InstructorScope.read(context);
    await store.refresh();
    final next = store.recentObservations();
    setState(() {
      _items = next;
    });
    await next.catchError((_) => <SessionObservation>[]);
  }

  @override
  Widget build(BuildContext context) {
    return InstructorLoadGate(
      builder: (context, data) => RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<SessionObservation>>(
          future: _items,
          builder: (context, snap) {
            final children = <Widget>[];
            if (snap.connectionState != ConnectionState.done) {
              children.add(
                const Padding(
                  padding: EdgeInsets.all(40),
                  child: Center(child: CircularProgressIndicator()),
                ),
              );
            } else if (snap.hasError) {
              final failure = snap.error is SetupError ? (snap.error! as SetupError).failure : SetupFailure.unknown;
              children.add(_Hint(setupFailureMessage(failure)));
            } else if (snap.data!.isEmpty) {
              children.add(const _Hint('لا ملاحظات في آخر شهرين. يكتب المؤطرون ملاحظاتهم من صفحة كل حصة.'));
            } else {
              for (final o in snap.data!) {
                final s = data.session(o.sessionId);
                children.add(
                  ObservationCard(
                    observation: o,
                    session: s,
                    groupName: data.groups.length > 1 && s != null ? data.group(s.groupId)?.name : null,
                  ),
                );
                children.add(const SizedBox(height: 4));
              }
            }
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: children,
            );
          },
        ),
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

class _ObservationDialog extends StatefulWidget {
  const _ObservationDialog();

  @override
  State<_ObservationDialog> createState() => _ObservationDialogState();
}

class _ObservationDialogState extends State<_ObservationDialog> {
  final _body = TextEditingController();

  @override
  void dispose() {
    _body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('ملاحظة على الحصة'),
      content: TextField(
        key: const Key('observation-body'),
        controller: _body,
        autofocus: true,
        minLines: 3,
        maxLines: 8,
        maxLength: 2000,
        onChanged: (_) => setState(() {}),
        decoration: const InputDecoration(hintText: 'كيف مرّت الحصة؟ ما الذي يحتاج متابعة؟'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('رجوع')),
        FilledButton(
          key: const Key('save-observation'),
          onPressed: _body.text.trim().isEmpty ? null : () => Navigator.pop(context, _body.text.trim()),
          child: const Text('حفظ'),
        ),
      ],
    );
  }
}
