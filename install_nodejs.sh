#!/bin/bash

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

print_status() { echo -e "${GREEN}[✓]${NC} $1"; }
print_error() { echo -e "${RED}[✗]${NC} $1"; }
print_info() { echo -e "${YELLOW}[→]${NC} $1"; }
print_title() { echo -e "${CYAN}=== $1 ===${NC}"; }

# Проверка прав суперпользователя
if [[ $EUID -ne 0 ]]; then
   print_error "Запустите скрипт с правами root (используйте sudo)"
   exit 1
fi

print_title "УСТАНОВКА NODE.JS ИЗ REPOSITORY NODESOURCE"

# Проверка архитектуры системы
ARCH=$(uname -m)
if [[ "$ARCH" == "aarch64" ]] || [[ "$ARCH" == "arm64" ]]; then
    NODE_ARCH="arm64"
    print_info "Обнаружена архитектура ARM64"
else
    NODE_ARCH="amd64"
    print_info "Обнаружена архитектура x86_64"
fi

# Обновление системы
print_info "Обновление списка пакетов..."
apt update

# Установка curl и зависимостей
print_info "Установка curl и необходимых зависимостей..."
apt install -y curl ca-certificates gnupg

# Очистка старых ключей (если есть)
print_info "Очистка старых ключей NodeSource..."
rm -f /etc/apt/trusted.gpg.d/nodesource.gpg 2>/dev/null
rm -f /usr/share/keyrings/nodesource.gpg 2>/dev/null
rm -f /etc/apt/sources.list.d/nodesource.list 2>/dev/null

# Добавление ключа GPG NodeSource
print_info "Добавление ключа GPG NodeSource..."
curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /usr/share/keyrings/nodesource.gpg

# Определение версии Node.js для установки
print_info "Выберите версию Node.js для установки:"
echo "  1) Node.js 22.x (последняя LTS, рекомендована)"
echo "  2) Node.js 20.x (LTS)"
echo "  3) Node.js 18.x (LTS)"
echo "  4) Node.js 23.x (текущая)"
echo "  5) Node.js 24.x (текущая)"
echo ""
read -p "Введите номер (1-5): " VERSION_CHOICE

case $VERSION_CHOICE in
    1)
        NODE_VERSION="22.x"
        ;;
    2)
        NODE_VERSION="20.x"
        ;;
    3)
        NODE_VERSION="18.x"
        ;;
    4)
        NODE_VERSION="23.x"
        ;;
    5)
        NODE_VERSION="24.x"
        ;;
    *)
        print_error "Неверный выбор. Устанавливается версия 22.x по умолчанию."
        NODE_VERSION="22.x"
        ;;
esac

# Формирование URL для репозитория
UBUNTU_VERSION=$(lsb_release -rs)
print_info "Версия Ubuntu: $UBUNTU_VERSION"

# Создание файла репозитория
print_info "Добавление репозитория NodeSource для версии $NODE_VERSION..."
REPO_URL="deb [signed-by=/usr/share/keyrings/nodesource.gpg] https://deb.nodesource.com/node_$NODE_VERSION nodistro main"
echo "$REPO_URL" > /etc/apt/sources.list.d/nodesource.list

# Обновление списка пакетов с новым репозиторием
print_info "Обновление списка пакетов после добавления репозитория..."
apt update

# Установка Node.js
print_info "Установка Node.js версии $NODE_VERSION..."
apt install -y nodejs

# Проверка установки
print_title "ПРОВЕРКА УСТАНОВКИ"
NODE_VERSION_INSTALLED=$(node --version)
NPM_VERSION=$(npm --version)

print_status "Node.js установлен: $NODE_VERSION_INSTALLED"
print_status "npm установлен: $NPM_VERSION"

# Установка дополнительных утилит
print_info "Установка полезных глобальных пакетов..."
npm install -g npm@latest
npm install -g yarn 2>/dev/null || print_info "Yarn не установлен (опционально)"
npm install -g pm2 2>/dev/null || print_info "PM2 не установлен (опционально)"

print_title "ГОТОВО! 🚀"
echo ""
print_status "Node.js успешно установлен из репозитория NodeSource"
print_info "Версия Node.js: $(node --version)"
print_info "Версия npm: $(npm --version)"
echo ""
print_info "Используйте следующие команды:"
echo "  node --version    # Проверить версию Node.js"
echo "  npm --version     # Проверить версию npm"
echo "  npx --version     # Проверить версию npx"
