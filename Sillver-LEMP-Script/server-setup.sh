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

clear

cat << 'EOF'
   _____ _ _ _                     _   ___   ___  _
  / ____(_) | |                   / | / _ \ / _ \| |
 | (___  _| | |_   _____ _ __    | || | | | | | | |
  \___ \| | | \ \ / / _ \ '__|   | || | | | | | | |
  ____) | | | |\ V /  __/ |      | || |_| | |_| | |
 |_____/|_|_|_| \_/ \___|_|      |_| \___/ \___/|_|

EOF

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
echo -e " ${GREEN}-${NC} SSL helper script at ${YELLOW}/opt/server-tools/request-ssl.sh${NC}"
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

    local spin='|/-\'
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

run_step "Updating package lists" apt update
run_step "Upgrading installed packages" apt upgrade -y
run_step "Installing required packages" apt install -y \
    nginx \
    php-fpm php-cli php-mysql php-curl php-mbstring php-xml php-zip \
    mysql-server \
    openssh-server \
    ufw \
    fail2ban \
    clamav clamav-daemon \
    curl wget unzip git dnsutils

echo -e "${CYAN}==>${NC} ${WHITE}Detecting PHP-FPM${NC}"
PHP_FPM_SERVICE="$(systemctl list-unit-files | awk '/^php[0-9]+\.[0-9]+-fpm\.service/ {print $1}' | sed 's/\.service$//' | sort -V | tail -n1)"
PHP_VERSION="$(echo "$PHP_FPM_SERVICE" | grep -oE '[0-9]+\.[0-9]+')"
PHP_SOCK="/run/php/php${PHP_VERSION}-fpm.sock"

if [[ -z "${PHP_FPM_SERVICE:-}" || -z "${PHP_VERSION:-}" || ! -S "${PHP_SOCK}" ]]; then
    echo -e "${RED}Could not determine installed PHP-FPM socket.${NC}"
    echo "Detected service: ${PHP_FPM_SERVICE:-none}"
    echo "Expected socket: ${PHP_SOCK:-none}"
    exit 1
fi

echo -e "${GREEN}Detected:${NC} ${PHP_FPM_SERVICE} [${PHP_SOCK}]"

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
    cat > /etc/fail2ban/jail.local << 'EOF'
[sshd]
enabled = true
port = 22
backend = systemd
maxretry = 5
bantime = 1h
findtime = 10m
EOF
}

update_clamav() {
    systemctl stop clamav-freshclam || true
    freshclam || true
    systemctl restart clamav-daemon || true
}

create_website() {
    mkdir -p /var/www/default/public

    cat > /var/www/default/public/index.php << 'EOF'
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
EOF

    chown -R www-data:www-data /var/www/default
}

configure_nginx() {
    rm -f /etc/nginx/sites-enabled/default
    rm -f /etc/nginx/sites-available/default

    cat > /etc/nginx/sites-available/default-site << EOF
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
EOF

    ln -sf /etc/nginx/sites-available/default-site /etc/nginx/sites-enabled/default-site
}

create_ssl_helper() {
    mkdir -p /opt/server-tools

    cat > /opt/server-tools/request-ssl.sh << 'EOF'
#!/bin/bash
set -euo pipefail

if [[ "$EUID" -ne 0 ]]; then
    echo
    echo "ERROR: This script must be run as root."
    echo
    echo "Run it using:"
    echo "  sudo /opt/server-tools/request-ssl.sh"
    echo
    exit 1
fi

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'
BOLD='\033[1m'
NC='\033[0m'

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || {
        echo -e "${RED}Missing required command:${NC} $1"
        exit 1
    }
}

get_public_ip() {
    local ip=""
    ip="$(curl -4 -fsS --max-time 5 https://api.ipify.org || true)"
    [[ -n "$ip" ]] || ip="$(curl -4 -fsS --max-time 5 https://ifconfig.me || true)"
    [[ -n "$ip" ]] || ip="$(curl -4 -fsS --max-time 5 https://icanhazip.com || true)"
    echo "$ip" | tr -d '[:space:]'
}

resolve_domain_ipv4() {
    local domain="$1"
    getent ahostsv4 "$domain" | awk '{print $1}' | sort -u
}

check_ufw_port() {
    local port="$1"
    if command -v ufw >/dev/null 2>&1; then
        ufw status | grep -Eq "(^|[[:space:]])${port}(/tcp)?[[:space:]].*ALLOW" && return 0
    fi
    return 1
}

check_listening_port() {
    local port="$1"
    ss -ltn | awk '{print $4}' | grep -Eq "(:|\\])${port}$"
}

