var API_BASE = 'https://api.projetosdinamicos.com.br/leilaocommodities';

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
  if (body) opts.body = JSON.stringify(body);
  return fetch(API_BASE + path, opts).then(function (r) {
    if (!r.ok) return r.json().then(function (e) { throw e; });
    return r.json();
  });
}

function cadastrar() {
  var nome = document.getElementById('reg-nome');
  var email = document.getElementById('reg-email');
  var telefone = document.getElementById('reg-telefone');
  var senha = document.getElementById('reg-senha');
  var senha2 = document.getElementById('reg-senha2');
  var status = document.getElementById('register-status');
  if (!nome || !email || !senha || !senha2) return;
  if (senha.value !== senha2.value) { status.innerHTML = '<div class="alert alert-error">Senhas n\u00e3o conferem</div>'; return; }
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
    .then(function (r) { setToken(r.token); setUsuario(r.usuario); window.location.href = '../admin/index.html'; })
    .catch(function (e) { status.innerHTML = '<div class="alert alert-error">' + (e.erro || 'Erro ao entrar') + '</div>'; });
}

function sair() { clearToken(); window.location.href = '../index.html'; }
function isAdmin() { var u = getUsuario(); return u && u.admin; }

function carregarCotacoes() {
  var grid = document.getElementById('cotacoes-grid');
  if (!grid) return;
  api('GET', '/comodities').then(function (dados) {
    grid.innerHTML = dados.map(function (c) { return (
      '<div class="commodity-card">' +
        '<div class="nome">' + c.nome + ' <small>(' + c.sigla + ')</small></div>' +
        '<div class="preco">R$ ' + parseFloat(c.preco).toFixed(2) + '</div>' +
        '<div class="variacao ' + (c.variacao >= 0 ? 'positiva' : 'negativa') + '">' + (c.variacao >= 0 ? '+' : '') + c.variacao + '%</div>' +
      '</div>'
    ); }).join('');
  }).catch(function () { grid.innerHTML = '<div class="loading">Erro ao carregar cota\u00e7\u00f5es</div>'; });
}

function carregarCotacoesLista() {
  var lista = document.getElementById('cotacoes-list');
  if (!lista) return;
  var statusEl = document.getElementById('status-cotacao');
  api('GET', '/comodities').then(function (dados) {
    lista.innerHTML = dados.map(function (c) { return (
      '<div class="cotacao-card">' +
        '<div class="header"><span class="nome">' + c.nome + ' <small>(' + c.sigla + ')</small></span>' +
        '<span class="' + (c.variacao >= 0 ? 'text-success' : 'text-danger') + '">' + (c.variacao >= 0 ? '+' : '') + c.variacao + '%</span></div>' +
        '<div class="preco">R$ ' + parseFloat(c.preco).toFixed(2) + '</div>' +
        '<div class="detalhes"><span>Atualizado: ' + new Date(c.updated_at).toLocaleString('pt-BR') + '</span></div>' +
      '</div>'
    ); }).join('');
    if (statusEl) { statusEl.classList.add('d-none'); }
  }).catch(function () { lista.innerHTML = '<div class="alert alert-error">Erro ao carregar cota\u00e7\u00f5es</div>'; });
}

function carregarLeiloes() {
  var lista = document.getElementById('lista-leiloes');
  if (!lista) return;
  var params = '';
  var fc = document.getElementById('filtro-comoditie');
  var fs = document.getElementById('filtro-status');
  if (fc && fc.value) params += '&comoditie=' + fc.value;
  if (fs && fs.value) params += '&status=' + fs.value;
  api('GET', '/leiloes' + (params ? '?' + params.slice(1) : '')).then(function (dados) {
    if (!dados.length) { lista.innerHTML = '<p class="text-muted">Nenhum leil\u00e3o encontrado</p>'; return; }
    lista.innerHTML = dados.map(function (l) {
      return (
        '<div class="card">' +
          '<div class="card-body">' +
            '<div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:0.5rem">' +
              '<span class="tag">' + (l.comoditie_sigla || '') + '</span>' +
              '<span style="font-size:0.8rem;font-weight:600;color:' + (l.status === 'ativo' ? 'var(--color-success)' : 'var(--color-error)') + '">' + l.status + '</span>' +
            '</div>' +
            '<h3>' + l.titulo + '</h3>' +
            '<div class="preco">R$ ' + parseFloat(l.maior_lance || l.preco_inicial).toFixed(2) + '</div>' +
            '<div class="meta">' + l.total_lances + ' lances &middot; ' + new Date(l.data_fim).toLocaleString('pt-BR') + '</div>' +
            '<a href="leilao.html?id=' + l.id + '" class="btn btn-primary btn-sm" style="margin-top:0.75rem">Ver Leil\u00e3o</a>' +
          '</div>' +
        '</div>'
      );
    }).join('');
  }).catch(function () { lista.innerHTML = '<div class="alert alert-error">Erro ao carregar leil\u00f5es</div>'; });
}

