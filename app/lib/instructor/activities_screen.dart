import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../setup/models.dart';
import '../setup/setup_repository.dart';
import '../setup/widgets.dart';
import '../theme/raeed_theme.dart';
import '../widgets/form_error.dart';
import '../widgets/select_field.dart';
import 'instructor_repository.dart' show StaffView;
import 'models.dart';
import 'session_form_screen.dart' show TimeField;
import 'sessions_screen.dart' show openSession;
import 'widgets.dart';

/// The colour of each kind of activity: (text and border, background).
(Color, Color) activityColors(ActivityKind k) => switch (k) {
  ActivityKind.camp => (const Color(0xFF1C7A55), const Color(0xFFE3F4EC)),
  ActivityKind.overnight => (const Color(0xFF5B4BC4), const Color(0xFFEEEBFC)),
  ActivityKind.outing => (const Color(0xFFB45F00), const Color(0xFFFFF4DA)),
  ActivityKind.custom => (RaeedColors.blue, RaeedColors.surfaceAlt),
};

Future<void> openActivity(BuildContext context, String id) =>
    Navigator.push(context, MaterialPageRoute<void>(builder: (_) => ActivityDetailScreen(activityId: id)));

Future<void> openActivityForm(BuildContext context, {SpecialActivity? activity, String? groupId}) => Navigator.push(
  context,
  MaterialPageRoute<void>(
    builder: (_) => ActivityFormScreen(activity: activity, groupId: groupId),
  ),
);

/// An activity in a list: bigger than a session card, in its kind's colour, with its
/// emoji. On a day after the first, it says which day of how many.
class ActivityCard extends StatelessWidget {
  const ActivityCard({
    super.key,
    required this.activity,
    required this.groupNames,
    this.day,
    this.onTap,
    this.replaced = 0,
  });

  final SpecialActivity activity;

  /// The names of its فئات that the reader knows, shown under the title.
  final List<String> groupNames;

  /// The day it is listed under, for "اليوم 2 من 3".
  final DateTime? day;
  final VoidCallback? onTap;

  /// How many حصص it replaces, for the staff.
  final int replaced;

