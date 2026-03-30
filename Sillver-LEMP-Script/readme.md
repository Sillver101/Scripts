# 🚀 Hardened LEMP Server Setup Script

A fully automated script to deploy a secure, production-ready LEMP stack on Ubuntu 20.04.

Designed for quick provisioning with built-in hardening, validation checks, and SSL automation.

---

## 📦 What This Script Does

This script installs and configures a complete LEMP stack along with essential security tools.

### 🖥️ Core Stack
- Nginx (Web Server)
- PHP-FPM (PHP Processing)
- MySQL (Database)

### 🔐 Security & Access
- OpenSSH
- UFW Firewall
- Fail2Ban
- ClamAV Antivirus

### 🧩 PHP Modules
- php-mysql
- php-curl
- php-mbstring
- Core PHP extensions

---

## ⚙️ Additional Configuration

- Configures Nginx with a default placeholder page
- Creates a tools directory at /opt/server-tools/
- Generates an SSL helper script at /opt/server-tools/request-ssl.sh
- Automatically makes the helper executable

---

## 🔐 SSL Helper Features

The included SSL helper performs multiple checks before requesting a certificate:

- DNS resolution validation
- Public IP detection
- UFW firewall rules verification
- Port availability check (HTTP and HTTPS)
- Confirms placeholder page accessibility via your domain

Only after passing all checks does it proceed with Certbot using Nginx integration.

---

## ⚠️ Important Note (Hairpin NAT)

The helper tests your domain using http://your-domain/ from the server itself.

If your network or hosting provider does not support hairpin NAT, this check may fail even though the site works from the public internet.

The script will detect this condition and notify you.

---

## 🔄 SSL Renewal

You can test automatic certificate renewal with:

```bash
certbot renew --dry-run
```

---

## ▶️ Installation

Run the script directly from GitHub:

```bash
curl -fsSL https://raw.githubusercontent.com/Sillver101/Scripts/main/Sillver-LEMP-Script/server-setup.sh | sudo bash
```

---

## 🔍 Verifying the Script

Before running, you can inspect the script manually:

```bash
curl -fsSL https://raw.githubusercontent.com/Sillver101/Scripts/main/Sillver-LEMP-Script/server-setup.sh
```

---

## 🛠️ Requirements

- Ubuntu 20.04 (fresh install recommended)
- Root or sudo access
- Public internet access
- A domain pointing to your server (for SSL)

---

## 📁 Repository Structure

```
Sillver-LEMP-Script/
└── server-setup.sh
```

---

## 👤 Author

Created by Sillver101

---

## ⚡ Notes

- Script must be run as root or with sudo
- No automatic privilege escalation is performed
- Designed for clean deployments, not upgrades