import 'package:flutter/material.dart';

import '../auth/phone.dart';
import '../profile/child_profile_screen.dart';
import '../theme/raeed_theme.dart';
import '../widgets/form_error.dart';
import 'models.dart';
import 'setup_repository.dart';
import 'staff_screen.dart' show PhoneField;
import 'widgets.dart';

/// Children by فئة, with search. The advisor's الأطفال tab and Setup's children list.
class ChildrenList extends StatefulWidget {
  const ChildrenList({super.key, this.profiles = false});

  /// Tapping a child opens their profile (the الأطفال tab) instead of the edit form.
  final bool profiles;

  @override
  State<ChildrenList> createState() => _ChildrenListState();
}

class _ChildrenListState extends State<ChildrenList> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('new-child'),
        heroTag: 'new-child',
        onPressed: () => openChildForm(context),
        icon: const Icon(Icons.add),
        label: const Text('طفل جديد'),
      ),
      body: SetupLoadGate(
        builder: (context, data) {
          final q = _query.trim();
          bool matches(Child c) =>
              q.isEmpty ||
              c.fullName.contains(q) ||
              c.parentIds.any((p) {
                final parent = data.person(p);
                return parent != null && (parent.fullName.contains(q) || parent.phone.contains(normalizePhone(q) ?? q));
              });
          final sections = <(String, Widget?, List<Child>)>[
            for (final g in data.groups)
              (g.name, GroupLogo.of(g, size: 22), data.childrenIn(g.id).where(matches).toList()),
            ('بدون فئة', null, data.childrenWithoutGroup.where(matches).toList()),
          ].where((s) => s.$3.isNotEmpty).toList();
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            children: [
              TextField(
                key: const Key('children-search'),
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'ابحث باسم الطفل أو ولي الأمر أو الهاتف'),
                onChanged: (v) => setState(() => _query = v),
              ),
              if (data.children.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Text('لا يوجد أطفال بعد. أضف أول طفل بالزر في الأسفل.',
                      textAlign: TextAlign.center, style: TextStyle(color: RaeedColors.grey)),
                ),
              for (final (title, logo, kids) in sections) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 14, bottom: 6),
                  child: Row(children: [
                    if (logo != null) ...[logo, const SizedBox(width: 8)],
                    Text('$title · ${kids.length}',
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(color: RaeedColors.grey)),
                  ]),
                ),
                for (final c in kids) ...[_ChildRow(child: c, data: data, profile: widget.profiles), const SizedBox(height: 8)],
              ],
            ],
          );
        },
      ),
    );
  }
}

class ChildrenScreen extends StatelessWidget {
  const ChildrenScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      Scaffold(appBar: AppBar(title: const Text('الأطفال وأولياء الأمور')), body: const ChildrenList());
}

class _ChildRow extends StatelessWidget {
  const _ChildRow({required this.child, required this.data, this.profile = false});

  final Child child;
  final SetupSnapshot data;
  final bool profile;

  @override
  Widget build(BuildContext context) {
    final parents = [for (final id in child.parentIds) data.person(id)?.fullName].nonNulls.join('، ');
    return SetupRow(
      leading: InitialAvatar(child.fullName),
      title: child.fullName,
      lines: [parents.isEmpty ? 'بدون ولي أمر' : 'ولي الأمر: $parents'],
      trailing: child.consentRecordedAt == null
          ? const Tooltip(message: 'الموافقة غير مسجّلة', child: Icon(Icons.assignment_late_outlined, color: Color(0xFFF06C00)))
          : null,
      onTap: () => profile ? openChildProfile(context, child.id) : openChildForm(context, child: child),
    );
  }
}

Future<void> openChildForm(BuildContext context, {Child? child}) =>
    Navigator.push(context, MaterialPageRoute<void>(builder: (_) => ChildFormScreen(child: child)));

/// Screen 12: the child, their فئة and up to two parents in one form.
class ChildFormScreen extends StatefulWidget {
  const ChildFormScreen({super.key, this.child});