  @override
  Widget build(BuildContext context) {
    final a = activity;
    final text = Theme.of(context).textTheme;
    final (fg, bg) = activityColors(a.kind);
    final n = day == null ? 1 : a.dayNumber(day!);
    final muted = text.bodySmall?.copyWith(color: RaeedColors.ink);
    return Card(
      key: Key('activity-${a.id}${day == null ? '' : '-${dbDay(day!)}'}'),
      color: a.cancelled ? null : bg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: a.cancelled ? RaeedColors.line : fg, width: 1.4),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Opacity(
          opacity: a.cancelled ? 0.7 : 1,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                  child: Text(a.kind.emoji, style: const TextStyle(fontSize: 26)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ['نشاط نوعي · ${a.kindLabel}', if (a.dayCount > 1) 'اليوم $n من ${a.dayCount}'].join(' · '),
                        style: text.labelMedium?.copyWith(color: fg, fontWeight: FontWeight.w700),
                      ),
                      Text(
                        a.title,
                        style: text.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          decoration: a.cancelled ? TextDecoration.lineThrough : null,
                        ),
                      ),
                      if (a.cancelled)
                        Text(
                          'ملغى${(a.cancelReason ?? '').isEmpty ? '' : ' · ${a.cancelReason}'}',
                          style: text.bodySmall?.copyWith(color: RaeedColors.error, fontWeight: FontWeight.w600),
                        )
                      else ...[
                        Text(a.whenLabel, style: muted),
                        Text(a.place, style: muted),
                        if (groupNames.isNotEmpty) Text(groupNames.join('، '), style: muted),
                        if (replaced > 0)
                          Text(
                            'بدل ${countLabel(replaced, one: 'حصة واحدة', two: 'حصتين', few: 'حصص', many: 'حصة')}',
                            style: text.bodySmall?.copyWith(color: fg, fontWeight: FontWeight.w600),
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

/// One activity: when, where, its فئات, the حصص it replaces, and its actions.
class ActivityDetailScreen extends StatelessWidget {
  const ActivityDetailScreen({super.key, required this.activityId});

  final String activityId;

  @override
  Widget build(BuildContext context) {
    final store = InstructorScope.of(context);
    final data = store.data;
    final a = data.activity(activityId);
    if (a == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('لم يعد هذا النشاط موجوداً.')),
      );
    }
    final text = Theme.of(context).textTheme;
    final (fg, bg) = activityColors(a.kind);
    final replaced = data.replacedSessions(a);
    final groups = [for (final g in a.groupIds) ?data.group(g)?.name];
    final taken = data.activityAttendanceFor(a.id).length;
    final manage = store.canManageActivity(a);
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 68,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(a.title),
            Text('نشاط نوعي · ${a.kindLabel}', style: text.bodySmall?.copyWith(color: RaeedColors.grey)),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          if (a.cancelled)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: const Color(0xFFFDE8E3), borderRadius: BorderRadius.circular(12)),
              child: Text(
                'هذا النشاط ملغى${(a.cancelReason ?? '').isEmpty ? '' : ': ${a.cancelReason}'}. الحصص المبرمجة في موعدها.',
                style: text.bodyMedium?.copyWith(color: RaeedColors.error, fontWeight: FontWeight.w600),
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
                Row(
                  children: [
                    Text(a.kind.emoji, style: const TextStyle(fontSize: 30)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        a.dayCount == 1 ? dayLabel(a.startDate, store.now()) : '${a.dayCount} أيام',
                        style: text.headlineSmall,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(a.whenLabel, key: const Key('activity-when'), style: text.titleSmall),
                const SizedBox(height: 6),
                Text('المكان: ${a.place}'),
                if ((a.meetingPlace ?? '').isNotEmpty) Text('التجمع والاستلام: ${a.meetingPlace}'),
                if (groups.isNotEmpty) Text('الفئات: ${groups.join('، ')}', key: const Key('activity-groups')),
                if ((a.mapUrl ?? '').isNotEmpty)
                  TextButton.icon(
                    onPressed: () => launchUrl(Uri.parse(a.mapUrl!), mode: LaunchMode.externalApplication),
                    icon: const Icon(Icons.map_outlined),
                    label: const Text('فتح الخريطة'),
                  ),
              ],
            ),
          ),
          if ((a.details ?? '').isNotEmpty) ...[
            const SectionLabel('تفاصيل لأولياء الأمور'),
            Card(
              child: Padding(padding: const EdgeInsets.all(12), child: Text(a.details!)),
            ),
          ],
          if (!a.cancelled && replaced.isNotEmpty) ...[
            SectionLabel(
              'يعوّض ${countLabel(replaced.length, one: 'حصة واحدة', two: 'حصتين', few: 'حصص', many: 'حصة')}',
            ),
            Text(
              'هذه الحصص ملغاة بسبب النشاط: لا يُسجَّل حضورها ولا يُحسب غياب للمؤطرين. تعود تلقائياً إن أُلغي النشاط أو تغيّر موعده.',
              style: text.bodySmall?.copyWith(color: RaeedColors.grey),
            ),
            const SizedBox(height: 6),
            for (final s in replaced)
              Card(
                key: Key('replaced-${s.id}'),
                child: ListTile(
                  dense: true,
                  leading: const Icon(Icons.event_busy_outlined, color: RaeedColors.error),
                  title: Text(
                    '${data.group(s.groupId)?.name ?? ''} · ${s.title}',
                    style: const TextStyle(decoration: TextDecoration.lineThrough),
                  ),
                  subtitle: Text('${longDay(s.date)} · ${s.timeLabel}'),
                  onTap: () => openSession(context, s.id),
                ),
              ),
          ],
          const SizedBox(height: 16),
          if (store.canRecordActivity(a))
            FilledButton.icon(
              key: const Key('activity-attendance'),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(builder: (_) => ActivityAttendanceScreen(activityId: a.id)),
              ),
              icon: const Icon(Icons.fact_check_outlined),
              label: Text(taken > 0 ? 'تعديل الحضور ($taken)' : 'تسجيل الحضور'),
            ),
          if (manage && !a.cancelled) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const Key('edit-activity'),
              onPressed: () => openActivityForm(context, activity: a),
              icon: const Icon(Icons.edit_outlined),
              label: const Text('تعديل النشاط'),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              key: const Key('cancel-activity'),
              style: TextButton.styleFrom(foregroundColor: RaeedColors.error),
              onPressed: () => _cancel(context, a),
              icon: const Icon(Icons.event_busy_outlined),
              label: const Text('إلغاء النشاط'),
            ),
          ],
          if (manage) ...[
            const SizedBox(height: 4),
            TextButton.icon(
              key: const Key('delete-activity'),
              style: TextButton.styleFrom(foregroundColor: RaeedColors.error),
              onPressed: () => _delete(context, a),
              icon: const Icon(Icons.delete_outline),
              label: const Text('حذف النشاط'),
            ),
          ],
          if (!manage && store.schedules)
            Text(
              'خطّط المشرف العام هذا النشاط لعدة فئات، فهو من يعدّله.',
              textAlign: TextAlign.center,
              style: text.bodySmall?.copyWith(color: RaeedColors.grey),
            ),
        ],
      ),
    );
  }

  Future<void> _cancel(BuildContext context, SpecialActivity a) async {
    final reason = await showDialog<String>(context: context, builder: (_) => const _CancelActivityDialog());
    if (reason == null || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await InstructorScope.read(context).cancelActivity(a, reason);
      messenger.showSnackBar(
        const SnackBar(content: Text('أُلغي النشاط وعادت الحصص إلى موعدها. سيُشعَر أولياء الأمور.')),
      );
    } on SetupError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(setupFailureMessage(e.failure))));
    }
  }

  Future<void> _delete(BuildContext context, SpecialActivity a) async {
    final ok = await confirmDeletion(
      context,
      title: 'حذف النشاط؟',
      message: 'يُحذف نهائياً مع حضوره المسجّل، وتعود الحصص إلى موعدها. لا يصل إشعار لأولياء الأمور، فإن كانوا ينتظرونه فالأفضل إلغاؤه.',
    );
    if (!ok || !context.mounted) return;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await InstructorScope.read(context).deleteActivity(a);
      navigator.pop();
      messenger.showSnackBar(const SnackBar(content: Text('حُذف النشاط.')));
    } on SetupError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(setupFailureMessage(e.failure))));
    }
  }
}

