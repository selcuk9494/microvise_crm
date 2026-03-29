class AppConfig {
  static const _defaultSupabaseUrl = 'https://xvbczyhvmmcvqezjjpbn.supabase.co';
  static const _defaultSupabaseAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inh2YmN6eWh2bW1jdnFlempqcGJuIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQ1NDIyMjMsImV4cCI6MjA5MDExODIyM30.C29qs4amA8gWbqvLQKukhF1WqouE_y2Tja6naXggiPw';

  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: _defaultSupabaseUrl,
  );
  static const supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: _defaultSupabaseAnonKey,
  );

  static bool get isSupabaseConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}
