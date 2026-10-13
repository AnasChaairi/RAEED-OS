import 'dart:typed_data';

import '../roles/app_role.dart';

enum Gender {
  male('ذكر'),
  female('أنثى');

  const Gender(this.label);

  final String label;

  String get dbName => name;

  static Gender? fromDb(Object? value) => values.where((g) => g.name == value).firstOrNull;
}

/// A فئة.
class Group {
  const Group({
    required this.id,
    required this.name,
    required this.logoLetter,
    required this.logoColor,
    this.logoPath,
    this.ageMin,
    this.ageMax,
    this.archived = false,
    this.instructorIds = const [],
  });

  final String id;
  final String name;
  final String logoLetter;

  /// 1 to 8, an index into [groupLogoColors].
  final int logoColor;

  /// The uploaded logo in the "group-logos" bucket, shown instead of the letter.
  final String? logoPath;
  final int? ageMin;
  final int? ageMax;
  final bool archived;
  final List<String> instructorIds;

  /// من 8 إلى 10 سنوات, or null when no range is set.
  String? get ageLabel {
    if (ageMin == null && ageMax == null) return null;
    if (ageMin != null && ageMax != null) return ageMin == ageMax ? '$ageMin سنوات' : 'من $ageMin إلى $ageMax سنوات';
    return ageMin != null ? 'من $ageMin سنوات' : 'حتى $ageMax سنوات';
  }
}

/// Anyone with an account: staff and parents.
class Person {
  const Person({
    required this.id,
    required this.fullName,
    required this.phone,
    required this.roles,
    this.mustChangePassword = false,
    this.gender,
  });

  final String id;
  final String fullName;
  final String phone;
  final Set<AppRole> roles;
  final Gender? gender;

  /// Still on the temporary password from the advisor.
  final bool mustChangePassword;

  bool get isStaff => roles.contains(AppRole.advisor) || roles.contains(AppRole.instructor);
}

class Child {
  const Child({
    required this.id,
    required this.fullName,
    this.birthDate,
    this.gender,
    this.groupId,
    this.parentIds = const [],
    this.consentRecordedAt,
  });

  final String id;
  final String fullName;
  final DateTime? birthDate;

  /// Null on children added before gender was asked.
  final Gender? gender;

  /// The current group, if any.
  final String? groupId;
  final List<String> parentIds;
  final DateTime? consentRecordedAt;
}

class Season {
  const Season({required this.id, required this.name, required this.startsOn, required this.endsOn, this.terms = const []});

  final String id;
  final String name;
  final DateTime startsOn;
  final DateTime endsOn;

  /// In date order.
  final List<Term> terms;
}

class Term {
  const Term({required this.id, required this.name, required this.startsOn, required this.endsOn});

  final String id;
  final String name;
  final DateTime startsOn;
  final DateTime endsOn;
}

/// Everything the advisor's setup screens show. Small enough to load in one go
/// (about 150 children, 180 people).
class SetupSnapshot {
  const SetupSnapshot({
    this.groups = const [],
    this.people = const [],
    this.children = const [],
    this.seasons = const [],
    this.deletionRequests = const [],
  });

  final List<Group> groups;
  final List<Person> people;
  final List<Child> children;
  final List<Season> seasons;

  /// People who asked for their account to be deleted, oldest request first.
  final List<({String personId, DateTime requestedAt})> deletionRequests;

  Group? group(String? id) => id == null ? null : groups.where((g) => g.id == id).firstOrNull;
  Person? person(String? id) => id == null ? null : people.where((p) => p.id == id).firstOrNull;

  List<Person> get staff => people.where((p) => p.isStaff).toList();
  List<Person> get instructors => people.where((p) => p.roles.contains(AppRole.instructor)).toList();
  List<Person> get parents => people.where((p) => p.roles.contains(AppRole.parent)).toList();
  List<Group> get activeGroups => groups.where((g) => !g.archived).toList();
  List<Child> childrenIn(String groupId) => children.where((c) => c.groupId == groupId).toList();
  List<Group> groupsTaughtBy(String personId) => groups.where((g) => g.instructorIds.contains(personId)).toList();
  List<Child> childrenOf(String parentId) => children.where((c) => c.parentIds.contains(parentId)).toList();

  /// Children whose parents would get no notifications.
  List<Child> get childrenWithoutParent => children.where((c) => c.parentIds.isEmpty).toList();
  List<Child> get childrenWithoutGroup => children.where((c) => c.groupId == null).toList();
  List<Group> get groupsWithoutInstructor => activeGroups.where((g) => g.instructorIds.isEmpty).toList();
}

/// What the advisor fills in on the group form.
class GroupDraft {
  const GroupDraft({
    this.id,
    required this.name,
    required this.logoLetter,
    required this.logoColor,
    this.newLogo,
    this.removeLogo = false,
    this.ageMin,
    this.ageMax,
    this.archived = false,
    this.instructorIds = const [],
  });

  final String? id;
  final String name;
  final String logoLetter;
  final int logoColor;

  /// A picked image, already scaled down, to upload as the group's logo.
  final Uint8List? newLogo;

  /// Go back to the letter.
  final bool removeLogo;
  final int? ageMin;
  final int? ageMax;
  final bool archived;
  final List<String> instructorIds;
}

/// A parent on the child form: someone already registered, or a new account.
class ParentDraft {
  const ParentDraft.existing(String this.personId) : fullName = null, phone = null;
  const ParentDraft.create({required String this.fullName, required String this.phone}) : personId = null;

  final String? personId;
  final String? fullName;
  final String? phone;
}

class ChildDraft {
  const ChildDraft({
    this.id,
    required this.fullName,
    this.birthDate,
    this.gender,
    this.groupId,
    this.parents = const [],
    this.consent = false,
  });

  final String? id;
  final String fullName;
  final DateTime? birthDate;
  final Gender? gender;
  final String? groupId;

  /// At most two.
  final List<ParentDraft> parents;

  /// The paper consent under Law 09-08 has been received.
  final bool consent;
}

/// An account the advisor just created or reset, to hand over.
class IssuedPassword {
  const IssuedPassword({required this.fullName, required this.phone, required this.temporaryPassword});

  final String fullName;
  final String phone;
  final String temporaryPassword;
}

/// The result of creating an account through the manage-account function.
class NewAccount {
  const NewAccount({required this.personId, this.temporaryPassword});

  final String personId;

  /// Null when the phone number already had an account, which keeps its password.
  final String? temporaryPassword;
}
