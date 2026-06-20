#!/bin/bash

# ============================================
# Скрипт установки Fail2Ban и Firewall (UFW)
# Для Ubuntu Server
# ============================================

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Функция для логирования
log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

# Проверка прав root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "Этот скрипт должен запускаться с правами root или через sudo"
        exit 1
    fi
}

# Проверка версии Ubuntu
check_ubuntu() {
    if [[ ! -f /etc/os-release ]]; then
        error "Не удалось определить операционную систему"
        exit 1
    fi
    
    . /etc/os-release
    
    if [[ $ID != "ubuntu" ]] && [[ $ID != "debian" ]]; then
        error "Этот скрипт предназначен для Ubuntu/Debian систем"
        exit 1
    fi
    
    info "Определена система: $NAME $VERSION"
}

# Обновление системы
update_system() {
    log "Обновление списка пакетов..."
    apt-get update -y
    
    log "Установка обновлений системы..."
    apt-get upgrade -y
}

# Установка UFW (Uncomplicated Firewall)
install_ufw() {
    log "Установка UFW (Uncomplicated Firewall)..."
    
    if dpkg -l | grep -q ufw; then
        warning "UFW уже установлен"
    else
        apt-get install ufw -y
        log "UFW успешно установлен"
    fi
}

# Базовая настройка UFW
configure_ufw() {
    log "Настройка UFW..."
    
    # Сброс правил (на случай если уже настроен)
    ufw --force reset > /dev/null 2>&1
    
    # Базовые правила
    log "Установка правил по умолчанию: запретить входящие, разрешить исходящие"
    ufw default deny incoming
    ufw default allow outgoing
    
    # Разрешаем SSH (порт 22)
    log "Разрешение SSH (порт 22)"
    ufw allow ssh
    ufw allow 22/tcp comment 'SSH'
    
    # Разрешаем HTTP и HTTPS если это веб-сервер
    read -p "$(echo -e ${YELLOW}"Это веб-сервер? Разрешить порты 80 и 443? (y/n): "${NC})" -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log "Разрешение HTTP (порт 80) и HTTPS (порт 443)"
        ufw allow 80/tcp comment 'HTTP'
        ufw allow 443/tcp comment 'HTTPS'
    fi
    
    # Дополнительные порты (можно добавить свои)
    read -p "$(echo -e ${YELLOW}"Добавить дополнительные порты? (y/n): "${NC})" -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        read -p "Введите порты через пробел (например: 8080 3306 5432): " ports
        for port in $ports; do
            ufw allow $port/tcp comment "Custom port $port"
            log "Разрешен порт $port/tcp"
        done
    fi
    
    # Ограничение SSH (защита от брутфорса)
    log "Настройка ограничения SSH подключений"
    ufw limit ssh comment 'SSH rate limit'
    
    # Включаем UFW
    log "Включение UFW..."
    ufw --force enable
    
    # Показываем статус
    log "Статус UFW:"
    ufw status verbose
}

# Установка Fail2Ban
install_fail2ban() {
    log "Установка Fail2Ban..."
    
    if dpkg -l | grep -q fail2ban; then
        warning "Fail2Ban уже установлен"
    else
        apt-get install fail2ban -y
        log "Fail2Ban успешно установлен"
    fi
}

