import 'dart:async';

import 'package:demo_application/core/network/dio_client.dart';
import 'package:demo_application/features/cart/data/datasources/cart_local_datasource.dart';
import 'package:demo_application/features/cart/data/repositories/cart_repository_impl.dart';
import 'package:demo_application/features/cart/domain/repositories/cart_repository.dart';
import 'package:demo_application/features/cart/presentation/cubit/cart_cubit.dart';
import 'package:demo_application/features/cart/presentation/cubit/cart_state.dart';
import 'package:demo_application/features/cart/presentation/pages/cart_page.dart';
import 'package:demo_application/features/catalog/data/datasources/catalog_remote_datasource.dart';
import 'package:demo_application/features/catalog/data/repositories/catalog_repository_impl.dart';
import 'package:demo_application/features/catalog/domain/entities/product.dart';
import 'package:demo_application/features/catalog/domain/repositories/catalog_repository.dart';
import 'package:demo_application/features/catalog/presentation/cubit/catalog_cubit.dart';
import 'package:demo_application/features/catalog/presentation/pages/catalog_page.dart';
import 'package:demo_application/features/invoice/data/datasources/invoice_remote_datasource.dart';
import 'package:demo_application/features/invoice/data/repositories/invoice_repository_impl.dart';
import 'package:demo_application/features/invoice/data/services/escpos_raster_printer_service.dart';
import 'package:demo_application/features/invoice/data/services/pdf_invoice_service.dart';
import 'package:demo_application/features/invoice/domain/repositories/invoice_repository.dart';
import 'package:demo_application/features/invoice/domain/services/printer_service.dart';
import 'package:demo_application/features/invoice/presentation/cubit/invoice_cubit.dart';
import 'package:demo_application/features/invoice/presentation/cubit/invoice_state.dart';
import 'package:demo_application/features/invoice/presentation/pages/invoice_history_page.dart';
import 'package:demo_application/features/invoice/presentation/pages/invoice_preview_page.dart';
import 'package:demo_application/features/settings/data/datasources/settings_local_datasource.dart';
import 'package:demo_application/features/settings/data/repositories/settings_repository_impl.dart';
import 'package:demo_application/features/settings/domain/repositories/settings_repository.dart';
import 'package:demo_application/features/settings/presentation/cubit/settings_cubit.dart';
import 'package:demo_application/features/settings/presentation/cubit/settings_state.dart';
import 'package:demo_application/features/settings/presentation/pages/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Root POS application wiring all 4 feature repositories, cubits, and shell navigation.
class PosDemoApp extends StatefulWidget {
  const PosDemoApp({
    super.key,
    required this.sharedPreferences,
    this.dioClient,
    this.settingsRepository,
    this.catalogRepository,
    this.cartRepository,
    this.invoiceRepository,
    this.printerService,
    this.imageBuilder,
    this.videoPreviewBuilder,
  });

  final SharedPreferences sharedPreferences;
  final DioClient? dioClient;
  final SettingsRepository? settingsRepository;
  final CatalogRepository? catalogRepository;
  final CartRepository? cartRepository;
  final InvoiceRepository? invoiceRepository;
  final PrinterService? printerService;
  final Widget Function(BuildContext context, String url)? imageBuilder;
  final Widget Function(BuildContext context, ProductMedia media)?
      videoPreviewBuilder;

  @override
  State<PosDemoApp> createState() => _PosDemoAppState();
}

class _PosDemoAppState extends State<PosDemoApp> {
  late final DioClient _dioClient;
  late final SettingsRepository _settingsRepository;
  late final CatalogRepository _catalogRepository;
  late final CartRepository _cartRepository;
  late final InvoiceRepository _invoiceRepository;
  late final PrinterService _printerService;

  @override
  void initState() {
    super.initState();
    _dioClient = widget.dioClient ?? DioClient();
    _settingsRepository = widget.settingsRepository ??
        SettingsRepositoryImpl(
          localDataSource: SettingsLocalDataSource(
            prefs: widget.sharedPreferences,
          ),
        );
    _catalogRepository = widget.catalogRepository ??
        CatalogRepositoryImpl(
          remoteDatasource: CatalogRemoteDatasource(dioClient: _dioClient),
        );
    _cartRepository = widget.cartRepository ??
        CartRepositoryImpl(
          localDataSource: CartLocalDataSource(prefs: widget.sharedPreferences),
        );
    _invoiceRepository = widget.invoiceRepository ??
        InvoiceRepositoryImpl(
          remoteDatasource: InvoiceRemoteDatasource(dioClient: _dioClient),
        );
    _printerService = widget.printerService ??
        EscPosRasterPrinterService(pdfInvoiceService: PdfInvoiceService());
  }

