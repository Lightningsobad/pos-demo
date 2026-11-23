import { copyFileSync, existsSync, mkdirSync, statSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { deflateSync } from 'node:zlib';
import { openDatabase } from './database.js';

const IMAGE_SPECS = [
  { name: 'prod_1.png', rgb: [37, 99, 235] },
  { name: 'prod_2.png', rgb: [16, 185, 129] },
  { name: 'prod_3.png', rgb: [245, 158, 11] },
  { name: 'prod_4.png', rgb: [239, 68, 68] },
];
const VIDEO_FILENAME = 'sample_promo.mp4';
const SAMPLE_VIDEO_SOURCE = resolve(
  dirname(fileURLToPath(import.meta.url)),
  '../../assets',
  VIDEO_FILENAME,
);

const PRODUCT_PREFIXES = [
  'Cà phê sữa đá',
  'Trà đào cam sả',
  'Bánh mì thịt nướng',
  'Nước ép cam tươi',
  'Sữa tươi trân châu',
  'Matcha latte',
  'Sinh tố bơ',
  'Bánh ngọt tiramisu',
  'Mì ý sốt bò bằm',
  'Cơm gà xối mỡ',
];
const PRODUCT_VARIANTS = ['Size M', 'Size L', 'Đặc biệt', 'Ít đường', 'Nguyên bản'];
const UNITS = ['Ly', 'Phần', 'Cái', 'Hộp', 'Chai', 'Gói'];
const VAT_RATES = [0, 8, 10];

const PNG_SIGNATURE = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);

const CRC_TABLE = (() => {
  const table = new Uint32Array(256);
  for (let n = 0; n < 256; n += 1) {
    let c = n;
    for (let k = 0; k < 8; k += 1) {
      c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    }
    table[n] = c >>> 0;
  }
  return table;
})();

function crc32(buf) {
  let c = 0xffffffff;
  for (let i = 0; i < buf.length; i += 1) {
    c = CRC_TABLE[(c ^ buf[i]) & 0xff] ^ (c >>> 8);
  }
  return (c ^ 0xffffffff) >>> 0;
}

function pngChunk(type, data) {
  const typeBuf = Buffer.from(type, 'ascii');
  const lenBuf = Buffer.allocUnsafe(4);
  lenBuf.writeUInt32BE(data.length, 0);

  const crcInput = Buffer.concat([typeBuf, data]);
  const crcBuf = Buffer.allocUnsafe(4);
  crcBuf.writeUInt32BE(crc32(crcInput), 0);

  return Buffer.concat([lenBuf, crcInput, crcBuf]);
}

function createSolidPng(width, height, [r, g, b]) {
  const ihdr = Buffer.allocUnsafe(13);
  ihdr.writeUInt32BE(width, 0);
  ihdr.writeUInt32BE(height, 4);
  ihdr[8] = 8; // bit depth
  ihdr[9] = 2; // RGB color type
  ihdr[10] = 0;
  ihdr[11] = 0;
  ihdr[12] = 0;

  const rowSize = 1 + width * 3;
  const raw = Buffer.allocUnsafe(rowSize * height);
  for (let y = 0; y < height; y += 1) {
    const rowOffset = y * rowSize;
    raw[rowOffset] = 0; // filter None
    for (let x = 0; x < width; x += 1) {
      const px = rowOffset + 1 + x * 3;
      raw[px] = r;
      raw[px + 1] = g;
      raw[px + 2] = b;
    }
  }

  const compressed = deflateSync(raw);
  return Buffer.concat([
    PNG_SIGNATURE,
    pngChunk('IHDR', ihdr),
    pngChunk('IDAT', compressed),
    pngChunk('IEND', Buffer.alloc(0)),
  ]);
}

/**
 * Ensure sample PNG images and MP4 video (< 5MB each) exist in mediaDir.
 * @param {string} mediaDir
 * @returns {{ images: string[], video: string }}
 */
export function ensureSampleMedia(mediaDir) {
  if (typeof mediaDir !== 'string' || mediaDir.trim().length === 0) {
    throw new RangeError('mediaDir must be a non-empty string');
  }
  mkdirSync(mediaDir, { recursive: true });

  const images = IMAGE_SPECS.map((spec) => {
    const filePath = join(mediaDir, spec.name);
    if (!existsSync(filePath)) {
      writeFileSync(filePath, createSolidPng(64, 64, spec.rgb));
    }
    return filePath;
  });

  const video = join(mediaDir, VIDEO_FILENAME);
  const sourceStats = statSync(SAMPLE_VIDEO_SOURCE);
  if (!existsSync(video) || statSync(video).size < sourceStats.size) {
    copyFileSync(SAMPLE_VIDEO_SOURCE, video);
  }

  return { images, video };
}

/**
 * Seed sample products idempotently into SQLite in a single transaction.
 * @param {import('node:sqlite').DatabaseSync} db
 * @param {number} [count=100000]
 * @returns {number}
 */
export function seedProducts(db, count = 100000) {
  if (!Number.isInteger(count) || count < 0) {
    throw new RangeError('count must be a non-negative integer');
  }

  const existing = db.prepare('SELECT COUNT(*) AS cnt FROM products').get();
  if (existing.cnt > 0) {
    return existing.cnt;
  }
  if (count === 0) {
    return 0;
  }

  const insertStmt = db.prepare(`
    INSERT INTO products (
      id, sku, name, unit, price, vat_rate, stock, media_type, media_url, thumbnail_url
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  `);

  db.exec('BEGIN');
  try {
    for (let i = 1; i <= count; i += 1) {
      const sku = `SP${String(i).padStart(6, '0')}`;
      const prefix = PRODUCT_PREFIXES[(i - 1) % PRODUCT_PREFIXES.length];
      const variant = PRODUCT_VARIANTS[(i - 1) % PRODUCT_VARIANTS.length];
      const name = `${prefix} ${variant} #${i}`;
      const unit = UNITS[(i - 1) % UNITS.length];
      const price = 15000 + ((i * 7919) % 2486) * 1000;
      const vatRate = VAT_RATES[i % VAT_RATES.length];
      const isVideo = i % 10 === 0;
      const imageFile = IMAGE_SPECS[(i - 1) % IMAGE_SPECS.length].name;
      const thumbnailUrl = `/media/${imageFile}`;
      const mediaType = isVideo ? 'video' : 'image';
      const mediaUrl = isVideo ? `/media/${VIDEO_FILENAME}` : thumbnailUrl;

      insertStmt.run(i, sku, name, unit, price, vatRate, 10, mediaType, mediaUrl, thumbnailUrl);
    }
    db.exec('COMMIT');
  } catch (err) {
    db.exec('ROLLBACK');
    throw err;
  }

  return count;
}

const isDirectEntry =
  Boolean(process.argv[1]) && pathToFileURL(resolve(process.argv[1])).href === import.meta.url;

if (isDirectEntry) {
  const backendRoot = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
  const dbPath = join(backendRoot, 'data', 'pos.db');
  const mediaDir = join(backendRoot, 'public', 'media');

  const start = performance.now();
  ensureSampleMedia(mediaDir);
  const db = openDatabase(dbPath);
  try {
    const total = seedProducts(db, 100000);
    const elapsedMs = Math.round(performance.now() - start);
    console.log(`Seeded products: ${total} (${elapsedMs}ms) -> ${dbPath}`);
  } finally {
    db.close();
  }
}
