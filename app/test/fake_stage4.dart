import 'dart:async';

import 'package:raeed_os/advisor/stats_models.dart';
import 'package:raeed_os/advisor/stats_repository.dart';
import 'package:raeed_os/advisor/stats_store.dart';
import 'package:raeed_os/instructor/models.dart';
import 'package:raeed_os/notifications/push.dart';
import 'package:raeed_os/parent/parent_models.dart';
import 'package:raeed_os/parent/parent_repository.dart';
import 'package:raeed_os/parent/parent_store.dart';
import 'package:raeed_os/profile/profile_repository.dart';
import 'package:raeed_os/setup/models.dart';
import 'package:raeed_os/setup/setup_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeParentRepository implements ParentRepository {
  ParentSnapshot data = const ParentSnapshot();
  bool offline = false;
  int loads = 0;

  @override
  Future<ParentSnapshot> load(String personId) async {
    loads++;
    if (offline) throw const SetupError(SetupFailure.offline);
    return data;
  }
}

class FakeStatsRepository implements StatsRepository {
  StatsData data = const StatsData();

  PilotMetrics pilot = const PilotMetrics();
  final pilotAsked = <(DateTime, DateTime)>[];
  int views = 0;

  @override
  Future<StatsData> load() async => data;

  @override
  Future<PilotMetrics> pilotMetrics(DateTime from, DateTime to) async {
    pilotAsked.add((from, to));
    return pilot;
  }

  @override
  Future<void> logView() async => views++;
}

class FakeProfileRepository implements ProfileRepository {
  final profiles = <String, ChildProfile>{};
  final added = <String>[];

  @override
  Future<ChildProfile> load(String childId) async {
    final p = profiles[childId] ?? ChildProfile(id: childId, fullName: 'طفل');
    return ChildProfile(
      id: p.id,
      fullName: p.fullName,
      birthDate: p.birthDate,
      stays: p.stays,
      parents: p.parents,
      marks: p.marks,
      notes: [
        ...p.notes,
        for (final body in added) ChildNote(authorName: 'أنا', body: body, createdAt: DateTime(2027, 2, 6, 9)),
      ],
      alerts: p.alerts,
      termStart: p.termStart,
    );
  }

  @override
  Future<void> addNote(String childId, String body) async => added.add(body);
}

/// Notifications on, with messages the test sends in.
class FakePush extends PushService {
  final controller = StreamController<PushMessage>.broadcast();
  PushState current = PushState.on;
  int registered = 0;
  int unregistered = 0;

  @override
  PushState get state => current;

  @override
  Stream<PushMessage> get messages => controller.stream;

  @override
  Future<void> register() async => registered++;

  @override
  Future<void> unregister() async => unregistered++;
}

/// The stage 4 parts of the app, empty unless given.
({ParentStore parent, StatsStore stats, ProfileRepository profiles, PushService push}) stage4(
  SharedPreferences prefs, {
  FakeParentRepository? parent,
  FakeStatsRepository? stats,
  FakeProfileRepository? profiles,
  PushService? push,
  DateTime Function()? clock,
}) => (
  parent: ParentStore(parent ?? FakeParentRepository(), prefs, clock: clock),
  stats: StatsStore(stats ?? FakeStatsRepository(), clock: clock),
  profiles: profiles ?? FakeProfileRepository(),
  push: push ?? NoPush(),
);

const starsGroup = Group(id: 'stars', name: 'فئة النجوم', logoLetter: 'ن', logoColor: 1, ageMin: 8, ageMax: 10);
const budsGroup = Group(id: 'buds', name: 'فئة البراعم', logoLetter: 'ب', logoColor: 2);
