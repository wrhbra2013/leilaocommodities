import { apiRequest } from '../lib/api-client.js';
import { authenticate, requireAdmin } from '../lib/auth.js';

export async function adminRoutes(fastify) {
  fastify.addHook('preHandler', authenticate);
  fastify.addHook('preHandler', requireAdmin);

  fastify.post('/api/admin/leiloes/criar', async (req, reply) => {
    const { titulo, descricao, comoditie_id, quantidade, preco_inicial, valor_minimo_lance, data_fim, foto_url } = req.body || {};
    if (!titulo || !comoditie_id || !preco_inicial) return reply.code(400).send({ error: 'Campos obrigatórios' });
    try {
      const r = await apiRequest('create', {
        table: 'leiloes',
        data: {
          titulo, descricao: descricao || '', comoditie_id, quantidade: quantidade || 1,
          preco_inicial, preco_atual: preco_inicial,
          valor_minimo_lance: valor_minimo_lance || null,
          data_inicio: new Date().toISOString(),
          data_fim: data_fim || new Date(Date.now() + 7*24*60*60*1000).toISOString(),
          status: 'ativo', foto_url: foto_url || null,
        }
      });
      return { success: true, data: r.data };
    } catch (e) {
      return reply.code(502).send({ error: 'Erro ao criar leilão', details: e.message });
    }
  });

  fastify.post('/api/admin/leiloes/update', async (req, reply) => {
    const { id, ...data } = req.body || {};
    if (!id) return reply.code(400).send({ error: 'ID obrigatório' });
    try {
      const r = await apiRequest('update', { table: 'leiloes', id, data });
      return { success: true, data: r.data };
    } catch (e) {
      return reply.code(502).send({ error: 'Erro ao atualizar', details: e.message });
    }
  });

  fastify.post('/api/admin/leiloes', async (req, reply) => {
    try {
      const r = await apiRequest('read', { table: 'leiloes', order_by: 'created_at', order_dir: 'DESC' });
      const leiloes = r.data || [];
      for (const l of leiloes) {
        if (l.comoditie_id) {
          try { const c = await apiRequest('read', { table: 'comodities', filters: { id: l.comoditie_id } }); if (c.data?.[0]) l.comoditie_nome = c.data[0].nome; } catch {}
        }
        try { const lc = await apiRequest('read', { table: 'lances', filters: { leilao_id: l.id } }); l.total_lances = (lc.data || []).length; } catch { l.total_lances = 0; }
      }
      return { data: leiloes };
    } catch { return { data: [] }; }
  });

  fastify.post('/api/admin/usuarios', async (req, reply) => {
    try {
      const r = await apiRequest('read', { table: 'usuarios', order_by: 'created_at', order_dir: 'DESC' });
      return { data: (r.data || []).map(u => ({ id: u.id, nome: u.nome, email: u.email, telefone: u.telefone, nivel: u.nivel, created_at: u.created_at })) };
    } catch { return { data: [] }; }
  });
}
