#!/bin/bash
#################### x-ui-pro-reality v1.0 (RU) @ github.com/GFW4Fun #################################
[[ $EUID -ne 0 ]] && echo "Запустите с правами root!" && sudo su -
##############################INFO######################################################################
msg_ok()   { echo -e "\e[1;42m $1 \e[0m"; }
msg_err()  { echo -e "\e[1;41m $1 \e[0m"; }
msg_inf()  { echo -e "\e[1;34m$1\e[0m"; }
echo; msg_inf '           ___    _   _   _  '	;
msg_inf		 ' \/ __ | |  | __ |_) |_) / \ '	;
msg_inf		 ' /\    |_| _|_   |   | \ \_/ '	; echo
##################################Variables#############################################################
XUIDB="/etc/x-ui/x-ui.db"
domain=""
UNINSTALL="x"
INSTALL="n"
AUTODOMAIN="n"
reality_domain=""
Pak=$(type apt &>/dev/null && echo "apt" || echo "yum")

##################################Functions#############################################################
gen_random_string() {
    local length="$1"
    head -c 4096 /dev/urandom | tr -dc 'a-zA-Z0-9' | head -c "$length"
    echo
}
get_port() {
    echo $(( ((RANDOM<<15)|RANDOM) % 49152 + 10000 ))
}
check_free() {
    local port=$1
    nc -z 127.0.0.1 $port &>/dev/null
    return $?
}
make_port() {
    while true; do
        PORT=$(get_port)
        if ! check_free $PORT; then 
            echo $PORT
            break
        fi
    done
}
arch() {
    case "$(uname -m)" in
        x86_64 | x64 | amd64) echo 'amd64' ;;
        i*86 | x86) echo '386' ;;
        armv8* | armv8 | arm64 | aarch64) echo 'arm64' ;;
        armv7* | armv7 | arm) echo 'armv7' ;;
        armv6* | armv6) echo 'armv6' ;;
        armv5* | armv5) echo 'armv5' ;;
        s390x) echo 's390x' ;;
        *) echo -e "${green}Неподдерживаемая архитектура CPU! ${plain}" && exit 1 ;;
    esac
}

UNINSTALL_XUI(){
    printf 'y\n' | x-ui uninstall
    rm -rf "/etc/x-ui/" "/usr/local/x-ui/" "/usr/bin/x-ui/"
    $Pak -y remove nginx nginx-common nginx-core nginx-full python3-certbot-nginx
    $Pak -y purge nginx nginx-common nginx-core nginx-full python3-certbot-nginx
    $Pak -y autoremove
    $Pak -y autoclean
    rm -rf "/var/www/html/" "/etc/nginx/" "/usr/share/nginx/" 
    clear && msg_ok "Полное удаление выполнено!" && exit 1
}

