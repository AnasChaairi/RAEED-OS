import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'auth/app_session.dart';
import 'auth/auth_repository.dart';
import 'config.dart';
import 'setup/setup_repository.dart';
import 'setup/setup_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: AppConfig.supabaseUrl, publishableKey: AppConfig.supabasePublishableKey);
  final prefs = await SharedPreferences.getInstance();
  final client = Supabase.instance.client;
  final session = AppSession(SupabaseAuthRepository(client), prefs);
  runApp(RaeedApp(session: session, setup: SetupStore(SupabaseSetupRepository(client))));
  await session.start();
}
