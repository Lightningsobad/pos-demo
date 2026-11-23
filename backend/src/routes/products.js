import { statSync } from 'node:fs';
import { resolve, sep } from 'node:path';

function parsePositiveInt(value) {
  if (typeof value !== 'string' || !/^\d+$/.test(value)) {
    return null;
  }
  const parsed = Number.parseInt(value, 10);
  return Number.isSafeInteger(parsed) && parsed > 0 ? parsed : null;
}

function parsePagination(query = {}) {
  const rawPage = Number.parseInt(query.page, 10);
  const page = Number.isFinite(rawPage) && rawPage >= 1 ? rawPage : 1;

  const rawLimit = Number.parseInt(query.limit, 10);
  const limit = Number.isFinite(rawLimit) ? Math.min(50, Math.max(1, rawLimit)) : 10;

  const q = typeof query.q === 'string' ? query.q.trim() : '';
  return { page, limit, offset: (page - 1) * limit, q };
}

function waitStockDelay(delayMs, request, reply) {
  if (delayMs <= 0) {
    return Promise.resolve(true);
  }
  return new Promise((resolvePromise) => {
    let settled = false;
    const cleanup = () => {
      request.raw.off('close', onClose);
    };

    const timer = setTimeout(() => {
      if (settled) return;
      settled = true;
      cleanup();
      resolvePromise(true);
    }, delayMs);

    const onClose = () => {
      if (settled || reply.raw.writableEnded) return;
      settled = true;
      clearTimeout(timer);
      cleanup();
      resolvePromise(false);
    };

    request.raw.on('close', onClose);
  });
}

function resolveMediaUrl(request, path) {
  if (typeof path !== 'string' || path.length === 0) {
    return '';
  }
  if (/^https?:\/\//i.test(path)) {
    return path;
  }
  const normalizedPath = path.startsWith('/') ? path : `/${path}`;
  const host = request.headers?.host;
  return host ? `${request.protocol}://${host}${normalizedPath}` : normalizedPath;
}

function getMediaSizeBytes(resolvedMediaDir, mediaUrl) {
  if (!resolvedMediaDir || typeof mediaUrl !== 'string') {
    return 0;
  }
  const relPath = mediaUrl.replace(/^\/+media\/+/, '');
  if (!relPath || relPath.startsWith('/')) {
    return 0;
  }
  const filePath = resolve(resolvedMediaDir, relPath);
  const basePrefix = resolvedMediaDir.endsWith(sep) ? resolvedMediaDir : `${resolvedMediaDir}${sep}`;
  if (filePath !== resolvedMediaDir && !filePath.startsWith(basePrefix)) {
    return 0;
  }
  try {
    return statSync(filePath).size;
  } catch {
    return 0;
  }
}

/**
 * Register the 3-stream product routes: list/search, delayed stock, and media metadata.
 * @param {import('fastify').FastifyInstance} fastify
 * @param {{ db: import('node:sqlite').DatabaseSync, stockDelayMs?: number, mediaDir?: string }} options
 */
export async function registerProductRoutes(fastify, options = {}) {
  const db = options.db ?? fastify.db;
  const stockDelayMs = options.stockDelayMs ?? 1000;
  const resolvedMediaDir = options.mediaDir ? resolve(options.mediaDir) : null;

  const listAllStmt = db.prepare(`
    SELECT id, sku, name, unit, price, vat_rate AS vatRate
    FROM products
    ORDER BY id ASC
    LIMIT ? OFFSET ?
  `);
  const countAllStmt = db.prepare('SELECT COUNT(*) AS total FROM products');

  const searchStmt = db.prepare(`
    SELECT id, sku, name, unit, price, vat_rate AS vatRate
    FROM products
    WHERE sku LIKE ? OR name LIKE ?
    ORDER BY id ASC
    LIMIT ? OFFSET ?
  `);
  const countSearchStmt = db.prepare(`
    SELECT COUNT(*) AS total
    FROM products
    WHERE sku LIKE ? OR name LIKE ?
  `);

  const selectStockStmt = db.prepare('SELECT id, stock FROM products WHERE id = ?');
  const selectMediaStmt = db.prepare(
    'SELECT id, media_type, media_url, thumbnail_url FROM products WHERE id = ?',
  );

  fastify.get('/api/products', async (request) => {
    const { page, limit, offset, q } = parsePagination(request.query);

    let items;
    let total;
    if (q.length > 0) {
      const pattern = `%${q}%`;
      items = searchStmt.all(pattern, pattern, limit, offset);
      ({ total } = countSearchStmt.get(pattern, pattern));
    } else {
      items = listAllStmt.all(limit, offset);
      ({ total } = countAllStmt.get());
    }

    return {
      items,
      page,
      limit,
      total,
      hasMore: offset + items.length < total,
    };
  });

  fastify.get('/api/products/:id/stock', async (request, reply) => {
    const id = parsePositiveInt(request.params?.id);
    if (id === null) {
      return reply.code(400).send({ error: 'Invalid product id' });
    }

    const row = selectStockStmt.get(id);
    if (!row) {
      return reply.code(404).send({ error: 'Product not found' });
    }

    const completed = await waitStockDelay(stockDelayMs, request, reply);
    if (!completed) {
      reply.hijack();
      return;
    }

    return {
      productId: row.id,
      stock: row.stock,
    };
  });

  fastify.get('/api/products/:id/media', async (request, reply) => {
    const id = parsePositiveInt(request.params?.id);
    if (id === null) {
      return reply.code(400).send({ error: 'Invalid product id' });
    }

    const row = selectMediaStmt.get(id);
    if (!row) {
      return reply.code(404).send({ error: 'Product not found' });
    }

    return {
      productId: row.id,
      mediaType: row.media_type,
      mediaUrl: resolveMediaUrl(request, row.media_url),
      thumbnailUrl: resolveMediaUrl(request, row.thumbnail_url),
      sizeBytes: getMediaSizeBytes(resolvedMediaDir, row.media_url),
    };
  });
}
