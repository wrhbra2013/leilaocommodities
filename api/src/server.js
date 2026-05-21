import Fastify from 'fastify';
import fastifyStatic from '@fastify/static';
import cors from '@fastify/cors';
import rateLimit from '@fastify/rate-limit';
import 'dotenv/config';
import path from 'path';
import { fileURLToPath } from 'url';
import fs from 'fs';

import { authRoutes } from './routes/auth.js';
import { commoditiesRoutes } from './routes/commodities.js';
import { leiloesRoutes } from './routes/leiloes.js';
import { lancesRoutes } from './routes/lances.js';
import { adminRoutes } from './routes/admin.js';
import { cotacoesRoutes } from './routes/cotacoes.js';
import { healthRoutes } from './routes/health.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const PROJECT_ROOT = path.resolve(__dirname, '../..');
const fastify = Fastify({ logger: true });

await fastify.register(cors, { origin: true });
await fastify.register(rateLimit, { max: 100, timeWindow: '1 minute' });

await fastify.register(authRoutes);
await fastify.register(commoditiesRoutes);
await fastify.register(leiloesRoutes);
await fastify.register(lancesRoutes);
await fastify.register(adminRoutes);
await fastify.register(cotacoesRoutes);
await fastify.register(healthRoutes);

await fastify.register(fastifyStatic, {
  root: PROJECT_ROOT, prefix: '/', wildcard: false,
  setHeaders: (res, fp) => { if (fp.endsWith('.html')) res.setHeader('X-Robots-Tag', 'noindex'); },
});

fastify.setNotFoundHandler(async (req, res) => {
  const idx = path.join(PROJECT_ROOT, 'index.html');
  if (fs.existsSync(idx)) { const c = await fs.promises.readFile(idx, 'utf-8'); res.type('text/html').send(c); }
  else res.code(404).send('Not Found');
});

const PORT = parseInt(process.env.PORT || '3001');
await fastify.listen({ port: PORT, host: '0.0.0.0' });
console.log(`Server: http://0.0.0.0:${PORT}`);
