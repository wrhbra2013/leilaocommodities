#!/usr/bin/env bash
set -euo pipefail

# ==============================================================
# Script de instalação — Leilão Commodities API
# Uso: sudo bash install.sh
# - Cria estrutura em /var/www/leilaocommodities/
# - API Node.js com CRUD PostgreSQL na porta 3002
# - Configura Nginx (location /api/ -> localhost:3002)
# - PM2 ecosystem.config.js
# ==============================================================

INSTALL_DIR="/var/www/leilaocommodities"
API_DIR="$INSTALL_DIR/api"
SRC_DIR="$API_DIR/src"
ROUTES_DIR="$SRC_DIR/routes"
MIDDLEWARE_DIR="$SRC_DIR/middleware"
NGINX_AVAILABLE="/etc/nginx/sites-available"
NGINX_CONF="$NGINX_AVAILABLE/default"

# Cores para output
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERRO]${NC} $1"; exit 1; }

# --------------------------------------------------------------
# 0. Verificações
# --------------------------------------------------------------
[[ $EUID -eq 0 ]] || error "Execute como root: sudo bash install.sh"

command -v node  >/dev/null 2>&1 || error "Node.js não encontrado"
command -v npm   >/dev/null 2>&1 || error "npm não encontrado"
command -v psql  >/dev/null 2>&1 || warn "psql não encontrado — PostgreSQL pode não estar instalado"
command -v pm2   >/dev/null 2>&1 || warn "pm2 não encontrado — será instalado via npm"

# --------------------------------------------------------------
# 1. Criar estrutura de diretórios
# --------------------------------------------------------------
info "Criando diretórios em $INSTALL_DIR"
mkdir -p "$ROUTES_DIR" "$MIDDLEWARE_DIR"

# --------------------------------------------------------------
# 2. Criar .env
# --------------------------------------------------------------
info "Criando .env"
cat > "$API_DIR/.env" <<'ENVEOF'
PORT=3002
DB_HOST=localhost
DB_PORT=5432
DB_NAME=leilaocommodities
DB_USER=leilaoadmin
DB_PASS=suasenhaaqui
JWT_SECRET=troque_por_uma_chave_segura_32chars
JWT_EXPIRES_IN=7d
ENVEOF

chmod 600 "$API_DIR/.env"

# --------------------------------------------------------------
# 3. Criar package.json
# --------------------------------------------------------------
info "Criando package.json"
cat > "$API_DIR/package.json" <<'JSONEOF'
{
  "name": "leilaocommodities-api",
  "version": "1.0.0",
  "private": true,
  "scripts": {
    "start": "node src/server.js",
    "dev": "node --watch src/server.js",
    "migrate": "node src/migrate.js"
  },
  "dependencies": {
    "bcryptjs": "^2.4.3",
    "cors": "^2.8.5",
    "dotenv": "^16.4.5",
    "express": "^4.21.0",
    "jsonwebtoken": "^9.0.2",
    "pg": "^8.12.0"
  }
}
JSONEOF

# --------------------------------------------------------------
# 4. Criar database.js (conexão PostgreSQL)
# --------------------------------------------------------------
info "Criando src/database.js"
cat > "$SRC_DIR/database.js" <<'DBEOF'
const { Pool } = require('pg');
require('dotenv').config();

const pool = new Pool({
  host: process.env.DB_HOST || 'localhost',
  port: parseInt(process.env.DB_PORT || '5432'),
  database: process.env.DB_NAME || 'leilaocommodities',
  user: process.env.DB_USER || 'leilaoadmin',
  password: process.env.DB_PASS || '',
  max: 20,
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: 5000,
});

pool.on('error', (err) => {
  console.error('Erro inesperado no pool PostgreSQL:', err);
});

module.exports = {
  query: (text, params) => pool.query(text, params),
  pool,
};
DBEOF

# --------------------------------------------------------------
# 5. Criar migrate.js (schema + seed)
# --------------------------------------------------------------
info "Criando src/migrate.js"
cat > "$SRC_DIR/migrate.js" <<'MGEOF'
require('dotenv').config();
const { query, pool } = require('./database');

async function migrate() {
  console.log('>>> Iniciando migração...');

  await query(`
    CREATE TABLE IF NOT EXISTS usuarios (
      id SERIAL PRIMARY KEY,
      nome VARCHAR(120) NOT NULL,
      email VARCHAR(255) UNIQUE NOT NULL,
      telefone VARCHAR(20),
      senha VARCHAR(255) NOT NULL,
      admin BOOLEAN DEFAULT false,
      created_at TIMESTAMP DEFAULT NOW(),
      updated_at TIMESTAMP DEFAULT NOW()
    );
  `);
  console.log('  OK  usuarios');

  await query(`
    CREATE TABLE IF NOT EXISTS comodities (
      id SERIAL PRIMARY KEY,
      nome VARCHAR(80) UNIQUE NOT NULL,
      sigla VARCHAR(10),
      preco DECIMAL(12,2) DEFAULT 0,
      variacao DECIMAL(6,2) DEFAULT 0,
      updated_at TIMESTAMP DEFAULT NOW()
    );
  `);
  console.log('  OK  comodities');

  await query(`
    CREATE TABLE IF NOT EXISTS leiloes (
      id SERIAL PRIMARY KEY,
      titulo VARCHAR(200) NOT NULL,
      descricao TEXT,
      comoditie_id INTEGER REFERENCES comodities(id),
      quantidade DECIMAL(12,2) DEFAULT 1,
      preco_inicial DECIMAL(12,2) NOT NULL,
      valor_min_lance DECIMAL(12,2),
      data_fim TIMESTAMP NOT NULL,
      status VARCHAR(20) DEFAULT 'ativo',
      criado_por INTEGER REFERENCES usuarios(id),
      created_at TIMESTAMP DEFAULT NOW(),
      updated_at TIMESTAMP DEFAULT NOW()
    );
  `);
  console.log('  OK  leiloes');

  await query(`
    CREATE TABLE IF NOT EXISTS lances (
      id SERIAL PRIMARY KEY,
      leilao_id INTEGER REFERENCES leiloes(id) ON DELETE CASCADE,
      usuario_id INTEGER REFERENCES usuarios(id),
      valor DECIMAL(12,2) NOT NULL,
      created_at TIMESTAMP DEFAULT NOW()
    );
  `);
  console.log('  OK  lances');

  // Seed comodities
  const { rowCount } = await query('SELECT COUNT(*) FROM comodities');
  if (parseInt(rowCount) === 0) {
    const seed = [
      ['Soja', 'SOJ', 142.30, 1.25],
      ['Milho', 'MIL', 68.90, -0.45],
      ['Café Arábica', 'CAF', 1240.50, 3.80],
      ['Boi Gordo', 'BGI', 235.70, 0.92],
      ['Trigo', 'TRI', 95.40, -0.30],
      ['Algodão', 'ALG', 185.20, 1.10],
      ['Açúcar', 'ACU', 130.80, -0.65],
      ['Etanol', 'ETA', 3.45, 0.02],
    ];
    for (const [nome, sigla, preco, variacao] of seed) {
      await query(
        'INSERT INTO comodities (nome, sigla, preco, variacao) VALUES ($1, $2, $3, $4)',
        [nome, sigla, preco, variacao]
      );
    }
    console.log('  OK  comodities seed (8 registros)');
  }

  // Seed admin user
  const { rowCount: userCount } = await query('SELECT COUNT(*) FROM usuarios');
  if (parseInt(userCount) === 0) {
    const bcrypt = require('bcryptjs');
    const hash = await bcrypt.hash('admin123', 10);
    await query(
      'INSERT INTO usuarios (nome, email, telefone, senha, admin) VALUES ($1, $2, $3, $4, true)',
      ['Administrador', 'admin@leilaocommodities.com.br', '(14) 99999-9999', hash]
    );
    console.log('  OK  admin user: admin@leilaocommodities.com.br / admin123');
  }

  console.log('>>> Migração concluída!');
  await pool.end();
}

