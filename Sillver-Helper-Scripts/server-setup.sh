#!/bin/bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

if [[ "${EUID}" -ne 0 ]]; then
    echo "Please run this script as root."
    exit 1
fi

log() {
    echo
    echo "==> $1"
}

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || {
        echo "Missing required command: $1"
        exit 1
    }
}

log "Updating package lists"
apt update

log "Upgrading installed packages"
apt upgrade -y

log "Installing base packages"
apt install -y \
    nginx \
    php-fpm php-cli php-mysql php-curl php-mbstring php-xml php-zip \
    mysql-server \
    openssh-server \
    ufw \
    fail2ban \
    clamav clamav-daemon \
    curl wget unzip git dnsutils ca-certificates lsb-release

log "Detecting PHP-FPM service"
PHP_FPM_SERVICE="$(systemctl list-unit-files | awk '/^php[0-9]+\.[0-9]+-fpm\.service/ {print $1}' | sed 's/\.service$//' | sort -V | tail -n1)"
PHP_VERSION="$(echo "${PHP_FPM_SERVICE}" | grep -oE '[0-9]+\.[0-9]+')"
PHP_SOCK="/run/php/php${PHP_VERSION}-fpm.sock"

if [[ -z "${PHP_FPM_SERVICE:-}" || -z "${PHP_VERSION:-}" || ! -S "${PHP_SOCK}" ]]; then
    echo "Could not determine installed PHP-FPM socket."
    echo "Detected service: ${PHP_FPM_SERVICE:-none}"
    echo "Expected socket: ${PHP_SOCK:-none}"
    exit 1
fi

log "Enabling services"
systemctl enable nginx
systemctl enable "${PHP_FPM_SERVICE}"
systemctl enable mysql
systemctl enable ssh
systemctl enable fail2ban
systemctl enable clamav-daemon

log "Configuring UFW"
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable

log "Configuring Fail2Ban"
cat > /etc/fail2ban/jail.local << 'EOF'
[sshd]
enabled = true
port = 22
backend = systemd
maxretry = 5
findtime = 10m
bantime = 1h
EOF

log "Updating ClamAV signatures"
systemctl stop clamav-freshclam || true
freshclam || true
systemctl enable clamav-freshclam || true
systemctl restart clamav-freshclam || true
systemctl restart clamav-daemon || true

log "Creating website root"
mkdir -p /var/www/default/public

cat > /var/www/default/public/index.php << 'EOF'
<?php
$domain = $_SERVER['HTTP_HOST'] ?? 'unknown-domain';
$domain = preg_replace('/:\d+$/', '', $domain);
$domain = htmlspecialchars($domain, ENT_QUOTES, 'UTF-8');
?>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
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
    <div class="card">
        <h1>Server setup for <span class="domain"><?php echo $domain; ?></span></h1>
        <p>If this is expected then there is nothing left to do.</p>
        <p>If this is not right contact your web developer.</p>
    </div>
</body>
</html>
EOF

chown -R www-data:www-data /var/www/default

log "Configuring Nginx"
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

log "Creating SSL helper directory"
mkdir -p /opt/server-tools

log "Creating Certbot helper script"
cat > /opt/server-tools/request-ssl.sh << 'EOF'
#!/bin/bash
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
    echo "Please run this script as root."
    exit 1
