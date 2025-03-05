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
    services=(
        "dbus.service"
        "networkd-dispatcher.service"
        "systemd-logind.service"
        "unattended-upgrades.service"
    )

    for service in "${services[@]}"; do
        if systemctl list-unit-files | grep -q "^${service}"; then
            if ! sudo systemctl restart "$service"; then
                errors+=("Не удалось перезапустить $service")
            fi
        else
            echo -e "${ORANGE}[!] Служба $service не найдена, пропускаем${NC}"
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
    PROMETHEUS_VERSION="3.2.1"
    PROMETHEUS_FILE="prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz"

    # Удаляем старые файлы
    sudo rm -rf prometheus-*

    # Скачивание
    echo -e "${ORANGE}• Скачиваем ${PROMETHEUS_FILE}...${NC}"
    if ! wget -q "https://github.com/prometheus/prometheus/releases/download/v${PROMETHEUS_VERSION}/${PROMETHEUS_FILE}"; then
        errors+=("Ошибка скачивания Prometheus")
    else
        # Распаковка
        echo -e "${ORANGE}• Распаковываем архив...${NC}"
        if ! tar -xf "${PROMETHEUS_FILE}"; then
            errors+=("Ошибка распаковки Prometheus")
        else
            cd "prometheus-${PROMETHEUS_VERSION}.linux-amd64" || errors+=("Ошибка перехода в директорию")
            
            # Установка
            echo -e "${ORANGE}• Переносим файлы...${NC}"
            sudo mv prometheus promtool /usr/local/bin/
            sudo mkdir -p /etc/prometheus/consoles /etc/prometheus/console_libraries
            sudo mv prometheus.yml /etc/prometheus/
            [ -d consoles ] && sudo mv consoles/* /etc/prometheus/consoles/
            [ -d console_libraries ] && sudo mv console_libraries/* /etc/prometheus/console_libraries/

            # Настройка сервиса
            echo "[Unit]
Description=Prometheus
After=network.target

[Service]
User=root
ExecStart=/usr/local/bin/prometheus \
    --config.file=/etc/prometheus/prometheus.yml \
    --storage.tsdb.path=/var/lib/prometheus/data \
    --web.listen-address=0.0.0.0:9090

[Install]
WantedBy=multi-user.target" | sudo tee /etc/systemd/system/prometheus.service >/dev/null

            # Запуск
            echo -e "${ORANGE}• Запускаем сервис...${NC}"
            if ! (sudo systemctl daemon-reload && sudo systemctl enable --now prometheus); then
                errors+=("Ошибка запуска Prometheus")
            elif ! systemctl is-active --quiet prometheus; then
                errors+=("Prometheus не запущен")
            fi
            
            cd ..
        fi
    fi

    if [ ${#errors[@]} -eq 0 ]; then
        echo -e "\n${ORANGE}[✓] СЕРВЕР УСПЕШНО УСТАНОВЛЕН!${NC}\n"
    else
        echo -e "\n${RED}[✗] СЕРВЕР УСТАНОВЛЕН НЕ ПОЛНОСТЬЮ!${NC}"
        echo -e "${ORANGE}Проблемные компоненты:${NC}"
        printf '• %s\n' "${errors[@]}"
        echo
    fi
}

# ... остальные функции без изменений ...
