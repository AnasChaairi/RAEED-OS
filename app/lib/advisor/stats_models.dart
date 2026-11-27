import '../instructor/models.dart';
import '../setup/models.dart';

/// The period the statistics cover. They open on this month (decided 12 October).
enum StatsPeriod {
  week('هذا الأسبوع'),
  month('هذا الشهر'),
  term('الفصل');

  const StatsPeriod(this.label);

  final String label;
}

/// A session as the statistics need it.
class StatSession {
  const StatSession({
    required this.id,
    required this.groupId,
    required this.date,
    this.start,
    required this.end,
    this.cancelled = false,
    this.instructorIds = const [],
  });

  final String id;
  final String groupId;
  final DateTime date;

  /// Minutes after midnight; null reads as [end].
  final int? start;

  /// Minutes after midnight.
  final int end;
  final bool cancelled;

  /// The instructors picked for it; empty means the فئة's instructors run it.
  final List<String> instructorIds;

  DateTime get startsAt => date.add(Duration(minutes: start ?? end));
  DateTime get endsAt => date.add(Duration(minutes: end));
}

/// A planned نشاط نوعي: the حصص of its فئات that overlap it do not take place.
class StatActivity {
  const StatActivity({required this.groupIds, required this.startsAt, required this.endsAt});

  final List<String> groupIds;
  final DateTime startsAt;
  final DateTime endsAt;

  bool replaces(StatSession s) =>
      groupIds.contains(s.groupId) && startsAt.isBefore(s.endsAt) && endsAt.isAfter(s.startsAt);
}

/// A child is followed up when they missed more than this share of their recorded حصص.
const absenceThreshold = 0.25;

/// ...over at least this many recorded حصص, so one missed حصة is not 100%.
const absenceThresholdMinSessions = 3;

/// Absent, or late, this many times or more in the last [repeatedWindowDays] days is
/// "repeated".
const repeatedCount = 3;
const repeatedWindowDays = 30;

class StatMark {
  const StatMark({required this.sessionId, required this.childId, required this.status});

  final String sessionId;
  final String childId;
  final AttendanceStatus status;

  bool get attended => status == AttendanceStatus.present || status == AttendanceStatus.late;
}

class StatChild {
  const StatChild({required this.id, required this.fullName, required this.groupId});

  final String id;
  final String fullName;
  final String groupId;
}

/// What the server holds for the academy: groups, children, sessions since the term began
/// (or five weeks back), their attendance, and the open alerts.
class StatsData {
  const StatsData({
    this.groups = const [],
    this.staffNames = const {},
    this.instructorCount = 0,
    this.children = const [],
    this.sessions = const [],
    this.marks = const [],
    this.openAlertGroups = const [],
    this.termStart,
    this.termEnd,
    this.seasonStart,
    this.activities = const [],
    this.absences = const {},
  });

  final List<Group> groups;
  final Map<String, String> staffNames;
  final int instructorCount;
  final List<StatChild> children;
  final List<StatSession> sessions;
  final List<StatMark> marks;

  /// The group of each open absence alert.
  final List<String> openAlertGroups;
  final DateTime? termStart;
  final DateTime? termEnd;

  /// Where the monthly trend starts.
  final DateTime? seasonStart;

  /// Planned أنشطة نوعية: the حصص they replace are left out everywhere.
  final List<StatActivity> activities;

  /// Instructors who said they would be absent, as `session id/person id`.
  final Set<String> absences;

  bool replaced(StatSession s) => activities.any((a) => a.replaces(s));

  /// Whether [s] counts: not cancelled and not replaced by a نشاط نوعي.
  bool counts(StatSession s) => !s.cancelled && !replaced(s);

  /// The day after the last day [period] covers.
  DateTime periodEnd(StatsPeriod period, DateTime now) {
    final from = periodStart(period, now);
    return switch (period) {
      StatsPeriod.week => from.add(const Duration(days: 7)),
      StatsPeriod.month => DateTime(from.year, from.month + 1),
      StatsPeriod.term => termEnd?.add(const Duration(days: 1)) ?? dayOnly(now).add(const Duration(days: 1)),
    };
  }

  /// Who runs [s]: those picked for it, or else its فئة's instructors, less those who
  /// said they would be absent.
  List<String> runners(StatSession s) {
    final picked = s.instructorIds.isNotEmpty
        ? s.instructorIds
        : groups.where((g) => g.id == s.groupId).firstOrNull?.instructorIds ?? const <String>[];
    return [
      for (final p in picked)
        if (!absences.contains('${s.id}/$p')) p,
    ];
  }

