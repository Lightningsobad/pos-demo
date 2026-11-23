import { calculateOrderPricing } from '../services/pricing.js';

function isPlainObject(value) {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

function formatDateYmd(date) {
  const yyyy = String(date.getFullYear());
  const mm = String(date.getMonth() + 1).padStart(2, '0');
  const dd = String(date.getDate()).padStart(2, '0');
  return `${yyyy}${mm}${dd}`;
}

function parseLimit(rawLimit) {
  const parsed = Number.parseInt(rawLimit, 10);
  return Number.isFinite(parsed) ? Math.min(100, Math.max(1, parsed)) : 20;
}

function validateOrderPayload(body) {
  if (!isPlainObject(body)) {
    return { error: 'Request body must be a JSON object' };
  }

  const staffName = typeof body.staffName === 'string' ? body.staffName.trim() : '';
  if (!staffName) {
    return { error: 'staffName is required' };
  }

  const paymentMethod = typeof body.paymentMethod === 'string' ? body.paymentMethod.trim() : '';
  if (!paymentMethod) {
    return { error: 'paymentMethod is required' };
  }

  if (!isPlainObject(body.store)) {
    return { error: 'store is required' };
  }
  const storeName = typeof body.store.name === 'string' ? body.store.name.trim() : '';
  if (!storeName) {
    return { error: 'store.name is required' };
  }
  const store = {
    name: storeName,
    phone: typeof body.store.phone === 'string' ? body.store.phone.trim() : '',
    address: typeof body.store.address === 'string' ? body.store.address.trim() : '',
    logoUrl:
      typeof body.store.logoUrl === 'string' && body.store.logoUrl.trim().length > 0
        ? body.store.logoUrl.trim()
        : null,
  };

  if (!Array.isArray(body.items) || body.items.length === 0) {
    return { error: 'items must be a non-empty array' };
  }

  for (let i = 0; i < body.items.length; i += 1) {
    const item = body.items[i];
    if (!isPlainObject(item) || !Number.isInteger(item.productId) || item.productId <= 0) {
      return { error: `items[${i}].productId must be a positive integer` };
    }
  }

  return {
    value: {
      staffName,
      paymentMethod,
      discountPercent: body.discountPercent ?? 0,
      store,
      items: body.items,
    },
  };
}

function formatOrderRow(orderRow, itemRows) {
  return {
    id: orderRow.id,
    orderCode: orderRow.order_code,
    staffName: orderRow.staff_name,
    paymentMethod: orderRow.payment_method,
    subtotal: orderRow.subtotal,
    discountPercent: orderRow.discount_percent,
    discountAmount: orderRow.discount_amount,
    totalPayable: orderRow.total_payable,
    store: {
      name: orderRow.store_name,
      phone: orderRow.store_phone,
      address: orderRow.store_address,
      logoUrl: orderRow.store_logo_url ?? null,
    },
    createdAt: orderRow.created_at,
    items: itemRows.map((row) => ({
      productId: row.product_id,
      sku: row.sku,
      name: row.name,
      unit: row.unit,
      quantity: row.quantity,
      unitPrice: row.unit_price,
      discountPercent: row.discount_percent,
      discountAmount: row.discount_amount,
      vatRate: row.vat_rate,
      vatAmount: row.vat_amount,
      lineTotal: row.line_total,
      note: row.note ?? '',
    })),
  };
}

class HttpError extends Error {
  constructor(statusCode, message) {
    super(message);
    this.statusCode = statusCode;
  }
}

/**
 * Register order creation and history routes.
 * @param {import('fastify').FastifyInstance} fastify
 * @param {{ db?: import('node:sqlite').DatabaseSync }} options
 */
export async function registerOrderRoutes(fastify, options = {}) {
  const db = options.db ?? fastify.db;

  const selectProductStmt = db.prepare(
    'SELECT id, sku, name, unit, price, vat_rate, stock FROM products WHERE id = ?',
  );
  const nextOrderIdStmt = db.prepare('SELECT COALESCE(MAX(id), 0) + 1 AS nextId FROM orders');
  const insertOrderStmt = db.prepare(`
    INSERT INTO orders (
      order_code, staff_name, payment_method,
      subtotal, discount_percent, discount_amount, total_payable,
      store_name, store_phone, store_address, store_logo_url, created_at
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  `);
  const insertOrderItemStmt = db.prepare(`
    INSERT INTO order_items (
      order_id, product_id, sku, name, unit, quantity,
      unit_price, discount_percent, discount_amount,
      vat_rate, vat_amount, line_total, note
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  `);
  const decrementStockStmt = db.prepare('UPDATE products SET stock = stock - ? WHERE id = ?');
  const selectOrdersStmt = db.prepare('SELECT * FROM orders ORDER BY id DESC LIMIT ?');
  const selectOrderItemsStmt = db.prepare(
    'SELECT * FROM order_items WHERE order_id = ? ORDER BY id ASC',
  );

  fastify.post('/api/orders', async (request, reply) => {
    const validated = validateOrderPayload(request.body);
    if (validated.error) {
      return reply.code(400).send({ error: validated.error });
    }
    const { staffName, paymentMethod, discountPercent, store, items } = validated.value;

    db.exec('BEGIN IMMEDIATE');
    try {
      const productMap = new Map();
      for (const item of items) {
        if (!productMap.has(item.productId)) {
          const product = selectProductStmt.get(item.productId);
          if (!product) {
            throw new HttpError(404, `Product ${item.productId} not found`);
          }
          productMap.set(item.productId, product);
        }
      }

      // Always ignore client unitPrice and use authoritative DB price
      const pricingInputs = items.map((item) => {
        const product = productMap.get(item.productId);
        return {
          productId: product.id,
          sku: product.sku,
          name: product.name,
          unit: product.unit,
          unitPrice: product.price,
          quantity: item.quantity,
          discountPercent: item.discountPercent ?? 0,
          vatRate: item.vatRate ?? product.vat_rate,
          note: item.note == null ? '' : String(item.note),
        };
      });

      const pricing = calculateOrderPricing(pricingInputs, discountPercent);

      // Aggregate requested quantity per productId so duplicate lines cannot bypass stock check
      const qtyByProduct = new Map();
      for (const line of pricing.items) {
        qtyByProduct.set(line.productId, (qtyByProduct.get(line.productId) ?? 0) + line.quantity);
      }

      for (const [productId, totalQty] of qtyByProduct) {
        const product = productMap.get(productId);
        if (product.stock < totalQty) {
          throw new HttpError(409, `Insufficient stock for product ${product.sku}`);
        }
      }

      const { nextId } = nextOrderIdStmt.get();
      const now = new Date();
      const createdAt = now.toISOString();
      const orderCode = `HD-${formatDateYmd(now)}-${String(nextId).padStart(4, '0')}`;

      const insertRes = insertOrderStmt.run(
        orderCode,
        staffName,
        paymentMethod,
        pricing.subtotal,
        pricing.discountPercent,
        pricing.discountAmount,
        pricing.totalPayable,
        store.name,
        store.phone,
        store.address,
        store.logoUrl,
        createdAt,
      );
      const orderId = Number(insertRes.lastInsertRowid);

      for (const line of pricing.items) {
        insertOrderItemStmt.run(
          orderId,
          line.productId,
          line.sku,
          line.name,
          line.unit,
          line.quantity,
          line.unitPrice,
          line.discountPercent,
          line.discountAmount,
          line.vatRate,
          line.vatAmount,
          line.lineTotal,
          line.note,
        );
      }

      for (const [productId, totalQty] of qtyByProduct) {
        decrementStockStmt.run(totalQty, productId);
      }

      db.exec('COMMIT');

      return reply.code(201).send({
        id: orderId,
        orderCode,
        staffName,
        paymentMethod,
        subtotal: pricing.subtotal,
        discountPercent: pricing.discountPercent,
        discountAmount: pricing.discountAmount,
        totalPayable: pricing.totalPayable,
        store,
        createdAt,
        items: pricing.items,
      });
    } catch (err) {
      try {
        db.exec('ROLLBACK');
      } catch {
        // Ignore rollback failure if transaction was already aborted
      }

      if (err instanceof HttpError) {
        return reply.code(err.statusCode).send({ error: err.message });
      }
      if (err instanceof RangeError) {
        return reply.code(400).send({ error: err.message });
      }
      throw err;
    }
  });

  fastify.get('/api/orders', async (request) => {
    const limit = parseLimit(request.query?.limit);
    const orders = selectOrdersStmt.all(limit);
    return {
      items: orders.map((orderRow) => formatOrderRow(orderRow, selectOrderItemsStmt.all(orderRow.id))),
    };
  });
}
