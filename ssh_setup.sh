#!/bin/bash

# Скрипт для настройки SSH: смена порта, отключение парольной аутентификации, добавление SSH-ключа для root
# Запускать от root или с sudo

set -e  # Прерывать выполнение при ошибке

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Функция для вывода сообщений
log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Проверка прав root
if [[ $EUID -ne 0 ]]; then
   error "Этот скрипт должен запускаться с правами root или через sudo"
   exit 1
fi

# Конфигурационные переменные
NEW_SSH_PORT=2222  # Новый порт SSH (измените при необходимости)
SSH_KEY_PATH="/root/.ssh/authorized_keys"
SSHD_CONFIG="/etc/ssh/sshd_config"
SSHD_CONFIG_BACKUP="/etc/ssh/sshd_config.backup.$(date +%Y%m%d_%H%M%S)"

# Запрос нового порта
read -p "Введите новый порт SSH (по умолчанию 2222): " INPUT_PORT
NEW_SSH_PORT=${INPUT_PORT:-$NEW_SSH_PORT}

# Проверка, что порт в допустимом диапазоне
if ! [[ "$NEW_SSH_PORT" =~ ^[0-9]+$ ]] || [ "$NEW_SSH_PORT" -lt 1024 ] || [ "$NEW_SSH_PORT" -gt 65535 ]; then
    error "Некорректный порт. Должен быть числом от 1024 до 65535"
    exit 1
fi

log "Начинаем настройку SSH..."

# Создание резервной копии конфигурации
log "Создание резервной копии $SSHD_CONFIG"
cp "$SSHD_CONFIG" "$SSHD_CONFIG_BACKUP"
log "Резервная копия сохранена в $SSHD_CONFIG_BACKUP"

# Настройка .ssh директории и authorized_keys для root
log "Настройка SSH ключей для root..."

# Создаем директорию .ssh если её нет
if [ ! -d "/root/.ssh" ]; then
    mkdir -p /root/.ssh
    chmod 700 /root/.ssh
    log "Создана директория /root/.ssh"
fi

# Создаем authorized_keys если его нет
if [ ! -f "$SSH_KEY_PATH" ]; then
    touch "$SSH_KEY_PATH"
    chmod 600 "$SSH_KEY_PATH"
    log "Создан файл $SSH_KEY_PATH"
fi

# Запрос публичного ключа
echo ""
warning "Вставьте ваш публичный SSH ключ (или нажмите Enter для пропуска):"
read -r SSH_PUB_KEY

if [ -n "$SSH_PUB_KEY" ]; then
    # Проверка формата ключа (простая проверка)
    if [[ "$SSH_PUB_KEY" =~ ^(ssh-rsa|ssh-ed25519|ecdsa-sha2-nistp256|ssh-dss|sk-ssh-ed25519) ]]; then
        # Проверяем, нет ли уже такого ключа
        if grep -qF "$SSH_PUB_KEY" "$SSH_KEY_PATH"; then
            warning "Этот ключ уже существует в authorized_keys"
        else
            echo "$SSH_PUB_KEY" >> "$SSH_KEY_PATH"
            log "Публичный ключ добавлен в $SSH_KEY_PATH"
        fi
    else
        error "Неверный формат SSH ключа. Ключ не добавлен."
    fi
else
    warning "Ключ не был добавлен. Вы можете добавить его позже вручную в $SSH_KEY_PATH"
fi

# Проверяем, что в authorized_keys есть хотя бы один ключ
if [ ! -s "$SSH_KEY_PATH" ]; then
    warning "Файл authorized_keys пуст! Убедитесь, что у вас есть другой способ доступа к серверу."
    read -p "Продолжить без ключей? (y/N): " CONTINUE
    if [[ ! "$CONTINUE" =~ ^[Yy]$ ]]; then
        error "Отмена операции"
        exit 1
    fi
fi

# Изменение конфигурации SSH
log "Изменение конфигурации SSH..."

# Функция для безопасного изменения параметров в sshd_config
update_sshd_config() {
    local param="$1"
    local value="$2"
    
    if grep -q "^#*${param}\s" "$SSHD_CONFIG"; then
        # Параметр существует, заменяем
        sed -i "s/^#*${param}.*/${param} ${value}/" "$SSHD_CONFIG"
    else
        # Параметр не найден, добавляем
        echo "${param} ${value}" >> "$SSHD_CONFIG"
    fi
}

