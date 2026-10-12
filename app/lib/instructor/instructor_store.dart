import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../setup/setup_repository.dart';
import 'instructor_repository.dart';
import 'models.dart';

/// The instructor's data. Everything is read online, and a copy is kept on the phone.
/// Attendance is the one thing written offline: it is saved on the phone first, then
/// sent by a waiting list as soon as there is a connection.
class InstructorStore extends ChangeNotifier {
  InstructorStore(this._repo, this._prefs, {this.retryEvery = const Duration(seconds: 30), DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final InstructorRepository _repo;
  final SharedPreferences _prefs;
  final DateTime Function() _clock;

  /// How long to wait before sending the waiting list again after a failure. Null turns
  /// the timer off (tests).
  final Duration? retryEvery;

  String? _personId;
  InstructorSnapshot _data = const InstructorSnapshot();
  bool _loaded = false;
  bool _loading = false;
  bool _offline = false;
  SetupFailure? _loadFailure;
  List<AttendanceRecord> _pending = [];
  Map<String, DateTime> _sent = {};
  Timer? _retry;

  InstructorSnapshot get data => _data;
  String? get personId => _personId;

  /// True once there is something to show, from the server or from the phone.
  bool get loaded => _loaded;
  bool get loading => _loading;

  /// The last try to reach the server failed for lack of a connection.
  bool get offline => _offline;
  SetupFailure? get loadFailure => _loadFailure;
  DateTime now() => _clock();

  /// Attendance saved on the phone and not yet on the server.
  List<AttendanceRecord> get pending => List.unmodifiable(_pending);

  /// Sessions whose attendance is waiting to be sent.
  Set<String> get waitingSessions => {for (final r in _pending) r.sessionId};

  /// When each session's attendance last reached the server, for this week.
  Map<String, DateTime> get sent => Map.unmodifiable(_sent);

  String get _cacheKey => 'instructor_cache_$_personId';
  String get _pendingKey => 'attendance_pending_$_personId';
  String get _sentKey => 'attendance_sent_$_personId';

  /// Opens [personId]'s data: the copy on the phone at once, then the server's.
  Future<void> start(String personId) async {
    if (_personId != personId) {
      _personId = personId;
      _data = const InstructorSnapshot();
      _loaded = false;
      _loadFailure = null;
      _readPhone();
      notifyListeners();
    }
    await refresh();
  }

  /// Sends anything waiting, then reloads from the server.
  Future<void> refresh() async {
    if (_personId == null) return;
    _loading = true;
    notifyListeners();
    try {
      await _send();
      final fresh = await _repo.load(_personId!);
      _data = _withPending(fresh);
      _loaded = true;
      _offline = false;
      _loadFailure = null;
      await _prefs.setString(_cacheKey, jsonEncode(_data.toJson()));
    } on SetupError catch (e) {
      if (e.failure == SetupFailure.offline) _offline = true;
      if (!_loaded) _loadFailure = e.failure;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Saves the sheet on the phone, then tries to send it.
  Future<void> saveAttendance(String sessionId, Map<String, AttendanceStatus> statuses) async {
    final existing = _data.attendanceFor(sessionId);
    final at = _clock();
    final records = [
      for (final e in statuses.entries)
        AttendanceRecord(
          id: existing[e.key]?.id ?? newId(),
          sessionId: sessionId,
          childId: e.key,
          status: e.value,
          recordedBy: _personId!,
          recordedAt: at,
        ),
    ];
    bool same(AttendanceRecord a, AttendanceRecord b) => a.sessionId == b.sessionId && a.childId == b.childId;
    _pending = [..._pending.where((p) => !records.any((r) => same(p, r))), ...records];
    _data = _data.copyWith(attendance: [..._data.attendance.where((a) => !records.any((r) => same(a, r))), ...records]);
    await _savePhone();
    notifyListeners();
    if (await _send()) await refresh();
  }

  /// Sends the waiting list now. True when nothing is left waiting.
  Future<bool> sendNow() async {
    final done = await _send();
    notifyListeners();
    if (done) await refresh();
    return done;
  }

  Future<bool> _send() async {
    if (_pending.isEmpty) return true;
    final batch = List.of(_pending);
    try {
      await _repo.pushAttendance(batch);
    } on SetupError catch (e) {
      if (e.failure == SetupFailure.offline) {
        _offline = true;
        _scheduleRetry();
        return false;
      }
      rethrow;
    }
    _offline = false;
    _pending = _pending.where((p) => !batch.contains(p)).toList();
    final at = _clock();
    for (final r in batch) {
      _sent[r.sessionId] = at;
    }
    _sent.removeWhere((_, t) => at.difference(t).inDays > 7);
    await _savePhone();
    return _pending.isEmpty;
  }

  void _scheduleRetry() {
    if (retryEvery == null || (_retry?.isActive ?? false)) return;
    _retry = Timer(retryEvery!, () => sendNow());
  }

  /// Throws [SetupError]. Returns the first session's id.
  Future<String> createSessions(SessionDraft draft, List<DateTime> dates, Set<int>? weekdays) async {
    final id = await _repo.createSessions(draft, dates, weekdays);
    await refresh();
    return id;
  }

  /// Throws [SetupError].
  Future<void> updateSession(Session s, SessionDraft draft, {required bool upcoming}) async {
    await _repo.updateSessions(s.id, draft, upcoming: upcoming);
    if (!_sameMaterials(s.materials, draft.materials)) await _repo.setMaterials(s.id, draft.materials);
    await refresh();
  }

  /// Throws [SetupError].
  Future<void> cancelSession(Session s, String reason, {required bool upcoming}) async {
    await _repo.cancelSessions(s.id, reason, upcoming: upcoming);
    await refresh();
  }

  /// Throws [SetupError].
  Future<List<ChildNote>> notesFor(String childId) => _repo.notesFor(childId);

  /// Throws [SetupError].
  Future<void> addNote(String childId, String body) => _repo.addNote(childId, body);

  /// Throws [SetupError].
  Future<void> logAttempt(AbsenceAlert a) async {
    await _repo.logAttempt(a.id);
    await refresh();
  }

  /// Throws [SetupError].
  Future<void> closeAlert(AbsenceAlert a, String reason) async {
    await _repo.closeAlert(a.id, reason);
    await refresh();
  }

  /// Signed out: forget the data in memory. The waiting list stays on the phone and is
  /// sent at the next sign-in.
  void clear() {
    _retry?.cancel();
    _personId = null;
    _data = const InstructorSnapshot();
    _loaded = false;
    _pending = [];
    _sent = {};
    notifyListeners();
  }

  InstructorSnapshot _withPending(InstructorSnapshot fresh) {
    if (_pending.isEmpty) return fresh;
    bool waiting(AttendanceRecord a) => _pending.any((p) => p.sessionId == a.sessionId && p.childId == a.childId);
    return fresh.copyWith(attendance: [...fresh.attendance.where((a) => !waiting(a)), ..._pending]);
  }

  void _readPhone() {
    try {
      final cache = _prefs.getString(_cacheKey);
      if (cache != null) {
        _data = InstructorSnapshot.fromJson(jsonDecode(cache) as Map<String, dynamic>);
        _loaded = true;
      }
      _pending = [
        for (final r in jsonDecode(_prefs.getString(_pendingKey) ?? '[]') as List)
          AttendanceRecord.fromJson(r as Map<String, dynamic>),
      ];
      _sent = {
        for (final e in (jsonDecode(_prefs.getString(_sentKey) ?? '{}') as Map).entries)
          e.key as String: DateTime.parse(e.value as String),
      };
      _data = _withPending(_data);
    } catch (_) {
      // A copy from an older version of the app: start again from the server.
      _data = const InstructorSnapshot();
      _loaded = false;
    }
  }

  Future<void> _savePhone() async {
    await _prefs.setString(_pendingKey, jsonEncode([for (final r in _pending) r.toJson()]));
    await _prefs.setString(_sentKey, jsonEncode({for (final e in _sent.entries) e.key: e.value.toIso8601String()}));
    await _prefs.setString(_cacheKey, jsonEncode(_data.toJson()));
  }

  static bool _sameMaterials(List<SessionMaterial> a, List<SessionMaterial> b) =>
      a.length == b.length &&
      [for (var i = 0; i < a.length; i++) a[i].url == b[i].url && a[i].label == b[i].label].every((x) => x);

  @override
  void dispose() {
    _retry?.cancel();
    super.dispose();
  }
}

final _random = Random.secure();

/// A random (version 4) UUID.
String newId() {
  final b = List<int>.generate(16, (_) => _random.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}
