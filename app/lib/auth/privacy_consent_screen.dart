import 'package:flutter/material.dart';

import '../setup/widgets.dart' show formatDate;
import '../theme/raeed_theme.dart';
import '../widgets/form_error.dart';
import 'auth_repository.dart';
import 'messages.dart';
import 'privacy_terms.dart';
import 'session_scope.dart';

/// The Law 09-08 statement. Shown to a parent once, right after their first password,
/// and again when the text changes: they cannot continue until they accept. Also opened
/// from حسابي to read it again ([fromAccount]).
class PrivacyConsentScreen extends StatefulWidget {
  const PrivacyConsentScreen({super.key, this.fromAccount = false});

  final bool fromAccount;

  @override
  State<PrivacyConsentScreen> createState() => _PrivacyConsentScreenState();
}

class _PrivacyConsentScreenState extends State<PrivacyConsentScreen> {
  bool _agreed = false;
  bool _busy = false;
  String? _error;

  Future<void> _accept() async {
    if (_busy || !_agreed) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await SessionScope.read(context).acceptPrivacyTerms();
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
    final acceptedAt = session.profile?.privacyConsentAt;
    return Scaffold(
      appBar: AppBar(
        title: const Text(privacyTermsTitle),
        actions: [
          if (!widget.fromAccount) TextButton(onPressed: _busy ? null : session.signOut, child: const Text('خروج')),
        ],
      ),
      body: SafeArea(
        child: ListView(
          key: const Key('privacy-terms'),
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          children: [
            Text(privacyTermsIntro, style: text.bodyMedium),
            for (final (heading, body) in privacyTermsSections) ...[
              const SizedBox(height: 16),
              Text(heading, style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(body, style: text.bodyMedium),
            ],
            const SizedBox(height: 20),
            if (widget.fromAccount)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Text(
                    acceptedAt == null
                        ? privacyTermsAgreement
                        : 'وافقت على هذا النص في ${formatDate(acceptedAt.toLocal())}.',
                    style: text.bodyMedium,
                  ),
                ),
              )
            else ...[
              Card(
                child: CheckboxListTile(
                  key: const Key('privacy-agree'),
                  value: _agreed,
                  onChanged: _busy ? null : (v) => setState(() => _agreed = v ?? false),
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(privacyTermsAgreement, style: text.bodyMedium),
                ),
              ),
              if (_error != null) ...[const SizedBox(height: 12), FormError(_error!)],
              const SizedBox(height: 16),
              FilledButton(
                key: const Key('privacy-accept'),
                onPressed: _busy || !_agreed ? null : _accept,
                child: _busy ? const ButtonSpinner() : const Text('أوافق وأتابع'),
              ),
              const SizedBox(height: 8),
              Text(
                'إن لم توافق، تواصل مع المشرف العام قبل استعمال التطبيق.',
                style: text.bodySmall?.copyWith(color: RaeedColors.grey),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