  final Child? child;

  @override
  State<ChildFormScreen> createState() => _ChildFormScreenState();
}

class _NewParent {
  final name = TextEditingController();
  final phone = TextEditingController();

  void dispose() {
    name.dispose();
    phone.dispose();
  }
}

class _ChildFormScreenState extends State<ChildFormScreen> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.child?.fullName);
  late DateTime? _birthDate = widget.child?.birthDate;
  late Gender? _gender = widget.child?.gender;
  late String? _groupId = widget.child?.groupId;
  late final List<String> _existingParents = [...?widget.child?.parentIds];
  final List<_NewParent> _newParents = [];
  late bool _consent = widget.child?.consentRecordedAt != null;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (_existingParents.isEmpty) _newParents.add(_NewParent());
  }

  @override
  void dispose() {
    _name.dispose();
    for (final p in _newParents) {
      p.dispose();
    }
    super.dispose();
  }

  int get _parentCount => _existingParents.length + _newParents.length;

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    final store = SetupScope.read(context);
    final parents = <ParentDraft>[
      for (final id in _existingParents) ParentDraft.existing(id),
      for (final p in _newParents)
        if (p.phone.text.trim().isNotEmpty) _parentDraft(store.data, p),
    ];
    final ids = parents.map((p) => p.personId ?? normalizePhone(p.phone!)).toSet();
    if (parents.isEmpty) return setState(() => _error = 'أضف ولي أمر واحداً على الأقل، لتصله الإشعارات.');
    if (ids.length != parents.length) return setState(() => _error = 'ولي الأمر نفسه مكتوب مرتين.');
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final issued = await store.saveChild(ChildDraft(
        id: widget.child?.id,
        fullName: _name.text.trim(),
        birthDate: _birthDate,
        gender: _gender,
        groupId: _groupId,
        parents: parents,
        consent: _consent,
      ));
      if (!mounted) return;
      setState(() => _busy = false);
      if (issued.isNotEmpty) await showIssuedPasswords(context, issued);
      if (mounted) Navigator.pop(context);
    } on SetupError catch (e) {
      if (mounted) setState(() => _error = setupFailureMessage(e.failure));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// A number that already has an account links to it instead of creating another.
  ParentDraft _parentDraft(SetupSnapshot data, _NewParent p) {
    final n = normalizePhone(p.phone.text);
    final existing = data.people.where((x) => normalizePhone(x.phone) == n).firstOrNull;
    return existing != null
        ? ParentDraft.existing(existing.id)
        : ParentDraft.create(fullName: p.name.text.trim(), phone: p.phone.text);
  }

  /// For brothers and sisters: links a parent who already has an account.
  Future<void> _pickParent(SetupSnapshot data) async {
    final picked = await showModalBottomSheet<Person>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ParentPicker(
        data: data,
        exclude: {..._existingParents, for (final p in _newParents) ?_matchedPerson(data, p.phone.text)?.id},
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      final empty = _newParents.where((p) => p.name.text.trim().isEmpty && p.phone.text.trim().isEmpty).firstOrNull;
      if (empty != null) _newParents.remove(empty..dispose());
      _existingParents.add(picked.id);
      _error = null;
    });
  }

  Future<void> _resetParent(Person parent) async {
    setState(() => _busy = true);
    try {
      final issued = await SetupScope.read(context).resetPassword(parent);
      if (!mounted) return;
      setState(() => _busy = false);
      await showIssuedPasswords(context, [issued]);
    } on SetupError catch (e) {
      if (mounted) setState(() => _error = setupFailureMessage(e.failure));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = SetupScope.of(context).data;
    final text = Theme.of(context).textTheme;
    final consentAt = widget.child?.consentRecordedAt;
    return Scaffold(
      appBar: AppBar(title: Text(widget.child == null ? 'طفل جديد' : 'ملف الطفل')),
      body: SafeArea(
        child: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              TextFormField(
                key: const Key('child-name'),
                controller: _name,
                decoration: const InputDecoration(labelText: 'الاسم الكامل'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'اكتب اسم الطفل' : null,
              ),
              const SizedBox(height: 14),
              DateField(
                label: 'تاريخ الميلاد',
                value: _birthDate,
                firstDate: DateTime(2005),
                lastDate: DateTime.now(),
                onChanged: (d) => setState(() => _birthDate = d),
              ),
              const SizedBox(height: 10),
              GenderField(
                fieldKey: const Key('child-gender'),
                value: _gender,
                onChanged: (g) => setState(() => _gender = g),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String?>(
                key: const Key('child-group'),
                initialValue: _groupId,
                decoration: const InputDecoration(labelText: 'الفئة'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('بدون فئة')),
                  for (final g in data.groups.where((g) => !g.archived || g.id == _groupId))
                    DropdownMenuItem(
                      value: g.id,
                      child: Row(children: [GroupLogo.of(g, size: 24), const SizedBox(width: 8), Text(g.name)]),
                    ),
                ],
                onChanged: (v) => setState(() => _groupId = v),
              ),
              const SectionLabel('أولياء الأمور'),
              for (final id in _existingParents)
                if (data.person(id) case final parent?) ...[
                  _ExistingParent(
                    parent: parent,
                    onRemove: () => setState(() => _existingParents.remove(id)),
                    onReset: _busy ? null : () => _resetParent(parent),
                  ),
                  const SizedBox(height: 8),
                ],
              for (final (i, p) in _newParents.indexed) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: RaeedColors.surfaceAlt, borderRadius: BorderRadius.circular(14)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(children: [
                        Expanded(
                          child: Text(
                            _existingParents.length + i == 0 ? 'ولي الأمر الأول' : 'ولي الأمر الثاني (اختياري)',
                            style: text.labelLarge,
                          ),
                        ),
                        if (_parentCount > 1)
                          IconButton(
                            tooltip: 'حذف',
                            icon: const Icon(Icons.close),
                            onPressed: () => setState(() => _newParents.removeAt(i).dispose()),
                          ),
                      ]),
                      const SizedBox(height: 6),
                      TextFormField(
                        key: Key('parent-name-$i'),
                        controller: p.name,
                        decoration: const InputDecoration(labelText: 'الاسم'),
                        validator: (v) {
                          final match = _matchedPerson(data, p.phone.text);
                          if (match != null) return null;
                          final optional = _existingParents.length + i > 0 && p.phone.text.trim().isEmpty;
                          return (!optional && (v == null || v.trim().isEmpty)) ? 'اكتب اسم ولي الأمر' : null;
                        },
                      ),
                      const SizedBox(height: 8),
                      PhoneField(
                        fieldKey: Key('parent-phone-$i'),
                        controller: p.phone,
                        label: 'الهاتف',
                        required: _existingParents.length + i == 0 || p.name.text.trim().isNotEmpty,
                      ),
                      ListenableBuilder(
                        listenable: p.phone,
                        builder: (context, _) {
                          final match = _matchedPerson(data, p.phone.text);
                          return match == null
                              ? const SizedBox.shrink()
                              : Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Text('هذا الرقم مسجّل باسم ${match.fullName}، سيُربط به الطفل.',
                                      style: text.bodySmall?.copyWith(color: RaeedColors.blue)),
                                );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ],
              Wrap(
                spacing: 4,
                children: [
                  if (_parentCount < 2)
                    TextButton.icon(
                      key: const Key('add-parent'),
                      onPressed: () => setState(() => _newParents.add(_NewParent())),
                      icon: const Icon(Icons.add),
                      label: const Text('إضافة ولي أمر'),
                    ),
                  if (_existingParents.length + _newParents.where((p) => p.phone.text.trim().isNotEmpty).length < 2 &&
                      data.parents.isNotEmpty)
                    TextButton.icon(
                      key: const Key('pick-parent'),
                      onPressed: () => _pickParent(data),
                      icon: const Icon(Icons.family_restroom),
                      label: const Text('اختيار ولي أمر مسجّل'),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Card(
                child: CheckboxListTile(
                  key: const Key('consent'),
                  value: _consent,
                  onChanged: consentAt != null ? null : (v) => setState(() => _consent = v ?? false),
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text('وافق ولي الأمر كتابياً على معالجة بيانات طفله وفق القانون 09-08.'),
                  subtitle: consentAt == null ? null : Text('سُجّلت الموافقة في ${formatDate(consentAt.toLocal())}'),
                ),
              ),
              if (_error != null) ...[const SizedBox(height: 12), FormError(_error!)],
              const SizedBox(height: 20),
              if (_newParents.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text('بعد الحفظ: كلمة مرور مؤقتة لكل ولي أمر جديد لتسليمها له',
                      textAlign: TextAlign.center, style: text.bodySmall?.copyWith(color: RaeedColors.grey)),
                ),
              FilledButton(
                key: const Key('save-child'),
                onPressed: _busy ? null : _save,
                child: _busy ? const ButtonSpinner() : const Text('حفظ الطفل'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Person? _matchedPerson(SetupSnapshot data, String phone) {
    final n = normalizePhone(phone);
    if (n == null) return null;
    return data.people.where((x) => normalizePhone(x.phone) == n).firstOrNull;
  }
}

class _ExistingParent extends StatelessWidget {
  const _ExistingParent({required this.parent, required this.onRemove, required this.onReset});

  final Person parent;
  final VoidCallback onRemove;
  final VoidCallback? onReset;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 4, 8),
        child: Row(
          children: [
            InitialAvatar(parent.fullName),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(parent.fullName, style: text.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                  Text(formatPhone(parent.phone), textDirection: TextDirection.ltr, style: text.bodySmall),
                  if (parent.mustChangePassword)
                    Text('لم يدخل بعد', style: text.bodySmall?.copyWith(color: RaeedColors.grey)),
                ],
              ),
            ),
            PopupMenuButton<String>(
              tooltip: 'خيارات',
              onSelected: (v) => v == 'reset' ? onReset?.call() : onRemove(),
              itemBuilder: (_) => [
                PopupMenuItem(value: 'reset', enabled: onReset != null, child: const Text('إعادة تعيين كلمة المرور')),
                const PopupMenuItem(value: 'remove', child: Text('إزالة من هذا الطفل')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A searchable list of parents who already have an account, with their children.
class _ParentPicker extends StatefulWidget {
  const _ParentPicker({required this.data, required this.exclude});

  final SetupSnapshot data;
  final Set<String> exclude;

  @override
  State<_ParentPicker> createState() => _ParentPickerState();
}

class _ParentPickerState extends State<_ParentPicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final q = _query.trim();
    final phone = normalizePhone(q);
    final parents = [
      for (final p in data.parents)
        if (!widget.exclude.contains(p.id) &&
            (q.isEmpty ||
                p.fullName.contains(q) ||
                p.phone.contains(phone ?? q) ||
                data.childrenOf(p.id).any((c) => c.fullName.contains(q))))
          p,
    ];
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.75,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                key: const Key('parent-search'),
                autofocus: true,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'ابحث باسم ولي الأمر أو هاتفه أو اسم أحد أبنائه',
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            Expanded(
              child: parents.isEmpty
                  ? const Center(child: Text('لا يوجد ولي أمر مطابق.', style: TextStyle(color: RaeedColors.grey)))
                  : ListView(
                      children: [
                        for (final p in parents)
                          ListTile(
                            key: Key('pick-parent-${p.id}'),
                            leading: InitialAvatar(p.fullName),
                            title: Text(p.fullName),
                            subtitle: Text(
                              [
                                '\u2066${formatPhone(p.phone)}\u2069',
                                if (data.childrenOf(p.id).isNotEmpty)
                                  'أبناؤه: ${data.childrenOf(p.id).map((c) => c.fullName).join('، ')}',
                              ].join(' · '),
                            ),
                            onTap: () => Navigator.pop(context, p),
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