check_http_placeholder_live() {
    local domain="$1"
    local tmpfile
    tmpfile="$(mktemp)"

    if curl -4 -fsS --max-time 10 "http://${domain}/" -o "$tmpfile"; then
        if grep -Fq "Server setup for" "$tmpfile"; then
            echo "reachable"
            rm -f "$tmpfile"
            return 0
        else
            echo "http-responded-but-placeholder-not-detected"
            rm -f "$tmpfile"
            return 0
        fi
    fi

    rm -f "$tmpfile"
    return 1
}

check_http_placeholder_local_host_header() {
    local domain="$1"
    local tmpfile
    tmpfile="$(mktemp)"

    if curl -4 -fsS --max-time 10 -H "Host: ${domain}" http://127.0.0.1/ -o "$tmpfile"; then
        if grep -Fq "Server setup for" "$tmpfile"; then
            echo "local-host-header-ok"
            rm -f "$tmpfile"
            return 0
        fi
    fi

    rm -f "$tmpfile"
    return 1
}

echo -e "${CYAN}${BOLD}Let's Encrypt / Certbot Helper${NC}"
echo -e "${BLUE}==========================================${NC}"
echo
echo "Prerequisites:"
echo "1. The domain must point to this server public IP"
echo "2. Port 80 must be reachable from the internet"
echo "3. Port 443 should also be forwarded and allowed"
echo "4. Nginx must be running"
echo "5. The placeholder page should be visible at http://your-domain/"
echo

read -rp "Continue with pre-checks? [y/N]: " START_CONFIRM
case "$START_CONFIRM" in
    y|Y|yes|YES) ;;
    *)
        echo "Cancelled."
        exit 0
        ;;
esac

require_cmd curl
require_cmd getent
require_cmd ss
require_cmd awk
require_cmd grep
require_cmd sed

read -rp "Enter the main domain name to secure, example site.com: " DOMAIN
if [[ -z "${DOMAIN:-}" ]]; then
    echo "Domain cannot be blank."
    exit 1
fi

read -rp "Enter a second domain too, example www.site.com [leave blank if not needed]: " DOMAIN2
read -rp "Enter email address for Let's Encrypt notices: " EMAIL
if [[ -z "${EMAIL:-}" ]]; then
    echo "Email cannot be blank."
    exit 1
fi

echo
echo "Running checks..."
echo

PUBLIC_IP="$(get_public_ip || true)"
if [[ -z "${PUBLIC_IP:-}" ]]; then
    echo -e "[${YELLOW}WARNING${NC}] Could not determine public IPv4 automatically."
else
    echo -e "[${GREEN}OK${NC}] Detected public IPv4: $PUBLIC_IP"
fi

DOMAIN_IPS="$(resolve_domain_ipv4 "$DOMAIN" || true)"
if [[ -z "${DOMAIN_IPS:-}" ]]; then
    echo -e "[${YELLOW}WARNING${NC}] Could not resolve an IPv4 address for $DOMAIN"
else
    echo -e "[${GREEN}OK${NC}] $DOMAIN resolves to:"
    echo "$DOMAIN_IPS" | sed 's/^/       - /'
fi

DOMAIN_MATCH="no"
if [[ -n "${PUBLIC_IP:-}" && -n "${DOMAIN_IPS:-}" ]]; then
    while IFS= read -r ip; do
        if [[ "$ip" == "$PUBLIC_IP" ]]; then
            DOMAIN_MATCH="yes"
            break
        fi
    done <<< "$DOMAIN_IPS"
fi

if [[ "$DOMAIN_MATCH" == "yes" ]]; then
    echo -e "[${GREEN}OK${NC}] Domain A record matches detected public IP"
else
    echo -e "[${YELLOW}WARNING${NC}] Domain A record does not appear to match the detected public IP"
fi

if systemctl is-active --quiet nginx; then
    echo -e "[${GREEN}OK${NC}] Nginx service is running"
else
    echo -e "[${YELLOW}WARNING${NC}] Nginx service is not running"
fi

if check_listening_port 80; then
    echo -e "[${GREEN}OK${NC}] Server is listening on TCP 80"
else
    echo -e "[${YELLOW}WARNING${NC}] Server is not listening on TCP 80"
fi

if check_listening_port 443; then
    echo -e "[${GREEN}OK${NC}] Server is listening on TCP 443"
else
    echo -e "[${BLUE}INFO${NC}] Server is not yet listening on TCP 443"
fi