  /// The first day [period] covers.
  DateTime periodStart(StatsPeriod period, DateTime now) {
    final today = dayOnly(now);
    return switch (period) {
      StatsPeriod.week => today.subtract(Duration(days: dayOfWeek(today))),
      StatsPeriod.month => DateTime(today.year, today.month),
      StatsPeriod.term => termStart ?? today.subtract(const Duration(days: 90)),
    };
  }

  /// Everything the statistics tab shows for [period].
  Stats compute(StatsPeriod period, DateTime now) {
    final from = periodStart(period, now);
    final until = periodEnd(period, now);
    final counted = sessions.where(counts).toList();
    final held = counted.where((s) => s.endsAt.isBefore(now) && !s.date.isBefore(from)).toList();
    final programmed = counted.where((s) => !s.date.isBefore(from) && s.date.isBefore(until)).toList();
    final heldIds = {for (final s in held) s.id};
    final marksIn = marks.where((m) => heldIds.contains(m.sessionId)).toList();
    final recordedIds = {for (final m in marksIn) m.sessionId};
    final sessionGroup = {for (final s in held) s.id: s.groupId};

    final rows = [
      for (final g in groups)
        () {
          final gSessions = held.where((s) => s.groupId == g.id).toList();
          final gMarks = marksIn.where((m) => sessionGroup[m.sessionId] == g.id).toList();
          return GroupStats(
            group: g,
            programmed: programmed.where((s) => s.groupId == g.id).length,
            children: children.where((c) => c.groupId == g.id).length,
            instructors: [for (final id in g.instructorIds) ?staffNames[id]],
            sessions: gSessions.length,
            recorded: gSessions.where((s) => recordedIds.contains(s.id)).length,
            rate: _rate(gMarks),
            openAlerts: openAlertGroups.where((a) => a == g.id).length,
          );
        }(),
    ]..sort((a, b) => (a.rate ?? 2).compareTo(b.rate ?? 2));

    // The last five weeks, Sunday to Saturday, oldest first.
    final thisWeek = periodStart(StatsPeriod.week, now);
    final weeks = <double?>[];
    for (var i = 4; i >= 0; i--) {
      final start = thisWeek.subtract(Duration(days: 7 * i));
      final end = start.add(const Duration(days: 7));
      final ids = {
        for (final s in counted)
          if (!s.date.isBefore(start) && s.date.isBefore(end) && s.endsAt.isBefore(now)) s.id,
      };
      weeks.add(_rate(marks.where((m) => ids.contains(m.sessionId))));
    }

    // Children: absence over the period, and what repeats in the last 30 days.
    final childById = {for (final c in children) c.id: c};
    final byChild = <String, List<StatMark>>{};
    for (final m in marksIn) {
      if (childById.containsKey(m.childId)) (byChild[m.childId] ??= []).add(m);
    }
    final overThreshold = <ChildCount>[
      for (final e in byChild.entries)
        if (e.value.length >= absenceThresholdMinSessions &&
            e.value.where((m) => !m.attended).length / e.value.length > absenceThreshold)
          ChildCount(child: childById[e.key]!, count: e.value.where((m) => !m.attended).length, of: e.value.length),
    ]..sort((a, b) => (b.count / b.of).compareTo(a.count / a.of));

    final windowStart = dayOnly(now).subtract(const Duration(days: repeatedWindowDays - 1));
    final recentIds = {
      for (final s in counted)
        if (!s.date.isBefore(windowStart) && s.endsAt.isBefore(now)) s.id,
    };
    final recent = <String, List<StatMark>>{};
    for (final m in marks) {
      if (recentIds.contains(m.sessionId) && childById.containsKey(m.childId)) (recent[m.childId] ??= []).add(m);
    }
    List<ChildCount> repeated(bool Function(StatMark) hit) => [
      for (final e in recent.entries)
        if (e.value.where(hit).length >= repeatedCount)
          ChildCount(child: childById[e.key]!, count: e.value.where(hit).length, of: e.value.length),
    ]..sort((a, b) => b.count.compareTo(a.count));

    // Instructors with a حصة that ended and has no attendance.
    final missing = <String, List<StatSession>>{};
    for (final s in held) {
      if (recordedIds.contains(s.id)) continue;
      for (final p in runners(s)) {
        (missing[p] ??= []).add(s);
      }
    }
    final unrecorded =
        [
          for (final e in missing.entries)
            InstructorGap(
              personId: e.key,
              name: staffNames[e.key] ?? '—',
              sessions: e.value..sort((a, b) => b.date.compareTo(a.date)),
            ),
        ]..sort(
          (a, b) => b.sessions.length != a.sessions.length
              ? b.sessions.length.compareTo(a.sessions.length)
              : a.name.compareTo(b.name),
        );

    return Stats(
      period: period,
      from: from,
      groupCount: groups.length,
      instructorCount: instructorCount,
      childCount: children.length,
      rate: _rate(marksIn),
      weeks: weeks,
      openAlerts: openAlertGroups.length,
      sessionsHeld: held.length,
      sessionsWithoutAttendance: held.length - recordedIds.length,
      groups: rows,
      programmed: programmed.length,
      overThreshold: overThreshold,
      repeatedAbsence: repeated((m) => !m.attended),
      repeatedLate: repeated((m) => m.status == AttendanceStatus.late),
      unrecorded: unrecorded,
      months: months(now),
    );
  }

