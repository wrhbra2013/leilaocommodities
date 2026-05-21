import Fastify from 'fastify';
import fastifyStatic from '@fastify/static';
import cors from '@fastify/cors';
import 'dotenv/config';
import path from 'path';
import { fileURLToPath } from 'url';
import fs from 'fs';
import crypto from 'crypto';
import fetch from 'node-fetch';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const PROJECT_ROOT = path.resolve(__dirname, '../..');
const fastify = Fastify({ logger: true });

const EXTERNAL_API = process.env.EXTERNAL_API || 'https://api.projetosdinamicos.com.br/leilao-commodities';
const API_TOKEN = process.env.API_TOKEN || crypto.randomUUID();

await fastify.register(cors, { origin: true });

function validateId(id) { return /^[a-zA-Z0-9_-]{1,128}$/.test(id); }
function validateEmail(e) { return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(e); }

async function apiRequest(action, body = {}) {
  const res = await fetch(`${EXTERNAL_API}/api/${action}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${API_TOKEN}` },
    body: JSON.stringify({ project: 'leilao-commodities', ...body }),
  });
  if (!res.ok) {
    const err = await res.json().catch(() => ({ error: 'API request failed' }));
    throw new Error(err.error || `HTTP ${res.status}`);
  }
  return res.json();
}

// ---- Auth ----
fastify.post('/api/login', async (req, reply) => {
  const { email, senha } = req.body || {};
  if (!email || !senha) return reply.code(400).send({ error: 'Email e senha obrigatórios' });
  try {
    const r = await apiRequest('read', { table: 'usuarios', filters: { email, senha } });
    const users = r.data || [];
    if (!users.length) return reply.code(401).send({ error: 'Credenciais inválidas' });
    const u = users[0];
    return { success: true, user: { id: u.id, nome: u.nome, email: u.email, nivel: u.nivel }, token: API_TOKEN };
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
    return { success: true, user: { id: u.id, nome: u.nome, email: u.email, nivel: u.nivel }, token: API_TOKEN };
  } catch (e) {
    if (e.message.includes('unique')) return reply.code(409).send({ error: 'Email já cadastrado' });
    return reply.code(502).send({ error: 'Serviço indisponível' });
  }
});

// ---- Commodities ----
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

// ---- Leiloes ----
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
    // Buscar lances do leilão
    try {
      const lancesR = await apiRequest('read', { table: 'lances', filters: { leilao_id: req.params.id }, order_by: 'valor', order_dir: 'DESC' });
      leilao.lances = lancesR.data || [];
    } catch { leilao.lances = []; }
    // Buscar commodity
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

// ---- Lances ----
fastify.post('/api/lances/criar', async (req, reply) => {
  const { leilao_id, usuario_id, valor } = req.body || {};
  if (!leilao_id || !usuario_id || !valor) return reply.code(400).send({ error: 'Campos obrigatórios' });
  if (!validateId(leilao_id) || !validateId(usuario_id)) return reply.code(400).send({ error: 'IDs inválidos' });

  try {
    // Buscar leilão
    const leilaoR = await apiRequest('read', { table: 'leiloes', filters: { id: leilao_id, status: 'ativo' } });
    if (!leilaoR.data || !leilaoR.data.length) return reply.code(404).send({ error: 'Leilão não encontrado ou encerrado' });
    const l = leilaoR.data[0];

    if (parseFloat(valor) <= parseFloat(l.preco_atual)) return reply.code(400).send({ error: 'Lance deve ser maior que o preço atual' });
    if (l.valor_minimo_lance && parseFloat(valor) < parseFloat(l.preco_atual) + parseFloat(l.valor_minimo_lance))
      return reply.code(400).send({ error: `Lance mínimo de R$ ${parseFloat(l.valor_minimo_lance).toFixed(2)} acima do atual` });
    if (new Date() > new Date(l.data_fim)) return reply.code(400).send({ error: 'Leilão encerrado' });

    // Criar lance
    const r = await apiRequest('create', { table: 'lances', data: { leilao_id, usuario_id, valor } });
    if (!r.success) return reply.code(400).send({ error: 'Erro ao registrar lance' });

    // Atualizar preço atual do leilão
    await apiRequest('update', { table: 'leiloes', id: leilao_id, data: { preco_atual: valor } });

    return { success: true, data: r.data };
  } catch (e) {
    return reply.code(502).send({ error: 'Serviço indisponível', details: e.message });
  }
});

fastify.get('/api/lances/:leilao_id', async (req, reply) => {
  try {
    const r = await apiRequest('read', { table: 'lances', filters: { leilao_id: req.params.leilao_id }, order_by: 'valor', order_dir: 'DESC' });
    return r.data || [];
  } catch { return []; }
});

// ---- Admin ----
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

fastify.post('/api/admin/usuarios', async (req, reply) => {
  try {
    const r = await apiRequest('read', { table: 'usuarios', order_by: 'created_at', order_dir: 'DESC' });
    return { data: (r.data || []).map(u => ({ id: u.id, nome: u.nome, email: u.email, telefone: u.telefone, nivel: u.nivel, created_at: u.created_at })) };
  } catch { return { data: [] }; }
});

fastify.post('/api/admin/leiloes', async (req, reply) => {
  try {
    const r = await apiRequest('read', { table: 'leiloes', order_by: 'created_at', order_dir: 'DESC' });
    const leiloes = r.data || [];
    // Enriquecer com nome da commodity
    for (const l of leiloes) {
      if (l.comoditie_id) {
        try { const c = await apiRequest('read', { table: 'comodities', filters: { id: l.comoditie_id } }); if (c.data?.[0]) l.comoditie_nome = c.data[0].nome; } catch {}
      }
      try { const lc = await apiRequest('read', { table: 'lances', filters: { leilao_id: l.id } }); l.total_lances = (lc.data || []).length; } catch { l.total_lances = 0; }
    }
    return { data: leiloes };
  } catch { return { data: [] }; }
});

// ---- Cotacoes ----
fastify.get('/api/cotacoes', async (req, reply) => {
  const mock = {
    soja: { preco: 138.50, variacao: '+2.30', data: new Date().toISOString().split('T')[0] },
    milho: { preco: 62.80, variacao: '-0.75', data: new Date().toISOString().split('T')[0] },
    'cafe-arabica': { preco: 245.90, variacao: '+5.10', data: new Date().toISOString().split('T')[0] },
    'boi-gordo': { preco: 310.00, variacao: '+1.50', data: new Date().toISOString().split('T')[0] },
    'acucar-cristal': { preco: 85.20, variacao: '-1.20', data: new Date().toISOString().split('T')[0] },
    algodao: { preco: 112.40, variacao: '+0.80', data: new Date().toISOString().split('T')[0] },
    'petroleo-brent': { preco: 82.15, variacao: '-1.45', data: new Date().toISOString().split('T')[0] },
    ouro: { preco: 345.60, variacao: '+3.20', data: new Date().toISOString().split('T')[0] },
  };
  const { comodities: slugs } = req.query;
  if (slugs) return slugs.split(',').reduce((acc, s) => { if (mock[s]) acc[s] = mock[s]; return acc; }, {});
  return mock;
});

// ---- Static Files ----
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
