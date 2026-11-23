import 'package:demo_application/features/settings/data/datasources/settings_local_datasource.dart';
import 'package:demo_application/features/settings/domain/entities/app_settings.dart';
import 'package:demo_application/features/settings/domain/repositories/settings_repository.dart';

/// Repository implementation delegating settings storage and BT scan to local data source.
class SettingsRepositoryImpl implements SettingsRepository {
  SettingsRepositoryImpl({required this._localDataSource});

  final SettingsLocalDataSource _localDataSource;

  @override
  Future<AppSettings> loadSettings() => _localDataSource.loadSettings();

  @override
  Future<void> saveSettings(AppSettings settings) =>
      _localDataSource.saveSettings(settings);

  @override
  Future<List<BluetoothPrinterDevice>> scanBluetoothDevices() =>
      _localDataSource.scanBluetoothDevices();
}
