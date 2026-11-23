import 'package:demo_application/core/config/app_config.dart';
import 'package:equatable/equatable.dart';

/// Supported receipt printing backends.
enum PrinterMode { escPosLan, escPosBluetooth, pdfSystem }

/// Paired Bluetooth thermal printer descriptor.
class BluetoothPrinterDevice extends Equatable {
  const BluetoothPrinterDevice({
    required this.name,
    required this.macAddress,
  });

  final String name;
  final String macAddress;

  @override
  List<Object?> get props => [name, macAddress];
}

/// Store metadata printed on receipts and invoices.
class StoreConfig extends Equatable {
  const StoreConfig({
    this.name = 'Cửa hàng Demo POS',
    this.phone = '0901 234 567',
    this.address = '123 Nguyễn Huệ, Q.1, TP.HCM',
    this.logoUrl = '',
  });

  final String name;
  final String phone;
  final String address;
  final String logoUrl;

  StoreConfig copyWith({
    String? name,
    String? phone,
    String? address,
    String? logoUrl,
  }) {
    return StoreConfig(
      name: name ?? this.name,
      phone: phone ?? this.phone,
      address: address ?? this.address,
      logoUrl: logoUrl ?? this.logoUrl,
    );
  }

  @override
  List<Object?> get props => [name, phone, address, logoUrl];
}

/// Thermal/PDF printer configuration.
class PrinterConfig extends Equatable {
  const PrinterConfig({
    this.mode = PrinterMode.pdfSystem,
    this.lanIp = '192.168.1.200',
    this.lanPort = 9100,
    this.paperWidthMm = 80,
    this.bluetoothMac = '',
    this.bluetoothName = '',
  });

  final PrinterMode mode;
  final String lanIp;
  final int lanPort;
  final int paperWidthMm;
  final String bluetoothMac;
  final String bluetoothName;

  PrinterConfig copyWith({
    PrinterMode? mode,
    String? lanIp,
    int? lanPort,
    int? paperWidthMm,
    String? bluetoothMac,
    String? bluetoothName,
  }) {
    return PrinterConfig(
      mode: mode ?? this.mode,
      lanIp: lanIp ?? this.lanIp,
      lanPort: lanPort ?? this.lanPort,
      paperWidthMm: paperWidthMm ?? this.paperWidthMm,
      bluetoothMac: bluetoothMac ?? this.bluetoothMac,
      bluetoothName: bluetoothName ?? this.bluetoothName,
    );
  }

  @override
  List<Object?> get props => [
        mode,
        lanIp,
        lanPort,
        paperWidthMm,
        bluetoothMac,
        bluetoothName,
      ];
}

/// Persisted POS application settings.
class AppSettings extends Equatable {
  const AppSettings({
    this.serverUrl = AppConfig.defaultServerUrl,
    this.defaultStaff = 'Nguyễn Văn An',
    this.store = const StoreConfig(),
    this.printer = const PrinterConfig(),
  });

  static const List<String> sampleStaffNames = [
    'Nguyễn Văn An',
    'Trần Thị Bình',
    'Lê Minh Châu',
    'Phạm Quốc Dũng',
  ];

  final String serverUrl;
  final String defaultStaff;
  final StoreConfig store;
  final PrinterConfig printer;

  AppSettings copyWith({
    String? serverUrl,
    String? defaultStaff,
    StoreConfig? store,
    PrinterConfig? printer,
  }) {
    return AppSettings(
      serverUrl: serverUrl ?? this.serverUrl,
      defaultStaff: defaultStaff ?? this.defaultStaff,
      store: store ?? this.store,
      printer: printer ?? this.printer,
    );
  }

  @override
  List<Object?> get props => [serverUrl, defaultStaff, store, printer];
}
