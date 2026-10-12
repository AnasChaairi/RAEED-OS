import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../roles/app_role.dart';
import 'auth_repository.dart';

enum SessionStage {
  /// Checking a saved session on start-up.
  starting,
  signedOut,

  /// Signed in with a temporary password from the advisor.
  mustChangePassword,

  /// Several roles and no remembered choice yet.
  choosingRole,

  /// Signed in, but the account has no role yet.
  noRole,

  /// Signed in, but the profile could not be loaded (usually no connection).
  profileError,
  ready,
}

/// Where the person is in sign-in, and which role they are using.
class AppSession extends ChangeNotifier {
  AppSession(this._auth, this._prefs);

  static const _lastRoleKey = 'last_role';

  final AuthRepository _auth;
  final SharedPreferences _prefs;

  SessionStage _stage = SessionStage.starting;
  Profile? _profile;
  AppRole? _role;
  AuthFailure? _profileFailure;

  SessionStage get stage => _stage;
  Profile? get profile => _profile;
  AppRole? get role => _role;
  AuthFailure? get profileFailure => _profileFailure;

  /// Picks up a session saved on the phone.
  Future<void> start() async {
    if (_auth.currentUserId == null) {
      _set(SessionStage.signedOut);
      return;
    }
    try {
      await _loadProfile();
    } on AuthError {
      // No profile: already signed out, and the sign-in screen is showing.
    }
  }

  /// Throws [AuthError] so the sign-in screen can show the reason.
  Future<void> signIn({required String phone, required String password}) async {
    await _auth.signIn(phone: phone, password: password);
    await _loadProfile();
  }

  Future<void> retry() => start();

  /// Throws [AuthError].
  Future<void> changePassword(String newPassword) async {
    await _auth.changePassword(newPassword);
    _profile = _profile!.copyWith(mustChangePassword: false);
    _route();
  }

  void chooseRole(AppRole role) {
    assert(_profile!.roles.contains(role));
    _role = role;
    _prefs.setString(_lastRoleKey, role.dbName);
    _set(SessionStage.ready);
  }

  Future<void> signOut() async {
    await _auth.signOut();
    _profile = null;
    _role = null;
    _set(SessionStage.signedOut);
  }

  Future<void> _loadProfile() async {
    try {
      _profile = await _auth.loadProfile();
      _profileFailure = null;
    } on AuthError catch (e) {
      if (e.failure == AuthFailure.noProfile) {
        // An account without a people row cannot use the app; don't leave it signed in.
        await _auth.signOut();
        _profile = null;
        _set(SessionStage.signedOut);
        rethrow;
      }
      _profileFailure = e.failure;
      _set(SessionStage.profileError);
      return;
    }
    _route();
  }

  void _route() {
    final p = _profile!;
    if (p.mustChangePassword) return _set(SessionStage.mustChangePassword);
    if (p.roles.isEmpty) return _set(SessionStage.noRole);
    if (p.roles.length == 1) {
      _role = p.roles.single;
      return _set(SessionStage.ready);
    }
    final remembered = AppRole.fromDb(_prefs.getString(_lastRoleKey) ?? '');
    if (remembered != null && p.roles.contains(remembered)) {
      _role = remembered;
      return _set(SessionStage.ready);
    }
    _set(SessionStage.choosingRole);
  }

  void _set(SessionStage stage) {
    _stage = stage;
    notifyListeners();
  }
}
