/* Shared admin auction modal — elimina duplicação entre admin/index.html e admin/leiloes.html */

function initAdminModal(comods) {
  const sel = document.getElementById('l-comoditie');
  if (sel && comods) {
    sel.innerHTML = comods.map(c => '<option value="' + html(c.id) + '">' + html(c.icone) + ' ' + html(c.nome) + '</option>').join('');
    const fim = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000);
    const fimEl = document.getElementById('l-data-fim');
    if (fimEl) fimEl.value = fim.toISOString().slice(0, 16);
  }
}

let modalEditId = null;

function modalAbrirCriar() {
  modalEditId = null;
  document.getElementById('modal-leilao-title') && (document.getElementById('modal-leilao-title').textContent = 'Novo Leilão');
  document.getElementById('modal-title') && (document.getElementById('modal-title').textContent = 'Novo Leilão');
  const btn = document.getElementById('btn-salvar-leilao') || document.getElementById('btn-salvar');
  if (btn) btn.textContent = 'Criar Leilão';
  ['l-titulo', 'l-descricao', 'l-preco', 'l-min-lance'].forEach(id => { const el = document.getElementById(id); if (el) el.value = ''; });
  const q = document.getElementById('l-quantidade');
  if (q) q.value = '1';
  const fim = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000);
  const fimEl = document.getElementById('l-data-fim');
  if (fimEl) fimEl.value = fim.toISOString().slice(0, 16);
  const st = document.getElementById('leilao-status') || document.getElementById('status');
  if (st) st.innerHTML = '';
  const modal = document.getElementById('modal-leilao');
  if (modal) modal.classList.add('active');
}

async function modalEditar(id, onLoaded) {
  const l = await API.getLeilao(id);
  modalEditId = id;
  document.getElementById('modal-leilao-title') && (document.getElementById('modal-leilao-title').textContent = 'Editar Leilão');
  document.getElementById('modal-title') && (document.getElementById('modal-title').textContent = 'Editar Leilão');
  const btn = document.getElementById('btn-salvar-leilao') || document.getElementById('btn-salvar');
  if (btn) btn.textContent = 'Salvar';
  const titulo = document.getElementById('l-titulo');
  if (titulo) titulo.value = l.titulo;
  const desc = document.getElementById('l-descricao');
  if (desc) desc.value = l.descricao || '';
  const comod = document.getElementById('l-comoditie');
  if (comod) comod.value = l.comoditie_id;
  const qtd = document.getElementById('l-quantidade');
  if (qtd) qtd.value = l.quantidade;
  const preco = document.getElementById('l-preco');
  if (preco) preco.value = l.preco_inicial;
  const minLance = document.getElementById('l-min-lance');
  if (minLance) minLance.value = l.valor_minimo_lance || '';
  const dataFim = document.getElementById('l-data-fim');
  if (dataFim) dataFim.value = new Date(l.data_fim).toISOString().slice(0, 16);
  const st = document.getElementById('leilao-status') || document.getElementById('status');
  if (st) st.innerHTML = '';
  document.getElementById('modal-leilao').classList.add('active');
  if (onLoaded) onLoaded(l);
}

async function modalSalvar(onSuccess) {
  const titulo = document.getElementById('l-titulo');
  const comod = document.getElementById('l-comoditie');
  const preco = document.getElementById('l-preco');
  const data = {
    titulo: titulo ? titulo.value.trim() : '',
    descricao: (document.getElementById('l-descricao') || {}).value || '',
    comoditie_id: comod ? comod.value : '',
    quantidade: parseFloat(document.getElementById('l-quantidade')?.value) || 1,
    preco_inicial: parseFloat(preco ? preco.value : 0),
    valor_minimo_lance: parseFloat(document.getElementById('l-min-lance')?.value) || null,
    data_fim: new Date(document.getElementById('l-data-fim')?.value).toISOString(),
  };
  const st = document.getElementById('leilao-status') || document.getElementById('status');
  if (!data.titulo || !data.comoditie_id || !data.preco_inicial) {
    if (st) st.innerHTML = '<div class="alert alert-error">Preencha título, commodity e preço</div>';
    return;
  }
  const r = modalEditId ? await API.updateLeilao({ ...data, id: modalEditId }) : await API.criarLeilao(data);
  if (r.success) {
    if (st) st.innerHTML = '<div class="alert alert-success">Leilão salvo!</div>';
    setTimeout(() => { modalFechar(); if (onSuccess) onSuccess(); }, 500);
  } else {
    if (st) st.innerHTML = '<div class="alert alert-error">' + (r.error || 'Erro') + '</div>';
  }
}

async function modalEncerrar(id) {
  if (!confirm('Tem certeza que deseja encerrar este leilão?')) return;
  const r = await API.updateLeilao({ id, status: 'encerrado' });
  return r.success;
}

function modalFechar() {
  const modal = document.getElementById('modal-leilao');
  if (modal) modal.classList.remove('active');
}
