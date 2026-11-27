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
    final supervisorsBefore = _data.group(id)?.supervisorIds ?? const <String>[];
    if (!setEquals(supervisorsBefore.toSet(), draft.supervisorIds.toSet())) {
      await _repo.setGroupSupervisors(id, draft.supervisorIds);
    }
    final before = _data.group(id)?.logoPath;
    if (draft.newLogo != null || (draft.removeLogo && before != null)) {
      await _repo.setGroupLogo(id, draft.newLogo, replaces: before);
    }
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
    List<String> supervisedGroupIds = const [],
    Gender? gender,
  }) async {
    final account = await _repo.createAccount(fullName: fullName, phone: phone, roles: _accountRoles(roles));
    if (gender != null) await _repo.setGender(account.personId, gender);
    if (roles.contains(AppRole.instructor) && groupIds.isNotEmpty) {
      final existing = _data.groupsTaughtBy(account.personId).map((g) => g.id);
      await _repo.setInstructorGroups(account.personId, {...existing, ...groupIds}.toList());
    }
    if (roles.contains(AppRole.supervisor)) {
      final existing = _data.groupsSupervisedBy(account.personId).map((g) => g.id);
      await _setSupervised(account.personId, {...existing, ...supervisedGroupIds});
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
    List<String> supervisedGroupIds = const [],
    Gender? gender,
  }) async {
    if (fullName != person.fullName) await _repo.renamePerson(person.id, fullName);
    if (gender != null && gender != person.gender) await _repo.setGender(person.id, gender);
    // Keep the parent role: it comes from the children's records, not from this form.
    final allRoles = {..._accountRoles(roles), if (person.roles.contains(AppRole.parent)) AppRole.parent};
    if (!setEquals(allRoles, person.roles)) await _repo.setRoles(person.id, allRoles);
    await _repo.setInstructorGroups(person.id, allRoles.contains(AppRole.instructor) ? groupIds : const []);
    await _setSupervised(person.id, roles.contains(AppRole.supervisor) ? supervisedGroupIds.toSet() : const {});
    await load();
  }

  /// The roles kept in person_roles. مشرف الفئة is not one of them (it comes from
  /// group_supervisors), and an account needs at least one: a supervisor alone is also
  /// an instructor.
  static Set<AppRole> _accountRoles(Set<AppRole> roles) {
    final kept = roles.where((r) => r != AppRole.supervisor).toSet();
    return kept.isEmpty ? {AppRole.instructor} : kept;
  }

  /// Makes [personId] the supervisor of exactly [groupIds], leaving each group's other
  /// supervisors as they are.
  Future<void> _setSupervised(String personId, Set<String> groupIds) async {
    for (final g in _data.groups) {
      final has = g.supervisorIds.contains(personId);
      final wants = groupIds.contains(g.id);
      if (has == wants) continue;
      await _repo.setGroupSupervisors(g.id, [
        for (final id in g.supervisorIds)
          if (id != personId) id,
        if (wants) personId,
      ]);
    }
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

  /// Deletes a staff account after taking them off their categories and upcoming
  /// activities. Throws [SetupError].
  Future<void> deleteStaff(Person person) async {
    await _repo.releaseStaff(person.id);
    await _repo.deleteAccount(person.id);
    await load();
  }

  /// The child's parents whose accounts can go with the child: they have no other child
  /// and no staff role. Brothers' and sisters' parents always stay.
  ({List<Person> removable, List<Person> kept}) parentsOnDelete(Child child) {
    final removable = <Person>[];
    final kept = <Person>[];
    for (final id in child.parentIds) {
      final p = _data.person(id);
      if (p == null) continue;
      final otherChildren = _data.children.any((c) => c.id != child.id && c.parentIds.contains(id));
      final staff = p.roles.any((r) => r != AppRole.parent);
      (otherChildren || staff ? kept : removable).add(p);
    }
    return (removable: removable, kept: kept);
  }

  /// Deletes the child, and with [deleteParents] the parents that [parentsOnDelete] marks
  /// removable. Throws [SetupError].
  Future<void> deleteChild(Child child, {required bool deleteParents}) async {
    final parents = deleteParents ? parentsOnDelete(child).removable : const <Person>[];
    await _repo.deleteChild(child.id);
    try {
      for (final p in parents) {
        await _repo.deleteAccount(p.id);
      }
    } finally {
      await load();
    }
  }

  /// Throws [SetupError].
  Future<GroupDeletionCounts> groupDeletionCounts(Group group) => _repo.groupDeletionCounts(group.id);

  /// Throws [SetupError].
  Future<void> deleteGroup(Group group) async {
    await _repo.deleteGroup(group.id);
    await load();
  }

  /// Throws [SetupError].
  Future<void> deleteSeason(Season season) async {
    await _repo.deleteSeason(season.id);
    await load();
  }

  /// Throws [SetupError].
  Future<void> deleteTerm(Term term) async {
    await _repo.deleteTerm(term.id);
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
      gender: draft.gender,
      recordConsent: draft.consent && before?.consentRecordedAt == null,
    );
    if (before?.groupId != draft.groupId) await _repo.moveChild(childId, draft.groupId);
    if (!listEquals(before?.parentIds, parentIds)) await _repo.setChildParents(childId, parentIds);
    await load();
    return issued;
  }

  /// Throws [SetupError].
  Future<void> saveSeason({
    String? id,
    required String name,
    required DateTime startsOn,
    required DateTime endsOn,
  }) async {
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

  static IssuedPassword? _issued(NewAccount account, String fullName, String phone) => account.temporaryPassword == null
      ? null
      : IssuedPassword(
          fullName: fullName,
          phone: '+${normalizePhone(phone) ?? phone}',
          temporaryPassword: account.temporaryPassword!,
        );
}