function carregarLeiloesDestaque() {
  var grid = document.getElementById('leiloes-destaque');
  if (!grid) return;
  var bp = typeof basePath !== 'undefined' ? basePath : '';
  api('GET', '/leiloes?status=ativo').then(function (dados) {
    if (!dados.length) { grid.innerHTML = '<p class="text-muted">Nenhum leil\u00e3o ativo no momento</p>'; return; }
    grid.innerHTML = dados.slice(0, 6).map(function (l) {
      return (
        '<div class="card">' +
          '<div class="card-body">' +
            '<div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:0.5rem">' +
              '<span class="tag tag-ativo">' + (l.comoditie_sigla || '') + '</span>' +
              '<span style="font-size:0.8rem;font-weight:600;color:var(--color-success)">ativo</span>' +
            '</div>' +
            '<h3>' + l.titulo + '</h3>' +
            '<div class="preco">R$ ' + parseFloat(l.maior_lance || l.preco_inicial).toFixed(2) + '</div>' +
            '<div class="meta">' + l.total_lances + ' lances &middot; ' + new Date(l.data_fim).toLocaleString('pt-BR') + '</div>' +
            '<a href="' + bp + 'paginas/leilao.html?id=' + l.id + '" class="btn btn-primary btn-sm" style="margin-top:0.75rem">Ver Leil\u00e3o</a>' +
          '</div>' +
        '</div>'
      );
    }).join('');
  }).catch(function () { grid.innerHTML = '<div class="alert alert-error">Erro ao carregar leil\u00f5es</div>'; });
}

function carregarLeilao() {
  var container = document.getElementById('leilao-container');
  if (!container) return;
  var id = new URLSearchParams(window.location.search).get('id');
  if (!id) { container.innerHTML = '<p class="alert alert-error">Leil\u00e3o n\u00e3o informado</p>'; return; }
  api('GET', '/leiloes/' + id).then(function (d) {
    var encerrado = d.status !== 'ativo';
    var html =
      '<div class="leilao-header">' +
        '<h1>' + d.titulo + '</h1>' +
        '<div class="preco-atual">R$ ' + parseFloat(d.maior_lance || d.preco_inicial).toFixed(2) + '</div>' +
        '<div class="timer">' + (encerrado ? 'Encerrado' : 'Status: ' + d.status) + '</div>' +
      '</div>' +
      '<div class="leilao-info-grid">' +
        '<div><strong>Commoditie</strong><br>' + d.comoditie_nome + ' (' + d.comoditie_sigla + ')</div>' +
        '<div><strong>Quantidade</strong><br>' + d.quantidade + '</div>' +
        '<div><strong>Pre\u00e7o inicial</strong><br>R$ ' + parseFloat(d.preco_inicial).toFixed(2) + '</div>' +
        '<div><strong>Valor m\u00ednimo lance</strong><br>' + (d.valor_min_lance ? 'R$ ' + parseFloat(d.valor_min_lance).toFixed(2) : '—') + '</div>' +
        '<div><strong>Total de lances</strong><br>' + d.total_lances + '</div>' +
        '<div><strong>T\u00e9rmino</strong><br>' + new Date(d.data_fim).toLocaleString('pt-BR') + '</div>' +
        '<div><strong>Descri\u00e7\u00e3o</strong><br>' + (d.descricao || '—') + '</div>' +
      '</div>';
    if (!encerrado && getToken()) {
      html += '<button class="btn btn-primary" onclick="abrirModalLance()">Dar Lance</button>';
    }
    html += '<h2 style="margin-top:2rem;margin-bottom:1rem">Hist\u00f3rico de Lances</h2>';
    if (d.lances && d.lances.length) {
      html += '<table><thead><tr><th>Usu\u00e1rio</th><th>Valor</th><th>Data</th></tr></thead><tbody>';
      d.lances.forEach(function (l) {
        html += '<tr><td>' + (l.usuario_nome || '—') + '</td><td>R$ ' + parseFloat(l.valor).toFixed(2) + '</td><td>' + new Date(l.created_at).toLocaleString('pt-BR') + '</td></tr>';
      });
      html += '</tbody></table>';
    } else {
      html += '<p class="text-muted">Nenhum lance ainda. Seja o primeiro!</p>';
    }
    container.innerHTML = html;
    window._leilaoAtual = d;
  }).catch(function () { container.innerHTML = '<div class="alert alert-error">Erro ao carregar leil\u00e3o</div>'; });
}