if command -v ufw >/dev/null 2>&1; then
    if check_ufw_port 80; then
        echo -e "[${GREEN}OK${NC}] UFW appears to allow TCP 80"
    else
        echo -e "[${YELLOW}WARNING${NC}] UFW does not appear to allow TCP 80"
    fi

    if check_ufw_port 443; then
        echo -e "[${GREEN}OK${NC}] UFW appears to allow TCP 443"
    else
        echo -e "[${YELLOW}WARNING${NC}] UFW does not appear to allow TCP 443"
    fi
fi

HTTP_STATUS="unreachable"
TMP_STATUS_FILE="$(mktemp)"
if check_http_placeholder_live "$DOMAIN" >"$TMP_STATUS_FILE" 2>/dev/null; then
    HTTP_STATUS="$(cat "$TMP_STATUS_FILE")"
fi
rm -f "$TMP_STATUS_FILE"

case "$HTTP_STATUS" in
    reachable)
        echo -e "[${GREEN}OK${NC}] The placeholder page is reachable at http://$DOMAIN/"
        ;;
    http-responded-but-placeholder-not-detected)
        echo -e "[${YELLOW}WARNING${NC}] http://$DOMAIN/ responded, but the expected placeholder text was not detected"
        ;;
    *)
        echo -e "[${YELLOW}WARNING${NC}] Could not confirm the placeholder page at http://$DOMAIN/"
        if check_http_placeholder_local_host_header "$DOMAIN" >/dev/null 2>&1; then
            echo -e "[${BLUE}INFO${NC}] The placeholder page works locally with a forced Host header"
            echo "       Public reachability or hairpin NAT may be the issue"
        fi
        ;;
esac

if [[ -n "${DOMAIN2:-}" ]]; then
    DOMAIN2_IPS="$(resolve_domain_ipv4 "$DOMAIN2" || true)"
    if [[ -z "${DOMAIN2_IPS:-}" ]]; then
        echo -e "[${YELLOW}WARNING${NC}] Could not resolve an IPv4 address for $DOMAIN2"
    else
        echo -e "[${GREEN}OK${NC}] $DOMAIN2 resolves to:"
        echo "$DOMAIN2_IPS" | sed 's/^/       - /'
    fi
fi

echo
echo "Summary:"
echo "  Main domain: $DOMAIN"
[[ -n "${DOMAIN2:-}" ]] && echo "  Second domain: $DOMAIN2"
echo "  Email: $EMAIL"
[[ -n "${PUBLIC_IP:-}" ]] && echo "  Detected public IPv4: $PUBLIC_IP"
echo

if [[ "$DOMAIN_MATCH" != "yes" ]]; then
    echo "The main domain does not currently appear to resolve to this server public IP."
    echo "Certbot will probably fail unless DNS or upstream forwarding is corrected first."
    echo
    read -rp "Continue anyway? [y/N]: " FORCE_CONFIRM
    case "$FORCE_CONFIRM" in
        y|Y|yes|YES) ;;
        *)
            echo "Cancelled."
            exit 1
            ;;
    esac
fi

read -rp "Proceed with Certbot installation and certificate request? [y/N]: " FINAL_CONFIRM
case "$FINAL_CONFIRM" in
    y|Y|yes|YES) ;;
    *)
        echo "Cancelled."
        exit 0
        ;;
esac

apt update
apt install -y certbot python3-certbot-nginx

if [[ -n "${DOMAIN2:-}" ]]; then
    certbot --nginx -d "$DOMAIN" -d "$DOMAIN2" --non-interactive --agree-tos --email "$EMAIL" --redirect
else
    certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos --email "$EMAIL" --redirect
fi

nginx -t
systemctl reload nginx

echo
echo -e "${GREEN}Certificate installation complete.${NC}"
echo "Recommended test:"
echo "certbot renew --dry-run"
EOF

    chmod 700 /opt/server-tools/request-ssl.sh
}

restart_services() {
    systemctl restart "$PHP_FPM_SERVICE"
    systemctl restart nginx
    systemctl restart mysql
    systemctl restart ssh
    systemctl restart fail2ban
}

run_step "Enabling services" enable_services
run_step "Configuring UFW firewall" configure_ufw
run_step "Writing Fail2Ban configuration" write_fail2ban
run_step "Updating ClamAV signatures" update_clamav
run_step "Creating website root" create_website
run_step "Configuring Nginx" configure_nginx
run_step "Creating SSL helper script" create_ssl_helper
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
echo -e "${WHITE}SSL helper:${NC} /opt/server-tools/request-ssl.sh"
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
echo "  sudo /opt/server-tools/request-ssl.sh"
