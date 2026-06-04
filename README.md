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
