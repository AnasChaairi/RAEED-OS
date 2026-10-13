import 'package:supabase_flutter/supabase_flutter.dart';

import '../instructor/models.dart';
import '../setup/models.dart';
import '../setup/setup_repository.dart';
import 'stats_models.dart';

/// The advisor's reads for the statistics. Throws [SetupError].
abstract interface class StatsRepository {
  Future<StatsData> load();
}

class SupabaseStatsRepository implements StatsRepository {
  SupabaseStatsRepository(this._db);

  final SupabaseClient _db;

  @override
  Future<StatsData> load() => guardSupabase(() async {
    final today = dayOnly(DateTime.now());
    final terms = await _db
        .from('terms')
        .select('starts_on')
        .lte('starts_on', dbDay(today))
        .gte('ends_on', dbDay(today))
        .limit(1);
    final termStart = terms.isEmpty ? null : DateTime.parse(terms.first['starts_on'] as String);
    // Enough for this term, this month, and the five-week trend.
    var from = today.subtract(Duration(days: 35 + dayOfWeek(today)));
    if (termStart != null && termStart.isBefore(from)) from = termStart;

    final results = await Future.wait<List<dynamic>>([
      _db
          .from('groups')
          .select(
            'id, name, logo_letter, logo_color, age_min, age_max, group_instructors(person_id, people(full_name))',
          )
          .eq('archived', false)
          .order('name'),
      _db.from('person_roles').select('person_id').eq('role', 'instructor'),
      _db.from('child_groups').select('group_id, children(id, full_name)').isFilter('to_date', null),
      _db
          .from('sessions')
          .select('id, group_id, session_date, end_time, status')
          .gte('session_date', dbDay(from))
          .lte('session_date', dbDay(today)),
      _db.from('absence_alerts').select('group_id').eq('status', 'open'),
    ]);

    final staffNames = <String, String>{};
    final groups = <Group>[];
    for (final g in results[0]) {
      final staff = g['group_instructors'] as List;
      for (final i in staff) {
        staffNames[i['person_id'] as String] = (i['people'] as Map?)?['full_name'] as String? ?? '';
      }
      groups.add(
        Group(
          id: g['id'] as String,
          name: g['name'] as String,
          logoLetter: g['logo_letter'] as String,
          logoColor: g['logo_color'] as int,
          ageMin: g['age_min'] as int?,
          ageMax: g['age_max'] as int?,
          instructorIds: [for (final i in staff) i['person_id'] as String],
        ),
      );
    }
    final sessions = [
      for (final s in results[3])
        StatSession(
          id: s['id'] as String,
          groupId: s['group_id'] as String,
          date: DateTime.parse(s['session_date'] as String),
          end: parseTime(s['end_time'] as String),
          cancelled: s['status'] == 'cancelled',
        ),
    ];

    // Attendance, a hundred sessions per request.
    final ids = [
      for (final s in sessions)
        if (!s.cancelled) s.id,
    ];
    final marks = <StatMark>[];
    for (var i = 0; i < ids.length; i += 100) {
      final rows = await _db
          .from('attendance')
          .select('session_id, child_id, status')
          .inFilter('session_id', ids.sublist(i, i + 100 > ids.length ? ids.length : i + 100));
      for (final r in rows) {
        marks.add(
          StatMark(
            sessionId: r['session_id'] as String,
            childId: r['child_id'] as String,
            status: AttendanceStatus.fromDb(r['status'] as String),
          ),
        );
      }
    }

    return StatsData(
      groups: groups,
      staffNames: staffNames,
      instructorCount: results[1].length,
      children: [
        for (final c in results[2])
          if (c['children'] != null)
            StatChild(
              id: c['children']['id'] as String,
              fullName: c['children']['full_name'] as String,
              groupId: c['group_id'] as String,
            ),
      ]..sort((a, b) => a.fullName.compareTo(b.fullName)),
      sessions: sessions,
      marks: marks,
      openAlertGroups: [for (final a in results[4]) a['group_id'] as String],
      termStart: termStart,
    );
  });
}
