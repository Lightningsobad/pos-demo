import 'dart:io';

import 'package:demo_application/core/config/app_config.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';

/// Shared HTTP client configured with connection pooling and timeouts.
class DioClient {
  DioClient({String baseUrl = AppConfig.defaultServerUrl})
      : _dio = Dio(
          BaseOptions(
            baseUrl: _normalizeBaseUrl(baseUrl),
            connectTimeout: AppConfig.connectTimeout,
            receiveTimeout: AppConfig.receiveTimeout,
          ),
        ) {
    _dio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () =>
          HttpClient()..maxConnectionsPerHost = AppConfig.maxConnectionsPerHost,
    );
  }

  final Dio _dio;

  Dio get dio => _dio;

  void updateBaseUrl(String baseUrl) {
    _dio.options.baseUrl = _normalizeBaseUrl(baseUrl);
  }

  static String _normalizeBaseUrl(String baseUrl) {
    final normalized = baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    if (normalized.isEmpty) {
      throw ArgumentError.value(baseUrl, 'baseUrl', 'Must not be empty');
    }
    return normalized;
  }
}