fi

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || {
        echo "Missing required command: $1"
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

echo
echo "=========================================="
echo "Let's Encrypt / Certbot Helper"
echo "=========================================="
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
    echo "[WARNING] Could not determine public IPv4 automatically."
else
    echo "[OK] Detected public IPv4: $PUBLIC_IP"
fi

DOMAIN_IPS="$(resolve_domain_ipv4 "$DOMAIN" || true)"
if [[ -z "${DOMAIN_IPS:-}" ]]; then
    echo "[WARNING] Could not resolve an IPv4 address for $DOMAIN"
else
    echo "[OK] $DOMAIN resolves to:"
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
    echo "[OK] Domain A record matches detected public IP"
else
    echo "[WARNING] Domain A record does not appear to match the detected public IP"
fi

if systemctl is-active --quiet nginx; then
    echo "[OK] Nginx service is running"
else
    echo "[WARNING] Nginx service is not running"
fi

if check_listening_port 80; then
    echo "[OK] Server is listening on TCP 80"
else
    echo "[WARNING] Server is not listening on TCP 80"
fi

if check_listening_port 443; then
    echo "[OK] Server is listening on TCP 443"
else
    echo "[INFO] Server is not yet listening on TCP 443"
    echo "       This is normal before the certificate is installed"
fi

if command -v ufw >/dev/null 2>&1; then
    if check_ufw_port 80; then
        echo "[OK] UFW appears to allow TCP 80"
    else
        echo "[WARNING] UFW does not appear to allow TCP 80"
    fi

    if check_ufw_port 443; then
        echo "[OK] UFW appears to allow TCP 443"
    else
        echo "[WARNING] UFW does not appear to allow TCP 443"
    fi
else
    echo "[INFO] UFW not installed, skipping UFW checks"
fi

HTTP_STATUS="unreachable"
TMP_STATUS_FILE="$(mktemp)"
if check_http_placeholder_live "$DOMAIN" >"$TMP_STATUS_FILE" 2>/dev/null; then
    HTTP_STATUS="$(cat "$TMP_STATUS_FILE")"
fi
rm -f "$TMP_STATUS_FILE"

case "$HTTP_STATUS" in
    reachable)
        echo "[OK] The placeholder page is reachable at http://$DOMAIN/"
        ;;
    http-responded-but-placeholder-not-detected)
        echo "[WARNING] http://$DOMAIN/ responded, but the expected placeholder text was not detected"
        ;;
    *)
        echo "[WARNING] Could not confirm the placeholder page at http://$DOMAIN/"
        if check_http_placeholder_local_host_header "$DOMAIN" >/dev/null 2>&1; then
            echo "[INFO] The placeholder page works locally when forcing the Host header"
            echo "       This usually means Nginx is fine, but public reachability or hairpin NAT may be the issue"
        fi
        ;;
esac

if [[ -n "${DOMAIN2:-}" ]]; then
    DOMAIN2_IPS="$(resolve_domain_ipv4 "$DOMAIN2" || true)"
    if [[ -z "${DOMAIN2_IPS:-}" ]]; then
        echo "[WARNING] Could not resolve an IPv4 address for $DOMAIN2"
    else
        echo "[OK] $DOMAIN2 resolves to:"
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

echo
echo "Installing Certbot"
apt update
apt install -y certbot python3-certbot-nginx

echo
echo "Requesting certificate"
if [[ -n "${DOMAIN2:-}" ]]; then
    certbot --nginx \
        -d "$DOMAIN" \
        -d "$DOMAIN2" \
        --non-interactive \
        --agree-tos \
        --email "$EMAIL" \
        --redirect
else
    certbot --nginx \
        -d "$DOMAIN" \
        --non-interactive \
        --agree-tos \
        --email "$EMAIL" \
        --redirect
fi

echo
echo "Validating Nginx configuration"
nginx -t
systemctl reload nginx

echo
echo "Certificate installation complete."
echo "Recommended test:"
echo "certbot renew --dry-run"
EOF

chmod 700 /opt/server-tools/request-ssl.sh

log "Testing Nginx configuration"
nginx -t

log "Restarting services"
systemctl restart "${PHP_FPM_SERVICE}"
systemctl restart nginx
systemctl restart mysql
systemctl restart ssh
systemctl restart fail2ban

log "Verifying PHP modules"
MISSING_MODULES=()
for mod in mysqli pdo_mysql mbstring openssl curl json fileinfo; do
    if ! php -m | grep -iq "^${mod}$"; then
        MISSING_MODULES+=("$mod")
    fi
done

echo
echo "=================================================="
echo "Setup complete"
echo "=================================================="
echo "Installed:"
echo "  Nginx"
echo "  PHP-FPM ${PHP_VERSION}"
echo "  MySQL"
echo "  OpenSSH"
echo "  UFW"
echo "  Fail2Ban"
echo "  ClamAV"
echo
echo "Open ports:"
echo "  22/tcp"
echo "  80/tcp"
echo "  443/tcp"
echo
echo "Website root:"
echo "  /var/www/default/public"
echo
echo "Nginx config:"
echo "  /etc/nginx/sites-available/default-site"
echo
echo "SSL helper:"
echo "  /opt/server-tools/request-ssl.sh"
echo
if [[ ${#MISSING_MODULES[@]} -eq 0 ]]; then
    echo "Required PHP modules detected:"
    echo "  mysqli, pdo_mysql, mbstring, openssl, curl, json, fileinfo"
else
    echo "WARNING: Missing PHP modules:"
    printf '  %s\n' "${MISSING_MODULES[@]}"
fi
echo
echo "When DNS is correct, run:"
echo "  sudo /opt/server-tools/request-ssl.sh"