migrate().catch((err) => {
  console.error('Falha na migração:', err.message);
  process.exit(1);
});
MGEOF

# --------------------------------------------------------------
# 6. Criar middleware/auth.js
# --------------------------------------------------------------
info "Criando src/middleware/auth.js"
cat > "$MIDDLEWARE_DIR/auth.js" <<'AUTHEOF'
const jwt = require('jsonwebtoken');
require('dotenv').config();

const SECRET = process.env.JWT_SECRET || 'fallback_secret_change_me';

function gerarToken(usuario) {
  return jwt.sign(
    { id: usuario.id, email: usuario.email, admin: usuario.admin },
    SECRET,
    { expiresIn: process.env.JWT_EXPIRES_IN || '7d' }
  );
}

function autenticar(req, res, next) {
  const header = req.headers.authorization;
  if (!header) return res.status(401).json({ erro: 'Token não fornecido' });
  const token = header.startsWith('Bearer ') ? header.slice(7) : header;
  try {
    req.usuario = jwt.verify(token, SECRET);
    next();
  } catch {
    return res.status(401).json({ erro: 'Token inválido ou expirado' });
  }
}

function adminOnly(req, res, next) {
  if (!req.usuario || !req.usuario.admin) {
    return res.status(403).json({ erro: 'Acesso restrito a administradores' });
  }
  next();
}

module.exports = { gerarToken, autenticar, adminOnly };
AUTHEOF

# --------------------------------------------------------------
# 7. Criar rotas
# --------------------------------------------------------------

# 7a. auth.js
info "Criando routes/auth.js"
cat > "$ROUTES_DIR/auth.js" <<'AUTHEOF'
const { Router } = require('express');
const bcrypt = require('bcryptjs');
const db = require('../database');
const { gerarToken } = require('../middleware/auth');

const router = Router();

router.post('/register', async (req, res) => {
  try {
    const { nome, email, telefone, senha } = req.body;
    if (!nome || !email || !senha || senha.length < 6)
      return res.status(400).json({ erro: 'Nome, email e senha (min 6) são obrigatórios' });
    const existente = await db.query('SELECT id FROM usuarios WHERE email = $1', [email]);
    if (existente.rows.length)
      return res.status(409).json({ erro: 'Email já cadastrado' });
    const hash = await bcrypt.hash(senha, 10);
    const { rows } = await db.query(
      'INSERT INTO usuarios (nome, email, telefone, senha) VALUES ($1,$2,$3,$4) RETURNING id, nome, email, admin, created_at',
      [nome, email, telefone || null, hash]
    );
    const usuario = rows[0];
    const token = gerarToken(usuario);
    res.status(201).json({ usuario, token });
  } catch (err) {
    console.error('Erro register:', err);
    res.status(500).json({ erro: 'Erro interno do servidor' });
  }
});

router.post('/login', async (req, res) => {
  try {
    const { email, senha } = req.body;
    if (!email || !senha)
      return res.status(400).json({ erro: 'Email e senha são obrigatórios' });
    const { rows } = await db.query('SELECT * FROM usuarios WHERE email = $1', [email]);
    if (!rows.length)
      return res.status(401).json({ erro: 'Credenciais inválidas' });
    const usuario = rows[0];
    const valida = await bcrypt.compare(senha, usuario.senha);
    if (!valida)
      return res.status(401).json({ erro: 'Credenciais inválidas' });
    const token = gerarToken(usuario);
    delete usuario.senha;
    res.json({ usuario, token });
  } catch (err) {
    console.error('Erro login:', err);
    res.status(500).json({ erro: 'Erro interno do servidor' });
  }
});

module.exports = router;
AUTHEOF

# 7b. usuarios.js
info "Criando routes/usuarios.js"
cat > "$ROUTES_DIR/usuarios.js" <<'USRSEOF'
const { Router } = require('express');
const db = require('../database');
const { autenticar, adminOnly } = require('../middleware/auth');

const router = Router();

router.get('/', autenticar, adminOnly, async (req, res) => {
  try {
    const { rows } = await db.query(
      'SELECT id, nome, email, telefone, admin, created_at FROM usuarios ORDER BY created_at DESC'
    );
    res.json(rows);
  } catch (err) {
    console.error(err);
    res.status(500).json({ erro: 'Erro ao listar usuários' });
  }
});

