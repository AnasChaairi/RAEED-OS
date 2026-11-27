import '../setup/models.dart';

/// The four attendance statuses. Late counts as attended; excused does not count towards an
/// absence alert.
enum AttendanceStatus {
  present('حاضر'),
  late('متأخر'),
  absent('غائب'),
  excused('معذور');

  const AttendanceStatus(this.label);

  final String label;

  static AttendanceStatus fromDb(String v) => values.firstWhere((s) => s.name == v);
}

enum SessionPlace { samae, away }

enum SessionStatus { planned, changed, cancelled }

/// The floors at جمعية سماء, as stored in sessions.floor.
const floors = <int, String>{-1: 'تحت الأرضي', 0: 'الأرضي', 1: 'الأول', 2: 'الثاني', 3: 'الثالث', 4: 'الرابع'};

/// Day names by Postgres day of week (0 is Sunday), as stored in session_series.weekdays.
const weekdayNames = ['الأحد', 'الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت'];
const monthNames = [
  'يناير',
  'فبراير',
  'مارس',
  'أبريل',
  'ماي',
  'يونيو',
  'يوليوز',
  'غشت',
  'شتنبر',
  'أكتوبر',
  'نونبر',
  'دجنبر',
];

/// 0 for Sunday, as Postgres counts.
int dayOfWeek(DateTime d) => d.weekday % 7;

DateTime dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// السبت 13 فبراير
String longDay(DateTime d) => '${weekdayNames[dayOfWeek(d)]} ${d.day} ${monthNames[d.month - 1]}';

