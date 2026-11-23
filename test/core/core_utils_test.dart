import 'dart:io';

import 'package:demo_application/core/config/app_config.dart';
import 'package:demo_application/core/network/dio_client.dart';
import 'package:demo_application/core/utils/currency_formatter.dart';
import 'package:dio/io.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CurrencyFormatter', () {
    test('formats VND amounts as ###,### đ', () {
      expect(CurrencyFormatter.formatVnd(0), '0 đ');
      expect(CurrencyFormatter.formatVnd(87209), '87,209 đ');
      expect(CurrencyFormatter.formatVnd(1234567.6), '1,234,568 đ');
    });

    test('throws ArgumentError on non-finite amount', () {
      expect(() => CurrencyFormatter.formatVnd(double.nan), throwsArgumentError);
      expect(
        () => CurrencyFormatter.formatVnd(double.infinity),
        throwsArgumentError,
      );
    });
  });

  group('DioClient', () {
    test('configures baseUrl, timeouts, and IOHttpClientAdapter pool', () {
      final client = DioClient(baseUrl: 'http://192.168.1.10:3000/');

      expect(client.dio.options.baseUrl, 'http://192.168.1.10:3000');
      expect(client.dio.options.connectTimeout, AppConfig.connectTimeout);
      expect(client.dio.options.receiveTimeout, AppConfig.receiveTimeout);

      final adapter = client.dio.httpClientAdapter as IOHttpClientAdapter;
      final HttpClient? httpClient = adapter.createHttpClient?.call();
      expect(httpClient, isNotNull);
      expect(httpClient!.maxConnectionsPerHost, AppConfig.maxConnectionsPerHost);
      httpClient.close();

      client.updateBaseUrl(' http://10.0.2.2:3000/// ');
      expect(client.dio.options.baseUrl, 'http://10.0.2.2:3000');
    });

    test('rejects empty baseUrl', () {
      expect(() => DioClient(baseUrl: '   '), throwsArgumentError);
      final client = DioClient();
      expect(() => client.updateBaseUrl('/'), throwsArgumentError);
    });
  });
}
