#!/bin/bash

# Конфигурация
LOGO_URL="https://raw.githubusercontent.com/ProNodeRunner/Logo/main/Logo"
ORANGE='\033[0;33m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'
NODE_DIR="light-node"
MERKLE_DIR="risc0-merkle-service"
SERVICE_USER=$(whoami)

show_logo() {
    echo -e "${ORANGE}"
    curl -sSf $LOGO_URL 2>/dev/null || echo "=== LAYEREDGE NODE MANAGER ==="
    echo -e "${NC}"
}

check_dependencies() {
    # Проверка и установка недостающих пакетов
    local missing=()
    for pkg in git curl build-essential; do
        ! dpkg -l | grep -q $pkg && missing+=($pkg)
    done
    
    [ ${#missing[@]} -gt 0 ] && {
        echo -e "${ORANGE}Установка системных пакетов: ${missing[@]}${NC}"
        sudo DEBIAN_FRONTEND=noninteractive apt-get install -yq "${missing[@]}"
    }

    # Обновление ядра
    current_kernel=$(uname -r)
    latest_kernel=$(apt list --installed | grep linux-image-generic | awk -F' ' '{print $2}')
    [ "$current_kernel" != "$latest_kernel" ] && {
        echo -e "${ORANGE}Обновление ядра до $latest_kernel${NC}"
        sudo DEBIAN_FRONTEND=noninteractive apt-get install -yq linux-image-generic
        sudo apt-get -yq autoremove
    }
}

install_go() {
    ! command -v go &>/dev/null && {
        echo -e "${ORANGE}Установка Go 1.18...${NC}"
        sudo add-apt-repository -y ppa:longsleep/golang-backports
        sudo DEBIAN_FRONTEND=noninteractive apt-get install -yq golang-1.18
        echo 'export PATH=$PATH:/usr/lib/go-1.18/bin' >> ~/.bashrc
        source ~/.bashrc
    }
}

install_rust() {
    ! command -v cargo &>/dev/null && {
        echo -e "${ORANGE}Установка Rust...${NC}"
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
        source "$HOME/.cargo/env"
        rustup default 1.81.0 -y
    }
}

install_risc0() {
    ! command -v rzup &>/dev/null && {
        echo -e "${ORANGE}Установка Risc0...${NC}"
        curl -L https://risczero.com/install | bash
        source "$HOME/.cargo/env"
        rzup install
    }
}

setup_systemd() {
    echo -e "${ORANGE}Настройка systemd сервисов...${NC}"
    
    # Merkle Service
    sudo tee /etc/systemd/system/merkle.service >/dev/null <<EOL
[Unit]
Description=LayerEdge Merkle Service
After=network.target

[Service]
User=$SERVICE_USER
WorkingDirectory=$(pwd)/$MERKLE_DIR
ExecStart=$(which cargo) run --release
Restart=always
RestartSec=10s

[Install]
WantedBy=multi-user.target
EOL

    # Node Service
    sudo tee /etc/systemd/system/layeredge-node.service >/dev/null <<EOL
[Unit]
Description=LayerEdge Light Node
After=merkle.service

[Service]
User=$SERVICE_USER
WorkingDirectory=$(pwd)
ExecStart=$(pwd)/layeredge-node
Restart=always
RestartSec=10s

[Install]
WantedBy=multi-user.target
EOL

    sudo systemctl daemon-reload
    sudo systemctl enable merkle.service layeredge-node.service
}

start_services() {
    echo -e "${ORANGE}Запуск сервисов...${NC}"
    sudo systemctl restart merkle.service layeredge-node.service
}

node_status() {
    echo -e "\n${ORANGE}=== СТАТУС СЕРВИСОВ ===${NC}"
    systemctl status merkle.service layeredge-node.service --no-pager -l
}

show_logs() {
    echo -e "\n${ORANGE}=== ЛОГИ MERCKLE ===${NC}"
    journalctl -u merkle.service -n 10 --no-pager
    
    echo -e "\n${ORANGE}=== ЛОГИ НОДЫ ===${NC}"
    journalctl -u layeredge-node.service -n 10 --no-pager
}

delete_node() {
    echo -e "${RED}Удаление ноды...${NC}"
    sudo systemctl stop merkle.service layeredge-node.service
    sudo systemctl disable merkle.service layeredge-node.service
    sudo rm -f /etc/systemd/system/merkle.service /etc/systemd/system/layeredge-node.service
    rm -rf $NODE_DIR
}

show_menu() {
    clear
    show_logo
    echo -e "${ORANGE}1. Установить ноду"
    echo -e "2. Показать статус"
    echo -e "3. Показать логи"
    echo -e "4. Перезапустить сервисы"
    echo -e "5. Удалить ноду"
    echo -e "6. Выход${NC}"
}

install_node() {
    check_dependencies
    install_go
    install_rust
    install_risc0
    
    echo -e "${ORANGE}Клонирование репозитория...${NC}"
    [ ! -d "$NODE_DIR" ] && git clone https://github.com/Layer-Edge/light-node.git
    cd $NODE_DIR || exit 1

    read -p "Введите приватный ключ кошелька: " PRIVATE_KEY
    cat > .env <<EOL
GRPC_URL=34.31.74.109:9090
CONTRACT_ADDR=cosmos1ufs3tlq4umljk0qfe8k5ya0x6hpavn897u2cnf9k0en9jr7qarqqt56709
ZK_PROVER_URL=http://127.0.0.1:3001
API_REQUEST_TIMEOUT=100
POINTS_API=http://127.0.0.1:8080
PRIVATE_KEY='$PRIVATE_KEY'
EOL

    echo -e "${GREEN}Сборка проекта...${NC}"
    cd $MERKLE_DIR && cargo build --release
    cd ../ && go build -o layeredge-node
    
    setup_systemd
    start_services
}

while true; do
    show_menu
    read -p "Выберите действие: " choice

    case $choice in
        1) install_node ;;
        2) node_status ;;
        3) show_logs ;;
        4) start_services ;;
        5) delete_node ;;
        6) exit 0 ;;
        *) echo -e "${RED}Неверный выбор!${NC}" ;;
    esac
    
    read -p $'\nНажмите Enter чтобы продолжить...'
done
