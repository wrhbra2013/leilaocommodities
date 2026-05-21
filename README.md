# Leilão Commodities

Plataforma web de negociações agrícolas por leilão.

## Arquitetura

```
Browser (HTML/CSS/JS vanilla)
    ↕ HTTP
Fastify Server (BFF — Backend for Frontend, porta 3001)
    ↕ HTTP (POST, Authorization: Bearer API_TOKEN)
API REST Externa (PostgreSQL, VM separada)
```

O servidor Node.js atua como **BFF (Backend for Frontend)**: serve os arquivos estáticos e faz proxy das operações para uma API REST externa que detém o banco de dados.

## Stack

| Layer        | Tecnologia                     |
|-------------|--------------------------------|
| Backend      | Node.js + Fastify              |
| Frontend     | HTML5 + CSS3 + JavaScript Vanilla |
| Database     | PostgreSQL (via API externa)   |
| Auth         | JWT + bcrypt (externo)         |
| Deploy       | PM2 + Nginx                    |

## Requisitos

- Node.js 18+
- NPM
- Acesso à API REST externa

## Setup Local

```bash
cd api
cp .env.example .env
# Edite .env com as credenciais da API externa
npm install
npm run dev
```

O servidor inicia em `http://localhost:3001`.

## Variáveis de Ambiente

| Variável       | Descrição                          | Obrigatório |
|---------------|-----------------------------------|-------------|
| `EXTERNAL_API` | URL da API REST externa           | Sim         |
| `API_TOKEN`    | Token de autenticação com a API   | Sim         |
| `JWT_SECRET`   | Chave secreta para assinar JWTs   | Sim         |
| `PORT`         | Porta do servidor (default: 3001) | Não         |

## Scripts

| Comando      | Descrição                    |
|-------------|------------------------------|
| `npm start` | Inicia em produção           |
| `npm run dev` | Inicia com hot-reload      |

## Deploy em Produção

O script `api/setup-leilao-commodities.sh` automatiza o deploy:

```bash
# Instalar dependências base (Node, Nginx, PM2)
sudo bash setup-leilao-commodities.sh install

# Instalar/configurar o projeto
sudo bash setup-leilao-commodities.sh setup

# Atualizar código
sudo bash setup-leilao-commodities.sh update

# Remover projeto
sudo bash setup-leilao-commodities.sh remove
```

O projeto é instalado em `/var/www/leilao-commodities/` com PM2 e proxy reverso Nginx.

## Endpoints da API

| Método | Rota                        | Autenticação     | Descrição               |
|--------|-----------------------------|------------------|------------------------|
| POST   | `/api/login`                | Pública          | Login do usuário       |
| POST   | `/api/register`             | Pública          | Cadastro               |
| GET    | `/api/health`               | Pública          | Health check           |
| GET    | `/api/comodities`           | Pública          | Lista commodities      |
| GET    | `/api/comodities/:slug`     | Pública          | Detalhe commodity      |
| POST   | `/api/leiloes/read`         | Pública          | Lista leilões          |
| GET    | `/api/leiloes/:id`          | Pública          | Detalhe leilão         |
| POST   | `/api/lances/criar`         | JWT              | Registrar lance        |
| GET    | `/api/lances/:leilao_id`    | Pública          | Lances do leilão       |
| POST   | `/api/admin/leiloes/criar`  | JWT + Admin      | Criar leilão           |
| POST   | `/api/admin/leiloes/update` | JWT + Admin      | Atualizar leilão       |
| POST   | `/api/admin/leiloes`        | JWT + Admin      | Listar todos leilões   |
| POST   | `/api/admin/usuarios`       | JWT + Admin      | Listar usuários        |
| GET    | `/api/cotacoes`             | Pública          | Cotações mock          |

## Estrutura do Projeto

```
├── api/                        # Backend (Node.js + Fastify)
│   ├── src/
│   │   ├── server.js           # Entry point (orquestrador)
│   │   ├── lib/
│   │   │   ├── api-client.js   # Cliente para API externa
│   │   │   └── auth.js         # JWT sign/verify + middleware
│   │   └── routes/
│   │       ├── auth.js         # Login/register
│   │       ├── commodities.js  # CRUD commodities
│   │       ├── leiloes.js      # Leilões públicos
│   │       ├── lances.js       # Lances (com auth)
│   │       ├── admin.js        # Admin (com auth + role)
│   │       ├── cotacoes.js     # Mock de cotações
│   │       └── health.js       # Health check
│   ├── .env                    # Variáveis de ambiente
│   └── setup-leilao-commodities.sh  # Script de deploy
├── static/                     # Assets estáticos
│   ├── css/style.css           # Estilos modernos com design tokens
│   └── js/
│       ├── api-client.js       # HTTP client
│       ├── helpers.js          # Utilitários (html escape, $el)
│       └── components.js       # Header/footer/nav
├── admin/                      # Painel admin
│   ├── index.html              # Dashboard
│   ├── leiloes.html            # Gerenciar leilões
│   ├── usuarios.html           # Gerenciar usuários
│   ├── login.html              # Login
│   └── register.html           # Cadastro
├── paginas/                    # Páginas públicas
│   ├── comodities.html         # Cotações
│   ├── leilao.html             # Detalhe do leilão
│   ├── leiloes.html            # Lista de leilões
│   └── meus-lances.html        # Lances do usuário
└── index.html                  # Landing page
```
