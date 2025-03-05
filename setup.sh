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
    local errors=()
    
    echo -e "${ORANGE}[*] Обновляем пакеты...${NC}"  
    if ! sudo DEBIAN_FRONTEND=noninteractive apt update && sudo DEBIAN_FRONTEND=noninteractive apt upgrade -y; then
        errors+=("Не удалось обновить пакеты")
    fi

    echo -e "${ORANGE}[*] Устанавливаем обновления ядра...${NC}"  
    if ! sudo DEBIAN_FRONTEND=noninteractive apt install -y linux-generic; then
        errors+=("Не удалось установить обновления ядра")
    fi

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
        if ! sudo systemctl restart "$service"; then
            errors+=("Не удалось перезапустить $service")
        fi
    done  

    echo -e "${ORANGE}[*] Настраиваем machine-id...${NC}"  
    if ! (sudo rm /etc/machine-id && sudo systemd-machine-id-setup); then
        errors+=("Ошибка настройки machine-id")
    fi

    echo -e "${ORANGE}[*] Устанавливаем компоненты...${NC}"  
    if ! sudo DEBIAN_FRONTEND=noninteractive apt install -y nano file fail2ban screen vnstat; then
        errors+=("Ошибка установки базовых компонентов")
    fi

    echo -e "${ORANGE}[*] Устанавливаем Prometheus...${NC}"  
    PROMETHEUS_VERSION="2.47.0"
    if ! wget -q https://github.com/prometheus/prometheus/releases/download/v$PROMETHEUS_VERSION/prometheus-$PROMETHEUS_VERSION.linux-amd64.tar.gz || 
       ! tar -xf prometheus-$PROMETHEUS_VERSION.linux-amd64.tar.gz || 
       ! cd prometheus-$PROMETHEUS_VERSION.linux-amd64; then
        errors+=("Ошибка загрузки/распаковки Prometheus")
    else
        sudo mv prometheus promtool /usr/local/bin/  
        sudo mkdir -p /etc/prometheus/consoles /etc/prometheus/console_libraries  
        sudo mv prometheus.yml /etc/prometheus/  
        [ -d consoles ] && sudo mv consoles/* /etc/prometheus/consoles/  
        [ -d console_libraries ] && sudo mv console_libraries/* /etc/prometheus/console_libraries/  

        echo "[Unit]
Description=Prometheus
After=network.target

[Service]
User=root
ExecStart=/usr/local/bin/prometheus --config.file=/etc/prometheus/prometheus.yml --storage.tsdb.path=/var/lib/prometheus/data

[Install]
WantedBy=multi-user.target" | sudo tee /etc/systemd/system/prometheus.service >/dev/null

        if ! sudo systemctl daemon-reload || ! sudo systemctl enable --now prometheus; then
            errors+=("Ошибка запуска Prometheus")
        fi
        
        if ! systemctl is-active --quiet prometheus; then
            errors+=("Prometheus не запущен")
        fi
        cd ..
    fi

    if [ ${#errors[@]} -eq 0 ]; then
        echo -e "\n${GREEN}[✓] СЕРВЕР УСПЕШНО УСТАНОВЛЕН!${NC}\n"
    else
        echo -e "\n${RED}[✗] СЕРВЕР УСТАНОВЛЕН НЕ ПОЛНОСТЬЮ!${NC}"
        echo -e "${ORANGE}Проблемные компоненты:${NC}"
        printf '• %s\n' "${errors[@]}"
        echo
    fi
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
    
    echo -e "\n${ORANGE}[*] Docker-контейнеры нод:${NC}"
    docker ps -a --filter "name=node" --format "table {{.Names}}\t{{.Status}}\t{{.Image}}" || echo "Ноды не найдены"
    
    echo -e "\n${ORANGE}[*] Проверка аппаратных параметров:${NC}"
    for volume in $(docker volume ls -q --filter "name=node"); do
        echo -e "${GREEN}Обнаружен volume: $volume${NC}"
        docker run --rm -v "$volume:/data" alpine sh -c '
            echo "CPU cores: $(cat /data/cpu_cores)"
            echo "RAM GB: $(cat /data/ram_gb)"
            echo "SSD GB: $(cat /data/ssd_gb)"
        ' 2>/dev/null || echo "Данные спуфинга не найдены"
    done
    
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
