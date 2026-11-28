import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../instructor/models.dart' show RosterChild, dayOnly, longDay;
import '../instructor/widgets.dart' show InstructorScope;
import '../notifications/push.dart';
import '../parent/parent_models.dart' show ParentChild;
import '../parent/parent_store.dart';
import '../setup/setup_repository.dart';
import '../setup/widgets.dart';
import '../theme/raeed_theme.dart';
import '../widgets/form_error.dart';
import '../widgets/pickers.dart';
import 'homework.dart';

const _doneColor = Color(0xFF1C7A55);

/// «التسليم: الخميس 4 دجنبر», with «اليوم» and «غداً».
String dueLabel(DateTime due, DateTime now) {
  final days = dayOnly(due).difference(dayOnly(now)).inDays;
  final when = switch (days) {
    0 => 'اليوم',
    1 => 'غداً',
    _ => longDay(due),
  };
  return 'التسليم: $when';
}

/// Loads homework for [groupIds] and reloads it after a change or a notification.
mixin _HomeworkLoader<T extends StatefulWidget> on State<T> {
  Future<List<Homework>>? items;
  StreamSubscription<PushMessage>? _pushes;
  String _key = '';

  List<String> get groupIds;
  HomeworkRepository? get repo => HomeworkScope.of(context);

  void reload() {
    final r = repo;
    if (r == null) return;
    setState(() {
      items = r.load(groupIds);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final key = groupIds.join(',');
    if (repo != null && (items == null || key != _key)) {
      _key = key;
      items = repo!.load(groupIds);
      _pushes ??= PushScope.read(context).messages.listen((_) {
        if (mounted) reload();
      });
    }
  }

  @override
  void dispose() {
    _pushes?.cancel();
    super.dispose();
  }

  Future<bool> run(Future<void> Function(HomeworkRepository r) action) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action(repo!);
      reload();
      return true;
    } on SetupError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(setupFailureMessage(e.failure))));
      return false;
    }
  }

  Widget loaded(Widget Function(List<Homework>) build) {
    if (repo == null) return const _Hint('غير متاح.');
    return FutureBuilder<List<Homework>>(
      future: items,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.all(40),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snap.hasError) {
          final failure = snap.error is SetupError ? (snap.error! as SetupError).failure : SetupFailure.unknown;
          return Column(
            children: [
              _Hint(setupFailureMessage(failure)),
              TextButton(onPressed: reload, child: const Text('حاول مرة أخرى')),
            ],
          );
        }
        return build(snap.data!);
      },
    );
  }
}

// The parent's tab -----------------------------------------------------------------------------

/// The parent's الواجبات tab: each child's homework, to mark تم or لم يتم.
class ParentHomeworkTab extends StatefulWidget {
  const ParentHomeworkTab({super.key});

  @override
  State<ParentHomeworkTab> createState() => _ParentHomeworkTabState();
}

class _ParentHomeworkTabState extends State<ParentHomeworkTab> with _HomeworkLoader {
  bool _showPast = false;

  List<ParentChild> get _kids => ParentScope.of(context).data.children;

  @override
  List<String> get groupIds => {for (final c in _kids) ?c.group?.id}.toList()..sort();

