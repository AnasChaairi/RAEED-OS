import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../setup/setup_repository.dart';
import 'parent_models.dart';
import 'parent_repository.dart';

/// The parent's schedule. Read online, with a copy on the phone so it opens without a
/// connection.
class ParentStore extends ChangeNotifier {
  ParentStore(this._repo, this._prefs, {DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final ParentRepository _repo;
  final SharedPreferences _prefs;
  final DateTime Function() _clock;

  String? _personId;
  ParentSnapshot _data = const ParentSnapshot();
  bool _loaded = false;
  bool _loading = false;
  bool _offline = false;
  SetupFailure? _loadFailure;
  String? _childId;

  ParentSnapshot get data => _data;
  bool get loaded => _loaded;
  bool get loading => _loading;
  bool get offline => _offline;
  SetupFailure? get loadFailure => _loadFailure;
  DateTime now() => _clock();

  /// The child whose schedule is showing.
  String? get childId =>
      _data.child(_childId ?? '') != null ? _childId : (_data.children.isEmpty ? null : _data.children.first.id);

  void showChild(String id) {
    _childId = id;
    notifyListeners();
  }

  String get _cacheKey => 'parent_cache_$_personId';

  /// Opens [personId]'s data: the copy on the phone at once, then the server's.
  Future<void> start(String personId) async {
    if (_personId != personId) {
      _personId = personId;
      _data = const ParentSnapshot();
      _loaded = false;
      _loadFailure = null;
      _childId = null;
      try {
        final cache = _prefs.getString(_cacheKey);
        if (cache != null) {
          _data = ParentSnapshot.fromJson(jsonDecode(cache) as Map<String, dynamic>);
          _loaded = true;
        }
      } catch (_) {
        // A copy from an older version of the app: wait for the server.
      }
      notifyListeners();
    }
    await refresh();
  }

  Future<void> refresh() async {
    if (_personId == null) return;
    _loading = true;
    notifyListeners();
    try {
      _data = await _repo.load(_personId!);
      _loaded = true;
      _offline = false;
      _loadFailure = null;
      await _prefs.setString(_cacheKey, jsonEncode(_data.toJson()));
    } on SetupError catch (e) {
      _offline = e.failure == SetupFailure.offline;
      if (!_loaded) _loadFailure = e.failure;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  void clear() {
    _personId = null;
    _data = const ParentSnapshot();
    _loaded = false;
    _childId = null;
    notifyListeners();
  }
}

class ParentScope extends InheritedNotifier<ParentStore> {
  const ParentScope({super.key, required ParentStore store, required super.child}) : super(notifier: store);

  static ParentStore of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<ParentScope>()!.notifier!;

  static ParentStore read(BuildContext context) => context.getInheritedWidgetOfExactType<ParentScope>()!.notifier!;
}
