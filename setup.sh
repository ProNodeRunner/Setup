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
    curl -sSf "$LOGO_URL" 2>/dev/null || echo -e "=== Server Management ==="
    echo -e "\n\n\n"
    echo " ༺ Управление сервером по кайфу v3.0 ༻ "
    echo "======================================="
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
    if ! sudo DEBIAN_FRONTEND=noninteractive apt install -y wget tar nano file fail2ban screen vnstat ifstat net-tools jq; then
        errors+=("Ошибка установки базовых компонентов")
    fi

    echo -e "${ORANGE}[*] Устанавливаем Prometheus...${NC}"  
    PROMETHEUS_VERSION="3.2.1"
    PROMETHEUS_FILE="prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz"
    PROMETHEUS_DIR="prometheus-${PROMETHEUS_VERSION}.linux-amd64"

    sudo rm -rf prometheus-*

    echo -e "${ORANGE}• Скачиваем ${PROMETHEUS_FILE}...${NC}"
    if ! wget -q "https://github.com/prometheus/prometheus/releases/download/v${PROMETHEUS_VERSION}/${PROMETHEUS_FILE}"; then
        errors+=("Ошибка скачивания Prometheus")
    else
        echo -e "${ORANGE}• Распаковываем архив...${NC}"
        if ! tar -xf "${PROMETHEUS_FILE}"; then
            errors+=("Ошибка распаковки Prometheus")
        elif [ ! -d "${PROMETHEUS_DIR}" ]; then
            errors+=("Директория ${PROMETHEUS_DIR} не найдена")
        else
            cd "${PROMETHEUS_DIR}" || {
                errors+=("Ошибка перехода в директорию ${PROMETHEUS_DIR}")
                cd ..
            }

            if [ ${#errors[@]} -eq 0 ]; then
                echo -e "${ORANGE}• Переносим файлы...${NC}"
                sudo mv -v prometheus promtool /usr/local/bin/ || errors+=("Ошибка перемещения бинарных файлов")
                sudo mkdir -p /etc/prometheus || errors+=("Ошибка создания директории /etc/prometheus")
                sudo mv -v prometheus.yml /etc/prometheus/ || errors+=("Ошибка перемещения конфига")

                echo -e "${ORANGE}• Настраиваем сервис...${NC}"
                sudo tee /etc/systemd/system/prometheus.service >/dev/null <<EOF
[Unit]
Description=Prometheus
After=network.target

[Service]
User=root
ExecStart=/usr/local/bin/prometheus \
    --config.file=/etc/prometheus/prometheus.yml \
    --storage.tsdb.path=/var/lib/prometheus/data \
    --web.listen-address=0.0.0.0:9090

[Install]
WantedBy=multi-user.target
EOF

                echo -e "${ORANGE}• Запускаем сервис...${NC}"
                if ! (sudo systemctl daemon-reload && sudo systemctl enable --now prometheus); then
                    errors+=("Ошибка запуска Prometheus")
                elif ! systemctl is-active --quiet prometheus; then
                    errors+=("Prometheus не запущен")
                fi
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

check_resource_usage() {
    echo -e "${ORANGE}=== Загрузка ресурсов ===${NC}"

    # 1️⃣ CPU сервера (исправленный расчет)
    CPU_LOAD=$(top -bn1 | grep "Cpu(s)" | awk '{print $2 + $4}')
    STEAL_TIME=$(top -bn1 | grep "Cpu(s)" | awk '{print $8}')
    MEMORY_LOAD=$(free | awk '/Mem:/ {printf "%.1f", $3/$2 * 100}')

    echo -e "CPU сервера: ${ORANGE}${CPU_LOAD}%${NC}"
    echo -e "RAM сервера: ${ORANGE}${MEMORY_LOAD}%${NC}"
    echo -e "Steal Time (украденный CPU на VPS): ${RED}${STEAL_TIME}%${NC}"

    # 2️⃣ Нагрузка по CLI-нодам (улучшено)
    echo -e "${ORANGE}=== Нагрузка по нодам (CLI-клиенты) ===${NC}"
    ps -eo pid,comm,%cpu,%mem --sort=-%cpu | head -n 15 | awk '{printf "PID: %s | Процесс: %s | CPU: %s%% | RAM: %s%%\n", $1, $2, $3, $4}'

    # 3️⃣ Нагрузка по screen-сессиям
    if command -v screen &>/dev/null && screen -ls | grep -q "."; then
        echo -e "${ORANGE}=== Нагрузка по screen-сессиям ===${NC}"
        screen -ls | grep -oE '[0-9]+[.][^ ]+' | while read -r session; do
            PID=$(screen -ls | grep "$session" | awk '{print $1}' | cut -d'.' -f1)
            CPU=$(ps -p $PID -o %cpu --no-headers | awk '{print $1}')
            MEM=$(ps -p $PID -o %mem --no-headers | awk '{print $1}')
            echo -e "Сессия: ${ORANGE}$session${NC} | CPU: ${ORANGE}${CPU:-0}%${NC} | RAM: ${ORANGE}${MEM:-0}%${NC}"
        done
    fi

    # 4️⃣ Нагрузка по Docker-контейнерам (исправлено)
    if command -v docker &>/dev/null; then
        echo -e "${ORANGE}=== Нагрузка по Docker-нодам ===${NC}"
        docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}"
    fi

    # 5️⃣ Проверка Steal Time (если CPU воруют другие VM)
    echo -e "${ORANGE}=== Анализ использования CPU ядрами ===${NC}"
    mpstat -P ALL 1 1 | tail -n +4 | awk '{printf "Ядро %s | Пользователь: %s%% | Система: %s%% | Украдено: %s%%\n", $2, $3, $5, $13}'

    # 6️⃣ Проверка сетевого трафика за 30 дней (исправлено)
    if command -v vnstat &>/dev/null; then
        echo -e "${ORANGE}=== Общий трафик за 30 дней ===${NC}"
        TRAFFIC_JSON=$(vnstat --json m 2>/dev/null)
        if [[ -z "$TRAFFIC_JSON" ]]; then
            echo -e "${RED}Сбор данных... Подождите несколько часов.${NC}"
        else
            RX_BYTES=$(echo "$TRAFFIC_JSON" | jq -r '.interfaces[0].traffic.month[0].rx')
            TX_BYTES=$(echo "$TRAFFIC_JSON" | jq -r '.interfaces[0].traffic.month[0].tx')

            format_bytes() {
                local bytes=$1
                if (( bytes >= 1073741824 )); then
                    echo "$(awk "BEGIN {printf \"%.2f GB\", $bytes/1073741824}")"
                elif (( bytes >= 1048576 )); then
                    echo "$(awk "BEGIN {printf \"%.2f MB\", $bytes/1048576}")"
                else
                    echo "${bytes} KB"
                fi
            }

            echo -e "Получено: ${ORANGE}$(format_bytes $RX_BYTES)${NC}"
            echo -e "Отправлено: ${ORANGE}$(format_bytes $TX_BYTES)${NC}"
        fi
    else
        echo -e "${RED}vnstat не установлен!${NC}"
    fi

    # 7️⃣ Проверка текущей скорости трафика (исправлено)
    echo -e "${ORANGE}=== Текущая скорость трафика (замер за 10 сек) ===${NC}"
    NET_IF=$(ip -o -4 route show to default | awk '{print $5}')
    RX1=$(cat /sys/class/net/$NET_IF/statistics/rx_bytes)
    TX1=$(cat /sys/class/net/$NET_IF/statistics/tx_bytes)
    sleep 10
    RX2=$(cat /sys/class/net/$NET_IF/statistics/rx_bytes)
    TX2=$(cat /sys/class/net/$NET_IF/statistics/tx_bytes)

    RX_SPEED=$(awk "BEGIN {printf \"%.2f\", ($RX2 - $RX1) / 1024 / 1024 / 10}")
    TX_SPEED=$(awk "BEGIN {printf \"%.2f\", ($TX2 - $TX1) / 1024 / 1024 / 10}")

    echo -e "Скорость загрузки: ${ORANGE}${RX_SPEED} MB/s${NC}"
    echo -e "Скорость выгрузки: ${ORANGE}${TX_SPEED} MB/s${NC}"
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
    sudo systemctl disable --now prometheus 2>/dev/null
    sudo rm -rf /etc/prometheus /var/lib/prometheus /usr/local/bin/prometheus* 2>/dev/null
    
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
