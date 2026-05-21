import { apiRequest } from '../lib/api-client.js';

export async function leiloesRoutes(fastify) {
  fastify.post('/api/leiloes/read', async (req, reply) => {
    try {
      const { comoditie_id, status, limit = 50, offset = 0 } = req.body || {};
      const filters = {};
      if (comoditie_id) filters.comoditie_id = comoditie_id;
      if (status) filters.status = status;
      const r = await apiRequest('read', { table: 'leiloes', filters, limit, offset, order_by: 'data_fim', order_dir: 'ASC' });
      return { data: r.data || [] };
    } catch { return { data: [] }; }
  });

  fastify.get('/api/leiloes/:id', async (req, reply) => {
    try {
      const r = await apiRequest('read', { table: 'leiloes', filters: { id: req.params.id } });
      if (!r.data || !r.data.length) return reply.code(404).send({ error: 'Leilão não encontrado' });
      const leilao = r.data[0];
      try {
        const lancesR = await apiRequest('read', { table: 'lances', filters: { leilao_id: req.params.id }, order_by: 'valor', order_dir: 'DESC' });
        leilao.lances = lancesR.data || [];
      } catch { leilao.lances = []; }
      if (leilao.comoditie_id) {
        try {
          const comR = await apiRequest('read', { table: 'comodities', filters: { id: leilao.comoditie_id } });
          const c = comR.data?.[0];
          if (c) { leilao.comoditie_nome = c.nome; leilao.comoditie_slug = c.slug; leilao.unidade = c.unidade; leilao.icone = c.icone; }
        } catch {}
      }
      return leilao;
    } catch { return reply.code(502).send({ error: 'Serviço indisponível' }); }
  });
}
