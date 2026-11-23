import 'package:demo_application/core/utils/currency_formatter.dart';
import 'package:demo_application/features/cart/domain/entities/cart_item.dart';
import 'package:demo_application/features/cart/presentation/cubit/cart_cubit.dart';
import 'package:demo_application/features/cart/presentation/cubit/cart_state.dart';
import 'package:demo_application/features/cart/presentation/widgets/cart_item_edit_sheet.dart';
import 'package:demo_application/features/settings/domain/entities/app_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// POS shopping cart screen for editing line items, order discounts, staff, payment, and checkout.
class CartPage extends StatefulWidget {
  const CartPage({
    super.key,
    this.onCheckout,
    this.isSubmitting = false,
  });

  final void Function(CartState state)? onCheckout;
  final bool isSubmitting;

  @override
  State<CartPage> createState() => _CartPageState();
}

class _CartPageState extends State<CartPage> {
  late final TextEditingController _orderDiscountController;
  late final FocusNode _orderDiscountFocusNode;

  @override
  void initState() {
    super.initState();
    final initialDiscount = context.read<CartCubit>().state.orderDiscountPercent;
    _orderDiscountController =
        TextEditingController(text: _formatNumber(initialDiscount));
    _orderDiscountFocusNode = FocusNode()
      ..addListener(_onOrderDiscountFocusChanged);
  }

  @override
  void dispose() {
    _orderDiscountFocusNode
      ..removeListener(_onOrderDiscountFocusChanged)
      ..dispose();
    _orderDiscountController.dispose();
    super.dispose();
  }

  static String _formatNumber(double value) {
    return value == value.roundToDouble()
        ? value.toInt().toString()
        : value.toString();
  }

  void _onOrderDiscountFocusChanged() {
    if (!_orderDiscountFocusNode.hasFocus) {
      _syncOrderDiscountField(
        context.read<CartCubit>().state.orderDiscountPercent,
        forceIfEmpty: true,
      );
    }
  }

  void _syncOrderDiscountField(double percent, {bool forceIfEmpty = false}) {
    final text = _orderDiscountController.text.trim();
    if (!forceIfEmpty &&
        _orderDiscountFocusNode.hasFocus &&
        text.isEmpty &&
        percent == 0) {
      return;
    }
    final currentParsed = double.tryParse(text.replaceAll(',', '.'));
    if (currentParsed == percent) return;
    _orderDiscountController.text = _formatNumber(percent);
  }

  void _onOrderDiscountChanged(String raw) {
    final normalized = raw.trim().replaceAll(',', '.');
    if (normalized.isEmpty) {
      context.read<CartCubit>().setOrderDiscountPercent(0);
      return;
    }
    final parsed = double.tryParse(normalized);
    if (parsed != null) {
      context.read<CartCubit>().setOrderDiscountPercent(parsed);
    }
  }

  Future<void> _openEditSheet(CartItem item) async {
    final cubit = context.read<CartCubit>();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => CartItemEditSheet(
        item: item,
        onSave: ({
          required double quantity,
          required double discountPercent,
          required double vatRate,
          required String note,
        }) {
          cubit.updateItem(
            item.productId,
            quantity: quantity,
            discountPercent: discountPercent,
            vatRate: vatRate,
            note: note,
          );
        },
        onRemove: () => cubit.removeItem(item.productId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<CartCubit, CartState>(
      listenWhen: (previous, current) =>
          previous.errorNonce != current.errorNonce ||
          previous.orderDiscountPercent != current.orderDiscountPercent ||
          previous.isEmpty != current.isEmpty,
      listener: (context, state) {
        _syncOrderDiscountField(
          state.orderDiscountPercent,
          forceIfEmpty: state.isEmpty,
        );
        if (state.errorMessage != null && state.errorMessage!.isNotEmpty) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              SnackBar(
                content: Text(state.errorMessage!),
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
            );
        }
      },
      builder: (context, state) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Giỏ hàng POS'),
            actions: [
              if (state.isNotEmpty)
                TextButton.icon(
                  onPressed: widget.isSubmitting
                      ? null
                      : () => context.read<CartCubit>().clearCart(),
                  icon: const Icon(Icons.delete_sweep_outlined),
                  label: const Text('Xóa giỏ'),
                ),
            ],
          ),
          body: state.isEmpty
              ? const _EmptyCartView()
              : Column(
                  children: [
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.all(12),
                        children: [
                          ...state.items.map(
                            (item) => _CartItemCard(
                              item: item,
                              enabled: !widget.isSubmitting,
                              onTap: () => _openEditSheet(item),
                              onDecrement: () {
                                if (item.quantity <= 1) {
                                  context
                                      .read<CartCubit>()
                                      .removeItem(item.productId);
                                } else {
                                  context.read<CartCubit>().updateItem(
                                        item.productId,
                                        quantity: item.quantity - 1,
                                      );
                                }
                              },
                              onIncrement: () {
                                context.read<CartCubit>().updateItem(
                                      item.productId,
                                      quantity: item.quantity + 1,
                                    );
                              },
                            ),
                          ),
                          const SizedBox(height: 8),
                          _OrderOptionsCard(
                            state: state,
                            enabled: !widget.isSubmitting,
                            orderDiscountController: _orderDiscountController,
                            orderDiscountFocusNode: _orderDiscountFocusNode,
                            onOrderDiscountChanged: _onOrderDiscountChanged,
                          ),
                        ],
                      ),
                    ),
                    _CartSummaryFooter(
                      state: state,
                      isSubmitting: widget.isSubmitting,
                      onCheckout: widget.onCheckout == null
                          ? null
                          : () => widget.onCheckout!(state),
                    ),
                  ],
                ),
        );
      },
    );
  }
}

