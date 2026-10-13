import 'package:supabase_flutter/supabase_flutter.dart' hide Session;

import '../instructor/models.dart';
import '../setup/setup_repository.dart';
import 'parent_models.dart';

/// The parent's reads. Every call throws [SetupError]; offline shows as
/// [SetupFailure.offline].
abstract interface class ParentRepository {
  /// [personId]'s children, their groups' sessions from a week ago to two months ahead,
  /// the instructors' names, and who else is a parent of each child.
  Future<ParentSnapshot> load(String personId);
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
                .gte('session_date', dbDay(today.subtract(const Duration(days: 7))))
                .lte('session_date', dbDay(today.add(const Duration(days: 62))))
                .order('session_date')
                .order('start_time'),
      _db.rpc<List<dynamic>>('my_children_parents'),
      for (final g in groupIds) _db.rpc<List<dynamic>>('group_staff_names', params: {'g': g}),
    ]);
    return ParentSnapshot(
      children: children,
      sessions: [for (final s in results[0]) Session.fromJson(s as Map<String, dynamic>)],
      parents: [for (final p in results[1]) ChildParent.fromJson(p as Map<String, dynamic>)],
      staffNames: {
        for (var i = 0; i < groupIds.length; i++)
          groupIds[i]: [for (final n in results[i + 2]) (n as Map)['full_name'] as String],
      },
    );
  });
}
