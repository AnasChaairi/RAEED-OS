import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../theme/raeed_theme.dart';
import '../widgets/form_error.dart';
import 'models.dart';
import 'setup_repository.dart';
import 'widgets.dart';

/// The list of فئات, used as the advisor's الفئات tab and from Setup.
class GroupsList extends StatelessWidget {
  const GroupsList({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('new-group'),
        heroTag: 'new-group',
        onPressed: () => openGroupForm(context),
        icon: const Icon(Icons.add),
        label: const Text('فئة جديدة'),
      ),
      body: SetupLoadGate(
        builder: (context, data) {
          final active = data.activeGroups;
          final archived = data.groups.where((g) => g.archived).toList();
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            children: [
              if (data.groups.isEmpty)
                const _Empty(text: 'لا توجد فئات بعد. أضف أول فئة بالزر في الأسفل.'),
              for (final g in active) ...[_GroupRow(group: g, data: data), const SizedBox(height: 8)],
              if (archived.isNotEmpty) ...[
                const SectionLabel('فئات مؤرشفة'),
                for (final g in archived) ...[_GroupRow(group: g, data: data), const SizedBox(height: 8)],
              ],
            ],
          );
        },
      ),
    );
  }
}

class GroupsScreen extends StatelessWidget {
  const GroupsScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('الفئات')), body: const GroupsList());
}

class _GroupRow extends StatelessWidget {
  const _GroupRow({required this.group, required this.data});

  final Group group;
  final SetupSnapshot data;

  @override
  Widget build(BuildContext context) {
    final names = [for (final id in group.instructorIds) data.person(id)?.fullName].nonNulls.join('، ');
    final count = data.childrenIn(group.id).length;
    return SetupRow(
      leading: GroupLogo.of(group),
      title: group.name,
      lines: [
        [?group.ageLabel, countLabel(count, one: 'طفل واحد', two: 'طفلان', few: 'أطفال', many: 'طفلاً')].join(' · '),
        names.isEmpty ? 'بدون مؤطر' : 'المؤطرون: $names',
      ],
      onTap: () => openGroupForm(context, group: group),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Text(text, textAlign: TextAlign.center, style: const TextStyle(color: RaeedColors.grey)),
      );
}

/// Lets the advisor choose a logo from the phone's photos, scaled down for upload.
/// Replaced in tests.
@visibleForTesting
Future<Uint8List?> Function() pickGroupLogo = () async {
  final file = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 512, maxHeight: 512, imageQuality: 85);
  return file?.readAsBytes();
};

Future<void> openGroupForm(BuildContext context, {Group? group}) =>
    Navigator.push(context, MaterialPageRoute<void>(builder: (_) => GroupFormScreen(group: group)));

/// Screen 11: new or edit a فئة.
class GroupFormScreen extends StatefulWidget {
  const GroupFormScreen({super.key, this.group});

  final Group? group;

  @override
  State<GroupFormScreen> createState() => _GroupFormScreenState();
}