class _CancelActivityDialog extends StatefulWidget {
  const _CancelActivityDialog();

  @override
  State<_CancelActivityDialog> createState() => _CancelActivityDialogState();
}

class _CancelActivityDialogState extends State<_CancelActivityDialog> {
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('إلغاء النشاط؟'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('يصل إشعار لأولياء أمور الفئات ومؤطريها، وتعود الحصص المبرمجة في هذه الفترة.'),
          const SizedBox(height: 10),
          TextField(
            key: const Key('cancel-activity-reason'),
            controller: _reason,
            decoration: const InputDecoration(labelText: 'السبب (اختياري)', hintText: 'مثلاً: أحوال الطقس'),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('رجوع')),
        FilledButton(
          key: const Key('confirm-cancel-activity'),
          style: FilledButton.styleFrom(backgroundColor: RaeedColors.error),
          onPressed: () => Navigator.pop(context, _reason.text.trim()),
          child: const Text('إلغاء النشاط'),
        ),
      ],
    );
  }
}

/// New activity, or edit one. Shows the حصص it will replace before saving, and what the
/// parents will receive.
class ActivityFormScreen extends StatefulWidget {
  const ActivityFormScreen({super.key, this.activity, this.groupId});

  final SpecialActivity? activity;
  final String? groupId;

  @override
  State<ActivityFormScreen> createState() => _ActivityFormScreenState();
}

class _ActivityFormScreenState extends State<ActivityFormScreen> {
  final _form = GlobalKey<FormState>();
  late final SpecialActivity? _initial = widget.activity;
  late ActivityKind _kind = _initial?.kind ?? ActivityKind.outing;
  late final _customLabel = TextEditingController(text: _initial?.customLabel);
  late final _title = TextEditingController(text: _initial?.title);
  late final _place = TextEditingController(text: _initial?.place);
  late final _mapUrl = TextEditingController(text: _initial?.mapUrl);
  late final _meetingPlace = TextEditingController(text: _initial?.meetingPlace);
  late final _details = TextEditingController(text: _initial?.details);
  late final Set<String> _groups = {...?_initial?.groupIds, ?widget.groupId};
  late DateTime? _startDate = _initial?.startDate;
  late int? _start = _initial?.start;
  late DateTime? _endDate = _initial?.endDate;
  late int? _end = _initial?.end;
  bool _busy = false;
  String? _error;
  bool _pickedDefaultGroup = false;

  bool get _editing => widget.activity != null;

