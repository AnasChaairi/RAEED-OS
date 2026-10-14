import 'dart:async';

import 'package:flutter/material.dart';

import '../advisor/stats_screen.dart';
import '../advisor/stats_store.dart';
import '../auth/delete_account.dart';
import '../auth/phone.dart';
import '../auth/session_scope.dart';
import '../roles/app_role.dart';
import '../instructor/alerts_screen.dart';
import '../instructor/groups_screen.dart';
import '../instructor/sessions_screen.dart';
import '../instructor/today_screen.dart';
import '../instructor/widgets.dart';
import '../notifications/push.dart';
import '../parent/account_screen.dart';
import '../parent/parent_store.dart';
import '../parent/schedule_screen.dart';
import '../roles/choose_role_screen.dart';
import '../setup/children_screen.dart';
import '../setup/groups_screen.dart';
import '../setup/setup_hub.dart';
import '../setup/widgets.dart';
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
  late final AppLifecycleListener _lifecycle;
  StreamSubscription<PushMessage>? _pushes;

  @override
  void initState() {
    super.initState();
    _refreshSetup();
    // Back in the app: send waiting attendance and pick up changes.
    _lifecycle = AppLifecycleListener(onResume: _refreshRole);
    final push = PushScope.read(context);
    _pushes = push.messages.listen(_showPush);
    WidgetsBinding.instance.addPostFrameCallback((_) => push.register());
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _pushes?.cancel();
    super.dispose();
  }

  void _refreshRole() {
    switch (widget.role) {
      case AppRole.instructor:
        InstructorScope.read(context).refresh();
      case AppRole.parent:
        ParentScope.read(context).refresh();
      case AppRole.advisor:
        StatsScope.read(context).load();
        InstructorScope.read(context).refresh();
    }
  }

  /// A notification while the app is open: show it, and fetch what it is about.
  void _showPush(PushMessage m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(m.body.isEmpty ? m.title : '${m.title}\n${m.body}')),
    );
    _refreshRole();
  }

  @override
  void didUpdateWidget(HomeShell old) {
    super.didUpdateWidget(old);
    if (old.role != widget.role) {
      _index = 0;
      _refreshSetup();
    }
  }

  /// Fresh data each time someone signs in or switches to the advisor role.
  void _refreshSetup() {
    if (widget.role == AppRole.advisor) {
      final store = SetupScope.read(context);
      final stats = StatsScope.read(context);
      // The advisor plans every group's sessions.
      final sessions = InstructorScope.read(context);
      final id = SessionScope.read(context).profile!.id;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        store.load();
        stats.load();
        sessions.start(id, allGroups: true);
      });
    }
    if (widget.role == AppRole.parent) {
      final store = ParentScope.read(context);
      final id = SessionScope.read(context).profile!.id;
      WidgetsBinding.instance.addPostFrameCallback((_) => store.start(id));
    }
    if (widget.role == AppRole.instructor) {
      final store = InstructorScope.read(context);
      final id = SessionScope.read(context).profile!.id;
      WidgetsBinding.instance.addPostFrameCallback((_) => store.start(id));
    }
  }

  Widget _tabBody(int i) => switch ((widget.role, i)) {
        (AppRole.advisor, 0) => const StatsTab(),
        (AppRole.advisor, 1) => const SessionsTab(),
        (AppRole.advisor, 2) => const GroupsList(),
        (AppRole.advisor, 3) => const ChildrenList(profiles: true),
        (AppRole.advisor, 4) => const SetupHub(),
        (AppRole.instructor, 0) => const TodayTab(),
        (AppRole.instructor, 1) => const SessionsTab(),
        (AppRole.instructor, 2) => const MyGroupsTab(),
        (AppRole.instructor, 3) => const AlertsTab(),
        (AppRole.parent, 0) => const ParentScheduleTab(),
        (AppRole.parent, 1) => const ParentAccountTab(),
        _ => EmptyTab(tab: widget.role.tabs[i]),
      };

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
        children: [for (var i = 0; i < tabs.length; i++) _tabBody(i)],
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
              const DeleteAccountButton(),
            ],
          ),
        ),
      );
    },
  );
}
