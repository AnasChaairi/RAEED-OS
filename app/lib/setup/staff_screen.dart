import 'package:flutter/material.dart';

import '../auth/phone.dart';
import '../auth/session_scope.dart';
import '../roles/app_role.dart';
import '../theme/raeed_theme.dart';
import '../widgets/form_error.dart';
import 'models.dart';
import 'setup_repository.dart';
import 'widgets.dart';

/// Instructors and advisors.
class StaffScreen extends StatelessWidget {
  const StaffScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('المؤطرون والمشرفون')),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('new-staff'),
        heroTag: 'new-staff',
        onPressed: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const StaffFormScreen())),
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('مؤطر جديد'),
      ),
      body: SetupLoadGate(
        builder: (context, data) {
          final advisors = data.staff.where((p) => p.roles.contains(AppRole.advisor)).toList();
          final instructors = data.staff.where((p) => !p.roles.contains(AppRole.advisor)).toList();
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
            children: [
              SectionLabel('المؤطرون (${instructors.length})'),
              if (instructors.isEmpty)
                const Text('لا يوجد مؤطرون بعد.', style: TextStyle(color: RaeedColors.grey)),
              for (final p in instructors) ...[_StaffRow(person: p, data: data), const SizedBox(height: 8)],
              SectionLabel('المشرفون (${advisors.length})'),
              for (final p in advisors) ...[_StaffRow(person: p, data: data), const SizedBox(height: 8)],
            ],
          );
        },
      ),
    );
  }
}

class _StaffRow extends StatelessWidget {
  const _StaffRow({required this.person, required this.data});

  final Person person;
  final SetupSnapshot data;

  @override
  Widget build(BuildContext context) {
    final groups = data.groupsTaughtBy(person.id).map((g) => g.name).join('، ');
    return SetupRow(
      leading: InitialAvatar(person.fullName),
      title: person.fullName,
      lines: [
        [for (final r in AppRole.values) if (person.roles.contains(r)) r.label].join(' · '),
        if (groups.isNotEmpty) groups,
        if (person.mustChangePassword) 'لم يدخل بعد بكلمة مروره الخاصة',
      ],
      onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => StaffFormScreen(person: person))),
    );
  }
}

/// New staff member (name, phone, role, groups), or edit one.
class StaffFormScreen extends StatefulWidget {
  const StaffFormScreen({super.key, this.person});

  final Person? person;

  @override
  State<StaffFormScreen> createState() => _StaffFormScreenState();
}

