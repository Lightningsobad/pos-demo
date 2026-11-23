import { after, before, describe, test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { buildApp } from '../src/app.js';

describe('Products 3-Stream API Routes', () => {
  let tempDir;
  let app;

  before(() => {
    tempDir = mkdtempSync(join(tmpdir(), 'pos-routes-'));
    app = buildApp({
      dbPath: join(tempDir, 'pos.db'),
      mediaDir: join(tempDir, 'media'),
      stockDelayMs: 50,
      autoSeedCount: 25,
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

  test('GET /api/products tra ve trang 1 (10 items, khong co stock/mediaUrl, hasMore=true) va trang 3 (5 items, hasMore=false)', async () => {
    const res1 = await app.inject({
      method: 'GET',
      url: '/api/products?page=1&limit=10',
    });

    assert.equal(res1.statusCode, 200);
    const body1 = res1.json();
    assert.equal(body1.page, 1);
    assert.equal(body1.limit, 10);
    assert.equal(body1.total, 25);
    assert.equal(body1.hasMore, true);
    assert.equal(Array.isArray(body1.items), true);
    assert.equal(body1.items.length, 10);

    const first = body1.items[0];
    assert.equal(first.id, 1);
    assert.equal(first.sku, 'SP000001');
    assert.equal(typeof first.name, 'string');
    assert.equal(typeof first.unit, 'string');
    assert.equal(typeof first.price, 'number');
    assert.equal(typeof first.vatRate, 'number');
    assert.equal('stock' in first, false);
    assert.equal('mediaUrl' in first, false);
    assert.equal('thumbnailUrl' in first, false);
    assert.equal('vat_rate' in first, false);

    const res3 = await app.inject({
      method: 'GET',
      url: '/api/products?page=3&limit=10',
    });

    assert.equal(res3.statusCode, 200);
    const body3 = res3.json();
    assert.equal(body3.page, 3);
    assert.equal(body3.limit, 10);
    assert.equal(body3.total, 25);
    assert.equal(body3.hasMore, false);
    assert.equal(body3.items.length, 5);
  });

  test('GET /api/products ho tro gia tri mac dinh, clamp limit 1..50 va tim kiem q theo sku/name', async () => {
    const clampedRes = await app.inject({
      method: 'GET',
      url: '/api/products?page=0&limit=100',
    });
    assert.equal(clampedRes.statusCode, 200);
    const clampedBody = clampedRes.json();
    assert.equal(clampedBody.page, 1);
    assert.equal(clampedBody.limit, 50);
    assert.equal(clampedBody.items.length, 25);
    assert.equal(clampedBody.hasMore, false);

    const minLimitRes = await app.inject({
      method: 'GET',
      url: '/api/products?limit=0',
    });
    assert.equal(minLimitRes.statusCode, 200);
    assert.equal(minLimitRes.json().limit, 1);
    assert.equal(minLimitRes.json().items.length, 1);

    const skuRes = await app.inject({
      method: 'GET',
      url: '/api/products?q=SP000012',
    });
    assert.equal(skuRes.statusCode, 200);
    const skuBody = skuRes.json();
    assert.equal(skuBody.total, 1);
    assert.equal(skuBody.items[0].id, 12);
    assert.equal(skuBody.items[0].sku, 'SP000012');

    const nameRes = await app.inject({
      method: 'GET',
      url: `/api/products?q=${encodeURIComponent('#25')}`,
    });
    assert.equal(nameRes.statusCode, 200);
    const nameBody = nameRes.json();
    assert.equal(nameBody.total, 1);
    assert.equal(nameBody.items[0].id, 25);
  });

  test('GET /api/products/:id/stock tra ve { productId, stock } sau delay va validate 400/404', async () => {
    const start = performance.now();
    const res = await app.inject({
      method: 'GET',
      url: '/api/products/1/stock',
    });
    const elapsed = performance.now() - start;

    assert.equal(res.statusCode, 200);
    assert.deepEqual(res.json(), { productId: 1, stock: 10 });
    assert.ok(elapsed >= 35, `Expected delay >= 35ms, got ${elapsed}ms`);

    const badRes = await app.inject({
      method: 'GET',
      url: '/api/products/abc/stock',
    });
    assert.equal(badRes.statusCode, 400);

    const zeroRes = await app.inject({
      method: 'GET',
      url: '/api/products/0/stock',
    });
    assert.equal(zeroRes.statusCode, 400);

    const missingRes = await app.inject({
      method: 'GET',
      url: '/api/products/9999/stock',
    });
    assert.equal(missingRes.statusCode, 404);
  });

  test('GET /api/products/:id/stock don dep timer khi client huy request som', async () => {
    const slowDir = mkdtempSync(join(tmpdir(), 'pos-abort-'));
    const slowApp = buildApp({
      dbPath: join(slowDir, 'pos.db'),
      mediaDir: join(slowDir, 'media'),
      stockDelayMs: 500,
      autoSeedCount: 5,
    });

    try {
      await slowApp.listen({ port: 0, host: '127.0.0.1' });
      const { port } = slowApp.server.address();
      const ac = new AbortController();
      const abortTimer = setTimeout(() => ac.abort(), 30);

      await assert.rejects(
        () => fetch(`http://127.0.0.1:${port}/api/products/1/stock`, { signal: ac.signal }),
        (err) => err.name === 'AbortError',
      );
      clearTimeout(abortTimer);

      // Normal request still works cleanly
      const okResp = await fetch(`http://127.0.0.1:${port}/api/products/2/stock`);
      assert.equal(okResp.status, 200);
      assert.deepEqual(await okResp.json(), { productId: 2, stock: 10 });
    } finally {
      await slowApp.close();
      rmSync(slowDir, { recursive: true, force: true });
    }
  });

  test('GET /api/products/:id/media tra ve full URL, sizeBytes < 5MB va static /media/... tra ve 200', async () => {
    const imgRes = await app.inject({
      method: 'GET',
      url: '/api/products/1/media',
      headers: { host: '10.0.2.2:3000' },
    });

    assert.equal(imgRes.statusCode, 200);
    const imgBody = imgRes.json();
    assert.equal(imgBody.productId, 1);
    assert.equal(imgBody.mediaType, 'image');
    assert.equal(imgBody.mediaUrl, 'http://10.0.2.2:3000/media/prod_1.png');
    assert.equal(imgBody.thumbnailUrl, 'http://10.0.2.2:3000/media/prod_1.png');
    assert.ok(imgBody.sizeBytes > 0 && imgBody.sizeBytes < 5 * 1024 * 1024);

    const staticImg = await app.inject({
      method: 'GET',
      url: '/media/prod_1.png',
    });
    assert.equal(staticImg.statusCode, 200);
    assert.equal(staticImg.rawPayload.length, imgBody.sizeBytes);

    const videoRes = await app.inject({
      method: 'GET',
      url: '/api/products/10/media',
      headers: { host: '192.168.1.10:3000' },
    });
    assert.equal(videoRes.statusCode, 200);
    const videoBody = videoRes.json();
    assert.equal(videoBody.productId, 10);
    assert.equal(videoBody.mediaType, 'video');
    assert.equal(videoBody.mediaUrl, 'http://192.168.1.10:3000/media/sample_promo.mp4');
    assert.match(videoBody.thumbnailUrl, /^http:\/\/192\.168\.1\.10:3000\/media\/prod_\d+\.png$/);
    assert.ok(videoBody.sizeBytes > 0 && videoBody.sizeBytes < 5 * 1024 * 1024);

    const staticVideo = await app.inject({
      method: 'GET',
      url: '/media/sample_promo.mp4',
    });
    assert.equal(staticVideo.statusCode, 200);
    assert.equal(staticVideo.rawPayload.length, videoBody.sizeBytes);

    const badRes = await app.inject({ method: 'GET', url: '/api/products/-5/media' });
    assert.equal(badRes.statusCode, 400);

    const missingRes = await app.inject({ method: 'GET', url: '/api/products/9999/media' });
    assert.equal(missingRes.statusCode, 404);
  });

  test('CORS duoc bat tren response', async () => {
    const res = await app.inject({
      method: 'GET',
      url: '/api/products?page=1&limit=1',
      headers: { origin: 'http://localhost:8080' },
    });

    assert.equal(res.statusCode, 200);
    assert.equal(res.headers['access-control-allow-origin'], 'http://localhost:8080');
  });
});
