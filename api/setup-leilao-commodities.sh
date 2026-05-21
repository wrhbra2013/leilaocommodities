#!/bin/bash

CONFIG_FILE="/var/www/.setup-api-config"
NGINX_MAIN_CONF="/etc/nginx/sites-available/main"
PROJECT_NAME="leilao-commodities"
PROJECT_DIR="/var/www/$PROJECT_NAME"
API_DIR="$PROJECT_DIR/api"
PORT=3001

save_config() {
    grep -q "^$PROJECT_NAME|" "$CONFIG_FILE" 2>/dev/null || echo "$PROJECT_NAME||$PORT|$PROJECT_NAME" >> "$CONFIG_FILE"
}

check_port() {
    local port=$1
    if lsof -Pi :$port -sTCP:LISTEN -t >/dev/null 2>&1; then
        echo "Porta $port já está em uso"
        return 1
    fi
    return 0
}

kill_port() {
    local port=$1
    local pids=$(lsof -Pi :$port -t 2>/dev/null || true)
    if [ -n "$pids" ]; then
        echo "Matando processos na porta $port: $pids"
        echo "$pids" | xargs -r sudo kill -9 2>/dev/null || true
        sleep 1
    fi
}

cleanup_pm2() {
    local name=$1
    sudo pm2 stop "$name" 2>/dev/null || true
    sudo pm2 delete "$name" 2>/dev/null || true
}

remove_location() {
    if [ -f "$NGINX_MAIN_CONF" ]; then
        echo "Removendo location /$PROJECT_NAME do Nginx..."
        sudo sed -i "/location \/$PROJECT_NAME/,/}/d" "$NGINX_MAIN_CONF"
    fi
}

install_base() {
    echo ""
    echo "--- INSTALAÇÃO BASE ---"

    echo "1. Atualizando pacotes..."
    sudo apt update && sudo apt upgrade -y

    echo "2. Instalando Node.js 20..."
    if ! command -v node &> /dev/null; then
        curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
        sudo apt install -y nodejs
    fi

    echo "3. Instalando Nginx..."
    if ! command -v nginx &> /dev/null; then
        sudo apt install -y nginx
    fi

    echo "4. Instalando PM2..."
    if ! command -v pm2 &> /dev/null; then
        sudo npm install -g pm2
    fi

    echo "5. Verificando instalações..."
    node -v
    nginx -v
    pm2 --version

    echo ""
    echo "Base instalada com sucesso!"
}

install_project() {
    echo ""
    echo "=============================================="
    echo "  INSTALAR LEILÃO COMMODITIES"
    echo "=============================================="

    if [ ! -d "$PROJECT_DIR" ]; then
        echo "Criando diretório $PROJECT_DIR..."
        sudo mkdir -p "$PROJECT_DIR"
    fi

    echo ""
    echo "--- Configuração de Porta ---"
    read -p "Porta [3001]: " PORT_USER
    PORT="${PORT_USER:-3001}"

    if ! check_port "$PORT"; then
        echo ""
        read -p "Deseja limpar a porta e continuar? (sim/não): " CLEAN_PORT
        if [ "$CLEAN_PORT" == "sim" ]; then
            kill_port "$PORT"
        else
            echo "Cancelado"
            return 1
        fi
    fi

    echo ""
    echo "--- Copiando arquivos do projeto ---"

    SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
    LOCAL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

    echo "Origem: $LOCAL_DIR"
    echo "Destino: $PROJECT_DIR"

    sudo rsync -av --exclude='node_modules' --exclude='.git' "$LOCAL_DIR/" "$PROJECT_DIR/"

    echo ""
    echo "--- Configuração da API Externa ---"

    read -p "URL da API externa [https://api.projetosdinamicos.com.br/leilao-commodities]: " EXTERNAL_API
    EXTERNAL_API="${EXTERNAL_API:-https://api.projetosdinamicos.com.br/leilao-commodities}"

    read -p "API Token (deixe em branco para gerar automático): " API_TOKEN
    if [ -z "$API_TOKEN" ]; then
        API_TOKEN=$(node -e "console.log(require('crypto').randomUUID())")
    fi

    echo ""
    echo "--- Instalando dependências ---"

    cd "$API_DIR"
    if [ -d "node_modules" ]; then
        echo "node_modules já existe, pulando npm install"
    else
        npm install
    fi

    echo ""
    echo "--- Configurando .env ---"

    sudo tee "$API_DIR/.env" > /dev/null <<EOF
EXTERNAL_API=$EXTERNAL_API
API_TOKEN=$API_TOKEN
PORT=$PORT
EOF

    echo ".env criado em $API_DIR/.env"

    echo ""
    echo "--- Configurando PM2 ---"

    cleanup_pm2 "$PROJECT_NAME"

    cd "$API_DIR"
    sudo pm2 start src/server.js --name "$PROJECT_NAME"
    sudo pm2 save

    SYSTEMD_SERVICE=$(sudo pm2 startup | tail -1)
    if [ -n "$SYSTEMD_SERVICE" ]; then
        echo "$SYSTEMD_SERVICE" | sudo bash 2>/dev/null || true
    fi

    echo ""
    echo "--- Configurando Nginx ---"

    read -p "Domínio/IP do servidor (ex: 201.54.22.122): " SERVER_NAME
    SERVER_NAME="${SERVER_NAME:-201.54.22.122}"

    local location_block="
    location /$PROJECT_NAME/ {
        proxy_pass http://127.0.0.1:$PORT/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_cache_bypass \$http_upgrade;
    }
"

    if [ -f "$NGINX_MAIN_CONF" ]; then
        if ! grep -q "location /$PROJECT_NAME/" "$NGINX_MAIN_CONF"; then
            sudo sed -i "s|server {|server {\n$location_block|" "$NGINX_MAIN_CONF"
            echo "Location /$PROJECT_NAME/ adicionado ao Nginx existente"
        else
            echo "Location /$PROJECT_NAME/ já existe no Nginx"
        fi
    else
        echo "Criando novo config Nginx..."
        sudo tee "$NGINX_MAIN_CONF" > /dev/null <<EOF
server {
    listen 80;
    server_name $SERVER_NAME;
$location_block
}
EOF
    fi

    sudo ln -sf "$NGINX_MAIN_CONF" /etc/nginx/sites-enabled/main 2>/dev/null || true
    sudo nginx -t && sudo systemctl reload nginx || echo "Erro no Nginx, verifique manualmente"

    save_config

    echo ""
    echo "--- Testando API ---"
    sleep 2
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:$PORT/ 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" != "000" ]; then
        echo "API respondendo na porta $PORT (HTTP $HTTP_CODE)"
    else
        echo "AVISO: API pode não estar respondendo. Verifique: pm2 logs $PROJECT_NAME"
    fi

    echo ""
    echo "=============================================="
    echo "  RESUMO"
    echo "=============================================="
    echo ""
    echo "Projeto: $PROJECT_NAME"
    echo "Diretório: $PROJECT_DIR"
    echo "API: $API_DIR"
    echo "Porta: $PORT"
    echo "URL: http://$SERVER_NAME/$PROJECT_NAME/"
    echo ""
    echo "Comandos úteis:"
    echo "  pm2 status                        - Ver status"
    echo "  pm2 logs $PROJECT_NAME            - Ver logs"
    echo "  pm2 restart $PROJECT_NAME         - Reiniciar"
    echo "  pm2 stop $PROJECT_NAME            - Parar"
    echo ""
    echo "=== Projeto instalado com sucesso! ==="
}

