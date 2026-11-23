import { existsSync, mkdirSync, writeFileSync } from 'node:fs';
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

function mp4Box(type, ...parts) {
  const payload = parts.length === 1 ? parts[0] : Buffer.concat(parts);
  const header = Buffer.allocUnsafe(8);
  header.writeUInt32BE(8 + payload.length, 0);
  header.write(type, 4, 4, 'ascii');
  return Buffer.concat([header, payload]);
}

function mp4FullBox(type, version, flags, ...parts) {
  const vf = Buffer.allocUnsafe(4);
  vf.writeUInt32BE(((version & 0xff) << 24) | (flags & 0xffffff), 0);
  return mp4Box(type, vf, ...parts);
}

function createIdentityMatrix() {
  const m = Buffer.alloc(36);
  m.writeUInt32BE(0x00010000, 0);
  m.writeUInt32BE(0x00010000, 16);
  m.writeUInt32BE(0x40000000, 32);
  return m;
}

function createMinimalMp4() {
  const ftyp = mp4Box(
    'ftyp',
    Buffer.from('isom', 'ascii'),
    Buffer.from([0x00, 0x00, 0x02, 0x00]),
    Buffer.from('isomiso2avc1mp41', 'ascii'),
  );

  // Minimal 1-sample H.264 payload (~2KB) inside mdat
  const mdatPayload = Buffer.alloc(2048, 0);
  // AVCC length-prefixed IDR slice placeholder header
  mdatPayload.writeUInt32BE(mdatPayload.length - 4, 0);
  mdatPayload[4] = 0x65;

  const buildMoov = (chunkOffset) => {
    const mvhdBody = Buffer.alloc(96);
    mvhdBody.writeUInt32BE(1000, 8); // timescale
    mvhdBody.writeUInt32BE(1000, 12); // duration
    mvhdBody.writeUInt32BE(0x00010000, 16); // rate 1.0
    mvhdBody.writeUInt16BE(0x0100, 20); // volume 1.0
    createIdentityMatrix().copy(mvhdBody, 32);
    mvhdBody.writeUInt32BE(2, 92); // next_track_ID
    const mvhd = mp4FullBox('mvhd', 0, 0, mvhdBody);

    const tkhdBody = Buffer.alloc(80);
    tkhdBody.writeUInt32BE(1, 8); // track_ID
    tkhdBody.writeUInt32BE(1000, 16); // duration
    createIdentityMatrix().copy(tkhdBody, 36);
    tkhdBody.writeUInt32BE(16 << 16, 72); // width
    tkhdBody.writeUInt32BE(16 << 16, 76); // height
    const tkhd = mp4FullBox('tkhd', 0, 3, tkhdBody);

    const mdhdBody = Buffer.alloc(20);
    mdhdBody.writeUInt32BE(1000, 8); // timescale
    mdhdBody.writeUInt32BE(1000, 12); // duration
    mdhdBody.writeUInt16BE(0x55c4, 16); // 'und'
    const mdhd = mp4FullBox('mdhd', 0, 0, mdhdBody);

    const hdlrBody = Buffer.concat([
      Buffer.alloc(4),
      Buffer.from('vide', 'ascii'),
      Buffer.alloc(12),
      Buffer.from('VideoHandler\0', 'ascii'),
    ]);
    const hdlr = mp4FullBox('hdlr', 0, 0, hdlrBody);

    const vmhd = mp4FullBox('vmhd', 0, 1, Buffer.alloc(8));
    const urlBox = mp4FullBox('url ', 0, 1);
    const drefCount = Buffer.allocUnsafe(4);
    drefCount.writeUInt32BE(1, 0);
    const dinf = mp4Box('dinf', mp4FullBox('dref', 0, 0, drefCount, urlBox));

    // Minimal avcC (baseline profile, level 1.0, 16x16)
    const sps = Buffer.from([0x67, 0x42, 0xc0, 0x0a, 0xd9, 0x0f, 0x88, 0x84]);
    const pps = Buffer.from([0x68, 0xce, 0x3c, 0x80]);
    const avcC = mp4Box(
      'avcC',
      Buffer.from([0x01, 0x42, 0xc0, 0x0a, 0xff, 0xe1, 0x00, sps.length]),
      sps,
      Buffer.from([0x01, 0x00, pps.length]),
      pps,
    );

    const avc1Body = Buffer.alloc(78);
    avc1Body.writeUInt16BE(1, 6); // data_reference_index
    avc1Body.writeUInt16BE(16, 24); // width
    avc1Body.writeUInt16BE(16, 26); // height
    avc1Body.writeUInt32BE(0x00480000, 28); // horizresolution 72 dpi
    avc1Body.writeUInt32BE(0x00480000, 32); // vertresolution 72 dpi
    avc1Body.writeUInt16BE(1, 40); // frame_count
    avc1Body.writeUInt16BE(0x0018, 74); // depth 24
    avc1Body.writeInt16BE(-1, 76); // pre_defined
    const avc1 = mp4Box('avc1', avc1Body, avcC);

    const stsdCount = Buffer.allocUnsafe(4);
    stsdCount.writeUInt32BE(1, 0);
    const stsd = mp4FullBox('stsd', 0, 0, stsdCount, avc1);

    const sttsBody = Buffer.allocUnsafe(12);
    sttsBody.writeUInt32BE(1, 0);
    sttsBody.writeUInt32BE(1, 4);
    sttsBody.writeUInt32BE(1000, 8);
    const stts = mp4FullBox('stts', 0, 0, sttsBody);

    const stscBody = Buffer.allocUnsafe(16);
    stscBody.writeUInt32BE(1, 0);
    stscBody.writeUInt32BE(1, 4);
    stscBody.writeUInt32BE(1, 8);
    stscBody.writeUInt32BE(1, 12);
    const stsc = mp4FullBox('stsc', 0, 0, stscBody);

    const stszBody = Buffer.allocUnsafe(12);
    stszBody.writeUInt32BE(0, 0);
    stszBody.writeUInt32BE(1, 4);
    stszBody.writeUInt32BE(mdatPayload.length, 8);
    const stsz = mp4FullBox('stsz', 0, 0, stszBody);

    const stcoBody = Buffer.allocUnsafe(8);
    stcoBody.writeUInt32BE(1, 0);
    stcoBody.writeUInt32BE(chunkOffset, 4);
    const stco = mp4FullBox('stco', 0, 0, stcoBody);

    const stbl = mp4Box('stbl', stsd, stts, stsc, stsz, stco);
    const minf = mp4Box('minf', vmhd, dinf, stbl);
    const mdia = mp4Box('mdia', mdhd, hdlr, minf);
    const trak = mp4Box('trak', tkhd, mdia);
    return mp4Box('moov', mvhd, trak);
  };

  // Compute exact stco offset (ftyp + moov + 8-byte mdat header)
  const draftMoov = buildMoov(0);
  const moov = buildMoov(ftyp.length + draftMoov.length + 8);
  const mdat = mp4Box('mdat', mdatPayload);

  return Buffer.concat([ftyp, moov, mdat]);
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
  if (!existsSync(video)) {
    writeFileSync(video, createMinimalMp4());
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
