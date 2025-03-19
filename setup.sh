#!/bin/bash

LOGO_URL="https://raw.githubusercontent.com/ProNodeRunner/Logo/main/Logo"
ORANGE='\033[0;33m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'
NODE_DIR="light-node"
MERKLE_DIR="risc0-merkle-service"
SERVICE_USER=$(whoami)
INSTALL_DIR=$(pwd)

show_logo() {
    echo -e "${ORANGE}"
    curl -sSf $LOGO_URL 2>/dev/null || echo "=== LAYEREDGE NODE MANAGER ==="
    echo -e "${NC}"
}

check_dependencies() {
    echo -e "${ORANGE}[1/7] Проверка зависимостей...${NC}"
    sudo DEBIAN_FRONTEND=noninteractive apt-get update -yq
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -yq git curl build-essential
}

install_go() {
    if ! command -v go &>/dev/null; then
        echo -e "${ORANGE}[2/7] Установка Go 1.18...${NC}"
        sudo add-apt-repository -y ppa:longsleep/golang-backports
        sudo DEBIAN_FRONTEND=noninteractive apt-get install -yq golang-1.18
        echo 'export PATH=$PATH:/usr/lib/go-1.18/bin' >> ~/.bashrc
        source ~/.bashrc
    fi
}

install_rust() {
    if ! command -v cargo &>/dev/null; then
        echo -e "${ORANGE}[3/7] Установка Rust...${NC}"
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
        source "$HOME/.cargo/env"
        rustup default 1.81.0 -y
    fi
}

install_risc0() {
    if ! command -v rzup &>/dev/null; then
        echo -e "${ORANGE}[4/7] Установка Risc0...${NC}"
        curl -L https://risczero.com/install | bash
        source "$HOME/.cargo/env"
        rzup install --force
    fi
}

setup_systemd() {
    echo -e "${ORANGE}[5/7] Настройка systemd...${NC}"
    
    sudo tee /etc/systemd/system/merkle.service >/dev/null <<EOL
[Unit]
Description=LayerEdge Merkle Service
After=network.target

[Service]
User=$SERVICE_USER
WorkingDirectory=$INSTALL_DIR/$NODE_DIR/$MERKLE_DIR
ExecStart=$(which cargo) run --release
Restart=always
RestartSec=10s

[Install]
WantedBy=multi-user.target
EOL

    sudo tee /etc/systemd/system/layeredge-node.service >/dev/null <<EOL
[Unit]
Description=LayerEdge Light Node
After=merkle.service

[Service]
User=$SERVICE_USER
WorkingDirectory=$INSTALL_DIR/$NODE_DIR
ExecStart=$INSTALL_DIR/$NODE_DIR/layeredge-node
Restart=always
RestartSec=10s

[Install]
WantedBy=multi-user.target
EOL

    sudo systemctl daemon-reload
    sudo systemctl enable merkle.service layeredge-node.service
}

build_project() {
    echo -e "${ORANGE}[6/7] Сборка проекта...${NC}"
    
    cd $INSTALL_DIR/$NODE_DIR/$MERKLE_DIR
    cargo build --release || {
        echo -e "${RED}Ошибка сборки Merkle-сервиса!${NC}"
        exit 1
    }
    
    cd $INSTALL_DIR/$NODE_DIR
    go build -o layeredge-node || {
        echo -e "${RED}Ошибка сборки Light Node!${NC}"
        exit 1
    }
}

start_services() {
    echo -e "${ORANGE}[7/7] Запуск сервисов...${NC}"
    sudo systemctl restart merkle.service layeredge-node.service
}

node_status() {
    echo -e "\n${ORANGE}=== СТАТУС СЕРВИСОВ ===${NC}"
    systemctl status merkle.service layeredge-node.service --no-pager -l
}

show_logs() {
    echo -e "\n${ORANGE}=== ЛОГИ MERCKLE ===${NC}"
    journalctl -u merkle.service -n 10 --no-pager --no-hostname
    
    echo -e "\n${ORANGE}=== ЛОГИ НОДЫ ===${NC}"
    journalctl -u layeredge-node.service -n 10 --no-pager --no-hostname
}

delete_node() {
    echo -e "${RED}Удаление ноды...${NC}"
    sudo systemctl stop merkle.service layeredge-node.service
    sudo systemctl disable merkle.service layeredge-node.service
    sudo rm -f /etc/systemd/system/{merkle,layeredge-node}.service
    sudo rm -rf $INSTALL_DIR/$NODE_DIR
    echo -e "${GREEN}Нода удалена!${NC}"
}

install_node() {
    check_dependencies
    install_go
    install_rust
    install_risc0

    echo -e "${ORANGE}Клонирование репозитория...${NC}"
    [ ! -d "$NODE_DIR" ] && git clone https://github.com/Layer-Edge/light-node.git || cd $NODE_DIR
    
    read -p "Введите приватный ключ: " PRIVATE_KEY
    cat > $NODE_DIR/.env <<EOL
GRPC_URL=34.31.74.109:9090
CONTRACT_ADDR=cosmos1ufs3tlq4umljk0qfe8k5ya0x6hpavn897u2cnf9k0en9jr7qarqqt56709
ZK_PROVER_URL=http://127.0.0.1:3001
API_REQUEST_TIMEOUT=100
POINTS_API=http://127.0.0.1:8080
PRIVATE_KEY='$PRIVATE_KEY'
EOL

    build_project
    setup_systemd
    start_services
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
