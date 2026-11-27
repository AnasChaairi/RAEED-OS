import 'package:raeed_os/instructor/instructor_repository.dart';
import 'package:raeed_os/instructor/models.dart';
import 'package:raeed_os/setup/models.dart';
import 'package:raeed_os/setup/setup_repository.dart';

/// An in-memory stand-in for the instructor's Supabase calls. Absent twice in a row
/// raises an alert, like the server's trigger.
class FakeInstructorRepository implements InstructorRepository {
  final groups = <Group>[];
  final children = <RosterChild>[];
  final sessions = <Session>[];
  final attendance = <String, AttendanceRecord>{};
  final alerts = <AbsenceAlert>[];
  final staffNames = <String, String>{};
  final calls = <String>[];
  final notes = <String, List<ChildNote>>{};
  final observations = <SessionObservation>[];
  final staffPhones = <String, String>{};
  final absences = <InstructorAbsence>[];
  final activities = <SpecialActivity>[];
  final breaks = <CalendarBreak>[];
  final activityAttendance = <String, ActivityAttendance>{};

  /// Who is signed in, for writes that take it from the session.
  String me = 'me';

  /// Sessions whose attendance the server refuses, as for an instructor not picked.
  final refused = <String>{};
  bool offline = false;
  int _ids = 0;

  void _check() {
    if (offline) throw const SetupError(SetupFailure.offline);
  }

  @override
  Future<InstructorSnapshot> load(String personId, {StaffView view = StaffView.teaching}) async {
    _check();
    final mine = groups
        .where(
          (g) => switch (view) {
            StaffView.all => true,
            StaffView.supervising => g.supervisorIds.contains(personId),
            StaffView.teaching => g.instructorIds.contains(personId),
          },
        )
        .map((g) => g.id)
        .toSet();
    final list = sessions.where((s) => mine.contains(s.groupId)).toList()
      ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
    return InstructorSnapshot(
      groups: groups.where((g) => mine.contains(g.id)).toList(),
      children: children.where((c) => mine.contains(c.groupId)).toList(),
      sessions: list,
      attendance: attendance.values.toList(),
      alerts: alerts.where((a) => mine.contains(a.groupId)).toList(),
      staffNames: staffNames,
      staffPhones: staffPhones,
      absences: absences.where((a) => list.any((s) => s.id == a.sessionId)).toList(),
      activities: (activities.where((a) => a.groupIds.any(mine.contains)).toList()
        ..sort((a, b) => a.startsAt.compareTo(b.startsAt))),
      activityAttendance: activityAttendance.values.toList(),
      breaks: breaks,
    );
  }

  @override
  Future<void> pushAttendance(List<AttendanceRecord> records) async {
    _check();
    calls.add('pushAttendance ${records.length}');
    if (records.any((r) => refused.contains(r.sessionId))) throw const SetupError(SetupFailure.notAllowed);
    for (final r in records) {
      attendance['${r.sessionId}/${r.childId}'] = r;
      if (r.status == AttendanceStatus.absent) _maybeAlert(r);
    }
  }

  void _maybeAlert(AttendanceRecord r) {
    final group = sessions.firstWhere((s) => s.id == r.sessionId).groupId;
    final recorded =
        sessions
            .where((s) => s.groupId == group && !s.cancelled && attendance.containsKey('${s.id}/${r.childId}'))
            .toList()
          ..sort((a, b) => b.startsAt.compareTo(a.startsAt));
    final lastTwo = recorded.take(2).toList();
    if (lastTwo.length == 2 &&
        lastTwo.every((s) => attendance['${s.id}/${r.childId}']!.status == AttendanceStatus.absent) &&
        !alerts.any((a) => a.childId == r.childId && a.open)) {
      alerts.add(
        AbsenceAlert(
          id: 'alert-${++_ids}',
          childId: r.childId,
          groupId: group,
          sessionIds: [for (final s in lastTwo) s.id],
          createdAt: DateTime.now(),
        ),
      );
    }
  }

  @override
  Future<String> createSessions(SessionDraft d, List<DateTime> dates, Set<int>? weekdays) async {
    _check();
    calls.add('createSessions ${dates.length} ${weekdays == null ? 'once' : 'weekly'}');
    final series = weekdays == null ? null : 'series-${++_ids}';
    String? first;
    for (final date in dates) {
      final id = 'session-${++_ids}';
      first ??= id;
      sessions.add(
        Session(
          id: id,
          groupId: d.groupId,
          seriesId: series,
          title: d.title,
          date: date,
          start: d.start,
          end: d.end,
          place: d.place,
          floor: d.away ? null : d.floor,
          address: d.away ? d.address : null,
          pickupPlace: d.away ? d.pickupPlace : null,
          pickupTime: d.away ? d.pickupTime : null,
          materials: id == first ? d.materials : const [],
          instructorIds: d.instructorIds,
          remind: d.remind,
        ),
      );
    }
    return first!;
  }

