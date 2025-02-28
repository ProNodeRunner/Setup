#!/bin/bash  

# Функция для установки нового сервера  
install_server() {  
    echo "Обновляем пакеты..."  
    sudo DEBIAN_FRONTEND=noninteractive apt update && sudo DEBIAN_FRONTEND=noninteractive apt upgrade -y  

    echo "Устанавливаем последние обновления ядра, если доступно..."  
    sudo DEBIAN_FRONTEND=noninteractive apt install -y linux-generic  

    # Проверка текущего ядра  
    CURRENT_KERNEL=$(uname -r)  
    NEW_KERNEL=$(dpkg -l | grep linux-image | awk '{print $2}' | sort | tail -n 1 | sed 's/linux-image-//g')  

    if [[ "$CURRENT_KERNEL" != "$NEW_KERNEL" ]]; then  
        echo "Доступно новое ядро: $NEW_KERNEL."  
        echo "Следующее, что вы можете сделать, это перезагрузить сервер, чтобы загрузить новое ядро."  
    else  
        echo "Текущая версия ядра актуальна: $CURRENT_KERNEL."  
    fi  

    # Перезапускаем службы автоматом  
    echo "Перезапускаем службы..."  
    services=("dbus.service" "getty@tty1.service" "networkd-dispatcher.service" "systemd-logind.service" "systemd-manager" "unattended-upgrades.service" "user@0.service")  

    for service in "${services[@]}"; do  
        echo "Перезапускаем $service..."  
        sudo systemctl restart "$service"  
    done  

    echo "Все службы успешно перезапущены."  

    echo "Настраиваем machine-id..."  
    sudo rm /etc/machine-id  
    sudo systemd-machine-id-setup  
    cat /etc/machine-id  

    echo "Устанавливаем текстовый редактор nano..."  
    sudo DEBIAN_FRONTEND=noninteractive apt install -y nano  

    echo "Устанавливаем файл-менеджер..."  
    sudo DEBIAN_FRONTEND=noninteractive apt install -y file   

    echo "Устанавливаем fail2ban для защиты от атак..."  
    sudo DEBIAN_FRONTEND=noninteractive apt install -y fail2ban  

    # Установка screen
    echo "Устанавливаем screen для управления сессиями..."
    sudo DEBIAN_FRONTEND=noninteractive apt install -y screen

    # Установка Prometheus  
    echo "Устанавливаем Prometheus..."  

    # Создайте директорию для Prometheus  
    sudo mkdir -p /etc/prometheus  
    sudo mkdir -p /var/lib/prometheus  

    # Скачайте последнюю версию Prometheus  
    PROMETHEUS_VERSION="3.2.0" # Укажите последнюю стабильную версию  
    wget https://github.com/prometheus/prometheus/releases/download/v$PROMETHEUS_VERSION/prometheus-$PROMETHEUS_VERSION.darwin-amd64.tar.gz  
    tar -xvf prometheus-$PROMETHEUS_VERSION.darwin-amd64.tar.gz  
    cd prometheus-$PROMETHEUS_VERSION.darwin-amd64 || return

    # Переместите бинарные файлы в /usr/local/bin  
    sudo mv prometheus /usr/local/bin/  
    sudo mv promtool /usr/local/bin/  

    # Переместите конфигурационные файлы в /etc/prometheus  
    sudo mv prometheus.yml /etc/prometheus/  
    sudo mv consoles/ /etc/prometheus/  
    sudo mv console_libraries/ /etc/prometheus/  

    # Создать systemd service file для Prometheus  
    echo "[Unit]  
Description=Prometheus  
Wants=network-online.target  
After=network-online.target  

[Service]  
User=root  
ExecStart=/usr/local/bin/prometheus --config.file=/etc/prometheus/prometheus.yml --storage.tsdb.path=/var/lib/prometheus/data  

[Install]  
WantedBy=multi-user.target" | sudo tee /etc/systemd/system/prometheus.service  

    # Запустите и включите Prometheus  
    sudo systemctl daemon-reload  
    sudo systemctl start prometheus  
    sudo systemctl enable prometheus  

    echo ""  # Отступ в одну строку  
    # Зелёный цвет для успеха  
    echo -e "\e[1;32mСЕРВЕР УСПЕШНО УСТАНОВЛЕН!\e[0m"
    echo ""  # Одна пустая строка после финального сообщения  
    echo "Выберите один из вариантов действий в меню."  
}  