class _GroupFormScreenState extends State<GroupFormScreen> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.group?.name);
  late final _letter = TextEditingController(text: widget.group?.logoLetter);
  late final _ageMin = TextEditingController(text: widget.group?.ageMin?.toString());
  late final _ageMax = TextEditingController(text: widget.group?.ageMax?.toString());
  late int _color = widget.group?.logoColor ?? 1;
  late bool _archived = widget.group?.archived ?? false;
  late final Set<String> _instructors = {...?widget.group?.instructorIds};
  bool _letterEdited = false;
  Uint8List? _newLogo;
  bool _removeLogo = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _letterEdited = widget.group != null;
    _name.addListener(() {
      if (!_letterEdited) setState(() => _letter.text = suggestLogoLetter(_name.text));
    });
  }

  @override
  void dispose() {
    for (final c in [_name, _letter, _ageMin, _ageMax]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await SetupScope.read(context).saveGroup(GroupDraft(
        id: widget.group?.id,
        name: _name.text.trim(),
        logoLetter: _letter.text.trim(),
        logoColor: _color,
        newLogo: _newLogo,
        removeLogo: _removeLogo,
        ageMin: int.tryParse(_ageMin.text),
        ageMax: int.tryParse(_ageMax.text),
        archived: _archived,
        instructorIds: _instructors.toList(),
      ));
      if (mounted) Navigator.pop(context);
    } on SetupError catch (e) {
      if (mounted) setState(() => _error = setupFailureMessage(e.failure));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickLogo() async {
    final Uint8List? bytes;
    try {
      bytes = await pickGroupLogo();
    } catch (_) {
      if (mounted) setState(() => _error = 'تعذّر فتح الصور. تحقّق من إذن الوصول إلى الصور.');
      return;
    }
    if (bytes == null || !mounted) return;
    if (bytes.length > 1024 * 1024) return setState(() => _error = 'الصورة كبيرة جداً. اختر صورة أصغر.');
    setState(() {
      _newLogo = bytes;
      _removeLogo = false;
      _error = null;
    });
  }

  ImageProvider? get _logoImage {
    if (_newLogo != null) return MemoryImage(_newLogo!);
    return _removeLogo ? null : groupLogoImage(widget.group?.logoPath);
  }

  String? _age(String? v) {
    if (v == null || v.isEmpty) return null;
    final n = int.tryParse(v);
    if (n == null || n < 3 || n > 20) return 'بين 3 و 20';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final data = SetupScope.of(context).data;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text(widget.group == null ? 'فئة جديدة' : 'تعديل الفئة')),
      body: SafeArea(
        child: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              TextFormField(
                key: const Key('group-name'),
                controller: _name,
                decoration: const InputDecoration(labelText: 'اسم الفئة', hintText: 'فئة النجوم'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'اكتب اسم الفئة' : null,
              ),
              const SectionLabel('الشعار'),
              Row(
                children: [
                  GroupLogo(
                    key: const Key('group-logo-preview'),
                    letter: _letter.text.isEmpty ? '؟' : _letter.text,
                    color: _color,
                    size: 56,
                    image: _logoImage,
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 96,
                    child: TextFormField(
                      key: const Key('group-letter'),
                      controller: _letter,
                      maxLength: 2,
                      decoration: const InputDecoration(labelText: 'الحرف', counterText: ''),
                      onChanged: (_) => setState(() => _letterEdited = true),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'حرف واحد' : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton.icon(
                    key: const Key('pick-logo'),
                    onPressed: _busy ? null : _pickLogo,
                    icon: const Icon(Icons.image_outlined),
                    label: Text(_logoImage == null ? 'رفع صورة الشعار' : 'تغيير الصورة'),
                  ),
                  if (_logoImage != null)
                    TextButton(
                      key: const Key('remove-logo'),
                      onPressed: _busy
                          ? null
                          : () => setState(() {
                                _newLogo = null;
                                _removeLogo = true;
                              }),
                      child: const Text('إزالة الصورة'),
                    ),
                ],
              ),
              Text(
                'الحرف واللون يظهران عندما لا توجد صورة، أو قبل أن تُحمَّل.',
                style: text.bodySmall?.copyWith(color: RaeedColors.grey),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var i = 1; i <= groupLogoColors.length; i++)
                    Semantics(
                      selected: i == _color,
                      label: 'اللون $i',
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => setState(() => _color = i),
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: i == _color ? RaeedColors.ink : Colors.transparent, width: 2),
                          ),
                          child: GroupLogo(letter: '', color: i, size: 40),
                        ),
                      ),
                    ),
                ],
              ),
              const SectionLabel('السن'),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      key: const Key('age-min'),
                      controller: _ageMin,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'من سن'),
                      validator: _age,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextFormField(
                      key: const Key('age-max'),
                      controller: _ageMax,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'إلى سن'),
                      validator: (v) {
                        final own = _age(v);
                        if (own != null) return own;
                        final lo = int.tryParse(_ageMin.text), hi = int.tryParse(v ?? '');
                        return lo != null && hi != null && hi < lo ? 'أصغر من البداية' : null;
                      },
                    ),
                  ),
                ],
              ),
              const SectionLabel('المؤطرون'),
              if (data.instructors.isEmpty)
                Text('لا يوجد مؤطرون بعد. أضفهم من «المؤطرون والمشرفون» في الإعدادات.',
                    style: text.bodySmall?.copyWith(color: RaeedColors.grey))
              else
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final p in data.instructors)
                      FilterChip(
                        label: Text(p.fullName),
                        selected: _instructors.contains(p.id),
                        onSelected: (on) => setState(() => on ? _instructors.add(p.id) : _instructors.remove(p.id)),
                      ),
                  ],
                ),
              if (widget.group != null) ...[
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('أرشفة الفئة'),
                  subtitle: const Text('تختفي من القوائم وتبقى في السجلات'),
                  value: _archived,
                  onChanged: (v) => setState(() => _archived = v),
                ),
              ],
              if (_error != null) ...[const SizedBox(height: 12), FormError(_error!)],
              const SizedBox(height: 20),
              FilledButton(
                key: const Key('save-group'),
                onPressed: _busy ? null : _save,
                child: _busy ? const ButtonSpinner() : const Text('حفظ الفئة'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The first letter of the name, skipping a leading «فئة».
String suggestLogoLetter(String name) {
  final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return '';
  final word = words.length > 1 && words.first == 'فئة' ? words[1] : words.first;
  final stripped = word.startsWith('ال') && word.length > 2 ? word.substring(2) : word;
  return stripped.characters.first;
}
