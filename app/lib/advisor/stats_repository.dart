import 'package:supabase_flutter/supabase_flutter.dart';

import '../instructor/models.dart';
import '../setup/models.dart';
import '../setup/setup_repository.dart';
import 'stats_models.dart';

/// The advisor's reads for the statistics. Throws [SetupError].
abstract interface class StatsRepository {
  Future<StatsData> load();

  /// The pilot measures for the days [from] to [to], both included.
  Future<PilotMetrics> pilotMetrics(DateTime from, DateTime to);

  /// Notes that the advisor opened the statistics, for the pilot metrics.
  Future<void> logView();
}

class SupabaseStatsRepository implements StatsRepository {
  SupabaseStatsRepository(this._db);

  final SupabaseClient _db;

  @override
  Future<StatsData> load() => guardSupabase(() async {
    final today = dayOnly(DateTime.now());
    final terms = await _db
        .from('terms')
        .select('starts_on, ends_on')
        .lte('starts_on', dbDay(today))
        .gte('ends_on', dbDay(today))
        .limit(1);
    final termStart = terms.isEmpty ? null : DateTime.parse(terms.first['starts_on'] as String);
    final termEnd = terms.isEmpty ? null : DateTime.parse(terms.first['ends_on'] as String);
    final seasons = await _db
        .from('seasons')
        .select('starts_on')
        .lte('starts_on', dbDay(today))
        .gte('ends_on', dbDay(today))
        .limit(1);
    final seasonStart = seasons.isEmpty ? null : DateTime.parse(seasons.first['starts_on'] as String);
    // Enough for the season's monthly trend (a year at most), this term, this month,
    // the five-week trend and the last 30 days.
    var from = today.subtract(Duration(days: 35 + dayOfWeek(today)));
    for (final d in [termStart, seasonStart]) {
      if (d != null && d.isBefore(from)) from = d;
    }
    final yearAgo = DateTime(today.year, today.month - 11);
    if (from.isBefore(yearAgo)) from = yearAgo;
    // ...and the rest of this week, month and term, for the حصص planned in them.
    var until = DateTime(today.year, today.month + 1).subtract(const Duration(days: 1));
    if (termEnd != null && termEnd.isAfter(until)) until = termEnd;

    final results = await Future.wait<List<dynamic>>([
      _db
          .from('groups')
          .select(
            'id, name, logo_letter, logo_color, logo_path, age_min, age_max, group_instructors(person_id, people(full_name))',
          )
          .eq('archived', false)
          .order('name'),
      _db.from('person_roles').select('person_id, people(full_name)').eq('role', 'instructor'),
      _db.from('child_groups').select('group_id, children(id, full_name)').isFilter('to_date', null),
      _all(
        () => _db
            .from('sessions')
            .select('id, group_id, session_date, start_time, end_time, status, session_instructors(person_id)')
            .gte('session_date', dbDay(from))
            .lte('session_date', dbDay(until))
            .order('id'),
      ),
      _db.from('absence_alerts').select('group_id').eq('status', 'open'),
    ]);

    final staffNames = <String, String>{
      for (final r in results[1])
        if ((r['people'] as Map?)?['full_name'] is String) r['person_id'] as String: r['people']['full_name'] as String,
    };
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
          logoPath: g['logo_path'] as String?,
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
          start: parseTime(s['start_time'] as String),
          end: parseTime(s['end_time'] as String),
          cancelled: s['status'] == 'cancelled',
          instructorIds: [for (final i in (s['session_instructors'] as List? ?? const [])) i['person_id'] as String],
        ),
    ];

    // Attendance of the حصص that ended, a hundred sessions per request.
    final now = DateTime.now();
    final ids = [
      for (final s in sessions)
        if (!s.cancelled && s.endsAt.isBefore(now)) s.id,
    ];
    final marks = <StatMark>[];
    for (var i = 0; i < ids.length; i += 100) {
      final chunk = ids.sublist(i, i + 100 > ids.length ? ids.length : i + 100);
      final rows = await _all(
        () => _db.from('attendance').select('session_id, child_id, status').inFilter('session_id', chunk).order('id'),
      );
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

    // أنشطة نوعية and instructors' notices, read apart: the app still opens before their
    // tables exist.
    final activities = <StatActivity>[];
    try {
      final rows = await _all(
        () => _db
            .from('special_activities')
            .select('start_date, start_time, end_date, end_time, activity_groups(group_id)')
            .eq('status', 'planned')
            .gte('end_date', dbDay(from))
            .lte('start_date', dbDay(until))
            .order('id'),
      );
      for (final a in rows) {
        activities.add(
          StatActivity(
            groupIds: [for (final g in a['activity_groups'] as List) g['group_id'] as String],
            startsAt: DateTime.parse(a['start_date'] as String)
                .add(Duration(minutes: parseTime(a['start_time'] as String))),
            endsAt: DateTime.parse(a['end_date'] as String).add(Duration(minutes: parseTime(a['end_time'] as String))),
          ),
        );
      }
    } on PostgrestException {
      activities.clear();
    }
    final absences = <String>{};
    try {
      for (var i = 0; i < ids.length; i += 100) {
        final chunk = ids.sublist(i, i + 100 > ids.length ? ids.length : i + 100);
        final rows = await _db
            .from('instructor_absences')
            .select('session_id, person_id')
            .inFilter('session_id', chunk);
        for (final r in rows) {
          absences.add('${r['session_id']}/${r['person_id']}');
        }
      }
    } on PostgrestException {
      absences.clear();
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
      termEnd: termEnd,
      seasonStart: seasonStart,
      activities: activities,
      absences: absences,
    );
  });

  /// Every row of [query], a thousand at a time (the server sends no more per request).
  /// [query] must be ordered.
  static Future<List<Map<String, dynamic>>> _all(PostgrestTransformBuilder<PostgrestList> Function() query) async {
    const page = 1000;
    final out = <Map<String, dynamic>>[];
    for (var at = 0; ; at += page) {
      final rows = await query().range(at, at + page - 1);
      out.addAll(rows);
      if (rows.length < page) return out;
    }
  }

  @override
  Future<PilotMetrics> pilotMetrics(DateTime from, DateTime to) => guardSupabase(() async {
    final j = await _db.rpc('pilot_metrics', params: {'p_from': dbDay(from), 'p_to': dbDay(to)});
    return PilotMetrics.fromJson(Map<String, dynamic>.from(j as Map));
  });

  @override
  Future<void> logView() => guardSupabase(() => _db.from('usage_events').insert({'kind': 'stats_view'}));
}
