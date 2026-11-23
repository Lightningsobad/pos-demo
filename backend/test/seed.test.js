import { describe, test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, mkdtempSync, readFileSync, rmSync, statSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { openDatabase } from '../src/db/database.js';
import { ensureSampleMedia, seedProducts } from '../src/db/seed.js';

const MAX_MEDIA_BYTES = 5 * 1024 * 1024;
const PNG_SIGNATURE = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);

describe('Media & Product Seeder', () => {
  test('ensureSampleMedia tao 4 file PNG hop le va 1 file MP4 hop le deu < 5MB', () => {
    const tempDir = mkdtempSync(join(tmpdir(), 'pos-media-'));
    const mediaDir = join(tempDir, 'nested', 'media');

    try {
      const result = ensureSampleMedia(mediaDir);

      assert.equal(Array.isArray(result.images), true);
      assert.equal(result.images.length, 4);
      assert.equal(typeof result.video, 'string');

      for (const imgPath of result.images) {
        assert.equal(existsSync(imgPath), true, `Missing image file: ${imgPath}`);
        const stats = statSync(imgPath);
        assert.ok(stats.size > 0 && stats.size < MAX_MEDIA_BYTES, `Invalid image size: ${stats.size}`);

        const buf = readFileSync(imgPath);
        assert.equal(buf.subarray(0, 8).equals(PNG_SIGNATURE), true, 'Invalid PNG signature');
        assert.ok(buf.includes(Buffer.from('IHDR')), 'Missing PNG IHDR chunk');
        assert.ok(buf.includes(Buffer.from('IDAT')), 'Missing PNG IDAT chunk');
        assert.ok(buf.includes(Buffer.from('IEND')), 'Missing PNG IEND chunk');
      }

      assert.equal(existsSync(result.video), true, `Missing video file: ${result.video}`);
      const videoStats = statSync(result.video);
      assert.ok(
        videoStats.size > 0 && videoStats.size < MAX_MEDIA_BYTES,
        `Invalid video size: ${videoStats.size}`,
      );

      const videoBuf = readFileSync(result.video);
      assert.equal(videoBuf.subarray(4, 8).toString('ascii'), 'ftyp', 'Missing MP4 ftyp box');
      assert.ok(videoBuf.includes(Buffer.from('moov')), 'Missing MP4 moov box');
      assert.ok(videoBuf.includes(Buffer.from('mdat')), 'Missing MP4 mdat box');

      // Calling again should be idempotent and return the same paths
      const secondResult = ensureSampleMedia(mediaDir);
      assert.deepEqual(secondResult, result);
    } finally {
      rmSync(tempDir, { recursive: true, force: true });
    }
  });

  test('openDatabase(tempFilePath) tao thu muc cha va bat journal_mode = wal tren dia', () => {
    const tempDir = mkdtempSync(join(tmpdir(), 'pos-db-'));
    const dbPath = join(tempDir, 'nested', 'dir', 'pos.db');
    let db;

    try {
      db = openDatabase(dbPath);
      assert.equal(existsSync(dbPath), true);

      const mode = db.prepare('PRAGMA journal_mode').get();
      assert.equal(String(mode.journal_mode).toLowerCase(), 'wal');
    } finally {
      db?.close();
      rmSync(tempDir, { recursive: true, force: true });
    }
  });

  test('seedProducts(db, 1000) idempotent, du 1000 dong, stock=10, media_type & thumbnail_url hop le', () => {
    const db = openDatabase(':memory:');
    try {
      const inserted = seedProducts(db, 1000);
      assert.equal(inserted, 1000);

      // Call a second time -> idempotent, still 1000
      const secondCount = seedProducts(db, 1000);
      assert.equal(secondCount, 1000);

      const totalRow = db.prepare('SELECT COUNT(*) AS cnt FROM products').get();
      assert.equal(totalRow.cnt, 1000);

      const rows = db
        .prepare('SELECT id, sku, name, unit, price, vat_rate, stock, media_type, media_url, thumbnail_url FROM products')
        .all();
      assert.equal(rows.length, 1000);

      let imageCount = 0;
      let videoCount = 0;

      for (const row of rows) {
        assert.equal(row.stock, 10);
        assert.ok(row.price >= 15000 && row.price <= 2500000, `Unexpected price: ${row.price}`);
        assert.ok([0, 8, 10].includes(row.vat_rate), `Unexpected vat_rate: ${row.vat_rate}`);
        assert.ok(row.media_type === 'image' || row.media_type === 'video', `Invalid media_type: ${row.media_type}`);
        assert.ok(typeof row.thumbnail_url === 'string' && row.thumbnail_url.startsWith('/media/'), `Invalid thumbnail_url: ${row.thumbnail_url}`);
        assert.ok(typeof row.media_url === 'string' && row.media_url.startsWith('/media/'), `Invalid media_url: ${row.media_url}`);

        if (row.media_type === 'image') {
          imageCount += 1;
          assert.ok(row.media_url.endsWith('.png'));
        } else {
          videoCount += 1;
          assert.ok(row.media_url.endsWith('.mp4'));
          assert.ok(row.thumbnail_url.endsWith('.png'));
        }
      }

      assert.equal(imageCount, 900);
      assert.equal(videoCount, 100);
    } finally {
      db.close();
    }
  });
});