  @override
  Future<void> updateSessions(String sessionId, SessionDraft d, {required bool upcoming}) async {
    _check();
    calls.add('updateSessions $sessionId ${upcoming ? 'upcoming' : 'one'}');
    final s = sessions.firstWhere((x) => x.id == sessionId);
    for (var i = 0; i < sessions.length; i++) {
      final t = sessions[i];
      final hit = upcoming && s.seriesId != null ? t.seriesId == s.seriesId && !t.date.isBefore(s.date) : t.id == s.id;
      if (!hit) continue;
      sessions[i] = Session(
        id: t.id,
        groupId: t.groupId,
        seriesId: t.seriesId,
        title: d.title,
        date: upcoming ? t.date : d.date,
        start: d.start,
        end: d.end,
        place: d.place,
        floor: d.floor,
        status: SessionStatus.changed,
        materials: t.materials,
        instructorIds: d.instructorIds,
        remind: d.remind,
      );
    }
  }

  @override
  Future<void> cancelSessions(String sessionId, String reason, {required bool upcoming}) async {
    _check();
    calls.add('cancelSessions $sessionId ${upcoming ? 'upcoming' : 'one'}');
    final i = sessions.indexWhere((x) => x.id == sessionId);
    final t = sessions[i];
    sessions[i] = Session(
      id: t.id,
      groupId: t.groupId,
      seriesId: t.seriesId,
      title: t.title,
      date: t.date,
      start: t.start,
      end: t.end,
      floor: t.floor,
      status: SessionStatus.cancelled,
      cancelReason: reason,
    );
  }

  @override
  Future<void> deleteSessions(Session s, {required bool upcoming}) async {
    _check();
    calls.add('deleteSessions ${s.id} ${upcoming ? 'upcoming' : 'one'}');
    sessions.removeWhere(
      (x) => x.id == s.id || (upcoming && s.seriesId != null && x.seriesId == s.seriesId && !x.date.isBefore(s.date)),
    );
  }

  @override
  Future<void> setMaterials(String sessionId, List<SessionMaterial> materials) async {
    _check();
    calls.add('setMaterials $sessionId ${materials.length}');
  }

  @override
  Future<List<ChildNote>> notesFor(String childId) async {
    _check();
    return notes[childId] ?? const [];
  }

  @override
  Future<void> addNote(String childId, String body) async {
    _check();
    calls.add('addNote $childId');
    (notes[childId] ??= []).add(ChildNote(authorName: 'أنا', body: body, createdAt: DateTime.now()));
  }

  @override
  Future<void> logAttempt(String alertId) async {
    _check();
    calls.add('logAttempt $alertId');
    final i = alerts.indexWhere((a) => a.id == alertId);
    final a = alerts[i];
    alerts[i] = AbsenceAlert(
      id: a.id,
      childId: a.childId,
      groupId: a.groupId,
      sessionIds: a.sessionIds,
      createdAt: a.createdAt,
      lastAttemptAt: DateTime.now(),
      lastAttemptBy: 'me',
    );
  }

  @override
  Future<void> closeAlert(String alertId, String reason) async {
    _check();
    calls.add('closeAlert $alertId $reason');
    final i = alerts.indexWhere((a) => a.id == alertId);
    final a = alerts[i];
    alerts[i] = AbsenceAlert(
      id: a.id,
      childId: a.childId,
      groupId: a.groupId,
      sessionIds: a.sessionIds,
      createdAt: a.createdAt,
      open: false,
      reachedParent: true,
      reason: reason,
      closedAt: DateTime.now(),
    );
  }

  /// Timed attendance sheets, as "sessionId seconds".
  final sheets = <String>[];

  @override
  Future<void> logSheet(String sessionId, int seconds) async {
    _check();
    sheets.add('$sessionId $seconds');
  }

  @override
  Future<List<SessionObservation>> observationsFor(String sessionId) async {
    _check();
    return observations.where((o) => o.sessionId == sessionId).toList().reversed.toList();
  }

  @override
  Future<List<SessionObservation>> recentObservations(List<String> groupIds, DateTime since) async {
    _check();
    return observations
        .where((o) => groupIds.contains(sessions.firstWhere((s) => s.id == o.sessionId).groupId))
        .toList()
        .reversed
        .toList();
  }

  @override
  Future<void> addObservation(String sessionId, String body) async {
    _check();
    calls.add('addObservation $sessionId $body');
    observations.add(
      SessionObservation(
        id: 'o${_ids++}',
        sessionId: sessionId,
        authorId: 'me',
        authorName: 'أنا',
        body: body,
        createdAt: DateTime(2026, 10, 1),
      ),
    );
  }

  @override
  Future<void> deleteObservation(String id) async {
    _check();
    observations.removeWhere((o) => o.id == id);
  }