var _leilaoAtual = null;

function abrirModalLance() {
  var m = document.getElementById('modal-lance');
  if (m) m.style.display = 'flex';
}
function fecharModal() {
  var m = document.getElementById('modal-lance');
  if (m) m.style.display = 'none';
}

function confirmarLance() {
  var input = document.getElementById('lance-valor');
  var status = document.getElementById('lance-status');
  if (!input || !status || !_leilaoAtual) return;
  api('POST', '/lances', { leilao_id: _leilaoAtual.id, valor: parseFloat(input.value) })
    .then(function () {
      status.innerHTML = '<div class="alert alert-success">Lance registrado!</div>';
      setTimeout(function () { fecharModal(); carregarLeilao(); }, 1000);
    })
    .catch(function (e) { status.innerHTML = '<div class="alert alert-error">' + (e.erro || 'Erro ao dar lance') + '</div>'; });
}

function filtrar() { carregarLeiloes(); }

/* Admin */

function carregarDashboard() {
  var stats = document.getElementById('stats');
  if (!stats) return;
  api('GET', '/dashboard').then(function (d) {
    stats.innerHTML =
      '<div class="stat-card"><div class="numero">' + d.usuarios + '</div><div class="rotulo">Usu\u00e1rios</div></div>' +
      '<div class="stat-card"><div class="numero">' + d.leiloes_ativos + '</div><div class="rotulo">Leil\u00f5es Ativos</div></div>' +
      '<div class="stat-card"><div class="numero">' + d.total_lances + '</div><div class="rotulo">Total de Lances</div></div>' +
      '<div class="stat-card"><div class="numero">' + d.comodities + '</div><div class="rotulo">Commodities</div></div>';
    carregarAdminLeiloes('admin-leiloes');
  }).catch(function () { stats.innerHTML = '<div class="alert alert-error">Erro ao carregar dashboard</div>'; });
}

function carregarAdminLeiloes(containerId) {
  var lista = document.getElementById(containerId);
  if (!lista) return;
  api('GET', '/leiloes').then(function (dados) {
    if (!dados.length) { lista.innerHTML = '<p class="text-muted">Nenhum leil\u00e3o</p>'; return; }
    lista.innerHTML = dados.map(function (l) {
      return (
        '<div class="card">' +
          '<div class="card-body">' +
            '<div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:0.5rem">' +
              '<span class="tag">' + (l.comoditie_sigla || '') + '</span>' +
              '<span class="tag tag-' + l.status + '">' + l.status + '</span>' +
            '</div>' +
            '<h3>' + l.titulo + '</h3>' +
            '<div class="meta">R$ ' + parseFloat(l.preco_inicial).toFixed(2) + ' &middot; ' + l.total_lances + ' lances &middot; ' + new Date(l.data_fim).toLocaleString('pt-BR') + '</div>' +
            '<div style="margin-top:0.5rem;display:flex;gap:0.5rem">' +
              '<button class="btn btn-outline btn-xs" onclick="editarLeilao(' + l.id + ')">Editar</button>' +
              '<button class="btn btn-danger btn-xs" onclick="removerLeilao(' + l.id + ')">Remover</button>' +
            '</div>' +
          '</div>' +
        '</div>'
      );
    }).join('');
  }).catch(function () { lista.innerHTML = '<div class="alert alert-error">Erro ao carregar</div>'; });
}

function carregarLeiloesAdmin() { carregarAdminLeiloes('leiloes-list'); }

