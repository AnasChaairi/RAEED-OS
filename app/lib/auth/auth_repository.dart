import 'package:supabase_flutter/supabase_flutter.dart';

import '../roles/app_role.dart';
import 'phone.dart';
import 'privacy_terms.dart';

/// The signed-in person, from public.people and public.person_roles.
class Profile {
  const Profile({
    required this.id,
    required this.fullName,
    required this.phone,
    required this.mustChangePassword,
    required this.roles,
    this.privacyConsentVersion,
    this.privacyConsentAt,
  });

  final String id;
  final String fullName;
  final String phone;
  final bool mustChangePassword;

  /// Always in the order advisor, instructor, parent.
  final List<AppRole> roles;

  /// The version of the Law 09-08 statement this person accepted, and when. Null when
  /// they have not accepted any.
  final int? privacyConsentVersion;
  final DateTime? privacyConsentAt;

  Profile copyWith({bool? mustChangePassword, int? privacyConsentVersion, DateTime? privacyConsentAt}) => Profile(
    id: id,
    fullName: fullName,
    phone: phone,
    mustChangePassword: mustChangePassword ?? this.mustChangePassword,
    roles: roles,
    privacyConsentVersion: privacyConsentVersion ?? this.privacyConsentVersion,
    privacyConsentAt: privacyConsentAt ?? this.privacyConsentAt,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'full_name': fullName,
    'phone': phone,
    'must_change_password': mustChangePassword,
    'roles': [for (final r in roles) r.dbName],
    'privacy_consent_version': privacyConsentVersion,
    'privacy_consent_at': privacyConsentAt?.toIso8601String(),
  };

  static Profile fromJson(Map<String, Object?> j) => Profile(
    id: j['id'] as String,
    fullName: j['full_name'] as String,
    phone: j['phone'] as String,
    mustChangePassword: j['must_change_password'] as bool,
    roles: [for (final r in j['roles'] as List) ?AppRole.fromDb(r as String)],
    privacyConsentVersion: j['privacy_consent_version'] as int?,
    privacyConsentAt: _date(j['privacy_consent_at']),
  );
}

DateTime? _date(Object? v) => v == null ? null : DateTime.parse(v as String);

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

  /// Records that the signed-in person accepted [version] of the Law 09-08 statement.
  Future<void> acceptPrivacyTerms(int version);

  /// Asks the advisor to delete this account and its data. Asking twice is harmless.
  Future<void> requestDeletion();

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
    // مشرف الفئة comes from being put in charge of a فئة, not from person_roles.
    try {
      final supervised = await _client.from('group_supervisors').select('group_id').eq('person_id', id).limit(1);
      if (supervised.isNotEmpty) held.add(AppRole.supervisor);
    } on PostgrestException {
      // The database does not know category supervisors yet.
    }
    int? consentVersion;
    DateTime? consentAt;
    try {
      final consent = await _client
          .from('people')
          .select('privacy_consent_version, privacy_consent_at')
          .eq('id', id)
          .single();
      consentVersion = consent['privacy_consent_version'] as int?;
      consentAt = _date(consent['privacy_consent_at']);
    } on PostgrestException {
      // The database cannot store the acceptance yet: don't hold the parent on a
      // screen they cannot get past.
      consentVersion = privacyTermsVersion;
    }
    return Profile(
      id: id,
      fullName: person['full_name'] as String,
      phone: person['phone'] as String,
      mustChangePassword: person['must_change_password'] as bool,
      roles: [
        for (final r in AppRole.values)
          if (held.contains(r)) r,
      ],
      privacyConsentVersion: consentVersion,
      privacyConsentAt: consentAt,
    );
  });

  @override
  Future<void> changePassword(String newPassword) => _guard(() async {
    await _client.auth.updateUser(UserAttributes(password: newPassword));
    await _client.rpc('mark_password_changed');
  });

  @override
  Future<void> acceptPrivacyTerms(int version) =>
      _guard(() => _client.rpc('accept_privacy_terms', params: {'p_version': version}));

  @override
  Future<void> requestDeletion() => _guard(
    () => _client.from('account_deletion_requests').upsert({
      'person_id': _client.auth.currentUser!.id,
    }, ignoreDuplicates: true),
  );

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