router.put('/:id', autenticar, adminOnly, async (req, res) => {
  try {
    const { id } = req.params;
    const { nome, email, telefone, admin } = req.body;
    const { rows } = await db.query(
      `UPDATE usuarios SET nome=$1, email=$2, telefone=$3, admin=$4, updated_at=NOW()
       WHERE id=$5 RETURNING id, nome, email, telefone, admin, created_at`,
      [nome, email, telefone, admin, id]
    );
    if (!rows.length) return res.status(404).json({ erro: 'Usuário não encontrado' });
    res.json(rows[0]);
  } catch (err) {
    console.error(err);
    res.status(500).json({ erro: 'Erro ao atualizar usuário' });
  }
});

router.delete('/:id', autenticar, adminOnly, async (req, res) => {
  try {
    const { id } = req.params;
    const { rowCount } = await db.query('DELETE FROM usuarios WHERE id=$1', [id]);
    if (!rowCount) return res.status(404).json({ erro: 'Usuário não encontrado' });
    res.json({ ok: true });
  } catch (err) {
    console.error(err);
    res.status(500).json({ erro: 'Erro ao remover usuário' });
  }
});

module.exports = router;
USRSEOF

# 7c. comodities.js
info "Criando routes/comodities.js"
cat > "$ROUTES_DIR/comodities.js" <<'CMDFEOF'
const { Router } = require('express');
const db = require('../database');
const { autenticar, adminOnly } = require('../middleware/auth');

const router = Router();

router.get('/', async (_req, res) => {
  try {
    const { rows } = await db.query('SELECT * FROM comodities ORDER BY nome');
    res.json(rows);
  } catch (err) {
    console.error(err);
    res.status(500).json({ erro: 'Erro ao listar commodities' });
  }
});

router.put('/:id/preco', autenticar, adminOnly, async (req, res) => {
  try {
    const { id } = req.params;
    const { preco, variacao } = req.body;
    const { rows } = await db.query(
      'UPDATE comodities SET preco=$1, variacao=$2, updated_at=NOW() WHERE id=$3 RETURNING *',
      [preco, variacao, id]
    );
    if (!rows.length) return res.status(404).json({ erro: 'Commoditie não encontrada' });
    res.json(rows[0]);
  } catch (err) {
    console.error(err);
    res.status(500).json({ erro: 'Erro ao atualizar preço' });
  }
});

module.exports = router;
CMDFEOF

# 7d. leiloes.js
info "Criando routes/leiloes.js"
cat > "$ROUTES_DIR/leiloes.js" <<'LEILEOF'
const { Router } = require('express');
const db = require('../database');
const { autenticar, adminOnly } = require('../middleware/auth');

const router = Router();

router.get('/', async (req, res) => {
  try {
    const { comoditie, status } = req.query;
    let sql = `
      SELECT l.*, c.nome AS comoditie_nome, c.sigla AS comoditie_sigla,
        (SELECT COUNT(*) FROM lances WHERE leilao_id = l.id) AS total_lances,
        (SELECT COALESCE(MAX(valor), l.preco_inicial) FROM lances WHERE leilao_id = l.id) AS maior_lance
      FROM leiloes l
      JOIN comodities c ON c.id = l.comoditie_id
      WHERE 1=1
    `;
    const params = [];
    if (comoditie) { params.push(comoditie); sql += ` AND l.comoditie_id = $${params.length}`; }
    if (status) { params.push(status); sql += ` AND l.status = $${params.length}`; }
    sql += ' ORDER BY l.created_at DESC';
    const { rows } = await db.query(sql, params);
    res.json(rows);
  } catch (err) {
    console.error(err);
    res.status(500).json({ erro: 'Erro ao listar leilões' });
  }
});

router.get('/:id', async (req, res) => {
  try {
    const { id } = req.params;
    const { rows } = await db.query(
      `SELECT l.*, c.nome AS comoditie_nome, c.sigla AS comoditie_sigla,
        (SELECT COUNT(*) FROM lances WHERE leilao_id = l.id) AS total_lances,
        (SELECT COALESCE(MAX(valor), l.preco_inicial) FROM lances WHERE leilao_id = l.id) AS maior_lance
      FROM leiloes l
      JOIN comodities c ON c.id = l.comoditie_id
      WHERE l.id = $1`, [id]
    );
    if (!rows.length) return res.status(404).json({ erro: 'Leilão não encontrado' });
    // busca lances do leilão
    const lances = await db.query(
      `SELECT l.*, u.nome AS usuario_nome
       FROM lances l JOIN usuarios u ON u.id = l.usuario_id
       WHERE l.leilao_id = $1 ORDER BY l.valor DESC`, [id]
    );
    res.json({ ...rows[0], lances: lances.rows });
  } catch (err) {
    console.error(err);
    res.status(500).json({ erro: 'Erro ao buscar leilão' });
  }
});

router.post('/', autenticar, adminOnly, async (req, res) => {
  try {
    const { titulo, descricao, comoditie_id, quantidade, preco_inicial, valor_min_lance, data_fim } = req.body;
    if (!titulo || !comoditie_id || !preco_inicial || !data_fim)
      return res.status(400).json({ erro: 'Título, commodity, preço inicial e data fim são obrigatórios' });
    const { rows } = await db.query(
      `INSERT INTO leiloes (titulo, descricao, comoditie_id, quantidade, preco_inicial, valor_min_lance, data_fim, criado_por)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8) RETURNING *`,
      [titulo, descricao || '', comoditie_id, quantidade || 1, preco_inicial, valor_min_lance || null, data_fim, req.usuario.id]
    );
    res.status(201).json(rows[0]);
  } catch (err) {
    console.error(err);
    res.status(500).json({ erro: 'Erro ao criar leilão' });
  }
});

