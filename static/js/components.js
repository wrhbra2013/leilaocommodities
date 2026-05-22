function initComponents() {
  var ph = document.getElementById('header-placeholder');
  var pf = document.getElementById('footer-placeholder');
  if (!ph && !pf) return;
  var loaded = 0;
  function done() {
    loaded++;
    if (loaded === 2) {
      fixActiveNav();
      initMenu();
      updateNavAuth();
    }
  }
  if (ph) fetch('/static/partials/header.html').then(function(r){return r.text();}).then(function(h){ph.innerHTML=h;done();});
  else done();
  if (pf) fetch('/static/partials/footer.html').then(function(r){return r.text();}).then(function(f){pf.innerHTML=f;done();var y=document.getElementById('footer-year');if(y)y.textContent=new Date().getFullYear();});
  else done();
}

function fixActiveNav() {
  var path = window.location.pathname;
  document.querySelectorAll('.main-nav a[data-page]').forEach(function(a) {
    var page = a.getAttribute('data-page');
    if (page === 'home' && (path === '/' || path.endsWith('index.html'))) a.classList.add('active');
    else if (page !== 'home' && path.includes(page)) a.classList.add('active');
  });
}

function initMenu() {
  var toggle = document.getElementById('menu-toggle');
  var nav = document.getElementById('main-nav');
  if (toggle && nav) {
    toggle.addEventListener('change', function() {
      nav.classList.toggle('is-active', toggle.checked);
    });
  }
}

function updateNavAuth() {
  var token = localStorage.getItem('lcm_token');
  var elEntrar = document.getElementById('nav-entrar');
  var elSair = document.getElementById('nav-sair');
  var elLances = document.getElementById('nav-meus-lances');
  var elAdmin = document.getElementById('nav-admin');
  if (token) {
    if (elEntrar) elEntrar.style.display = 'none';
    if (elSair) elSair.style.display = '';
    if (elLances) elLances.style.display = '';
    var user = JSON.parse(localStorage.getItem('lcm_user') || '{}');
    if (elAdmin) elAdmin.style.display = user.nivel === 'admin' ? '' : 'none';
  } else {
    if (elEntrar) elEntrar.style.display = '';
    if (elSair) elSair.style.display = 'none';
    if (elLances) elLances.style.display = 'none';
    if (elAdmin) elAdmin.style.display = 'none';
  }
}

function logout() {
  localStorage.removeItem('lcm_token');
  localStorage.removeItem('lcm_user');
  window.location.href = '/';
}

document.addEventListener('DOMContentLoaded', initComponents);
