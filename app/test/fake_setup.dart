import 'dart:typed_data';

import 'package:raeed_os/auth/phone.dart';
import 'package:raeed_os/roles/app_role.dart';
import 'package:raeed_os/setup/models.dart';
import 'package:raeed_os/setup/setup_repository.dart';

/// An in-memory stand-in for the advisor's Supabase tables and the manage-account function.
class FakeSetupRepository implements SetupRepository {
  final groups = <String, Group>{};
  final people = <String, Person>{};
  final children = <String, Child>{};
  final seasons = <String, Season>{};
  final calls = <String>[];
  final deletionRequests = <({String personId, DateTime requestedAt})>[];
  var _next = 0;
  bool offline = false;

  String _id(String prefix) => '$prefix-${++_next}';

  void _check() {
    if (offline) throw const SetupError(SetupFailure.offline);
  }

  void addPerson(String id, String name, String phone, Set<AppRole> roles) =>
      people[id] = Person(id: id, fullName: name, phone: '+${normalizePhone(phone)}', roles: roles);

  @override
  Future<SetupSnapshot> load() async {
    _check();
    return SetupSnapshot(
      groups: groups.values.toList(),
      people: people.values.toList(),
      children: children.values.toList(),
      seasons: seasons.values.toList(),
      deletionRequests: List.of(deletionRequests),
    );
  }

  @override
  Future<void> deleteAccount(String personId) async {
    _check();
    calls.add('deleteAccount $personId');
    people.remove(personId);
    deletionRequests.removeWhere((r) => r.personId == personId);
    for (final c in children.values.toList()) {
      if (c.parentIds.contains(personId)) {
        children[c.id] = Child(
          id: c.id,
          fullName: c.fullName,
          birthDate: c.birthDate,
          gender: c.gender,
          groupId: c.groupId,
          parentIds: c.parentIds.where((p) => p != personId).toList(),
          consentRecordedAt: c.consentRecordedAt,
        );
      }
    }
  }

  @override
  Future<String> saveGroup(GroupDraft d) async {
    _check();
    calls.add('saveGroup ${d.name}');
    if (groups.values.any((g) => g.name == d.name && g.id != d.id)) throw const SetupError(SetupFailure.duplicateName);
    final id = d.id ?? _id('group');
    groups[id] = Group(
      id: id,
      name: d.name,
      logoLetter: d.logoLetter,
      logoColor: d.logoColor,
      logoPath: groups[id]?.logoPath,
      ageMin: d.ageMin,
      ageMax: d.ageMax,
      archived: d.archived,
      instructorIds: groups[id]?.instructorIds ?? const [],
    );
    return id;
  }

  @override
  Future<void> setGroupInstructors(String groupId, List<String> personIds) async {
    calls.add('setGroupInstructors $groupId ${personIds.join(',')}');
    final g = groups[groupId]!;
    groups[groupId] = _withInstructors(g, personIds);
  }

  @override
  Future<void> setInstructorGroups(String personId, List<String> groupIds) async {
    calls.add('setInstructorGroups $personId ${groupIds.join(',')}');
    for (final g in groups.values.toList()) {
      final ids = {...g.instructorIds}..remove(personId);
      if (groupIds.contains(g.id)) ids.add(personId);
      groups[g.id] = _withInstructors(g, ids.toList());
    }
  }

  Group _withInstructors(Group g, List<String> ids) => Group(
        id: g.id,
        name: g.name,
        logoLetter: g.logoLetter,
        logoColor: g.logoColor,
        logoPath: g.logoPath,
        ageMin: g.ageMin,
        ageMax: g.ageMax,
        archived: g.archived,
        instructorIds: ids,
      );

  /// Uploaded logos by path.
  final logos = <String, Uint8List>{};

  @override
  Future<void> setGroupLogo(String groupId, Uint8List? image, {String? replaces}) async {
    _check();
    calls.add('setGroupLogo $groupId ${image == null ? 'none' : '${image.length} bytes'} replaces=$replaces');
    String? path;
    if (image != null) {
      path = '$groupId/${logos.length + 1}.jpg';
      logos[path] = image;
    }
    if (replaces != null) logos.remove(replaces);
    final g = groups[groupId]!;
    groups[groupId] = Group(
      id: g.id,
      name: g.name,
      logoLetter: g.logoLetter,
      logoColor: g.logoColor,
      logoPath: path,
      ageMin: g.ageMin,
      ageMax: g.ageMax,
      archived: g.archived,
      instructorIds: g.instructorIds,
    );
  }

