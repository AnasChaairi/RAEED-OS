import 'package:flutter/material.dart';

import '../theme/raeed_theme.dart';
import '../widgets/form_error.dart';
import 'auth_repository.dart';
import 'messages.dart';
import 'phone.dart';
import 'session_scope.dart';

/// Screen 1 of the main screens: phone number and password. Accounts are created by the
/// advisor, so there is no sign-up and no "forgot password" flow.
class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _form = GlobalKey<FormState>();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _showPassword = false;
  String? _error;

  @override
  void dispose() {
    _phone.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await SessionScope.read(context).signIn(phone: _phone.text, password: _password.text);
    } on AuthError catch (e) {
      if (mounted) setState(() => _error = failureMessage(e.failure));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Image.asset('assets/images/raeed-logo.png', height: 140, semanticLabel: 'شعار أكاديمية رائد'),
                    const SizedBox(height: 16),
                    Text('مرحباً بك في رائد', style: text.headlineMedium, textAlign: TextAlign.center),
                    const SizedBox(height: 4),
                    Text(
                      'أدخل رقم هاتفك المسجّل وكلمة المرور',
                      style: text.bodyMedium?.copyWith(color: RaeedColors.grey),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 28),
                    TextFormField(
                      key: const Key('phone'),
                      controller: _phone,
                      keyboardType: TextInputType.phone,
                      textDirection: TextDirection.ltr,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.telephoneNumber],
                      decoration: const InputDecoration(
                        labelText: 'رقم الهاتف',
                        hintText: '06 12 34 56 78',
                        hintTextDirection: TextDirection.ltr,
                        prefixIcon: Icon(Icons.phone_outlined),
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'اكتب رقم هاتفك';
                        if (normalizePhone(v) == null) return failureMessage(AuthFailure.invalidPhone);
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      key: const Key('password'),
                      controller: _password,
                      obscureText: !_showPassword,
                      textInputAction: TextInputAction.done,
                      autofillHints: const [AutofillHints.password],
                      onFieldSubmitted: (_) => _submit(),
                      decoration: InputDecoration(
                        labelText: 'كلمة المرور',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          tooltip: _showPassword ? 'إخفاء كلمة المرور' : 'إظهار كلمة المرور',
                          icon: Icon(_showPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                          onPressed: () => setState(() => _showPassword = !_showPassword),
                        ),
                      ),
                      validator: (v) => (v == null || v.isEmpty) ? 'اكتب كلمة المرور' : null,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'نسيت كلمة المرور؟ تواصل مع المشرف لإعادة تعيينها.',
                      style: text.bodySmall?.copyWith(color: RaeedColors.grey),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      FormError(_error!),
                    ],
                    const SizedBox(height: 24),
                    FilledButton(
                      key: const Key('sign-in'),
                      onPressed: _busy ? null : _submit,
                      child: _busy ? const ButtonSpinner() : const Text('دخول'),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'رقمك غير مسجّل؟ تواصل مع مشرف الأكاديمية.',
                      style: text.bodySmall?.copyWith(color: RaeedColors.grey),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
