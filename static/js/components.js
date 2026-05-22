document.addEventListener('DOMContentLoaded', function() {
  var bp = typeof basePath !== 'undefined' ? basePath : '';

  var headerHtml = '<header class="header">' +
    '<div class="header-container">' +
    '<a href="' + bp + 'index.html" class="header-logo" aria-label="Leilao Commodities">' +
    '<span class="logo-leilao">Leilao</span><span class="logo-commodities">COMMODITIES</span></a>' +
    '<input type="checkbox" id="menu-toggle" class="menu-checkbox">' +
    '<label for="menu-toggle" class="sandwich-button" aria-label="Menu">' +
    '<span></span><span></span><span></span></label>' +
    '<nav class="main-nav" id="main-nav"><ul>' +
    '<li><a href="' + bp + 'index.html" data-page="home">Home</a></li>' +
    '<li><a href="' + bp + 'paginas/comodities.html" data-page="comodities">Cotações</a></li>' +
    '<li><a href="' + bp + 'paginas/leiloes.html" data-page="leiloes">Leilões</a></li>' +
    '<li id="nav-meus-lances" style="display:none"><a href="' + bp + 'paginas/meus-lances.html" data-page="meus-lances">Meus Lances</a></li>' +
    '<li id="nav-admin" style="display:none"><a href="' + bp + 'admin/index.html" data-page="admin">Admin</a></li>' +
    '<li id="nav-entrar"><a href="' + bp + 'admin/login.html" data-page="login">Entrar</a></li>' +
    '<li id="nav-sair" style="display:none"><a href="#" onclick="logout()" class="nav-sair">Sair</a></li>' +
    '</ul></nav></div></header>';

  var footerHtml = '<footer class="footer">' +
    '<p>&copy; ' + new Date().getFullYear() + ' Leilao Commodities. Todos os direitos reservados.</p></footer>';

  var ph = document.getElementById('header-placeholder');
  var pf = document.getElementById('footer-placeholder');
  if (ph) ph.innerHTML = headerHtml;
  if (pf) pf.innerHTML = footerHtml;
  fixActiveNav();
  initMenu();
  updateNavAuth();
});

function fixActiveNav() {
  var path = window.location.pathname;
  var page = path.split('/').pop().replace('.html','') || 'index';
  document.querySelectorAll('.main-nav a[data-page]').forEach(function(a) {
    if (a.getAttribute('data-page') === page) a.classList.add('active');
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
  window.location.href = (typeof basePath !== 'undefined' ? basePath : '') + 'index.html';
}