  /// The rate of each month from the season's start (at most twelve months back) to
  /// this month, oldest first.
  List<MonthRate> months(DateTime now) {
    final first = seasonStart ?? termStart ?? dayOnly(now).subtract(const Duration(days: 35));
    var month = DateTime(first.year, first.month);
    final last = DateTime(now.year, now.month);
    if (last.difference(month).inDays > 340) month = DateTime(last.year, last.month - 11);
    final out = <MonthRate>[];
    while (!month.isAfter(last)) {
      final next = DateTime(month.year, month.month + 1);
      final ids = {
        for (final s in sessions)
          if (counts(s) && !s.date.isBefore(month) && s.date.isBefore(next) && s.endsAt.isBefore(now)) s.id,
      };
      final ms = marks.where((m) => ids.contains(m.sessionId)).toList();
      out.add(MonthRate(month: month, rate: _rate(ms), sessions: {for (final m in ms) m.sessionId}.length));
      month = next;
    }
    return out;
  }

  /// Attended over recorded for [childId] in [period], or null with nothing recorded.
  double? childRate(String childId, StatsPeriod period, DateTime now) {
    final from = periodStart(period, now);
    final ids = {
      for (final s in sessions)
        if (counts(s) && !s.date.isBefore(from)) s.id,
    };
    return _rate(marks.where((m) => m.childId == childId && ids.contains(m.sessionId)));
  }

  static double? _rate(Iterable<StatMark> marks) {
    final list = marks.toList();
    if (list.isEmpty) return null;
    return list.where((m) => m.attended).length / list.length;
  }
}

/// A child and how many times something happened, out of [of] recorded حصص.
class ChildCount {
  const ChildCount({required this.child, required this.count, required this.of});

  final StatChild child;
  final int count;
  final int of;
}

/// An instructor and the حصص they ran that ended without attendance.
class InstructorGap {
  const InstructorGap({required this.personId, required this.name, required this.sessions});

  final String personId;
  final String name;
  final List<StatSession> sessions;
}

/// One month of the trend; [sessions] counts the حصص with attendance.
class MonthRate {
  const MonthRate({required this.month, required this.rate, required this.sessions});

  final DateTime month;
  final double? rate;
  final int sessions;
}

class GroupStats {
  const GroupStats({
    required this.group,
    this.programmed = 0,
    required this.children,
    required this.instructors,
    required this.sessions,
    required this.recorded,
    required this.rate,
    required this.openAlerts,
  });

  final Group group;

  /// حصص planned in the whole period, cancelled and replaced ones left out.
  final int programmed;
  final int children;
  final List<String> instructors;

  /// Sessions held in the period, and how many of them have attendance.
  final int sessions;
  final int recorded;
  final double? rate;
  final int openAlerts;
}

class Stats {
  const Stats({
    required this.period,
    required this.from,
    required this.groupCount,
    required this.instructorCount,
    required this.childCount,
    required this.rate,
    required this.weeks,
    required this.openAlerts,
    required this.sessionsHeld,
    required this.sessionsWithoutAttendance,
    required this.groups,
    this.programmed = 0,
    this.overThreshold = const [],
    this.repeatedAbsence = const [],
    this.repeatedLate = const [],
    this.unrecorded = const [],
    this.months = const [],
  });

