import 'package:flutter/foundation.dart';

import '../auth/phone.dart';
import '../roles/app_role.dart';
import 'models.dart';
import 'setup_repository.dart';

/// The advisor's setup data, loaded once and reloaded after every change.
class SetupStore extends ChangeNotifier {
  SetupStore(this._repo);

  final SetupRepository _repo;

  SetupSnapshot _data = const SetupSnapshot();
  bool _loading = false;
  bool _loaded = false;
  SetupFailure? _loadFailure;

  SetupSnapshot get data => _data;
  bool get loading => _loading;
  bool get loaded => _loaded;
  SetupFailure? get loadFailure => _loadFailure;

  Future<void> load() async {
    _loading = true;
    notifyListeners();
    try {
      _data = await _repo.load();
      _loaded = true;
      _loadFailure = null;
    } on SetupError catch (e) {
      _loadFailure = e.failure;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Loads the first time only.
  Future<void> ensureLoaded() async {
    if (!_loaded && !_loading) await load();
  }

  /// Throws [SetupError].
  Future<void> saveGroup(GroupDraft draft) async {
    final id = await _repo.saveGroup(draft);
    await _repo.setGroupInstructors(id, draft.instructorIds);
    await load();
  }

  /// Creates a staff account (or adds the roles to an existing one) and puts the
  /// instructor in their groups. Returns the password to hand over, or null when the
  /// number was already registered. Throws [SetupError].
  Future<IssuedPassword?> createStaff({
    required String fullName,
    required String phone,
    required Set<AppRole> roles,
    required List<String> groupIds,
  }) async {
    final account = await _repo.createAccount(fullName: fullName, phone: phone, roles: roles);
    if (roles.contains(AppRole.instructor) && groupIds.isNotEmpty) {
      final existing = _data.groupsTaughtBy(account.personId).map((g) => g.id);
      await _repo.setInstructorGroups(account.personId, {...existing, ...groupIds}.toList());
    }
    await load();
    return _issued(account, fullName, phone);
  }

  /// Throws [SetupError].
  Future<void> updateStaff({
    required Person person,
    required String fullName,
    required Set<AppRole> roles,
    required List<String> groupIds,
  }) async {
    if (fullName != person.fullName) await _repo.renamePerson(person.id, fullName);
    // Keep the parent role: it comes from the children's records, not from this form.
    final allRoles = {...roles, if (person.roles.contains(AppRole.parent)) AppRole.parent};
    if (!setEquals(allRoles, person.roles)) await _repo.setRoles(person.id, allRoles);
    await _repo.setInstructorGroups(person.id, roles.contains(AppRole.instructor) ? groupIds : const []);
    await load();
  }

  /// Throws [SetupError].
  Future<void> renamePerson(Person person, String fullName) async {
    await _repo.renamePerson(person.id, fullName);
    await load();
  }

  /// Throws [SetupError].
  Future<void> deleteAccount(Person person) async {
    await _repo.deleteAccount(person.id);
    await load();
  }

  /// Throws [SetupError].
  Future<IssuedPassword> resetPassword(Person person) async {
    final password = await _repo.resetPassword(person.id);
    await load();
    return IssuedPassword(fullName: person.fullName, phone: person.phone, temporaryPassword: password);
  }

  /// Saves the child, their group and parents, creating parent accounts as needed.
  /// Returns the passwords to hand to new parents. Throws [SetupError].
  Future<List<IssuedPassword>> saveChild(ChildDraft draft) async {
    final issued = <IssuedPassword>[];
    final parentIds = <String>[];
    for (final p in draft.parents) {
      if (p.personId != null) {
        parentIds.add(p.personId!);
        continue;
      }
      final account = await _repo.createAccount(fullName: p.fullName!, phone: p.phone!, roles: {AppRole.parent});
      parentIds.add(account.personId);
      final pw = _issued(account, p.fullName!, p.phone!);
      if (pw != null) issued.add(pw);
    }

    final before = draft.id == null ? null : _data.children.where((c) => c.id == draft.id).firstOrNull;
    final childId = await _repo.saveChild(
      id: draft.id,
      fullName: draft.fullName,
      birthDate: draft.birthDate,
      recordConsent: draft.consent && before?.consentRecordedAt == null,
    );
    if (before?.groupId != draft.groupId) await _repo.moveChild(childId, draft.groupId);
    if (!listEquals(before?.parentIds, parentIds)) await _repo.setChildParents(childId, parentIds);
    await load();
    return issued;
  }

  /// Throws [SetupError].
  Future<void> saveSeason({String? id, required String name, required DateTime startsOn, required DateTime endsOn}) async {
    await _repo.saveSeason(id: id, name: name, startsOn: startsOn, endsOn: endsOn);
    await load();
  }

  /// Throws [SetupError].
  Future<void> saveTerm({
    String? id,
    required String seasonId,
    required String name,
    required DateTime startsOn,
    required DateTime endsOn,
  }) async {
    await _repo.saveTerm(id: id, seasonId: seasonId, name: name, startsOn: startsOn, endsOn: endsOn);
    await load();
  }

  static IssuedPassword? _issued(NewAccount account, String fullName, String phone) =>
      account.temporaryPassword == null
          ? null
          : IssuedPassword(
              fullName: fullName,
              phone: '+${normalizePhone(phone) ?? phone}',
              temporaryPassword: account.temporaryPassword!,
            );
}
