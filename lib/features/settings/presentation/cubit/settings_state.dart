import 'package:demo_application/features/settings/domain/entities/app_settings.dart';
import 'package:equatable/equatable.dart';

/// Lifecycle status for loading and saving POS settings.
enum SettingsStatus { initial, loading, loaded, saving, saved, error }

/// Immutable state managed by [SettingsCubit].
class SettingsState extends Equatable {
  const SettingsState({
    this.status = SettingsStatus.initial,
    this.settings = const AppSettings(),
    this.bluetoothDevices = const [],
    this.isScanningBluetooth = false,
    this.errorMessage,
    this.errorNonce = 0,
  });

  final SettingsStatus status;
  final AppSettings settings;
  final List<BluetoothPrinterDevice> bluetoothDevices;
  final bool isScanningBluetooth;
  final String? errorMessage;
  final int errorNonce;

  SettingsState copyWith({
    SettingsStatus? status,
    AppSettings? settings,
    List<BluetoothPrinterDevice>? bluetoothDevices,
    bool? isScanningBluetooth,
    String? errorMessage,
    int? errorNonce,
    bool clearError = false,
  }) {
    return SettingsState(
      status: status ?? this.status,
      settings: settings ?? this.settings,
      bluetoothDevices: bluetoothDevices ?? this.bluetoothDevices,
      isScanningBluetooth: isScanningBluetooth ?? this.isScanningBluetooth,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      errorNonce: errorNonce ?? this.errorNonce,
    );
  }

  @override
  List<Object?> get props => [
        status,
        settings,
        bluetoothDevices,
        isScanningBluetooth,
        errorMessage,
        errorNonce,
      ];
}
