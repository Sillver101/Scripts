This is a custom script created to setup a Hardened LEMP server running on Ubuntu 20.04
The script installs
Nginx,
PHP-FPM,
MySQL,
OpenSSH,
UFW,
Fail2Ban,
ClamAV
As well as php-mysql, php-curl, php-mbstring, plus core PHP modules.
It also configures Nginx with a placeholder page
It then builds an SSL helper at /opt/server-tools/request-ssl.sh
makes that helper executable automatically
lets the helper check DNS, public IP, UFW, listening ports, and whether the placeholder page is reachable at the entered domain before trying Certbot.

The helper checks http://your-domain/ from the server itself. If the upstream firewall or provider does not support hairpin NAT, that check can fail even though the page works fine from the public internet. The script already tells the user when that looks like the issue. Certbot’s Nginx flow can automatically request and install the certificate, and renewal can be tested with certbot renew --dry-run

Run the script with the following command 
curl -fsSL https://raw.githubusercontent.com/YOURUSER/YOURREPO/main/server-setup.sh | sudo bash

You can verify the script that is downloaded with the raw file by running this
curl -fsSL https://raw.githubusercontent.com/YOURUSER/YOURREPO/main/server-setup.sh | sudo bash
