import 'package:flutter/material.dart';

import '../auth/phone.dart';
import '../auth/session_scope.dart';
import '../roles/app_role.dart';
import '../roles/choose_role_screen.dart';
import '../theme/raeed_theme.dart';

/// The signed-in app: the active role's tabs, with the account and role switcher behind
/// the avatar at the top.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.role});

  final AppRole role;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  void didUpdateWidget(HomeShell old) {
    super.didUpdateWidget(old);
    if (old.role != widget.role) _index = 0;
  }

  @override
  Widget build(BuildContext context) {
    final tabs = widget.role.tabs;
    final session = SessionScope.of(context);
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 68,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tabs[_index].label),
            Text(
              '${widget.role.label} · ${session.profile?.fullName ?? ''}',
              style: text.bodySmall?.copyWith(color: RaeedColors.grey),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 12),
            child: IconButton(
              key: const Key('account'),
              tooltip: 'الحساب وتبديل الدور',
              onPressed: () => showAccountSheet(context),
              icon: RoleBadge(role: widget.role, size: 38),
            ),
          ),
        ],
      ),
      body: IndexedStack(
        index: _index,
        children: [for (final tab in tabs) EmptyTab(tab: tab)],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          for (final tab in tabs)
            NavigationDestination(icon: Icon(tab.icon), selectedIcon: Icon(tab.selectedIcon), label: tab.label),
        ],
      ),
    );
  }
}

/// A tab whose screens arrive in a later stage.
class EmptyTab extends StatelessWidget {
  const EmptyTab({super.key, required this.tab});

  final RoleTab tab;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: const BoxDecoration(gradient: RaeedColors.sky, shape: BoxShape.circle),
              child: Icon(tab.selectedIcon, size: 44, color: Colors.white),
            ),
            const SizedBox(height: 20),
            Text(tab.label, style: text.headlineSmall),
            const SizedBox(height: 6),
            Text(
              'هذه الصفحة قيد الإعداد وستكون جاهزة قريباً.',
              style: text.bodyMedium?.copyWith(color: RaeedColors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> showAccountSheet(BuildContext context) {
  final session = SessionScope.read(context);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) {
      final profile = session.profile!;
      final text = Theme.of(sheetContext).textTheme;
      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(profile.fullName, style: text.titleLarge),
              Text(
                formatPhone(profile.phone),
                textDirection: TextDirection.ltr,
                textAlign: TextAlign.end,
                style: text.bodyMedium?.copyWith(color: RaeedColors.grey),
              ),
              if (profile.roles.length > 1) ...[
                const SizedBox(height: 16),
                Text('تبديل الدور', style: text.labelLarge?.copyWith(color: RaeedColors.grey)),
                const SizedBox(height: 8),
                for (final role in profile.roles) ...[
                  RoleOption(
                    role: role,
                    selected: role == session.role,
                    onTap: () {
                      Navigator.pop(sheetContext);
                      session.chooseRole(role);
                    },
                  ),
                  const SizedBox(height: 8),
                ],
              ],
              const SizedBox(height: 12),
              TextButton.icon(
                key: const Key('sign-out'),
                style: TextButton.styleFrom(foregroundColor: RaeedColors.error),
                onPressed: () {
                  Navigator.pop(sheetContext);
                  session.signOut();
                },
                icon: const Icon(Icons.logout),
                label: const Text('تسجيل الخروج'),
              ),
            ],
          ),
        ),
      );
    },
  );
}
