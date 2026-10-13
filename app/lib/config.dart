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

  // Firebase project raeed-os, for push notifications (from google-services.json). Not
  // secret: Firebase's own rules decide what these can do. With all four empty the app runs
  // without notifications.
  static const firebaseApiKey = String.fromEnvironment(
    'FIREBASE_API_KEY',
    defaultValue: 'AIzaSyDTy47JIyqqr0GspVmqi6riWBCJzmf45hY',
  );
  static const firebaseAppId = String.fromEnvironment(
    'FIREBASE_APP_ID',
    defaultValue: '1:765815959359:android:162d3ce59cbb6d252e6d8a',
  );
  static const firebaseSenderId = String.fromEnvironment('FIREBASE_SENDER_ID', defaultValue: '765815959359');
  static const firebaseProjectId = String.fromEnvironment('FIREBASE_PROJECT_ID', defaultValue: 'raeed-os');

  static bool get pushConfigured =>
      firebaseApiKey != '' && firebaseAppId != '' && firebaseSenderId != '' && firebaseProjectId != '';
}
