import 'package:demo_application/features/invoice/domain/entities/invoice.dart';
import 'package:demo_application/features/settings/domain/entities/app_settings.dart';
import 'package:equatable/equatable.dart';

/// Lifecycle status for invoice creation and printing.
enum InvoiceStatus { initial, submitting, ready, printing }

/// Immutable state managed by [InvoiceCubit].
class InvoiceState extends Equatable {
  const InvoiceState({
    this.status = InvoiceStatus.initial,
    this.currentInvoice,
    this.history = const [],
    this.isLoadingHistory = false,
    this.lastPrintedMode,
    this.printSuccessNonce = 0,
    this.errorMessage,
    this.errorNonce = 0,
  });

  final InvoiceStatus status;
  final Invoice? currentInvoice;
  final List<Invoice> history;
  final bool isLoadingHistory;
  final PrinterMode? lastPrintedMode;
  final int printSuccessNonce;
  final String? errorMessage;
  final int errorNonce;

  InvoiceState copyWith({
    InvoiceStatus? status,
    Invoice? currentInvoice,
    List<Invoice>? history,
    bool? isLoadingHistory,
    PrinterMode? lastPrintedMode,
    int? printSuccessNonce,
    String? errorMessage,
    int? errorNonce,
    bool clearError = false,
  }) {
    return InvoiceState(
      status: status ?? this.status,
      currentInvoice: currentInvoice ?? this.currentInvoice,
      history: history ?? this.history,
      isLoadingHistory: isLoadingHistory ?? this.isLoadingHistory,
      lastPrintedMode: lastPrintedMode ?? this.lastPrintedMode,
      printSuccessNonce: printSuccessNonce ?? this.printSuccessNonce,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      errorNonce: errorNonce ?? this.errorNonce,
    );
  }

  @override
  List<Object?> get props => [
        status,
        currentInvoice,
        history,
        isLoadingHistory,
        lastPrintedMode,
        printSuccessNonce,
        errorMessage,
        errorNonce,
      ];
}