# Функция для проверки загрузки ресурсов  
check_resource_usage() {  
    echo "Загруженность процессора, оперативной памяти и интернет-трафик:"  

    # Получение загрузки процессора  
    CPU_LOAD=$(top -b -n1 | grep "Cpu" | awk '{print $2 + $4}') # Половина строк  
    MEMORY_LOAD=$(free | grep Mem | awk '{print $3/$2 * 100}') # Процент использования памяти  
    TRAFFIC=$(vnstat --oneline | awk -F';' '{print $2}') # Трафик  

    echo "Загрузка процессора: ${CPU_LOAD}%"  
    echo "Загрузка памяти: ${MEMORY_LOAD}%"  
    echo "Интернет-трафик: ${TRAFFIC}"  
}  

# Функция для проверки нод на сервере
check_nodes() {
    echo "=== Анализ нод на сервере ==="

    # Проверка процессов
    echo -e "\n[!] Запущенные процессы, использующие порты 8080 и выше:"
    ps aux | grep -E '[n]ode|[d]aemon|[s]erver' | grep -E '808[0-9]|809[0-9]'

    # Проверка сетевых подключений
    echo -e "\n[!] Открытые порты 8080 и выше:"
    sudo ss -tulpn | grep -E '808[0-9]|809[0-9]'

    # Проверка конфигурационных файлов
    echo -e "\n[!] Поиск конфигурационных файлов нод:"
    find / -type d -name "config" 2>/dev/null | grep -E 'node|chain|testnet'

    # Проверка Docker-контейнеров
    echo -e "\n[!] Docker-контейнеры, использующие порты 8080 и выше:"
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E '808[0-9]|809[0-9]'

    # Проверка системных сервисов
    echo -e "\n[!] Системные сервисы, связанные с нодами:"
    systemctl list-units --type=service | grep -E 'node|chain|testnet'

    # Проверка логов
    echo -e "\n[!] Логи нод:"
    sudo journalctl -u *node* -u *chain* -u *testnet* -n 100 --no-pager

    echo -e "\n=== Поиск завершен ==="
}

# Функция для перезагрузки сервера  
reboot_server() {  
    echo "Перезагрузка сервера..."  
    sudo reboot  
}  

# Функция для удаления сервера  
remove_server() {  
    echo "Удаление сервера..."  
    # Остановка Prometheus  
    sudo systemctl stop prometheus  
    sudo systemctl disable prometheus  
    sudo rm -rf /etc/prometheus /var/lib/prometheus /usr/local/bin/prometheus /usr/local/bin/promtool /etc/systemd/system/prometheus.service  

    # Удаление установленных пакетов  
    sudo apt remove -y nano file ufw fail2ban curl git htop vnstat  
    sudo apt autoremove -y  

    echo "Сервер удален!"  
}  

# Основное меню  
while true; do  
    echo "Выберите опцию:"  
    echo "1. Установить новый сервер"  
    echo "2. Проверить загрузку ресурсов"  
    echo "3. Проверить ноды на сервере"      # НОВЫЙ ПУНКТ
    echo "4. Перезагрузить сервер"           # СМЕЩЁН
    echo "5. Удалить сервер"                 # СМЕЩЁН
    echo "6. Выход"                          # СМЕЩЁН

    read -p "Введите номер опции [1-6]: " option  
    option=$(echo $option | tr -d '[:space:]')  

    case $option in  
        1) install_server ;;  
        2) check_resource_usage ;;  
        3) check_nodes ;;                   # НОВЫЙ КЕЙС
        4) reboot_server ;;                 # СМЕЩЁН
        5) remove_server ;;                 # СМЕЩЁН
        6)                                  # СМЕЩЁН
            echo "Выход."  
            break  
            ;;  
        *) echo "Неверный ввод, попробуйте снова." ;;  
    esac  
    sleep 1  
done
