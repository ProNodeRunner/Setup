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
    echo " ༺ Управление сервером по кайфу v4.2 ༻ "
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

# Решение
check_resource_usage() {
  # Функция для рекурсивного поиска всех потомков (для суммирования нагрузки)
  get_descendants() {
    for child in $(ps -eo pid,ppid --no-headers | awk -v p="$1" '$2 == p {print $1}'); do
      echo "$child"
      get_descendants "$child"
    done
  }

  {
    echo -e "${ORANGE}=== Общая загрузка (CPU | RAM) ===${NC}"
    CPU_PERCENT=$(mpstat 1 1 | awk '/Average: *all/ {printf "%.2f", 100 - $NF}')
    MEM_PERCENT=$(free -m | awk '/Mem:/ {printf "%.2f", $3/$2*100}')
    echo "CPU: ${CPU_PERCENT}% | RAM: ${MEM_PERCENT}%"

    echo -e "\n${ORANGE}=== Топ-10 процессов по CPU ===${NC}"
    ps -eo pid,ppid,comm,%cpu,%mem --sort=-%cpu | head -n 11

    echo -e "\n${ORANGE}=== Нагрузка в screen-сессиях ===${NC}"
    if command -v screen &>/dev/null && screen -ls | grep -q "\."; then
      screen -ls | grep -Eo '([0-9]+)\.[^ ]+' | while read -r sess; do
        sess_pid=$(cut -d'.' -f1 <<< "$sess")
        sess_name=$(cut -d'.' -f2- <<< "$sess")
        all_children=$(get_descendants "$sess_pid")
        if [ -n "$all_children" ]; then
          usage=$(ps -o %cpu= -o %mem= -p $(echo "$all_children") --no-headers 2>/dev/null \
            | awk '{cpu+=$1; mem+=$2} END {printf "%.2f%% CPU / %.2f%% MEM", cpu, mem}')
          echo "Session: $sess_name => $usage"
        else
          echo "Session: $sess_name => 0.00% CPU / 0.00% MEM"
        fi
      done
    else
      echo "Нет активных screen-сессий"
    fi

    echo -e "\n${ORANGE}=== Docker контейнеры ===${NC}"
    if command -v docker &>/dev/null; then
      docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}"
    else
      echo "Docker не установлен"
    fi

    echo -e "\n${ORANGE}=== Трафик за 30 дней (vnstat) ===${NC}"
    if command -v vnstat &>/dev/null; then
      vnstat -m
    else
      echo "vnstat не установлен"
    fi

    echo -e "\n${ORANGE}=== Текущая скорость (10 сек) ===${NC}"
    NET_IF=$(ip -o -4 route show to default | awk '{print $5}')
    RX1=$(< /sys/class/net/$NET_IF/statistics/rx_bytes)
    TX1=$(< /sys/class/net/$NET_IF/statistics/tx_bytes)
    sleep 10
    RX2=$(< /sys/class/net/$NET_IF/statistics/rx_bytes)
    TX2=$(< /sys/class/net/$NET_IF/statistics/tx_bytes)
    RX_SPEED=$(awk "BEGIN {printf \"%.2f\", ($RX2 - $RX1)/1024/1024/10}")
    TX_SPEED=$(awk "BEGIN {printf \"%.2f\", ($TX2 - $TX1)/1024/1024/10}")
    echo "Загрузка: ${RX_SPEED} MB/s | Выгрузка: ${TX_SPEED} MB/s"
  }
  # Завершающий prompt вместо (END)
  echo
  read -n1 -s -r -p "Нажмите любую клавишу, чтобы выйти..."
  echo
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

# Решение: Полная очистка сервера от нод и зависимостей
remove_server() {
    echo -e "${ORANGE}[!] Начинается полное удаление сервера...${NC}"
    
    # 1. Отключение пользовательских сервисов
    sudo systemctl disable --now prometheus 2>/dev/null
    sudo systemctl disable --now titan-node.service 2>/dev/null

    # 2. Удаление конфигураций и файлов служб
    sudo rm -rf /etc/prometheus /var/lib/prometheus /usr/local/bin/prometheus* 2>/dev/null
    sudo rm -rf /etc/titan_nodes.conf /etc/systemd/system/titan-node.service 2>/dev/null

    # 3. Удаление Docker: контейнеров, volumes, образов и очистка системы
    if command -v docker &>/dev/null; then
        echo -e "${ORANGE}[1/7] Удаление docker контейнеров нод...${NC}"
        docker ps -aq --filter "name=node" | xargs -r docker rm -f

        echo -e "${ORANGE}[2/7] Удаление docker volumes нод...${NC}"
        docker volume ls -q --filter "name=node" | xargs -r docker volume rm

        echo -e "${ORANGE}[3/7] Удаление docker образов нод...${NC}"
        docker images -q "node*" | xargs -r docker rmi -f

        echo -e "${ORANGE}[4/7] Очистка docker системы...${NC}"
        docker system prune -af
    fi

    # 4. Остановка и удаление всех screen-сессий, связанных с нодами
    if command -v screen &>/dev/null; then
        echo -e "${ORANGE}[5/7] Остановка screen-сессий нод...${NC}"
        screen -ls | grep "node" | awk -F. '{print $1}' | xargs -r -I{} screen -X -S {} quit
    fi

    # 5. Удаление установленных пакетов, связанных с нодами и системными утилитами
    # Список пакетов можно расширять по необходимости.
    PACKAGES_TO_PURGE="docker-ce docker-ce-cli containerd.io screen wget tar nano file fail2ban vnstat ifstat net-tools jq"
    sudo apt-get purge -y $PACKAGES_TO_PURGE 2>/dev/null
    sudo apt-get autoremove -y --purge 2>/dev/null

    # 6. Очистка кастомных конфигурационных файлов и директорий
    sudo rm -rf /etc/docker /var/lib/docker /opt/node 2>/dev/null

    # 7. Очистка iptables и сохранение настроек
    sudo iptables -t nat -F
    sudo iptables -t mangle -F
    sudo netfilter-persistent save >/dev/null 2>&1

    echo -e "\n${RED}[!] Сервер полностью очищен и готов к возврату хостингу!${NC}\n"
}
# Полная очистка сервера от нод и зависимостей.


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
