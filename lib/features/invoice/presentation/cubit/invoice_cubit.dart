import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:demo_application/features/cart/presentation/cubit/cart_state.dart';
import 'package:demo_application/features/invoice/domain/entities/invoice.dart';
import 'package:demo_application/features/invoice/domain/repositories/invoice_repository.dart';
import 'package:demo_application/features/invoice/domain/services/printer_service.dart';
import 'package:demo_application/features/invoice/presentation/cubit/invoice_state.dart';
import 'package:demo_application/features/settings/domain/entities/app_settings.dart';
import 'package:dio/dio.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Cubit coordinating backend order submission, history retrieval, and dual printing.
class InvoiceCubit extends Cubit<InvoiceState> {
  InvoiceCubit({
    required this._repository,
    required this._printerService,
  }) : super(const InvoiceState());

  final InvoiceRepository _repository;
  final PrinterService _printerService;

  /// Submits [cart] to `POST /api/orders` once and opens preview with the persisted invoice.
  Future<Invoice?> submitOrderAndOpenPreview({
    required CartState cart,
    required StoreConfig store,
  }) async {
    if (cart.items.isEmpty) {
      _emitError('Giỏ hàng trống, không thể tạo hóa đơn');
      return null;
    }
    if (cart.staffName.trim().isEmpty) {
      _emitError('Vui lòng chọn nhân viên bán hàng');
      return null;
    }
    if (store.name.trim().isEmpty) {
      _emitError('Vui lòng cấu hình tên cửa hàng trước khi tạo hóa đơn');
      return null;
    }

    emit(state.copyWith(status: InvoiceStatus.submitting, clearError: true));

    try {
      final request = CreateOrderRequest.fromCart(cart: cart, store: store);
      final invoice = await _repository.createOrder(request);
      if (isClosed) return null;

      emit(
        state.copyWith(
          status: InvoiceStatus.ready,
          currentInvoice: invoice,
          clearError: true,
        ),
      );
      return invoice;
    } catch (error) {
      if (isClosed) return null;
      emit(
        state.copyWith(
          status: state.currentInvoice != null
              ? InvoiceStatus.ready
              : InvoiceStatus.initial,
          errorMessage: _formatError('Không thể tạo đơn hàng', error),
          errorNonce: state.errorNonce + 1,
        ),
      );
      return null;
    }
  }

  /// Prints [InvoiceState.currentInvoice] using [config], preserving `currentInvoice` on failure.
  Future<bool> printCurrentInvoice(
    PrinterConfig config, {
    Future<Uint8List> Function()? capturePng,
  }) async {
    final invoice = state.currentInvoice;
    if (invoice == null) {
      _emitError('Chưa có hóa đơn để in');
      return false;
    }

    emit(state.copyWith(status: InvoiceStatus.printing, clearError: true));

    try {
      if (config.mode == PrinterMode.pdfSystem) {
        await _printerService.printPdf(invoice: invoice);
      } else {
        if (capturePng == null) {
          throw const PrinterException(
            'Thiếu ảnh xem trước để gửi ra máy in nhiệt',
          );
        }
        final pngBytes = await capturePng();
        await _printerService.printEscPos(
          invoice: invoice,
          config: config,
          receiptPngBytes: pngBytes,
        );
      }

      if (isClosed) return false;
      emit(
        state.copyWith(
          status: InvoiceStatus.ready,
          lastPrintedMode: config.mode,
          printSuccessNonce: state.printSuccessNonce + 1,
          clearError: true,
        ),
      );
      return true;
    } catch (error) {
      if (isClosed) return false;
      // Always keep currentInvoice so the user can retry or fall back to PDF without re-posting.
      emit(
        state.copyWith(
          status: InvoiceStatus.ready,
          errorMessage: _formatError('In hóa đơn thất bại', error),
          errorNonce: state.errorNonce + 1,
        ),
      );
      return false;
    }
  }

  /// Convenience wrapper to print the current invoice via Android/system PDF dialog.
  Future<bool> printPdfCurrentInvoice() {
    return printCurrentInvoice(
      const PrinterConfig(mode: PrinterMode.pdfSystem),
    );
  }

  /// Loads recent invoices from `GET /api/orders`.
  Future<void> loadHistory({int limit = 20}) async {
    emit(state.copyWith(isLoadingHistory: true, clearError: true));
    try {
      final orders = await _repository.fetchOrders(limit: limit);
      if (isClosed) return;
      emit(
        state.copyWith(
          isLoadingHistory: false,
          history: List<Invoice>.unmodifiable(orders),
          clearError: true,
        ),
      );
    } catch (error) {
      if (isClosed) return;
      emit(
        state.copyWith(
          isLoadingHistory: false,
          errorMessage: _formatError('Không thể tải lịch sử hóa đơn', error),
          errorNonce: state.errorNonce + 1,
        ),
      );
    }
  }

  /// Selects an existing invoice from history for preview and reprinting.
  void selectInvoice(Invoice invoice) {
    emit(
      state.copyWith(
        status: InvoiceStatus.ready,
        currentInvoice: invoice,
        clearError: true,
      ),
    );
  }

  void _emitError(String message) {
    emit(
      state.copyWith(
        errorMessage: message,
        errorNonce: state.errorNonce + 1,
      ),
    );
  }

  static String _formatError(String prefix, Object error) {
    if (error is PrinterException) {
      return '$prefix: ${error.message}';
    }
    if (error is SocketException) {
      return '$prefix: Không kết nối được máy in/máy chủ (${error.message})';
    }
    if (error is TimeoutException) {
      return '$prefix: Quá thời gian chờ phản hồi';
    }
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map && data['error'] != null) {
        return '$prefix: ${data['error']}';
      }
      return '$prefix: ${error.message ?? error.type.name}';
    }
    return '$prefix: $error';
  }
}
