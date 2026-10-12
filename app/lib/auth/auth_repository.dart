import 'package:supabase_flutter/supabase_flutter.dart';

import '../roles/app_role.dart';
import 'phone.dart';

/// The signed-in person, from public.people and public.person_roles.
class Profile {
  const Profile({
    required this.id,
    required this.fullName,
    required this.phone,
    required this.mustChangePassword,
    required this.roles,
  });

  final String id;
  final String fullName;
  final String phone;
  final bool mustChangePassword;

  /// Always in the order advisor, instructor, parent.
  final List<AppRole> roles;

  Profile copyWith({bool? mustChangePassword}) => Profile(
        id: id,
        fullName: fullName,
        phone: phone,
        mustChangePassword: mustChangePassword ?? this.mustChangePassword,
        roles: roles,
      );
}

enum AuthFailure {
  /// The number is not a Moroccan phone number.
  invalidPhone,

  /// Unknown number or wrong password. Supabase does not say which, and neither do we.
  wrongCredentials,

  /// Signed in, but there is no people row for this account.
  noProfile,
  offline,
  weakPassword,
  samePassword,
  unknown,
}

class AuthError implements Exception {
  const AuthError(this.failure);

  final AuthFailure failure;

  @override
  String toString() => 'AuthError($failure)';
}

/// Everything the app shell needs from Supabase sign-in, behind an interface so the
/// screens can be tested without a server.
abstract interface class AuthRepository {
  /// The id of the account signed in on this phone, if any. Supabase keeps the session
  /// on the phone, so people stay signed in until they sign out.
  String? get currentUserId;

  Future<void> signIn({required String phone, required String password});

  Future<Profile> loadProfile();

  /// Sets a new password and clears people.must_change_password.
  Future<void> changePassword(String newPassword);

  Future<void> signOut();
}

class SupabaseAuthRepository implements AuthRepository {
  SupabaseAuthRepository(this._client);

  final SupabaseClient _client;

  @override
  String? get currentUserId => _client.auth.currentUser?.id;

  @override
  Future<void> signIn({required String phone, required String password}) async {
    final normalized = normalizePhone(phone);
    if (normalized == null) throw const AuthError(AuthFailure.invalidPhone);
    await _guard(() => _client.auth.signInWithPassword(email: phoneToEmail(normalized), password: password));
  }

  @override
  Future<Profile> loadProfile() => _guard(() async {
        final id = _client.auth.currentUser!.id;
        final person = await _client
            .from('people')
            .select('id, full_name, phone, must_change_password')
            .eq('id', id)
            .maybeSingle();
        if (person == null) throw const AuthError(AuthFailure.noProfile);
        final roleRows = await _client.from('person_roles').select('role').eq('person_id', id);
        final held = {for (final row in roleRows) AppRole.fromDb(row['role'] as String)};
        return Profile(
          id: id,
          fullName: person['full_name'] as String,
          phone: person['phone'] as String,
          mustChangePassword: person['must_change_password'] as bool,
          roles: [for (final r in AppRole.values) if (held.contains(r)) r],
        );
      });

  @override
  Future<void> changePassword(String newPassword) => _guard(() async {
        await _client.auth.updateUser(UserAttributes(password: newPassword));
        await _client.rpc('mark_password_changed');
      });

  @override
  Future<void> signOut() async {
    try {
      await _client.auth.signOut();
    } catch (_) {
      // Offline: the local session is cleared anyway.
    }
  }

  Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on AuthError {
      rethrow;
    } on AuthApiException catch (e) {
      throw AuthError(switch (e.code) {
        'invalid_credentials' => AuthFailure.wrongCredentials,
        'weak_password' => AuthFailure.weakPassword,
        'same_password' => AuthFailure.samePassword,
        _ => AuthFailure.unknown,
      });
    } on AuthWeakPasswordException {
      throw const AuthError(AuthFailure.weakPassword);
    } on AuthRetryableFetchException {
      throw const AuthError(AuthFailure.offline);
    } on PostgrestException {
      throw const AuthError(AuthFailure.unknown);
    } catch (e) {
      // SocketException, ClientException, TimeoutException: no usable connection.
      final text = e.toString();
      if (text.contains('SocketException') || text.contains('ClientException') || text.contains('TimeoutException')) {
        throw const AuthError(AuthFailure.offline);
      }
      throw const AuthError(AuthFailure.unknown);
    }
  }
}