router.put('/:id', autenticar, adminOnly, async (req, res) => {
  try {
    const { id } = req.params;
    const { titulo, descricao, comoditie_id, quantidade, preco_inicial, valor_min_lance, data_fim, status } = req.body;
    const { rows } = await db.query(
      `UPDATE leiloes SET titulo=$1, descricao=$2, comoditie_id=$3, quantidade=$4,
        preco_inicial=$5, valor_min_lance=$6, data_fim=$7, status=$8, updated_at=NOW()
       WHERE id=$9 RETURNING *`,
      [titulo, descricao, comoditie_id, quantidade, preco_inicial, valor_min_lance, data_fim, status, id]
    );
    if (!rows.length) return res.status(404).json({ erro: 'Leilão não encontrado' });
    res.json(rows[0]);
  } catch (err) {
    console.error(err);
    res.status(500).json({ erro: 'Erro ao atualizar leilão' });
  }
});

router.delete('/:id', autenticar, adminOnly, async (req, res) => {
  try {
    const { id } = req.params;
    await db.query('DELETE FROM lances WHERE leilao_id = $1', [id]);
    const { rowCount } = await db.query('DELETE FROM leiloes WHERE id = $1', [id]);
    if (!rowCount) return res.status(404).json({ erro: 'Leilão não encontrado' });
    res.json({ ok: true });
  } catch (err) {
    console.error(err);
    res.status(500).json({ erro: 'Erro ao remover leilão' });
  }
});

module.exports = router;
LEILEOF

# 7e. lances.js
info "Criando routes/lances.js"
cat > "$ROUTES_DIR/lances.js" <<'LANCESEOF'
const { Router } = require('express');
const db = require('../database');
const { autenticar } = require('../middleware/auth');

const router = Router();

router.get('/meus', autenticar, async (req, res) => {
  try {
    const { rows } = await db.query(
      `SELECT l.*, le.titulo AS leilao_titulo, c.nome AS comoditie_nome
       FROM lances l
       JOIN leiloes le ON le.id = l.leilao_id
       JOIN comodities c ON c.id = le.comoditie_id
       WHERE l.usuario_id = $1
       ORDER BY l.created_at DESC`, [req.usuario.id]
    );
    res.json(rows);
  } catch (err) {
    console.error(err);
    res.status(500).json({ erro: 'Erro ao listar seus lances' });
  }
});

router.post('/', autenticar, async (req, res) => {
  try {
    const { leilao_id, valor } = req.body;
    if (!leilao_id || !valor)
      return res.status(400).json({ erro: 'Leilão e valor são obrigatórios' });

    const leilao = await db.query('SELECT * FROM leiloes WHERE id = $1', [leilao_id]);
    if (!leilao.rows.length)
      return res.status(404).json({ erro: 'Leilão não encontrado' });
    if (leilao.rows[0].status !== 'ativo')
      return res.status(400).json({ erro: 'Leilão não está ativo' });
    if (new Date(leilao.rows[0].data_fim) < new Date())
      return res.status(400).json({ erro: 'Leilão já encerrado' });

    const maiorLance = await db.query(
      'SELECT COALESCE(MAX(valor), $1) AS atual FROM lances WHERE leilao_id = $2',
      [leilao.rows[0].preco_inicial, leilao_id]
    );
    if (valor <= parseFloat(maiorLance.rows[0].atual))
      return res.status(400).json({ erro: 'Lance deve ser maior que o maior lance atual' });

    if (leilao.rows[0].valor_min_lance && (valor - parseFloat(maiorLance.rows[0].atual)) < parseFloat(leilao.rows[0].valor_min_lance))
      return res.status(400).json({ erro: `Diferença mínima do lance é R$ ${parseFloat(leilao.rows[0].valor_min_lance).toFixed(2)}` });

    const { rows } = await db.query(
      'INSERT INTO lances (leilao_id, usuario_id, valor) VALUES ($1,$2,$3) RETURNING *',
      [leilao_id, req.usuario.id, valor]
    );
    res.status(201).json(rows[0]);
  } catch (err) {
    console.error(err);
    res.status(500).json({ erro: 'Erro ao registrar lance' });
  }
});

module.exports = router;
LANCESEOF

# 7f. dashboard.js
info "Criando routes/dashboard.js"
cat > "$ROUTES_DIR/dashboard.js" <<'DSHEOF'
const { Router } = require('express');
const db = require('../database');
const { autenticar, adminOnly } = require('../middleware/auth');

const router = Router();

router.get('/', autenticar, adminOnly, async (_req, res) => {
  try {
    const [usuarios, leiloes, lances, comodities] = await Promise.all([
      db.query('SELECT COUNT(*)::int AS total FROM usuarios'),
      db.query("SELECT COUNT(*)::int AS total FROM leiloes WHERE status = 'ativo'"),
      db.query('SELECT COUNT(*)::int AS total FROM lances'),
      db.query('SELECT COUNT(*)::int AS total FROM comodities'),
    ]);
    const { rows: ultimos } = await db.query(
      `SELECT l.*, c.nome AS comoditie_nome
       FROM leiloes l JOIN comodities c ON c.id = l.comoditie_id
       ORDER BY l.created_at DESC LIMIT 5`
    );
    res.json({
      usuarios: usuarios.rows[0].total,
      leiloes_ativos: leiloes.rows[0].total,
      total_lances: lances.rows[0].total,
      comodities: comodities.rows[0].total,
      ultimos_leiloes: ultimos,
    });
  } catch (err) {
    console.error(err);
    res.status(500).json({ erro: 'Erro ao carregar dashboard' });
  }
});

module.exports = router;
DSHEOF

# --------------------------------------------------------------
# 8. Criar server.js (entrypoint)
# --------------------------------------------------------------
info "Criando src/server.js"
cat > "$SRC_DIR/server.js" <<'SVREOF'
require('dotenv').config({ path: require('path').join(__dirname, '..', '.env') });
const express = require('express');
const cors = require('cors');

const app = express();
const PORT = process.env.PORT || 3002;

app.use(cors());
app.use(express.json());

// Rotas
app.use('/api/auth',       require('./routes/auth'));
app.use('/api/usuarios',   require('./routes/usuarios'));
app.use('/api/comodities', require('./routes/comodities'));
app.use('/api/leiloes',    require('./routes/leiloes'));
app.use('/api/lances',     require('./routes/lances'));
app.use('/api/dashboard',  require('./routes/dashboard'));

// Health check
app.get('/api/ping', (_req, res) => res.json({ ok: true, time: new Date().toISOString() }));

