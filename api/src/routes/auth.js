import { apiRequest } from '../lib/api-client.js';
import { signToken } from '../lib/auth.js';

function validateEmail(e) {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(e);
}

export async function authRoutes(fastify) {
  fastify.post('/api/login', async (req, reply) => {
    const { email, senha } = req.body || {};
    if (!email || !senha) return reply.code(400).send({ error: 'Email e senha obrigatórios' });
    try {
      // AVISO: a API externa compara senha em plaintext — ideal seria usar bcrypt/argon2 com hash
      const r = await apiRequest('read', { table: 'usuarios', filters: { email, senha } });
      const users = r.data || [];
      if (!users.length) return reply.code(401).send({ error: 'Credenciais inválidas' });
      const u = users[0];
      const token = signToken(u);
      return { success: true, user: { id: u.id, nome: u.nome, email: u.email, nivel: u.nivel }, token };
    } catch (e) {
      return reply.code(502).send({ error: 'Serviço indisponível' });
    }
  });

  fastify.post('/api/register', async (req, reply) => {
    const { nome, email, telefone, senha } = req.body || {};
    if (!nome || !email || !senha) return reply.code(400).send({ error: 'Campos obrigatórios' });
    if (!validateEmail(email)) return reply.code(400).send({ error: 'Email inválido' });
    try {
      const r = await apiRequest('create', { table: 'usuarios', data: { nome, email, telefone: telefone || null, senha, nivel: 'user' } });
      if (!r.success) return reply.code(400).send({ error: 'Erro ao criar conta' });
      const u = r.data;
      const token = signToken(u);
      return { success: true, user: { id: u.id, nome: u.nome, email: u.email, nivel: u.nivel }, token };
    } catch (e) {
      if (e.message.includes('unique')) return reply.code(409).send({ error: 'Email já cadastrado' });
      return reply.code(502).send({ error: 'Serviço indisponível' });
    }
  });
}
