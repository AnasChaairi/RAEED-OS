import '../instructor/models.dart';
import '../setup/models.dart';

/// One of the parent's children, with the فئة they are in now.
class ParentChild {
  const ParentChild({required this.id, required this.fullName, this.group});

  final String id;
  final String fullName;
  final Group? group;

  /// آدم, from آدم بنعلي.
  String get firstName => fullName.trim().split(RegExp(r'\s+')).first;

  Map<String, Object?> toJson() => {
    'id': id,
    'full_name': fullName,
    'group': group == null ? null : groupToJson(group!),
  };

  static ParentChild fromJson(Map<String, dynamic> j) => ParentChild(
    id: j['id'] as String,
    fullName: j['full_name'] as String,
    group: j['group'] == null ? null : groupFromJson(j['group'] as Map<String, dynamic>),
  );
}

/// A parent of one of the children, and whether a phone of theirs receives notifications.
class ChildParent {
  const ChildParent({required this.childId, required this.parentId, required this.fullName, required this.notified});

  final String childId;
  final String parentId;
  final String fullName;
  final bool notified;

  Map<String, Object?> toJson() => {
    'child_id': childId,
    'parent_id': parentId,
    'full_name': fullName,
    'notified': notified,
  };

  static ChildParent fromJson(Map<String, dynamic> j) => ChildParent(
    childId: j['child_id'] as String,
    parentId: j['parent_id'] as String,
    fullName: j['full_name'] as String,
    notified: j['notified'] as bool? ?? false,
  );
}

/// Everything the parent's tabs show, kept on the phone so the schedule opens offline.
class ParentSnapshot {
  const ParentSnapshot({
    this.children = const [],
    this.sessions = const [],
    this.staffNames = const {},
    this.parents = const [],
  });

  final List<ParentChild> children;

  /// Sorted by start.
  final List<Session> sessions;

  /// Instructor names by group id.
  final Map<String, List<String>> staffNames;
  final List<ChildParent> parents;

  ParentChild? child(String id) => children.where((c) => c.id == id).firstOrNull;
  Session? session(String id) => sessions.where((s) => s.id == id).firstOrNull;

  /// The child's sessions that have not ended yet, cancelled ones included.
  List<Session> upcomingFor(String childId, DateTime now) {
    final group = child(childId)?.group?.id;
    if (group == null) return const [];
    return sessions.where((s) => s.groupId == group && s.endsAt.isAfter(now)).toList();
  }

  Session? nextFor(String childId, DateTime now) => upcomingFor(childId, now).where((s) => !s.cancelled).firstOrNull;

  /// Changed or cancelled sessions in the next seven days.
  List<Session> changesFor(String childId, DateTime now) {
    final until = dayOnly(now).add(const Duration(days: 8));
    return upcomingFor(childId, now).where((s) => s.status != SessionStatus.planned && s.date.isBefore(until)).toList();
  }

  /// Everyone told about these children's sessions: the caller first, each person once.
  List<ChildParent> get notifiedParents {
    final seen = <String>{};
    return [
      for (final p in parents)
        if (seen.add(p.parentId)) p,
    ];
  }

  Map<String, Object?> toJson() => {
    'children': [for (final c in children) c.toJson()],
    'sessions': [for (final s in sessions) s.toJson()],
    'staff_names': staffNames,
    'parents': [for (final p in parents) p.toJson()],
  };

  static ParentSnapshot fromJson(Map<String, dynamic> j) => ParentSnapshot(
    children: [for (final c in j['children'] as List) ParentChild.fromJson(c as Map<String, dynamic>)],
    sessions: [for (final s in j['sessions'] as List) Session.fromJson(s as Map<String, dynamic>)],
    staffNames: {
      for (final e in (j['staff_names'] as Map).entries)
        e.key as String: [for (final n in e.value as List) n as String],
    },
    parents: [for (final p in j['parents'] as List) ChildParent.fromJson(p as Map<String, dynamic>)],
  );
}

Map<String, Object?> groupToJson(Group g) => {
  'id': g.id,
  'name': g.name,
  'logo_letter': g.logoLetter,
  'logo_color': g.logoColor,
  'logo_path': g.logoPath,
  'age_min': g.ageMin,
  'age_max': g.ageMax,
};

Group groupFromJson(Map<String, dynamic> g) => Group(
  id: g['id'] as String,
  name: g['name'] as String,
  logoLetter: g['logo_letter'] as String,
  logoColor: g['logo_color'] as int,
  logoPath: g['logo_path'] as String?,
  ageMin: g['age_min'] as int?,
  ageMax: g['age_max'] as int?,
);
