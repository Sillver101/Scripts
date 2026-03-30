# Sillver LEMP Script

This folder contains the files for a simple Ubuntu 22.04 LEMP bootstrap.

## Files

- `server-setup.sh`
  - Main installer script
  - Installs Nginx, PHP-FPM, MySQL, OpenSSH, UFW, Fail2Ban, and ClamAV
  - Builds a default Nginx placeholder site
  - Downloads `request-ssl.sh` from GitHub and saves it to `/opt/server-tools/request-ssl.sh`

- `request-ssl.sh`
  - Standalone Certbot helper
  - Checks DNS resolution, public IP, UFW, listening ports, and HTTP reachability
  - Requests and installs a certificate with Certbot when the domain is ready

- `README.md`
  - Basic usage notes

## Recommended structure in your repo

This zip is built for placement under:

`Scripts/Sillver-LEMP-Script/`

## Run the main setup script

```bash
curl -fsSL https://raw.githubusercontent.com/Sillver101/Scripts/main/Sillver-LEMP-Script/server-setup.sh | sudo bash
```

## Run the SSL helper later

```bash
sudo /opt/server-tools/request-ssl.sh
```

## Suggested Git setting

Create a `.gitattributes` file in the repo root with:

```gitattributes
*.sh text eol=lf
```

This helps stop line-ending issues on shell scripts.
