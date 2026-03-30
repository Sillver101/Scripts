#!/bin/bash
set -euo pipefail

if [[ "$EUID" -ne 0 ]]; then
    echo
    echo "ERROR: This script must be run as root."
    echo
    echo "Run it using:"
    echo "  curl -fsSL https://raw.githubusercontent.com/Sillver101/Scripts/main/Sillver-LEMP-Script/server-setup.sh | sudo bash"
    echo
    exit 1
fi

export DEBIAN_FRONTEND=noninteractive

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'
BOLD='\033[1m'
NC='\033[0m'

CERT_HELPER_URL="https://raw.githubusercontent.com/Sillver101/Scripts/main/Sillver-LEMP-Script/request-ssl.sh"
CERT_HELPER_PATH="/opt/server-tools/request-ssl.sh"

clear

cat << 'EOF2'
   _____ _ _ _                     _   ___   ___  _
  / ____(_) | |                   / | / _ \ / _ \| |
 | (___  _| | |_   _____ _ __    | || | | | | | | |
  \___ \| | | \ \ / / _ \ '__|   | || | | | | | | |
  ____) | | | |\ V /  __/ |      | || |_| | |_| | |
 |_____/|_|_|_| \_/ \___|_|      |_| \___/ \___/|_|

EOF2

echo -e "${CYAN}${BOLD}Sillver101 Server Setup${NC}"
echo -e "${BLUE}============================================================${NC}"
echo -e "${WHITE}This script will install and configure:${NC}"
echo -e " ${GREEN}-${NC} Nginx"
echo -e " ${GREEN}-${NC} PHP-FPM with common extensions"
echo -e " ${GREEN}-${NC} MySQL Server"
echo -e " ${GREEN}-${NC} OpenSSH [SSH and SFTP]"
echo -e " ${GREEN}-${NC} UFW Firewall [22, 80, 443]"
echo -e " ${GREEN}-${NC} Fail2Ban"
echo -e " ${GREEN}-${NC} ClamAV"
echo -e " ${GREEN}-${NC} Default Nginx site with placeholder page"
echo -e " ${GREEN}-${NC} SSL helper downloaded to ${YELLOW}${CERT_HELPER_PATH}${NC}"
echo
echo -e "${WHITE}The default website will show:${NC}"
echo -e " ${YELLOW}Server setup for <domain>${NC}"
echo

read -rp "Continue with installation? [y/N]: " CONFIRM
case "$CONFIRM" in
    y|Y|yes|YES)
        ;;
    *)
        echo "Cancelled."
        exit 0
        ;;
esac

run_step() {
    local message="$1"
    shift
    local logfile
    logfile="$(mktemp)"

    echo -ne "${CYAN}==>${NC} ${WHITE}${message}${NC} "

    (
        "$@"
    ) >"$logfile" 2>&1 &
    local pid=$!

    local spin='|/-\\'
    local i=0

    while kill -0 "$pid" 2>/dev/null; do
        i=$(( (i + 1) % 4 ))
        printf "\b${MAGENTA}%c${NC}" "${spin:$i:1}"
        sleep 0.1
    done

    wait "$pid"
    local rc=$?

    if [[ $rc -eq 0 ]]; then
        printf "\b${GREEN}✔${NC}\n"
        rm -f "$logfile"
    else
        printf "\b${RED}✘${NC}\n"
        echo
        echo -e "${RED}Step failed:${NC} ${message}"
        echo -e "${YELLOW}Output:${NC}"
        cat "$logfile"
        rm -f "$logfile"
        exit $rc
    fi
}

install_packages() {
    apt update
    apt upgrade -y
    apt install -y \
        nginx \
        php-fpm php-cli php-mysql php-curl php-mbstring php-xml php-zip \
        mysql-server \
        openssh-server \
        ufw \
        fail2ban \
        clamav clamav-daemon \
        curl wget unzip git dnsutils
}

detect_php() {
    PHP_FPM_SERVICE="$(systemctl list-unit-files | awk '/^php[0-9]+\.[0-9]+-fpm\.service/ {print $1}' | sed 's/\.service$//' | sort -V | tail -n1)"
    PHP_VERSION="$(echo "$PHP_FPM_SERVICE" | grep -oE '[0-9]+\.[0-9]+')"
    PHP_SOCK="/run/php/php${PHP_VERSION}-fpm.sock"

    if [[ -z "${PHP_FPM_SERVICE:-}" || -z "${PHP_VERSION:-}" || ! -S "${PHP_SOCK}" ]]; then
        echo -e "${RED}Could not determine installed PHP-FPM socket.${NC}"
        echo "Detected service: ${PHP_FPM_SERVICE:-none}"
        echo "Expected socket: ${PHP_SOCK:-none}"
        exit 1
    fi
}

enable_services() {
    systemctl enable nginx
    systemctl enable "$PHP_FPM_SERVICE"
    systemctl enable mysql
    systemctl enable ssh
    systemctl enable fail2ban
    systemctl enable clamav-daemon
}

configure_ufw() {
    ufw --force reset
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow 22/tcp
    ufw allow 80/tcp
    ufw allow 443/tcp
    ufw --force enable
}

write_fail2ban() {
    cat > /etc/fail2ban/jail.local << 'EOF2'
[sshd]
enabled = true
port = 22
backend = systemd
maxretry = 5
bantime = 1h
findtime = 10m
EOF2
}