// 404
app.use((_req, res) => res.status(404).json({ erro: 'Rota não encontrada' }));

// Error handler
app.use((err, _req, res, _next) => {
  console.error('Erro não tratado:', err);
  res.status(500).json({ erro: 'Erro interno do servidor' });
});

app.listen(PORT, () => {
  console.log(`[LeilaoCommodities API] rodando na porta ${PORT}`);
});
SVREOF

# --------------------------------------------------------------
# 9. Criar static/js/api.js (frontend API client)
# --------------------------------------------------------------
info "Criando static/js/api.js"
cat > "$INSTALL_DIR/static/js/api.js" <<'APIEOF'
// --------------------------------------------------------------
// Cliente API — Leilão Commodities
// --------------------------------------------------------------
var API_BASE = '/api';

function getToken() { return localStorage.getItem('token'); }
function setToken(t) { localStorage.setItem('token', t); }
function clearToken() { localStorage.removeItem('token'); localStorage.removeItem('usuario'); }
function getUsuario() { return JSON.parse(localStorage.getItem('usuario') || 'null'); }
function setUsuario(u) { localStorage.setItem('usuario', JSON.stringify(u)); }

function api(method, path, body) {
  var opts = {
    method: method,
    headers: { 'Content-Type': 'application/json' },
  };
  var token = getToken();
  if (token) opts.headers['Authorization'] = 'Bearer ' + token;
  if (body && method !== 'GET') opts.body = JSON.stringify(body);
  return fetch(API_BASE + path, opts).then(function (r) {
    if (!r.ok) return r.json().then(function (e) { throw e; });
    return r.json();
  });
}

// ==================== AUTH ====================
function cadastrar() {
  var nome = document.getElementById('reg-nome');
  var email = document.getElementById('reg-email');
  var telefone = document.getElementById('reg-telefone');
  var senha = document.getElementById('reg-senha');
  var senha2 = document.getElementById('reg-senha2');
  var status = document.getElementById('register-status');
  if (!nome || !email || !senha || !senha2) return;
  if (senha.value !== senha2.value) { status.innerHTML = '<div class="alert alert-error">Senhas não conferem</div>'; return; }
  api('POST', '/auth/register', { nome: nome.value, email: email.value, telefone: telefone.value, senha: senha.value })
    .then(function (r) { setToken(r.token); setUsuario(r.usuario); window.location.href = 'index.html'; })
    .catch(function (e) { status.innerHTML = '<div class="alert alert-error">' + (e.erro || 'Erro ao cadastrar') + '</div>'; });
}

function entrar() {
  var email = document.getElementById('login-email');
  var senha = document.getElementById('login-senha');
  var status = document.getElementById('login-status');
  if (!email || !senha) return;
  api('POST', '/auth/login', { email: email.value, senha: senha.value })
    .then(function (r) { setToken(r.token); setUsuario(r.usuario); window.location.href = 'index.html'; })
    .catch(function (e) { status.innerHTML = '<div class="alert alert-error">' + (e.erro || 'Erro ao entrar') + '</div>'; });
}

function sair() { clearToken(); window.location.href = '../index.html'; }
function isAdmin() { var u = getUsuario(); return u && u.admin; }

// ==================== COMODITIES ====================
function carregarCotacoes() {
  var grid = document.getElementById('cotacoes-grid') || document.getElementById('cotacoes-list');
  if (!grid) return;
  grid.innerHTML = '<div class="loading">Carregando cotações...</div>';
  api('GET', '/comodities').then(function (dados) {
    grid.innerHTML = dados.map(function (c) { return (
      '<div class="cotacao-card">' +
        '<div class="header"><span class="nome">' + c.nome + ' <small>(' + c.sigla + ')</small></span>' +
        '<span class="variacao ' + (c.variacao >= 0 ? 'text-success' : 'text-danger') + '">' + (c.variacao >= 0 ? '+' : '') + c.variacao + '%</span></div>' +
        '<div class="preco">R$ ' + parseFloat(c.preco).toFixed(2) + '</div>' +
        '<div class="detalhes"><span>Atualizado: ' + new Date(c.updated_at).toLocaleString('pt-BR') + '</span></div>' +
      '</div>'
    ); }).join('');
  }).catch(function () { grid.innerHTML = '<div class="alert alert-error">Erro ao carregar cotações</div>'; });
}

// ==================== LEILOES ====================
function carregarLeiloes() {
  var lista = document.getElementById('lista-leiloes');
  if (!lista) return;
  lista.innerHTML = '<div class="loading">Carregando leilões...</div>';
  var params = '';
  var filtroC = document.getElementById('filtro-comoditie');
  var filtroS = document.getElementById('filtro-status');
  if (filtroC && filtroC.value) params += '&comoditie=' + filtroC.value;
  if (filtroS && filtroS.value) params += '&status=' + filtroS.value;
  api('GET', '/leiloes?' + params.slice(1)).then(function (dados) {
    if (!dados.length) { lista.innerHTML = '<p class="text-muted">Nenhum leilão encontrado</p>'; return; }
    lista.innerHTML = dados.map(function (l) {
      var encerrado = l.status !== 'ativo' || new Date(l.data_fim) < new Date();
      return (
        '<div class="card-leilao ' + (encerrado ? 'encerrado' : '') + '">' +
          '<div class="card-header">' +
            '<span class="tag">' + (l.comoditie_sigla || '') + '</span>' +
            '<span class="status ' + l.status + '">' + (encerrado ? 'Encerrado' : l.status) + '</span>' +
          '</div>' +
          '<h3>' + l.titulo + '</h3>' +
          '<p class="desc">' + (l.descricao || '') + '</p>' +
          '<div class="info-grid">' +
            '<div><small>Preço atual</small><strong>R$ ' + parseFloat(l.maior_lance || l.preco_inicial).toFixed(2) + '</strong></div>' +
            '<div><small>Lances</small><strong>' + l.total_lances + '</strong></div>' +
            '<div><small>Quantidade</small><strong>' + l.quantidade + '</strong></div>' +
            '<div><small>Término</small><strong>' + new Date(l.data_fim).toLocaleString('pt-BR') + '</strong></div>' +
          '</div>' +
          '<a href="leilao.html?id=' + l.id + '" class="btn btn-primary btn-sm">Ver Leilão</a>' +
        '</div>'
      );
    }).join('');
  }).catch(function () { lista.innerHTML = '<div class="alert alert-error">Erro ao carregar leilões</div>'; });
}

