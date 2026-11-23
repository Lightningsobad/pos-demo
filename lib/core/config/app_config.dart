/// Central default configuration constants for the POS mobile app.
abstract final class AppConfig {
  static const String defaultServerUrl = 'http://10.0.2.2:3000';
  static const int catalogPageSize = 10;
  static const int catalogLruMaxPages = 20;
  static const Duration scrollDebounce = Duration(milliseconds: 150);
  static const Duration searchDebounce = Duration(milliseconds: 300);
  static const int maxConnectionsPerHost = 16;
  static const Duration connectTimeout = Duration(seconds: 5);
  static const Duration receiveTimeout = Duration(seconds: 10);
}