install_panel() {
    # --- generate ports and paths ---
    panel_port=$(make_port)
    panel_path=$(gen_random_string 10)
    config_username=$(gen_random_string 10)
    config_password=$(gen_random_string 10)

    # --- stop and clean old services ---
    systemctl stop x-ui 2>/dev/null
    rm -rf /etc/systemd/system/x-ui.service
    rm -rf /usr/local/x-ui
    rm -rf /etc/x-ui
    rm -rf /etc/nginx/sites-enabled/*
    rm -rf /etc/nginx/sites-available/*
    rm -rf /etc/nginx/stream-enabled/*

    # --- install packages ---
    ufw disable
    $Pak -y update
    $Pak -y install curl wget jq bash sudo nginx-full certbot python3-certbot-nginx sqlite3 ufw
    systemctl daemon-reload && systemctl enable --now nginx
    systemctl stop nginx 
    fuser -k 80/tcp 80/udp 443/tcp 443/udp 2>/dev/null

    # --- get IPv4 ---
    IP4_REGEX="^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$"
    IP4=$(ip route get 8.8.8.8 2>&1 | grep -Po -- 'src \K\S*')
    [[ $IP4 =~ $IP4_REGEX ]] || IP4=$(curl -s ipv4.icanhazip.com);

    # --- domain handling ---
    if [[ ${AUTODOMAIN} == *"y"* ]]; then
        domain="${IP4}.cdn-one.org"
        reality_domain="${IP4//./-}.cdn-one.org"
    else
        while true; do	
            if [[ -n "$domain" ]]; then
                break
            fi
            echo -en "Введите доступный поддомен (sub.domain.tld): " && read domain 
        done
        domain=$(echo "$domain" 2>&1 | tr -d '[:space:]' )
        while true; do	
            if [[ -n "$reality_domain" ]]; then
                break
            fi
            echo -en "Введите доступный поддомен для REALITY (sub.domain.tld): " && read reality_domain 
        done
        reality_domain=$(echo "$reality_domain" 2>&1 | tr -d '[:space:]' )
    fi

    # --- resolve check for auto domain ---
    resolve_to_ip () {
        local host="$1"
        local a
        a=$(getent ahostsv4 "$host" 2>/dev/null | awk 'NR==1{print $1}')
        [[ -n "$a" ]] && [[ "$a" == "$IP4" ]]
    }
    if [[ ${AUTODOMAIN} == *"y"* ]]; then
        if ! resolve_to_ip "$domain"; then
            msg_err "Авто-домен $domain не резолвится на IP этого сервера ($IP4). Исправьте DNS/сервис и повторите."
            exit 1
        fi
        if ! resolve_to_ip "$reality_domain"; then
            msg_err "Авто-домен $reality_domain не резолвится на IP этого сервера ($IP4). Исправьте DNS/сервис и повторите."
            exit 1
        fi
    fi

    # --- SSL ---
    certbot certonly --standalone --non-interactive --agree-tos --register-unsafely-without-email -d "$domain"
    if [[ ! -d "/etc/letsencrypt/live/${domain}/" ]]; then
        systemctl start nginx >/dev/null 2>&1
        msg_err "Не удалось сгенерировать SSL для домена $domain! Проверьте домен/IP или введите новый домен." && exit 1
    fi
    certbot certonly --standalone --non-interactive --agree-tos --register-unsafely-without-email -d "$reality_domain"
    if [[ ! -d "/etc/letsencrypt/live/${reality_domain}/" ]]; then
        systemctl start nginx >/dev/null 2>&1
        msg_err "Не удалось сгенерировать SSL для домена $reality_domain! Проверьте домен/IP или введите новый домен." && exit 1
    fi

    # --- nginx config ---
    mkdir -p /root/cert/${domain}
    chmod 755 /root/cert/*
    ln -s /etc/letsencrypt/live/${domain}/fullchain.pem /root/cert/${domain}/fullchain.pem
    ln -s /etc/letsencrypt/live/${domain}/privkey.pem /root/cert/${domain}/privkey.pem

    mkdir -p /etc/nginx/stream-enabled
    cat > "/etc/nginx/stream-enabled/stream.conf" << EOF
map \$ssl_preread_server_name \$sni_name {
    hostnames;
    ${reality_domain}      xray;
    ${domain}           www;
    default              xray;
}
upstream xray {
    server 127.0.0.1:8443;
}
upstream www {
    server 127.0.0.1:7443;
}
server {
    proxy_protocol on;
    set_real_ip_from unix:;
    listen          443;
    listen         [::]:443;
    proxy_pass      \$sni_name;
    ssl_preread     on;
}
EOF

    grep -xqFR "stream { include /etc/nginx/stream-enabled/*.conf; }" /etc/nginx/* ||echo "stream { include /etc/nginx/stream-enabled/*.conf; }" >> /etc/nginx/nginx.conf
    grep -xqFR "load_module modules/ngx_stream_module.so;" /etc/nginx/* || sed -i '1s/^/load_module \/usr\/lib\/nginx\/modules\/ngx_stream_module.so; /' /etc/nginx/nginx.conf
    grep -xqFR "worker_rlimit_nofile 16384;" /etc/nginx/* ||echo "worker_rlimit_nofile 16384;" >> /etc/nginx/nginx.conf
    sed -i "/worker_connections/c\worker_connections 4096;" /etc/nginx/nginx.conf

    cat > "/etc/nginx/sites-available/80.conf" << EOF
server {
    listen 80;
    server_name ${domain} ${reality_domain};
    return 301 https://\$host\$request_uri;
}
EOF

    cat > "/etc/nginx/sites-available/${domain}" << EOF
server {
    server_tokens off;
    server_name ${domain};
    listen 7443 ssl http2 proxy_protocol;
    listen [::]:7443 ssl http2 proxy_protocol;
    index index.html index.htm index.php index.nginx-debian.html;
    root /var/www/html/;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!eNULL:!MD5:!DES:!RC4:!ADH:!SSLv3:!EXP:!PSK:!DSS;
    ssl_certificate /etc/letsencrypt/live/$domain/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$domain/privkey.pem;
    if (\$host !~* ^(.+\.)?$domain\$ ){return 444;}
    if (\$scheme ~* https) {set \$safe 1;}
    if (\$ssl_server_name !~* ^(.+\.)?$domain\$ ) {set \$safe "\${safe}0"; }
    if (\$safe = 10){return 444;}
    if (\$request_uri ~ "(\"|'|\`|~|,|:|;|%|\\$|&&|\?\?|0x00|0X00|\||\\|\{|\}|\[|\]|<|>|\.\.\.|\.\.\/|\/\/\/)"){set \$hack 1;}
    error_page 400 401 402 403 500 501 502 503 504 =404 /404;
    proxy_intercept_errors on;
    location /${panel_path}/ {
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Upgrade websocket;
        proxy_set_header Connection Upgrade;		
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
        proxy_pass https://127.0.0.1:${panel_port};
        break;
    }
    location /${panel_path} {
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Upgrade websocket;
        proxy_set_header Connection Upgrade;		
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
        proxy_pass https://127.0.0.1:${panel_port};
        break;
    }
    location / { try_files \$uri \$uri/ =404; }
}
EOF

    cat > "/etc/nginx/sites-available/${reality_domain}" << EOF
server {
    server_tokens off;
    server_name ${reality_domain};
    listen 9443 ssl http2;
    listen [::]:9443 ssl http2;
    index index.html index.htm index.php index.nginx-debian.html;
    root /var/www/html/;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!eNULL:!MD5:!DES:!RC4:!ADH:!SSLv3:!EXP:!PSK:!DSS;
    ssl_certificate /etc/letsencrypt/live/$reality_domain/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$reality_domain/privkey.pem;
    if (\$host !~* ^(.+\.)?${reality_domain}\$ ){return 444;}
    if (\$scheme ~* https) {set \$safe 1;}
    if (\$ssl_server_name !~* ^(.+\.)?${reality_domain}\$ ) {set \$safe "\${safe}0"; }
    if (\$safe = 10){return 444;}
    if (\$request_uri ~ "(\"|'|\`|~|,|:|;|%|\\$|&&|\?\?|0x00|0X00|\||\\|\{|\}|\[|\]|<|>|\.\.\.|\.\.\/|\/\/\/)"){set \$hack 1;}
    error_page 400 401 402 403 500 501 502 503 504 =404 /404;
    proxy_intercept_errors on;
    location / { try_files \$uri \$uri/ =404; }
}
EOF

    # --- enable nginx sites ---
    if [[ -f "/etc/nginx/sites-available/${domain}" ]]; then
        unlink "/etc/nginx/sites-enabled/default" >/dev/null 2>&1
        rm -f "/etc/nginx/sites-enabled/default" "/etc/nginx/sites-available/default"
        ln -s "/etc/nginx/sites-available/${domain}" "/etc/nginx/sites-enabled/" 2>/dev/null
        ln -s "/etc/nginx/sites-available/${reality_domain}" "/etc/nginx/sites-enabled/" 2>/dev/null
        ln -s "/etc/nginx/sites-available/80.conf" "/etc/nginx/sites-enabled/" 2>/dev/null
    else
        msg_err "Конфигурация nginx для домена ${domain} не найдена!" && exit 1
    fi
    if [[ $(nginx -t 2>&1 | grep -o 'successful') != "successful" ]]; then
        msg_err "Конфигурация nginx неверна!" && exit 1
    else
        systemctl start nginx 
    fi

    # --- install x-ui panel ---
    apt-get update && apt-get install -y -q wget curl tar tzdata
    cd /usr/local/
    tag_version=$(curl -Ls "https://api.github.com/repos/MHSanaei/3x-ui/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    if [[ ! -n "$tag_version" ]]; then
        tag_version=$(curl -4 -Ls "https://api.github.com/repos/MHSanaei/3x-ui/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
        if [[ ! -n "$tag_version" ]]; then
            msg_err "Не удалось получить версию x-ui. Попробуйте позже." && exit 1
        fi
    fi
    msg_inf "Получена последняя версия x-ui: ${tag_version}, начинаем установку..."
    wget -N -O /usr/local/x-ui-linux-$(arch).tar.gz https://github.com/MHSanaei/3x-ui/releases/download/${tag_version}/x-ui-linux-$(arch).tar.gz
    if [[ $? -ne 0 ]]; then
        msg_err "Не удалось скачать x-ui. Проверьте доступ к GitHub." && exit 1
    fi
    wget -O /usr/bin/x-ui-temp https://raw.githubusercontent.com/MHSanaei/3x-ui/main/x-ui.sh
    if [[ $? -ne 0 ]]; then
        msg_err "Не удалось скачать x-ui.sh" && exit 1
    fi

    if [[ -e /usr/local/x-ui/ ]]; then
        systemctl stop x-ui 2>/dev/null
        rm /usr/local/x-ui/ -rf
    fi
    tar zxvf x-ui-linux-$(arch).tar.gz
    rm x-ui-linux-$(arch).tar.gz -f
    cd x-ui
    chmod +x x-ui
    chmod +x x-ui.sh
    if [[ $(arch) == "armv5" || $(arch) == "armv6" || $(arch) == "armv7" ]]; then
        mv bin/xray-linux-$(arch) bin/xray-linux-arm
        chmod +x bin/xray-linux-arm
    fi
    chmod +x x-ui bin/xray-linux-$(arch)
    mv -f /usr/bin/x-ui-temp /usr/bin/x-ui
    chmod +x /usr/bin/x-ui

    cp -f x-ui.service.debian /etc/systemd/system/x-ui.service
    systemctl daemon-reload
    systemctl enable x-ui
    systemctl start x-ui

    msg_ok "Установка x-ui ${tag_version} завершена."

    # --- generate reality keys and update database ---
    x-ui stop
    output=$(/usr/local/x-ui/bin/xray-linux-amd64 x25519)
    private_key=$(echo "$output" | grep "^PrivateKey:" | awk '{print $2}')
    public_key=$(echo "$output" | grep "^Password" | awk '{print $3}')
    client_id=$(/usr/local/x-ui/bin/xray-linux-amd64 uuid)
    emoji_flag=$(LC_ALL=en_US.UTF-8 curl -s https://ipwho.is/ | jq -r '.flag.emoji')
    shor=($(openssl rand -hex 8) $(openssl rand -hex 8) $(openssl rand -hex 8) $(openssl rand -hex 8) $(openssl rand -hex 8) $(openssl rand -hex 8) $(openssl rand -hex 8) $(openssl rand -hex 8))

    sqlite3 $XUIDB <<EOF
INSERT INTO "settings" ("key", "value") VALUES ("webListen",  '');
INSERT INTO "settings" ("key", "value") VALUES ("webDomain",  '');
INSERT INTO "settings" ("key", "value") VALUES ("webCertFile",  '');
INSERT INTO "settings" ("key", "value") VALUES ("webKeyFile",  '');
INSERT INTO "settings" ("key", "value") VALUES ("sessionMaxAge",  '60');
INSERT INTO "settings" ("key", "value") VALUES ("pageSize",  '50');
INSERT INTO "settings" ("key", "value") VALUES ("expireDiff",  '0');
INSERT INTO "settings" ("key", "value") VALUES ("trafficDiff",  '0');
INSERT INTO "settings" ("key", "value") VALUES ("remarkModel",  '-ieo');
INSERT INTO "settings" ("key", "value") VALUES ("tgBotEnable",  'false');
INSERT INTO "settings" ("key", "value") VALUES ("tgBotToken",  '');
INSERT INTO "settings" ("key", "value") VALUES ("tgBotProxy",  '');
INSERT INTO "settings" ("key", "value") VALUES ("tgBotAPIServer",  '');
INSERT INTO "settings" ("key", "value") VALUES ("tgBotChatId",  '');
INSERT INTO "settings" ("key", "value") VALUES ("tgRunTime",  '@daily');
INSERT INTO "settings" ("key", "value") VALUES ("tgBotBackup",  'false');
INSERT INTO "settings" ("key", "value") VALUES ("tgBotLoginNotify",  'true');
INSERT INTO "settings" ("key", "value") VALUES ("tgCpu",  '80');
INSERT INTO "settings" ("key", "value") VALUES ("tgLang",  'en-US');
INSERT INTO "settings" ("key", "value") VALUES ("timeLocation",  'Europe/Moscow');
INSERT INTO "settings" ("key", "value") VALUES ("secretEnable",  'false');
INSERT INTO "settings" ("key", "value") VALUES ("subDomain",  '');
INSERT INTO "settings" ("key", "value") VALUES ("subCertFile",  '');
INSERT INTO "settings" ("key", "value") VALUES ("subKeyFile",  '');
INSERT INTO "settings" ("key", "value") VALUES ("subUpdates",  '12');
INSERT INTO "settings" ("key", "value") VALUES ("subEncrypt",  'false');
INSERT INTO "settings" ("key", "value") VALUES ("subShowInfo",  'false');
INSERT INTO "settings" ("key", "value") VALUES ("subJsonFragment",  '');
INSERT INTO "settings" ("key", "value") VALUES ("subJsonNoises",  '');
INSERT INTO "settings" ("key", "value") VALUES ("subJsonMux",  '');
INSERT INTO "settings" ("key", "value") VALUES ("subJsonRules",  '');
INSERT INTO "settings" ("key", "value") VALUES ("datepicker",  'gregorian');
INSERT INTO "client_traffics" ("inbound_id","enable","email","up","down","expiry_time","total","reset") VALUES ('1','1','first','0','0','0','0','0');
INSERT INTO "inbounds" ("user_id","up","down","total","remark","enable","expiry_time","listen","port","protocol","settings","stream_settings","tag","sniffing") VALUES ( 
'1','0','0','0','${emoji_flag} reality','1','0','','8443','vless',
'{
  "clients": [
    {
      "id": "${client_id}",
      "flow": "xtls-rprx-vision",
      "email": "first",
      "limitIp": 0,
      "totalGB": 0,
      "expiryTime": 0,
      "enable": true,
      "tgId": "",
      "subId": "first",
      "reset": 0,
      "created_at": 1756726925000,
      "updated_at": 1756726925000
    }
  ],
  "decryption": "none",
  "fallbacks": []
}',
'{
  "network": "tcp",
  "security": "reality",
  "externalProxy": [
    {
      "forceTls": "same",
      "dest": "${domain}",
      "port": 443,
      "remark": ""
    }
  ],
  "realitySettings": {
    "show": false,
    "xver": 0,
    "target": "127.0.0.1:9443",
    "serverNames": [
      "$reality_domain"
    ],
    "privateKey": "${private_key}",
    "minClient": "",
    "maxClient": "",
    "maxTimediff": 0,
    "shortIds": [
      "${shor[0]}",
      "${shor[1]}",
      "${shor[2]}",
      "${shor[3]}",
      "${shor[4]}",
      "${shor[5]}",
      "${shor[6]}",
      "${shor[7]}"
    ],
    "settings": {
      "publicKey": "${public_key}",
      "fingerprint": "chrome",
      "serverName": "",
      "spiderX": "/"
    }
  },
  "tcpSettings": {
    "acceptProxyProtocol": true,
    "header": {
      "type": "none"
    }
  }
}',
'inbound-8443',
'{
  "enabled": false,
  "destOverride": [
    "http",
    "tls",
    "quic",
    "fakedns"
  ],
  "metadataOnly": false,
  "routeOnly": false
}'
);
EOF

    /usr/local/x-ui/x-ui setting -username "${config_username}" -password "${config_password}" -port "${panel_port}" -webBasePath "${panel_path}"
    /usr/local/x-ui/x-ui cert -webCert "/root/cert/${domain}/fullchain.pem" -webCertKey "/root/cert/${domain}/privkey.pem"
    x-ui start

    # --- enable bbr and tune system ---
    apt-get install -yqq --no-install-recommends ca-certificates
    echo "net.core.default_qdisc=fq" | tee -a /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control=bbr" | tee -a /etc/sysctl.conf
    echo "fs.file-max=2097152" | tee -a /etc/sysctl.conf
    echo "net.ipv4.tcp_timestamps = 1" | tee -a /etc/sysctl.conf
    echo "net.ipv4.tcp_sack = 1" | tee -a /etc/sysctl.conf
    echo "net.ipv4.tcp_window_scaling = 1" | tee -a /etc/sysctl.conf
    echo "net.core.rmem_max = 16777216" | tee -a /etc/sysctl.conf
    echo "net.core.wmem_max = 16777216" | tee -a /etc/sysctl.conf
    echo "net.ipv4.tcp_rmem = 4096 87380 16777216" | tee -a /etc/sysctl.conf
    echo "net.ipv4.tcp_wmem = 4096 65536 16777216" | tee -a /etc/sysctl.conf
    sysctl -p

    # --- cron jobs ---
    crontab -l | grep -v "certbot\|x-ui" | crontab -
    (crontab -l 2>/dev/null; echo '@daily x-ui restart > /dev/null 2>&1 && nginx -s reload;') | crontab -
    (crontab -l 2>/dev/null; echo '@monthly certbot renew --nginx --non-interactive --post-hook "nginx -s reload" > /dev/null 2>&1;') | crontab -

    # --- ufw ---
    ufw disable
    ufw allow 22/tcp
    ufw allow 80/tcp
    ufw allow 443/tcp
    ufw --force enable  

    # --- final output ---
    clear
    printf '0\n' | x-ui | grep --color=never -i ':'
    msg_inf "- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -"
    nginx -T | grep -i 'ssl_certificate\|ssl_certificate_key'
    msg_inf "- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -"
    certbot certificates | grep -i 'Path:\|Domains:\|Expiry Date:'
    msg_inf "- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -"
    msg_inf "Панель X-UI (защищенная): https://${domain}/${panel_path}/\n"
    echo -e "Имя пользователя: ${config_username}\n"
    echo -e "Пароль: ${config_password}\n"
    msg_inf "- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -"
    msg_inf "Входящее подключение Reality настроено на порту 8443 с SNI: ${reality_domain}"
    msg_inf "ID клиента (UUID): ${client_id} (flow: xtls-rprx-vision)"
    msg_inf "Публичный ключ (PublicKey): ${public_key}"
    msg_inf "Короткие ID (ShortIds): ${shor[*]}"
    msg_inf "- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -"
    msg_inf "Пожалуйста, сохраните эту информацию!"	
}
##################################Main script logic########################################################
# Parse command line arguments if any
if [ $# -gt 0 ]; then
    while [ "$#" -gt 0 ]; do
        case "$1" in
            -install) INSTALL="$2"; shift 2;;
            -uninstall) UNINSTALL="$2"; shift 2;;
            -subdomain) domain="$2"; shift 2;;
            -reality_domain) reality_domain="$2"; shift 2;;
            -auto_domain) AUTODOMAIN="$2"; shift 2;;
            *) shift 1;;
        esac
    done
    if [[ ${UNINSTALL} == *"y"* ]]; then
        UNINSTALL_XUI
    elif [[ ${INSTALL} == *"y"* ]]; then
        install_panel
    else
        msg_err "Неизвестный режим. Используйте -install y или -uninstall y."
        exit 1
    fi
else
    # Interactive mode
    echo "Выберите действие:"
    echo "1) Установить (по умолчанию)"
    echo "2) Удалить"
    read -p "Ваш выбор [1/2]: " choice
    choice=${choice:-1}
    if [[ "$choice" == "2" ]]; then
        UNINSTALL_XUI
    else
        # Ask for auto domains
        read -p "Использовать автоматические домены (вида IP.cdn-one.org)? [y/N]: " auto
        if [[ "$auto" =~ ^[Yy]$ ]]; then
            AUTODOMAIN="y"
        else
            AUTODOMAIN="n"
        fi
        install_panel
    fi
fi