  @override
  Widget build(BuildContext context) {
    final store = ParentScope.of(context);
    final kids = _kids;
    final now = store.now();
    final text = Theme.of(context).textTheme;
    return RefreshIndicator(
      onRefresh: () async {
        reload();
        await items?.catchError((_) => <Homework>[]);
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          if (!store.loaded && store.loading)
            const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (kids.every((k) => k.group == null))
            const _Hint('لا واجبات بعد. حين يكلّف مشرف الفئة طفلك بواجب يظهر هنا ويصلك إشعار.')
          else
            loaded((all) {
              // One card per child and homework.
              final rows = <(Homework, ParentChild)>[
                for (final h in all)
                  for (final k in kids)
                    if (k.group?.id == h.groupId && h.targets([k.id]).isNotEmpty) (h, k),
              ];
              if (rows.isEmpty) {
                return const _Hint('لا واجبات بعد. حين يكلّف مشرف الفئة طفلك بواجب يظهر هنا ويصلك إشعار.');
              }
              final open = [
                for (final r in rows)
                  if (!r.$1.isPast(now)) r,
              ]..sort((a, b) => a.$1.dueDate.compareTo(b.$1.dueDate));
              final past = [
                for (final r in rows)
                  if (r.$1.isPast(now)) r,
              ];
              Widget card((Homework, ParentChild) r) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: HomeworkCard(
                  key: Key('parent-homework-${r.$1.id}-${r.$2.id}'),
                  homework: r.$1,
                  now: now,
                  childName: kids.length > 1 ? r.$2.firstName : null,
                  footer: MarkButtons(
                    keyPrefix: 'mark-${r.$1.id}-${r.$2.id}',
                    mark: r.$1.marks[r.$2.id],
                    onMark: (done) => run((repo) => repo.mark(r.$1.id, r.$2.id, done)),
                  ),
                ),
              );
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'بعد أن ينجز طفلك الواجب، اضغط «تم». يرى مشرف الفئة ما تختاره.',
                    style: text.bodySmall?.copyWith(color: RaeedColors.grey),
                  ),
                  const SizedBox(height: 8),
                  if (open.isEmpty) const _Hint('لا واجبات قادمة.') else for (final r in open) card(r),
                  if (past.isNotEmpty) ...[
                    TextButton.icon(
                      key: const Key('homework-past'),
                      onPressed: () => setState(() => _showPast = !_showPast),
                      icon: Icon(_showPast ? Icons.expand_less : Icons.expand_more),
                      label: Text('انتهى موعدها (${past.length})'),
                    ),
                    if (_showPast)
                      for (final r in past) card(r),
                  ],
                ],
              );
            }),
        ],
      ),
    );
  }
}

/// تم and لم يتم. Tapping the chosen one again clears it.
class MarkButtons extends StatelessWidget {
  const MarkButtons({super.key, required this.keyPrefix, required this.mark, required this.onMark});

  final String keyPrefix;
  final HomeworkMark? mark;
  final ValueChanged<bool?> onMark;

  @override
  Widget build(BuildContext context) {
    final done = mark?.done;
    Widget button(bool value, String label, IconData icon, Color color) {
      final selected = done == value;
      final style = selected
          ? FilledButton.styleFrom(backgroundColor: color, foregroundColor: Colors.white)
          : OutlinedButton.styleFrom(
              foregroundColor: color,
              side: BorderSide(color: color.withValues(alpha: 0.5)),
            );
      final child = Row(
        mainAxisSize: MainAxisSize.min,
        children: [Icon(icon, size: 18), const SizedBox(width: 6), Text(label)],
      );
      return Expanded(
        child: selected
            ? FilledButton(key: Key('$keyPrefix-$value'), style: style, onPressed: () => onMark(null), child: child)
            : OutlinedButton(key: Key('$keyPrefix-$value'), style: style, onPressed: () => onMark(value), child: child),
      );
    }

    return Row(
      children: [
        button(true, 'تم', Icons.check_circle_outline, _doneColor),
        const SizedBox(width: 8),
        button(false, 'لم يتم', Icons.cancel_outlined, RaeedColors.error),
      ],
    );
  }
}

/// A homework: its template, summary, details and due date.
class HomeworkCard extends StatelessWidget {
  const HomeworkCard({
    super.key,
    required this.homework,
    required this.now,
    this.childName,
    this.subtitle,
    this.groupName,
    this.footer,
    this.onTap,
  });

  final Homework homework;
  final DateTime now;
  final String? childName;
  final String? subtitle;

