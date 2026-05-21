function initComponents() {
  const html = `<header class="header">
    <div class="header-container">
      <a href="/" class="header-title">📊 Leilão Commodities</a>
      <input type="checkbox" id="menu-toggle" class="menu-checkbox">
      <label for="menu-toggle" class="sandwich-button" aria-label="Menu">
        <span></span><span></span><span></span>
      </label>
      <nav class="main-nav" id="main-nav">
        <ul>
          <li><a href="/" class="${isActive('/')}">Home</a></li>
          <li><a href="/paginas/comodities.html" class="${isActive('comodities')}">Cotações</a></li>
          <li><a href="/paginas/leiloes.html" class="${isActive('leiloes')}">Leilões</a></li>
          ${API.token ? `<li><a href="/paginas/meus-lances.html" class="${isActive('meus-lances')}">Meus Lances</a></li>` : ''}
          ${API.token ? `<li><a href="/admin/index.html" class="${isActive('admin')}">Admin</a></li>` : ''}
          ${API.token ? `<li><a href="#" onclick="logout()" style="color:#fbbf24;">Sair</a></li>`
            : `<li><a href="/admin/login.html" class="${isActive('login')}">Entrar</a></li>`}
        </ul>
      </nav>
    </div>
  </header>
  <footer class="footer">
    <p>&copy; ${new Date().getFullYear()} Leilap Commodities. Todos os direitos reservados.</p>
  </footer>`;
  document.getElementById('header-placeholder').innerHTML = html;
  document.getElementById('footer-placeholder').innerHTML = '';
  initMenu();
}

function isActive(page) {
  const p = window.location.pathname;
  return p.includes(page) ? 'active' : '';
}

function initMenu() {
  const toggle = document.getElementById('menu-toggle');
  const nav = document.getElementById('main-nav');
  if (toggle && nav) {
    toggle.addEventListener('change', () => nav.classList.toggle('is-active', toggle.checked));
  }
}

function logout() {
  API.clearToken();
  window.location.href = '/';
}

document.addEventListener('DOMContentLoaded', initComponents);
