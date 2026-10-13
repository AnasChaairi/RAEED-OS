import 'package:supabase_flutter/supabase_flutter.dart' hide Session;

import '../setup/models.dart';
import '../setup/setup_repository.dart';
import 'models.dart';

/// The instructor's reads and writes. Every call throws [SetupError]; offline shows as
/// [SetupFailure.offline].
abstract interface class InstructorRepository {
  /// The groups [personId] teaches, their children and parents, this term's sessions
  /// and attendance, and the alerts still open or closed in the last month.
  Future<InstructorSnapshot> load(String personId);

  /// Sends attendance saved on the phone. Sending a record twice is harmless.
  Future<void> pushAttendance(List<AttendanceRecord> records);

  /// One session, or a weekly series when [weekdays] is given. Returns the first id.
  Future<String> createSessions(SessionDraft draft, List<DateTime> dates, Set<int>? weekdays);

  /// Edits one session, or it and the later ones of its series.
  Future<void> updateSessions(String sessionId, SessionDraft draft, {required bool upcoming});
  Future<void> cancelSessions(String sessionId, String reason, {required bool upcoming});
  Future<void> setMaterials(String sessionId, List<SessionMaterial> materials);

  Future<List<ChildNote>> notesFor(String childId);
  Future<void> addNote(String childId, String body);

  /// A call that got no answer: the alert stays open and shows who tried and when.
  Future<void> logAttempt(String alertId);

  /// The parent was reached: closes the alert with the reason.
  Future<void> closeAlert(String alertId, String reason);

  /// How long the attendance sheet took, for the pilot metrics.
  Future<void> logSheet(String sessionId, int seconds);
}

class SupabaseInstructorRepository implements InstructorRepository {
  SupabaseInstructorRepository(this._db);

  final SupabaseClient _db;

  String get _me => _db.auth.currentUser!.id;

