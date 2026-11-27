import 'package:flutter/widgets.dart';

import 'app_session.dart';

/// Makes the [AppSession] available to every screen, and rebuilds them when it changes.
class SessionScope extends InheritedNotifier<AppSession> {
  const SessionScope({super.key, required AppSession session, required super.child}) : super(notifier: session);

  static AppSession of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SessionScope>()!.notifier!;

  /// For callbacks, which must not subscribe to changes.
  static AppSession read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<SessionScope>()!.notifier!;
}
