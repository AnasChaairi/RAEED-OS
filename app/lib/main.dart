import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'advisor/stats_repository.dart';
import 'advisor/stats_store.dart';
import 'app.dart';
import 'auth/app_session.dart';
import 'auth/auth_repository.dart';
import 'config.dart';
import 'instructor/instructor_repository.dart';
import 'instructor/instructor_store.dart';
import 'notifications/push.dart';
import 'parent/parent_repository.dart';
import 'parent/parent_store.dart';
import 'profile/profile_repository.dart';
import 'setup/setup_repository.dart';
import 'setup/setup_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: AppConfig.supabaseUrl, publishableKey: AppConfig.supabasePublishableKey);
  final prefs = await SharedPreferences.getInstance();
  final client = Supabase.instance.client;
  final push = await FirebasePush.create(client);
  final session = AppSession(SupabaseAuthRepository(client), prefs)..beforeSignOut = push.unregister;
  runApp(RaeedApp(
    session: session,
    setup: SetupStore(SupabaseSetupRepository(client)),
    instructor: InstructorStore(SupabaseInstructorRepository(client), prefs),
    parent: ParentStore(SupabaseParentRepository(client), prefs),
    stats: StatsStore(SupabaseStatsRepository(client)),
    profiles: SupabaseProfileRepository(client),
    push: push,
  ));
  await session.start();
}
