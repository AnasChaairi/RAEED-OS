import 'package:flutter/material.dart';

import '../auth/change_password_screen.dart';
import '../auth/delete_account.dart';
import '../auth/session_scope.dart';
import '../notifications/push.dart';
import '../setup/widgets.dart';
import '../theme/raeed_theme.dart';
import 'parent_store.dart';

/// The parent's حسابي tab: their children, who is notified, the privacy promise, the
/// password and signing out.
class ParentAccountTab extends StatelessWidget {
  const ParentAccountTab({super.key});

  @override
  Widget build(BuildContext context) {
    final store = ParentScope.of(context);
    final push = PushScope.of(context);
    final session = SessionScope.of(context);
    final me = session.profile?.id;
    final data = store.data;
    final text = Theme.of(context).textTheme;
    final muted = text.bodySmall?.copyWith(color: RaeedColors.grey);
    final parents = data.notifiedParents;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        const SectionLabel('أطفالي'),
        if (data.children.isEmpty)
          Text('لا يوجد طفل مرتبط بحسابك بعد.', style: text.bodyMedium?.copyWith(color: RaeedColors.grey))
        else
          Card(
            child: Column(
              children: [
                for (final c in data.children)
                  ListTile(
                    leading: InitialAvatar(c.fullName, size: 32),
                    title: Text([c.firstName, c.group?.name ?? 'بدون فئة'].join(' · ')),
                  ),
              ],
            ),
          ),
        const SectionLabel('من يتلقى الإشعارات'),
        Card(
          child: Column(
            children: [
              for (final p in parents)
                () {
                  final mine = p.parentId == me;
                  // This phone's own state is known better here than on the server.
                  final on = mine && push.state != PushState.unavailable ? push.state == PushState.on : p.notified;
                  return ListTile(
                    key: Key('notified-${p.parentId}'),
                    title: Text(mine ? '${p.fullName} (أنت)' : p.fullName),
                    trailing: Text(
                      on ? 'مفعّل' : 'غير مفعّل',
                      style: text.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: on ? const Color(0xFF1C7A55) : RaeedColors.grey,
                      ),
                    ),
                  );
                }(),
            ],
          ),
        ),
        if (push.state == PushState.denied)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('الإشعارات متوقفة على هذا الهاتف. فعّلها من إعدادات الهاتف لتطبيق رائد.', style: muted),
          ),
        if (push.state == PushState.unknown)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              key: const Key('enable-push'),
              onPressed: push.register,
              icon: const Icon(Icons.notifications_active_outlined),
              label: const Text('تفعيل الإشعارات على هذا الهاتف'),
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text('لإضافة أو تغيير ولي أمر، تواصل مع المشرف.', style: muted),
        ),
        const SectionLabel('بيانات أطفالك'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Text(
              'يرى بيانات طفلك مؤطرو فئته والمشرفون فقط. لا صور في التطبيق. لا تُشارك البيانات خارج الأكاديمية.',
              style: text.bodyMedium,
            ),
          ),
        ),
        const SizedBox(height: 20),
        OutlinedButton(
          key: const Key('change-password'),
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute<void>(builder: (_) => const ChangePasswordScreen(fromAccount: true)),
          ),
          child: const Text('تغيير كلمة المرور'),
        ),
        const SizedBox(height: 4),
        TextButton(
          key: const Key('parent-sign-out'),
          style: TextButton.styleFrom(foregroundColor: RaeedColors.error),
          onPressed: session.signOut,
          child: const Text('تسجيل الخروج'),
        ),
        const DeleteAccountButton(),
      ],
    );
  }
}
