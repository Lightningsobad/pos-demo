import 'package:demo_application/features/invoice/data/datasources/invoice_remote_datasource.dart';
import 'package:demo_application/features/invoice/domain/entities/invoice.dart';
import 'package:demo_application/features/invoice/domain/repositories/invoice_repository.dart';

/// Concrete [InvoiceRepository] backed by [InvoiceRemoteDatasource].
class InvoiceRepositoryImpl implements InvoiceRepository {
  InvoiceRepositoryImpl({required this._remoteDatasource});

  final InvoiceRemoteDatasource _remoteDatasource;

  @override
  Future<Invoice> createOrder(CreateOrderRequest request) {
    return _remoteDatasource.createOrder(request);
  }

  @override
  Future<List<Invoice>> fetchOrders({int limit = 20}) {
    return _remoteDatasource.fetchOrders(limit: limit);
  }
}