function abrirCriar() {
  var m = document.getElementById('modal-leilao');
  if (!m) return;
  document.getElementById('modal-title').textContent = 'Novo Leil\u00e3o';
  ['l-titulo','l-descricao','l-comoditie','l-quantidade','l-preco','l-min-lance','l-data-fim'].forEach(function (id) {
    var el = document.getElementById(id);
    if (el) el.value = '';
  });
  document.getElementById('btn-salvar').dataset.id = '';
  carregarComboComodities();
  m.style.display = 'flex';
}

function abrirCriarLeilao() {
  var m = document.getElementById('modal-leilao');
  if (!m) return;
  document.getElementById('modal-leilao-title').textContent = 'Novo Leil\u00e3o';
  ['l-titulo','l-descricao','l-comoditie','l-quantidade','l-preco','l-min-lance','l-data-fim'].forEach(function (id) {
    var el = document.getElementById(id);
    if (el) el.value = '';
  });
  document.getElementById('btn-salvar-leilao').dataset.id = '';
  carregarComboComodities();
  m.style.display = 'flex';
}

function editarLeilao(id) {
  api('GET', '/leiloes/' + id).then(function (l) {
    var m = document.getElementById('modal-leilao');
    if (!m) return;
    var titleEl = document.getElementById('modal-title') || document.getElementById('modal-leilao-title');
    if (titleEl) titleEl.textContent = 'Editar Leil\u00e3o';
    var el = document.getElementById('l-titulo'); if (el) el.value = l.titulo || '';
    var el = document.getElementById('l-descricao'); if (el) el.value = l.descricao || '';
    var el = document.getElementById('l-quantidade'); if (el) el.value = l.quantidade || 1;
    var el = document.getElementById('l-preco'); if (el) el.value = l.preco_inicial || '';
    var el = document.getElementById('l-min-lance'); if (el) el.value = l.valor_min_lance || '';
    var el = document.getElementById('l-data-fim'); if (el) el.value = l.data_fim ? l.data_fim.slice(0, 16) : '';
    carregarComboComodities(l.comoditie_id);
    var btn = document.getElementById('btn-salvar') || document.getElementById('btn-salvar-leilao');
    if (btn) btn.dataset.id = l.id;
    m.style.display = 'flex';
  }).catch(function () { alert('Erro ao carregar leil\u00e3o'); });
}

function fechar() {
  var m = document.getElementById('modal-leilao');
  if (m) m.style.display = 'none';
}

function salvar() {
  var btn = document.getElementById('btn-salvar') || document.getElementById('btn-salvar-leilao');
  var id = btn ? btn.dataset.id : '';
  var statusEl = document.getElementById('status') || document.getElementById('leilao-status');
  var dados = {
    titulo: (document.getElementById('l-titulo') || {}).value,
    descricao: (document.getElementById('l-descricao') || {}).value,
    comoditie_id: parseInt((document.getElementById('l-comoditie') || {}).value),
    quantidade: parseFloat((document.getElementById('l-quantidade') || {}).value) || 1,
    preco_inicial: parseFloat((document.getElementById('l-preco') || {}).value),
    valor_min_lance: parseFloat((document.getElementById('l-min-lance') || {}).value) || null,
    data_fim: (document.getElementById('l-data-fim') || {}).value,
  };
  if (!dados.titulo || !dados.comoditie_id || !dados.preco_inicial || !dados.data_fim) {
    if (statusEl) statusEl.innerHTML = '<div class="alert alert-error">Preencha todos os campos obrigat\u00f3rios</div>';
    return;
  }
  var req = id ? api('PUT', '/leiloes/' + id, dados) : api('POST', '/leiloes', dados);
  req.then(function () {
    if (statusEl) statusEl.innerHTML = '<div class="alert alert-success">Leil\u00e3o salvo!</div>';
    setTimeout(function () { fechar(); var f = carregarLeiloesAdmin || carregarAdminLeiloes; if (f) f('admin-leiloes'); }, 800);
  }).catch(function (e) {
    if (statusEl) statusEl.innerHTML = '<div class="alert alert-error">' + (e.erro || 'Erro ao salvar') + '</div>';
  });
}

function salvarLeilao() { salvar(); }

