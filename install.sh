#!/usr/bin/env bash
set -euo pipefail

# ==============================================================
# Script de instalação — Leilão Commodities API
# Uso: sudo bash install.sh
#
# API REST de persistência de dados via PostgreSQL.
# Projetado para servir páginas estáticas hospedadas em
# qualquer servidor (configurável via CORS).
#
# URL final:  https://api.projetosdinamicos.com.br/leilaocommodities/(crud)
# Proxy:      /leilaocommodities/ -> localhost:3002/api/
# Porta app:  3002
# ==============================================================

INSTALL_DIR="/var/www/leilaocommodities"
API_DIR="$INSTALL_DIR/api"
SRC_DIR="$API_DIR/src"
ROUTES_DIR="$SRC_DIR/routes"
MIDDLEWARE_DIR="$SRC_DIR/middleware"
NGINX_AVAILABLE="/etc/nginx/sites-available"
NGINX_CONF="$NGINX_AVAILABLE/default"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERRO]${NC} $1"; exit 1; }

[[ $EUID -eq 0 ]] || error "Execute como root: sudo bash install.sh"
command -v node  >/dev/null 2>&1 || error "Node.js não encontrado"
command -v npm   >/dev/null 2>&1 || error "npm não encontrado"
command -v psql  >/dev/null 2>&1 || warn "psql não encontrado — PostgreSQL pode não estar instalado"
command -v pm2   >/dev/null 2>&1 || warn "pm2 não encontrado — será instalado via npm"

mkdir -p "$ROUTES_DIR" "$MIDDLEWARE_DIR"

# --------------------------------------------------------------
# .env
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
CORS_ORIGIN=*           # ex: https://pages.projetosdinamicos.com.br
ENVEOF

chmod 600 "$API_DIR/.env"

# --------------------------------------------------------------
# package.json
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
# src/database.js
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
# src/migrate.js
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

  // seed comodities
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

  // seed admin
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
# src/middleware/auth.js
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
# routes/
# --------------------------------------------------------------

# auth.js
info "Criando routes/auth.js"
cat > "$ROUTES_DIR/auth.js" <<'RTAEOF'
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
    console.error(err);
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
    console.error(err);
    res.status(500).json({ erro: 'Erro interno do servidor' });
  }
});

module.exports = router;
RTAEOF

# usuarios.js
info "Criando routes/usuarios.js"
cat > "$ROUTES_DIR/usuarios.js" <<'USREOF'
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
USREOF

# comodities.js
info "Criando routes/comodities.js"
cat > "$ROUTES_DIR/comodities.js" <<'CMDEOF'
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
CMDEOF

# leiloes.js
info "Criando routes/leiloes.js"
cat > "$ROUTES_DIR/leiloes.js" <<'LLEOT'
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
LLEOT

# lances.js
info "Criando routes/lances.js"
cat > "$ROUTES_DIR/lances.js" <<'LANCT'
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
LANCT

# dashboard.js
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
# src/server.js
# --------------------------------------------------------------
info "Criando src/server.js"
cat > "$SRC_DIR/server.js" <<'SVREOF'
require('dotenv').config({ path: require('path').join(__dirname, '..', '.env') });

const express = require('express');
const cors = require('cors');

const app = express();
const PORT = process.env.PORT || 3002;

// CORS — permite requisições de origens externas
app.use(cors({
  origin: process.env.CORS_ORIGIN || '*',
  methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization'],
  credentials: true,
}));

app.use(express.json());

app.use('/api/auth',       require('./routes/auth'));
app.use('/api/usuarios',   require('./routes/usuarios'));
app.use('/api/comodities', require('./routes/comodities'));
app.use('/api/leiloes',    require('./routes/leiloes'));
app.use('/api/lances',     require('./routes/lances'));
app.use('/api/dashboard',  require('./routes/dashboard'));

app.get('/api/ping', (_req, res) => res.json({ ok: true, time: new Date().toISOString() }));

app.use((_req, res) => res.status(404).json({ erro: 'Rota não encontrada' }));

app.use((err, _req, res, _next) => {
  console.error('Erro não tratado:', err);
  res.status(500).json({ erro: 'Erro interno do servidor' });
});

app.listen(PORT, () => {
  console.log(`[LeilaoCommodities API] rodando na porta ${PORT}`);
});
SVREOF

# --------------------------------------------------------------
# ecosystem.config.js (PM2)
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
# Nginx — insere location /api/ -> localhost:3002
# --------------------------------------------------------------
info "Configurando Nginx — adicionando location /api/"

if [ -f "$NGINX_CONF" ]; then
  if grep -q '# leilaocommodities' "$NGINX_CONF"; then
    warn "Bloco leilaocommodities já encontrado em $NGINX_CONF — pulando"
  else
    sed -i '$i\
\
    # leilaocommodities — https://api.projetosdinamicos.com.br/leilaocommodities/\
    location /leilaocommodities/ {\
        proxy_pass http://localhost:3002/api/;\
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
    info "Location /leilaocommodities/ inserido em $NGINX_CONF"
  fi
else
  warn "$NGINX_CONF não encontrado — criando arquivo"
  cat > "$NGINX_CONF" <<'NGINXEOF'
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name api.projetosdinamicos.com.br;

    # leilaocommodities
    location /leilaocommodities/ {
        proxy_pass http://localhost:3002/api/;
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
}
NGINXEOF
  info "Arquivo $NGINX_CONF criado (server_name api.projetosdinamicos.com.br)"
fi

# --------------------------------------------------------------
# Instalar dependências
# --------------------------------------------------------------
info "Instalando dependências npm em $API_DIR"
npm install --prefix "$API_DIR" --production

# --------------------------------------------------------------
# Migração PostgreSQL
# --------------------------------------------------------------
info "Executando migração do banco de dados"
node "$SRC_DIR/migrate.js" && info "Migração concluída!" || warn "Migração falhou — verifique as credenciais do PostgreSQL"

# --------------------------------------------------------------
# PM2
# --------------------------------------------------------------
info "Registrando app no PM2"
pm2 start "$INSTALL_DIR/ecosystem.config.js" --env production && \
  pm2 save --force && \
  info "PM2: app registrado e salvo"

# --------------------------------------------------------------
# Nginx reload
# --------------------------------------------------------------
info "Testando e recarregando Nginx"
nginx -t && systemctl reload nginx && info "Nginx recarregado com sucesso!" || warn "Falha no nginx — execute manualmente: sudo nginx -t && sudo systemctl reload nginx"

# --------------------------------------------------------------
# Final
# --------------------------------------------------------------
echo ""
info "==========================================="
info " Instalação concluída!"
info "==========================================="
echo ""
echo "  URL base:  https://api.projetosdinamicos.com.br/leilaocommodities/"
echo "  Exemplos:"
echo "    GET  /leilaocommodities/ping"
echo "    GET  /leilaocommodities/leiloes"
echo "    POST /leilaocommodities/auth/login"
echo ""
echo "  Interno:   localhost:3002/api/ (proxy Nginx)"
echo ""
echo "  CORS:     configure CORS_ORIGIN em $API_DIR/.env"
echo "            com o domínio do seu frontend estático"
echo ""
echo "  Admin padrão:"
echo "    email: admin@leilaocommodities.com.br"
echo "    senha: admin123"
echo ""
echo "  PM2:  pm2 list | pm2 logs leilaocommodities"
echo ""