  final StatsPeriod period;
  final DateTime from;
  final int groupCount;
  final int instructorCount;
  final int childCount;

  /// Present and late over everything recorded, or null with nothing recorded.
  final double? rate;

  /// The rate in each of the last five weeks, oldest first.
  final List<double?> weeks;
  final int openAlerts;
  final int sessionsHeld;
  final int sessionsWithoutAttendance;

  /// Weakest first; groups with nothing recorded last.
  final List<GroupStats> groups;

  /// حصص planned in the whole period.
  final int programmed;

  /// Children who missed more than [absenceThreshold] of their حصص in the period.
  final List<ChildCount> overThreshold;

  /// Children absent, or late, [repeatedCount] times or more in the last 30 days.
  final List<ChildCount> repeatedAbsence;
  final List<ChildCount> repeatedLate;

  /// Instructors with حصص in the period that ended without attendance, most first.
  final List<InstructorGap> unrecorded;

  /// The monthly trend, oldest first.
  final List<MonthRate> months;

  /// The change from the month before the last month with a rate to that month, in
  /// points, or null with fewer than two months recorded.
  int? get monthChange {
    final rated = [
      for (final m in months)
        if (m.rate != null) m,
    ];
    if (rated.length < 2) return null;
    return ((rated.last.rate! - rated[rated.length - 2].rate!) * 100).round();
  }
}

/// 91%
String percent(double? rate) => rate == null ? '—' : '${(rate * 100).round()}%';

/// The pilot's success measures from the product definition, between two days.
class PilotMetrics {
  const PilotMetrics({
    this.sessionsHeld = 0,
    this.recordedWithin24h = 0,
    this.recordedLate = 0,
    this.groups = const [],
    this.medianSheetSeconds,
    this.sheetsTimed = 0,
    this.alertsDue = 0,
    this.alertsFollowedUp = 0,
    this.families = 0,
    this.familiesSignedIn = 0,
    this.advisors = const [],
  });

  factory PilotMetrics.fromJson(Map<String, dynamic> j) => PilotMetrics(
    sessionsHeld: j['sessions_held'] as int,
    recordedWithin24h: j['recorded_within_24h'] as int,
    recordedLate: j['recorded_late'] as int,
    groups: [
      for (final g in j['by_group'] as List)
        (groupId: g['group_id'] as String, held: g['held'] as int, onTime: g['on_time'] as int),
    ],
    medianSheetSeconds: (j['median_sheet_seconds'] as num?)?.round(),
    sheetsTimed: j['sheets_timed'] as int,
    alertsDue: j['alerts_due'] as int,
    alertsFollowedUp: j['alerts_followed_up'] as int,
    families: j['families'] as int,
    familiesSignedIn: j['families_signed_in'] as int,
    advisors: [
      for (final a in j['advisors'] as List)
        (
          name: a['full_name'] as String,
          weeksOpened: a['weeks_opened'] as int,
          lastOpened: a['last_opened'] == null ? null : DateTime.parse(a['last_opened'] as String).toLocal(),
        ),
    ],
  );

  /// Sessions that ended in the period, and how many had attendance within 24 hours.
  final int sessionsHeld;
  final int recordedWithin24h;
  final int recordedLate;
  final List<({String groupId, int held, int onTime})> groups;

  /// The median time from opening the attendance sheet to a first save.
  final int? medianSheetSeconds;
  final int sheetsTimed;

  /// Alerts at least seven days old or already followed up, and how many were followed
  /// up within seven days.
  final int alertsDue;
  final int alertsFollowedUp;

  /// Children with a parent account, and how many have a parent who signed in.
  final int families;
  final int familiesSignedIn;
  final List<({String name, int weeksOpened, DateTime? lastOpened})> advisors;

  double? get onTimeRate => sessionsHeld == 0 ? null : recordedWithin24h / sessionsHeld;
  double? get followUpRate => alertsDue == 0 ? null : alertsFollowedUp / alertsDue;
  double? get signedInRate => families == 0 ? null : familiesSignedIn / families;
}

/// The pilot's targets (product definition).
const pilotOnTimeTarget = 0.9;
const pilotSheetSecondsTarget = 180;
const pilotFollowUpTarget = 0.8;
const pilotSignedInTarget = 0.7;
