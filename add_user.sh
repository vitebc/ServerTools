#!/usr/bin/env bash
# ============================================================
# add_user.sh — создание пользователя в Ubuntu с SSH ключами
# Использование:
#   sudo bash add_user.sh                          — мастер создания пользователя
#   sudo bash add_user.sh --keygen [метка]         — только генерация ключей  
#   curl -fsSL https://raw.githubusercontent.com/vitebc/ServerTools/main/add_user.sh | sudo bash
# ============================================================
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log_ok()   { echo -e "${GREEN}✅ $1${NC}"; }
log_err()  { echo -e "${RED}❌ $1${NC}"; }
log_warn() { echo -e "${YELLOW}⚠️ $1${NC}"; }
log_info() { echo -e "${CYAN}ℹ️ $1${NC}"; }
separator() { echo -e "\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"; }

# ==========================================
# Режим: только генерация ключей
# ==========================================
if [ "${1:-}" = "--keygen" ]; then
    LABEL="${2:-key}"
    KEY_DIR="/tmp/ssh-keys-$LABEL"
    mkdir -p "$KEY_DIR"
    
    echo -e "${CYAN}🔑 Генерация SSH ключей (ed25519)${NC}"
    echo -e "   Метка: $LABEL"
    echo -e "   Файлы: $KEY_DIR/id_ed25519*\n"
    
    ssh-keygen -t ed25519 -f "$KEY_DIR/id_ed25519" -N "" -C "$LABEL" -q
    
    separator
    echo -e "${GREEN}=== Публичный ключ ===${NC}"
    cat "$KEY_DIR/id_ed25519.pub"
    echo ""
    echo -e "${RED}=== Приватный ключ (НИКОМУ НЕ ПОКАЗЫВАЙ!) ===${NC}"
    cat "$KEY_DIR/id_ed25519"
    echo ""
    separator
    echo -e "📁 Ключи сохранены: $KEY_DIR/"
    echo -e "   Использование: ssh -i $KEY_DIR/id_ed25519 user@host"
    exit 0
fi

# ==========================================
# Проверка root
# ==========================================
if [ "$(id -u)" -ne 0 ]; then
    log_err "Запустите скрипт от root: sudo bash $0"
    exit 1
fi

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
# ШАГ 2: Способ добавления SSH ключа
# ==========================================
echo "Выберите способ добавления SSH ключа:"
echo "  1) Вставить готовый публичный ключ"
echo "  2) Сгенерировать новую пару ключей"
echo "  3) Пропустить (без SSH доступа)"
while true; do
    read -p "Ваш выбор (1/2/3): " SSH_CHOICE
    case $SSH_CHOICE in
        1) SSH_MODE="paste"; break;;
        2) SSH_MODE="generate"; break;;
        3) SSH_MODE="none"; break;;
        *) log_warn "Введите 1, 2 или 3";;
    esac
done
echo ""

case $SSH_MODE in
    paste)
        read -p "Вставьте публичную часть ключа (ssh-ed25519 AAAA...): " SSH_KEY
        if [ -z "$SSH_KEY" ]; then
            log_warn "Ключ пустой. Без SSH доступа."
            HAS_KEY=false
        else
            HAS_KEY=true
        fi
        ;;
    generate)
        HAS_KEY=true
        SSH_DIR="/home/$USERNAME/.ssh"
        KEY_FILE="$SSH_DIR/id_ed25519"
        echo "Генерирую ключи ed25519..."
        mkdir -p "$SSH_DIR"
        ssh-keygen -t ed25519 -f "$KEY_FILE" -N "" -C "$USERNAME@$(hostname)" -q
        SSH_KEY=$(cat "${KEY_FILE}.pub")
        PRIV_KEY=$(cat "$KEY_FILE")
        chmod 600 "$KEY_FILE"
        chmod 644 "${KEY_FILE}.pub"
        chown -R "$USERNAME":"$USERNAME" "$SSH_DIR" 2>/dev/null || true
        separator
        echo -e "${GREEN}=== Сгенерирован публичный ключ ===${NC}"
        echo "$SSH_KEY"
        echo ""
        echo -e "${RED}=== Приватный ключ (НИКОМУ НЕ ПОКАЗЫВАЙ) ===${NC}"
        echo "$PRIV_KEY"
        separator
        echo -e "${CYAN}📁 Ключи сохранены:${NC}"
        echo -e "   Приватный: $KEY_FILE"
        echo -e "   Публичный: ${KEY_FILE}.pub"
        echo -e "${YELLOW}⚠️  Приватный ключ будет показан ещё раз в конце!${NC}"
        ;;
    none)
        HAS_KEY=false
        log_warn "Пользователь будет создан без SSH доступа."
        echo "   Его можно добавить позже: echo \"ключ\" >> /home/$USERNAME/.ssh/authorized_keys"
        ;;
esac
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

# ==========================================
# Подтверждение
# ==========================================
separator
echo -e "  ${CYAN}Проверьте параметры:${NC}"
echo -e "  ${CYAN}Имя:${NC}          $USERNAME"
echo -e "  ${CYAN}SSH ключ:${NC}     $([ "$HAS_KEY" = true ] && ( [ "$SSH_MODE" = "generate" ] && echo "сгенерирован" || echo "добавлен" ) || echo "нет")"
echo -e "  ${CYAN}Sudo группа:${NC}  $([ "$ADD_SUDO" = true ] && echo "да (NOPASSWD)" || echo "нет")"
separator
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
    echo "$SSH_KEY" > "$USER_SSH_DIR/authorized_keys"
    chmod 700 "$USER_SSH_DIR"
    chmod 600 "$USER_SSH_DIR/authorized_keys"
    chown -R "$USERNAME":"$USERNAME" "$USER_SSH_DIR"
    log_ok "SSH ключ добавлен в $USER_SSH_DIR/authorized_keys"
fi

# Группа sudo
if [ "$ADD_SUDO" = true ]; then
    usermod -aG sudo "$USERNAME"
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
echo -e "  ${CYAN}Подключение:${NC} ssh $USERNAME@<IP> -p <port>"

# Если генерировали ключи — показать приватный ещё раз
if [ "$SSH_MODE" = "generate" ]; then
    echo ""
    separator
    echo -e "${RED}=== Приватный ключ (сохрани в ~/.ssh/id_ed25519_$USERNAME) ===${NC}"
    echo "$PRIV_KEY"
    echo ""
    echo -e "${YELLOW}chmod 600 ~/.ssh/id_ed25519_$USERNAME${NC}"
    echo -e "${YELLOW}ssh -i ~/.ssh/id_ed25519_$USERNAME $USERNAME@<IP>${NC}"
    separator
fi