# Меняем порт
update_sshd_config "Port" "$NEW_SSH_PORT"
log "Порт SSH изменен на $NEW_SSH_PORT"

# Отключаем вход по паролю
update_sshd_config "PasswordAuthentication" "no"
log "Вход по паролю отключен"

# Отключаем пустые пароли
update_sshd_config "PermitEmptyPasswords" "no"

# Отключаем ChallengeResponseAuthentication
update_sshd_config "ChallengeResponseAuthentication" "no"

# Запрещаем вход root с паролем (только по ключу)
update_sshd_config "PermitRootLogin" "prohibit-password"
log "Root доступ разрешен только по ключу"

# Дополнительные настройки безопасности
update_sshd_config "MaxAuthTries" "3"
update_sshd_config "MaxSessions" "5"
update_sshd_config "ClientAliveInterval" "300"
update_sshd_config "ClientAliveCountMax" "2"

# Включаем PubkeyAuthentication (на всякий случай)
update_sshd_config "PubkeyAuthentication" "yes"

# Проверка конфигурации
log "Проверка конфигурации SSH..."
if sshd -t; then
    log "Конфигурация SSH корректна"
else
    error "Ошибка в конфигурации SSH! Восстановление из резервной копии..."
    cp "$SSHD_CONFIG_BACKUP" "$SSHD_CONFIG"
    error "Конфигурация восстановлена. Проверьте настройки вручную."
    exit 1
fi

# Настройка фаервола UFW (если установлен)
if command -v ufw &> /dev/null; then
    log "Настройка UFW..."
    
    # Получаем текущий порт SSH
    CURRENT_SSH_PORT=$(grep -E "^Port\s+" "$SSHD_CONFIG_BACKUP" | awk '{print $2}')
    CURRENT_SSH_PORT=${CURRENT_SSH_PORT:-22}
    
    # Разрешаем новый порт
    ufw allow "$NEW_SSH_PORT"/tcp comment 'SSH'
    log "Порт $NEW_SSH_PORT/tcp разрешен в UFW"
    
    # Удаляем старый порт если он отличается
    if [ "$CURRENT_SSH_PORT" != "$NEW_SSH_PORT" ]; then
        read -p "Удалить старый порт $CURRENT_SSH_PORT из UFW? (y/N): " REMOVE_OLD
        if [[ "$REMOVE_OLD" =~ ^[Yy]$ ]]; then
            ufw delete allow "$CURRENT_SSH_PORT"/tcp
            log "Старый порт $CURRENT_SSH_PORT удален из UFW"
        fi
    fi
elif command -v firewall-cmd &> /dev/null; then
    log "Настройка firewalld..."
    firewall-cmd --permanent --add-port="$NEW_SSH_PORT"/tcp
    firewall-cmd --reload
    log "Порт $NEW_SSH_PORT/tcp разрешен в firewalld"
else
    warning "Фаервол не обнаружен. Убедитесь, что порт $NEW_SSH_PORT открыт вручную."
fi

# Перезапуск SSH сервиса
log "Перезапуск SSH сервиса..."
systemctl restart sshd

# Проверка, что SSH слушает новый порт
sleep 2
if ss -tlnp | grep -q ":$NEW_SSH_PORT"; then
    log "SSH успешно слушает порт $NEW_SSH_PORT"
else
    warning "SSH может не слушать порт $NEW_SSH_PORT. Проверьте статус: systemctl status sshd"
fi

echo ""
echo "=========================================="
log "Настройка SSH завершена!"
echo "=========================================="
echo ""
echo -e "${YELLOW}ВАЖНО: Проверьте новое подключение в новом терминале перед закрытием текущей сессии!${NC}"
echo ""
echo "Новые параметры подключения:"
echo "  Порт SSH: $NEW_SSH_PORT"
echo "  Команда для подключения: ssh -p $NEW_SSH_PORT root@$(hostname -I | awk '{print $1}')"
echo ""
echo -e "${YELLOW}Резервная копия конфигурации: $SSHD_CONFIG_BACKUP${NC}"
echo ""
echo -e "${RED}НЕ ЗАКРЫВАЙТЕ ТЕКУЩУЮ SSH СЕССИЮ, пока не проверите новое подключение!${NC}"