class _EmptyCartView extends StatelessWidget {
  const _EmptyCartView();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.shopping_cart_outlined,
              size: 64,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 12),
            Text(
              'Giỏ hàng đang trống',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Chọn sản phẩm từ danh mục để thêm vào đơn hàng',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _CartItemCard extends StatelessWidget {
  const _CartItemCard({
    required this.item,
    required this.enabled,
    required this.onTap,
    required this.onDecrement,
    required this.onIncrement,
  });

  final CartItem item;
  final bool enabled;
  final VoidCallback onTap;
  final VoidCallback onDecrement;
  final VoidCallback onIncrement;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final calc = item.calculation;
    final qtyText = item.quantity == item.quantity.roundToDouble()
        ? item.quantity.toInt().toString()
        : item.quantity.toString();

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.name,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${item.sku} • ${CurrencyFormatter.formatVnd(item.unitPrice)}/${item.unit}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    CurrencyFormatter.formatVnd(calc.lineTotal),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        if (item.discountPercent > 0)
                          _MetaTag(
                            label: 'CK ${_formatRate(item.discountPercent)}%',
                            color: theme.colorScheme.errorContainer,
                            textColor: theme.colorScheme.onErrorContainer,
                          ),
                        _MetaTag(
                          label: 'VAT ${_formatRate(item.vatRate)}%',
                          color: theme.colorScheme.secondaryContainer,
                          textColor: theme.colorScheme.onSecondaryContainer,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: enabled ? onDecrement : null,
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 110),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Text(
                        '$qtyText ${item.unit}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: enabled ? onIncrement : null,
                    icon: const Icon(Icons.add_circle_outline),
                  ),
                ],
              ),
              if (item.note.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  'Ghi chú: ${item.note}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontStyle: FontStyle.italic,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static String _formatRate(double value) {
    return value == value.roundToDouble()
        ? value.toInt().toString()
        : value.toString();
  }
}

class _MetaTag extends StatelessWidget {
  const _MetaTag({
    required this.label,
    required this.color,
    required this.textColor,
  });

  final String label;
  final Color color;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: textColor,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

class _OrderOptionsCard extends StatelessWidget {
  const _OrderOptionsCard({
    required this.state,
    required this.enabled,
    required this.orderDiscountController,
    required this.orderDiscountFocusNode,
    required this.onOrderDiscountChanged,
  });

  final CartState state;
  final bool enabled;
  final TextEditingController orderDiscountController;
  final FocusNode orderDiscountFocusNode;
  final ValueChanged<String> onOrderDiscountChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final staffOptions = {
      ...AppSettings.sampleStaffNames,
      if (state.staffName.isNotEmpty) state.staffName,
    }.toList(growable: false);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Thông tin đơn hàng',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: DropdownButtonFormField<String>(
                    key: ValueKey('cart_staff_${state.staffName}'),
                    initialValue: state.staffName,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Nhân viên',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: staffOptions
                        .map(
                          (staff) => DropdownMenuItem<String>(
                            value: staff,
                            child: Text(
                              staff,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: enabled
                        ? (value) {
                            if (value != null) {
                              context.read<CartCubit>().setStaffName(value);
                            }
                          }
                        : null,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: TextField(
                    key: const Key('cart_order_discount_field'),
                    controller: orderDiscountController,
                    focusNode: orderDiscountFocusNode,
                    enabled: enabled,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: '% Giảm giá đơn',
                      suffixText: '%',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: onOrderDiscountChanged,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Hình thức thanh toán',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: CartCubit.paymentMethods
                  .map(
                    (method) => ChoiceChip(
                      label: Text(method),
                      selected: state.paymentMethod == method,
                      onSelected: enabled
                          ? (_) =>
                              context.read<CartCubit>().setPaymentMethod(method)
                          : null,
                    ),
                  )
                  .toList(growable: false),
            ),
          ],
        ),
      ),
    );
  }
}

class _CartSummaryFooter extends StatelessWidget {
  const _CartSummaryFooter({
    required this.state,
    required this.isSubmitting,
    required this.onCheckout,
  });

  final CartState state;
  final bool isSubmitting;
  final VoidCallback? onCheckout;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final summary = state.summary;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SummaryRow(
              label: 'Tổng giá trị đơn',
              value: CurrencyFormatter.formatVnd(summary.subtotal),
            ),
            const SizedBox(height: 4),
            _SummaryRow(
              label: 'Tiền giảm',
              value: CurrencyFormatter.formatVnd(summary.orderDiscountAmount),
            ),
            const Divider(height: 16),
            _SummaryRow(
              label: 'Tổng cần thanh toán',
              value: CurrencyFormatter.formatVnd(summary.totalPayable),
              highlight: true,
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: state.isEmpty || isSubmitting ? null : onCheckout,
              icon: isSubmitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.receipt_long_outlined),
              label: const Text('Thanh toán & Xuất hóa đơn'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.label,
    required this.value,
    this.highlight = false,
  });

  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelStyle = highlight
        ? theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)
        : theme.textTheme.bodyMedium;
    final valueStyle = highlight
        ? theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
            color: theme.colorScheme.primary,
          )
        : theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600);

    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: labelStyle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        Text(value, style: valueStyle),
      ],
    );
  }
}