  /// Shown when the list mixes فئات.
  final String? groupName;
  final Widget? footer;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final h = homework;
    final days = dayOnly(h.dueDate).difference(dayOnly(now)).inDays;
    final dueColor = days < 0 ? RaeedColors.grey : (days <= 1 ? RaeedColors.starEnd : RaeedColors.blue);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(color: RaeedColors.surfaceAlt, borderRadius: BorderRadius.circular(12)),
                    child: Icon(h.template.icon, color: RaeedColors.blue),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          [h.template.label, ?groupName, ?childName].join(' · '),
                          style: text.labelMedium?.copyWith(color: RaeedColors.grey),
                        ),
                        const SizedBox(height: 2),
                        Text(h.summary, style: text.titleMedium),
                        if (h.details != null && h.details!.trim().isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(h.details!, style: text.bodyMedium),
                        ],
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(Icons.event, size: 16, color: dueColor),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                dueLabel(h.dueDate, now),
                                style: text.bodySmall?.copyWith(color: dueColor, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                        if (h.assignedBy != null) ...[
                          const SizedBox(height: 2),
                          Text('كلّف به: ${h.assignedBy}', style: text.bodySmall?.copyWith(color: RaeedColors.grey)),
                        ],
                        if (subtitle != null) ...[
                          const SizedBox(height: 4),
                          Text(subtitle!, style: text.bodySmall?.copyWith(color: RaeedColors.grey)),
                        ],
                      ],
                    ),
                  ),
                  if (onTap != null) const Icon(Icons.chevron_left, color: RaeedColors.grey),
                ],
              ),
              if (footer != null) ...[const SizedBox(height: 12), footer!],
            ],
          ),
        ),
      ),
    );
  }
}

// The supervisor's side -----------------------------------------------------------------------

/// «تم 5 · لم يتم 1 · لم يُحدَّد 4» for [kids].
String progressLabel(Homework h, List<String> kids) {
  final targets = h.targets(kids);
  var done = 0, notDone = 0;
  for (final c in targets) {
    final m = h.marks[c];
    if (m == null) continue;
    m.done ? done++ : notDone++;
  }
  final who = h.wholeGroup
      ? 'الفئة كاملة'
      : countLabel(targets.length, one: 'طفل واحد', two: 'طفلان', few: 'أطفال', many: 'طفلاً');
  return '$who · تم $done · لم يتم $notDone · لم يُحدَّد ${targets.length - done - notDone}';
}

/// The الواجبات part of a فئة's page, for its supervisor: the homework given, how many
/// children did it, and the button to give a new one.
class GroupHomework extends StatefulWidget {
  const GroupHomework({super.key, required this.groupId});

  final String groupId;

  @override
  State<GroupHomework> createState() => _GroupHomeworkState();
}

class _GroupHomeworkState extends State<GroupHomework> with _HomeworkLoader {
  @override
  List<String> get groupIds => [widget.groupId];

  Future<void> _open(Widget screen) async {
    await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => screen));
    if (mounted) reload();
  }

  @override
  Widget build(BuildContext context) {
    final store = InstructorScope.of(context);
    final kids = [for (final k in store.data.childrenIn(widget.groupId)) k.id];
    final now = store.now();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          key: const Key('new-homework'),
          onPressed: repo == null ? null : () => _open(HomeworkFormScreen(groupId: widget.groupId)),
          icon: const Icon(Icons.add_task),
          label: const Text('واجب جديد'),
        ),
        const SizedBox(height: 10),
        loaded((all) {
          if (all.isEmpty) {
            return const _Hint('لم تُكلَّف هذه الفئة بأي واجب بعد. يصل كل واجب إلى أولياء الأمور في قسم الواجبات.');
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final h in all) ...[
                HomeworkCard(
                  key: Key('homework-${h.id}'),
                  homework: h,
                  now: now,
                  subtitle: progressLabel(h, kids),
                  onTap: () => _open(HomeworkDetailScreen(homework: h)),
                ),
                const SizedBox(height: 8),
              ],
            ],
          );
        }),
      ],
    );
  }
}

/// A homework for its supervisor: what each child's parents marked. The supervisor can
/// mark too (for a child whose parents have no account), change it or delete it.
class HomeworkDetailScreen extends StatefulWidget {
  const HomeworkDetailScreen({super.key, required this.homework, this.readOnly = false});

