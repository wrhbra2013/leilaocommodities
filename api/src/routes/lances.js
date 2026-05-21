import { apiRequest } from '../lib/api-client.js';
import { authenticate } from '../lib/auth.js';

function validateId(id) { return /^[a-zA-Z0-9_-]{1,128}$/.test(id); }

export async function lancesRoutes(fastify) {
  fastify.get('/api/lances/:leilao_id', async (req, reply) => {
    try {
      const r = await apiRequest('read', { table: 'lances', filters: { leilao_id: req.params.leilao_id }, order_by: 'valor', order_dir: 'DESC' });
      return r.data || [];
    } catch { return []; }
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
