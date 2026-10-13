import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../instructor/models.dart';
import '../setup/setup_repository.dart';

/// A stay in one فئة.
class GroupStay {
  const GroupStay({required this.groupName, required this.from, this.to});

  final String groupName;
  final DateTime from;
  final DateTime? to;
}

/// One recorded session.
class ProfileMark {
  const ProfileMark({required this.date, required this.title, required this.status});

  final DateTime date;
  final String title;
  final AttendanceStatus status;
}

/// An absence follow-up, as the profile's history shows it.
class ProfileAlert {
  const ProfileAlert({
    required this.createdAt,
    required this.open,
    this.reason,
    this.closedAt,
    this.closedByName,
    this.lastAttemptAt,
  });

  final DateTime createdAt;
  final bool open;
  final String? reason;
  final DateTime? closedAt;
  final String? closedByName;
  final DateTime? lastAttemptAt;
}

/// Everything about one child, for staff (ملف الطفل).
class ChildProfile {
  const ChildProfile({
    required this.id,
    required this.fullName,
    this.birthDate,
    this.stays = const [],
    this.parents = const [],
    this.marks = const [],
    this.notes = const [],
    this.alerts = const [],
    this.termStart,
  });

  final String id;
  final String fullName;
  final DateTime? birthDate;

  /// Oldest first.
  final List<GroupStay> stays;
  final List<ParentContact> parents;

  /// Oldest first.
  final List<ProfileMark> marks;
  final List<ChildNote> notes;
  final List<ProfileAlert> alerts;
  final DateTime? termStart;

  GroupStay? get currentStay => stays.where((s) => s.to == null).lastOrNull;

  int? ageOn(DateTime day) {
    final b = birthDate;
    if (b == null) return null;
    var age = day.year - b.year;
    if (day.month < b.month || (day.month == b.month && day.day < b.day)) age--;
    return age;
  }

  /// This term's marks, or the last 90 days' without a term.
  List<ProfileMark> termMarks(DateTime now) {
    final from = termStart ?? dayOnly(now).subtract(const Duration(days: 90));
    return marks.where((m) => !m.date.isBefore(from)).toList();
  }

  double? termRate(DateTime now) {
    final list = termMarks(now);
    if (list.isEmpty) return null;
    return list.where((m) => m.status == AttendanceStatus.present || m.status == AttendanceStatus.late).length /
        list.length;
  }
}

/// Reads a child's profile and adds notes. Throws [SetupError].
abstract interface class ProfileRepository {
  Future<ChildProfile> load(String childId);
  Future<void> addNote(String childId, String body);
}

class SupabaseProfileRepository implements ProfileRepository {
  SupabaseProfileRepository(this._db);

  final SupabaseClient _db;

  @override
  Future<ChildProfile> load(String childId) => guardSupabase(() async {
    final today = dayOnly(DateTime.now());
    final results = await Future.wait<Object?>([
      _db
          .from('children')
          .select(
            'id, full_name, birth_date, child_groups(from_date, to_date, groups(name)), child_parents(people(id, full_name, phone))',
          )
          .eq('id', childId)
          .single(),
      _db.from('attendance').select('status, sessions(session_date, title)').eq('child_id', childId),
      _db.from('notes').select('body, created_at, people(full_name)').eq('child_id', childId).order('created_at'),
      _db
          .from('absence_alerts')
          .select('status, reason, created_at, closed_at, last_attempt_at, closer:people!closed_by(full_name)')
          .eq('child_id', childId)
          .order('created_at'),
      _db.from('terms').select('starts_on').lte('starts_on', dbDay(today)).gte('ends_on', dbDay(today)).limit(1),
    ]);
    final c = results[0] as Map<String, dynamic>;
    DateTime? t(Object? v) => v == null ? null : DateTime.parse(v as String).toLocal();
    final terms = results[4] as List;
    return ChildProfile(
      id: c['id'] as String,
      fullName: c['full_name'] as String,
      birthDate: c['birth_date'] == null ? null : DateTime.parse(c['birth_date'] as String),
      stays: [
        for (final s in c['child_groups'] as List)
          GroupStay(
            groupName: (s['groups'] as Map?)?['name'] as String? ?? '',
            from: DateTime.parse(s['from_date'] as String),
            to: s['to_date'] == null ? null : DateTime.parse(s['to_date'] as String),
          ),
      ]..sort((a, b) => a.from.compareTo(b.from)),
      parents: [
        for (final cp in c['child_parents'] as List)
          if (cp['people'] != null) ParentContact.fromJson(cp['people'] as Map<String, dynamic>),
      ],
      marks: [
        for (final a in results[1] as List)
          if (a['sessions'] != null)
            ProfileMark(
              date: DateTime.parse(a['sessions']['session_date'] as String),
              title: a['sessions']['title'] as String,
              status: AttendanceStatus.fromDb(a['status'] as String),
            ),
      ]..sort((a, b) => a.date.compareTo(b.date)),
      notes: [
        for (final n in results[2] as List)
          ChildNote(
            authorName: (n['people'] as Map?)?['full_name'] as String? ?? '',
            body: n['body'] as String,
            createdAt: t(n['created_at'])!,
          ),
      ],
      alerts: [
        for (final a in results[3] as List)
          ProfileAlert(
            createdAt: t(a['created_at'])!,
            open: a['status'] == 'open',
            reason: a['reason'] as String?,
            closedAt: t(a['closed_at']),
            closedByName: (a['closer'] as Map?)?['full_name'] as String?,
            lastAttemptAt: t(a['last_attempt_at']),
          ),
      ],
      termStart: terms.isEmpty ? null : DateTime.parse(terms.first['starts_on'] as String),
    );
  });

  @override
  Future<void> addNote(String childId, String body) => guardSupabase(() async {
    await _db.from('notes').insert({'child_id': childId, 'author_id': _db.auth.currentUser!.id, 'body': body});
  });
}

/// Gives every screen the way to open a child's profile.
class ProfileScope extends InheritedWidget {
  const ProfileScope({super.key, required this.repo, required this.clock, required super.child});

  final ProfileRepository repo;
  final DateTime Function() clock;

  static ProfileScope of(BuildContext context) => context.getInheritedWidgetOfExactType<ProfileScope>()!;

  @override
  bool updateShouldNotify(ProfileScope old) => repo != old.repo;
}