function carregarLeilao() {
  var container = document.getElementById('leilao-container');
  if (!container) return;
  var params = new URLSearchParams(window.location.search);
  var id = params.get('id');
  if (!id) { container.innerHTML = '<p class="alert alert-error">Leilão não informado</p>'; return; }
  container.innerHTML = '<div class="loading">Carregando leilão...</div>';
  api('GET', '/leiloes/' + id).then(function (dados) {
    var encerrado = dados.status !== 'ativo' || new Date(dados.data_fim) < new Date();
    var html =
      '<h1>' + dados.titulo + '</h1>' +
      '<p>' + (dados.descricao || '') + '</p>' +
      '<div class="info-grid">' +
        '<div><small>Commoditie</small><strong>' + dados.comoditie_nome + ' (' + dados.comoditie_sigla + ')</strong></div>' +
        '<div><small>Preço atual</small><strong>R$ ' + parseFloat(dados.maior_lance || dados.preco_inicial).toFixed(2) + '</strong></div>' +
        '<div><small>Lances</small><strong>' + dados.total_lances + '</strong></div>' +
        '<div><small>Quantidade</small><strong>' + dados.quantidade + '</strong></div>' +
        '<div><small>Valor mínimo lance</small><strong>' + (dados.valor_min_lance ? 'R$ ' + parseFloat(dados.valor_min_lance).toFixed(2) : '—') + '</strong></div>' +
        '<div><small>Término</small><strong>' + new Date(dados.data_fim).toLocaleString('pt-BR') + '</strong></div>' +
        '<div><small>Status</small><strong class="status-' + dados.status + '">' + (encerrado ? 'Encerrado' : dados.status) + '</strong></div>' +
      '</div>';
    if (!encerrado && getToken()) {
      html += '<button class="btn btn-primary" onclick="abrirModalLance()">Dar Lance</button>';
    }
    if (dados.lances && dados.lances.length) {
      html += '<h2 class="mt-lg">Histórico de Lances</h2><table class="table"><thead><tr><th>Usuário</th><th>Valor</th><th>Data</th></tr></thead><tbody>';
      dados.lances.forEach(function (l) {
        html += '<tr><td>' + (l.usuario_nome || '—') + '</td><td>R$ ' + parseFloat(l.valor).toFixed(2) + '</td><td>' + new Date(l.created_at).toLocaleString('pt-BR') + '</td></tr>';
      });
      html += '</tbody></table>';
    } else {
      html += '<p class="text-muted mt-lg">Nenhum lance ainda. Seja o primeiro!</p>';
    }
    container.innerHTML = html;
    window.dadosLeilao = dados;
    if (document.getElementById('modal-lance')) {
      document.getElementById('lance-valor').min = (parseFloat(dados.maior_lance || dados.preco_inicial) + 0.01);
    }
  }).catch(function () { container.innerHTML = '<div class="alert alert-error">Erro ao carregar leilão</div>'; });
}

var dadosLeilao = null;

function abrirModalLance() {
  var modal = document.getElementById('modal-lance');
  if (modal) modal.style.display = 'flex';
}

function fecharModal() {
  var modal = document.getElementById('modal-lance');
  if (modal) modal.style.display = 'none';
}

function confirmarLance() {
  var input = document.getElementById('lance-valor');
  var status = document.getElementById('lance-status');
  if (!input || !status || !dadosLeilao) return;
  api('POST', '/lances', { leilao_id: dadosLeilao.id, valor: parseFloat(input.value) })
    .then(function () { status.innerHTML = '<div class="alert alert-success">Lance registrado!</div>'; setTimeout(function () { fecharModal(); carregarLeilao(); }, 1000); })
    .catch(function (e) { status.innerHTML = '<div class="alert alert-error">' + (e.erro || 'Erro ao dar lance') + '</div>'; });
}

function filtrar() { carregarLeiloes(); }

// ==================== ADMIN ====================
function carregarLeiloesAdmin() {
  var lista = document.getElementById('leiloes-list') || document.getElementById('admin-leiloes');
  if (!lista) return;
  var ehAdmin = lista.id === 'admin-leiloes';
  lista.innerHTML = '<div class="loading">Carregando...</div>';
  api('GET', '/leiloes').then(function (dados) {
    if (!dados.length) { lista.innerHTML = '<p class="text-muted">Nenhum leilão encontrado</p>'; return; }
    lista.innerHTML = dados.map(function (l) {
      return (
        '<div class="card-leilao">' +
          '<div class="card-header">' +
            '<span class="tag">' + (l.comoditie_sigla || '') + '</span>' +
            '<span class="status ' + l.status + '">' + l.status + '</span>' +
          '</div>' +
          '<h3>' + l.titulo + '</h3>' +
          '<div class="info-grid">' +
            '<div><small>Preço</small><strong>R$ ' + parseFloat(l.preco_inicial).toFixed(2) + '</strong></div>' +
            '<div><small>Lances</small><strong>' + l.total_lances + '</strong></div>' +
            '<div><small>Término</small><strong>' + new Date(l.data_fim).toLocaleString('pt-BR') + '</strong></div>' +
          '</div>' +
          (ehAdmin ? '<div class="card-actions"><button class="btn btn-outline btn-sm" onclick="editarLeilao(' + l.id + ')">Editar</button><button class="btn btn-danger btn-sm" onclick="removerLeilao(' + l.id + ')">Remover</button></div>' : '') +
        '</div>'
      );
    }).join('');
  }).catch(function () { lista.innerHTML = '<div class="alert alert-error">Erro ao carregar</div>'; });
}

function abrirCriar() {
  var modal = document.getElementById('modal-leilao');
  if (!modal) return;
  document.getElementById('modal-title').textContent = 'Novo Leilão';
  ['l-titulo','l-descricao','l-comoditie','l-quantidade','l-preco','l-min-lance','l-data-fim'].forEach(function (id) {
    var el = document.getElementById(id);
    if (el) el.value = '';
  });
  document.getElementById('btn-salvar').dataset.id = '';
  carregarComboComodities();
  modal.style.display = 'flex';
}

