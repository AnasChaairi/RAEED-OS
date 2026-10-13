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

  StatsData? get data => _data;
  bool get loading => _loading;
  SetupFailure? get failure => _failure;
  StatsPeriod get period => _period;
  DateTime now() => _clock();

  Stats? get stats => _data?.compute(_period, _clock());

  void choosePeriod(StatsPeriod p) {
    _period = p;
    notifyListeners();
  }

  Future<void> load() async {
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
