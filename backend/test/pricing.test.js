import { describe, test } from 'node:test';
import assert from 'node:assert/strict';
import { calculateOrderPricing } from '../src/services/pricing.js';
import { openDatabase } from '../src/db/database.js';

describe('POS Pricing Service', () => {
  test('tinh chinh xac so le VNĐ cho chiet khau dong, VAT va giam gia don', () => {
    const result = calculateOrderPricing(
      [
        {
          productId: 1,
          sku: 'SP001',
          name: 'Ca phe sua da',
          unit: 'Ly',
          unitPrice: 33333,
          quantity: 3,
          discountPercent: 15,
          vatRate: 8,
          note: 'It da',
        },
      ],
      5,
    );

    assert.equal(result.items.length, 1);
    const line = result.items[0];
    assert.equal(line.discountAmount, 15000);
    assert.equal(line.vatAmount, 6800);
    assert.equal(line.lineTotal, 91799);
    assert.equal(result.subtotal, 91799);
    assert.equal(result.discountPercent, 5);
    assert.equal(result.discountAmount, 4590);
    assert.equal(result.totalPayable, 87209);
  });

  test('tinh tong nhieu dong hang voi thue suat va chiet khau khac nhau', () => {
    const result = calculateOrderPricing(
      [
        {
          productId: 1,
          sku: 'SP001',
          name: 'Tra dao',
          unit: 'Ly',
          unitPrice: 25000,
          quantity: 2,
          discountPercent: 0,
          vatRate: 8,
          note: null,
        },
        {
          productId: 2,
          sku: 'SP002',
          name: 'Banh mi',
          unit: 'Cai',
          unitPrice: 15000,
          quantity: 1,
          discountPercent: 10,
          vatRate: 0,
          note: 'Khong ot',
        },
      ],
      0,
    );

    // Line 1: 50000 - 0 = 50000; VAT 8% = 4000; total = 54000
    // Line 2: 15000 - 1500 = 13500; VAT 0% = 0; total = 13500
    assert.equal(result.items[0].lineTotal, 54000);
    assert.equal(result.items[1].lineTotal, 13500);
    assert.equal(result.subtotal, 67500);
    assert.equal(result.discountAmount, 0);
    assert.equal(result.totalPayable, 67500);
  });

  test('tu choi so luong <= 0 hoac % chiet khau ngoai [0, 100]', () => {
    const baseItem = {
      productId: 1,
      sku: 'SP001',
      name: 'Ca phe',
      unit: 'Ly',
      unitPrice: 20000,
      quantity: 1,
      discountPercent: 0,
      vatRate: 8,
    };

    assert.throws(
      () => calculateOrderPricing([{ ...baseItem, quantity: 0 }], 0),
      RangeError,
    );
    assert.throws(
      () => calculateOrderPricing([{ ...baseItem, discountPercent: 105 }], 0),
      RangeError,
    );
    assert.throws(
      () => calculateOrderPricing([baseItem], -1),
      RangeError,
    );
    assert.throws(
      () => calculateOrderPricing([], 0),
      RangeError,
    );
    assert.throws(
      () => calculateOrderPricing([{ ...baseItem, vatRate: 101 }], 0),
      RangeError,
    );
  });
});

describe('SQLite Database Schema', () => {
  test('openDatabase(:memory:) tao dung 3 bang, cot, index va bat foreign_keys', () => {
    const db = openDatabase(':memory:');
    try {
      const fk = db.prepare('PRAGMA foreign_keys').get();
      assert.equal(fk.foreign_keys, 1);

      const tables = db
        .prepare(
          "SELECT name FROM sqlite_master WHERE type = 'table' AND name IN ('products', 'orders', 'order_items') ORDER BY name",
        )
        .all()
        .map((row) => row.name);
      assert.deepEqual(tables, ['order_items', 'orders', 'products']);

      const productCols = db
        .prepare('PRAGMA table_info(products)')
        .all()
        .map((col) => col.name);
      assert.deepEqual(productCols, [
        'id',
        'sku',
        'name',
        'unit',
        'price',
        'vat_rate',
        'stock',
        'media_type',
        'media_url',
        'thumbnail_url',
      ]);

      const orderCols = db
        .prepare('PRAGMA table_info(orders)')
        .all()
        .map((col) => col.name);
      assert.deepEqual(orderCols, [
        'id',
        'order_code',
        'staff_name',
        'payment_method',
        'subtotal',
        'discount_percent',
        'discount_amount',
        'total_payable',
        'store_name',
        'store_phone',
        'store_address',
        'store_logo_url',
        'created_at',
      ]);

      const orderItemCols = db
        .prepare('PRAGMA table_info(order_items)')
        .all()
        .map((col) => col.name);
      assert.deepEqual(orderItemCols, [
        'id',
        'order_id',
        'product_id',
        'sku',
        'name',
        'unit',
        'quantity',
        'unit_price',
        'discount_percent',
        'discount_amount',
        'vat_rate',
        'vat_amount',
        'line_total',
        'note',
      ]);

      const index = db
        .prepare(
          "SELECT name FROM sqlite_master WHERE type = 'index' AND name = 'idx_products_name'",
        )
        .get();
      assert.equal(index?.name, 'idx_products_name');
    } finally {
      db.close();
    }
  });
});