  @override
  Future<InstructorSnapshot> load(String personId) => guardSupabase(() async {
    final today = dayOnly(DateTime.now());
    final terms = await _db
        .from('terms')
        .select('starts_on')
        .lte('starts_on', dbDay(today))
        .gte('ends_on', dbDay(today))
        .limit(1);
    final termStart = terms.isEmpty ? null : DateTime.parse(terms.first['starts_on'] as String);
    final mine = await _db.from('group_instructors').select('group_id').eq('person_id', personId);
    final ids = [for (final r in mine) r['group_id'] as String];
    if (ids.isEmpty) return InstructorSnapshot(termStart: termStart);

    var from = today.subtract(const Duration(days: 30));
    if (termStart != null && termStart.isBefore(from)) from = termStart;
    final monthAgo = DateTime.now().subtract(const Duration(days: 30)).toUtc().toIso8601String();
    final results = await Future.wait([
      _db
          .from('groups')
          .select(
            'id, name, logo_letter, logo_color, logo_path, age_min, age_max, group_instructors(person_id, people(full_name))',
          )
          .inFilter('id', ids)
          .eq('archived', false)
          .order('name'),
      _db
          .from('child_groups')
          .select('group_id, children(id, full_name, child_parents(people(id, full_name, phone)))')
          .inFilter('group_id', ids)
          .isFilter('to_date', null),
      _db
          .from('sessions')
          .select('*, materials(kind, url, label)')
          .inFilter('group_id', ids)
          .gte('session_date', dbDay(from))
          .lte('session_date', dbDay(today.add(const Duration(days: 200))))
          .order('session_date')
          .order('start_time'),
      _db
          .from('absence_alerts')
          .select()
          .inFilter('group_id', ids)
          .or('status.eq.open,closed_at.gte.$monthAgo')
          .order('created_at', ascending: false),
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
          logoPath: g['logo_path'] as String?,
          ageMin: g['age_min'] as int?,
          ageMax: g['age_max'] as int?,
          instructorIds: [for (final i in staff) i['person_id'] as String],
        ),
      );
    }
    final children = [
      for (final m in results[1])
        if (m['children'] != null)
          RosterChild(
            id: m['children']['id'] as String,
            fullName: m['children']['full_name'] as String,
            groupId: m['group_id'] as String,
            parents: [
              for (final cp in m['children']['child_parents'] as List)
                if (cp['people'] != null) ParentContact.fromJson(cp['people'] as Map<String, dynamic>),
            ],
          ),
    ]..sort((a, b) => a.fullName.compareTo(b.fullName));
    final sessions = [for (final s in results[2]) Session.fromJson(s)];

    // Attendance for the sessions that have started, a hundred ids per request.
    final started = [
      for (final s in sessions)
        if (!s.date.isAfter(today)) s.id,
    ];
    final attendance = <AttendanceRecord>[];
    for (var i = 0; i < started.length; i += 100) {
      final rows = await _db
          .from('attendance')
          .select('id, session_id, child_id, status, recorded_by, recorded_at')
          .inFilter('session_id', started.sublist(i, i + 100 > started.length ? started.length : i + 100));
      attendance.addAll(rows.map(AttendanceRecord.fromJson));
    }

    return InstructorSnapshot(
      groups: groups,
      children: children,
      sessions: sessions,
      attendance: attendance,
      alerts: [for (final a in results[3]) AbsenceAlert.fromJson(a)],
      staffNames: staffNames,
      termStart: termStart,
    );
  });

  @override
  Future<void> pushAttendance(List<AttendanceRecord> records) => guardSupabase(() async {
    if (records.isEmpty) return;
    await _db.from('attendance').upsert([for (final r in records) r.toJson()], onConflict: 'session_id,child_id');
  });

  @override
  Future<String> createSessions(SessionDraft draft, List<DateTime> dates, Set<int>? weekdays) =>
      guardSupabase(() async {
        final id = await _db.rpc(
          'create_sessions',
          params: {
            'p_group': draft.groupId,
            'p_fields': draft.toFields(),
            'p_dates': [for (final d in dates) dbDay(d)],
            'p_weekdays': weekdays == null ? null : (weekdays.toList()..sort()),
            'p_materials': [for (final m in draft.materials) m.toJson()],
          },
        );
        return id as String;
      });

  @override
  Future<void> updateSessions(String sessionId, SessionDraft draft, {required bool upcoming}) => guardSupabase(
    () => _db.rpc(
      'update_sessions',
      params: {'p_session': sessionId, 'p_fields': draft.toFields(), 'p_upcoming': upcoming},
    ),
  );

  @override
  Future<void> cancelSessions(String sessionId, String reason, {required bool upcoming}) => guardSupabase(
    () => _db.rpc('cancel_sessions', params: {'p_session': sessionId, 'p_reason': reason, 'p_upcoming': upcoming}),
  );

  @override
  Future<void> setMaterials(String sessionId, List<SessionMaterial> materials) => guardSupabase(() async {
    await _db.from('materials').delete().eq('session_id', sessionId);
    if (materials.isEmpty) return;
    await _db.from('materials').insert([
      for (final m in materials) {...m.toJson(), 'session_id': sessionId},
    ]);
  });

  @override
  Future<List<ChildNote>> notesFor(String childId) => guardSupabase(() async {
    final rows = await _db
        .from('notes')
        .select('body, created_at, people(full_name)')
        .eq('child_id', childId)
        .order('created_at', ascending: false);
    return [
      for (final r in rows)
        ChildNote(
          authorName: (r['people'] as Map?)?['full_name'] as String? ?? '',
          body: r['body'] as String,
          createdAt: DateTime.parse(r['created_at'] as String).toLocal(),
        ),
    ];
  });

  @override
  Future<void> addNote(String childId, String body) =>
      guardSupabase(() => _db.from('notes').insert({'child_id': childId, 'author_id': _me, 'body': body}));

  @override
  Future<void> logAttempt(String alertId) => guardSupabase(
    () => _db
        .from('absence_alerts')
        .update({'last_attempt_at': DateTime.now().toUtc().toIso8601String(), 'last_attempt_by': _me})
        .eq('id', alertId),
  );

  @override
  Future<void> closeAlert(String alertId, String reason) => guardSupabase(
    () => _db
        .from('absence_alerts')
        .update({
          'status': 'closed',
          'reached_parent': true,
          'reason': reason,
          'closed_by': _me,
          'closed_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', alertId),
  );

  @override
  Future<void> logSheet(String sessionId, int seconds) => guardSupabase(
    () => _db.from('usage_events').insert({'kind': 'attendance_sheet', 'session_id': sessionId, 'seconds': seconds}),
  );
}
