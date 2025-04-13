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
    echo " ༺ Управление сервером по кайфу v5.0 ༻ "
    echo "======================================="
    echo " Что хозяин изволит? ༻ "
    echo "1) Установить новый сервер"
    echo "2) Замаскировать сервер"
    echo "3) Проверить загрузку ресурсов"
    echo "4) Проверить ноды на сервере"
    echo "5) Засейвить сервер"
    echo "6) Восстановить сервер после падения"
    echo "9) Перезагрузить сервер"
    echo "0) Удалить сервер"
    echo "7) Иди работай, чудо-машина!"
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

server_hide() {
    echo "=== Маскировка сервера: перегенерация machine-id и смена hostname ==="

    #########################################
    # 1. Перегенерация machine-id
    #########################################
    echo "Перегенерация machine-id..."
    sudo rm -f /etc/machine-id
    sudo systemd-machine-id-setup
    echo "Новый machine-id: $(cat /etc/machine-id)"
    echo

    #########################################
    # 2. Генерация нового hostname
    #########################################
    echo "Генерация нового hostname..."

    # Путь к файлу словаря
    DICT="/usr/share/dict/words"

    # Если словарь не найден, устанавливаем пакет wamerican без подтверждений
    if [ ! -f "$DICT" ]; then
        echo "Файл $DICT не найден, устанавливаем пакет wamerican..."
        sudo DEBIAN_FRONTEND=noninteractive apt-get update -y
        sudo DEBIAN_FRONTEND=noninteractive apt-get install -y wamerican
    fi

    # Читаем слова из файла или используем резервный список
    if [ -f "$DICT" ]; then
        # Берём только строки, состоящие из строчных латинских букв
        words=( $(grep '^[a-z]\+$' "$DICT") )
    else
        echo "Словарь не найден, используем резервный список слов."
        words=(apple banana cherry dog elephant fish grape honey lemon mango)
    fi

    # Если массив слов пуст, переключаемся на резервный список
    if [ ${#words[@]} -eq 0 ]; then
        echo "Словарь пуст, используем резервный список."
        words=(apple banana cherry dog elephant fish grape honey lemon mango)
    fi

    # Выбираем два случайных, неповторяющихся слова
    index1=$(( RANDOM % ${#words[@]} ))
    index2=$(( RANDOM % ${#words[@]} ))
    while [ "$index1" -eq "$index2" ]; do
        index2=$(( RANDOM % ${#words[@]} ))
    done
    word1=${words[$index1]}
    word2=${words[$index2]}

    # Генерируем случайные числа для вставок
    rand1=$(shuf -i 100-999 -n 1)
    rand2=$(shuf -i 10-99 -n 1)

    # Массивы для разделителей, префиксов и токенов окружения
    delim_options=("-" "_" "." "")
    prefixes=("srv" "node" "host")
    env_options=("prod" "dev" "stg" "test" "qa")
    # Выбираем случайный разделитель
    delim=${delim_options[$(( RANDOM % ${#delim_options[@]} ))]}

    # Случайным образом выбираем один из вариантов генерации hostname (от 0 до 10)
    pattern=$(( RANDOM % 11 ))
    case $pattern in
        0)
            # Вариант: число + разделитель + слово1 + разделитель + слово2
            new_hostname="${rand1}${delim}${word1}${delim}${word2}"
            ;;
        1)
            # Вариант: слово1 + разделитель + число + разделитель + слово2
            new_hostname="${word1}${delim}${rand1}${delim}${word2}"
            ;;
        2)
            # Вариант: слово1 + разделитель + слово2 + разделитель + число
            new_hostname="${word1}${delim}${word2}${delim}${rand1}"
            ;;
        3)
            # Вариант: число + разделитель + слово1 + разделитель + другое число + разделитель + слово2
            new_hostname="${rand1}${delim}${word1}${delim}${rand2}${delim}${word2}"
            ;;
        4)
            # Вариант: слово1 + число + слово2 (без разделителей)
            new_hostname="${word1}${rand1}${word2}"
            ;;
        5)
            # Вариант: слово1 + разделитель + слово2 с числом в конце
            new_hostname="${word1}${delim}${word2}${rand1}"
            ;;
        6)
            # Вариант: число + разделитель + слово1 + разделитель + слово2 + разделитель + число
            new_hostname="${rand1}${delim}${word1}${delim}${word2}${delim}${rand2}"
            ;;
        7)
            # Вариант: префикс + разделитель + слово1 + разделитель + слово2
            prefix=${prefixes[$(( RANDOM % ${#prefixes[@]} ))]}
            new_hostname="${prefix}${delim}${word1}${delim}${word2}"
            ;;
        8)
            # Вариант: слово1 + разделитель + токен окружения + разделитель + слово2
            env=${env_options[$(( RANDOM % ${#env_options[@]} ))]}
            new_hostname="${word1}${delim}${env}${delim}${word2}"
            ;;
        9)
            # CamelCase: слово1 и слово2 с заглавными первыми буквами + число в конце
            word1_cap="$(tr '[:lower:]' '[:upper:]' <<< ${word1:0:1})${word1:1}"
            word2_cap="$(tr '[:lower:]' '[:upper:]' <<< ${word2:0:1})${word2:1}"
            new_hostname="${word1_cap}${word2_cap}${rand1}"
            ;;
        10)
            # Вариант: префикс + слово1 + токен окружения + слово2 + число (без разделителей)
            prefix=${prefixes[$(( RANDOM % ${#prefixes[@]} ))]}
            env=${env_options[$(( RANDOM % ${#env_options[@]} ))]}
            new_hostname="${prefix}${word1}${env}${word2}${rand2}"
            ;;
    esac

    echo "Устанавливаем новый hostname: ${new_hostname}"
    sudo hostnamectl set-hostname "${new_hostname}"
    echo "Hostname успешно обновлён: $(hostname)"
    echo

    echo "Обратите внимание: PTR-запись не изменена этим скриптом!"
    echo "Для обновления PTR-записи воспользуйтесь панелью управления VPS или API провайдера."
    echo "=== Маскировка сервера завершена! ==="
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


# Решение
check_nodes() {
    echo -e "${ORANGE}=== Анализ нод ===${NC}"

    # 1. Вывод всех Docker контейнеров (независимо от статуса)
    echo -e "\n${ORANGE}[*] Все Docker контейнеры нод:${NC}"
    docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.Image}}" || echo "Контейнеры не найдены"

    # 2. Поиск нод в systemd unit файлах.
    # Универсальный поиск — ищем по ключевым словам: "node", "cli" и "rclient".
    echo -e "\n${ORANGE}[*] Systemd unit files автозапуска (поиск 'node|cli|rclient'):${NC}"
    sudo grep -RilE "(node|cli|rclient|daemon|fullnode|lightnode|validator|worker|agent|depin|edge|runner|service)" /etc/systemd/system/ 2>/dev/null | sort -u || echo "Нет записей в /etc/systemd/system/"

    # 3. Поиск нод в конфигурационных файлах.
    echo -e "\n${ORANGE}[*] Конфигурационные файлы с нодами (поиск 'node|cli|rclient'):${NC}"
    sudo grep -RilE "(node|cli|rclient|daemon|fullnode|lightnode|validator|worker|agent|depin|edge|runner|service)" /etc/ 2>/dev/null | sort -u || echo "Нет конфигураций с нодами"

    # 4. Поиск информации о нодах в screen-сессиях.
    echo -e "\n${ORANGE}[*] Screen-сессии (поиск 'node|cli|rclient'):${NC}"
    screen -ls 2>/dev/null | grep -Ei "(node|cli|rclient|daemon|fullnode|lightnode|validator|worker|agent|depin|edge|runner|service)" || echo "Нет активных или сохранённых screen-сессий"

    # 5. Вывод дополнительного файла автозапуска нод (если используется)
    echo -e "\n${ORANGE}[*] Файл автозапуска нод (/etc/nodes.conf):${NC}"
    if [ -f /etc/nodes.conf ]; then
        cat /etc/nodes.conf
    else
        echo "/etc/nodes.conf не найден"
    fi

    echo -e "\n${ORANGE}[!] Рекомендация:${NC}"
    echo "Если сервер перезагружен и screen-сессии утрачены, используйте найденные systemd unit файлы или конфигурации для восстановления нод."
    echo "Рекомендуется вести бэкап списка нод (например, в /etc/nodes.conf) для быстрого восстановления."
    
    echo -e "\n${GREEN}[✓] Анализ завершен. Используйте найденные данные для восстановления нод.${NC}"
}


reboot_server() {  
    echo -e "${ORANGE}[!] Инициирую перезагрузку...${NC}"  
    sudo reboot  
}  

# Решение: Обновлённая функция save_screen_nodes()
# Эта функция сохраняет информацию о активных screen-сессиях нод в файл /etc/nodes.conf,
# добавляя новые записи, если их там ещё нет, и оставляя существующие без изменений.
#
# Ожидаемый формат записи в /etc/nodes.conf:
#   # Нода: <имя проекта>
#   screen -dmS <имя проекта> bash -c "<команда запуска>"
#
# Если запись для конкретного проекта уже существует, она не перезаписывается.
# Таким образом, при последовательном запуске функция добавляет только новые ноды,
# сохраняя историю уже сохранённых записей для последующего восстановления.

save_screen_nodes() {
    echo -e "${ORANGE}[*] Сохранение активных screen-сессий нод в /etc/nodes.conf...${NC}"
    
    config_file="/etc/nodes.conf"
    tmpfile=$(mktemp)
    
    # Если /etc/nodes.conf уже существует, копируем его содержимое
    if [ -f "$config_file" ]; then
        cp "$config_file" "$tmpfile"
    else
        # Иначе создаем новый файл с заголовком
        {
            echo "# Конфигурация запуска нод, сохранённых в screen-сессиях"
            echo "# Данный файл используется для восстановления нод после ребута сервера."
            echo "# Формат: screen -dmS <имя проекта> bash -c \"<команда запуска>\""
            echo ""
        } > "$tmpfile"
    fi

    # Перебираем активные screen-сессии. Ожидается формат: "PID.ИМЯ" (например, "12345.Gensyn")
    screen -ls | grep -oE '[0-9]+\.[^[:space:]]+' | while read -r session; do
        session_pid=$(echo "$session" | cut -d'.' -f1)
        session_name=$(echo "$session" | cut -d'.' -f2)
        # Извлекаем первую дочернюю команду для данного screen-процесса
        child_cmd=$(ps --ppid "$session_pid" -o cmd= 2>/dev/null | head -n 1)
        if [ -z "$child_cmd" ]; then
            child_cmd="echo 'Запустить ноду $session_name' && sleep 1"
        fi

        # Проверяем, существует ли уже запись с этим именем сессии в файле
        if ! grep -q "screen -dmS $session_name " "$tmpfile"; then
            echo "# Нода: $session_name" >> "$tmpfile"
            echo "screen -dmS $session_name bash -c \"$child_cmd\"" >> "$tmpfile"
            echo "" >> "$tmpfile"
        fi
    done

    # Перемещаем временный файл в /etc/nodes.conf с правами root
    sudo mv "$tmpfile" "$config_file"
    echo -e "${GREEN}[✓] Конфигурация нод обновлена в $config_file${NC}"
    read -n1 -s -r -p "Нажмите любую клавишу для возврата в меню..."
    echo
}

# Решение: Функция revive_server для автоматического восстановления сервера после падения.
# Функция выполняет следующие действия:
# 1. Перезагружает конфигурацию systemd (если имеются unit-файлы для нод).
# 2. Перезапускает Docker-контейнеры нод, которые не активны.
# 3. Восстанавливает ноды, запущенные через screen, на основании конфигурационного файла /etc/nodes.conf.
#    Для каждой записи в файле:
#      - Извлекается имя сессии.
#      - Если сессия уже активна (проверяется через screen -ls), то пропускается.
#      - Если сессия отсутствует, выполняется команда запуска из файла.
#
# Это позволяет, если после падения сервера некоторые ноды не восстановились, их перезапустить
# без потери ранее добавленных записей (они аккумулируются в /etc/nodes.conf).

revive_server() {
    echo -e "${ORANGE}[!] Запуск восстановления сервера после падения...${NC}"

    # 1. Перезагрузка systemd unit файлов (если имеются)
    echo -e "\n${ORANGE}[*] Перезагрузка конфигурации systemd (если имеются unit-файлы)...${NC}"
    sudo systemctl daemon-reload

    # 2. Перезапуск Docker-контейнеров нод
    echo -e "\n${ORANGE}[*] Перезапуск Docker-контейнеров нод...${NC}"
    if command -v docker &>/dev/null; then
        for container in $(docker ps -a --filter "name=node" -q); do
            if [ "$(docker inspect -f '{{.State.Running}}' "$container")" != "true" ]; then
                echo -e "Запуск Docker контейнера: ${GREEN}$container${NC}"
                docker start "$container"
            else
                echo -e "Контейнер ${GREEN}$container${NC} уже запущен"
            fi
        done
    else
        echo "Docker не установлен"
    fi

    # 3. Восстановление нод, запущенных через screen, из файла /etc/nodes.conf
    echo -e "\n${ORANGE}[*] Восстановление нод из файла /etc/nodes.conf...${NC}"
    if [ -f /etc/nodes.conf ]; then
        while IFS= read -r line || [ -n "$line" ]; do
            # Пропускаем пустые строки и комментарии
            [[ -z "$line" || "$line" =~ ^# ]] && continue

            # Извлекаем имя сессии.
            # Ожидаемый формат: 
            #   screen -dmS <имя_сессии> bash -c "<команда запуска>"
            session_name=$(echo "$line" | awk '{print $3}')
            # Проверяем, есть ли уже активная сессия с этим именем:
            if screen -ls | grep -qE "[0-9]+\.$session_name\b"; then
                echo -e "Сессия ${GREEN}$session_name${NC} уже активна. Пропускаем."
            else
                echo -e "Запуск: ${GREEN}$line${NC}"
                bash -c "$line"
            fi
        done < /etc/nodes.conf
    else
        echo -e "${RED}Файл /etc/nodes.conf не найден. Ноды, запущенные через screen, не восстановлены.${NC}"
    fi

    echo -e "\n${GREEN}[✓] Восстановление сервера завершено. Проверьте состояние нод.${NC}"
    read -n1 -s -r -p "Нажмите любую клавишу для возврата в меню..."
    echo
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
    read -p " Пива, женщин и ?: " option
    
    case $option in  
        1) install_server ;;
        2) server_hide ;;
        3) check_resource_usage ;;
        4) check_nodes ;;
        5) save_screen_nodes ;;
        6) revive_server ;;
        9) reboot_server ;;
        0) remove_server ;;
        7) 
            echo -e "${GREEN}И тебе хорошего дня!${NC}"
            break ;;
        *) echo -e "${RED}Неверный выбор!${NC}" ;;
    esac
    
    read -p "Нажмите Enter чтобы продолжить..."
    clear
done
