import 'package:demo_application/features/cart/data/datasources/cart_local_datasource.dart';
import 'package:demo_application/features/cart/domain/repositories/cart_repository.dart';

/// Repository implementation delegating draft cart persistence to [CartLocalDataSource].
class CartRepositoryImpl implements CartRepository {
  CartRepositoryImpl({required this._localDataSource});

  final CartLocalDataSource _localDataSource;

  @override
  Future<CartDraft> loadDraft() => _localDataSource.loadDraft();

  @override
  Future<void> saveDraft(CartDraft draft) => _localDataSource.saveDraft(draft);

  @override
  Future<void> clearDraft() => _localDataSource.clearDraft();
}