function removerLeilao(id) {
  if (!confirm('Remover este leil\u00e3o e todos os lances?')) return;
  api('DELETE', '/leiloes/' + id).then(function () {
    carregarLeiloesAdmin();
    carregarAdminLeiloes('admin-leiloes');
  }).catch(function (e) { alert(e.erro || 'Erro ao remover'); });
}

function carregarComboComodities(selected) {
  var sel = document.getElementById('l-comoditie');
  if (!sel) return;
  api('GET', '/comodities').then(function (dados) {
    sel.innerHTML = '<option value="">Selecione...</option>' + dados.map(function (c) {
      return '<option value="' + c.id + '"' + (c.id === selected ? ' selected' : '') + '>' + c.nome + '</option>';
    }).join('');
  });
}

/* Usuarios admin */

function carregarUsuarios() {
  var lista = document.getElementById('usuarios-list');
  if (!lista) return;
  api('GET', '/usuarios').then(function (dados) {
    if (!dados.length) { lista.innerHTML = '<p class="text-muted">Nenhum usu\u00e1rio</p>'; return; }
    lista.innerHTML =
      '<table><thead><tr><th>Nome</th><th>Email</th><th>Telefone</th><th>Admin</th><th>Cadastro</th><th>A\u00e7\u00f5es</th></tr></thead><tbody>' +
      dados.map(function (u) {
        return '<tr><td>' + u.nome + '</td><td>' + u.email + '</td><td>' + (u.telefone || '—') + '</td><td>' + (u.admin ? 'Sim' : 'N\u00e3o') + '</td><td>' + new Date(u.created_at).toLocaleDateString('pt-BR') + '</td>' +
          '<td><button class="btn btn-danger btn-xs" onclick="removerUsuario(' + u.id + ')">Remover</button></td></tr>';
      }).join('') + '</tbody></table>';
  }).catch(function () { lista.innerHTML = '<div class="alert alert-error">Erro ao carregar</div>'; });
}

function removerUsuario(id) {
  if (!confirm('Remover este usu\u00e1rio?')) return;
  api('DELETE', '/usuarios/' + id).then(function () { carregarUsuarios(); }).catch(function (e) { alert(e.erro || 'Erro ao remover'); });
}

/* Lances */

function carregarMeusLances() {
  var c = document.getElementById('lances-container');
  if (!c) return;
  api('GET', '/lances/meus').then(function (dados) {
    if (!dados.length) { c.innerHTML = '<p class="text-muted">Voc\u00ea ainda n\u00e3o deu lances</p>'; return; }
    c.innerHTML = '<table><thead><tr><th>Leil\u00e3o</th><th>Commoditie</th><th>Valor</th><th>Data</th></tr></thead><tbody>' +
      dados.map(function (l) {
        return '<tr><td>' + l.leilao_titulo + '</td><td>' + l.comoditie_nome + '</td><td>R$ ' + parseFloat(l.valor).toFixed(2) + '</td><td>' + new Date(l.created_at).toLocaleString('pt-BR') + '</td></tr>';
      }).join('') + '</tbody></table>';
  }).catch(function () { c.innerHTML = '<div class="alert alert-error">Erro ao carregar lances</div>'; });
}

/* Init */

document.addEventListener('DOMContentLoaded', function () {
  if (document.getElementById('cotacoes-grid')) carregarCotacoes();
  if (document.getElementById('cotacoes-list')) carregarCotacoesLista();
  if (document.getElementById('leiloes-destaque')) carregarLeiloesDestaque();
  if (document.getElementById('lista-leiloes')) carregarLeiloes();
  if (document.getElementById('leilao-container')) carregarLeilao();
  if (document.getElementById('lances-container')) carregarMeusLances();
  if (document.getElementById('stats')) carregarDashboard();
  if (document.getElementById('admin-leiloes')) carregarAdminLeiloes('admin-leiloes');
  if (document.getElementById('leiloes-list')) carregarLeiloesAdmin();
  if (document.getElementById('usuarios-list')) carregarUsuarios();

  var filtroC = document.getElementById('filtro-comoditie');
  if (filtroC) {
    api('GET', '/comodities').then(function (dados) {
      dados.forEach(function (c) { filtroC.innerHTML += '<option value="' + c.id + '">' + c.nome + '</option>'; });
    });
  }
});
