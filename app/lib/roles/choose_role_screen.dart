import 'package:flutter/material.dart';

import '../auth/session_scope.dart';
import '../theme/raeed_theme.dart';
import 'app_role.dart';

/// Screen 3 of the main screens: only for someone with more than one role. The app
/// remembers the choice; switching later is from the avatar at the top of every tab.
class ChooseRoleScreen extends StatefulWidget {
  const ChooseRoleScreen({super.key});

  @override
  State<ChooseRoleScreen> createState() => _ChooseRoleScreenState();
}

class _ChooseRoleScreenState extends State<ChooseRoleScreen> {
  AppRole? _picked;

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.of(context);
    final roles = session.profile?.roles ?? const <AppRole>[];
    final picked = _picked ?? roles.firstOrNull;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('اختر الحساب')),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                children: [
                  Text('لديك أكثر من دور في الأكاديمية', style: text.bodyMedium?.copyWith(color: RaeedColors.grey)),
                  const SizedBox(height: 16),
                  for (final role in roles) ...[
                    RoleOption(role: role, selected: role == picked, onTap: () => setState(() => _picked = role)),
                    const SizedBox(height: 10),
                  ],
                  Text(
                    'يمكنك التبديل لاحقاً من صورتك في أعلى الشاشة.',
                    style: text.bodySmall?.copyWith(color: RaeedColors.grey),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: FilledButton(
                key: const Key('continue'),
                onPressed: picked == null ? null : () => session.chooseRole(_picked ?? picked),
                child: const Text('متابعة'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One role as a large tappable card, used on the chooser and in the switcher sheet.
class RoleOption extends StatelessWidget {
  const RoleOption({super.key, required this.role, required this.selected, required this.onTap});

  final AppRole role;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? RaeedColors.surfaceAlt : RaeedColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: selected ? RaeedColors.blue : RaeedColors.line, width: 1.5),
        ),
        child: InkWell(
          key: Key('role-${role.dbName}'),
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                RoleBadge(role: role),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(role.label, style: text.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                      Text(role.summary, style: text.bodySmall?.copyWith(color: RaeedColors.grey)),
                    ],
                  ),
                ),
                if (selected) const Icon(Icons.check_circle, color: RaeedColors.blue),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The role's icon on its colour: blue for advisor, sky for instructor, star for parent.
/// Light backgrounds take ink.
class RoleBadge extends StatelessWidget {
  const RoleBadge({super.key, required this.role, this.size = 42});

  final AppRole role;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: switch (role) {
          AppRole.advisor => const LinearGradient(colors: [RaeedColors.blue, RaeedColors.skyStart]),
          AppRole.instructor => RaeedColors.sky,
          AppRole.parent => RaeedColors.star,
        },
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: Icon(
        role.icon,
        size: size * 0.55,
        color: role == AppRole.advisor ? Colors.white : RaeedColors.ink,
      ),
    );
  }
}
