import 'package:flutter/material.dart';

import '../theme/raeed_theme.dart';
import '../widgets/form_error.dart';
import 'models.dart';
import 'setup_repository.dart';
import 'widgets.dart';

/// The موسم and its terms. Attendance rates are counted per term.
class SeasonsScreen extends StatelessWidget {
  const SeasonsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الموسم والفصول')),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('new-season'),
        heroTag: 'new-season',
        onPressed: () => _editDates(context),
        icon: const Icon(Icons.add),
        label: const Text('موسم جديد'),
      ),
      body: SetupLoadGate(
        builder: (context, data) {
          final text = Theme.of(context).textTheme;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            children: [
              if (data.seasons.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Text('لا يوجد موسم بعد. أضف موسم 2026–2027 بالزر في الأسفل.',
                      textAlign: TextAlign.center, style: TextStyle(color: RaeedColors.grey)),
                ),
              for (final s in data.seasons) ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(children: [
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(s.name, style: text.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                              Text('من ${formatDate(s.startsOn)} إلى ${formatDate(s.endsOn)}',
                                  style: text.bodySmall?.copyWith(color: RaeedColors.grey)),
                            ]),
                          ),
                          IconButton(tooltip: 'تعديل', icon: const Icon(Icons.edit_outlined), onPressed: () => _editDates(context, season: s)),
                        ]),
                        const Divider(),
                        if (s.terms.isEmpty)
                          Text('لا توجد فصول بعد.', style: text.bodySmall?.copyWith(color: RaeedColors.grey)),
                        for (final t in s.terms)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            title: Text(t.name),
                            subtitle: Text('من ${formatDate(t.startsOn)} إلى ${formatDate(t.endsOn)}'),
                            trailing: const Icon(Icons.edit_outlined, size: 20),
                            onTap: () => _editDates(context, season: s, term: t),
                          ),
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: TextButton.icon(
                            key: Key('new-term-${s.id}'),
                            onPressed: () => _editDates(context, season: s, newTerm: true),
                            icon: const Icon(Icons.add),
                            label: const Text('إضافة فصل'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ],
          );
        },
      ),
    );
  }

  Future<void> _editDates(BuildContext context, {Season? season, Term? term, bool newTerm = false}) {
    final isTerm = term != null || newTerm;
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _DatesSheet(
        title: isTerm ? (term == null ? 'فصل جديد' : 'تعديل الفصل') : (season == null ? 'موسم جديد' : 'تعديل الموسم'),
        nameHint: isTerm ? 'الفصل الأول' : 'موسم 2026–2027',
        name: isTerm ? term?.name : season?.name,
        startsOn: isTerm ? term?.startsOn : season?.startsOn,
        endsOn: isTerm ? term?.endsOn : season?.endsOn,
        bounds: isTerm ? (season!.startsOn, season.endsOn) : null,
        onSave: (name, start, end) {
          final store = SetupScope.read(context);
          return isTerm
              ? store.saveTerm(id: term?.id, seasonId: season!.id, name: name, startsOn: start, endsOn: end)
              : store.saveSeason(id: season?.id, name: name, startsOn: start, endsOn: end);
        },
      ),
    );
  }
}

class _DatesSheet extends StatefulWidget {
  const _DatesSheet({
    required this.title,
    required this.nameHint,
    required this.onSave,
    this.name,
    this.startsOn,
    this.endsOn,
    this.bounds,
  });

  final String title;
  final String nameHint;
  final String? name;
  final DateTime? startsOn;
  final DateTime? endsOn;

  /// A term must fall inside its season.
  final (DateTime, DateTime)? bounds;
  final Future<void> Function(String name, DateTime start, DateTime end) onSave;

  @override
  State<_DatesSheet> createState() => _DatesSheetState();
}

class _DatesSheetState extends State<_DatesSheet> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.name);
  late DateTime? _start = widget.startsOn;
  late DateTime? _end = widget.endsOn;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    if (!_end!.isAfter(_start!)) return setState(() => _error = 'تاريخ النهاية يجب أن يكون بعد البداية.');
    final b = widget.bounds;
    if (b != null && (_start!.isBefore(b.$1) || _end!.isAfter(b.$2))) {
      return setState(() => _error = 'الفصل يجب أن يكون داخل تواريخ الموسم.');
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onSave(_name.text.trim(), _start!, _end!);
      if (mounted) Navigator.pop(context);
    } on SetupError catch (e) {
      if (mounted) setState(() => _error = setupFailureMessage(e.failure));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('dates-name'),
                  controller: _name,
                  decoration: InputDecoration(labelText: 'الاسم', hintText: widget.nameHint),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'اكتب الاسم' : null,
                ),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: DateField(label: 'من', value: _start, required: true, onChanged: (d) => setState(() => _start = d))),
                  const SizedBox(width: 10),
                  Expanded(child: DateField(label: 'إلى', value: _end, required: true, onChanged: (d) => setState(() => _end = d))),
                ]),
                if (_error != null) ...[const SizedBox(height: 12), FormError(_error!)],
                const SizedBox(height: 16),
                FilledButton(
                  key: const Key('save-dates'),
                  onPressed: _busy ? null : _save,
                  child: _busy ? const ButtonSpinner() : const Text('حفظ'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