function editarLeilao(id) {
  api('GET', '/leiloes/' + id).then(function (l) {
    var modal = document.getElementById('modal-leilao');
    if (!modal) return;
    document.getElementById('modal-title').textContent = 'Editar Leilão';
    document.getElementById('l-titulo').value = l.titulo || '';
    document.getElementById('l-descricao').value = l.descricao || '';
    document.getElementById('l-quantidade').value = l.quantidade || 1;
    document.getElementById('l-preco').value = l.preco_inicial || '';
    document.getElementById('l-min-lance').value = l.valor_min_lance || '';
    document.getElementById('l-data-fim').value = l.data_fim ? l.data_fim.slice(0,16) : '';
    document.getElementById('btn-salvar').dataset.id = l.id;
    carregarComboComodities(l.comoditie_id);
    modal.style.display = 'flex';
  }).catch(function () { alert('Erro ao carregar leilão'); });
}

function fechar() {
  var modal = document.getElementById('modal-leilao');
  if (modal) modal.style.display = 'none';
}

function salvar() {
  var id = document.getElementById('btn-salvar').dataset.id;
  var status = document.getElementById('status');
  var dados = {
    titulo: document.getElementById('l-titulo').value,
    descricao: document.getElementById('l-descricao').value,
    comoditie_id: parseInt(document.getElementById('l-comoditie').value),
    quantidade: parseFloat(document.getElementById('l-quantidade').value) || 1,
    preco_inicial: parseFloat(document.getElementById('l-preco').value),
    valor_min_lance: parseFloat(document.getElementById('l-min-lance').value) || null,
    data_fim: document.getElementById('l-data-fim').value,
  };
  if (!dados.titulo || !dados.comoditie_id || !dados.preco_inicial || !dados.data_fim) {
    if (status) status.innerHTML = '<div class="alert alert-error">Preencha todos os campos obrigatórios</div>'; return;
  }
  var req = id ? api('PUT', '/leiloes/' + id, dados) : api('POST', '/leiloes', dados);
  req.then(function () {
    if (status) status.innerHTML = '<div class="alert alert-success">Leilão salvo!</div>';
    setTimeout(function () { fechar(); carregarLeiloesAdmin(); }, 800);
  }).catch(function (e) {
    if (status) status.innerHTML = '<div class="alert alert-error">' + (e.erro || 'Erro ao salvar') + '</div>';
  });
}

function removerLeilao(id) {
  if (!confirm('Remover este leilão e todos os lances?')) return;
  api('DELETE', '/leiloes/' + id).then(function () { carregarLeiloesAdmin(); }).catch(function (e) { alert(e.erro || 'Erro ao remover'); });
}

function carregarComboComodities(selected) {
  var sel = document.getElementById('l-comoditie');
  if (!sel) return;
  api('GET', '/comodities').then(function (dados) {
    sel.innerHTML = dados.map(function (c) {
      return '<option value="' + c.id + '"' + (c.id === selected ? ' selected' : '') + '>' + c.nome + '</option>';
    }).join('');
  });
}

// ==================== USUARIOS (admin) ====================
function carregarUsuarios() {
  var lista = document.getElementById('usuarios-list');
  if (!lista) return;
  lista.innerHTML = '<div class="loading">Carregando...</div>';
  api('GET', '/usuarios').then(function (dados) {
    if (!dados.length) { lista.innerHTML = '<p class="text-muted">Nenhum usuário</p>'; return; }
    lista.innerHTML = '<table class="table"><thead><tr><th>Nome</th><th>Email</th><th>Telefone</th><th>Admin</th><th>Cadastro</th><th>Ações</th></tr></thead><tbody>' +
      dados.map(function (u) {
        return '<tr><td>' + u.nome + '</td><td>' + u.email + '</td><td>' + (u.telefone || '—') + '</td><td>' + (u.admin ? 'Sim' : 'Não') + '</td><td>' + new Date(u.created_at).toLocaleDateString('pt-BR') + '</td>' +
          '<td><button class="btn btn-danger btn-sm" onclick="removerUsuario(' + u.id + ')">Remover</button></td></tr>';
      }).join('') + '</tbody></table>';
  }).catch(function () { lista.innerHTML = '<div class="alert alert-error">Erro ao carregar</div>'; });
}

function removerUsuario(id) {
  if (!confirm('Remover este usuário?')) return;
  api('DELETE', '/usuarios/' + id).then(function () { carregarUsuarios(); }).catch(function (e) { alert(e.erro || 'Erro ao remover'); });
}

// ==================== LANCES ====================
function carregarMeusLances() {
  var container = document.getElementById('lances-container');
  if (!container) return;
  container.innerHTML = '<div class="loading">Carregando...</div>';
  api('GET', '/lances/meus').then(function (dados) {
    if (!dados.length) { container.innerHTML = '<p class="text-muted">Você ainda não deu lances</p>'; return; }
    container.innerHTML = '<table class="table"><thead><tr><th>Leilão</th><th>Commoditie</th><th>Valor</th><th>Data</th></tr></thead><tbody>' +
      dados.map(function (l) {
        return '<tr><td>' + l.leilao_titulo + '</td><td>' + l.comoditie_nome + '</td><td>R$ ' + parseFloat(l.valor).toFixed(2) + '</td><td>' + new Date(l.created_at).toLocaleString('pt-BR') + '</td></tr>';
      }).join('') + '</tbody></table>';
  }).catch(function () { container.innerHTML = '<div class="alert alert-error">Erro ao carregar lances</div>'; });
}

