import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { buildApp } from './app.js';

const backendRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const dbPath = process.env.DB_PATH || join(backendRoot, 'data', 'pos.db');
const mediaDir = process.env.MEDIA_DIR || join(backendRoot, 'public', 'media');
const port = Number(process.env.PORT ?? 3000);
const stockDelayMs = Number(process.env.STOCK_DELAY_MS ?? 1000);
const autoSeedCount = Number(process.env.AUTO_SEED_COUNT ?? 100000);

const app = buildApp({
  dbPath,
  mediaDir,
  stockDelayMs,
  autoSeedCount,
});

const shutdown = async () => {
  await app.close();
  process.exit(0);
};
process.once('SIGINT', shutdown);
process.once('SIGTERM', shutdown);

await app.listen({ host: '0.0.0.0', port });
console.log(`POS backend listening on http://0.0.0.0:${port}`);
