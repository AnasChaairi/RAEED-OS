import 'dart:async';

import 'package:flutter/widgets.dart';

import '../setup/setup_repository.dart';
import 'stats_models.dart';
import 'stats_repository.dart';

/// The advisor's statistics. Read each time the tab opens; nothing is kept offline.
class StatsStore extends ChangeNotifier {
  StatsStore(this._repo, {DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final StatsRepository _repo;
  final DateTime Function() _clock;

  StatsData? _data;
  bool _loading = false;
  SetupFailure? _failure;
  StatsPeriod _period = StatsPeriod.month;
  bool _logged = false;
  PilotMetrics? _pilot;
  SetupFailure? _pilotFailure;

  StatsData? get data => _data;
  bool get loading => _loading;
  SetupFailure? get failure => _failure;
  StatsPeriod get period => _period;
  DateTime now() => _clock();

  PilotMetrics? get pilot => _pilot;
  SetupFailure? get pilotFailure => _pilotFailure;

  Stats? get stats => _data?.compute(_period, _clock());

  void choosePeriod(StatsPeriod p) {
    _period = p;
    _pilot = null;
    notifyListeners();
  }

  /// The pilot measures from the start of the chosen period to today.
  Future<void> loadPilot() async {
    _pilotFailure = null;
    notifyListeners();
    final today = _clock();
    final from = (_data ?? const StatsData()).periodStart(_period, today);
    try {
      _pilot = await _repo.pilotMetrics(from, today);
    } on SetupError catch (e) {
      _pilotFailure = e.failure;
    }
    notifyListeners();
  }

  Future<void> load() async {
    if (!_logged) {
      _logged = true;
      // Best effort: a visit made offline is not counted.
      unawaited(_repo.logView().catchError((_) {}));
    }
    _loading = true;
    _failure = null;
    notifyListeners();
    try {
      _data = await _repo.load();
    } on SetupError catch (e) {
      _failure = e.failure;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }
}

class StatsScope extends InheritedNotifier<StatsStore> {
  const StatsScope({super.key, required StatsStore store, required super.child}) : super(notifier: store);

  static StatsStore of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<StatsScope>()!.notifier!;

  static StatsStore read(BuildContext context) => context.getInheritedWidgetOfExactType<StatsScope>()!.notifier!;
}
