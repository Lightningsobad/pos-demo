import 'package:demo_application/features/settings/domain/entities/app_settings.dart';

/// Persistence and device-discovery contract for POS settings.
abstract interface class SettingsRepository {
  Future<AppSettings> loadSettings();

  Future<void> saveSettings(AppSettings settings);

  Future<List<BluetoothPrinterDevice>> scanBluetoothDevices();
}
