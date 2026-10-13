import 'package:flutter/material.dart';

import '../theme/raeed_theme.dart';
import 'auth_repository.dart';
import 'messages.dart';
import 'session_scope.dart';

/// Asks the advisor to delete the signed-in account and its data, after a confirmation.
class DeleteAccountButton extends StatelessWidget {
  const DeleteAccountButton({super.key});

  @override
  Widget build(BuildContext context) => TextButton(
    key: const Key('request-deletion'),
    style: TextButton.styleFrom(foregroundColor: RaeedColors.grey),
    onPressed: () => requestAccountDeletion(context),
    child: const Text('طلب حذف حسابي'),
  );
}

Future<void> requestAccountDeletion(BuildContext context) async {
  final session = SessionScope.read(context);
  final messenger = ScaffoldMessenger.of(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('حذف الحساب'),
      content: const Text(
        'سيصل طلبك إلى المشرف، فيحذف حسابك ورقم هاتفك من التطبيق. '
        'سجلّ حضور الأطفال يبقى لدى الأكاديمية ما دام الطفل مسجّلاً.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('إلغاء')),
        FilledButton(
          key: const Key('confirm-deletion'),
          style: FilledButton.styleFrom(backgroundColor: RaeedColors.error),
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('أرسل الطلب'),
        ),
      ],
    ),
  );
  if (ok != true) return;
  try {
    await session.requestDeletion();
    messenger.showSnackBar(const SnackBar(content: Text('وصل طلبك إلى المشرف ✓')));
  } on AuthError catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(failureMessage(e.failure))));
  }
}