  @override
  Future<void> reportAbsence(String sessionId, String reason) async {
    _check();
    calls.add('reportAbsence $sessionId $reason');
    absences.add(
      InstructorAbsence(
        id: 'a${_ids++}',
        sessionId: sessionId,
        personId: me,
        reason: reason,
        createdAt: DateTime(2026, 10, 1),
      ),
    );
  }

  @override
  Future<void> withdrawAbsence(String absenceId) async {
    _check();
    calls.add('withdrawAbsence $absenceId');
    absences.removeWhere((a) => a.id == absenceId);
  }

  SpecialActivity _withId(SpecialActivity d, String id, {bool? cancelled, String? reason}) => SpecialActivity(
    id: id,
    kind: d.kind,
    customLabel: d.customLabel,
    title: d.title,
    place: d.place,
    mapUrl: d.mapUrl,
    meetingPlace: d.meetingPlace,
    details: d.details,
    startDate: d.startDate,
    start: d.start,
    endDate: d.endDate,
    end: d.end,
    cancelled: cancelled ?? d.cancelled,
    cancelReason: reason ?? d.cancelReason,
    groupIds: d.groupIds,
  );

  @override
  Future<String> createActivity(SpecialActivity draft) async {
    _check();
    final id = 'act${_ids++}';
    calls.add('createActivity ${draft.title} ${(draft.groupIds.toList()..sort()).join(',')}');
    activities.add(_withId(draft, id));
    return id;
  }

  @override
  Future<void> updateActivity(SpecialActivity draft) async {
    _check();
    calls.add('updateActivity ${draft.id} ${draft.title}');
    final i = activities.indexWhere((a) => a.id == draft.id);
    activities[i] = _withId(draft, draft.id);
  }

  @override
  Future<void> cancelActivity(String activityId, String reason) async {
    _check();
    calls.add('cancelActivity $activityId $reason');
    final i = activities.indexWhere((a) => a.id == activityId);
    activities[i] = _withId(activities[i], activityId, cancelled: true, reason: reason);
  }

  @override
  Future<void> deleteActivity(String activityId) async {
    _check();
    calls.add('deleteActivity $activityId');
    activities.removeWhere((a) => a.id == activityId);
  }

  @override
  Future<void> saveActivityAttendance(String activityId, Map<String, AttendanceStatus> statuses) async {
    _check();
    calls.add('saveActivityAttendance $activityId ${statuses.length}');
    for (final e in statuses.entries) {
      activityAttendance['$activityId/${e.key}'] = ActivityAttendance(
        activityId: activityId,
        childId: e.key,
        status: e.value,
      );
    }
  }
}

/// A group of three children taught by [me], with a session today at 10:00 and one a
/// week before.
FakeInstructorRepository seededInstructorRepo({required String me, required DateTime today}) {
  final repo = FakeInstructorRepository()..me = me;
  repo.groups.add(
    const Group(
      id: 'stars',
      name: 'فئة النجوم',
      logoLetter: 'ن',
      logoColor: 1,
      ageMin: 8,
      ageMax: 10,
    ).withInstructors([me, 'sara']),
  );
  repo.staffNames.addAll({me: 'ياسين', 'sara': 'سارة الإدريسي'});
  repo.children.addAll(const [
    RosterChild(
      id: 'adam',
      fullName: 'آدم بنعلي',
      groupId: 'stars',
      parents: [ParentContact(id: 'karim', fullName: 'كريم بنعلي', phone: '+212612345678')],
    ),
    RosterChild(id: 'omar', fullName: 'عمر الفاسي', groupId: 'stars'),
    RosterChild(id: 'youssef', fullName: 'يوسف العلوي', groupId: 'stars'),
  ]);
  repo.sessions.addAll([
    Session(
      id: 'last-week',
      groupId: 'stars',
      seriesId: 'weekly',
      title: 'مراجعة الحفظ',
      date: today.subtract(const Duration(days: 7)),
      start: 600,
      end: 690,
      floor: 1,
    ),
    Session(
      id: 'today',
      groupId: 'stars',
      seriesId: 'weekly',
      title: 'حفظ سورة الملك',
      date: today,
      start: 600,
      end: 690,
      floor: 1,
    ),
    Session(
      id: 'next-week',
      groupId: 'stars',
      seriesId: 'weekly',
      title: 'حفظ سورة الملك',
      date: today.add(const Duration(days: 7)),
      start: 600,
      end: 690,
      floor: 1,
    ),
  ]);
  return repo;
}

extension GroupStaff on Group {
  Group withInstructors(List<String> ids, {List<String>? supervisors}) => Group(
    id: id,
    name: name,
    logoLetter: logoLetter,
    logoColor: logoColor,
    ageMin: ageMin,
    ageMax: ageMax,
    instructorIds: ids,
    supervisorIds: supervisors ?? supervisorIds,
  );
}
