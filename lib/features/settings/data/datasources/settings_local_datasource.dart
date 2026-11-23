import 'dart:convert';

import 'package:demo_application/features/settings/domain/entities/app_settings.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:shared_preferences/shared_preferences.dart';

typedef BluetoothDeviceScanner = Future<List<BluetoothPrinterDevice>> Function();

/// Local persistence and Bluetooth printer discovery data source.
class SettingsLocalDataSource {
  SettingsLocalDataSource({
    required this._prefs,
    BluetoothDeviceScanner? bluetoothScanner,
  }) : _bluetoothScanner = bluetoothScanner ?? _defaultBluetoothScanner;

  static const String _storageKey = 'pos_app_settings_v1';

  final SharedPreferences _prefs;
  final BluetoothDeviceScanner _bluetoothScanner;

  Future<AppSettings> loadSettings() async {
    final raw = _prefs.getString(_storageKey);
    if (raw == null || raw.trim().isEmpty) {
      return const AppSettings();
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return const AppSettings();
      }
      return _fromJson(decoded);
    } on FormatException {
      return const AppSettings();
    }
  }

  Future<void> saveSettings(AppSettings settings) async {
    final encoded = jsonEncode(_toJson(settings));
    final saved = await _prefs.setString(_storageKey, encoded);
    if (!saved) {
      throw StateError('Không thể lưu cấu hình vào bộ nhớ cục bộ');
    }
  }

  Future<List<BluetoothPrinterDevice>> scanBluetoothDevices() {
    return _bluetoothScanner();
  }

  static Future<List<BluetoothPrinterDevice>> _defaultBluetoothScanner() async {
    final granted = await PrintBluetoothThermal.isPermissionBluetoothGranted;
    if (!granted) {
      throw StateError('Chưa cấp quyền Bluetooth trên thiết bị');
    }

    final devices = await PrintBluetoothThermal.pairedBluetooths;
    return devices
        .map(
          (device) => BluetoothPrinterDevice(
            name: device.name,
            macAddress: device.macAdress,
          ),
        )
        .toList(growable: false);
  }

  static Map<String, dynamic> _toJson(AppSettings settings) {
    return {
      'serverUrl': settings.serverUrl,
      'defaultStaff': settings.defaultStaff,
      'store': {
        'name': settings.store.name,
        'phone': settings.store.phone,
        'address': settings.store.address,
        'logoUrl': settings.store.logoUrl,
      },
      'printer': {
        'mode': settings.printer.mode.name,
        'lanIp': settings.printer.lanIp,
        'lanPort': settings.printer.lanPort,
        'paperWidthMm': settings.printer.paperWidthMm,
        'bluetoothMac': settings.printer.bluetoothMac,
        'bluetoothName': settings.printer.bluetoothName,
      },
    };
  }

  static AppSettings _fromJson(Map<String, dynamic> json) {
    const defaults = AppSettings();
    final storeJson = json['store'] is Map<String, dynamic>
        ? json['store'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final printerJson = json['printer'] is Map<String, dynamic>
        ? json['printer'] as Map<String, dynamic>
        : const <String, dynamic>{};

    final modeName = printerJson['mode'] as String?;
    final mode = PrinterMode.values.firstWhere(
      (value) => value.name == modeName,
      orElse: () => defaults.printer.mode,
    );

    final rawPort = printerJson['lanPort'];
    final lanPort = rawPort is int && rawPort >= 1 && rawPort <= 65535
        ? rawPort
        : defaults.printer.lanPort;

    final rawPaper = printerJson['paperWidthMm'];
    final paperWidthMm =
        rawPaper == 58 || rawPaper == 80 ? rawPaper as int : 80;

    return AppSettings(
      serverUrl: _nonEmptyOr(json['serverUrl'], defaults.serverUrl),
      defaultStaff: _nonEmptyOr(json['defaultStaff'], defaults.defaultStaff),
      store: StoreConfig(
        name: _nonEmptyOr(storeJson['name'], defaults.store.name),
        phone: _stringOr(storeJson['phone'], defaults.store.phone),
        address: _stringOr(storeJson['address'], defaults.store.address),
        logoUrl: _stringOr(storeJson['logoUrl'], defaults.store.logoUrl),
      ),
      printer: PrinterConfig(
        mode: mode,
        lanIp: _stringOr(printerJson['lanIp'], defaults.printer.lanIp),
        lanPort: lanPort,
        paperWidthMm: paperWidthMm,
        bluetoothMac: _stringOr(
          printerJson['bluetoothMac'],
          defaults.printer.bluetoothMac,
        ),
        bluetoothName: _stringOr(
          printerJson['bluetoothName'],
          defaults.printer.bluetoothName,
        ),
      ),
    );
  }

  static String _stringOr(Object? value, String fallback) {
    return value is String ? value : fallback;
  }

  static String _nonEmptyOr(Object? value, String fallback) {
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
    return fallback;
  }
}
