import 'package:demo_application/core/config/app_config.dart';
import 'package:demo_application/core/network/dio_client.dart';
import 'package:demo_application/features/settings/domain/entities/app_settings.dart';
import 'package:demo_application/features/settings/domain/repositories/settings_repository.dart';
import 'package:demo_application/features/settings/presentation/cubit/settings_state.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Cubit managing store, staff, server URL, and printer settings.
class SettingsCubit extends Cubit<SettingsState> {
  SettingsCubit({
    required this._repository,
    required this._dioClient,
  }) : super(const SettingsState());

  final SettingsRepository _repository;
  final DioClient _dioClient;

  /// Loads persisted settings and syncs the HTTP client base URL.
  Future<void> loadSettings() async {
    emit(state.copyWith(status: SettingsStatus.loading, clearError: true));
    try {
      final loaded = await _repository.loadSettings();
      if (isClosed) return;

      final safeUrl = isValidServerUrl(loaded.serverUrl)
          ? normalizeServerUrl(loaded.serverUrl)
          : AppConfig.defaultServerUrl;
      final normalized = loaded.copyWith(serverUrl: safeUrl);

      _dioClient.updateBaseUrl(normalized.serverUrl);
      emit(
        state.copyWith(
          status: SettingsStatus.loaded,
          settings: normalized,
          clearError: true,
        ),
      );
    } catch (error) {
      if (isClosed) return;
      emit(
        state.copyWith(
          status: SettingsStatus.error,
          errorMessage: 'Không thể tải cấu hình: $error',
        ),
      );
    }
  }

  /// Validates, persists, and applies updated settings to [DioClient].
  Future<bool> saveSettings(AppSettings settings) async {
    final normalizedUrl = normalizeServerUrl(settings.serverUrl);
    if (!isValidServerUrl(normalizedUrl)) {
      emit(
        state.copyWith(
          status: SettingsStatus.error,
          errorMessage: 'Server URL phải bắt đầu bằng http:// hoặc https://',
        ),
      );
      return false;
    }

    if (settings.printer.lanPort < 1 || settings.printer.lanPort > 65535) {
      emit(
        state.copyWith(
          status: SettingsStatus.error,
          errorMessage: 'Port máy in LAN phải trong khoảng 1 - 65535',
        ),
      );
      return false;
    }

    if (settings.printer.paperWidthMm != 58 &&
        settings.printer.paperWidthMm != 80) {
      emit(
        state.copyWith(
          status: SettingsStatus.error,
          errorMessage: 'Khổ giấy chỉ hỗ trợ 58mm hoặc 80mm',
        ),
      );
      return false;
    }

    final normalizedSettings = settings.copyWith(
      serverUrl: normalizedUrl,
      defaultStaff: settings.defaultStaff.trim().isEmpty
          ? const AppSettings().defaultStaff
          : settings.defaultStaff.trim(),
      store: settings.store.copyWith(
        name: settings.store.name.trim().isEmpty
            ? const StoreConfig().name
            : settings.store.name.trim(),
        phone: settings.store.phone.trim(),
        address: settings.store.address.trim(),
        logoUrl: settings.store.logoUrl.trim(),
      ),
      printer: settings.printer.copyWith(
        lanIp: settings.printer.lanIp.trim(),
        bluetoothMac: settings.printer.bluetoothMac.trim(),
        bluetoothName: settings.printer.bluetoothName.trim(),
      ),
    );

    emit(state.copyWith(status: SettingsStatus.saving, clearError: true));
    try {
      await _repository.saveSettings(normalizedSettings);
      if (isClosed) return false;

      _dioClient.updateBaseUrl(normalizedSettings.serverUrl);
      emit(
        state.copyWith(
          status: SettingsStatus.saved,
          settings: normalizedSettings,
          clearError: true,
        ),
      );
      return true;
    } catch (error) {
      if (isClosed) return false;
      emit(
        state.copyWith(
          status: SettingsStatus.error,
          errorMessage: 'Lưu cấu hình thất bại: $error',
        ),
      );
      return false;
    }
  }

  /// Scans paired Bluetooth printers via the platform repository.
  Future<void> scanBluetoothDevices() async {
    emit(state.copyWith(isScanningBluetooth: true, clearError: true));
    try {
      final devices = await _repository.scanBluetoothDevices();
      if (isClosed) return;
      emit(
        state.copyWith(
          isScanningBluetooth: false,
          bluetoothDevices: devices,
          clearError: true,
        ),
      );
    } catch (error) {
      if (isClosed) return;
      emit(
        state.copyWith(
          isScanningBluetooth: false,
          errorMessage: 'Lỗi quét Bluetooth: $error',
        ),
      );
    }
  }

  static String normalizeServerUrl(String raw) {
    return raw.trim().replaceFirst(RegExp(r'/+$'), '');
  }

  static bool isValidServerUrl(String raw) {
    final uri = Uri.tryParse(normalizeServerUrl(raw));
    if (uri == null) return false;
    return (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
  }
}
