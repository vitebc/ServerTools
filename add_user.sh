#!/usr/bin/env bash
# ============================================================
# add_user.sh — создание пользователя в Ubuntu
# Использование: sudo bash add_user.sh
# или: sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/vitebc/ServerTools/main/add_user.sh)"
# ============================================================
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_ok()   { echo -e "${GREEN}✅ $1${NC}"; }
log_err()  { echo -e "${RED}❌ $1${NC}"; }
log_warn() { echo -e "${YELLOW}⚠️ $1${NC}"; }

# Проверка root
if [ "$(id -u)" -ne 0 ]; then
    log_err "Запустите скрипт от root: sudo bash $0"
    exit 1
fi

# Проверка ОС
if [ ! -f /etc/os-release ]; then
    log_err "Не удалось определить ОС"
    exit 1
fi
. /etc/os-release
log_ok "ОС: $NAME $VERSION"

echo ""

# ==========================================
# ШАГ 1: Имя пользователя
# ==========================================
while true; do
    read -p "Введите имя пользователя: " USERNAME
    if [ -z "$USERNAME" ]; then
        log_warn "Имя не может быть пустым"
        continue
    fi
    if id "$USERNAME" &>/dev/null 2>&1; then
        log_warn "Пользователь $USERNAME уже существует"
    fi
    break
done

echo ""

# ==========================================
# ШАГ 2: Публичный SSH ключ
# ==========================================
read -p "Вставьте публичную часть SSH ключа (ssh-ed25519 AAAA...): " SSH_KEY
if [ -z "$SSH_KEY" ]; then
    log_warn "Ключ не введён. Пользователь будет создан без SSH доступа."
    echo "   Его можно добавить позже: echo \"ключ\" >> /home/$USERNAME/.ssh/authorized_keys"
    HAS_KEY=false
else
    HAS_KEY=true
fi

echo ""

# ==========================================
# ШАГ 3: Sudo доступ
# ==========================================
while true; do
    read -p "Добавить пользователя в группу sudo? (y/n): " SUDO_CHOICE
    case $SUDO_CHOICE in
        [Yy]* ) ADD_SUDO=true; break;;
        [Nn]* ) ADD_SUDO=false; break;;
        * ) log_warn "Введите y или n";;
    esac
done

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Проверьте параметры:"
echo "  Имя:          $USERNAME"
echo "  SSH ключ:     $([ "$HAS_KEY" = true ] && echo "да" || echo "нет")"
echo "  Sudo группа:  $([ "$ADD_SUDO" = true ] && echo "да (NOPASSWD)" || echo "нет")"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
read -p "Продолжить? (y/n): " CONFIRM
case $CONFIRM in
    [Yy]* ) ;;
    * ) log_warn "Отменено"; exit 0;;
esac

# ==========================================
# Создание пользователя
# ==========================================
echo ""
if ! id "$USERNAME" &>/dev/null 2>&1; then
    useradd -m -s /bin/bash "$USERNAME"
    log_ok "Пользователь $USERNAME создан"
else
    log_ok "Пользователь $USERNAME уже существует"
fi

# SSH ключ
if [ "$HAS_KEY" = true ]; then
    USER_SSH_DIR="/home/$USERNAME/.ssh"
    mkdir -p "$USER_SSH_DIR"
    echo "$SSH_KEY" >> "$USER_SSH_DIR/authorized_keys"
    chmod 700 "$USER_SSH_DIR"
    chmod 600 "$USER_SSH_DIR/authorized_keys"
    chown -R "$USERNAME":"$USERNAME" "$USER_SSH_DIR"
    log_ok "SSH ключ добавлен в $USER_SSH_DIR/authorized_keys"
fi

# Группа sudo
if [ "$ADD_SUDO" = true ]; then
    usermod -aG sudo "$USERNAME"
    
    # Добавляем NOPASSWD если ещё нет
    SUDOERS_FILE="/etc/sudoers.d/$USERNAME"
    if [ ! -f "$SUDOERS_FILE" ]; then
        echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" > "$SUDOERS_FILE"
        chmod 440 "$SUDOERS_FILE"
        log_ok "Пользователь добавлен в sudo (NOPASSWD)"
    else
        log_ok "Правило sudo уже существует"
    fi
fi

echo ""
log_ok "Готово! Пользователь $USERNAME настроен."
echo ""
echo "  Подключение: ssh $USERNAME@<IP> -p <port>"