// ==================== DASHBOARD ====================
function carregarDashboard() {
  var stats = document.getElementById('stats');
  if (!stats) return;
  stats.innerHTML = '<div class="loading">Carregando...</div>';
  api('GET', '/dashboard').then(function (d) {
    stats.innerHTML =
      '<div class="stat-card"><h3>' + d.usuarios + '</h3><p>Usuários</p></div>' +
      '<div class="stat-card"><h3>' + d.leiloes_ativos + '</h3><p>Leilões Ativos</p></div>' +
      '<div class="stat-card"><h3>' + d.total_lances + '</h3><p>Total de Lances</p></div>' +
      '<div class="stat-card"><h3>' + d.comodities + '</h3><p>Commodities</p></div>';
  }).catch(function () { stats.innerHTML = '<div class="alert alert-error">Erro ao carregar dashboard</div>'; });
  carregarLeiloesAdmin();
}

// ==================== INIT ====================
document.addEventListener('DOMContentLoaded', function () {
  // Auto-init baseado na página
  if (document.getElementById('cotacoes-grid') || document.getElementById('cotacoes-list')) carregarCotacoes();
  if (document.getElementById('lista-leiloes')) carregarLeiloes();
  if (document.getElementById('leilao-container')) carregarLeilao();
  if (document.getElementById('lances-container')) carregarMeusLances();
  if (document.getElementById('stats')) carregarDashboard();
  if (document.getElementById('admin-leiloes')) carregarLeiloesAdmin();
  if (document.getElementById('leiloes-list')) carregarLeiloesAdmin();
  if (document.getElementById('usuarios-list')) carregarUsuarios();
  if (document.getElementById('filtro-comoditie')) {
    api('GET', '/comodities').then(function (dados) {
      var sel = document.getElementById('filtro-comoditie');
      if (sel) dados.forEach(function (c) { sel.innerHTML += '<option value="' + c.id + '">' + c.nome + '</option>'; });
    });
  }
});
APIEOF

# --------------------------------------------------------------
# 10. Criar ecosystem.config.js (PM2)
# --------------------------------------------------------------
info "Criando ecosystem.config.js"
cat > "$INSTALL_DIR/ecosystem.config.js" <<'PM2EOF'
module.exports = {
  apps: [{
    name: 'leilaocommodities',
    script: './api/src/server.js',
    cwd: '/var/www/leilaocommodities',
    instances: 1,
    autorestart: true,
    watch: false,
    max_memory_restart: '300M',
    env: {
      NODE_ENV: 'production',
    },
  }],
};
PM2EOF

# --------------------------------------------------------------
# 13. Configurar Nginx
# --------------------------------------------------------------
info "Configurando Nginx — adicionando location /api/"

if [ -f "$NGINX_CONF" ]; then
  # Verifica se o bloco leilaocommodities já existe
  if grep -q 'leilaocommodities' "$NGINX_CONF"; then
    warn "Bloco leilaocommodities já encontrado em $NGINX_CONF — pulando"
  else
    # Insere antes do último '}'
    sed -i '$i\
\
    # --------------------------------------------\
    # Leilao Commodities API (porta 3002)\
    # --------------------------------------------\
    location /api/ {\
        proxy_pass http://localhost:3002;\
        proxy_http_version 1.1;\
        proxy_set_header Upgrade $http_upgrade;\
        proxy_set_header Connection "upgrade";\
        proxy_set_header Host $host;\
        proxy_set_header X-Real-IP $remote_addr;\
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;\
        proxy_set_header X-Forwarded-Proto $scheme;\
        proxy_read_timeout 120s;\
        proxy_send_timeout 120s;\
    }\
' "$NGINX_CONF"
    info "Bloco /api/ inserido em $NGINX_CONF"
  fi
else
  warn "$NGINX_CONF não encontrado — criando arquivo"
  cat > "$NGINX_CONF" <<'NGINXEOF'
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;

    root /var/www/html;
    index index.html;

    # Leilao Commodities API
    location /api/ {
        proxy_pass http://localhost:3002;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 120s;
        proxy_send_timeout 120s;
    }

    location / {
        try_files $uri $uri/ =404;
    }
}
NGINXEOF
  info "Arquivo $NGINX_CONF criado"
fi

# --------------------------------------------------------------
# 11. Adicionar script api.js nas páginas HTML
# --------------------------------------------------------------
info "Injetando script api.js nas páginas HTML"
find "$INSTALL_DIR" -name '*.html' -type f | while read -r html; do
  # Insere api.js antes do ultimo </body> ou antes de </html>
  if grep -q 'components.js' "$html" && ! grep -q 'api.js' "$html"; then
    sed -i 's|<script src="\(.*\)components.js"></script>|<script src="\1components.js"></script>\n  <script src="\1api.js"></script>|' "$html"
    echo "    + $html"
  fi
done

# --------------------------------------------------------------
# 12. Instalar dependências npm
# --------------------------------------------------------------
info "Instalando dependências npm em $API_DIR"
npm install --prefix "$API_DIR" --production

# --------------------------------------------------------------
# 14. Migração do banco PostgreSQL
# --------------------------------------------------------------
info "Executando migração do banco de dados"
node "$SRC_DIR/migrate.js" && info "Migração concluída!" || warn "Migração falhou — verifique as credenciais do PostgreSQL"

# --------------------------------------------------------------
# 15. PM2 — registrar e salvar
# --------------------------------------------------------------
info "Registrando app no PM2"
pm2 start "$INSTALL_DIR/ecosystem.config.js" --env production && \
  pm2 save --force && \
  info "PM2: app registrado e salvo"

# --------------------------------------------------------------
# 16. Testar Nginx e recarregar
# --------------------------------------------------------------
info "Testando e recarregando Nginx"
nginx -t && systemctl reload nginx && info "Nginx recarregado com sucesso!" || warn "Falha no nginx — execute manualmente: sudo nginx -t && sudo systemctl reload nginx"

# --------------------------------------------------------------
# 17. Final
# --------------------------------------------------------------
echo ""
info "==========================================="
info " Instalação concluída!"
info "==========================================="
echo ""
echo "  API rodando em:  http://localhost:3002/api/ping"
echo "  Proxy Nginx:     http://SEU_IP/api/ping"
echo ""
echo "  Admin padrão:    admin@leilaocommodities.com.br"
echo "  Senha:           admin123"
echo ""
echo "  PM2:             pm2 list"
echo "  Logs:            pm2 logs leilaocommodities"
echo ""
echo "  .env:            $API_DIR/.env (ajuste DB_PASS e JWT_SECRET)"
echo ""
