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

  async handleResponse(r) {
    if (r.status === 401) {
      this.clearToken();
      const redirect = encodeURIComponent(window.location.pathname + window.location.search);
      window.location.href = '/admin/login.html?redirect=' + redirect;
      throw new Error('Sessão expirada');
    }
    return r.json();
  },

  async get(path) {
    const r = await fetch(this.baseUrl + path, { headers: this.headers() });
    return this.handleResponse(r);
  },

  async post(path, body) {
    const r = await fetch(this.baseUrl + path, { method: 'POST', headers: this.headers(), body: JSON.stringify(body) });
    return this.handleResponse(r);
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
  async criarLance(leilao_id, valor) { return this.post('/api/lances/criar', { leilao_id, valor }); },
  async getLances(leilao_id) { return this.get('/api/lances/' + leilao_id); },
  async meusLances() { return this.get('/api/meus-lances'); },

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
