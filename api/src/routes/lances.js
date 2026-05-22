import { apiRequest } from '../lib/api-client.js';
import { authenticate } from '../lib/auth.js';

function validateId(id) { return /^[a-zA-Z0-9_-]{1,128}$/.test(id); }

export async function lancesRoutes(fastify) {
  fastify.get('/api/meus-lances', { preHandler: [authenticate] }, async (req, reply) => {
    try {
      const r = await apiRequest('read', { table: 'lances', filters: { usuario_id: req.user.id }, order_by: 'timestamp', order_dir: 'DESC' });
      const lances = r.data || [];
      const leilaoIds = [...new Set(lances.map(l => l.leilao_id))];
      const leiloes = {};
      for (const id of leilaoIds) {
        try {
          const lr = await apiRequest('read', { table: 'leiloes', filters: { id } });
          if (lr.data?.[0]) {
            const lei = lr.data[0];
            if (lei.comoditie_id) {
              try { const cr = await apiRequest('read', { table: 'comodities', filters: { id: lei.comoditie_id } }); if (cr.data?.[0]) { lei.comoditie_nome = cr.data[0].nome; lei.unidade = cr.data[0].unidade; } } catch {}
            }
            leiloes[id] = lei;
          }
        } catch {}
      }
      return { data: lances.map(l => ({ ...l, leilao: leiloes[l.leilao_id] || null })) };
    } catch (e) { req.log.error(e, 'meus lances'); return { data: [] }; }
  });

  fastify.get('/api/lances/:leilao_id', async (req, reply) => {
    try {
      const r = await apiRequest('read', { table: 'lances', filters: { leilao_id: req.params.leilao_id }, order_by: 'valor', order_dir: 'DESC' });
      return r.data || [];
    } catch (e) { req.log.error(e, 'lances list'); return []; }
  });

  fastify.post('/api/lances/criar', { preHandler: [authenticate] }, async (req, reply) => {
    const { leilao_id, valor } = req.body || {};
    const usuario_id = req.user.id;
    if (!leilao_id || !valor) return reply.code(400).send({ error: 'Campos obrigatórios' });
    if (!validateId(leilao_id)) return reply.code(400).send({ error: 'IDs inválidos' });

    try {
      const leilaoR = await apiRequest('read', { table: 'leiloes', filters: { id: leilao_id, status: 'ativo' } });
      if (!leilaoR.data || !leilaoR.data.length) return reply.code(404).send({ error: 'Leilão não encontrado ou encerrado' });
      const l = leilaoR.data[0];

      if (parseFloat(valor) <= parseFloat(l.preco_atual)) return reply.code(400).send({ error: 'Lance deve ser maior que o preço atual' });
      if (l.valor_minimo_lance && parseFloat(valor) < parseFloat(l.preco_atual) + parseFloat(l.valor_minimo_lance))
        return reply.code(400).send({ error: `Lance mínimo de R$ ${parseFloat(l.valor_minimo_lance).toFixed(2)} acima do atual` });
      if (new Date() > new Date(l.data_fim)) return reply.code(400).send({ error: 'Leilão encerrado' });

      const r = await apiRequest('create', { table: 'lances', data: { leilao_id, usuario_id, valor } });
      if (!r.success) return reply.code(400).send({ error: 'Erro ao registrar lance' });

      await apiRequest('update', { table: 'leiloes', id: leilao_id, data: { preco_atual: valor } });
      return { success: true, data: r.data };
    } catch (e) {
      return reply.code(502).send({ error: 'Serviço indisponível' });
    }
  });
}
