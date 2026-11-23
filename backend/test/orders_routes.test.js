import { after, before, describe, test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { buildApp } from '../src/app.js';

describe('Orders API Routes', () => {
  let tempDir;
  let app;

  before(() => {
    tempDir = mkdtempSync(join(tmpdir(), 'pos-orders-'));
    app = buildApp({
      dbPath: join(tempDir, 'pos.db'),
      mediaDir: join(tempDir, 'media'),
      stockDelayMs: 0,
      autoSeedCount: 10,
    });
  });

  after(async () => {
    if (app) {
      await app.close();
    }
    if (tempDir) {
      rmSync(tempDir, { recursive: true, force: true });
    }
  });

  test('POST /api/orders bo qua unitPrice gia mao, tinh dung gia DB, cap HD-YYYYMMDD-XXXX va tru ton kho', async () => {
    const prod1 = app.db.prepare('SELECT id, sku, name, unit, price, vat_rate, stock FROM products WHERE id = 1').get();
    const prod2 = app.db.prepare('SELECT id, sku, name, unit, price, vat_rate, stock FROM products WHERE id = 2').get();

    // Expected math from DB prices (ignoring client unitPrice: 1)
    const gross1 = prod1.price * 2;
    const disc1 = Math.round(gross1 * 0.1);
    const vat1 = Math.round((gross1 - disc1) * (prod1.vat_rate / 100));
    const line1 = gross1 - disc1 + vat1;

    const gross2 = prod2.price * 1;
    const disc2 = 0;
    const vat2 = Math.round(gross2 * (5 / 100)); // explicit vatRate: 5
    const line2 = gross2 + vat2;

    const expectedSubtotal = line1 + line2;
    const expectedOrderDiscount = Math.round(expectedSubtotal * 0.05);
    const expectedTotal = expectedSubtotal - expectedOrderDiscount;

    const res = await app.inject({
      method: 'POST',
      url: '/api/orders',
      payload: {
        staffName: 'Nguyen Van A',
        paymentMethod: 'cash',
        discountPercent: 5,
        store: {
          name: 'Cua hang Demo',
          phone: '0901234567',
          address: '123 Le Loi, Q1',
          logoUrl: 'http://localhost:3000/media/prod_1.png',
        },
        items: [
          {
            productId: prod1.id,
            unitPrice: 1, // spoofed!
            quantity: 2,
            discountPercent: 10,
            // vatRate omitted -> fallback to DB vat_rate
            note: 'It da',
          },
          {
            productId: prod2.id,
            unitPrice: 99, // spoofed!
            quantity: 1,
            vatRate: 5,
          },
        ],
      },
    });

    assert.equal(res.statusCode, 201);
    const order = res.json();
    assert.equal(order.id, 1);
    assert.match(order.orderCode, /^HD-\d{8}-0001$/);
    assert.equal(order.staffName, 'Nguyen Van A');
    assert.equal(order.paymentMethod, 'cash');
    assert.equal(order.subtotal, expectedSubtotal);
    assert.equal(order.discountPercent, 5);
    assert.equal(order.discountAmount, expectedOrderDiscount);
    assert.equal(order.totalPayable, expectedTotal);
    assert.deepEqual(order.store, {
      name: 'Cua hang Demo',
      phone: '0901234567',
      address: '123 Le Loi, Q1',
      logoUrl: 'http://localhost:3000/media/prod_1.png',
    });
    assert.ok(Date.parse(order.createdAt) > 0);
    assert.equal(order.items.length, 2);

    assert.deepEqual(order.items[0], {
      productId: prod1.id,
      sku: prod1.sku,
      name: prod1.name,
      unit: prod1.unit,
      quantity: 2,
      unitPrice: prod1.price,
      discountPercent: 10,
      discountAmount: disc1,
      vatRate: prod1.vat_rate,
      vatAmount: vat1,
      lineTotal: line1,
      note: 'It da',
    });

    assert.deepEqual(order.items[1], {
      productId: prod2.id,
      sku: prod2.sku,
      name: prod2.name,
      unit: prod2.unit,
      quantity: 1,
      unitPrice: prod2.price,
      discountPercent: 0,
      discountAmount: 0,
      vatRate: 5,
      vatAmount: vat2,
      lineTotal: line2,
      note: '',
    });

    // Verify stock decremented via GET /api/products/:id/stock
    const stockRes1 = await app.inject({ method: 'GET', url: `/api/products/${prod1.id}/stock` });
    assert.equal(stockRes1.statusCode, 200);
    assert.equal(stockRes1.json().stock, prod1.stock - 2);

    const stockRes2 = await app.inject({ method: 'GET', url: `/api/products/${prod2.id}/stock` });
    assert.equal(stockRes2.statusCode, 200);
    assert.equal(stockRes2.json().stock, prod2.stock - 1);
  });

  test('POST /api/orders tra 409 khi dat vuot ton kho, gom don canh tranh va dong trung productId', async () => {
    // Product 3 has stock = 10. Order 1 takes 7, Order 2 asks for 5 -> 409, stock stays 3.
    const basePayload = (qty) => ({
      staffName: 'Tran Thi B',
      paymentMethod: 'transfer',
      store: { name: 'Cua hang Demo', phone: '0901234567', address: '123 Le Loi' },
      items: [{ productId: 3, quantity: qty }],
    });

    const [res1, res2] = await Promise.all([
      app.inject({ method: 'POST', url: '/api/orders', payload: basePayload(7) }),
      app.inject({ method: 'POST', url: '/api/orders', payload: basePayload(5) }),
    ]);

    const statuses = [res1.statusCode, res2.statusCode].sort();
    assert.deepEqual(statuses, [201, 409]);

    const stockRes = await app.inject({ method: 'GET', url: '/api/products/3/stock' });
    assert.equal(stockRes.statusCode, 200);
    const remainingStock = stockRes.json().stock;
    assert.ok(remainingStock === 3 || remainingStock === 5);

    // Duplicate lines for product 3 totaling > remainingStock must be rejected with 409
    const dupRes = await app.inject({
      method: 'POST',
      url: '/api/orders',
      payload: {
        staffName: 'Tran Thi B',
        paymentMethod: 'cash',
        store: { name: 'Cua hang Demo', phone: '0901234567', address: '123 Le Loi' },
        items: [
          { productId: 3, quantity: remainingStock },
          { productId: 3, quantity: 1 },
        ],
      },
    });
    assert.equal(dupRes.statusCode, 409);

    const stockAfterDup = await app.inject({ method: 'GET', url: '/api/products/3/stock' });
    assert.equal(stockAfterDup.json().stock, remainingStock);
  });

  test('POST /api/orders tra 400 voi input khong hop le va 404 (khong tru ton) khi thieu san pham', async () => {
    const invalidPayloads = [
      {},
      { staffName: 'A', paymentMethod: 'cash', store: { name: 'S' }, items: [] },
      { staffName: '  ', paymentMethod: 'cash', store: { name: 'S' }, items: [{ productId: 4, quantity: 1 }] },
      { staffName: 'A', paymentMethod: '', store: { name: 'S' }, items: [{ productId: 4, quantity: 1 }] },
      { staffName: 'A', paymentMethod: 'cash', store: { name: '' }, items: [{ productId: 4, quantity: 1 }] },
      { staffName: 'A', paymentMethod: 'cash', store: { name: 'S' }, items: [{ productId: 'bad', quantity: 1 }] },
      { staffName: 'A', paymentMethod: 'cash', store: { name: 'S' }, items: [{ productId: 4, quantity: 0 }] },
      { staffName: 'A', paymentMethod: 'cash', store: { name: 'S' }, items: [{ productId: 4, quantity: 1, discountPercent: 150 }] },
    ];

    for (const payload of invalidPayloads) {
      const res = await app.inject({ method: 'POST', url: '/api/orders', payload });
      assert.equal(res.statusCode, 400);
    }

    // Item 1 valid (id=4), Item 2 missing (id=9999) -> 404 and stock of id=4 untouched (10)
    const missingRes = await app.inject({
      method: 'POST',
      url: '/api/orders',
      payload: {
        staffName: 'A',
        paymentMethod: 'cash',
        store: { name: 'S', phone: '1', address: '2' },
        items: [
          { productId: 4, quantity: 3 },
          { productId: 9999, quantity: 1 },
        ],
      },
    });
    assert.equal(missingRes.statusCode, 404);

    const stockRes = await app.inject({ method: 'GET', url: '/api/products/4/stock' });
    assert.equal(stockRes.json().stock, 10);
  });

  test('GET /api/orders tra ve danh sach moi nhat truoc kem items chi tiet va clamp limit 1..100', async () => {
    const res = await app.inject({
      method: 'GET',
      url: '/api/orders?limit=20',
    });
    assert.equal(res.statusCode, 200);
    const body = res.json();
    assert.equal(Array.isArray(body.items), true);
    assert.ok(body.items.length >= 2);
    assert.ok(body.items[0].id > body.items[1].id);
    assert.equal(body.items[body.items.length - 1].id, 1);
    assert.equal(body.items[body.items.length - 1].items.length, 2);
    assert.equal(typeof body.items[0].orderCode, 'string');
    assert.equal(typeof body.items[0].store.name, 'string');

    const limitOneRes = await app.inject({
      method: 'GET',
      url: '/api/orders?limit=0',
    });
    assert.equal(limitOneRes.statusCode, 200);
    assert.equal(limitOneRes.json().items.length, 1);
  });
});