  @override
  Future<void> setGender(String personId, Gender gender) async {
    calls.add('setGender $personId ${gender.dbName}');
    final p = people[personId]!;
    people[personId] = Person(
      id: p.id,
      fullName: p.fullName,
      phone: p.phone,
      roles: p.roles,
      mustChangePassword: p.mustChangePassword,
      gender: gender,
    );
  }

  @override
  Future<NewAccount> createAccount({required String fullName, required String phone, required Set<AppRole> roles}) async {
    _check();
    final n = normalizePhone(phone);
    if (n == null) throw const SetupError(SetupFailure.invalidPhone);
    calls.add('createAccount $fullName');
    final existing = people.values.where((p) => p.phone == '+$n').firstOrNull;
    if (existing != null) {
      people[existing.id] = Person(
        id: existing.id,
        fullName: existing.fullName,
        phone: existing.phone,
        roles: {...existing.roles, ...roles},
        gender: existing.gender,
      );
      return NewAccount(personId: existing.id);
    }
    final id = _id('person');
    people[id] = Person(id: id, fullName: fullName, phone: '+$n', roles: roles, mustChangePassword: true);
    return NewAccount(personId: id, temporaryPassword: 'temp$id');
  }

  @override
  Future<String> resetPassword(String personId) async {
    calls.add('resetPassword $personId');
    return 'reset$personId';
  }

  @override
  Future<void> setRoles(String personId, Set<AppRole> roles) async {
    calls.add('setRoles $personId ${roles.map((r) => r.dbName).join(',')}');
    final p = people[personId]!;
    people[personId] = Person(id: p.id, fullName: p.fullName, phone: p.phone, roles: roles, gender: p.gender);
  }

  @override
  Future<void> renamePerson(String personId, String fullName) async {
    calls.add('renamePerson $personId $fullName');
    final p = people[personId]!;
    people[personId] = Person(id: p.id, fullName: fullName, phone: p.phone, roles: p.roles, gender: p.gender);
  }

  @override
  Future<String> saveChild({
    String? id,
    required String fullName,
    DateTime? birthDate,
    Gender? gender,
    required bool recordConsent,
  }) async {
    _check();
    calls.add('saveChild $fullName consent=$recordConsent');
    final childId = id ?? _id('child');
    final before = children[childId];
    children[childId] = Child(
      id: childId,
      fullName: fullName,
      birthDate: birthDate,
      gender: gender ?? before?.gender,
      groupId: before?.groupId,
      parentIds: before?.parentIds ?? const [],
      consentRecordedAt: recordConsent ? DateTime(2026, 10, 12) : before?.consentRecordedAt,
    );
    return childId;
  }

  @override
  Future<void> moveChild(String childId, String? groupId) async {
    calls.add('moveChild $childId $groupId');
    final c = children[childId]!;
    children[childId] = Child(id: c.id, fullName: c.fullName, birthDate: c.birthDate, gender: c.gender, groupId: groupId, parentIds: c.parentIds, consentRecordedAt: c.consentRecordedAt);
  }

  @override
  Future<void> setChildParents(String childId, List<String> parentIds) async {
    calls.add('setChildParents $childId ${parentIds.join(',')}');
    if (parentIds.length > 2) throw const SetupError(SetupFailure.tooManyParents);
    final c = children[childId]!;
    children[childId] = Child(id: c.id, fullName: c.fullName, birthDate: c.birthDate, gender: c.gender, groupId: c.groupId, parentIds: parentIds, consentRecordedAt: c.consentRecordedAt);
  }

  @override
  Future<String> saveSeason({String? id, required String name, required DateTime startsOn, required DateTime endsOn}) async {
    final sid = id ?? _id('season');
    seasons[sid] = Season(id: sid, name: name, startsOn: startsOn, endsOn: endsOn, terms: seasons[sid]?.terms ?? const []);
    return sid;
  }

  @override
  Future<String> saveTerm({String? id, required String seasonId, required String name, required DateTime startsOn, required DateTime endsOn}) async {
    final s = seasons[seasonId]!;
    final tid = id ?? _id('term');
    final terms = [...s.terms.where((t) => t.id != tid), Term(id: tid, name: name, startsOn: startsOn, endsOn: endsOn)]
      ..sort((a, b) => a.startsOn.compareTo(b.startsOn));
    seasons[seasonId] = Season(id: s.id, name: s.name, startsOn: s.startsOn, endsOn: s.endsOn, terms: terms);
    return tid;
  }
}
