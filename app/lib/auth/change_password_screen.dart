import 'package:flutter/material.dart';

import '../theme/raeed_theme.dart';
import '../widgets/form_error.dart';
import 'auth_repository.dart';
import 'messages.dart';
import 'session_scope.dart';

const minPasswordLength = 8;

/// Screen 2 of the main screens: shown once, after signing in with the temporary
/// password the advisor handed over. Also opened from the account screen, where it
/// closes itself once saved.
class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key, this.fromAccount = false});

  final bool fromAccount;

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _form = GlobalKey<FormState>();
  final _first = TextEditingController();
  final _second = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _first.dispose();
    _second.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await SessionScope.read(context).changePassword(_first.text);
      if (widget.fromAccount && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم تغيير كلمة المرور ✓')));
        Navigator.pop(context);
      }
    } on AuthError catch (e) {
      if (mounted) setState(() => _error = failureMessage(e.failure));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.of(context);
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.fromAccount ? 'تغيير كلمة المرور' : 'إنشاء كلمة المرور'),
        actions: [
          if (!widget.fromAccount)
            TextButton(onPressed: _busy ? null : session.signOut, child: const Text('خروج')),
        ],
      ),
      body: SafeArea(
        child: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            children: [
              if (!widget.fromAccount) ...[
              Text('أول دخول · ${session.profile?.fullName ?? ''}', style: text.bodyMedium?.copyWith(color: RaeedColors.grey)),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Text(
                    'دخلت بكلمة مرور مؤقتة من الأكاديمية. اختر كلمة مرور خاصة بك.',
                    style: text.bodyMedium,
                  ),
                ),
              ),
              ],
              const SizedBox(height: 20),
              TextFormField(
                key: const Key('new-password'),
                controller: _first,
                obscureText: true,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.newPassword],
                decoration: const InputDecoration(labelText: 'كلمة المرور الجديدة'),
                validator: (v) => (v == null || v.length < minPasswordLength)
                    ? 'كلمة المرور قصيرة: $minPasswordLength أحرف على الأقل'
                    : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                key: const Key('repeat-password'),
                controller: _second,
                obscureText: true,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _submit(),
                decoration: const InputDecoration(labelText: 'أعد كتابتها'),
                validator: (v) => v != _first.text ? 'كلمتا المرور غير متطابقتين' : null,
              ),
              const SizedBox(height: 10),
              Text(
                '$minPasswordLength أحرف على الأقل. يبقى حسابك مفتوحاً على هذا الهاتف.',
                style: text.bodySmall?.copyWith(color: RaeedColors.grey),
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                FormError(_error!),
              ],
              const SizedBox(height: 24),
              FilledButton(
                key: const Key('save-password'),
                onPressed: _busy ? null : _submit,
                child: _busy ? const ButtonSpinner() : Text(widget.fromAccount ? 'حفظ' : 'حفظ والمتابعة'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
