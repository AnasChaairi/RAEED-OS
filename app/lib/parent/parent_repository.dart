import 'package:supabase_flutter/supabase_flutter.dart' hide Session;

import '../instructor/instructor_repository.dart' show loadCalendarBreaks;
import '../instructor/models.dart';
import '../setup/setup_repository.dart';
import 'parent_models.dart';

/// The parent's reads. Every call throws [SetupError]; offline shows as
/// [SetupFailure.offline].
abstract interface class ParentRepository {
  /// [personId]'s children, their groups' sessions from five weeks ago to four months ahead (the month calendar browses them),
  /// the instructors' names, and who else is a parent of each child.
  Future<ParentSnapshot> load(String personId);

  /// The signed-in parent reports that [childId] will miss [sessionId]. The session's
  /// instructors and the فئة's supervisors are notified.
  Future<void> reportAbsence(String sessionId, String childId, String reason);

  /// Takes back a notice of absence, before the session starts.
  Future<void> withdrawAbsence(String reportId);
}

class SupabaseParentRepository implements ParentRepository {
  SupabaseParentRepository(this._db);

  final SupabaseClient _db;

  @override
  Future<ParentSnapshot> load(String personId) => guardSupabase(() async {
    final rows = await _db
        .from('child_parents')
        .select(
          'children(id, full_name, child_groups(to_date, groups(id, name, logo_letter, logo_color, logo_path, age_min, age_max)))',
        )
        .eq('parent_id', personId);
    final children = <ParentChild>[];
    for (final r in rows) {
      final c = r['children'] as Map<String, dynamic>?;
      if (c == null) continue;
      final current = [
        for (final cg in c['child_groups'] as List)
          if (cg['to_date'] == null && cg['groups'] != null) cg['groups'] as Map<String, dynamic>,
      ];
      children.add(
        ParentChild(
          id: c['id'] as String,
          fullName: c['full_name'] as String,
          group: current.isEmpty ? null : groupFromJson(current.first),
        ),
      );
    }
    children.sort((a, b) => a.fullName.compareTo(b.fullName));
    final groupIds = {for (final c in children) ?c.group?.id}.toList();

    final today = dayOnly(DateTime.now());
    final results = await Future.wait<List<dynamic>>([
      groupIds.isEmpty
          ? Future.value(const <dynamic>[])
          : _db
                .from('sessions')
                .select('*, materials(kind, url, label)')
                .inFilter('group_id', groupIds)
                .gte('session_date', dbDay(today.subtract(const Duration(days: 35))))
                .lte('session_date', dbDay(today.add(const Duration(days: 124))))
                .order('session_date')
                .order('start_time'),
      _db.rpc<List<dynamic>>('my_children_parents'),
      for (final g in groupIds) _db.rpc<List<dynamic>>('group_staff_names', params: {'g': g}),
    ]);
    // أنشطة نوعية, read apart: the schedule still opens before their tables exist.
    final activities = <SpecialActivity>[];
    if (groupIds.isNotEmpty) {
      try {
        final links = await _db.from('activity_groups').select('activity_id').inFilter('group_id', groupIds);
        final ids = {for (final l in links) l['activity_id'] as String}.toList();
        if (ids.isNotEmpty) {
          final rows = await _db
              .from('special_activities')
              .select('*, activity_groups(group_id)')
              .inFilter('id', ids)
              .gte('end_date', dbDay(today.subtract(const Duration(days: 35))))
              .lte('start_date', dbDay(today.add(const Duration(days: 124))));
          activities.addAll(rows.map(SpecialActivity.fromJson));
          activities.sort((a, b) => a.startsAt.compareTo(b.startsAt));
        }
      } on PostgrestException {
        activities.clear();
      }
    }
    // Absence notices, read apart: the schedule still opens before their table exists.
    final absences = <ChildAbsenceReport>[];
    if (children.isNotEmpty) {
      try {
        final rows = await _db
            .from('child_absence_reports')
            .select('id, session_id, child_id, reported_by, reason, created_at')
            .inFilter('child_id', [for (final c in children) c.id]);
        absences.addAll(rows.map(ChildAbsenceReport.fromJson));
      } on PostgrestException {
        absences.clear();
      }
    }
    final breaks = groupIds.isEmpty
        ? const <CalendarBreak>[]
        : await loadCalendarBreaks(_db, today.subtract(const Duration(days: 35)), today.add(const Duration(days: 124)));
    return ParentSnapshot(
      absences: absences,
      breaks: breaks,
      activities: activities,
      children: children,
      sessions: [for (final s in results[0]) Session.fromJson(s as Map<String, dynamic>)],
      parents: [for (final p in results[1]) ChildParent.fromJson(p as Map<String, dynamic>)],
      staffNames: {
        for (var i = 0; i < groupIds.length; i++)
          groupIds[i]: [for (final n in results[i + 2]) (n as Map)['full_name'] as String],
      },
    );
  });

  @override
  Future<void> reportAbsence(String sessionId, String childId, String reason) => guardSupabase(
    () => _db.from('child_absence_reports').insert({
      'session_id': sessionId,
      'child_id': childId,
      'reported_by': _db.auth.currentUser!.id,
      'reason': reason,
    }),
  );

  @override
  Future<void> withdrawAbsence(String reportId) =>
      guardSupabase(() => _db.from('child_absence_reports').delete().eq('id', reportId));
}
