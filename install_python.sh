#!/bin/bash

# Цвета для красивого вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Функция для вывода сообщений
print_status() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

print_info() {
    echo -e "${YELLOW}[→]${NC} $1"
}

# Проверка прав суперпользователя
if [[ $EUID -ne 0 ]]; then
   print_error "Этот скрипт должен запускаться с правами root (используйте sudo)"
   exit 1
fi

print_info "Начинается установка Python на Ubuntu Server..."

# Обновление системы
print_info "Обновление списка пакетов..."
apt update

# Установка Python и основных пакетов
print_info "Установка Python 3, pip и необходимых пакетов..."
apt install -y \
    python3 \
    python3-pip \
    python3-dev \
    python3-venv \
    build-essential \
    libssl-dev \
    libffi-dev \
    libbz2-dev \
    libreadline-dev \
    libsqlite3-dev \
    libncurses5-dev \
    libgdbm-dev \
    zlib1g-dev \
    uuid-dev \
    tk-dev

# Проверка установки
print_info "Проверка установленных версий..."
PYTHON_VERSION=$(python3 --version 2>&1 | awk '{print $2}')
PIP_VERSION=$(pip3 --version 2>&1 | awk '{print $2}')

if [ $? -eq 0 ]; then
    print_status "Python версия: $PYTHON_VERSION"
    print_status "pip версия: $PIP_VERSION"
else
    print_error "Ошибка при установке Python!"
    exit 1
fi

# Обновление pip до последней версии
print_info "Обновление pip до последней версии..."
pip3 install --upgrade pip

# Создание символической ссылки для удобства (опционально)
if ! command -v python &> /dev/null; then
    print_info "Создание символической ссылки python -> python3"
    ln -sf /usr/bin/python3 /usr/bin/python
fi

# Установка полезных пакетов для разработки
print_info "Установка полезных пакетов..."
pip3 install --upgrade \
    setuptools \
    wheel \
    virtualenv

print_status "Установка Python успешно завершена!"
print_status "Python: $(python --version 2>&1)"
print_status "pip: $(pip --version 2>&1)"

echo ""
print_info "Для создания виртуального окружения используйте:"
echo "  python3 -m venv myenv"
echo "  source myenv/bin/activate"