class _StaffFormScreenState extends State<StaffFormScreen> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.person?.fullName);
  final _phone = TextEditingController();
  late final Set<AppRole> _roles = widget.person == null
      ? {AppRole.instructor}
      : widget.person!.roles.where((r) => r != AppRole.parent).toSet();
  Set<String>? _groups;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    if (_roles.isEmpty) return setState(() => _error = 'اختر دوراً واحداً على الأقل');
    setState(() {
      _busy = true;
      _error = null;
    });
    final store = SetupScope.read(context);
    try {
      if (widget.person == null) {
        final issued = await store.createStaff(
          fullName: _name.text.trim(),
          phone: _phone.text,
          roles: _roles,
          groupIds: _groups?.toList() ?? const [],
        );
        if (!mounted) return;
        setState(() => _busy = false);
        if (issued != null) {
          await showIssuedPasswords(context, [issued]);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('هذا الرقم مسجّل من قبل. أضيف له الدور ويحتفظ بكلمة مروره.')),
          );
        }
      } else {
        await store.updateStaff(
          person: widget.person!,
          fullName: _name.text.trim(),
          roles: _roles,
          groupIds: _groups?.toList() ?? store.data.groupsTaughtBy(widget.person!.id).map((g) => g.id).toList(),
        );
      }
      if (mounted) Navigator.pop(context);
    } on SetupError catch (e) {
      if (mounted) setState(() => _error = setupFailureMessage(e.failure));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reset() async {
    final person = widget.person!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('إعادة تعيين كلمة المرور؟'),
        content: Text('ستتوقف كلمة مرور ${person.fullName} الحالية، ويختار كلمة جديدة عند الدخول.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('إلغاء')),
          FilledButton(key: const Key('confirm-reset'), onPressed: () => Navigator.pop(d, true), child: const Text('إعادة التعيين')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final issued = await SetupScope.read(context).resetPassword(person);
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
    final store = SetupScope.of(context);
    final data = store.data;
    final person = widget.person;
    _groups ??= person == null ? <String>{} : data.groupsTaughtBy(person.id).map((g) => g.id).toSet();
    final isSelf = person != null && person.id == SessionScope.read(context).profile?.id;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text(person == null ? 'مؤطر جديد' : person.fullName)),
      body: SafeArea(
        child: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              TextFormField(
                key: const Key('staff-name'),
                controller: _name,
                decoration: const InputDecoration(labelText: 'الاسم الكامل'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'اكتب الاسم' : null,
              ),
              const SizedBox(height: 14),
              if (person == null)
                PhoneField(fieldKey: const Key('staff-phone'), controller: _phone, label: 'رقم الهاتف')
              else
                InputDecorator(
                  decoration: const InputDecoration(labelText: 'رقم الهاتف'),
                  child: Text(formatPhone(person.phone), textDirection: TextDirection.ltr, textAlign: TextAlign.end),
                ),
              const SectionLabel('الدور'),
              Wrap(
                spacing: 6,
                children: [
                  for (final r in const [AppRole.instructor, AppRole.advisor])
                    FilterChip(
                      key: Key('staff-role-${r.dbName}'),
                      label: Text(r.label),
                      selected: _roles.contains(r),
                      onSelected: (isSelf && r == AppRole.advisor)
                          ? null
                          : (on) => setState(() => on ? _roles.add(r) : _roles.remove(r)),
                    ),
                ],
              ),
              if (person != null && person.roles.contains(AppRole.parent))
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('وهو أيضاً ولي أمر.', style: text.bodySmall?.copyWith(color: RaeedColors.grey)),
                ),
              if (_roles.contains(AppRole.instructor)) ...[
                const SectionLabel('الفئات'),
                if (data.activeGroups.isEmpty)
                  Text('لا توجد فئات بعد.', style: text.bodySmall?.copyWith(color: RaeedColors.grey))
                else
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final g in data.activeGroups)
                        FilterChip(
                          avatar: GroupLogo.of(g, size: 22),
                          label: Text(g.name),
                          selected: _groups!.contains(g.id),
                          onSelected: (on) => setState(() => on ? _groups!.add(g.id) : _groups!.remove(g.id)),
                        ),
                    ],
                  ),
              ],
              if (_error != null) ...[const SizedBox(height: 12), FormError(_error!)],
              const SizedBox(height: 20),
              FilledButton(
                key: const Key('save-staff'),
                onPressed: _busy ? null : _save,
                child: _busy ? const ButtonSpinner() : Text(person == null ? 'إنشاء الحساب' : 'حفظ'),
              ),
              if (person != null) ...[
                const SizedBox(height: 8),
                TextButton.icon(
                  key: const Key('reset-password'),
                  onPressed: _busy ? null : _reset,
                  icon: const Icon(Icons.lock_reset),
                  label: const Text('إعادة تعيين كلمة المرور'),
                ),
              ] else
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'بعد الحفظ تظهر كلمة مرور مؤقتة لتسليمها له.',
                    textAlign: TextAlign.center,
                    style: text.bodySmall?.copyWith(color: RaeedColors.grey),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A Moroccan phone number field, written left to right.
class PhoneField extends StatelessWidget {
  const PhoneField({super.key, required this.controller, required this.label, this.fieldKey, this.required = true});

  final TextEditingController controller;
  final String label;
  final Key? fieldKey;
  final bool required;

  @override
  Widget build(BuildContext context) => TextFormField(
        key: fieldKey,
        controller: controller,
        keyboardType: TextInputType.phone,
        textDirection: TextDirection.ltr,
        decoration: InputDecoration(
          labelText: label,
          hintText: '06 12 34 56 78',
          hintTextDirection: TextDirection.ltr,
          prefixIcon: const Icon(Icons.phone_outlined),
        ),
        validator: (v) {
          if (v == null || v.trim().isEmpty) return required ? 'اكتب رقم الهاتف' : null;
          return normalizePhone(v) == null ? 'رقم الهاتف غير صحيح' : null;
        },
      );
}
