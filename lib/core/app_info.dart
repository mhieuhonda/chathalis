/// App identity, kept in one place so the About card can never drift from
/// the store listing. Keep [version] in sync with `version:` in
/// pubspec.yaml.
abstract final class AppInfo {
  static const String appName = 'ChatHalis';
  static const String version = '1.2.0';
}
