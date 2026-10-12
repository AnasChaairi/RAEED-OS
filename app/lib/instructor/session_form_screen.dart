import 'package:flutter/material.dart';

import '../setup/setup_repository.dart';
import '../setup/widgets.dart';
import '../theme/raeed_theme.dart';
import '../widgets/form_error.dart';
import 'models.dart';
import 'sessions_screen.dart';
import 'widgets.dart';

Future<void> openSessionForm(BuildContext context, {Session? session, String? groupId}) => Navigator.push(
  context,
  MaterialPageRoute<void>(
    builder: (_) => SessionFormScreen(session: session, groupId: groupId),
  ),
);

/// New session (once or weekly), or edit one. Parents of the group are notified when it
/// is saved, and the form shows them what they will receive.
class SessionFormScreen extends StatefulWidget {
  const SessionFormScreen({super.key, this.session, this.groupId});

  final Session? session;
  final String? groupId;

  @override
  State<SessionFormScreen> createState() => _SessionFormScreenState();
}

class _SessionFormScreenState extends State<SessionFormScreen> {
  final _form = GlobalKey<FormState>();
  late final SessionDraft? _initial = widget.session?.toDraft();
  late final _title = TextEditingController(text: _initial?.title);
  late final _address = TextEditingController(text: _initial?.address);
  late final _mapUrl = TextEditingController(text: _initial?.mapUrl);
  late final _dropoffPlace = TextEditingController(text: _initial?.dropoffPlace);
  late final _pickupPlace = TextEditingController(text: _initial?.pickupPlace);
  final _materialLabel = TextEditingController();
  final _materialUrl = TextEditingController();

  String? _groupId;
  late DateTime? _date = _initial?.date;
  late int? _start = _initial?.start;
  late int? _end = _initial?.end;
  late SessionPlace _place = _initial?.place ?? SessionPlace.samae;
  late int _floor = _initial?.floor ?? 0;
  late int? _dropoffTime = _initial?.dropoffTime;
  late int? _pickupTime = _initial?.pickupTime;
  bool _weekly = false;
  final Set<int> _days = {};
  DateTime? _until;
  late final List<SessionMaterial> _materials = [...?_initial?.materials];
  String? _materialError;
  bool _busy = false;
  String? _error;

  bool get _editing => widget.session != null;

  @override
  void dispose() {
    for (final c in [_title, _address, _mapUrl, _dropoffPlace, _pickupPlace, _materialLabel, _materialUrl]) {
      c.dispose();
    }
    super.dispose();
  }

  SessionDraft _draft() => SessionDraft(
    groupId: _groupId!,
    title: _title.text.trim(),
    date: _date!,
    start: _start!,
    end: _end!,
    place: _place,
    floor: _floor,
    address: _address.text.trim(),
    mapUrl: _mapUrl.text.trim().isEmpty ? null : _mapUrl.text.trim(),
    dropoffPlace: _dropoffPlace.text.trim().isEmpty ? null : _dropoffPlace.text.trim(),
    dropoffTime: _dropoffTime,
    pickupPlace: _pickupPlace.text.trim(),
    pickupTime: _pickupTime,
    materials: _materials,
  );

  List<DateTime> get _dates =>
      !_weekly ? [?_date] : (_date == null || _until == null ? const [] : seriesDates(_date!, _until!, _days));