update_clamav() {
    systemctl stop clamav-freshclam || true
    freshclam || true
    systemctl restart clamav-daemon || true
}

create_website() {
    mkdir -p /var/www/default/public

    cat > /var/www/default/public/index.php << 'EOF2'
<?php
$domain = $_SERVER['HTTP_HOST'] ?? 'unknown-domain';
$domain = preg_replace('/:\d+$/', '', $domain);
$domain = htmlspecialchars($domain, ENT_QUOTES, 'UTF-8');
?>
<!DOCTYPE html>
<html lang='en'>
<head>
    <meta charset='UTF-8'>
    <meta name='viewport' content='width=device-width, initial-scale=1.0'>
    <title>Server setup for <?php echo $domain; ?></title>
    <style>
        body {
            margin: 0;
            font-family: Arial, Helvetica, sans-serif;
            background: #f5f7fa;
            color: #1f2937;
            display: flex;
            align-items: center;
            justify-content: center;
            min-height: 100vh;
        }
        .card {
            max-width: 760px;
            background: #ffffff;
            border: 1px solid #d1d5db;
            border-radius: 12px;
            padding: 32px;
            box-shadow: 0 10px 30px rgba(0,0,0,0.08);
        }
        h1 {
            margin-top: 0;
            font-size: 32px;
            line-height: 1.2;
        }
        p {
            font-size: 18px;
            line-height: 1.6;
            margin-bottom: 14px;
        }
        .domain {
            color: #2563eb;
            word-break: break-word;
        }
    </style>
</head>
<body>
    <div class='card'>
        <h1>Server setup for <span class='domain'><?php echo $domain; ?></span></h1>
        <p>If this is expected then there is nothing left to do.</p>
        <p>If this is not right contact your web developer.</p>
    </div>
</body>
</html>
EOF2

    chown -R www-data:www-data /var/www/default
}

configure_nginx() {
    rm -f /etc/nginx/sites-enabled/default
    rm -f /etc/nginx/sites-available/default

    cat > /etc/nginx/sites-available/default-site << EOF2
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;

    root /var/www/default/public;
    index index.php index.html;

    access_log /var/log/nginx/default-site-access.log;
    error_log /var/log/nginx/default-site-error.log;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:${PHP_SOCK};
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF2

    ln -sf /etc/nginx/sites-available/default-site /etc/nginx/sites-enabled/default-site
}

download_ssl_helper() {
    mkdir -p /opt/server-tools
    curl -fsSL "$CERT_HELPER_URL" -o "$CERT_HELPER_PATH"
    chmod 700 "$CERT_HELPER_PATH"
    sed -i 's/\r$//' "$CERT_HELPER_PATH"
    bash -n "$CERT_HELPER_PATH"
}

restart_services() {
    systemctl restart "$PHP_FPM_SERVICE"
    systemctl restart nginx
    systemctl restart mysql
    systemctl restart ssh
    systemctl restart fail2ban
}

run_step "Installing required packages" install_packages
run_step "Detecting PHP-FPM" detect_php
echo -e "${GREEN}Detected:${NC} ${PHP_FPM_SERVICE} [${PHP_SOCK}]"
run_step "Enabling services" enable_services
run_step "Configuring UFW firewall" configure_ufw
run_step "Writing Fail2Ban configuration" write_fail2ban
run_step "Updating ClamAV signatures" update_clamav
run_step "Creating website root" create_website
run_step "Configuring Nginx" configure_nginx
run_step "Downloading SSL helper script" download_ssl_helper
run_step "Testing Nginx configuration" nginx -t
run_step "Restarting services" restart_services

echo -e "${CYAN}==>${NC} ${WHITE}Verifying PHP modules${NC}"
MISSING_MODULES=()
for mod in mysqli pdo_mysql mbstring openssl curl json fileinfo; do
    if ! php -m | grep -iq "^${mod}$"; then
        MISSING_MODULES+=("$mod")
    fi
done

echo
echo -e "${BLUE}============================================================${NC}"
echo -e "${GREEN}${BOLD}Setup complete${NC}"
echo -e "${BLUE}============================================================${NC}"
echo
echo -e "${WHITE}Installed:${NC}"
echo "  Nginx"
echo "  PHP-FPM ${PHP_VERSION}"
echo "  MySQL"
echo "  OpenSSH"
echo "  UFW"
echo "  Fail2Ban"
echo "  ClamAV"
echo
echo -e "${WHITE}Open ports:${NC}"
echo "  22/tcp"
echo "  80/tcp"
echo "  443/tcp"
echo
echo -e "${WHITE}Website root:${NC} /var/www/default/public"
echo -e "${WHITE}Nginx config:${NC} /etc/nginx/sites-available/default-site"
echo -e "${WHITE}SSL helper:${NC} ${CERT_HELPER_PATH}"
echo

if [[ ${#MISSING_MODULES[@]} -eq 0 ]]; then
    echo -e "${GREEN}Required PHP modules detected:${NC}"
    echo "  mysqli, pdo_mysql, mbstring, openssl, curl, json, fileinfo"
else
    echo -e "${YELLOW}WARNING: Missing PHP modules:${NC}"
    printf '  %s\n' "${MISSING_MODULES[@]}"
fi

echo
echo -e "${YELLOW}When DNS is correct, run:${NC}"
echo "  sudo ${CERT_HELPER_PATH}"
