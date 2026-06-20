# ServerTools

Набор скриптов для управления Linux серверами.

## Скрипты

### add_user.sh

Создание пользователя в Ubuntu с SSH ключом и sudo доступом (NOPASSWD).

**Запросы:**
1. Имя пользователя
2. Публичный SSH ключ
3. Добавление в sudo (y/n) — если да, то с NOPASSWD

**Установка и запуск:**

```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/vitebc/ServerTools/main/add_user.sh)"
```

Или:

```bash
curl -fsSL https://raw.githubusercontent.com/vitebc/ServerTools/main/add_user.sh -o add_user.sh
chmod +x add_user.sh
sudo ./add_user.sh
```

### install-docker.sh

Установка Docker

```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/vitebc/ServerTools/main/install-docker.sh)"
```

```bash
curl -fsSL https://gist.githubusercontent.com/vitebc/ServerTools/main/install-docker.sh | sudo bash
```

### security-setup.sh

Установка Fail2ban и Firewall (UFW)

```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/vitebc/ServerTools/main/security-setup.sh)"
```

```bash
wget https://raw.githubusercontent.com/vitebc/ServerTools/main/security-setup.sh
chmod +x security-setup.sh
sudo ./security-setup.sh
```
