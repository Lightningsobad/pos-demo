import { resolve } from 'node:path';
import Fastify from 'fastify';
import cors from '@fastify/cors';
import fastifyStatic from '@fastify/static';
import { openDatabase } from './db/database.js';
import { ensureSampleMedia, seedProducts } from './db/seed.js';
import { registerProductRoutes } from './routes/products.js';
import { registerOrderRoutes } from './routes/orders.js';

/**
 * Build and configure the Fastify application instance.
 * @param {{ dbPath: string, mediaDir: string, stockDelayMs?: number, autoSeedCount?: number }} options
 * @returns {import('fastify').FastifyInstance}
 */
export function buildApp({
  dbPath,
  mediaDir,
  stockDelayMs = 1000,
  autoSeedCount = 0,
}) {
  const resolvedMediaDir = resolve(mediaDir);
  ensureSampleMedia(resolvedMediaDir);

  const db = openDatabase(dbPath);
  try {
    if (autoSeedCount > 0) {
      seedProducts(db, autoSeedCount);
    }
  } catch (err) {
    db.close();
    throw err;
  }

  const fastify = Fastify({ logger: false });
  fastify.decorate('db', db);

  fastify.register(cors, { origin: true });
  fastify.register(fastifyStatic, {
    root: resolvedMediaDir,
    prefix: '/media/',
  });
  fastify.register(registerProductRoutes, {
    db,
    stockDelayMs,
    mediaDir: resolvedMediaDir,
  });
  fastify.register(registerOrderRoutes, { db });

  fastify.addHook('onClose', async () => {
    db.close();
  });

  return fastify;
}