  @override
  void dispose() {
    for (final c in [_customLabel, _title, _place, _mapUrl, _meetingPlace, _details]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _text(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();

  /// The activity as typed, once its dates and times are chosen.
  SpecialActivity? _draft() {
    if (_startDate == null || _start == null || _endDate == null || _end == null) return null;
    return SpecialActivity(
      id: _initial?.id ?? '',
      kind: _kind,
      customLabel: _kind == ActivityKind.custom ? _text(_customLabel) : null,
      title: _title.text.trim(),
      place: _place.text.trim(),
      mapUrl: _text(_mapUrl),
      meetingPlace: _text(_meetingPlace),
      details: _text(_details),
      startDate: _startDate!,
      start: _start!,
      endDate: _endDate!,
      end: _end!,
      groupIds: _groups.toList(),
    );
  }

  Future<void> _save() async {
    if (_busy) return;
    final noGroup = _groups.isEmpty;
    setState(() => _error = noGroup ? 'اختر فئة واحدة على الأقل.' : null);
    if (!_form.currentState!.validate() || noGroup) return;
    final draft = _draft()!;
    if (!draft.endsAt.isAfter(draft.startsAt)) return setState(() => _error = 'النهاية بعد البداية.');
    setState(() {
      _busy = true;
      _error = null;
    });
    final store = InstructorScope.read(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (_editing) {
        await store.updateActivity(draft);
      } else {
        await store.createActivity(draft);
      }
      if (!mounted) return;
      Navigator.pop(context);
      messenger.showSnackBar(const SnackBar(content: Text('حُفظ النشاط ✓')));
    } on SetupError catch (e) {
      if (mounted) setState(() => _error = setupFailureMessage(e.failure));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = InstructorScope.of(context);
    final data = store.data;
    final groups = data.groups;
    if (!_pickedDefaultGroup) {
      _pickedDefaultGroup = true;
      if (_groups.isEmpty && groups.length == 1) _groups.add(groups.single.id);
    }
    final text = Theme.of(context).textTheme;
    final draft = _draft();
    final replaced = draft == null
        ? const <Session>[]
        : [
            for (final s in data.sessions)
              if (!s.cancelled && draft.replaces(s)) s,
          ];
    final parents = {
      for (final c in data.children)
        if (_groups.contains(c.groupId)) ...c.parents.map((p) => p.id),
    }.length;
    return Scaffold(
      appBar: AppBar(title: Text(_editing ? 'تعديل النشاط' : 'نشاط نوعي جديد')),
      body: SafeArea(
        child: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              if (store.offline) ...[
                const OfflineBanner(text: 'لا يوجد إنترنت. إنشاء الأنشطة وتعديلها يحتاج اتصالاً.'),
                const SizedBox(height: 10),
              ],
              Text('النوع', style: text.labelLarge),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final k in ActivityKind.values)
                    ChoiceChip(
                      key: Key('activity-kind-${k.name}'),
                      label: Text('${k.emoji} ${k.label}'),
                      selected: _kind == k,
                      onSelected: (_) => setState(() => _kind = k),
                    ),
                ],
              ),
              if (_kind == ActivityKind.custom) ...[
                const SizedBox(height: 10),
                TextFormField(
                  key: const Key('activity-custom-label'),
                  controller: _customLabel,
                  decoration: const InputDecoration(labelText: 'اسم النوع', hintText: 'مثلاً: زيارة، مسابقة، حفل'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'اكتب اسم النوع' : null,
                ),
              ],
              const SizedBox(height: 14),
              TextFormField(
                key: const Key('activity-title'),
                controller: _title,
                decoration: const InputDecoration(labelText: 'العنوان', hintText: 'مخيم الربيع'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'اكتب العنوان' : null,
              ),
              const SectionLabel('الفئات'),
              if (groups.isEmpty)
                Text('لا فئات بعد.', style: text.bodySmall?.copyWith(color: RaeedColors.grey))
              else
                MultiSelectField<String>(
                  title: 'الفئات',
                  searchHint: 'ابحث باسم الفئة',
                  options: [for (final g in groups) SelectOption(g.id, g.name, key: Key('activity-group-${g.id}'))],
                  selected: _groups,
                  onChanged: (id, on) => setState(() => on ? _groups.add(id) : _groups.remove(id)),
                ),
              if (store.view == StaffView.supervising)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'تظهر هنا الفئات التي تشرف عليها فقط.',
                    style: text.bodySmall?.copyWith(color: RaeedColors.grey),
                  ),
                ),
              const SizedBox(height: 14),
              TextFormField(
                key: const Key('activity-place'),
                controller: _place,
                decoration: const InputDecoration(labelText: 'المكان', hintText: 'غابة المعمورة'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'اكتب المكان' : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _mapUrl,
                keyboardType: TextInputType.url,
                textDirection: TextDirection.ltr,
                decoration: const InputDecoration(labelText: 'رابط الخريطة (اختياري)'),
              ),
              const SizedBox(height: 10),
              TextFormField(
                key: const Key('activity-meeting'),
                controller: _meetingPlace,
                decoration: const InputDecoration(
                  labelText: 'مكان التجمع والاستلام (اختياري)',
                  hintText: 'أمام جمعية سماء',
                ),
              ),
              const SectionLabel('البداية'),
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: DateField(
                      key: const Key('activity-start-date'),
                      label: 'التاريخ',
                      value: _startDate,
                      required: true,
                      upcoming: true,
                      firstDate: DateTime(2026),
                      onChanged: (d) => setState(() {
                        _startDate = d;
                        if (_endDate == null || _endDate!.isBefore(d)) _endDate = d;
                      }),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: TimeField(
                      fieldKey: const Key('activity-start-time'),
                      label: 'الساعة',
                      value: _start,
                      required: true,
                      onChanged: (t) => setState(() {
                        _start = t;
                        _end ??= (t + 180).clamp(0, 24 * 60 - 1);
                      }),
                    ),
                  ),
                ],
              ),
              const SectionLabel('النهاية'),
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: DateField(
                      key: const Key('activity-end-date'),
                      label: 'التاريخ',
                      value: _endDate,
                      required: true,
                      upcoming: true,
                      firstDate: _startDate ?? DateTime(2026),
                      onChanged: (d) => setState(() => _endDate = d),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: TimeField(
                      fieldKey: const Key('activity-end-time'),
                      label: 'الساعة',
                      value: _end,
                      required: true,
                      validator: (_) => draft != null && !draft.endsAt.isAfter(draft.startsAt) ? 'بعد البداية' : null,
                      onChanged: (t) => setState(() => _end = t),
                    ),
                  ),
                ],
              ),
              if (draft != null && draft.dayCount > 1)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '${draft.dayCount} أيام · ${draft.whenLabel}',
                    style: text.bodySmall?.copyWith(color: RaeedColors.blue, fontWeight: FontWeight.w600),
                  ),
                ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _details,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'تفاصيل لأولياء الأمور (اختياري)',
                  hintText: 'ما يحضره الطفل، التكلفة، اللباس...',
                ),
              ),
              const SectionLabel('الحصص التي سيُلغيها'),
              _Conflicts(sessions: replaced, data: data, ready: draft != null && _groups.isNotEmpty),
              const SectionLabel('ما سيصل لأولياء الأمور'),
              Container(
                key: const Key('activity-preview'),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: RaeedColors.surfaceAlt, borderRadius: BorderRadius.circular(12)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      parents == 0
                          ? 'لا يوجد أولياء أمور مسجّلون في هذه الفئات بعد.'
                          : 'إشعار · ${countLabel(parents, one: 'ولي أمر واحد', two: 'وليّا أمر', few: 'أولياء أمور', many: 'ولي أمر')} · وتذكير قبل يوم',
                      style: text.labelMedium?.copyWith(color: RaeedColors.grey),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_editing ? 'تغيير نشاط' : 'نشاط جديد'} · اسم الطفل\n'
                      '${_kind == ActivityKind.custom ? (_text(_customLabel) ?? 'النوع') : _kind.label}: '
                      '${_text(_title) ?? 'العنوان'}${draft == null ? '' : ' · ${draft.whenLabel}'}',
                      style: text.bodyMedium,
                    ),
                  ],
                ),
              ),
              if (_error != null) ...[const SizedBox(height: 12), FormError(_error!)],
              const SizedBox(height: 20),
              FilledButton(
                key: const Key('save-activity'),
                onPressed: _busy ? null : _save,
                child: _busy ? const ButtonSpinner() : const Text('حفظ وإشعار أولياء الأمور'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The حصص the activity being typed will replace.
class _Conflicts extends StatelessWidget {
  const _Conflicts({required this.sessions, required this.data, required this.ready});

  final List<Session> sessions;
  final InstructorSnapshot data;
  final bool ready;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    if (!ready) {
      return Text(
        'اختر الفئات والتاريخ لترى الحصص التي يعوّضها النشاط.',
        style: text.bodySmall?.copyWith(color: RaeedColors.grey),
      );
    }
    if (sessions.isEmpty) {
      return Text(
        'لا حصص مبرمجة في هذه الفترة.',
        key: const Key('no-conflicts'),
        style: text.bodySmall?.copyWith(color: RaeedColors.grey),
      );
    }
    return Container(
      key: const Key('activity-conflicts'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: RaeedColors.starSoft, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'للنشاط الأولوية: ستظهر ${countLabel(sessions.length, one: 'حصة واحدة', two: 'حصتان', few: 'حصص', many: 'حصة')} ملغاة بسببه',
            style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700, color: const Color(0xFF8A4B00)),
          ),
          for (final s in sessions)
            Text(
              '• ${data.group(s.groupId)?.name ?? ''} · ${s.title} · ${longDay(s.date)} ${formatTime(s.start)}',
              style: text.bodySmall,
            ),
          const SizedBox(height: 4),
          Text(
            'لا يُسجَّل حضورها ولا يُحسب غياب للمؤطرين، وتعود إن أُلغي النشاط.',
            style: text.bodySmall?.copyWith(color: RaeedColors.grey),
          ),
        ],
      ),
    );
  }
}

