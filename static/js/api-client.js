const API = {
  baseUrl: '',
  token: null,

  setToken(t) { this.token = t; localStorage.setItem('lcm_token', t); },
  loadToken() { this.token = localStorage.getItem('lcm_token'); return this.token; },
  clearToken() { this.token = null; localStorage.removeItem('lcm_token'); localStorage.removeItem('lcm_user'); },

  headers() {
    const h = { 'Content-Type': 'application/json' };
    if (this.token) h['Authorization'] = 'Bearer ' + this.token;
    return h;
  },

  async get(path) {
    const r = await fetch(this.baseUrl + path, { headers: this.headers() });
    return r.json();
  },

  async post(path, body) {
    const r = await fetch(this.baseUrl + path, { method: 'POST', headers: this.headers(), body: JSON.stringify(body) });
    return r.json();
  },

  // Auth
  async login(email, senha) { return this.post('/api/login', { email, senha }); },
  async register(nome, email, telefone, senha) { return this.post('/api/register', { nome, email, telefone, senha }); },

  // Commodities
  async getComodities() { return this.get('/api/comodities'); },
  async getComoditie(slug) { return this.get('/api/comodities/' + slug); },

  // Leiloes
  async listLeiloes(filters) { return this.post('/api/leiloes/read', filters); },
  async getLeilao(id) { return this.get('/api/leiloes/' + id); },

  // Lances
  async criarLance(leilao_id, usuario_id, valor) { return this.post('/api/lances/criar', { leilao_id, usuario_id, valor }); },
  async getLances(leilao_id) { return this.get('/api/lances/' + leilao_id); },

  // Admin
  async criarLeilao(data) { return this.post('/api/admin/leiloes/criar', data); },
  async updateLeilao(data) { return this.post('/api/admin/leiloes/update', data); },
  async adminLeiloes() { return this.post('/api/admin/leiloes'); },
  async adminUsuarios() { return this.post('/api/admin/usuarios'); },

  // Cotacoes
  async getCotacoes(slugs) { return this.get('/api/cotacoes?comodities=' + (slugs || '')); },
};

API.loadToken();
window.API = API;
