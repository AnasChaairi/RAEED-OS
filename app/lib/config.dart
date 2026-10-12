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
}
