import 'package:demo_application/core/utils/currency_formatter.dart';
import 'package:demo_application/core/utils/pos_calculator.dart';
import 'package:demo_application/features/cart/domain/entities/cart_item.dart';
import 'package:flutter/material.dart';

/// Bottom sheet allowing the cashier to adjust line quantity, discount %, VAT %, and note.
class CartItemEditSheet extends StatefulWidget {
  const CartItemEditSheet({
    super.key,
    required this.item,
    required this.onSave,
    this.onRemove,
  });

  final CartItem item;
  final void Function({
    required double quantity,
    required double discountPercent,
    required double vatRate,
    required String note,
  }) onSave;
  final VoidCallback? onRemove;

  @override
  State<CartItemEditSheet> createState() => _CartItemEditSheetState();
}

class _CartItemEditSheetState extends State<CartItemEditSheet> {
  static const List<double> _quickVatRates = [0, 5, 8, 10];

  late final TextEditingController _quantityController;
  late final TextEditingController _discountController;
  late final TextEditingController _vatController;
  late final TextEditingController _noteController;

  String? _validationError;

  @override
  void initState() {
    super.initState();
    _quantityController =
        TextEditingController(text: _formatNumber(widget.item.quantity));
    _discountController =
        TextEditingController(text: _formatNumber(widget.item.discountPercent));
    _vatController =
        TextEditingController(text: _formatNumber(widget.item.vatRate));
    _noteController = TextEditingController(text: widget.item.note);
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _discountController.dispose();
    _vatController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  static String _formatNumber(double value) {
    return value == value.roundToDouble()
        ? value.toInt().toString()
        : value.toString();
  }

  static double? _parseNumber(String raw) {
    final normalized = raw.trim().replaceAll(',', '.');
    if (normalized.isEmpty) return null;
    final parsed = double.tryParse(normalized);
    return parsed != null && parsed.isFinite ? parsed : null;
  }

  void _stepQuantity(double delta) {
    final current = _parseNumber(_quantityController.text) ?? widget.item.quantity;
    final next = current + delta;
    if (next <= 0) return;
    setState(() {
      _quantityController.text = _formatNumber(next);
      _validationError = null;
    });
  }

  void _selectVat(double rate) {
    setState(() {
      _vatController.text = _formatNumber(rate);
      _validationError = null;
    });
  }

  PosLineCalculation? _previewCalculation() {
    final qty = _parseNumber(_quantityController.text);
    final discount = _parseNumber(_discountController.text);
    final vat = _parseNumber(_vatController.text);
    if (qty == null ||
        qty <= 0 ||
        discount == null ||
        discount < 0 ||
        discount > 100 ||
        vat == null ||
        vat < 0 ||
        vat > 100) {
      return null;
    }
    return PosCalculator.calculateLine(
      unitPrice: widget.item.unitPrice,
      quantity: qty,
      discountPercent: discount,
      vatRate: vat,
    );
  }

  void _submit() {
    final qty = _parseNumber(_quantityController.text);
    final discount = _parseNumber(_discountController.text);
    final vat = _parseNumber(_vatController.text);

    if (qty == null || qty <= 0) {
      setState(() => _validationError = 'Số lượng phải lớn hơn 0');
      return;
    }
    if (discount == null || discount < 0 || discount > 100) {
      setState(
        () => _validationError = 'Chiết khấu phải nằm trong khoảng 0% - 100%',
      );
      return;
    }
    if (vat == null || vat < 0 || vat > 100) {
      setState(
        () => _validationError = 'Thuế VAT phải nằm trong khoảng 0% - 100%',
      );
      return;
    }

    widget.onSave(
      quantity: qty,
      discountPercent: discount,
      vatRate: vat,
      note: _noteController.text.trim(),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final preview = _previewCalculation();
    final currentVat = _parseNumber(_vatController.text);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomInset),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.item.name,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${widget.item.sku} • ${CurrencyFormatter.formatVnd(widget.item.unitPrice)}/${widget.item.unit}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (widget.onRemove != null)
                  IconButton(
                    tooltip: 'Xóa sản phẩm',
                    onPressed: () {
                      widget.onRemove!();
                      Navigator.of(context).pop();
                    },
                    icon: Icon(
                      Icons.delete_outline,
                      color: theme.colorScheme.error,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                IconButton.outlined(
                  onPressed: () => _stepQuantity(-1),
                  icon: const Icon(Icons.remove),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    key: const Key('cart_edit_quantity_field'),
                    controller: _quantityController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Số lượng',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (_) => setState(() => _validationError = null),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.outlined(
                  onPressed: () => _stepQuantity(1),
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('cart_edit_discount_field'),
                    controller: _discountController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Chiết khấu (%)',
                      suffixText: '%',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (_) => setState(() => _validationError = null),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    key: const Key('cart_edit_vat_field'),
                    controller: _vatController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Thuế VAT (%)',
                      suffixText: '%',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (_) => setState(() => _validationError = null),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: _quickVatRates
                  .map(
                    (rate) => ChoiceChip(
                      label: Text('${rate.toInt()}%'),
                      selected: currentVat == rate,
                      onSelected: (_) => _selectVat(rate),
                    ),
                  )
                  .toList(growable: false),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('cart_edit_note_field'),
              controller: _noteController,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Ghi chú hàng',
                hintText: 'Ví dụ: Ít đá, gói riêng...',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            if (_validationError != null) ...[
              const SizedBox(height: 10),
              Text(
                _validationError!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            if (preview != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  children: [
                    _PreviewRow(
                      label: 'Tiền hàng',
                      value: CurrencyFormatter.formatVnd(preview.grossAmount),
                    ),
                    _PreviewRow(
                      label: 'Chiết khấu dòng',
                      value:
                          '-${CurrencyFormatter.formatVnd(preview.discountAmount)}',
                    ),
                    _PreviewRow(
                      label: 'Thuế VAT',
                      value: CurrencyFormatter.formatVnd(preview.vatAmount),
                    ),
                    const Divider(height: 12),
                    _PreviewRow(
                      label: 'Thành tiền',
                      value: CurrencyFormatter.formatVnd(preview.lineTotal),
                      isBold: true,
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 14),
            FilledButton(
              onPressed: _submit,
              child: const Text('Áp dụng'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PreviewRow extends StatelessWidget {
  const _PreviewRow({
    required this.label,
    required this.value,
    this.isBold = false,
  });

  final String label;
  final String value;
  final bool isBold;

  @override
  Widget build(BuildContext context) {
    final style = isBold
        ? Theme.of(context)
            .textTheme
            .bodyMedium
            ?.copyWith(fontWeight: FontWeight.w700)
        : Theme.of(context).textTheme.bodySmall;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style),
          Text(value, style: style),
        ],
      ),
    );
  }
}
