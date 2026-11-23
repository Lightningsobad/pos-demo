import 'package:intl/intl.dart';

/// Formats numeric monetary values as `###,### đ` for VND display.
abstract final class CurrencyFormatter {
  static final NumberFormat _vndFormat = NumberFormat('#,##0', 'en_US');

  static String formatVnd(num amount) {
    if (!amount.isFinite) {
      throw ArgumentError.value(amount, 'amount', 'Must be finite');
    }
    return '${_vndFormat.format(amount.round())} đ';
  }
}