rollback_project() {
    echo ""
    echo "=============================================="
    echo "  REMOVER PROJETO"
    echo "=============================================="

    echo ""
    echo "ATENÇÃO: Isso irá remover:"
    echo "  - Diretório: $PROJECT_DIR"
    echo "  - Location Nginx: /$PROJECT_NAME/"
    echo "  - Processo PM2"
    echo ""
    read -p "Confirmar? (sim/não): " CONFIRM
    if [ "$CONFIRM" != "sim" ]; then
        echo "Cancelado"
        return 0
    fi

    echo "1. Parando PM2..."
    cleanup_pm2 "$PROJECT_NAME"

    echo "2. Removendo location Nginx..."
    remove_location

    echo "3. Liberando porta $PORT..."
    kill_port "$PORT"

    echo "4. Removendo diretório..."
    sudo rm -rf "$PROJECT_DIR"

    echo "5. Atualizando config..."
    if [ -f "$CONFIG_FILE" ]; then
        grep -v "^$PROJECT_NAME|" "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
    fi

    echo ""
    echo "=== Projeto removido! ==="
}

update_code() {
    echo ""
    echo "=============================================="
    echo "  ATUALIZAR CÓDIGO"
    echo "=============================================="

    SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
    LOCAL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

    echo "Origem: $LOCAL_DIR"
    echo "Destino: $PROJECT_DIR"

    read -p "Confirmar? (sim/não): " CONFIRM
    if [ "$CONFIRM" != "sim" ]; then
        echo "Cancelado"
        return 0
    fi

    sudo rsync -av --exclude='node_modules' --exclude='.git' --exclude='.env' "$LOCAL_DIR/" "$PROJECT_DIR/"
    echo ""
    echo "Código atualizado! Reinicie o PM2 para aplicar:"
    echo "  pm2 restart $PROJECT_NAME"
}

show_menu() {
    echo ""
    echo "=============================================="
    echo "  Setup Leilão Commodities"
    echo "=============================================="
    echo ""
    echo "Escolha uma opção:"
    echo "  1 - Instalar base (Node, Nginx, PM2)"
    echo "  2 - Instalar/Atualizar projeto completo"
    echo "  3 - Remover projeto"
    echo "  4 - Atualizar código (rsync)"
    echo "  5 - Sair"
    echo ""
    read -p "Opção: " OPTION

    case $OPTION in
        1) install_base ;;
        2) install_project ;;
        3) rollback_project ;;
        4) update_code ;;
        5) echo "Saindo..."; exit 0 ;;
        *) echo "Opção inválida" ;;
    esac
}

if [ "$1" == "install" ]; then
    install_base
elif [ "$1" == "setup" ]; then
    install_project
elif [ "$1" == "remove" ]; then
    rollback_project
elif [ "$1" == "update" ]; then
    update_code
else
    show_menu
fi
