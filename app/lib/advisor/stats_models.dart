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
    required this.end,
    this.cancelled = false,
  });

  final String id;
  final String groupId;
  final DateTime date;

  /// Minutes after midnight.
  final int end;
  final bool cancelled;

  DateTime get endsAt => date.add(Duration(minutes: end));
}

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
    final held = sessions.where((s) => !s.cancelled && s.endsAt.isBefore(now) && !s.date.isBefore(from)).toList();
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
        for (final s in sessions)
          if (!s.cancelled && !s.date.isBefore(start) && s.date.isBefore(end) && s.endsAt.isBefore(now)) s.id,
      };
      weeks.add(_rate(marks.where((m) => ids.contains(m.sessionId))));
    }

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
    );
  }

  /// Attended over recorded for [childId] in [period], or null with nothing recorded.
  double? childRate(String childId, StatsPeriod period, DateTime now) {
    final from = periodStart(period, now);
    final ids = {
      for (final s in sessions)
        if (!s.cancelled && !s.date.isBefore(from)) s.id,
    };
    return _rate(marks.where((m) => m.childId == childId && ids.contains(m.sessionId)));
  }

  static double? _rate(Iterable<StatMark> marks) {
    final list = marks.toList();
    if (list.isEmpty) return null;
    return list.where((m) => m.attended).length / list.length;
  }
}

class GroupStats {
  const GroupStats({
    required this.group,
    required this.children,
    required this.instructors,
    required this.sessions,
    required this.recorded,
    required this.rate,
    required this.openAlerts,
  });

  final Group group;
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
}

/// 91%
String percent(double? rate) => rate == null ? '—' : '${(rate * 100).round()}%';
