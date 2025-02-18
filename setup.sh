#!/bin/bash  

# Обновление и установка необходимых пакетов  
echo "Обновляем пакеты..."  
sudo apt update && sudo apt upgrade -y  

echo "Устанавливаем Node.js..."  
sudo apt install -y nodejs  

echo "Настраиваем machine-id..."  
sudo rm /etc/machine-id  
sudo systemd-machine-id-setup  
cat /etc/machine-id  

echo "Устанавливаем текстовый редактор nano..."  
sudo apt install -y nano  

echo "Устанавливаем файл-менеджер..."  
sudo apt install -y file  

# Устанавливаем UFW (брандмауэр)  
echo "Устанавливаем UFW (брандмауэр)..."  
sudo apt install -y ufw  
sudo ufw allow OpenSSH  
sudo ufw enable  

# Устанавливаем fail2ban для защиты от атак  
echo "Устанавливаем fail2ban..."  
sudo apt install -y fail2ban  

# Устанавливаем curl, git, htop  
echo "Устанавливаем curl, git, htop..."  
sudo apt install -y curl git htop  

# Установка Prometheus  
echo "Устанавливаем Prometheus..."  
# Создайте директорию для Prometheus  
sudo mkdir -p /etc/prometheus  
sudo mkdir -p /var/lib/prometheus  

# Скачайте последнюю версию Prometheus  
PROMETHEUS_VERSION="2.40.0" # Укажите последнюю стабильную версию на момент установки  
wget https://github.com/prometheus/prometheus/releases/download/v$PROMETHEUS_VERSION/prometheus-$PROMETHEUS_VERSION.linux-amd64.tar.gz  
tar -xvf prometheus-$PROMETHEUS_VERSION.linux-amd64.tar.gz  
cd prometheus-$PROMETHEUS_VERSION.linux-amd64  

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

# Проверка наличия обновлений для всех установленных пакетов  
echo "Обновляем все установленные пакеты..."  
sudo apt upgrade -y  

# Рекомендуем завершить с перезагрузкой  
echo "Система будет перезагружена через 3 секунды..."  
sleep 3  
sudo reboot
