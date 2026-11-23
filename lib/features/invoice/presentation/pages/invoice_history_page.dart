import 'package:demo_application/core/utils/currency_formatter.dart';
import 'package:demo_application/features/invoice/domain/entities/invoice.dart';
import 'package:demo_application/features/invoice/presentation/cubit/invoice_cubit.dart';
import 'package:demo_application/features/invoice/presentation/cubit/invoice_state.dart';
import 'package:demo_application/features/invoice/presentation/pages/invoice_preview_page.dart';
import 'package:demo_application/features/settings/domain/entities/app_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

/// Screen listing recent backend invoices from `GET /api/orders` for preview and reprinting.
class InvoiceHistoryPage extends StatefulWidget {
  const InvoiceHistoryPage({
    super.key,
    this.printerConfig = const PrinterConfig(),
    this.onOpenPrinterSettings,
    this.onSelectInvoice,
    this.loadOnInit = true,
  });

  final PrinterConfig printerConfig;
  final VoidCallback? onOpenPrinterSettings;
  final void Function(Invoice invoice)? onSelectInvoice;
  final bool loadOnInit;

  @override
  State<InvoiceHistoryPage> createState() => _InvoiceHistoryPageState();
}

class _InvoiceHistoryPageState extends State<InvoiceHistoryPage> {
  static final DateFormat _dateTimeFormat = DateFormat('dd/MM/yyyy HH:mm');

  @override
  void initState() {
    super.initState();
    if (widget.loadOnInit) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          context.read<InvoiceCubit>().loadHistory();
        }
      });
    }
  }

  void _openInvoice(BuildContext context, Invoice invoice) {
    final cubit = context.read<InvoiceCubit>();
    cubit.selectInvoice(invoice);
    if (widget.onSelectInvoice != null) {
      widget.onSelectInvoice!(invoice);
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BlocProvider.value(
          value: cubit,
          child: InvoicePreviewPage(
            printerConfig: widget.printerConfig,
            onOpenPrinterSettings: widget.onOpenPrinterSettings,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<InvoiceCubit, InvoiceState>(
      builder: (context, state) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Lịch sử hóa đơn'),
            actions: [
              IconButton(
                tooltip: 'Tải lại',
                onPressed: state.isLoadingHistory
                    ? null
                    : () => context.read<InvoiceCubit>().loadHistory(),
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          body: _buildBody(context, state),
        );
      },
    );
  }

  Widget _buildBody(BuildContext context, InvoiceState state) {
    if (state.isLoadingHistory && state.history.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.history.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.receipt_long_outlined, size: 56),
              const SizedBox(height: 12),
              const Text(
                'Chưa có hóa đơn nào được tạo',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              if (state.errorMessage != null) ...[
                const SizedBox(height: 8),
                Text(
                  state.errorMessage!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => context.read<InvoiceCubit>().loadHistory(),
                icon: const Icon(Icons.refresh),
                label: const Text('Tải danh sách'),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => context.read<InvoiceCubit>().loadHistory(),
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: state.history.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final invoice = state.history[index];
          final localCreated = invoice.createdAt.toLocal();

          return Card(
            child: ListTile(
              leading: CircleAvatar(
                child: Text('${invoice.items.length}'),
              ),
              title: Text(
                invoice.orderCode,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(
                '${_dateTimeFormat.format(localCreated)} • ${invoice.staffName}\n${invoice.paymentMethod}',
              ),
              isThreeLine: true,
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    CurrencyFormatter.formatVnd(invoice.totalPayable),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Icon(Icons.chevron_right, size: 18),
                ],
              ),
              onTap: () => _openInvoice(context, invoice),
            ),
          );
        },
      ),
    );
  }
}
