import 'dart:async';
import 'dart:convert';

import 'package:bloc_test/bloc_test.dart';
import 'package:demo_application/core/config/app_config.dart';
import 'package:demo_application/core/network/dio_client.dart';
import 'package:demo_application/features/settings/data/datasources/settings_local_datasource.dart';
import 'package:demo_application/features/settings/data/repositories/settings_repository_impl.dart';
import 'package:demo_application/features/settings/domain/entities/app_settings.dart';
import 'package:demo_application/features/settings/domain/repositories/settings_repository.dart';
import 'package:demo_application/features/settings/presentation/cubit/settings_cubit.dart';
import 'package:demo_application/features/settings/presentation/cubit/settings_state.dart';
import 'package:demo_application/features/settings/presentation/pages/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockDioClient extends Mock implements DioClient {}

void main() {
  late _MockDioClient mockDioClient;
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    mockDioClient = _MockDioClient();
    when(() => mockDioClient.updateBaseUrl(any())).thenReturn(null);
  });

  SettingsCubit createCubit({
    Future<List<BluetoothPrinterDevice>> Function()? bluetoothScanner,
  }) {
    final dataSource = SettingsLocalDataSource(
      prefs: prefs,
      bluetoothScanner: bluetoothScanner,
    );
    final repository = SettingsRepositoryImpl(localDataSource: dataSource);
    return SettingsCubit(repository: repository, dioClient: mockDioClient);
  }

  group('SettingsCubit', () {
    test(
      'loadSettings returns sensible defaults when SharedPreferences is empty',
      () async {
        final cubit = createCubit();
        addTearDown(cubit.close);

        await cubit.loadSettings();

        expect(cubit.state.status, SettingsStatus.loaded);
        expect(cubit.state.settings.serverUrl, AppConfig.defaultServerUrl);
        expect(cubit.state.settings.defaultStaff, 'Nguyễn Văn An');
        expect(AppSettings.sampleStaffNames, isNotEmpty);
        expect(cubit.state.settings.store.name, 'Cửa hàng Demo POS');
        expect(cubit.state.settings.store.phone, isNotEmpty);
        expect(cubit.state.settings.store.address, isNotEmpty);
        expect(cubit.state.settings.printer.mode, PrinterMode.pdfSystem);
        expect(cubit.state.settings.printer.lanPort, 9100);
        expect(cubit.state.settings.printer.paperWidthMm, 80);

        verify(() => mockDioClient.updateBaseUrl(AppConfig.defaultServerUrl))
            .called(1);
      },
    );

    test(
      'saveSettings persists settings and calls dioClient.updateBaseUrl',
      () async {
        final cubit = createCubit();
        addTearDown(cubit.close);

        const updated = AppSettings(
          serverUrl: 'http://192.168.1.50:3000/',
          defaultStaff: 'Trần Thị Bình',
          store: StoreConfig(
            name: 'Tạp hóa Minh Tâm',
            phone: '0987 654 321',
            address: '45 Lê Lợi, Q.1, TP.HCM',
            logoUrl: 'https://example.com/logo.png',
          ),
          printer: PrinterConfig(
            mode: PrinterMode.escPosLan,
            lanIp: '192.168.1.222',
            lanPort: 9100,
            paperWidthMm: 58,
            bluetoothMac: '00:11:22:33:44:55',
            bluetoothName: 'XP-58IIH',
          ),
        );

        final ok = await cubit.saveSettings(updated);
        expect(ok, isTrue);
        expect(cubit.state.status, SettingsStatus.saved);
        expect(cubit.state.settings.serverUrl, 'http://192.168.1.50:3000');

        verify(() => mockDioClient.updateBaseUrl('http://192.168.1.50:3000'))
            .called(1);

        final reloadedCubit = createCubit();
        addTearDown(reloadedCubit.close);
        await reloadedCubit.loadSettings();

        expect(reloadedCubit.state.settings, equals(cubit.state.settings));
      },
    );

    blocTest<SettingsCubit, SettingsState>(
      'saveSettings rejects invalid serverUrl without updating DioClient',
      build: createCubit,
      act: (cubit) => cubit.saveSettings(
        const AppSettings(serverUrl: 'ftp://bad-host'),
      ),
      expect: () => [
        isA<SettingsState>()
            .having((s) => s.status, 'status', SettingsStatus.error)
            .having((s) => s.errorMessage, 'errorMessage', isNotEmpty)
            .having(
              (s) => s.settings.serverUrl,
              'serverUrl',
              AppConfig.defaultServerUrl,
            ),
      ],
      verify: (_) {
        verifyNever(() => mockDioClient.updateBaseUrl(any()));
      },
    );

    test('scanBluetoothDevices populates discovered paired devices', () async {
      final cubit = createCubit(
        bluetoothScanner: () async => const [
          BluetoothPrinterDevice(name: 'RPP02N', macAddress: 'AA:BB:CC:DD:EE:FF'),
          BluetoothPrinterDevice(name: 'XP-P300', macAddress: '11:22:33:44:55:66'),
        ],
      );
      addTearDown(cubit.close);

      await cubit.scanBluetoothDevices();

      expect(cubit.state.isScanningBluetooth, isFalse);
      expect(cubit.state.bluetoothDevices, hasLength(2));
      expect(cubit.state.bluetoothDevices.first.name, 'RPP02N');
      expect(cubit.state.errorMessage, isNull);
    });

    test('scanBluetoothDevices handles scanner failure gracefully', () async {
      final cubit = createCubit(
        bluetoothScanner: () async =>
            throw StateError('Chưa cấp quyền Bluetooth'),
      );
      addTearDown(cubit.close);

      await cubit.scanBluetoothDevices();

      expect(cubit.state.isScanningBluetooth, isFalse);
      expect(cubit.state.bluetoothDevices, isEmpty);
      expect(cubit.state.errorMessage, contains('Bluetooth'));
    });

    test('loadSettings falls back to defaults on corrupt JSON', () async {
      await prefs.setString('pos_app_settings_v1', '{not-valid-json');
      final cubit = createCubit();
      addTearDown(cubit.close);

      await cubit.loadSettings();

      expect(cubit.state.status, SettingsStatus.loaded);
      expect(cubit.state.settings, const AppSettings());
      verify(() => mockDioClient.updateBaseUrl(AppConfig.defaultServerUrl))
          .called(1);
    });

    test('saveSettings rejects out-of-range LAN port', () async {
      final cubit = createCubit();
      addTearDown(cubit.close);

      final ok = await cubit.saveSettings(
        const AppSettings(printer: PrinterConfig(lanPort: 70000)),
      );

      expect(ok, isFalse);
      expect(cubit.state.status, SettingsStatus.error);
      verifyNever(() => mockDioClient.updateBaseUrl(any()));
    });

    testWidgets('SettingsPage renders fields, quick-fill URL, and saves',
        (tester) async {
      final cubit = createCubit();
      addTearDown(cubit.close);
      await cubit.loadSettings();

      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<SettingsCubit>.value(
            value: cubit,
            child: const SettingsPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Cấu hình POS'), findsOneWidget);
      expect(find.text('Điền nhanh 10.0.2.2:3000'), findsOneWidget);

      await tester.ensureVisible(find.text('Trần Thị Bình'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Trần Thị Bình'));
      await tester.pump();
      await tester.tap(find.text('Lưu'));
      await tester.pumpAndSettle();

      expect(cubit.state.status, SettingsStatus.saved);
      expect(cubit.state.settings.defaultStaff, 'Trần Thị Bình');
    });

    test('repeated identical validation errors increment errorNonce', () async {
      final cubit = createCubit();
      addTearDown(cubit.close);

      final emitted = <SettingsState>[];
      final sub = cubit.stream.listen(emitted.add);
      addTearDown(sub.cancel);

      await cubit.saveSettings(const AppSettings(serverUrl: 'ftp://bad-host'));
      await cubit.saveSettings(const AppSettings(serverUrl: 'ftp://bad-host'));
      await Future<void>.delayed(Duration.zero);

      expect(emitted, hasLength(2));
      expect(emitted[0].status, SettingsStatus.error);
      expect(emitted[1].status, SettingsStatus.error);
      expect(emitted[1].errorNonce, greaterThan(emitted[0].errorNonce));
    });

    testWidgets(
        'SettingsPage preserves unsaved edits and shows SnackBar on scan error and repeated errors',
        (tester) async {
      var scanCalls = 0;
      final cubit = createCubit(
        bluetoothScanner: () async {
          scanCalls++;
          throw StateError('Chưa cấp quyền Bluetooth');
        },
      );
      addTearDown(cubit.close);
      await cubit.loadSettings();

      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<SettingsCubit>.value(
            value: cubit,
            child: const SettingsPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Edit store name without saving.
      final storeNameField =
          find.widgetWithText(TextFormField, 'Cửa hàng Demo POS');
      await tester.enterText(storeNameField, 'Cửa hàng Chưa Lưu');
      await tester.pump();

      final listScrollable = find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first;

      // Switch printer mode to Bluetooth and tap Quét.
      await tester.scrollUntilVisible(
        find.text('Bluetooth'),
        200,
        scrollable: listScrollable,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bluetooth'));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Quét'),
        200,
        scrollable: listScrollable,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Quét'));
      await tester.pumpAndSettle();

      expect(scanCalls, 1);
      expect(
        find.textContaining('Lỗi quét Bluetooth'),
        findsOneWidget,
      );

      // Dismiss current SnackBar and trigger the same scan error a second time.
      ScaffoldMessenger.of(
        tester.element(find.byType(SettingsPage)),
      ).clearSnackBars();
      await tester.pumpAndSettle();

      await tester.tap(find.text('Quét'));
      await tester.pumpAndSettle();

      expect(scanCalls, 2);
      expect(
        find.textContaining('Lỗi quét Bluetooth'),
        findsOneWidget,
      );

      // Scroll back up to verify unsaved store name edit was preserved.
      await tester.scrollUntilVisible(
        find.text('Cửa hàng Chưa Lưu'),
        -200,
        scrollable: listScrollable,
      );
      expect(find.text('Cửa hàng Chưa Lưu'), findsOneWidget);
    });

    test('SettingsLocalDataSource parses paperWidthMm when stored as num/double', () async {
      await prefs.setString(
        'pos_app_settings_v1',
        jsonEncode({
          'printer': {'paperWidthMm': 58.0},
        }),
      );
      final dataSource = SettingsLocalDataSource(prefs: prefs);
      final loaded = await dataSource.loadSettings();
      expect(loaded.printer.paperWidthMm, 58);
    });

    testWidgets('SettingsPage disables AppBar Lưu button while saving', (tester) async {
      final saveCompleter = Completer<void>();
      final repo = _DelayedSaveSettingsRepository(saveCompleter);
      final cubit = SettingsCubit(repository: repo, dioClient: mockDioClient);
      addTearDown(cubit.close);
      await cubit.loadSettings();

      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<SettingsCubit>.value(
            value: cubit,
            child: const SettingsPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Lưu'));
      await tester.pump();

      final saveAction = tester.widget<TextButton>(
        find.ancestor(
          of: find.text('Lưu'),
          matching: find.byType(TextButton),
        ),
      );
      expect(saveAction.onPressed, isNull);

      saveCompleter.complete();
      await tester.pumpAndSettle();
    });
  });
}

class _DelayedSaveSettingsRepository implements SettingsRepository {
  _DelayedSaveSettingsRepository(this._saveCompleter);

  final Completer<void> _saveCompleter;

  @override
  Future<AppSettings> loadSettings() async => const AppSettings();

  @override
  Future<void> saveSettings(AppSettings settings) => _saveCompleter.future;

  @override
  Future<List<BluetoothPrinterDevice>> scanBluetoothDevices() async => const [];
}
