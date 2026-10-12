import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'auth/app_session.dart';
import 'auth/auth_repository.dart';
import 'config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: AppConfig.supabaseUrl, publishableKey: AppConfig.supabasePublishableKey);
  final prefs = await SharedPreferences.getInstance();
  final session = AppSession(SupabaseAuthRepository(Supabase.instance.client), prefs);
  runApp(RaeedApp(session: session));
  await session.start();
}
