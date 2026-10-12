import 'package:raeed_os/auth/auth_repository.dart';
import 'package:raeed_os/auth/phone.dart';
import 'package:raeed_os/roles/app_role.dart';

/// An in-memory stand-in for Supabase sign-in.
class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({Map<String, FakeAccount>? accounts, this.signedInAs}) : accounts = accounts ?? {};

  /// Keyed by normalized phone number.
  final Map<String, FakeAccount> accounts;
  String? signedInAs;
  bool offline = false;
  int changePasswordCalls = 0;

  @override
  String? get currentUserId => signedInAs;

  @override
  Future<void> signIn({required String phone, required String password}) async {
    final n = normalizePhone(phone);
    if (n == null) throw const AuthError(AuthFailure.invalidPhone);
    if (offline) throw const AuthError(AuthFailure.offline);
    final account = accounts[n];
    if (account == null || account.password != password) throw const AuthError(AuthFailure.wrongCredentials);
    signedInAs = n;
  }

  @override
  Future<Profile> loadProfile() async {
    if (offline) throw const AuthError(AuthFailure.offline);
    final a = accounts[signedInAs]!;
    if (!a.hasProfile) throw const AuthError(AuthFailure.noProfile);
    return Profile(
      id: signedInAs!,
      fullName: a.fullName,
      phone: '+$signedInAs',
      mustChangePassword: a.mustChangePassword,
      roles: [for (final r in AppRole.values) if (a.roles.contains(r)) r],
    );
  }

  @override
  Future<void> changePassword(String newPassword) async {
    changePasswordCalls++;
    if (offline) throw const AuthError(AuthFailure.offline);
    final a = accounts[signedInAs]!;
    if (newPassword == a.password) throw const AuthError(AuthFailure.samePassword);
    a
      ..password = newPassword
      ..mustChangePassword = false;
  }

  @override
  Future<void> signOut() async => signedInAs = null;
}

class FakeAccount {
  FakeAccount({
    required this.fullName,
    required this.password,
    required this.roles,
    this.mustChangePassword = false,
    this.hasProfile = true,
  });

  final String fullName;
  String password;
  final Set<AppRole> roles;
  bool mustChangePassword;
  final bool hasProfile;
}