# Создание конфигурации Fail2Ban
configure_fail2ban() {
    log "Настройка Fail2Ban..."
    
    # Создание локальной конфигурации
    cat > /etc/fail2ban/jail.local << 'EOF'
[DEFAULT]
# Баны на 1 час (3600 секунд)
bantime = 3600

# Количество попыток
maxretry = 5

# Время для подсчета попыток
findtime = 600

# Действие при бане (блокировка через UFW)
banaction = ufw

# Игнорируемые IP (например, ваш постоянный IP)
#ignoreip = 127.0.0.1/8 192.168.1.0/24

# Уведомления
destemail = root@localhost
sender = root@$(hostname -f)
action = %(action_mwl)s

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 86400

[sshd-ddos]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 10
findtime = 300
bantime = 86400

# Защита от брутфорса веб-сервера
[nginx-http-auth]
enabled = true
port = http,https
filter = nginx-http-auth
logpath = /var/log/nginx/error.log
maxretry = 3

[apache-auth]
enabled = true
port = http,https
filter = apache-auth
logpath = /var/log/apache2/*error.log
maxretry = 3

[apache-badbots]
enabled = true
port = http,https
filter = apache-badbots
logpath = /var/log/apache2/*access.log
bantime = 172800
maxretry = 1

[apache-botsearch]
enabled = true
port = http,https
filter = apache-botsearch
logpath = /var/log/apache2/*access.log
bantime = 172800
maxretry = 1

[proftpd]
enabled = true
port = ftp,ftp-data,ftps,ftps-data
filter = proftpd
logpath = /var/log/proftpd/proftpd.log
maxretry = 6

[postfix]
enabled = true
port = smtp,ssmtp,submission
filter = postfix
logpath = /var/log/mail.log

[dovecot]
enabled = true
port = pop3,pop3s,imap,imaps,submission,465,sieve
filter = dovecot
logpath = /var/log/mail.log
EOF
    
    # Настройка игнорируемых IP
    read -p "$(echo -e ${YELLOW}"Добавить доверенные IP адреса (через пробел)? (y/n): "${NC})" -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        read -p "Введите IP адреса (например: 192.168.1.0/24 10.0.0.1): " trusted_ips
        sed -i "s/#ignoreip = 127.0.0.1\/8 192.168.1.0\/24/ignoreip = 127.0.0.1\/8 $trusted_ips/" /etc/fail2ban/jail.local
    fi
    
    # Перезапуск Fail2Ban
    log "Перезапуск Fail2Ban..."
    systemctl restart fail2ban
    systemctl enable fail2ban
    
    # Проверка статуса
    sleep 2
    log "Статус Fail2Ban:"
    systemctl status fail2ban --no-pager
}

# Установка дополнительных инструментов
install_additional_tools() {
    log "Установка дополнительных инструментов..."
    
    read -p "$(echo -e ${YELLOW}"Установить дополнительные инструменты (iptables-persistent, net-tools)? (y/n): "${NC})" -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        apt-get install -y iptables-persistent net-tools
        log "Дополнительные инструменты установлены"
    fi
}

# Создание скрипта для мониторинга
create_monitoring_script() {
    log "Создание скрипта мониторинга..."
    
    cat > /usr/local/bin/check-firewall.sh << 'EOF'
#!/bin/bash
echo "=== Статус UFW ==="
ufw status verbose
echo ""
echo "=== Статус Fail2Ban ==="
fail2ban-client status
echo ""
echo "=== Забаненные IP ==="
fail2ban-client banned
echo ""
echo "=== Статистика по SSH ==="
fail2ban-client status sshd
EOF
    
    chmod +x /usr/local/bin/check-firewall.sh
    log "Скрипт мониторинга создан: /usr/local/bin/check-firewall.sh"
}

# Вывод итоговой информации
show_summary() {
    echo -e "\n${GREEN}========================================${NC}"
    echo -e "${GREEN}      Установка успешно завершена!       ${NC}"
    echo -e "${GREEN}========================================${NC}\n"
    
    echo -e "${BLUE}Полезные команды:${NC}"
    echo -e "  ${YELLOW}sudo ufw status${NC} - Просмотр статуса файрвола"
    echo -e "  ${YELLOW}sudo ufw allow/deny PORT${NC} - Разрешить/запретить порт"
    echo -e "  ${YELLOW}sudo fail2ban-client status${NC} - Статус Fail2Ban"
    echo -e "  ${YELLOW}sudo fail2ban-client set sshd unbanip IP${NC} - Разбанить IP"
    echo -e "  ${YELLOW}sudo fail2ban-client status sshd${NC} - Статистика по SSH"
    echo -e "  ${YELLOW}sudo check-firewall.sh${NC} - Быстрая проверка статуса"
    echo -e "  ${YELLOW}sudo tail -f /var/log/fail2ban.log${NC} - Просмотр логов Fail2Ban"
    
    echo -e "\n${BLUE}Важные файлы:${NC}"
    echo -e "  ${YELLOW}/etc/fail2ban/jail.local${NC} - Конфигурация Fail2Ban"
    echo -e "  ${YELLOW}/etc/ufw/user.rules${NC} - Правила UFW"
    echo -e "  ${YELLOW}/var/log/fail2ban.log${NC} - Логи Fail2Ban"
    echo -e "  ${YELLOW}/var/log/ufw.log${NC} - Логи UFW"
}

# Главная функция
main() {
    clear
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}     Установка Firewall и Fail2Ban       ${NC}"
    echo -e "${GREEN}========================================${NC}\n"
    
    # Проверки
    check_root
    check_ubuntu
    
    # Подтверждение
    echo -e "${YELLOW}Этот скрипт установит и настроит:${NC}"
    echo "  - UFW (Uncomplicated Firewall)"
    echo "  - Fail2Ban (защита от брутфорса)"
    echo "  - Дополнительные инструменты"
    echo -e "${YELLOW}SSH будет автоматически разрешен.${NC}\n"
    
    read -p "Продолжить установку? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        warning "Установка отменена"
        exit 0
    fi
    
    # Процесс установки
    update_system
    install_ufw
    configure_ufw
    install_fail2ban
    configure_fail2ban
    install_additional_tools
    create_monitoring_script
    
    # Итоговая информация
    show_summary
    
    # Сохранение лога установки
    log "Лог установки сохранен в /root/security-setup.log"
    echo "Installation completed at $(date)" >> /root/security-setup.log
}

# Запуск главной функции
main