  final Homework homework;

  /// For the مشرف العام: sees everything, changes nothing.
  final bool readOnly;

  @override
  State<HomeworkDetailScreen> createState() => _HomeworkDetailScreenState();
}

class _HomeworkDetailScreenState extends State<HomeworkDetailScreen> with _HomeworkLoader {
  @override
  List<String> get groupIds => [widget.homework.groupId];

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('حذف الواجب؟'),
        content: const Text('يختفي من قسم الواجبات عند أولياء الأمور، مع ما سجّلوه.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
          TextButton(
            key: const Key('confirm-delete-homework'),
            style: TextButton.styleFrom(foregroundColor: RaeedColors.error),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final navigator = Navigator.of(context);
    if (await run((r) => r.delete(widget.homework.id))) navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final store = InstructorScope.of(context);
    final kids = store.data.childrenIn(widget.homework.groupId);
    final now = store.now();
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('الواجب'),
        actions: [
          if (!widget.readOnly) ...[
            FutureBuilder<List<Homework>>(
              future: items,
              builder: (context, snap) {
                final h = snap.data?.where((x) => x.id == widget.homework.id).firstOrNull ?? widget.homework;
                return IconButton(
                  key: const Key('edit-homework'),
                  tooltip: 'تعديل',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => HomeworkFormScreen(groupId: h.groupId, homework: h),
                      ),
                    );
                    if (mounted) reload();
                  },
                );
              },
            ),
            IconButton(
              key: const Key('delete-homework'),
              tooltip: 'حذف',
              icon: const Icon(Icons.delete_outline, color: RaeedColors.error),
              onPressed: _delete,
            ),
          ],
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          loaded((all) {
            final h = all.where((x) => x.id == widget.homework.id).firstOrNull;
            if (h == null) return const _Hint('حُذف هذا الواجب.');
            final targets = h.targets([for (final k in kids) k.id]);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                HomeworkCard(
                  homework: h,
                  now: now,
                  groupName: store.data.group(h.groupId)?.name,
                  subtitle: progressLabel(h, [for (final k in kids) k.id]),
                ),
                const SizedBox(height: 12),
                Text('الأطفال', style: text.titleMedium),
                const SizedBox(height: 4),
                Text(
                  widget.readOnly
                      ? 'ما اختاره أولياء الأمور (أو مشرف الفئة) لكل طفل، وتاريخه.'
                      : 'يختار أولياء الأمور «تم» أو «لم يتم». يمكنك أيضاً التسجيل بنفسك.',
                  style: text.bodySmall?.copyWith(color: RaeedColors.grey),
                ),
                const SizedBox(height: 8),
                if (targets.isEmpty)
                  const _Hint('لا أطفال في هذا الواجب.')
                else
                  Card(
                    child: Column(
                      children: [
                        for (final k in kids)
                          if (targets.contains(k.id))
                            _ChildMarkRow(child: k, homework: h, onMark: widget.readOnly ? null : run),
                      ],
                    ),
                  ),
              ],
            );
          }),
        ],
      ),
    );
  }
}

class _ChildMarkRow extends StatelessWidget {
  const _ChildMarkRow({required this.child, required this.homework, required this.onMark});

  final RosterChild child;
  final Homework homework;
  final Future<bool> Function(Future<void> Function(HomeworkRepository r))? onMark;

