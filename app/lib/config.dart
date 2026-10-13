/// Supabase project for RAEED OS (Frankfurt). The publishable key is meant to ship inside
/// the app: what each person can read or write is decided by the database's access rules.
/// Both can be overridden at build time with --dart-define.
abstract final class AppConfig {
  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://ezqmiwqpiinxuqjvgiye.supabase.co',
  );
  static const supabasePublishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: 'sb_publishable_5yufcRQeD-d_JTp9LK8CWw_yslKVT1k',
  );

  // Firebase, for push notifications. Not secret: Firebase's own rules decide what these
  // can do. Empty until the academy's Firebase project exists; the app then runs without
  // notifications.
  static const firebaseApiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const firebaseAppId = String.fromEnvironment('FIREBASE_APP_ID');
  static const firebaseSenderId = String.fromEnvironment('FIREBASE_SENDER_ID');
  static const firebaseProjectId = String.fromEnvironment('FIREBASE_PROJECT_ID');

  static bool get pushConfigured =>
      firebaseApiKey != '' && firebaseAppId != '' && firebaseSenderId != '' && firebaseProjectId != '';
}