  @override
  Widget build(BuildContext context) {
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider<SettingsRepository>.value(value: _settingsRepository),
        RepositoryProvider<CatalogRepository>.value(value: _catalogRepository),
        RepositoryProvider<CartRepository>.value(value: _cartRepository),
        RepositoryProvider<InvoiceRepository>.value(value: _invoiceRepository),
        RepositoryProvider<PrinterService>.value(value: _printerService),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider<SettingsCubit>(
            create: (_) => SettingsCubit(
              repository: _settingsRepository,
              dioClient: _dioClient,
            ),
          ),
          BlocProvider<CatalogCubit>(
            create: (_) => CatalogCubit(_catalogRepository),
          ),
          BlocProvider<CartCubit>(
            create: (_) => CartCubit(repository: _cartRepository),
          ),
          BlocProvider<InvoiceCubit>(
            create: (_) => InvoiceCubit(
              repository: _invoiceRepository,
              printerService: _printerService,
            ),
          ),
        ],
        child: MaterialApp(
          title: 'POS Hóa Đơn',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFFEE4D2D),
            ),
          ),
          home: MainShellPage(
            imageBuilder: widget.imageBuilder,
            videoPreviewBuilder: widget.videoPreviewBuilder,
          ),
        ),
      ),
    );
  }
}

/// Primary 4-tab POS shell coordinating startup sequence, checkout, and invoice preview.
class MainShellPage extends StatefulWidget {
  const MainShellPage({
    super.key,
    this.imageBuilder,
    this.videoPreviewBuilder,
  });

  final Widget Function(BuildContext context, String url)? imageBuilder;
  final Widget Function(BuildContext context, ProductMedia media)?
      videoPreviewBuilder;

  @override
  State<MainShellPage> createState() => _MainShellPageState();
}

class _MainShellPageState extends State<MainShellPage> {
  static const int _catalogTab = 0;
  static const int _historyTab = 2;
  static const int _settingsTab = 3;

  int _currentIndex = _catalogTab;

  @override
  void initState() {
    super.initState();
    unawaited(_bootstrap());
  }

  Future<void> _bootstrap() async {
    final settingsCubit = context.read<SettingsCubit>();
    final catalogCubit = context.read<CatalogCubit>();
    final cartCubit = context.read<CartCubit>();

    // Sync persisted serverUrl into DioClient before starting catalog network requests.
    await settingsCubit.loadSettings();
    if (!mounted) return;

    unawaited(catalogCubit.loadInitial());
    unawaited(cartCubit.loadDraftCart());
  }

  void _switchToTab(int index) {
    setState(() => _currentIndex = index);
    if (index == _historyTab) {
      context.read<InvoiceCubit>().loadHistory();
    }
  }

