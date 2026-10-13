import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';

/// A notification that arrived while the app was open.
class PushMessage {
  const PushMessage({required this.title, required this.body});

  final String title;
  final String body;
}

enum PushState {
  /// This build has no Firebase project, so no notifications.
  unavailable,

  /// Not asked yet, or the phone has not answered.
  unknown,

  /// The person said no in the phone's settings.
  denied,
  on,
}

/// Push notifications for whoever is signed in on this phone.
abstract class PushService extends ChangeNotifier {
  PushState get state;

  /// Notifications that arrive while the app is open; the phone shows the others itself.
  Stream<PushMessage> get messages;

  /// Asks for permission if needed and registers this phone for the signed-in person.
  Future<void> register();

  /// Before signing out: this phone stops receiving the person's notifications.
  Future<void> unregister();
}

/// Tests and builds without Firebase.
class NoPush extends PushService {
  @override
  PushState get state => PushState.unavailable;

  @override
  Stream<PushMessage> get messages => const Stream.empty();

  @override
  Future<void> register() async {}

  @override
  Future<void> unregister() async {}
}

/// Firebase Cloud Messaging. The server's send-notifications function reads the token
/// this registers in the devices table.
class FirebasePush extends PushService {
  FirebasePush(this._db);

  final SupabaseClient _db;
  final _messages = StreamController<PushMessage>.broadcast();
  PushState _state = PushState.unknown;
  String? _token;
  bool _started = false;

  /// Starts Firebase when this build has a project. Returns [NoPush] otherwise, or when
  /// Firebase fails to start.
  static Future<PushService> create(SupabaseClient db) async {
    if (!AppConfig.pushConfigured || kIsWeb) return NoPush();
    try {
      await Firebase.initializeApp(
        options: const FirebaseOptions(
          apiKey: AppConfig.firebaseApiKey,
          appId: AppConfig.firebaseAppId,
          messagingSenderId: AppConfig.firebaseSenderId,
          projectId: AppConfig.firebaseProjectId,
        ),
      );
      return FirebasePush(db);
    } catch (e) {
      debugPrint('push unavailable: $e');
      return NoPush();
    }
  }

  @override
  PushState get state => _state;

  @override
  Stream<PushMessage> get messages => _messages.stream;

  @override
  Future<void> register() async {
    try {
      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission();
      _state = switch (settings.authorizationStatus) {
        AuthorizationStatus.authorized || AuthorizationStatus.provisional => PushState.on,
        AuthorizationStatus.denied => PushState.denied,
        _ => PushState.unknown,
      };
      notifyListeners();
      if (_state != PushState.on) return;
      if (!_started) {
        _started = true;
        FirebaseMessaging.onMessage.listen((m) {
          final n = m.notification;
          if (n != null) _messages.add(PushMessage(title: n.title ?? '', body: n.body ?? ''));
        });
        messaging.onTokenRefresh.listen(_save);
      }
      final token = await messaging.getToken();
      if (token != null) await _save(token);
    } catch (e) {
      // No connection or no Play services: try again next time the app opens.
      debugPrint('push register failed: $e');
    }
  }

  Future<void> _save(String token) async {
    _token = token;
    if (_db.auth.currentUser == null) return;
    await _db.rpc<void>(
      'register_device',
      params: {'p_token': token, 'p_platform': defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android'},
    );
  }

  @override
  Future<void> unregister() async {
    final token = _token;
    if (token == null) return;
    try {
      await _db.from('devices').delete().eq('push_token', token);
    } catch (_) {
      // Offline: the server forgets the token when Firebase reports it gone.
    }
  }
}

class PushScope extends InheritedNotifier<PushService> {
  const PushScope({super.key, required PushService push, required super.child}) : super(notifier: push);

  static PushService of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<PushScope>()!.notifier!;

  static PushService read(BuildContext context) => context.getInheritedWidgetOfExactType<PushScope>()!.notifier!;
}
