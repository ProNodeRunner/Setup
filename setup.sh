#!/bin/bash

# Конфигурация
LOGO_URL="https://raw.githubusercontent.com/ProNodeRunner/Logo/main/Logo"
ORANGE='\033[0;33m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

show_menu() {
    clear
    echo -e "${ORANGE}"
    curl -sSf $LOGO_URL 2>/dev/null || echo -e "=== Server Management ==="
    echo -e "\n\n\n"
    echo " ༺ Управление сервером v2.0 ༻ "
    echo "▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔"
    echo "1) Установить новый сервер"
    echo "2) Проверить загрузку ресурсов"
    echo "3) Проверить ноды на сервере"
    echo "4) Перезагрузить сервер"
    echo "5) Удалить сервер"
    echo "6) Выход"
    echo -e "${NC}"
}

install_server() {  
    echo -e "${ORANGE}[*] Обновляем пакеты...${NC}"  
    sudo DEBIAN_FRONTEND=noninteractive apt update && sudo DEBIAN_FRONTEND=noninteractive apt upgrade -y  

    echo -e "${ORANGE}[*] Устанавливаем обновления ядра...${NC}"  
    sudo DEBIAN_FRONTEND=noninteractive apt install -y linux-generic  

    CURRENT_KERNEL=$(uname -r)  
    NEW_KERNEL=$(dpkg -l | grep linux-image | awk '{print $2}' | sort | tail -n 1 | sed 's/linux-image-//g')  

    if [[ "$CURRENT_KERNEL" != "$NEW_KERNEL" ]]; then  
        echo -e "${ORANGE}[!] Доступно новое ядро: $NEW_KERNEL${NC}"  
    else  
        echo -e "${GREEN}[✓] Ядро актуально: $CURRENT_KERNEL${NC}"  
    fi  

    echo -e "${ORANGE}[*] Перезапускаем службы...${NC}"  
    services=("dbus.service" "getty@tty1.service" "networkd-dispatcher.service" "systemd-logind.service" "systemd-manager" "unattended-upgrades.service" "user@0.service")  
    for service in "${services[@]}"; do  
        sudo systemctl restart "$service"  
    done  

    echo -e "${ORANGE}[*] Настраиваем machine-id...${NC}"  
    sudo rm /etc/machine-id  
    sudo systemd-machine-id-setup  

    echo -e "${ORANGE}[*] Устанавливаем компоненты...${NC}"  
    sudo DEBIAN_FRONTEND=noninteractive apt install -y nano file fail2ban screen  

    echo -e "${ORANGE}[*] Устанавливаем Prometheus...${NC}"  
    PROMETHEUS_VERSION="3.2.0"
    wget -q https://github.com/prometheus/prometheus/releases/download/v$PROMETHEUS_VERSION/prometheus-$PROMETHEUS_VERSION.darwin-amd64.tar.gz  
    tar -xf prometheus-$PROMETHEUS_VERSION.darwin-amd64.tar.gz  
    cd prometheus-$PROMETHEUS_VERSION.darwin-amd64 || return

    sudo mv prometheus promtool /usr/local/bin/  
    sudo mkdir -p /etc/prometheus  
    sudo mv prometheus.yml consoles/ console_libraries/ /etc/prometheus/  

    echo "[Unit]
Description=Prometheus
After=network.target

[Service]
User=root
ExecStart=/usr/local/bin/prometheus --config.file=/etc/prometheus/prometheus.yml --storage.tsdb.path=/var/lib/prometheus/data

[Install]
WantedBy=multi-user.target" | sudo tee /etc/systemd/system/prometheus.service >/dev/null

    sudo systemctl daemon-reload  
    sudo systemctl enable --now prometheus  

    echo -e "\n${GREEN}[✓] СЕРВЕР УСПЕШНО УСТАНОВЛЕН!${NC}\n"  
}  

check_resource_usage() {  
    echo -e "${ORANGE}=== Загрузка ресурсов ===${NC}"  
    CPU_LOAD=$(top -b -n1 | grep "Cpu" | awk '{print $2 + $4}')
    MEMORY_LOAD=$(free | grep Mem | awk '{printf "%.1f", $3/$2 * 100}')
    TRAFFIC=$(vnstat --oneline | awk -F';' '{print $2}') 

    echo -e "CPU: ${ORANGE}${CPU_LOAD}%${NC}"
    echo -e "RAM: ${ORANGE}${MEMORY_LOAD}%${NC}"
    echo -e "Трафик: ${ORANGE}${TRAFFIC}${NC}"
}  

check_nodes() {
    echo -e "${ORANGE}=== Анализ нод ===${NC}"
    
    echo -e "\n${ORANGE}[*] Сетевые подключения:${NC}"
    sudo ss -tulpn | grep -E '808[0-9]|809[0-9]' | awk '{print "Порт:", $5, "Процесс:", $7}'
    
    echo -e "\n${ORANGE}[*] Docker-контейнеры:${NC}"
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E '808[0-9]|809[0-9]'
    
    echo -e "\n${ORANGE}[*] Системные сервисы:${NC}"
    systemctl list-units --type=service | grep -E 'node|chain|testnet'
    
    echo -e "\n${GREEN}[✓] Проверка завершена${NC}"
}

reboot_server() {  
    echo -e "${ORANGE}[!] Инициирую перезагрузку...${NC}"  
    sudo reboot  
}  

remove_server() {  
    echo -e "${ORANGE}[!] Удаление сервера...${NC}"  
    sudo systemctl disable --now prometheus
    sudo rm -rf /etc/prometheus /var/lib/prometheus /usr/local/bin/prometheus*
    
    sudo apt remove -y nano file fail2ban 2>/dev/null
    sudo apt autoremove -y
    
    echo -e "\n${RED}[!] Сервер удален!${NC}\n"  
}  

while true; do  
    show_menu
    read -p "Выберите опцию [1-6]: " option
    
    case $option in  
        1) install_server ;;
        2) check_resource_usage ;;
        3) check_nodes ;;
        4) reboot_server ;;
        5) remove_server ;;
        6) 
            echo -e "${GREEN}Выход...${NC}"
            break ;;
        *) echo -e "${RED}Неверный выбор!${NC}" ;;
    esac
    
    read -p "Нажмите Enter чтобы продолжить..."
    clear
done