  void _handleAddToCart(BuildContext context, Product product) {
    context.read<CartCubit>().addProduct(product);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Đã thêm "${product.name}" vào giỏ hàng'),
          duration: const Duration(milliseconds: 1200),
        ),
      );
  }

  Future<void> _handleCheckout(BuildContext context, CartState cartState) async {
    final invoiceCubit = context.read<InvoiceCubit>();
    if (invoiceCubit.state.status == InvoiceStatus.submitting) return;

    final store = context.read<SettingsCubit>().state.settings.store;
    final invoice = await invoiceCubit.submitOrderAndOpenPreview(
      cart: cartState,
      store: store,
    );
    if (!context.mounted) return;

    if (invoice == null) {
      final error = invoiceCubit.state.errorMessage;
      if (error != null && error.isNotEmpty) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(error),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
      }
      return;
    }

    await context.read<CartCubit>().clearCart();
    if (!context.mounted) return;

    final soldQuantities = <int, double>{};
    for (final item in invoice.items) {
      soldQuantities.update(
        item.productId,
        (existing) => existing + item.quantity,
        ifAbsent: () => item.quantity,
      );
    }
    context.read<CatalogCubit>().decrementLocalStock(soldQuantities);

    await _openInvoicePreview(context);
  }

  Future<void> _openInvoicePreview(BuildContext context) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => BlocBuilder<SettingsCubit, SettingsState>(
          builder: (routeContext, settingsState) {
            return InvoicePreviewPage(
              printerConfig: settingsState.settings.printer,
              onOpenPrinterSettings: () {
                Navigator.of(routeContext).popUntil((route) => route.isFirst);
                _switchToTab(_settingsTab);
              },
            );
          },
        ),
      ),
    );
  }

  static String _formatCartBadge(CartState state) {
    final total = state.summary.totalQuantity;
    if (total <= 0) return '';
    if (total > 99) return '99+';
    return total == total.roundToDouble()
        ? total.toInt().toString()
        : total.toStringAsFixed(1);
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<SettingsCubit, SettingsState>(
      listenWhen: (previous, current) =>
          current.status == SettingsStatus.saved &&
          previous.status != SettingsStatus.saved &&
          previous.settings.serverUrl != current.settings.serverUrl,
      listener: (context, _) {
        final catalogCubit = context.read<CatalogCubit>();
        catalogCubit.loadInitial(query: catalogCubit.state.searchQuery);
      },
      child: Scaffold(
        body: IndexedStack(
          index: _currentIndex,
          children: [
            Scaffold(
              appBar: AppBar(title: const Text('Danh mục sản phẩm')),
              body: CatalogPage(
                imageBuilder: widget.imageBuilder,
                videoPreviewBuilder: widget.videoPreviewBuilder,
                onAddToCart: (product) => _handleAddToCart(context, product),
              ),
            ),
            BlocBuilder<InvoiceCubit, InvoiceState>(
              buildWhen: (previous, current) =>
                  previous.status != current.status,
              builder: (context, invoiceState) {
                return CartPage(
                  isSubmitting: invoiceState.status == InvoiceStatus.submitting,
                  onCheckout: (cartState) => _handleCheckout(context, cartState),
                );
              },
            ),
            BlocBuilder<SettingsCubit, SettingsState>(
              buildWhen: (previous, current) =>
                  previous.settings.printer != current.settings.printer,
              builder: (context, settingsState) {
                return InvoiceHistoryPage(
                  loadOnInit: false,
                  printerConfig: settingsState.settings.printer,
                  onOpenPrinterSettings: () => _switchToTab(_settingsTab),
                  onSelectInvoice: (_) => _openInvoicePreview(context),
                );
              },
            ),
            const SettingsPage(),
          ],
        ),
        bottomNavigationBar: BlocBuilder<CartCubit, CartState>(
          buildWhen: (previous, current) =>
              previous.summary.totalQuantity != current.summary.totalQuantity ||
              previous.items.length != current.items.length,
          builder: (context, cartState) {
            final badgeText = _formatCartBadge(cartState);
            final showBadge =
                cartState.items.isNotEmpty && badgeText.isNotEmpty;

            return NavigationBar(
              selectedIndex: _currentIndex,
              onDestinationSelected: _switchToTab,
              destinations: [
                const NavigationDestination(
                  icon: Icon(Icons.storefront_outlined),
                  selectedIcon: Icon(Icons.storefront),
                  label: 'Sản phẩm',
                ),
                NavigationDestination(
                  icon: Badge(
                    isLabelVisible: showBadge,
                    label: Text(badgeText),
                    child: const Icon(Icons.shopping_cart_outlined),
                  ),
                  selectedIcon: Badge(
                    isLabelVisible: showBadge,
                    label: Text(badgeText),
                    child: const Icon(Icons.shopping_cart),
                  ),
                  label: 'Giỏ hàng',
                ),
                const NavigationDestination(
                  icon: Icon(Icons.receipt_long_outlined),
                  selectedIcon: Icon(Icons.receipt_long),
                  label: 'Hóa đơn',
                ),
                const NavigationDestination(
                  icon: Icon(Icons.settings_outlined),
                  selectedIcon: Icon(Icons.settings),
                  label: 'Cài đặt',
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
