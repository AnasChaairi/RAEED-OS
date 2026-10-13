import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'advisor/stats_store.dart';
import 'auth/app_session.dart';
import 'auth/change_password_screen.dart';
import 'auth/messages.dart';
import 'auth/session_scope.dart';
import 'auth/sign_in_screen.dart';
import 'home/home_shell.dart';
import 'instructor/instructor_store.dart';
import 'instructor/widgets.dart';
import 'notifications/push.dart';
import 'parent/parent_store.dart';
import 'profile/profile_repository.dart';
import 'roles/choose_role_screen.dart';
import 'setup/setup_store.dart';
import 'setup/widgets.dart';
import 'theme/raeed_theme.dart';

/// Arabic only, right to left, everywhere.
class RaeedApp extends StatelessWidget {
  const RaeedApp({
    super.key,
    required this.session,
    required this.setup,
    required this.instructor,
    required this.parent,
    required this.stats,
    required this.profiles,
    required this.push,
  });

  final AppSession session;

  /// The advisor's setup data. Loaded only when an advisor opens a setup screen.
  final SetupStore setup;

  /// The instructor's sessions and attendance, kept on the phone for offline use.
  final InstructorStore instructor;

  /// The parent's schedule, kept on the phone.
  final ParentStore parent;

  /// The advisor's statistics.
  final StatsStore stats;

  /// Child profiles, for advisors and instructors.
  final ProfileRepository profiles;
  final PushService push;

  @override
  Widget build(BuildContext context) {
    return SessionScope(
      session: session,
      child: SetupScope(
        store: setup,
        child: InstructorScope(
          store: instructor,
          child: ParentScope(
            store: parent,
            child: StatsScope(
              store: stats,
              child: PushScope(
                push: push,
                child: ProfileScope(
                  repo: profiles,
                  clock: instructor.now,
                  child: MaterialApp(
            title: 'رائد',
            debugShowCheckedModeBanner: false,
            theme: buildRaeedTheme(),
            locale: const Locale('ar', 'MA'),
            supportedLocales: const [Locale('ar', 'MA')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            home: const SessionGate(),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Shows the screen that matches where the person is in sign-in.
class SessionGate extends StatelessWidget {
  const SessionGate({super.key});

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.of(context);
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: switch (session.stage) {
        SessionStage.starting => const _Splash(),
        SessionStage.signedOut => const SignInScreen(),
        SessionStage.mustChangePassword => const ChangePasswordScreen(),
        SessionStage.choosingRole => const ChooseRoleScreen(),
        SessionStage.noRole => const _Notice(
            key: ValueKey('no-role'),
            message: 'حسابك موجود لكن لم يُحدَّد له دور بعد. تواصل مع المشرف.',
          ),
        SessionStage.profileError => _Notice(
            key: const ValueKey('profile-error'),
            message: failureMessage(session.profileFailure!),
            onRetry: session.retry,
          ),
        SessionStage.ready => HomeShell(role: session.role!),
      },
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(child: Image.asset('assets/images/raeed-logo.png', width: 160, semanticLabel: 'رائد')),
      );
}

class _Notice extends StatelessWidget {
  const _Notice({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.read(context);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Image.asset('assets/images/raeed-logo.png', height: 110),
              const SizedBox(height: 24),
              Text(message, style: Theme.of(context).textTheme.titleMedium, textAlign: TextAlign.center),
              const SizedBox(height: 24),
              if (onRetry != null) ...[
                FilledButton(onPressed: onRetry, child: const Text('حاول مرة أخرى')),
                const SizedBox(height: 8),
              ],
              TextButton(
                style: TextButton.styleFrom(foregroundColor: RaeedColors.error),
                onPressed: session.signOut,
                child: const Text('تسجيل الخروج'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
