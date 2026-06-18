#!/bin/bash
# ==================================================
# Скрипт установки Docker CE на Ubuntu Server
# Поддерживает: Ubuntu 20.04, 22.04, 24.04
# ==================================================

set -e  # Остановка при любой ошибке

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Функция вывода сообщений
print_status() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

print_step() {
    echo -e "\n${YELLOW}===>${NC} $1"
}

# Проверка прав root
if [[ $EUID -ne 0 ]]; then
   print_error "Этот скрипт должен запускаться с правами root (sudo)"
   exit 1
fi

# Проверка ОС
if ! lsb_release -d | grep -q "Ubuntu"; then
    print_error "Скрипт предназначен только для Ubuntu Server"
    exit 1
fi

UBUNTU_VERSION=$(lsb_release -rs)
print_status "Обнаружена Ubuntu $UBUNTU_VERSION"

# Проверка наличия уже установленного Docker
if command -v docker &> /dev/null; then
    print_warning "Docker уже установлен"
    CURRENT_VERSION=$(docker --version)
    echo "Текущая версия: $CURRENT_VERSION"
    read -p "Хотите переустановить? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_status "Установка отменена"
        exit 0
    fi
    # Удаление старой версии
    print_step "Удаление старой версии Docker"
    apt-get remove -y docker docker-engine docker.io containerd runc || true
fi

# 1. Обновление системы
print_step "Обновление списка пакетов"
apt-get update

# 2. Установка зависимостей
print_step "Установка зависимостей"
apt-get install -y \
    ca-certificates \
    curl \
    gnupg \
    lsb-release

# 3. Добавление GPG ключа Docker
print_step "Добавление GPG ключа Docker"
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

# 4. Добавление репозитория Docker
print_step "Добавление официального репозитория Docker"
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null

# 5. Обновление с новым репозиторием
print_step "Обновление списка пакетов (с репозиторием Docker)"
apt-get update

# 6. Установка Docker
print_step "Установка Docker Engine"
apt-get install -y \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin

# 7. Проверка установки
print_step "Проверка установки"
if docker run --rm hello-world &> /dev/null; then
    print_status "Docker установлен и работает корректно!"
else
    print_error "Проверка Docker не прошла"
    exit 1
fi

# 8. Настройка автозапуска
print_step "Настройка автозапуска Docker"
systemctl enable docker
systemctl start docker
systemctl enable containerd
systemctl start containerd

# 9. Добавление пользователя в группу docker (опционально)
print_step "Настройка прав пользователя"
if [[ -n "$SUDO_USER" ]]; then
    USERNAME="$SUDO_USER"
else
    USERNAME=$(whoami)
fi

if [[ "$USERNAME" != "root" ]]; then
    usermod -aG docker "$USERNAME"
    print_status "Пользователь '$USERNAME' добавлен в группу 'docker'"
    print_warning "Для применения прав выйдите и зайдите заново или выполните: newgrp docker"
fi

# 10. Вывод информации
echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}✅ Установка Docker завершена!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "Версия Docker: $(docker --version)"
echo -e "Версия Compose: $(docker compose version)"
echo -e "\nПолезные команды:"
echo -e "  docker --version          - Проверить версию Docker"
echo -e "  docker compose version    - Проверить версию Docker Compose"
echo -e "  docker ps                 - Список запущенных контейнеров"
echo -e "  docker images             - Список образов"
echo -e "\n${YELLOW}Теперь вы можете запускать Docker без sudo (после перезахода)${NC}"
echo -e "${GREEN}========================================${NC}"