String dbDay(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Minutes after midnight, the app's form of a Postgres time.
int parseTime(String v) {
  final parts = v.split(':');
  return int.parse(parts[0]) * 60 + int.parse(parts[1]);
}

String formatTime(int minutes) =>
    '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';

int? _timeOrNull(Object? v) => v == null ? null : parseTime(v as String);

class SessionMaterial {
  const SessionMaterial({required this.kind, required this.url, required this.label});

  /// youtube, drive or other.
  final String kind;
  final String url;
  final String label;

  static String kindOf(String url) {
    final host = Uri.tryParse(url)?.host ?? '';
    if (host.contains('youtube.com') || host.contains('youtu.be')) return 'youtube';
    if (host.contains('drive.google.com') || host.contains('docs.google.com')) return 'drive';
    return 'other';
  }

  String get kindLabel => switch (kind) {
    'youtube' => 'YouTube',
    'drive' => 'Drive',
    _ => 'رابط',
  };

  Map<String, Object?> toJson() => {'kind': kind, 'url': url, 'label': label};

  static SessionMaterial fromJson(Map<String, dynamic> j) =>
      SessionMaterial(kind: j['kind'] as String, url: j['url'] as String, label: j['label'] as String);
}

/// What an instructor types into the session form. The date is ignored when editing
/// "all upcoming".
class SessionDraft {
  const SessionDraft({
    required this.groupId,
    required this.title,
    required this.date,
    required this.start,
    required this.end,
    this.place = SessionPlace.samae,
    this.floor = 0,
    this.address,
    this.mapUrl,
    this.dropoffPlace,
    this.dropoffTime,
    this.pickupPlace,
    this.pickupTime,
    this.materials = const [],
    this.instructorIds = const [],
    this.remind = false,
  });

  final String groupId;
  final String title;
  final DateTime date;
  final int start;
  final int end;
  final SessionPlace place;
  final int? floor;
  final String? address;
  final String? mapUrl;
  final String? dropoffPlace;
  final int? dropoffTime;
  final String? pickupPlace;
  final int? pickupTime;
  final List<SessionMaterial> materials;

  /// Who runs the session: one or more of the group's instructors.
  final List<String> instructorIds;

  /// Remind its instructors and the children's parents 5 hours before it starts.
  final bool remind;

  bool get away => place == SessionPlace.away;

  /// The session columns, in the shape the server functions read.
  Map<String, Object?> toFields() => {
    'title': title,
    'session_date': dbDay(date),
    'start_time': formatTime(start),
    'end_time': formatTime(end),
    'place': place.name,
    'floor': away ? null : floor,
    'address': away ? address : null,
    'map_url': away ? mapUrl : null,
    'dropoff_place': away ? dropoffPlace : null,
    'dropoff_time': away && dropoffTime != null ? formatTime(dropoffTime!) : null,
    'pickup_place': away ? pickupPlace : null,
    'pickup_time': away && pickupTime != null ? formatTime(pickupTime!) : null,
    'remind': remind,
  };
}

class Session {
  const Session({
    required this.id,
    required this.groupId,
    this.seriesId,
    required this.title,
    required this.date,
    required this.start,
    required this.end,
    this.place = SessionPlace.samae,
    this.floor,
    this.address,
    this.mapUrl,
    this.dropoffPlace,
    this.dropoffTime,
    this.pickupPlace,
    this.pickupTime,
    this.status = SessionStatus.planned,
    this.cancelReason,
    this.materials = const [],
    this.instructorIds = const [],
    this.originalDate,
    this.originalStart,
    this.originalEnd,
    this.remind = false,
  });

  final String id;
  final String groupId;
  final String? seriesId;
  final String title;
  final DateTime date;
  final int start;
  final int end;
  final SessionPlace place;
  final int? floor;
  final String? address;
  final String? mapUrl;
  final String? dropoffPlace;
  final int? dropoffTime;
  final String? pickupPlace;
  final int? pickupTime;
  final SessionStatus status;
  final String? cancelReason;
  final List<SessionMaterial> materials;

  /// Who runs the session. Empty for sessions planned before the advisor picked them.
  final List<String> instructorIds;

  /// When the session was first planned, if it has since moved.
  final DateTime? originalDate;
  final int? originalStart;
  final int? originalEnd;

  /// A reminder goes to its instructors and parents 5 hours before it starts.
  final bool remind;

  bool get cancelled => status == SessionStatus.cancelled;
  bool get away => place == SessionPlace.away;
  DateTime get startsAt => date.add(Duration(minutes: start));
  DateTime get endsAt => date.add(Duration(minutes: end));

  /// جمعية سماء · الطابق الأول, or the address of a trip.
  String get placeLabel => away ? 'خارج المقر · ${address ?? ''}' : 'جمعية سماء · الطابق ${floors[floor] ?? ''}';

  String get timeLabel => '${formatTime(start)} – ${formatTime(end)}';

  /// "كان 17:00", or "كان الأربعاء 10 فبراير 17:00" when the day moved too. Null when the
  /// session is where it was first planned.
  String? get movedFrom {
    if (originalDate == null || originalStart == null) return null;
    if (originalDate == date && originalStart == start && originalEnd == end) return null;
    if (originalDate == date) return 'كان ${formatTime(originalStart!)}';
    return 'كان ${longDay(originalDate!)} ${formatTime(originalStart!)}';
  }

  SessionDraft toDraft() => SessionDraft(
    groupId: groupId,
    title: title,
    date: date,
    start: start,
    end: end,
    place: place,
    floor: floor ?? 0,
    address: address,
    mapUrl: mapUrl,
    dropoffPlace: dropoffPlace,
    dropoffTime: dropoffTime,
    pickupPlace: pickupPlace,
    pickupTime: pickupTime,
    materials: materials,
    instructorIds: instructorIds,
    remind: remind,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'group_id': groupId,
    'series_id': seriesId,
    'title': title,
    'session_date': dbDay(date),
    'start_time': formatTime(start),
    'end_time': formatTime(end),
    'place': place.name,
    'floor': floor,
    'address': address,
    'map_url': mapUrl,
    'dropoff_place': dropoffPlace,
    'dropoff_time': dropoffTime == null ? null : formatTime(dropoffTime!),
    'pickup_place': pickupPlace,
    'pickup_time': pickupTime == null ? null : formatTime(pickupTime!),
    'status': status.name,
    'cancel_reason': cancelReason,
    'materials': [for (final m in materials) m.toJson()],
    'instructor_ids': instructorIds,
    'original_date': originalDate == null ? null : dbDay(originalDate!),
    'original_start': originalStart == null ? null : formatTime(originalStart!),
    'original_end': originalEnd == null ? null : formatTime(originalEnd!),
    'remind': remind,
  };

  /// Reads a sessions row (with its materials and session_instructors) or [toJson]'s output.
  static Session fromJson(Map<String, dynamic> j) => Session(
    id: j['id'] as String,
    groupId: j['group_id'] as String,
    seriesId: j['series_id'] as String?,
    title: j['title'] as String,
    date: DateTime.parse(j['session_date'] as String),
    start: parseTime(j['start_time'] as String),
    end: parseTime(j['end_time'] as String),
    place: SessionPlace.values.byName(j['place'] as String),
    floor: j['floor'] as int?,
    address: j['address'] as String?,
    mapUrl: j['map_url'] as String?,
    dropoffPlace: j['dropoff_place'] as String?,
    dropoffTime: _timeOrNull(j['dropoff_time']),
    pickupPlace: j['pickup_place'] as String?,
    pickupTime: _timeOrNull(j['pickup_time']),
    status: SessionStatus.values.byName(j['status'] as String),
    cancelReason: j['cancel_reason'] as String?,
    materials: [
      for (final m in (j['materials'] as List? ?? const [])) SessionMaterial.fromJson(m as Map<String, dynamic>),
    ],
    instructorIds: [
      for (final i in (j['instructor_ids'] as List? ?? const [])) i as String,
      for (final i in (j['session_instructors'] as List? ?? const [])) (i as Map)['person_id'] as String,
    ],
    originalDate: j['original_date'] == null ? null : DateTime.parse(j['original_date'] as String),
    originalStart: _timeOrNull(j['original_start']),
    originalEnd: _timeOrNull(j['original_end']),
    remind: j['remind'] as bool? ?? false,
  );
}

class ParentContact {
  const ParentContact({required this.id, required this.fullName, required this.phone});

  final String id;
  final String fullName;
  final String phone;

  Map<String, Object?> toJson() => {'id': id, 'full_name': fullName, 'phone': phone};

  static ParentContact fromJson(Map<String, dynamic> j) =>
      ParentContact(id: j['id'] as String, fullName: j['full_name'] as String, phone: j['phone'] as String);
}

/// A child in one of the instructor's groups, with the parents to call.
class RosterChild {
  const RosterChild({required this.id, required this.fullName, required this.groupId, this.parents = const []});

  final String id;
  final String fullName;
  final String groupId;
  final List<ParentContact> parents;

  Map<String, Object?> toJson() => {
    'id': id,
    'full_name': fullName,
    'group_id': groupId,
    'parents': [for (final p in parents) p.toJson()],
  };

  static RosterChild fromJson(Map<String, dynamic> j) => RosterChild(
    id: j['id'] as String,
    fullName: j['full_name'] as String,
    groupId: j['group_id'] as String,
    parents: [for (final p in j['parents'] as List) ParentContact.fromJson(p as Map<String, dynamic>)],
  );
}

/// One child's status for one session. The id is made on the phone, so sending the same
/// record twice never makes two rows.
class AttendanceRecord {
  const AttendanceRecord({
    required this.id,
    required this.sessionId,
    required this.childId,
    required this.status,
    required this.recordedBy,
    required this.recordedAt,
  });

  final String id;
  final String sessionId;
  final String childId;
  final AttendanceStatus status;
  final String recordedBy;
  final DateTime recordedAt;

  Map<String, Object?> toJson() => {
    'id': id,
    'session_id': sessionId,
    'child_id': childId,
    'status': status.name,
    'recorded_by': recordedBy,
    'recorded_at': recordedAt.toUtc().toIso8601String(),
  };

  static AttendanceRecord fromJson(Map<String, dynamic> j) => AttendanceRecord(
    id: j['id'] as String,
    sessionId: j['session_id'] as String,
    childId: j['child_id'] as String,
    status: AttendanceStatus.fromDb(j['status'] as String),
    recordedBy: j['recorded_by'] as String,
    recordedAt: DateTime.parse(j['recorded_at'] as String).toLocal(),
  );
}

/// Raised by the server after two unexcused absences in a row.
class AbsenceAlert {
  const AbsenceAlert({
    required this.id,
    required this.childId,
    required this.groupId,
    required this.sessionIds,
    required this.createdAt,
    this.open = true,
    this.reachedParent,
    this.reason,
    this.closedBy,
    this.closedAt,
    this.lastAttemptAt,
    this.lastAttemptBy,
  });

  final String id;
  final String childId;
  final String groupId;

  /// The two missed sessions, latest first.
  final List<String> sessionIds;
  final DateTime createdAt;
  final bool open;
  final bool? reachedParent;
  final String? reason;
  final String? closedBy;
  final DateTime? closedAt;
  final DateTime? lastAttemptAt;
  final String? lastAttemptBy;

  Map<String, Object?> toJson() => {
    'id': id,
    'child_id': childId,
    'group_id': groupId,
    'session_ids': sessionIds,
    'created_at': createdAt.toUtc().toIso8601String(),
    'status': open ? 'open' : 'closed',
    'reached_parent': reachedParent,
    'reason': reason,
    'closed_by': closedBy,
    'closed_at': closedAt?.toUtc().toIso8601String(),
    'last_attempt_at': lastAttemptAt?.toUtc().toIso8601String(),
    'last_attempt_by': lastAttemptBy,
  };

  static AbsenceAlert fromJson(Map<String, dynamic> j) {
    DateTime? t(String k) => j[k] == null ? null : DateTime.parse(j[k] as String).toLocal();
    return AbsenceAlert(
      id: j['id'] as String,
      childId: j['child_id'] as String,
      groupId: j['group_id'] as String,
      sessionIds: [for (final s in j['session_ids'] as List) s as String],
      createdAt: t('created_at')!,
      open: j['status'] == 'open',
      reachedParent: j['reached_parent'] as bool?,
      reason: j['reason'] as String?,
      closedBy: j['closed_by'] as String?,
      closedAt: t('closed_at'),
      lastAttemptAt: t('last_attempt_at'),
      lastAttemptBy: j['last_attempt_by'] as String?,
    );
  }
}

class ChildNote {
  const ChildNote({required this.authorName, required this.body, required this.createdAt});

  final String authorName;
  final String body;
  final DateTime createdAt;
}

/// What an instructor of a session noted about it, for the category supervisor and the
/// advisors.
class SessionObservation {
  const SessionObservation({
    required this.id,
    required this.sessionId,
    required this.authorId,
    required this.authorName,
    required this.body,
    required this.createdAt,
  });

  final String id;
  final String sessionId;
  final String authorId;
  final String authorName;
  final String body;
  final DateTime createdAt;

  /// Reads a session_observations row with its author's name.
  static SessionObservation fromJson(Map<String, dynamic> j) => SessionObservation(
    id: j['id'] as String,
    sessionId: j['session_id'] as String,
    authorId: j['author_id'] as String,
    authorName: (j['people'] as Map?)?['full_name'] as String? ?? '',
    body: j['body'] as String,
    createdAt: DateTime.parse(j['created_at'] as String).toLocal(),
  );
}

/// An instructor's notice that they will miss a session, with the reason. The category
/// supervisor hears of it.
class InstructorAbsence {
  const InstructorAbsence({
    required this.id,
    required this.sessionId,
    required this.personId,
    required this.reason,
    required this.createdAt,
  });

  final String id;
  final String sessionId;
  final String personId;
  final String reason;
  final DateTime createdAt;

  Map<String, Object?> toJson() => {
    'id': id,
    'session_id': sessionId,
    'person_id': personId,
    'reason': reason,
    'created_at': createdAt.toUtc().toIso8601String(),
  };

  static InstructorAbsence fromJson(Map<String, dynamic> j) => InstructorAbsence(
    id: j['id'] as String,
    sessionId: j['session_id'] as String,
    personId: j['person_id'] as String,
    reason: j['reason'] as String,
    createdAt: DateTime.parse(j['created_at'] as String).toLocal(),
  );
}

/// How one instructor stands on one session they were given.
enum InstructorPresence {
  /// Still to come.
  upcoming('قادمة'),

  /// They said they would miss it.
  absent('غائب'),

  /// Over, with its attendance taken.
  present('حاضر'),

  /// Over, with no notice of absence but no attendance taken either.
  unrecorded('بلا حضور مسجّل');

  const InstructorPresence(this.label);
  final String label;
}

/// Everything the instructor's tabs show, kept on the phone so attendance works offline.
class InstructorSnapshot {
  const InstructorSnapshot({
    this.groups = const [],
    this.children = const [],
    this.sessions = const [],
    this.attendance = const [],
    this.alerts = const [],
    this.staffNames = const {},
    this.staffPhones = const {},
    this.absences = const [],
    this.termStart,
    this.activities = const [],
    this.activityAttendance = const [],
    this.breaks = const [],
  });

  final List<Group> groups;
  final List<RosterChild> children;

  /// Sorted by start.
  final List<Session> sessions;
  final List<AttendanceRecord> attendance;
  final List<AbsenceAlert> alerts;

  /// The instructors of these groups, by id.
  final Map<String, String> staffNames;

  /// Their phone numbers, by id, where the reader may see them.
  final Map<String, String> staffPhones;

  /// Instructors' notices of absence on these sessions.
  final List<InstructorAbsence> absences;
  final DateTime? termStart;

  /// The أنشطة نوعية of these groups, sorted by start.
  final List<SpecialActivity> activities;
  final List<ActivityAttendance> activityAttendance;

  /// Holidays, Ramadan and the academy's stops, for the month calendar.
  final List<CalendarBreak> breaks;

  SpecialActivity? activity(String id) => activities.where((a) => a.id == id).firstOrNull;

  /// The planned activity that replaces [s], if any.
  SpecialActivity? replacedBy(Session s) => activityReplacing(activities, s);

  /// The activities on [day], cancelled ones included.
  List<SpecialActivity> activitiesOn(DateTime day) => activities.where((a) => a.covers(day)).toList();

  /// The sessions [a] replaces, for the groups in this snapshot.
  List<Session> replacedSessions(SpecialActivity a) => sessions.where((s) => !s.cancelled && a.replaces(s)).toList();

  Map<String, AttendanceStatus> activityAttendanceFor(String activityId) => {
    for (final r in activityAttendance)
      if (r.activityId == activityId) r.childId: r.status,
  };

  /// The children of [a]'s groups that this snapshot holds.
  List<RosterChild> childrenOf(SpecialActivity a) => children.where((c) => a.groupIds.contains(c.groupId)).toList();

  /// [personId]'s notice of absence for [sessionId], if they gave one.
  InstructorAbsence? absenceOf(String sessionId, String? personId) =>
      absences.where((a) => a.sessionId == sessionId && a.personId == personId).firstOrNull;

  List<InstructorAbsence> absencesFor(String sessionId) => absences.where((a) => a.sessionId == sessionId).toList();

  /// [personId]'s presence on [s], which they were given. Two instructors may share a
  /// session and one takes the attendance, so any attendance counts for both.
  InstructorPresence presence(Session s, String personId, DateTime now) {
    if (absenceOf(s.id, personId) != null) return InstructorPresence.absent;
    if (s.endsAt.isAfter(now)) return InstructorPresence.upcoming;
    return attendanceFor(s.id).isEmpty ? InstructorPresence.unrecorded : InstructorPresence.present;
  }

  Group? group(String id) => groups.where((g) => g.id == id).firstOrNull;
  RosterChild? child(String id) => children.where((c) => c.id == id).firstOrNull;
  Session? session(String id) => sessions.where((s) => s.id == id).firstOrNull;

  List<RosterChild> childrenIn(String groupId) => children.where((c) => c.groupId == groupId).toList();

  List<Session> sessionsOn(DateTime day) => sessions.where((s) => s.date == dayOnly(day)).toList();

  List<Session> sessionsOf(String groupId) => sessions.where((s) => s.groupId == groupId).toList();

  Map<String, AttendanceRecord> attendanceFor(String sessionId) => {
    for (final a in attendance)
      if (a.sessionId == sessionId) a.childId: a,
  };

  List<AbsenceAlert> get openAlerts => alerts.where((a) => a.open).toList();

  /// The next session that has not ended, today or later. With [where], the next one
  /// that passes it.
  Session? nextSession(DateTime now, {String? groupId, bool Function(Session)? where}) => sessions
      .where(
        (s) =>
            !s.cancelled &&
            s.endsAt.isAfter(now) &&
            replacedBy(s) == null &&
            (groupId == null || s.groupId == groupId) &&
            (where == null || where(s)),
      )
      .firstOrNull;

  /// Whether [personId] runs [s]: they were picked for it, or nobody was picked and they
  /// teach its group. Only they take its attendance and write observations on it.
  bool runs(Session s, String? personId) {
    if (personId == null) return false;
    if (s.instructorIds.isNotEmpty) return s.instructorIds.contains(personId);
    return group(s.groupId)?.instructorIds.contains(personId) ?? false;
  }

  /// Attended (present or late) over recorded sessions, since the term started.
  double? attendanceRate(String childId) {
    final since = termStart;
    final mine = attendance.where((a) {
      if (a.childId != childId) return false;
      final s = session(a.sessionId);
      return s != null && !s.cancelled && (since == null || !s.date.isBefore(since));
    }).toList();
    if (mine.isEmpty) return null;
    return mine.where((a) => a.status == AttendanceStatus.present || a.status == AttendanceStatus.late).length /
        mine.length;
  }

  /// The number of parent accounts that hear about a change to this group.
  int parentCount(String groupId) => {for (final c in childrenIn(groupId)) ...c.parents.map((p) => p.id)}.length;

  InstructorSnapshot copyWith({List<AttendanceRecord>? attendance, List<ActivityAttendance>? activityAttendance}) =>
      InstructorSnapshot(
        groups: groups,
        children: children,
        sessions: sessions,
        attendance: attendance ?? this.attendance,
        alerts: alerts,
        staffNames: staffNames,
        staffPhones: staffPhones,
        absences: absences,
        termStart: termStart,
        activities: activities,
        activityAttendance: activityAttendance ?? this.activityAttendance,
        breaks: breaks,
      );

  Map<String, Object?> toJson() => {
    'groups': [
      for (final g in groups)
        {
          'id': g.id,
          'name': g.name,
          'logo_letter': g.logoLetter,
          'logo_color': g.logoColor,
          'logo_path': g.logoPath,
          'age_min': g.ageMin,
          'age_max': g.ageMax,
          'instructor_ids': g.instructorIds,
        },
    ],
    'children': [for (final c in children) c.toJson()],
    'sessions': [for (final s in sessions) s.toJson()],
    'attendance': [for (final a in attendance) a.toJson()],
    'alerts': [for (final a in alerts) a.toJson()],
    'staff_names': staffNames,
    'staff_phones': staffPhones,
    'absences': [for (final a in absences) a.toJson()],
    'term_start': termStart == null ? null : dbDay(termStart!),
    'activities': [for (final a in activities) a.toJson()],
    'activity_attendance': [for (final a in activityAttendance) a.toJson()],
    'breaks': [for (final b in breaks) b.toJson()],
  };

  static InstructorSnapshot fromJson(Map<String, dynamic> j) => InstructorSnapshot(
    groups: [
      for (final g in j['groups'] as List)
        Group(
          id: g['id'] as String,
          name: g['name'] as String,
          logoLetter: g['logo_letter'] as String,
          logoColor: g['logo_color'] as int,
          logoPath: g['logo_path'] as String?,
          ageMin: g['age_min'] as int?,
          ageMax: g['age_max'] as int?,
          instructorIds: [for (final i in g['instructor_ids'] as List) i as String],
        ),
    ],
    children: [for (final c in j['children'] as List) RosterChild.fromJson(c as Map<String, dynamic>)],
    sessions: [for (final s in j['sessions'] as List) Session.fromJson(s as Map<String, dynamic>)],
    attendance: [for (final a in j['attendance'] as List) AttendanceRecord.fromJson(a as Map<String, dynamic>)],
    alerts: [for (final a in j['alerts'] as List) AbsenceAlert.fromJson(a as Map<String, dynamic>)],
    staffNames: {for (final e in (j['staff_names'] as Map).entries) e.key as String: e.value as String},
    staffPhones: {for (final e in ((j['staff_phones'] as Map?) ?? {}).entries) e.key as String: e.value as String},
    absences: [
      for (final a in (j['absences'] as List?) ?? const []) InstructorAbsence.fromJson(a as Map<String, dynamic>),
    ],
    termStart: j['term_start'] == null ? null : DateTime.parse(j['term_start'] as String),
    activities: [
      for (final a in (j['activities'] as List?) ?? const []) SpecialActivity.fromJson(a as Map<String, dynamic>),
    ],
    activityAttendance: [
      for (final a in (j['activity_attendance'] as List?) ?? const [])
        ActivityAttendance.fromJson(a as Map<String, dynamic>),
    ],
    breaks: [for (final b in (j['breaks'] as List?) ?? const []) CalendarBreak.fromJson(b as Map<String, dynamic>)],
  );
}

/// The dates a weekly series makes: every chosen weekday from [first] to [until], both
/// included.
List<DateTime> seriesDates(DateTime first, DateTime until, Set<int> weekdays) {
  final out = <DateTime>[];
  for (var d = dayOnly(first); !d.isAfter(dayOnly(until)); d = DateTime(d.year, d.month, d.day + 1)) {
    if (weekdays.contains(dayOfWeek(d))) out.add(d);
  }
  return out;
}

/// The types of نشاط نوعي. [custom] carries the planner's own name for it.
enum ActivityKind {
  camp('مخيم', '⛺'),
  overnight('مبيت', '🌙'),
  outing('خرجة', '🚌'),
  custom('نشاط آخر', '⭐');

  const ActivityKind(this.label, this.emoji);

  final String label;
  final String emoji;
}

/// A نشاط نوعي: a camp, sleepover, outing or another kind, for one or more فئات, over
/// one or several days. It has priority: a حصة of one of its فئات that overlaps it is
/// replaced by it (shown crossed out, no attendance, no reminder).
class SpecialActivity {
  const SpecialActivity({
    required this.id,
    required this.kind,
    this.customLabel,
    required this.title,
    required this.place,
    this.mapUrl,
    this.meetingPlace,
    this.details,
    required this.startDate,
    required this.start,
    required this.endDate,
    required this.end,
    this.cancelled = false,
    this.cancelReason,
    this.groupIds = const [],
    this.createdBy,
  });

  final String id;
  final ActivityKind kind;
  final String? customLabel;
  final String title;
  final String place;
  final String? mapUrl;

  /// Where the children are dropped off and picked up, when it is not [place].
  final String? meetingPlace;

  /// What to bring, the cost, anything else for the parents.
  final String? details;
  final DateTime startDate;

  /// Minutes after midnight on [startDate].
  final int start;
  final DateTime endDate;

  /// Minutes after midnight on [endDate].
  final int end;
  final bool cancelled;
  final String? cancelReason;
  final List<String> groupIds;
  final String? createdBy;

  DateTime get startsAt => startDate.add(Duration(minutes: start));
  DateTime get endsAt => endDate.add(Duration(minutes: end));

  /// مخيم, مبيت, خرجة, or the planner's name for it.
  String get kindLabel =>
      kind == ActivityKind.custom && (customLabel ?? '').trim().isNotEmpty ? customLabel!.trim() : kind.label;

  /// The number of days it covers, 1 for a single day.
  int get dayCount => endDate.difference(startDate).inDays + 1;

  bool covers(DateTime day) => !dayOnly(day).isBefore(startDate) && !dayOnly(day).isAfter(endDate);

  /// What a حصة it replaces says: "ملغاة بسبب: ⛺ مخيم · مخيم الربيع".
  String get replacesLabel => 'ملغاة بسبب: ${kind.emoji} $kindLabel · $title';

  /// 1 on its first day, 2 on the second...
  int dayNumber(DateTime day) => dayOnly(day).difference(startDate).inDays + 1;

  /// السبت 13 فبراير · 09:00 – 17:00, or من السبت 13 فبراير 09:00 إلى الاثنين 15 فبراير 17:00.
  String get whenLabel => dayCount == 1
      ? '${longDay(startDate)} · ${formatTime(start)} – ${formatTime(end)}'
      : 'من ${longDay(startDate)} ${formatTime(start)} إلى ${longDay(endDate)} ${formatTime(end)}';

  /// Whether it replaces [s]: planned, for [s]'s فئة, and overlapping it in time.
  bool replaces(Session s) =>
      !cancelled && groupIds.contains(s.groupId) && startsAt.isBefore(s.endsAt) && endsAt.isAfter(s.startsAt);

  /// The columns in the shape create_activity and update_activity read.
  Map<String, Object?> toFields() => {
    'kind': kind.name,
    'custom_label': kind == ActivityKind.custom ? customLabel : null,
    'title': title,
    'place': place,
    'map_url': mapUrl,
    'meeting_place': meetingPlace,
    'details': details,
    'start_date': dbDay(startDate),
    'start_time': formatTime(start),
    'end_date': dbDay(endDate),
    'end_time': formatTime(end),
  };

  Map<String, Object?> toJson() => {
    'id': id,
    ...toFields(),
    'status': cancelled ? 'cancelled' : 'planned',
    'cancel_reason': cancelReason,
    'group_ids': groupIds,
    'created_by': createdBy,
  };

  /// Reads a special_activities row (with its activity_groups) or [toJson]'s output.
  static SpecialActivity fromJson(Map<String, dynamic> j) => SpecialActivity(
    id: j['id'] as String,
    kind: ActivityKind.values.byName(j['kind'] as String),
    customLabel: j['custom_label'] as String?,
    title: j['title'] as String,
    place: j['place'] as String,
    mapUrl: j['map_url'] as String?,
    meetingPlace: j['meeting_place'] as String?,
    details: j['details'] as String?,
    startDate: DateTime.parse(j['start_date'] as String),
    start: parseTime(j['start_time'] as String),
    endDate: DateTime.parse(j['end_date'] as String),
    end: parseTime(j['end_time'] as String),
    cancelled: j['status'] == 'cancelled',
    cancelReason: j['cancel_reason'] as String?,
    groupIds: [
      for (final g in (j['group_ids'] as List? ?? const [])) g as String,
      for (final g in (j['activity_groups'] as List? ?? const [])) (g as Map)['group_id'] as String,
    ],
    createdBy: j['created_by'] as String?,
  );
}

/// One child's status on one activity.
class ActivityAttendance {
  const ActivityAttendance({required this.activityId, required this.childId, required this.status});

  final String activityId;
  final String childId;
  final AttendanceStatus status;

  Map<String, Object?> toJson() => {'activity_id': activityId, 'child_id': childId, 'status': status.name};

  static ActivityAttendance fromJson(Map<String, dynamic> j) => ActivityAttendance(
    activityId: j['activity_id'] as String,
    childId: j['child_id'] as String,
    status: AttendanceStatus.fromDb(j['status'] as String),
  );
}

/// The first planned activity of [activities] that replaces [s], if any.
SpecialActivity? activityReplacing(List<SpecialActivity> activities, Session s) =>
    activities.where((a) => a.replaces(s)).firstOrNull;

/// What a [CalendarBreak] is: a school or national holiday, Ramadan, or the academy stopping.
enum BreakKind {
  holiday('عطلة'),
  ramadan('رمضان'),
  pause('توقف الأكاديمية');

  const BreakKind(this.label);
  final String label;

  static BreakKind parse(String? s) => switch (s) {
    'ramadan' => BreakKind.ramadan,
    'pause' => BreakKind.pause,
    _ => BreakKind.holiday,
  };
}

/// A stretch of days from the year's programme, shown on the month calendar. Only shown:
/// it cancels no حصة. With no [groupId] it is for every فئة.
class CalendarBreak {
  const CalendarBreak({
    required this.id,
    required this.kind,
    required this.title,
    required this.startDate,
    required this.endDate,
    this.groupId,
  });

  final String id;
  final BreakKind kind;
  final String title;
  final DateTime startDate;
  final DateTime endDate;
  final String? groupId;

  bool covers(DateTime day) => !dayOnly(day).isBefore(startDate) && !dayOnly(day).isAfter(endDate);

  /// Whether it concerns one of [groupIds] (every break with no فئة does).
  bool concerns(Iterable<String> groupIds) => groupId == null || groupIds.contains(groupId);

  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind.name,
    'title': title,
    'start_date': dbDay(startDate),
    'end_date': dbDay(endDate),
    'group_id': groupId,
  };

  static CalendarBreak fromJson(Map<String, dynamic> j) => CalendarBreak(
    id: j['id'] as String,
    kind: BreakKind.parse(j['kind'] as String?),
    title: j['title'] as String,
    startDate: DateTime.parse(j['start_date'] as String),
    endDate: DateTime.parse(j['end_date'] as String),
    groupId: j['group_id'] as String?,
  );
}
