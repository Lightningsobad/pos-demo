import 'package:demo_application/core/config/app_config.dart';
import 'package:demo_application/features/settings/domain/entities/app_settings.dart';
import 'package:demo_application/features/settings/presentation/cubit/settings_cubit.dart';
import 'package:demo_application/features/settings/presentation/cubit/settings_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// POS configuration screen for server URL, store metadata, staff, and printer.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _serverUrlController;
  late final TextEditingController _storeNameController;
  late final TextEditingController _storePhoneController;
  late final TextEditingController _storeAddressController;
  late final TextEditingController _storeLogoUrlController;
  late final TextEditingController _staffController;
  late final TextEditingController _lanIpController;
  late final TextEditingController _lanPortController;

  PrinterMode _printerMode = PrinterMode.pdfSystem;
  int _paperWidthMm = 80;
  String _bluetoothMac = '';
  String _bluetoothName = '';

  @override
  void initState() {
    super.initState();
    final initial = context.read<SettingsCubit>().state.settings;
    _serverUrlController = TextEditingController(text: initial.serverUrl);
    _storeNameController = TextEditingController(text: initial.store.name);
    _storePhoneController = TextEditingController(text: initial.store.phone);
    _storeAddressController =
        TextEditingController(text: initial.store.address);
    _storeLogoUrlController =
        TextEditingController(text: initial.store.logoUrl);
    _staffController = TextEditingController(text: initial.defaultStaff);
    _lanIpController = TextEditingController(text: initial.printer.lanIp);
    _lanPortController =
        TextEditingController(text: initial.printer.lanPort.toString());
    _printerMode = initial.printer.mode;
    _paperWidthMm = initial.printer.paperWidthMm;
    _bluetoothMac = initial.printer.bluetoothMac;
    _bluetoothName = initial.printer.bluetoothName;
  }

  @override
  void dispose() {
    _serverUrlController.dispose();
    _storeNameController.dispose();
    _storePhoneController.dispose();
    _storeAddressController.dispose();
    _storeLogoUrlController.dispose();
    _staffController.dispose();
    _lanIpController.dispose();
    _lanPortController.dispose();
    super.dispose();
  }

  void _applySettingsToForm(AppSettings settings) {
    _serverUrlController.text = settings.serverUrl;
    _storeNameController.text = settings.store.name;
    _storePhoneController.text = settings.store.phone;
    _storeAddressController.text = settings.store.address;
    _storeLogoUrlController.text = settings.store.logoUrl;
    _staffController.text = settings.defaultStaff;
    _lanIpController.text = settings.printer.lanIp;
    _lanPortController.text = settings.printer.lanPort.toString();
    setState(() {
      _printerMode = settings.printer.mode;
      _paperWidthMm = settings.printer.paperWidthMm;
      _bluetoothMac = settings.printer.bluetoothMac;
      _bluetoothName = settings.printer.bluetoothName;
    });
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final port = int.tryParse(_lanPortController.text.trim()) ?? 9100;
    final updated = AppSettings(
      serverUrl: _serverUrlController.text.trim(),
      defaultStaff: _staffController.text.trim(),
      store: StoreConfig(
        name: _storeNameController.text.trim(),
        phone: _storePhoneController.text.trim(),
        address: _storeAddressController.text.trim(),
        logoUrl: _storeLogoUrlController.text.trim(),
      ),
      printer: PrinterConfig(
        mode: _printerMode,
        lanIp: _lanIpController.text.trim(),
        lanPort: port,
        paperWidthMm: _paperWidthMm,
        bluetoothMac: _bluetoothMac,
        bluetoothName: _bluetoothName,
      ),
    );

    await context.read<SettingsCubit>().saveSettings(updated);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cấu hình POS'),
        actions: [
          TextButton.icon(
            onPressed: _submit,
            icon: const Icon(Icons.save_outlined),
            label: const Text('Lưu'),
          ),
        ],
      ),
      body: BlocConsumer<SettingsCubit, SettingsState>(
        listenWhen: (previous, current) {
          final statusSynced = previous.status != current.status &&
              current.errorMessage == null &&
              (current.status == SettingsStatus.loaded ||
                  current.status == SettingsStatus.saved);
          final errorRaised = current.errorMessage != null &&
              (previous.errorNonce != current.errorNonce ||
                  previous.errorMessage != current.errorMessage);
          return statusSynced || errorRaised;
        },
        listener: (context, state) {
          if (state.errorMessage != null) {
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(
                SnackBar(content: Text(state.errorMessage!)),
              );
            return;
          }
          if (state.status == SettingsStatus.loaded) {
            _applySettingsToForm(state.settings);
          } else if (state.status == SettingsStatus.saved) {
            _applySettingsToForm(state.settings);
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(
                const SnackBar(content: Text('Đã lưu cấu hình POS')),
              );
          }
        },
        builder: (context, state) {
          final isSaving = state.status == SettingsStatus.saving;
          return Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _SectionHeader(title: 'Kết nối Server API'),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _serverUrlController,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: 'Server URL',
                    hintText: AppConfig.defaultServerUrl,
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.dns_outlined),
                  ),
                  validator: (value) {
                    if (value == null ||
                        !SettingsCubit.isValidServerUrl(value)) {
                      return 'Nhập URL hợp lệ (http:// hoặc https://)';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    ActionChip(
                      avatar: const Icon(Icons.flash_on, size: 18),
                      label: const Text('Điền nhanh 10.0.2.2:3000'),
                      onPressed: () {
                        _serverUrlController.text = AppConfig.defaultServerUrl;
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                _SectionHeader(title: 'Thông tin Cửa hàng & Logo'),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _storeNameController,
                  decoration: const InputDecoration(
                    labelText: 'Tên cửa hàng',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.storefront_outlined),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Tên cửa hàng không được để trống';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _storePhoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Số điện thoại',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.phone_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _storeAddressController,
                  decoration: const InputDecoration(
                    labelText: 'Địa chỉ',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.location_on_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _storeLogoUrlController,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: 'Logo URL (tùy chọn)',
                    hintText: 'https://... hoặc để trống',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.image_outlined),
                  ),
                ),
                const SizedBox(height: 20),
                _SectionHeader(title: 'Nhân viên mặc định'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: AppSettings.sampleStaffNames.map((name) {
                    final selected = _staffController.text.trim() == name;
                    return ChoiceChip(
                      label: Text(name),
                      selected: selected,
                      onSelected: (_) {
                        setState(() {
                          _staffController.text = name;
                        });
                      },
                    );
                  }).toList(growable: false),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _staffController,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Tên nhân viên thu ngân',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.badge_outlined),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Vui lòng nhập tên nhân viên';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 20),
                _SectionHeader(title: 'Cấu hình Máy in hóa đơn'),
                const SizedBox(height: 8),
                SegmentedButton<PrinterMode>(
                  segments: const [
                    ButtonSegment(
                      value: PrinterMode.escPosLan,
                      label: Text('LAN'),
                      icon: Icon(Icons.lan_outlined),
                    ),
                    ButtonSegment(
                      value: PrinterMode.escPosBluetooth,
                      label: Text('Bluetooth'),
                      icon: Icon(Icons.bluetooth),
                    ),
                    ButtonSegment(
                      value: PrinterMode.pdfSystem,
                      label: Text('PDF / System'),
                      icon: Icon(Icons.picture_as_pdf_outlined),
                    ),
                  ],
                  selected: {_printerMode},
                  onSelectionChanged: (selection) {
                    setState(() => _printerMode = selection.first);
                  },
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Text('Khổ giấy:'),
                    const SizedBox(width: 12),
                    SegmentedButton<int>(
                      segments: const [
                        ButtonSegment(value: 80, label: Text('80mm')),
                        ButtonSegment(value: 58, label: Text('58mm')),
                      ],
                      selected: {_paperWidthMm},
                      onSelectionChanged: (selection) {
                        setState(() => _paperWidthMm = selection.first);
                      },
                    ),
                  ],
                ),
                if (_printerMode == PrinterMode.escPosLan) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: TextFormField(
                          controller: _lanIpController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'IP Máy in LAN',
                            hintText: '192.168.1.200',
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) {
                            if (_printerMode == PrinterMode.escPosLan &&
                                (value == null || value.trim().isEmpty)) {
                              return 'Nhập IP máy in';
                            }
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _lanPortController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Port',
                            hintText: '9100',
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) {
                            final port = int.tryParse(value?.trim() ?? '');
                            if (_printerMode == PrinterMode.escPosLan &&
                                (port == null || port < 1 || port > 65535)) {
                              return '1-65535';
                            }
                            return null;
                          },
                        ),
                      ),
                    ],
                  ),
                ],
                if (_printerMode == PrinterMode.escPosBluetooth) ...[
                  const SizedBox(height: 12),
                  _BluetoothPickerSection(
                    selectedMac: _bluetoothMac,
                    selectedName: _bluetoothName,
                    devices: state.bluetoothDevices,
                    isScanning: state.isScanningBluetooth,
                    onScan: () =>
                        context.read<SettingsCubit>().scanBluetoothDevices(),
                    onSelect: (device) {
                      setState(() {
                        _bluetoothMac = device.macAddress;
                        _bluetoothName = device.name;
                      });
                    },
                  ),
                ],
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: isSaving ? null : _submit,
                  icon: isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check),
                  label: Text(isSaving ? 'Đang lưu...' : 'Lưu cấu hình'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
    );
  }
}

class _BluetoothPickerSection extends StatelessWidget {
  const _BluetoothPickerSection({
    required this.selectedMac,
    required this.selectedName,
    required this.devices,
    required this.isScanning,
    required this.onScan,
    required this.onSelect,
  });

  final String selectedMac;
  final String selectedName;
  final List<BluetoothPrinterDevice> devices;
  final bool isScanning;
  final VoidCallback onScan;
  final ValueChanged<BluetoothPrinterDevice> onSelect;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    selectedMac.isEmpty
                        ? 'Chưa chọn máy in Bluetooth'
                        : 'Đã chọn: $selectedName ($selectedMac)',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: isScanning ? null : onScan,
                  icon: isScanning
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.bluetooth_searching),
                  label: const Text('Quét'),
                ),
              ],
            ),
            if (devices.isNotEmpty) ...[
              const Divider(height: 16),
              ...devices.map(
                (device) => ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    device.macAddress == selectedMac
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                  ),
                  title: Text(device.name),
                  subtitle: Text(device.macAddress),
                  onTap: () => onSelect(device),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