  void _addMaterial() {
    final url = _materialUrl.text.trim();
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      return setState(() => _materialError = 'الرابط يبدأ بـ https://');
    }
    final label = _materialLabel.text.trim();
    setState(() {
      _materials.add(SessionMaterial(kind: SessionMaterial.kindOf(url), url: url, label: label.isEmpty ? url : label));
      _materialError = null;
      _materialUrl.clear();
      _materialLabel.clear();
    });
  }

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    if (_weekly && _dates.isEmpty) return setState(() => _error = 'لا توجد أيام بين البداية والنهاية.');
    if (_dates.length > 150) return setState(() => _error = 'سلسلة طويلة جداً. اختر تاريخ نهاية أقرب.');
    var upcoming = false;
    if (_editing && widget.session!.seriesId != null) {
      final choice = await askSeriesScope(context, action: 'تعديل');
      if (choice == null || !mounted) return;
      upcoming = choice;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final store = InstructorScope.read(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (_editing) {
        await store.updateSession(widget.session!, _draft(), upcoming: upcoming);
      } else {
        await store.createSessions(_draft(), _dates, _weekly ? _days : null);
      }
      if (!mounted) return;
      Navigator.pop(context);
      messenger.showSnackBar(const SnackBar(content: Text('حُفظت الحصة ✓')));
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
    _groupId ??= widget.session?.groupId ?? widget.groupId ?? (groups.length == 1 ? groups.single.id : null);
    final text = Theme.of(context).textTheme;
    final group = _groupId == null ? null : data.group(_groupId!);
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 68,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_editing ? 'تعديل الحصة' : 'حصة جديدة'),
            if (group != null)
              Text([group.name, ?group.ageLabel].join(' · '), style: text.bodySmall?.copyWith(color: RaeedColors.grey)),
          ],
        ),
      ),
      body: SafeArea(
        child: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              if (store.offline) ...[
                const OfflineBanner(text: 'لا يوجد إنترنت. إنشاء الحصص وتعديلها يحتاج اتصالاً.'),
                const SizedBox(height: 10),
              ],
              if (!_editing && groups.length > 1) ...[
                DropdownButtonFormField<String>(
                  key: const Key('session-group'),
                  initialValue: _groupId,
                  decoration: const InputDecoration(labelText: 'الفئة'),
                  items: [for (final g in groups) DropdownMenuItem(value: g.id, child: Text(g.name))],
                  onChanged: (v) => setState(() => _groupId = v),
                  validator: (v) => v == null ? 'اختر الفئة' : null,
                ),
                const SizedBox(height: 14),
              ],
              TextFormField(
                key: const Key('session-title'),
                controller: _title,
                decoration: const InputDecoration(labelText: 'عنوان الحصة', hintText: 'حفظ سورة الملك'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'اكتب العنوان' : null,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 14),
              DateField(
                key: const Key('session-date'),
                label: _weekly ? 'أول حصة' : 'التاريخ',
                value: _date,
                required: true,
                firstDate: DateTime(2026),
                onChanged: (d) => setState(() {
                  _date = d;
                  if (_weekly && _days.isEmpty) _days.add(dayOfWeek(d));
                }),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: TimeField(
                      fieldKey: const Key('session-start'),
                      label: 'من',
                      value: _start,
                      required: true,
                      onChanged: (t) => setState(() {
                        final length = _start != null && _end != null ? _end! - _start! : 90;
                        _start = t;
                        _end = (t + length).clamp(0, 24 * 60 - 1);
                      }),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TimeField(
                      fieldKey: const Key('session-end'),
                      label: 'إلى',
                      value: _end,
                      required: true,
                      validator: (t) => t != null && _start != null && t <= _start! ? 'بعد البداية' : null,
                      onChanged: (t) => setState(() => _end = t),
                    ),
                  ),
                ],
              ),
              const SectionLabel('المكان'),
              SegmentedButton<SessionPlace>(
                key: const Key('session-place'),
                segments: const [
                  ButtonSegment(value: SessionPlace.samae, label: Text('جمعية سماء')),
                  ButtonSegment(value: SessionPlace.away, label: Text('خارج المقر')),
                ],
                selected: {_place},
                onSelectionChanged: (v) => setState(() => _place = v.first),
              ),
              const SizedBox(height: 10),
              if (_place == SessionPlace.samae)
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final f in floors.entries)
                      ChoiceChip(
                        key: Key('floor-${f.key}'),
                        label: Text(f.value),
                        selected: _floor == f.key,
                        onSelected: (_) => setState(() => _floor = f.key),
                      ),
                  ],
                )
              else ...[
                TextFormField(
                  key: const Key('session-address'),
                  controller: _address,
                  decoration: const InputDecoration(labelText: 'العنوان', hintText: 'حديقة الجامعة العربية'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'اكتب العنوان' : null,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _mapUrl,
                  keyboardType: TextInputType.url,
                  textDirection: TextDirection.ltr,
                  decoration: const InputDecoration(labelText: 'رابط الخريطة (اختياري)'),
                ),
                const SectionLabel('التسليم: أين ومتى يُحضر الطفل؟'),
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextFormField(
                        controller: _dropoffPlace,
                        decoration: const InputDecoration(labelText: 'المكان'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: TimeField(
                        label: 'الساعة',
                        value: _dropoffTime,
                        onChanged: (t) => setState(() => _dropoffTime = t),
                      ),
                    ),
                  ],
                ),
                const SectionLabel('الاستلام: أين ومتى يُستلم الطفل؟'),
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextFormField(
                        key: const Key('pickup-place'),
                        controller: _pickupPlace,
                        decoration: const InputDecoration(labelText: 'المكان', hintText: 'أمام جمعية سماء'),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'اكتب المكان' : null,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: TimeField(
                        fieldKey: const Key('pickup-time'),
                        label: 'الساعة',
                        value: _pickupTime,
                        required: true,
                        onChanged: (t) => setState(() => _pickupTime = t),
                      ),
                    ),
                  ],
                ),
              ],
              if (!_editing) ...[
                const SectionLabel('التكرار'),
                SegmentedButton<bool>(
                  key: const Key('session-repeat'),
                  segments: const [
                    ButtonSegment(value: false, label: Text('مرة واحدة')),
                    ButtonSegment(value: true, label: Text('أسبوعياً')),
                  ],
                  selected: {_weekly},
                  onSelectionChanged: (v) => setState(() {
                    _weekly = v.first;
                    if (_weekly && _days.isEmpty && _date != null) _days.add(dayOfWeek(_date!));
                  }),
                ),
                if (_weekly) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (var d = 0; d < 7; d++)
                        FilterChip(
                          key: Key('day-$d'),
                          label: Text(weekdayNames[d]),
                          selected: _days.contains(d),
                          onSelected: (on) => setState(() => on ? _days.add(d) : _days.remove(d)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  DateField(
                    key: const Key('session-until'),
                    label: 'ينتهي في',
                    value: _until,
                    required: true,
                    firstDate: _date ?? DateTime(2026),
                    onChanged: (d) => setState(() => _until = d),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _repeatSummary(),
                    key: const Key('repeat-summary'),
                    style: text.bodySmall?.copyWith(color: RaeedColors.blue, fontWeight: FontWeight.w600),
                  ),
                ],
              ],
              const SectionLabel('المواد'),
              for (var i = 0; i < _materials.length; i++)
                MaterialRow(material: _materials[i], onRemove: () => setState(() => _materials.removeAt(i))),
              TextField(
                key: const Key('material-label'),
                controller: _materialLabel,
                decoration: const InputDecoration(labelText: 'اسم المادة', hintText: 'تلاوة سورة الملك'),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('material-url'),
                      controller: _materialUrl,
                      keyboardType: TextInputType.url,
                      textDirection: TextDirection.ltr,
                      decoration: InputDecoration(labelText: 'رابط YouTube أو Drive', errorText: _materialError),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(key: const Key('add-material'), onPressed: _addMaterial, child: const Text('إضافة')),
                ],
              ),
              if (!_editing && _weekly && _materials.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'تُرفق المواد بالحصة الأولى. أضف مواد كل حصة من تفاصيلها.',
                    style: text.bodySmall?.copyWith(color: RaeedColors.grey),
                  ),
                ),
              const SectionLabel('ما سيصل لأولياء الأمور'),
              _Preview(text: _previewText(data), parents: _groupId == null ? 0 : data.parentCount(_groupId!)),
              if (_error != null) ...[const SizedBox(height: 12), FormError(_error!)],
              const SizedBox(height: 20),
              FilledButton(
                key: const Key('save-session'),
                onPressed: _busy ? null : _save,
                child: _busy ? const ButtonSpinner() : const Text('حفظ وإشعار أولياء الأمور'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _repeatSummary() {
    if (_days.isEmpty) return 'اختر يوماً واحداً على الأقل.';
    final names = [for (final d in _days.toList()..sort()) weekdayNames[d]].join(' و');
    if (_until == null) return 'كل $names · اختر تاريخ النهاية.';
    final n = _dates.length;
    return 'كل $names حتى ${formatDate(_until!)} · ${countLabel(n, one: 'حصة واحدة', two: 'حصتان', few: 'حصص', many: 'حصة')}';
  }

  String _previewText(InstructorSnapshot data) {
    final title = _title.text.trim().isEmpty ? 'عنوان الحصة' : _title.text.trim();
    final when = [
      if (_date != null) '${_date!.day.toString().padLeft(2, '0')}/${_date!.month.toString().padLeft(2, '0')}',
      if (_start != null) formatTime(_start!),
    ].join(' · ');
    final verb = _editing ? 'تغيير موعد' : (_weekly ? 'حصص جديدة' : 'حصة جديدة');
    final kid = _groupId == null ? null : data.childrenIn(_groupId!).firstOrNull;
    final name = kid == null ? 'اسم الطفل' : kid.fullName.split(' ').first;
    return '$verb · $name\n$title${when.isEmpty ? '' : ' · $when'}';
  }
}

class _Preview extends StatelessWidget {
  const _Preview({required this.text, required this.parents});

  final String text;
  final int parents;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme;
    return Container(
      key: const Key('notification-preview'),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: RaeedColors.surfaceAlt, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            parents == 0
                ? 'لا يوجد أولياء أمور مسجّلون في هذه الفئة بعد.'
                : 'إشعار · ${countLabel(parents, one: 'ولي أمر واحد', two: 'وليّا أمر', few: 'أولياء أمور', many: 'ولي أمر')}',
            style: style.labelMedium?.copyWith(color: RaeedColors.grey),
          ),
          const SizedBox(height: 4),
          Text(text, style: style.bodyMedium),
          const SizedBox(height: 4),
          Text('يُرسل الإشعار عند الحفظ فقط.', style: style.bodySmall?.copyWith(color: RaeedColors.grey)),
        ],
      ),
    );
  }
}

/// A time shown as 17:00; tapping opens the time picker.
class TimeField extends StatelessWidget {
  const TimeField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.fieldKey,
    this.required = false,
    this.validator,
  });

  final String label;
  final int? value;
  final ValueChanged<int> onChanged;
  final Key? fieldKey;
  final bool required;
  final String? Function(int?)? validator;

  @override
  Widget build(BuildContext context) {
    return FormField<int>(
      key: fieldKey,
      initialValue: value,
      validator: (_) => required && value == null ? 'اختر الساعة' : validator?.call(value),
      builder: (state) => InkWell(
        onTap: () async {
          final picked = await showTimePicker(
            context: context,
            initialTime: value == null
                ? const TimeOfDay(hour: 10, minute: 0)
                : TimeOfDay(hour: value! ~/ 60, minute: value! % 60),
          );
          if (picked != null) {
            final t = picked.hour * 60 + picked.minute;
            onChanged(t);
            state.didChange(t);
          }
        },
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            errorText: state.errorText,
            suffixIcon: const Icon(Icons.schedule),
          ),
          child: Text(
            value == null ? '' : formatTime(value!),
            textDirection: TextDirection.ltr,
            textAlign: TextAlign.end,
          ),
        ),
      ),
    );
  }
}
