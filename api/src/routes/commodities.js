import { apiRequest } from '../lib/api-client.js';

export async function commoditiesRoutes(fastify) {
  fastify.get('/api/comodities', async () => {
    try {
      const r = await apiRequest('read', { table: 'comodities', filters: { ativo: true }, order_by: 'nome', order_dir: 'ASC' });
      return r.data || [];
    } catch { return []; }
  });

  fastify.get('/api/comodities/:slug', async (req, reply) => {
    try {
      const r = await apiRequest('read', { table: 'comodities', filters: { slug: req.params.slug } });
      if (!r.data || !r.data.length) return reply.code(404).send({ error: 'Não encontrada' });
      return r.data[0];
    } catch { return reply.code(502).send({ error: 'Serviço indisponível' }); }
  });
}
