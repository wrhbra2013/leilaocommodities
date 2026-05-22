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
    '</ul></nav></div></header>';

  var footerHtml = '<footer class="footer">' +
    '<p>&copy; ' + new Date().getFullYear() + ' Leilao Commodities. Todos os direitos reservados.</p></footer>';

  var ph = document.getElementById('header-placeholder');
  var pf = document.getElementById('footer-placeholder');
  if (ph) ph.innerHTML = headerHtml;
  if (pf) pf.innerHTML = footerHtml;
  fixActiveNav();
  initMenu();
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
