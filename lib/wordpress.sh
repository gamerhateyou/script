#!/bin/bash

# =============================================================================
# WORDPRESS INSTALLATION FUNCTIONS
# =============================================================================

# shellcheck source=./utils.sh
source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"

# =============================================================================
# WORDPRESS SCRIPT GENERATION
# =============================================================================

generate_wordpress_script() {
    local output_file="$1"

    log_step "Generazione script WordPress..."

    cat > "$output_file" << 'WORDPRESS_SCRIPT_EOF'
#!/bin/bash

# =============================================================================
# SCRIPT INSTALLAZIONE WORDPRESS OTTIMIZZATO
# Versione 2025.09 - Modulare
# =============================================================================

set -euo pipefail

# Colori
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"; }

# =============================================================================
# CONFIGURATION
# =============================================================================

# WordPress defaults
WP_VERSION="latest"
WP_LOCALE="it_IT"
PHP_VERSION="8.3"

# Directories
NGINX_SITES_AVAILABLE="/etc/nginx/sites-available"
NGINX_SITES_ENABLED="/etc/nginx/sites-enabled"
PHP_FPM_POOL="/etc/php/${PHP_VERSION}/fpm/pool.d"
PHP_FPM_CONF="/etc/php/${PHP_VERSION}/fpm/conf.d"

# =============================================================================
# INPUT VALIDATION
# =============================================================================

validate_domain() {
    local domain="$1"
    local regex='^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$'
    [[ $domain =~ $regex ]]
}

validate_email() {
    local email="$1"
    local regex='^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'
    [[ $email =~ $regex ]]
}

validate_ip() {
    local ip="$1"
    local regex='^([0-9]{1,3}\.){3}[0-9]{1,3}$'
    [[ $ip =~ $regex ]]
}

# =============================================================================
# CONFIGURATION COLLECTION
# =============================================================================

configure_params() {
    log_step "Configurazione parametri WordPress..."

    echo "=== CONFIGURAZIONE WORDPRESS ==="

    # Site information
    while true; do
        read -p "Nome del sito: " SITE_NAME
        [[ -n "$SITE_NAME" ]] && break
        log_error "Il nome del sito non può essere vuoto"
    done

    while true; do
        read -p "Dominio (es: example.com): " DOMAIN
        if validate_domain "$DOMAIN"; then
            break
        else
            log_error "Dominio non valido. Usa formato: example.com"
        fi
    done

    # Database configuration
    while true; do
        read -p "IP server MySQL: " DB_HOST
        if validate_ip "$DB_HOST"; then
            break
        else
            log_error "Indirizzo IP non valido"
        fi
    done

    read -p "Nome database: " DB_NAME
    read -p "Username database: " DB_USER
    read -s -p "Password database: " DB_PASS
    echo

    # WordPress admin
    while true; do
        read -p "Email admin WordPress: " WP_ADMIN_EMAIL
        if validate_email "$WP_ADMIN_EMAIL"; then
            break
        else
            log_error "Email non valida"
        fi
    done

    read -p "Username admin WordPress: " WP_ADMIN_USER
    read -s -p "Password admin WordPress: " WP_ADMIN_PASS
    echo

    # Optional services
    read -p "IP server Redis [opzionale]: " REDIS_HOST
    read -p "IP server MinIO [opzionale]: " MINIO_HOST

    # SSL configuration
    read -p "Configurare SSL automaticamente? [y/N]: " SETUP_SSL
    [[ "${SETUP_SSL,,}" =~ ^(y|yes|s|si)$ ]] && SETUP_SSL=true || SETUP_SSL=false

    log_success "Parametri configurati"
}

# =============================================================================
# SYSTEM UPDATE
# =============================================================================

update_system() {
    log_step "Aggiornamento sistema..."

    export DEBIAN_FRONTEND=noninteractive

    # Update package list
    apt update -y || {
        log_error "Errore aggiornamento package list"
        return 1
    }

    # Upgrade system
    apt upgrade -y || {
        log_warn "Alcuni aggiornamenti potrebbero essere falliti"
    }

    # Install base packages
    apt install -y software-properties-common apt-transport-https ca-certificates \
                   curl wget gnupg lsb-release unzip zip htop net-tools \
                   mysql-client bc || {
        log_error "Errore installazione pacchetti base"
        return 1
    }

    # Configure timezone
    timedatectl set-timezone Europe/Rome || log_warn "Impossibile impostare timezone"

    log_success "Sistema aggiornato"
}

# =============================================================================
# PHP INSTALLATION
# =============================================================================

install_php() {
    log_step "Installazione PHP ${PHP_VERSION}..."

    # Add Ondrej PPA for latest PHP
    if ! add-apt-repository ppa:ondrej/php -y; then
        log_error "Errore aggiunta repository PHP"
        return 1
    fi

    apt update -y

    # Core PHP packages
    local php_packages=(
        "php${PHP_VERSION}" "php${PHP_VERSION}-fpm" "php${PHP_VERSION}-mysql"
        "php${PHP_VERSION}-curl" "php${PHP_VERSION}-gd" "php${PHP_VERSION}-intl"
        "php${PHP_VERSION}-mbstring" "php${PHP_VERSION}-xml" "php${PHP_VERSION}-zip"
        "php${PHP_VERSION}-opcache" "php${PHP_VERSION}-cli" "php${PHP_VERSION}-common"
        "php${PHP_VERSION}-imagick" "php${PHP_VERSION}-bcmath" "php${PHP_VERSION}-soap"
        "php${PHP_VERSION}-xmlrpc"
    )

    # Add Redis support if configured
    [[ -n "$REDIS_HOST" ]] && php_packages+=("php${PHP_VERSION}-redis")

    if ! apt install -y "${php_packages[@]}"; then
        log_error "Errore installazione PHP"
        return 1
    fi

    log_success "PHP ${PHP_VERSION} installato"
}

configure_php() {
    log_step "Configurazione PHP per performance..."

    # Main PHP configuration
    local php_ini="${PHP_FPM_CONF}/99-wordpress.ini"

    cat > "$php_ini" << EOF
; WordPress Performance Settings - 2025
memory_limit = 512M
upload_max_filesize = 128M
post_max_size = 128M
max_execution_time = 300
max_input_time = 300
max_input_vars = 10000
date.timezone = Europe/Rome

; OPcache Configuration
opcache.enable=1
opcache.enable_cli=1
opcache.memory_consumption=256
opcache.interned_strings_buffer=32
opcache.max_accelerated_files=10000
opcache.max_wasted_percentage=10
opcache.validate_timestamps=0
opcache.revalidate_freq=0
opcache.save_comments=1

; Security Settings
expose_php = Off
display_errors = Off
log_errors = On
allow_url_fopen = Off
allow_url_include = Off

; Performance
realpath_cache_size = 2M
realpath_cache_ttl = 600
EOF

    # PHP-FPM pool configuration
    local pool_conf="${PHP_FPM_POOL}/wordpress.conf"

    cat > "$pool_conf" << EOF
[wordpress]
user = www-data
group = www-data
listen = /run/php/php${PHP_VERSION}-fpm-wordpress.sock
listen.owner = www-data
listen.group = www-data
listen.mode = 0660

pm = dynamic
pm.max_children = 20
pm.start_servers = 4
pm.min_spare_servers = 2
pm.max_spare_servers = 8
pm.max_requests = 500

; Security
php_admin_value[disable_functions] = exec,passthru,shell_exec,system,proc_open,popen
php_admin_flag[allow_url_fopen] = off

; Performance per sito
php_value[memory_limit] = 512M
php_value[max_execution_time] = 300
EOF

    # Restart PHP-FPM
    if ! systemctl restart "php${PHP_VERSION}-fpm"; then
        log_error "Errore riavvio PHP-FPM"
        return 1
    fi

    log_success "PHP configurato"
}

# =============================================================================
# NGINX INSTALLATION
# =============================================================================

install_nginx() {
    log_step "Installazione Nginx..."

    if ! apt install -y nginx; then
        log_error "Errore installazione Nginx"
        return 1
    fi

    # Backup original configuration
    cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.backup.$(date +%Y%m%d)

    configure_nginx_global
    configure_nginx_site

    # Test configuration
    if ! nginx -t; then
        log_error "Configurazione Nginx non valida"
        return 1
    fi

    systemctl restart nginx
    log_success "Nginx installato e configurato"
}

configure_nginx_global() {
    log_step "Configurazione globale Nginx..."

    cat > /etc/nginx/nginx.conf << 'NGINX_CONF_EOF'
user www-data;
worker_processes auto;
worker_rlimit_nofile 65535;
pid /run/nginx.pid;

events {
    worker_connections 4096;
    use epoll;
    multi_accept on;
}

http {
    # Basic Settings
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 30;
    keepalive_requests 1000;
    types_hash_max_size 2048;
    client_max_body_size 128M;
    server_tokens off;

    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    # Security Headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;

    # Compression
    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_types
        application/atom+xml
        application/javascript
        application/json
        application/ld+json
        application/manifest+json
        application/rss+xml
        application/vnd.geo+json
        application/vnd.ms-fontobject
        application/x-font-ttf
        application/x-web-app-manifest+json
        application/xhtml+xml
        application/xml
        font/opentype
        image/bmp
        image/svg+xml
        image/x-icon
        text/cache-manifest
        text/css
        text/plain
        text/vcard
        text/vnd.rim.location.xloc
        text/vtt
        text/x-component
        text/x-cross-domain-policy;

    # Logging
    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                   '$status $body_bytes_sent "$http_referer" '
                   '"$http_user_agent" rt=$request_time';

    access_log /var/log/nginx/access.log main;
    error_log /var/log/nginx/error.log warn;

    # Virtual Host Configs
    include /etc/nginx/conf.d/*.conf;
    include /etc/nginx/sites-enabled/*;
}
NGINX_CONF_EOF
}

configure_nginx_site() {
    log_step "Configurazione sito WordPress..."

    local site_config="${NGINX_SITES_AVAILABLE}/${DOMAIN}"

    cat > "$site_config" << EOF
# WordPress Configuration for ${DOMAIN} - Optimized 2025

server {
    listen 80;
    server_name ${DOMAIN} www.${DOMAIN};
    root /var/www/${DOMAIN};
    index index.php index.html index.htm;

    # Security
    location ~* /(?:uploads|files)/.*\.php$ {
        deny all;
    }

    # Static files caching
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
        access_log off;
    }

    # WordPress permalinks
    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }

    # PHP processing
    location ~ \.php$ {
        try_files \$uri =404;
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_pass unix:/run/php/php${PHP_VERSION}-fpm-wordpress.sock;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;

        # Security headers
        add_header X-Frame-Options "SAMEORIGIN" always;
        add_header X-Content-Type-Options "nosniff" always;
        add_header X-XSS-Protection "1; mode=block" always;
    }

    # Deny access to sensitive files
    location ~* \.(htaccess|htpasswd|ini|log|sh|sql|tar|tgz|gz)$ {
        deny all;
    }

    location ~ /\. {
        deny all;
    }

    # WordPress XML-RPC protection
    location = /xmlrpc.php {
        deny all;
    }

    # Logs
    access_log /var/log/nginx/${DOMAIN}.access.log main;
    error_log /var/log/nginx/${DOMAIN}.error.log warn;
}
EOF

    # Enable site
    ln -sf "$site_config" "${NGINX_SITES_ENABLED}/"
    rm -f "${NGINX_SITES_ENABLED}/default"

    log_success "Sito configurato: $DOMAIN"
}

# =============================================================================
# WORDPRESS INSTALLATION
# =============================================================================

install_wpcli() {
    log_step "Installazione WP-CLI..."

    local wpcli_phar="/tmp/wp-cli.phar"

    if ! curl -o "$wpcli_phar" https://raw.githubusercontent.com/wp-cli/wp-cli/v2.8.1/wp-cli.phar; then
        log_error "Errore download WP-CLI"
        return 1
    fi

    chmod +x "$wpcli_phar"
    mv "$wpcli_phar" /usr/local/bin/wp

    # Verify installation
    if wp --info >/dev/null 2>&1; then
        log_success "WP-CLI installato"
    else
        log_error "Errore verifica WP-CLI"
        return 1
    fi
}

test_database_connection() {
    log_step "Test connessione database..."

    if mysql -h"$DB_HOST" -u"$DB_USER" -p"$DB_PASS" "$DB_NAME" -e "SELECT 1;" >/dev/null 2>&1; then
        log_success "✓ Connessione database OK"
        return 0
    else
        log_error "✗ Connessione database fallita!"
        log_error "Verifica: Host: $DB_HOST, DB: $DB_NAME, User: $DB_USER"
        return 1
    fi
}

install_wordpress() {
    log_step "Installazione WordPress..."

    local wp_dir="/var/www/${DOMAIN}"

    # Create directory
    mkdir -p "$wp_dir"
    cd "$wp_dir"

    # Download WordPress
    if ! sudo -u www-data wp core download --locale="$WP_LOCALE"; then
        log_error "Errore download WordPress"
        return 1
    fi

    # Generate secure database prefix and salts
    local db_prefix="wp_$(openssl rand -hex 3)_"

    # Create wp-config.php
    sudo -u www-data wp config create \
        --dbname="$DB_NAME" \
        --dbuser="$DB_USER" \
        --dbpass="$DB_PASS" \
        --dbhost="$DB_HOST" \
        --dbprefix="$db_prefix" || {
        log_error "Errore creazione wp-config.php"
        return 1
    }

    configure_wordpress_advanced

    # Install WordPress
    sudo -u www-data wp core install \
        --url="http://$DOMAIN" \
        --title="$SITE_NAME" \
        --admin_user="$WP_ADMIN_USER" \
        --admin_password="$WP_ADMIN_PASS" \
        --admin_email="$WP_ADMIN_EMAIL" \
        --skip-email || {
        log_error "Errore installazione WordPress"
        return 1
    }

    log_success "WordPress installato"
}

configure_wordpress_advanced() {
    log_step "Configurazione avanzata WordPress..."

    # Add advanced configurations to wp-config.php
    cat >> wp-config.php << EOF

/* WordPress Security Settings - 2025 */
define('DISALLOW_FILE_EDIT', true);
define('DISALLOW_FILE_MODS', false);
define('AUTOMATIC_UPDATER_DISABLED', false);
define('WP_AUTO_UPDATE_CORE', true);
define('FORCE_SSL_ADMIN', false);
define('WP_DEBUG', false);
define('WP_DEBUG_LOG', false);

/* Performance Settings */
define('WP_MEMORY_LIMIT', '512M');
define('WP_CACHE', true);
define('COMPRESS_CSS', true);
define('COMPRESS_SCRIPTS', true);
define('CONCATENATE_SCRIPTS', false);

/* Security Keys */
EOF

    # Generate and add security salts
    sudo -u www-data wp config shuffle-salts

    # Redis configuration if available
    if [[ -n "$REDIS_HOST" ]]; then
        cat >> wp-config.php << EOF

/* Redis Object Cache */
define('WP_REDIS_HOST', '${REDIS_HOST}');
define('WP_REDIS_PORT', 6379);
define('WP_REDIS_TIMEOUT', 1);
define('WP_REDIS_READ_TIMEOUT', 1);
define('WP_REDIS_DATABASE', 0);
EOF
        log_info "Configurazione Redis aggiunta"
    fi

    log_success "Configurazioni avanzate applicate"
}

# =============================================================================
# PLUGINS INSTALLATION
# =============================================================================

install_essential_plugins() {
    log_step "Installazione plugin essenziali..."

    cd "/var/www/${DOMAIN}"

    # Essential plugins list
    local plugins=(
        "wordfence"
        "wp-optimize"
        "updraftplus"
        "limit-login-attempts-reloaded"
        "ssl-insecure-content-fixer"
        "wp-mail-smtp"
    )

    # Add Redis plugin if configured
    [[ -n "$REDIS_HOST" ]] && plugins+=("redis-cache")

    # Install and activate plugins
    for plugin in "${plugins[@]}"; do
        if sudo -u www-data wp plugin install "$plugin" --activate; then
            log_success "Plugin installato: $plugin"
        else
            log_warn "Errore installazione plugin: $plugin"
        fi
    done

    # Configure Redis Cache if available
    if [[ -n "$REDIS_HOST" ]]; then
        if sudo -u www-data wp redis enable; then
            log_success "Redis Object Cache attivato"
        else
            log_warn "Errore attivazione Redis Cache"
        fi
    fi
}

# =============================================================================
# SSL CONFIGURATION
# =============================================================================

setup_ssl_certificates() {
    [[ "$SETUP_SSL" != true ]] && return 0

    log_step "Configurazione SSL Let's Encrypt..."

    # Install Certbot
    if ! command -v certbot >/dev/null 2>&1; then
        apt install -y snapd
        snap install core
        snap refresh core
        snap install --classic certbot
        ln -sf /snap/bin/certbot /usr/bin/certbot
    fi

    # Try to obtain SSL certificate
    if certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos --email "$WP_ADMIN_EMAIL" 2>/dev/null; then
        log_success "✓ SSL configurato con successo"

        # Update wp-config for SSL
        sed -i "s/define('FORCE_SSL_ADMIN', false);/define('FORCE_SSL_ADMIN', true);/" /var/www/"$DOMAIN"/wp-config.php

        # Update site URL
        cd "/var/www/${DOMAIN}"
        sudo -u www-data wp option update home "https://$DOMAIN"
        sudo -u www-data wp option update siteurl "https://$DOMAIN"

    else
        log_warn "⚠ SSL non configurato (dominio non raggiungibile pubblicamente)"
        log_info "Potrai configurare SSL manualmente quando il dominio sarà attivo"
    fi
}

# =============================================================================
# SECURITY CONFIGURATION
# =============================================================================

configure_security() {
    log_step "Configurazione sicurezza..."

    # Install and configure Fail2ban
    apt install -y fail2ban

    # WordPress filter for Fail2ban
    cat > /etc/fail2ban/filter.d/wordpress.conf << 'FAIL2BAN_FILTER_EOF'
[Definition]
failregex = ^<HOST> .* "POST /wp-login.php
            ^<HOST> .* "POST /xmlrpc.php
ignoreregex =
FAIL2BAN_FILTER_EOF

    # WordPress jail for Fail2ban
    cat > /etc/fail2ban/jail.d/wordpress.conf << 'FAIL2BAN_JAIL_EOF'
[wordpress]
enabled = true
filter = wordpress
logpath = /var/log/nginx/*.access.log
maxretry = 5
bantime = 3600
findtime = 600
action = iptables-multiport[name=wordpress, port="http,https", protocol=tcp]
FAIL2BAN_JAIL_EOF

    # Configure UFW firewall
    configure_firewall

    # Set correct file permissions
    set_wordpress_permissions

    # Restart security services
    systemctl restart fail2ban
    systemctl restart nginx
    systemctl restart "php${PHP_VERSION}-fpm"

    log_success "Sicurezza configurata"
}

configure_firewall() {
    log_step "Configurazione firewall..."

    apt install -y ufw

    # Reset firewall rules
    ufw --force reset

    # Default policies
    ufw default deny incoming
    ufw default allow outgoing

    # Allow essential services
    ufw allow ssh
    ufw allow http
    ufw allow https

    # Enable firewall
    ufw --force enable

    log_success "Firewall configurato"
}

set_wordpress_permissions() {
    log_step "Impostazione permessi WordPress..."

    local wp_dir="/var/www/${DOMAIN}"

    # Set ownership
    chown -R www-data:www-data "$wp_dir"

    # Set directory permissions
    find "$wp_dir" -type d -exec chmod 755 {} \;

    # Set file permissions
    find "$wp_dir" -type f -exec chmod 644 {} \;

    # Secure wp-config.php
    chmod 600 "$wp_dir/wp-config.php"

    log_success "Permessi configurati"
}

# =============================================================================
# MAINTENANCE AND OPTIMIZATION
# =============================================================================

setup_maintenance_jobs() {
    log_step "Configurazione manutenzione automatica..."

    # Create maintenance cron job
    cat > /etc/cron.d/wordpress-maintenance << EOF
# WordPress Maintenance Jobs for ${DOMAIN}

# Core updates (Sunday at 2:00 AM)
0 2 * * 0 www-data cd /var/www/${DOMAIN} && wp core update --quiet

# Plugin updates (Sunday at 2:30 AM)
30 2 * * 0 www-data cd /var/www/${DOMAIN} && wp plugin update --all --quiet

# Database optimization (Sunday at 4:00 AM)
0 4 * * 0 www-data cd /var/www/${DOMAIN} && wp db optimize --quiet

# Clean transients (Daily at 5:00 AM)
0 5 * * * www-data cd /var/www/${DOMAIN} && wp transient delete --all --quiet
EOF

    log_success "Manutenzione automatica configurata"
}

create_management_scripts() {
    log_step "Creazione script di gestione..."

    # Status script
    cat > /usr/local/bin/wp-status.sh << EOF
#!/bin/bash

echo "=== WordPress Status per ${DOMAIN} ==="
echo "Data: \$(date)"
echo "URL: http://${DOMAIN}"
echo
echo "=== Servizi ==="
systemctl is-active nginx && echo "✓ Nginx: Running" || echo "✗ Nginx: Stopped"
systemctl is-active php${PHP_VERSION}-fpm && echo "✓ PHP-FPM: Running" || echo "✗ PHP-FPM: Stopped"
systemctl is-active mysql && echo "✓ MySQL: Running" || echo "✗ MySQL: Not local"
systemctl is-active fail2ban && echo "✓ Fail2ban: Running" || echo "✗ Fail2ban: Stopped"
echo
echo "=== Performance ==="
echo "CPU: \$(top -bn1 | grep 'Cpu(s)' | awk '{print \$2}' | cut -d'%' -f1)%"
echo "Memory: \$(free -h | awk 'NR==2{printf \"Used: %s/%s (%.1f%%)\", \$3,\$2,\$3*100/\$2}')"
echo "Disk: \$(df -h / | awk 'NR==2{print \$3\"/\"\$2\" (\"\$5\")\"}')"
echo "Load: \$(uptime | awk -F'load average:' '{print \$2}' | xargs)"
echo
echo "=== WordPress ==="
cd /var/www/${DOMAIN} 2>/dev/null || exit 1
echo "Version: \$(wp core version 2>/dev/null || echo 'N/A')"
echo "Plugins: \$(wp plugin list --status=active --format=count 2>/dev/null || echo 'N/A') active"
echo "Themes: \$(wp theme list --status=active --format=count 2>/dev/null || echo 'N/A') active"
echo "Database: \$(wp db size 2>/dev/null || echo 'N/A')"
echo
echo "=== Security ==="
echo "Failed login attempts: \$(fail2ban-client status wordpress 2>/dev/null | grep 'Currently failed:' | awk '{print \$3}' || echo 'N/A')"
echo "Banned IPs: \$(fail2ban-client status wordpress 2>/dev/null | grep 'Currently banned:' | awk '{print \$3}' || echo 'N/A')"
EOF

    chmod +x /usr/local/bin/wp-status.sh

    log_success "Script di gestione creati"
}

# =============================================================================
# FINAL SUMMARY
# =============================================================================

show_installation_summary() {
    echo
    echo "=========================================="
    echo "🎉 WORDPRESS INSTALLATO CON SUCCESSO!"
    echo "=========================================="
    echo
    echo "📋 DETTAGLI INSTALLAZIONE:"
    echo "   • Sito: http://$DOMAIN"
    if [[ "$SETUP_SSL" == true ]]; then
        echo "   • Sito SSL: https://$DOMAIN"
    fi
    echo "   • Admin: http://$DOMAIN/wp-admin"
    echo "   • Username: $WP_ADMIN_USER"
    echo "   • Email: $WP_ADMIN_EMAIL"
    echo "   • Database: $DB_HOST/$DB_NAME"
    [[ -n "$REDIS_HOST" ]] && echo "   • Redis: $REDIS_HOST:6379"
    echo
    echo "🔧 SERVIZI ATTIVI:"
    echo "   • Nginx con configurazione ottimizzata"
    echo "   • PHP ${PHP_VERSION} FPM con OPcache"
    echo "   • WordPress ${WP_VERSION} (${WP_LOCALE})"
    echo "   • Plugin di sicurezza installati"
    echo "   • Fail2ban e UFW attivi"
    [[ -n "$REDIS_HOST" ]] && echo "   • Redis Object Cache"
    [[ "$SETUP_SSL" == true ]] && echo "   • SSL/TLS configurato"
    echo
    echo "🛠️ COMANDI UTILI:"
    echo "   • Status: wp-status.sh"
    echo "   • Log Nginx: tail -f /var/log/nginx/${DOMAIN}.access.log"
    echo "   • Restart: systemctl restart nginx php${PHP_VERSION}-fpm"
    echo "   • WordPress CLI: cd /var/www/${DOMAIN} && wp --info"
    echo
    echo "📖 FILE IMPORTANTI:"
    echo "   • Sito: /var/www/${DOMAIN}"
    echo "   • Config Nginx: /etc/nginx/sites-available/${DOMAIN}"
    echo "   • Config PHP: /etc/php/${PHP_VERSION}/fpm/pool.d/wordpress.conf"
    echo "   • Log errori: /var/log/nginx/${DOMAIN}.error.log"
    echo
    echo "🔐 SICUREZZA:"
    echo "   • Firewall UFW attivo (SSH, HTTP, HTTPS)"
    echo "   • Fail2ban configurato per WordPress"
    echo "   • File permissions corretti"
    echo "   • XML-RPC disabilitato"
    echo "   • Plugin Wordfence installato"
    echo
    echo "📝 PROSSIMI PASSI:"
    echo "   1. Configura DNS per puntare a questo server"
    echo "   2. Accedi: http://$DOMAIN/wp-admin"
    echo "   3. Configura plugin Wordfence"
    echo "   4. Configura backup UpdraftPlus"
    echo "   5. Installa e configura tema"
    echo
    echo "=========================================="
    echo "Installazione completata! 🚀"
    echo "=========================================="
}

# =============================================================================
# MAIN FUNCTION
# =============================================================================

main() {
    local start_time
    start_time=$(date +%s)

    echo
    echo "=============================================================="
    echo "🚀 INSTALLAZIONE WORDPRESS OTTIMIZZATA"
    echo "=============================================================="
    echo "Versione: 2025.09 - Script Modulare"
    echo "Data: $(date)"
    echo "=============================================================="
    echo

    # Configuration
    configure_params

    # System preparation
    update_system

    # Core components
    install_php
    configure_php
    install_nginx
    install_wpcli

    # Database verification
    test_database_connection || exit 1

    # WordPress installation
    install_wordpress
    install_essential_plugins

    # Security and SSL
    setup_ssl_certificates
    configure_security

    # Maintenance
    setup_maintenance_jobs
    create_management_scripts

    # Final cleanup
    apt autoremove -y
    apt autoclean

    # Summary
    show_installation_summary

    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - start_time))

    echo
    log_success "🎉 Installazione completata in $duration secondi!"
}

# Error handling
set -euo pipefail
trap 'log_error "Script interrotto alla riga $LINENO"' ERR

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
WORDPRESS_SCRIPT_EOF

    chmod +x "$output_file"
    log_success "Script WordPress generato: $output_file"
}

# =============================================================================
# WORDPRESS VALIDATION FUNCTIONS
# =============================================================================

validate_wordpress_config() {
    local config_file="$1"

    log_step "Validazione configurazione WordPress..."

    # Check required parameters
    local required_params=(
        "DOMAIN"
        "DB_HOST"
        "DB_NAME"
        "DB_USER"
        "DB_PASS"
        "WP_ADMIN_USER"
        "WP_ADMIN_PASS"
        "WP_ADMIN_EMAIL"
    )

    for param in "${required_params[@]}"; do
        if ! grep -q "^$param=" "$config_file"; then
            log_error "Parametro mancante: $param"
            return 1
        fi
    done

    log_success "Configurazione WordPress validata"
}