/// The attendance of an activity, for the children of the reader's groups. Everyone starts
/// as present. Sent at once: it needs a connection.
class ActivityAttendanceScreen extends StatefulWidget {
  const ActivityAttendanceScreen({super.key, required this.activityId});

  final String activityId;

  @override
  State<ActivityAttendanceScreen> createState() => _ActivityAttendanceScreenState();
}

class _ActivityAttendanceScreenState extends State<ActivityAttendanceScreen> {
  Map<String, AttendanceStatus>? _statuses;
  bool _busy = false;
  String? _error;

  Future<void> _save(SpecialActivity a) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await InstructorScope.read(context).saveActivityAttendance(a, _statuses!);
      navigator.pop();
      messenger.showSnackBar(const SnackBar(content: Text('حُفظ حضور النشاط ✓')));
    } on SetupError catch (e) {
      if (mounted) setState(() => _error = setupFailureMessage(e.failure));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = InstructorScope.of(context);
    final data = store.data;
    final a = data.activity(widget.activityId);
    if (a == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('لم يعد هذا النشاط موجوداً.')),
      );
    }
    final kids = data.childrenOf(a);
    final existing = data.activityAttendanceFor(a.id);
    final statuses = _statuses ??= {for (final c in kids) c.id: existing[c.id] ?? AttendanceStatus.present};
    final text = Theme.of(context).textTheme;
    final groupsShown = a.groupIds.where((g) => data.group(g) != null).length > 1;
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 68,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('الحضور · ${a.title}'),
            Text(a.whenLabel, style: text.bodySmall?.copyWith(color: RaeedColors.grey)),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          if (store.offline) ...[
            const OfflineBanner(text: 'لا يوجد إنترنت. حضور الأنشطة يحتاج اتصالاً ليُحفظ.'),
            const SizedBox(height: 8),
          ],
          Text(
            existing.isEmpty ? 'الجميع حاضر مبدئياً. غيّر حالة الغائبين فقط.' : 'سُجّل الحضور من قبل. يمكنك تعديله.',
            style: text.bodySmall?.copyWith(color: RaeedColors.grey),
          ),
          const SizedBox(height: 8),
          for (final c in kids)
            Card(
              key: Key('activity-kid-${c.id}'),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      [c.fullName, if (groupsShown) ?data.group(c.groupId)?.name].join(' · '),
                      style: text.titleSmall,
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final st in AttendanceStatus.values)
                          ChoiceChip(
                            key: Key('activity-status-${c.id}-${st.name}'),
                            label: Text(st.label),
                            selected: statuses[c.id] == st,
                            selectedColor: statusColors(st).$2,
                            labelStyle: TextStyle(
                              color: statuses[c.id] == st ? statusColors(st).$1 : null,
                              fontWeight: statuses[c.id] == st ? FontWeight.w700 : null,
                            ),
                            onSelected: (_) => setState(() => statuses[c.id] = st),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          if (kids.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text('لا أطفال في فئات هذا النشاط.', textAlign: TextAlign.center),
            ),
          if (_error != null) ...[const SizedBox(height: 12), FormError(_error!)],
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('save-activity-attendance'),
            onPressed: _busy || kids.isEmpty ? null : () => _save(a),
            child: _busy ? const ButtonSpinner() : const Text('حفظ الحضور'),
          ),
        ],
      ),
    );
  }
}

/// The names of [a]'s groups that [groups] knows.
List<String> activityGroupNames(SpecialActivity a, List<Group> groups) => [
  for (final id in a.groupIds) ?groups.where((g) => g.id == id).firstOrNull?.name,
];