  @override
  Widget build(BuildContext context) {
    final m = homework.marks[child.id];
    final (label, color, icon) = switch (m?.done) {
      true => ('تم', _doneColor, Icons.check_circle),
      false => ('لم يتم', RaeedColors.error, Icons.cancel),
      null => ('لم يُحدَّد', RaeedColors.grey, Icons.radio_button_unchecked),
    };
    return ListTile(
      key: Key('homework-child-${child.id}'),
      leading: InitialAvatar(child.fullName, size: 32),
      title: Text(child.fullName),
      subtitle: m == null ? null : Text('${m.markedAt.day}/${m.markedAt.month}'),
      trailing: PopupMenuButton<int>(
        key: Key('homework-child-mark-${child.id}'),
        tooltip: 'تسجيل',
        enabled: onMark != null,
        onSelected: (v) => onMark!((r) => r.mark(homework.id, child.id, v == 2 ? null : v == 1)),
        itemBuilder: (_) => const [
          PopupMenuItem(value: 1, child: Text('تم')),
          PopupMenuItem(value: 0, child: Text('لم يتم')),
          PopupMenuItem(value: 2, child: Text('مسح')),
        ],
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(color: color, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

/// Gives a new homework to the فئة or some of its children, or changes [homework]. The
/// supervisor picks a template, then fills its fields.
class HomeworkFormScreen extends StatefulWidget {
  const HomeworkFormScreen({super.key, required this.groupId, this.homework});

  final String groupId;
  final Homework? homework;

  @override
  State<HomeworkFormScreen> createState() => _HomeworkFormScreenState();
}

class _HomeworkFormScreenState extends State<HomeworkFormScreen> {
  final _form = GlobalKey<FormState>();
  HomeworkTemplate? _template;
  final _controllers = <String, TextEditingController>{};
  final _details = TextEditingController();
  DateTime? _due;
  bool _whole = true;
  final _picked = <String>{};
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final h = widget.homework;
    if (h != null) {
      _template = h.template;
      for (final e in h.fields.entries) {
        _controller(e.key).text = e.value;
      }
      _details.text = h.details ?? '';
      _due = h.dueDate;
      _whole = h.wholeGroup;
      _picked.addAll(h.childIds);
    }
  }

  TextEditingController _controller(String key) => _controllers.putIfAbsent(key, TextEditingController.new);

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    _details.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final repo = HomeworkScope.of(context);
    if (repo == null || _template == null) return;
    if (!_form.currentState!.validate()) return;
    if (!_whole && _picked.isEmpty) {
      setState(() => _error = 'اختر طفلاً واحداً على الأقل، أو «الفئة كاملة».');
      return;
    }
    final kids = {for (final k in InstructorScope.read(context).data.childrenIn(widget.groupId)) k.id};
    final draft = HomeworkDraft(
      groupId: widget.groupId,
      template: _template!,
      fields: {for (final f in _template!.fields) f.key: _controller(f.key).text},
      details: _details.text,
      dueDate: _due!,
      childIds: _whole
          ? const []
          : [
              for (final c in _picked)
                if (kids.contains(c)) c,
            ],
    );
    setState(() {
      _saving = true;
      _error = null;
    });
    final navigator = Navigator.of(context);
    try {
      if (widget.homework == null) {
        await repo.create(draft);
      } else {
        await repo.update(widget.homework!.id, draft);
      }
      navigator.pop();
    } on SetupError catch (e) {
      setState(() => _error = setupFailureMessage(e.failure));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = InstructorScope.of(context);
    final kids = store.data.childrenIn(widget.groupId);
    final text = Theme.of(context).textTheme;
    final t = _template;
    final today = dayOnly(store.now());
    return Scaffold(
      appBar: AppBar(title: Text(widget.homework == null ? 'واجب جديد' : 'تعديل الواجب')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            Text('نوع الواجب', style: text.titleMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final x in HomeworkTemplate.values)
                  ChoiceChip(
                    key: Key('template-${x.dbName}'),
                    avatar: Icon(x.icon, size: 18),
                    label: Text(x.label),
                    selected: t == x,
                    onSelected: (_) => setState(() => _template = x),
                  ),
              ],
            ),
            if (t == null) ...[
              const SizedBox(height: 16),
              Text(
                'اختر نموذجاً لتظهر خاناته. «واجب آخر» لما ليس في القائمة.',
                style: text.bodySmall?.copyWith(color: RaeedColors.grey),
              ),
            ] else ...[
              const SizedBox(height: 16),
              for (final f in t.fields) ...[
                TextFormField(
                  key: Key('homework-field-${f.key}'),
                  controller: _controller(f.key),
                  decoration: InputDecoration(labelText: f.label, hintText: f.hint),
                  keyboardType: f.number ? TextInputType.number : TextInputType.text,
                  inputFormatters: f.number ? [FilteringTextInputFormatter.digitsOnly] : null,
                  textInputAction: TextInputAction.next,
                  validator: (v) => f.required && (v ?? '').trim().isEmpty ? 'اكتب ${f.label}' : null,
                ),
                const SizedBox(height: 12),
              ],
              TextFormField(
                key: const Key('homework-details'),
                controller: _details,
                decoration: const InputDecoration(labelText: 'تفصيل', hintText: 'اختياري: توجيهات، طريقة التسليم...'),
                minLines: 2,
                maxLines: 5,
                maxLength: 2000,
              ),
              const SizedBox(height: 4),
              FormField<DateTime>(
                key: const Key('homework-due'),
                validator: (_) => _due == null ? 'اختر موعد التسليم' : null,
                builder: (state) => InkWell(
                  onTap: () async {
                    final picked = await showUpcomingDateSheet(
                      context,
                      title: 'موعد التسليم',
                      initial: _due,
                      firstDate: _due != null && _due!.isBefore(today) ? _due! : today,
                      lastDate: today.add(const Duration(days: 365)),
                      today: today,
                    );
                    if (picked != null) {
                      setState(() => _due = picked);
                      state.didChange(picked);
                    }
                  },
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: 'موعد التسليم',
                      errorText: state.errorText,
                      suffixIcon: const Icon(Icons.calendar_today_outlined),
                    ),
                    child: Text(_due == null ? '' : longDay(_due!)),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text('لمن؟', style: text.titleMedium),
              const SizedBox(height: 8),
              SegmentedButton<bool>(
                key: const Key('homework-target'),
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(value: true, label: Text('الفئة كاملة (${kids.length})')),
                  const ButtonSegment(value: false, label: Text('أطفال محددون')),
                ],
                selected: {_whole},
                onSelectionChanged: (v) => setState(() => _whole = v.first),
              ),
              if (!_whole) ...[
                const SizedBox(height: 8),
                Card(
                  child: Column(
                    children: [
                      for (final k in kids)
                        CheckboxListTile(
                          key: Key('homework-pick-${k.id}'),
                          value: _picked.contains(k.id),
                          title: Text(k.fullName),
                          onChanged: (v) => setState(() => v == true ? _picked.add(k.id) : _picked.remove(k.id)),
                        ),
                    ],
                  ),
                ),
              ],
              if (_error != null) ...[const SizedBox(height: 12), FormError(_error!)],
              const SizedBox(height: 16),
              FilledButton(
                key: const Key('save-homework'),
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const ButtonSpinner()
                    : Text(widget.homework == null ? 'إرسال إلى أولياء الأمور' : 'حفظ التعديل'),
              ),
              if (widget.homework == null) ...[
                const SizedBox(height: 6),
                Text(
                  'يصل إشعار إلى أولياء أمور الأطفال المعنيين، ويظهر الواجب في قسم الواجبات.',
                  style: text.bodySmall?.copyWith(color: RaeedColors.grey),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

// The مشرف العام's side ---------------------------------------------------------------------

/// Every فئة's homework, for the مشرف العام, read only: who gave it, and per child what
/// was marked. Filter by فئة with the chips at the top.
class AllHomeworkScreen extends StatefulWidget {
  const AllHomeworkScreen({super.key});

  @override
  State<AllHomeworkScreen> createState() => _AllHomeworkScreenState();
}

class _AllHomeworkScreenState extends State<AllHomeworkScreen> with _HomeworkLoader {
  String? _group;

  @override
  List<String> get groupIds => [for (final g in InstructorScope.of(context).data.groups) g.id]..sort();

  @override
  Widget build(BuildContext context) {
    final store = InstructorScope.of(context);
    final data = store.data;
    final now = store.now();
    return Scaffold(
      appBar: AppBar(title: const Text('واجبات الفئات')),
      body: RefreshIndicator(
        onRefresh: () async {
          reload();
          await items?.catchError((_) => <Homework>[]);
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  ChoiceChip(
                    key: const Key('homework-filter-all'),
                    label: const Text('كل الفئات'),
                    selected: _group == null,
                    onSelected: (_) => setState(() => _group = null),
                  ),
                  for (final g in data.groups) ...[
                    const SizedBox(width: 6),
                    ChoiceChip(
                      key: Key('homework-filter-${g.id}'),
                      label: Text(g.name),
                      selected: _group == g.id,
                      onSelected: (_) => setState(() => _group = g.id),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 10),
            loaded((all) {
              final shown = [
                for (final h in all)
                  if (_group == null || h.groupId == _group) h,
              ];
              if (shown.isEmpty) return const _Hint('لا واجبات بعد.');
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final h in shown) ...[
                    HomeworkCard(
                      key: Key('homework-${h.id}'),
                      homework: h,
                      now: now,
                      groupName: data.group(h.groupId)?.name,
                      subtitle: progressLabel(h, [for (final k in data.childrenIn(h.groupId)) k.id]),
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute<void>(builder: (_) => HomeworkDetailScreen(homework: h, readOnly: true)),
                        );
                        if (mounted) reload();
                      },
                    ),
                    const SizedBox(height: 8),
                  ],
                ],
              );
            }),
          ],
        ),
      ),
    );
  }
}

/// A child's homework on their profile: each one with what was marked.
class ChildHomework extends StatefulWidget {
  const ChildHomework({super.key, required this.childId, required this.now});

  final String childId;
  final DateTime now;

  @override
  State<ChildHomework> createState() => _ChildHomeworkState();
}

class _ChildHomeworkState extends State<ChildHomework> {
  Future<List<Homework>>? _items;
  bool _all = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _items ??= HomeworkScope.of(context)?.loadForChild(widget.childId);
  }

  @override
  Widget build(BuildContext context) {
    final grey = Theme.of(context).textTheme.bodyMedium?.copyWith(color: RaeedColors.grey);
    if (_items == null) return Text('غير متاح.', style: grey);
    return FutureBuilder<List<Homework>>(
      future: _items,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snap.hasError) {
          final failure = snap.error is SetupError ? (snap.error! as SetupError).failure : SetupFailure.unknown;
          return Text(setupFailureMessage(failure), style: grey);
        }
        final list = snap.data!;
        if (list.isEmpty) return Text('لا واجبات بعد.', style: grey);
        var done = 0, notDone = 0;
        for (final h in list) {
          final m = h.marks[widget.childId];
          if (m == null) continue;
          m.done ? done++ : notDone++;
        }
        final shown = _all ? list : list.take(3).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'تم $done · لم يتم $notDone · لم يُحدَّد ${list.length - done - notDone}',
              key: const Key('child-homework-summary'),
              style: grey,
            ),
            const SizedBox(height: 8),
            for (final h in shown) ...[
              HomeworkCard(
                key: Key('child-homework-${h.id}'),
                homework: h,
                now: widget.now,
                footer: _MarkChip(mark: h.marks[widget.childId]),
              ),
              const SizedBox(height: 8),
            ],
            if (list.length > 3 && !_all)
              TextButton(onPressed: () => setState(() => _all = true), child: Text('عرض الكل (${list.length})')),
          ],
        );
      },
    );
  }
}

class _MarkChip extends StatelessWidget {
  const _MarkChip({required this.mark});

  final HomeworkMark? mark;

  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = switch (mark?.done) {
      true => ('تم', _doneColor, Icons.check_circle),
      false => ('لم يتم', RaeedColors.error, Icons.cancel),
      null => ('لم يُحدَّد بعد', RaeedColors.grey, Icons.radio_button_unchecked),
    };
    return Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 6),
        Text(
          mark == null ? label : '$label · ${mark!.markedAt.day}/${mark!.markedAt.month}',
          style: TextStyle(color: color, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: const TextStyle(color: RaeedColors.grey),
    ),
  );
}
