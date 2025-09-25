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

    # Optional services - Redis
    read -p "Configurare Redis Object Cache? [y/N]: " USE_REDIS
    if [[ "${USE_REDIS,,}" =~ ^(y|yes|s|si)$ ]]; then
        while true; do
            read -p "IP server Redis: " REDIS_HOST
            if validate_ip "$REDIS_HOST"; then
                break
            else
                log_error "Indirizzo IP Redis non valido"
            fi
        done
        read -p "Porta Redis [6379]: " REDIS_PORT
        REDIS_PORT="${REDIS_PORT:-6379}"
        read -s -p "Password Redis [lascia vuoto se nessuna]: " REDIS_PASS
        echo
        read -p "Database Redis [0]: " REDIS_DB
        REDIS_DB="${REDIS_DB:-0}"
    fi

    # Optional services - MinIO
    read -p "Configurare MinIO Object Storage? [y/N]: " USE_MINIO
    if [[ "${USE_MINIO,,}" =~ ^(y|yes|s|si)$ ]]; then
        while true; do
            read -p "Endpoint MinIO (es: https://minio.example.com): " MINIO_ENDPOINT
            if [[ "$MINIO_ENDPOINT" =~ ^https?:// ]]; then
                break
            else
                log_error "Endpoint MinIO non valido (deve iniziare con http:// o https://)"
            fi
        done
        read -p "Access Key MinIO: " MINIO_ACCESS_KEY
        read -s -p "Secret Key MinIO: " MINIO_SECRET_KEY
        echo
        read -p "Nome bucket [wordpress-media]: " MINIO_BUCKET
        MINIO_BUCKET="${MINIO_BUCKET:-wordpress-media}"
        read -p "Regione MinIO [us-east-1]: " MINIO_REGION
        MINIO_REGION="${MINIO_REGION:-us-east-1}"
    fi

    # SMTP Configuration
    read -p "Configurare SMTP per email? [y/N]: " USE_SMTP
    if [[ "${USE_SMTP,,}" =~ ^(y|yes|s|si)$ ]]; then
        read -p "Host SMTP: " SMTP_HOST
        read -p "Porta SMTP [587]: " SMTP_PORT
        SMTP_PORT="${SMTP_PORT:-587}"
        read -p "Username SMTP: " SMTP_USER
        read -s -p "Password SMTP: " SMTP_PASS
        echo
        read -p "Crittografia [TLS/SSL/none]: " SMTP_ENCRYPTION
        SMTP_ENCRYPTION="${SMTP_ENCRYPTION:-TLS}"
        read -p "Email mittente [${WP_ADMIN_EMAIL}]: " SMTP_FROM
        SMTP_FROM="${SMTP_FROM:-$WP_ADMIN_EMAIL}"
    fi

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
    export LC_ALL=C.UTF-8
    export LANG=C.UTF-8

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
                   mysql-client bc locales || {
        log_error "Errore installazione pacchetti base"
        return 1
    }

    # Configure locales
    locale-gen it_IT.UTF-8 en_US.UTF-8
    update-locale LANG=it_IT.UTF-8

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

    # Core PHP packages - Updated September 2025
    local php_packages=(
        "php${PHP_VERSION}" "php${PHP_VERSION}-fpm" "php${PHP_VERSION}-mysql"
        "php${PHP_VERSION}-curl" "php${PHP_VERSION}-gd" "php${PHP_VERSION}-intl"
        "php${PHP_VERSION}-mbstring" "php${PHP_VERSION}-xml" "php${PHP_VERSION}-zip"
        "php${PHP_VERSION}-opcache" "php${PHP_VERSION}-cli" "php${PHP_VERSION}-common"
        "php${PHP_VERSION}-imagick" "php${PHP_VERSION}-bcmath" "php${PHP_VERSION}-soap"
        "php${PHP_VERSION}-xmlrpc" "php${PHP_VERSION}-xsl" "php${PHP_VERSION}-readline"
        "php${PHP_VERSION}-tidy"
        # Security and development packages
        "php${PHP_VERSION}-dev"
        # SEO Image optimization packages
        "imagemagick" "webp" "jpegoptim" "optipng" "pngquant"
        # System packages for SSL/TLS security
        "software-properties-common" "ca-certificates" "lsb-release" "apt-transport-https"
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

; Security - Updated September 2025
php_admin_value[disable_functions] = exec,passthru,shell_exec,system,proc_open,popen,eval,base64_decode,file_get_contents,fopen,readfile,show_source
php_admin_flag[allow_url_fopen] = off
php_admin_flag[allow_url_include] = off
php_admin_flag[expose_php] = off
php_admin_flag[log_errors] = on
php_admin_flag[display_errors] = off
php_admin_flag[display_startup_errors] = off
php_admin_value[session.cookie_httponly] = 1
php_admin_value[session.cookie_secure] = 1
php_admin_value[session.use_strict_mode] = 1

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

        # SEO Headers
        add_header Referrer-Policy "strict-origin-when-cross-origin" always;
        add_header Permissions-Policy "geolocation=(), microphone=(), camera=()" always;
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

    # SEO-friendly robots.txt
    location = /robots.txt {
        access_log off;
        log_not_found off;
        expires 1d;
        add_header Cache-Control "public";
    }

    # XML Sitemaps
    location ~* \.(xml|xsl)$ {
        expires 1h;
        add_header Cache-Control "public";
        access_log off;
    }

    # Optimize feed requests
    location ~* \/feed\/ {
        expires 1h;
        add_header Cache-Control "public";
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

    # Remove existing file if present
    rm -f "$wpcli_phar"

    # Download WP-CLI with proper error handling
    if ! curl -L -o "$wpcli_phar" "https://github.com/wp-cli/wp-cli/releases/download/v2.8.1/wp-cli-2.8.1.phar"; then
        log_warn "Fallback al download diretto..."
        if ! wget -O "$wpcli_phar" "https://github.com/wp-cli/wp-cli/releases/download/v2.8.1/wp-cli-2.8.1.phar"; then
            log_error "Errore download WP-CLI da entrambe le fonti"
            return 1
        fi
    fi

    # Verify file size (should be > 1MB)
    local file_size=$(stat --format=%s "$wpcli_phar" 2>/dev/null || echo 0)
    if [ "$file_size" -lt 1048576 ]; then
        log_error "File WP-CLI scaricato incompleto (${file_size} bytes)"
        return 1
    fi

    # Verify it's a valid phar file
    if ! php -r "try { new Phar('$wpcli_phar'); echo 'OK'; } catch (Exception \$e) { echo 'FAIL'; exit(1); }" >/dev/null 2>&1; then
        log_error "File WP-CLI non valido"
        return 1
    fi

    chmod +x "$wpcli_phar"
    mv "$wpcli_phar" /usr/local/bin/wp

    # Configure WP-CLI for LXC container environment
    configure_wpcli_for_lxc

    # Verify installation with timeout
    if timeout 10 wp --info >/dev/null 2>&1; then
        log_success "WP-CLI installato e verificato"
        wp --version
    else
        log_error "Errore verifica WP-CLI"
        return 1
    fi
}

# Configure WP-CLI for LXC container to avoid --allow-root warnings
configure_wpcli_for_lxc() {
    log_info "Configurazione WP-CLI per container LXC..."

    # Create www-data user if it doesn't exist
    if ! id www-data >/dev/null 2>&1; then
        useradd -r -s /bin/bash www-data
        log_info "Utente www-data creato"
    fi

    # Ensure www-data has a home directory
    if [ ! -d /home/www-data ]; then
        mkdir -p /home/www-data
        chown www-data:www-data /home/www-data
    fi

    # Create WP-CLI config to suppress root warnings in LXC
    mkdir -p /root/.wp-cli
    cat > /root/.wp-cli/config.yml << 'EOF'
# WP-CLI configuration for LXC container
# This configuration allows safe root operation in containerized environments
path: /var/www
apache_modules:
  - mod_rewrite
disabled_commands: []

# Suppress warnings for containerized environments
quiet: false
color: true
EOF

    # Create a minimal helper script for file permissions
    cat > /usr/local/bin/wp-cli-lxc-helper.php << 'EOF'
<?php
/**
 * WP-CLI LXC Container Helper - Minimal version
 * Handles basic file permissions in LXC container
 */

// Only run if WP-CLI is available and WordPress is loaded
if (defined('WP_CLI') && WP_CLI && function_exists('get_option')) {
    // Simple hook to ensure proper file ownership after major operations
    WP_CLI::add_hook('after_wp_config_create', function() {
        if (file_exists('wp-config.php')) {
            chmod('wp-config.php', 0644);
        }
    });
}
EOF

    # Create environment variable to suppress warnings
    echo 'export WP_CLI_CONFIG_PATH="/root/.wp-cli/config.yml"' >> /root/.bashrc
    echo 'export WP_CLI_ALLOW_ROOT=1' >> /root/.bashrc

    # Create a simple alias that automatically adds --allow-root
    echo 'alias wp="/usr/local/bin/wp --allow-root"' >> /root/.bashrc

    # Make it available immediately
    export WP_CLI_CONFIG_PATH="/root/.wp-cli/config.yml"
    export WP_CLI_ALLOW_ROOT=1

    log_success "WP-CLI configurato per ambiente LXC"
}

# Get WordPress admin user for plugin configurations
get_wp_admin_user() {
    local admin_user
    # Try to get the first administrator user
    admin_user=$(wp --allow-root user list --role=administrator --field=user_login --format=csv --quiet 2>/dev/null | head -1)

    if [[ -n "$admin_user" ]]; then
        echo "$admin_user"
        return 0
    else
        # Fallback to the username used during installation
        echo "${WP_ADMIN_USER:-admin}"
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
    if ! wp --allow-root core download --locale="$WP_LOCALE"; then
        log_error "Errore download WordPress"
        return 1
    fi

    # Generate secure database prefix and salts
    local db_prefix="wp_$(openssl rand -hex 3)_"

    # Create wp-config.php
    wp --allow-root config create \
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
    wp --allow-root core install \
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

/* WordPress Security Settings - September 2025 */
define('DISALLOW_FILE_EDIT', true);
define('DISALLOW_FILE_MODS', false);
define('AUTOMATIC_UPDATER_DISABLED', false);
define('WP_AUTO_UPDATE_CORE', true);
define('FORCE_SSL_ADMIN', true);
define('WP_DEBUG', false);
define('WP_DEBUG_LOG', false);

/* Additional Security Settings - 2025 Best Practices */
define('WP_DISABLE_FATAL_ERROR_HANDLER', true);
define('COOKIE_DOMAIN', '.${DOMAIN}');
define('COOKIEHASH', md5('${DOMAIN}'));
define('WP_CONTENT_URL', 'https://${DOMAIN}/wp-content');
define('WP_SITEURL', 'https://${DOMAIN}');
define('WP_HOME', 'https://${DOMAIN}');
define('WP_HTTP_BLOCK_EXTERNAL', false);
define('WP_ACCESSIBLE_HOSTS', '*.${DOMAIN},api.wordpress.org,downloads.wordpress.org');
define('DISALLOW_UNFILTERED_HTML', true);

/* Performance Settings */
define('WP_MEMORY_LIMIT', '512M');
define('WP_CACHE', true);
define('COMPRESS_CSS', true);
define('COMPRESS_SCRIPTS', true);
define('CONCATENATE_SCRIPTS', false);

/* SEO Performance Optimizations */
define('AUTOSAVE_INTERVAL', 300);
define('WP_POST_REVISIONS', 3);
define('MEDIA_TRASH', true);
define('EMPTY_TRASH_DAYS', 30);

/* Image Optimization */
define('WP_IMAGE_EDITOR', 'WP_Image_Editor_Imagick');
define('BIG_IMAGE_SIZE_THRESHOLD', 2048);
define('WP_DEFAULT_THEME', 'generatepress');

/* Database Optimization */
define('WP_ALLOW_REPAIR', false);
define('AUTOMATIC_UPDATER_DISABLED', false);
define('WP_AUTO_UPDATE_CORE', 'minor');

/* Security Keys */
EOF

    # Generate and add security salts
    wp --allow-root config shuffle-salts

    # Redis configuration if available
    if [[ "${USE_REDIS:-}" == "y"* ]] || [[ "${USE_REDIS,,}" =~ ^(yes|s|si)$ ]]; then
        cat >> wp-config.php << EOF

/* Redis Object Cache Configuration */
define('WP_REDIS_HOST', '${REDIS_HOST}');
define('WP_REDIS_PORT', ${REDIS_PORT});
define('WP_REDIS_TIMEOUT', 1);
define('WP_REDIS_READ_TIMEOUT', 1);
define('WP_REDIS_DATABASE', ${REDIS_DB});
EOF
        if [[ -n "$REDIS_PASS" ]]; then
            cat >> wp-config.php << EOF
define('WP_REDIS_PASSWORD', '${REDIS_PASS}');
EOF
        fi
        log_info "Configurazione Redis aggiunta"
    fi

    # MinIO S3 configuration if available
    if [[ "${USE_MINIO:-}" == "y"* ]] || [[ "${USE_MINIO,,}" =~ ^(yes|s|si)$ ]]; then
        cat >> wp-config.php << EOF

/* MinIO S3 Object Storage Configuration */
define('AS3CF_SETTINGS', serialize(array(
    'provider' => 'other',
    'access-key-id' => '${MINIO_ACCESS_KEY}',
    'secret-access-key' => '${MINIO_SECRET_KEY}',
    'bucket' => '${MINIO_BUCKET}',
    'region' => '${MINIO_REGION}',
    'domain' => 'cloudfront',
    'cloudfront' => '${MINIO_ENDPOINT}',
    'enable-object-prefix' => true,
    'object-prefix' => 'wp-content/uploads/',
    'use-server-roles' => false,
    'copy-to-s3' => true,
    'serve-from-s3' => true,
)));
EOF
        log_info "Configurazione MinIO S3 aggiunta"
    fi

    # SMTP configuration if available
    if [[ "${USE_SMTP:-}" == "y"* ]] || [[ "${USE_SMTP,,}" =~ ^(yes|s|si)$ ]]; then
        cat >> wp-config.php << EOF

/* SMTP Email Configuration */
define('WPMS_ON', true);
define('WPMS_MAIL_FROM', '${SMTP_FROM}');
define('WPMS_MAIL_FROM_NAME', '${SITE_NAME}');
define('WPMS_MAILER', 'smtp');
define('WPMS_SET_RETURN_PATH', true);
define('WPMS_SMTP_HOST', '${SMTP_HOST}');
define('WPMS_SMTP_PORT', ${SMTP_PORT});
define('WPMS_SMTP_AUTH', true);
define('WPMS_SMTP_AUTOTLS', true);
define('WPMS_SMTP_SECURE', '${SMTP_ENCRYPTION,,}');
define('WPMS_SMTP_USER', '${SMTP_USER}');
define('WPMS_SMTP_PASS', '${SMTP_PASS}');
EOF
        log_info "Configurazione SMTP aggiunta"
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
        # SEO Essential Plugins
        "wordpress-seo"
        "google-sitemap-generator"
        "wp-super-cache"
        "autoptimize"
        "smush"
        "broken-link-checker"
        "google-analytics-dashboard-for-wp"
        "schema"
        "amp"
        "web-stories"
        # Performance SEO
        "wp-fastest-cache"
        "lazy-load"
        "webp-express"
        # GDPR/Privacy Compliance
        "cookie-law-info"
        "wp-gdpr-compliance"
        "complianz-gdpr"
        "gdpr-cookie-consent"
        "privacy-policy-generator"
    )

    # Add Redis plugin if configured
    if [[ "${USE_REDIS:-}" == "y"* ]] || [[ "${USE_REDIS,,}" =~ ^(yes|s|si)$ ]]; then
        plugins+=("redis-cache")
    fi

    # Add MinIO S3 plugin if configured
    if [[ "${USE_MINIO:-}" == "y"* ]] || [[ "${USE_MINIO,,}" =~ ^(yes|s|si)$ ]]; then
        plugins+=("amazon-s3-and-cloudfront")
    fi

    # Add SMTP plugin if configured
    if [[ "${USE_SMTP:-}" == "y"* ]] || [[ "${USE_SMTP,,}" =~ ^(yes|s|si)$ ]]; then
        plugins+=("wp-mail-smtp")
    fi

    # Verify WordPress admin user exists before plugin installation
    local admin_user
    admin_user=$(get_wp_admin_user)
    if [[ -z "$admin_user" ]]; then
        log_warn "Nessun utente amministratore trovato. Creazione utente admin..."
        # Create admin user if missing
        wp --allow-root user create "${WP_ADMIN_USER:-admin}" "${WP_ADMIN_EMAIL:-admin@example.com}" \
            --role=administrator --user_pass="${WP_ADMIN_PASS:-password}" --quiet 2>/dev/null || true
        admin_user="${WP_ADMIN_USER:-admin}"
    fi

    log_info "Utilizzando utente amministratore: $admin_user"

    # Install and activate plugins
    for plugin in "${plugins[@]}"; do
        # First install without activation
        if wp --allow-root plugin install "$plugin" --quiet 2>/dev/null; then
            # Then activate separately to avoid user ID issues
            if wp --allow-root plugin activate "$plugin" --quiet 2>/dev/null; then
                log_success "Plugin installato: $plugin"
            else
                log_warn "Plugin installato ma non attivato: $plugin"
            fi
        else
            log_warn "Errore installazione plugin: $plugin"
        fi
    done

    # Configure all essential plugins
    configure_essential_plugins
}

configure_essential_plugins() {
    log_step "Configurazione avanzata plugin essenziali..."

    cd "/var/www/${DOMAIN}"

    # 1. Configure Wordfence Security
    configure_wordfence

    # 2. Configure WP Optimize
    configure_wp_optimize

    # 3. Configure Yoast SEO
    configure_yoast_advanced

    # 4. Configure Autoptimize
    configure_autoptimize

    # 5. Configure Smush Image Optimization
    configure_smush

    # 6. Configure WebP Express
    configure_webp_express

    # 7. Configure Redis Cache if available
    if [[ "${USE_REDIS:-}" == "y"* ]] || [[ "${USE_REDIS,,}" =~ ^(yes|s|si)$ ]]; then
        configure_redis_cache
    fi

    # 8. Configure S3 Plugin if available
    if [[ "${USE_MINIO:-}" == "y"* ]] || [[ "${USE_MINIO,,}" =~ ^(yes|s|si)$ ]]; then
        configure_s3_plugin
    fi

    # 9. Configure SMTP Plugin if available
    if [[ "${USE_SMTP:-}" == "y"* ]] || [[ "${USE_SMTP,,}" =~ ^(yes|s|si)$ ]]; then
        configure_smtp_plugin
    fi

    # 10. Configure Schema Plugin
    configure_schema_plugin

    # 11. Configure Google Analytics
    configure_google_analytics

    # 12. Configure AMP
    configure_amp_plugin

    # 13. Configure GDPR/Privacy Compliance
    configure_gdpr_compliance

    log_success "Tutti i plugin sono stati configurati ottimamente"
}

configure_wordfence() {
    log_step "Configurazione Wordfence Security..."

    # Advanced Wordfence configuration
    wp --allow-root option update wordfence_version "7.9.0" --quiet 2>/dev/null || true

    # Wordfence settings
    local wf_settings='{
        "apiKey": "",
        "isPaid": 0,
        "whitelisted": [],
        "bannedURLs": [],
        "bannedUserAgents": [],
        "whitelistedServices": ["127.0.0.1"],
        "firewallEnabled": 1,
        "blockFakeBots": 1,
        "blockScanners": 1,
        "blockSpambots": 1,
        "blockXSS": 1,
        "blockSQLi": 1,
        "blockBruteBots": 1,
        "maxExecutionTime": 300,
        "maxGlobalRequests": 240,
        "maxRequestsHumans": 60,
        "maxRequestsCrawlers": 30,
        "bruteForceEnabled": 1,
        "maxLoginAttempts": 5,
        "countryBlocking": 0,
        "loginSecurityEnabled": 1,
        "twoFactorEnabled": 1,
        "scanEnabled": 1,
        "scansEnabled_checkGSB": 1,
        "scansEnabled_checkHowGetIPs": 1,
        "scansEnabled_suspiciousAdminUsers": 1,
        "alertEmails_scanIssues": "'${WP_ADMIN_EMAIL}'"
    }'

    wp --allow-root option update wf_settings "$wf_settings" --format=json --quiet 2>/dev/null || log_warn "Wordfence configurazione manuale richiesta"

    log_success "Wordfence configurato"
}

configure_wp_optimize() {
    log_step "Configurazione WP Optimize..."

    # WP Optimize settings
    local wpo_settings='{
        "enable_cache": true,
        "enable_gzip_compression": true,
        "enable_browser_cache": true,
        "cache_expiry_time": 86400,
        "enable_minify": true,
        "minify_css": true,
        "minify_js": true,
        "remove_query_strings": true,
        "defer_js": true,
        "defer_jquery": false,
        "preload_cache": true,
        "cache_mobile": true,
        "cache_logged_in_users": false,
        "enable_database_optimization": true,
        "auto_cleanup": true,
        "cleanup_frequency": "weekly"
    }'

    wp --allow-root option update wpo_cache_config "$wpo_settings" --format=json --quiet 2>/dev/null || true

    # Enable cache
    wp --allow-root option update wpo_cache_enabled 1 --quiet 2>/dev/null || true

    log_success "WP Optimize configurato"
}

configure_yoast_advanced() {
    log_step "Configurazione avanzata Yoast SEO..."

    # Advanced Yoast configuration
    local yoast_settings='{
        "disableadvanced_meta": false,
        "onpage_indexability": true,
        "content_analysis_active": true,
        "keyword_analysis_active": true,
        "enable_admin_bar_menu": true,
        "enable_cornerstone_content": true,
        "enable_xml_sitemap": true,
        "enable_text_link_counter": true,
        "breadcrumbs-enable": true,
        "breadcrumbs-home": "Home",
        "breadcrumbs-blog": "Blog",
        "opengraph": true,
        "twitter": true,
        "social_url_facebook": "",
        "social_url_twitter": "",
        "social_url_instagram": "",
        "social_url_linkedin": "",
        "company_name": "'${SITE_NAME}'",
        "company_logo": "",
        "website_name": "'${SITE_NAME}'",
        "alternate_website_name": ""
    }'

    wp --allow-root option update wpseo "$yoast_settings" --format=json --quiet 2>/dev/null || true

    # XML Sitemaps configuration
    local xml_settings='{
        "sitemap_index": "on",
        "post_types-post": "on",
        "post_types-page": "on",
        "taxonomies-category": "on",
        "taxonomies-post_tag": "on",
        "user_sitemap": "off",
        "disable_author_sitemap": true,
        "disable_author_noposts": true,
        "max_entries_per_sitemap": 1000
    }'

    wp --allow-root option update wpseo_xml "$xml_settings" --format=json --quiet 2>/dev/null || true

    # Title templates
    wp --allow-root option update wpseo_titles '{
        "title-home-wpseo": "'${SITE_NAME}' %%page%% %%sep%% %%sitename%%",
        "title-post": "%%title%% %%page%% %%sep%% %%sitename%%",
        "title-page": "%%title%% %%page%% %%sep%% %%sitename%%",
        "title-category": "%%term_title%% Archives %%page%% %%sep%% %%sitename%%",
        "title-post_tag": "%%term_title%% Archives %%page%% %%sep%% %%sitename%%",
        "metadesc-home-wpseo": "",
        "metadesc-post": "%%excerpt%%",
        "metadesc-page": "%%excerpt%%"
    }' --format=json --quiet 2>/dev/null || true

    log_success "Yoast SEO configurato avanzato"
}

configure_autoptimize() {
    log_step "Configurazione Autoptimize..."

    # Autoptimize advanced settings
    local ao_settings='{
        "autoptimize_optimize_logged": "on",
        "autoptimize_html": "on",
        "autoptimize_html_keepcomments": "",
        "autoptimize_js": "on",
        "autoptimize_js_exclude": "wp-includes/js/dist/, wp-includes/js/tinymce/, js/jquery/jquery.js, js/jquery/jquery.min.js",
        "autoptimize_js_defer": "on",
        "autoptimize_js_forcehead": "",
        "autoptimize_css": "on",
        "autoptimize_css_exclude": "",
        "autoptimize_css_defer": "on",
        "autoptimize_css_defer_inline": "on",
        "autoptimize_css_inline": "on",
        "autoptimize_css_datauris": "on",
        "autoptimize_cdn_url": "",
        "autoptimize_enable_site_config": "on",
        "autoptimize_cache_nogzip": "",
        "autoptimize_optimize_checkout": "",
        "autoptimize_optimize_cart": ""
    }'

    # Apply settings one by one (more reliable)
    wp --allow-root option update autoptimize_html "on" --quiet 2>/dev/null || true
    wp --allow-root option update autoptimize_js "on" --quiet 2>/dev/null || true
    wp --allow-root option update autoptimize_js_defer "on" --quiet 2>/dev/null || true
    wp --allow-root option update autoptimize_css "on" --quiet 2>/dev/null || true
    wp --allow-root option update autoptimize_css_defer "on" --quiet 2>/dev/null || true

    log_success "Autoptimize configurato"
}

configure_smush() {
    log_step "Configurazione Smush Image Optimization..."

    local smush_settings='{
        "auto": 1,
        "lossy": 0,
        "strip_exif": 1,
        "resize": 1,
        "detection": 1,
        "original": 0,
        "backup": 0,
        "png_to_jpg": 1,
        "lazy_load": 1,
        "usage": 1
    }'

    wp --allow-root option update wp-smush-settings "$smush_settings" --format=json --quiet 2>/dev/null || true

    log_success "Smush configurato"
}

configure_webp_express() {
    log_step "Configurazione WebP Express..."

    local webp_settings='{
        "operation-mode": "varied-responses",
        "cache-control-custom": "",
        "cache-control": "one-week",
        "image-types": 3,
        "source-folder": "auto",
        "destination-folder": "separate",
        "destination-extension": "append",
        "destination-structure": "image-roots",
        "quality-auto": true,
        "quality-specific": 85,
        "encoding": "lossy",
        "near-lossless-quality": 60,
        "alpha-quality": 85,
        "low-memory": true,
        "log-conversions": false,
        "log-conversions-in-db": false
    }'

    wp --allow-root option update webp-express-settings "$webp_settings" --format=json --quiet 2>/dev/null || true

    log_success "WebP Express configurato"
}

configure_redis_cache() {
    log_step "Configurazione Redis Object Cache..."

    # Test Redis connection first
    if test_redis_connection "$REDIS_HOST" "$REDIS_PORT" "$REDIS_PASS"; then
        if wp --allow-root redis enable --quiet 2>/dev/null; then
            # Configure Redis settings
            wp --allow-root config set WP_REDIS_CLIENT predis --quiet 2>/dev/null || true
            wp --allow-root config set WP_REDIS_SELECTIVE_FLUSH true --quiet 2>/dev/null || true

            log_success "Redis Object Cache attivato e configurato"
        else
            log_warn "Errore attivazione Redis Cache"
        fi
    else
        log_warn "Redis configurato ma connessione non disponibile"
    fi
}

configure_s3_plugin() {
    log_step "Configurazione Amazon S3 and CloudFront..."

    if test_minio_connection "$MINIO_ENDPOINT" "$MINIO_ACCESS_KEY" "$MINIO_SECRET_KEY"; then
        # Create bucket if it doesn't exist
        create_minio_bucket "$MINIO_ENDPOINT" "$MINIO_ACCESS_KEY" "$MINIO_SECRET_KEY" "$MINIO_BUCKET"

        # Configure S3 plugin
        wp --allow-root option update amazon_s3_and_cloudfront_settings '{
            "provider": "other",
            "access-key-id": "'${MINIO_ACCESS_KEY}'",
            "secret-access-key": "'${MINIO_SECRET_KEY}'",
            "bucket": "'${MINIO_BUCKET}'",
            "region": "'${MINIO_REGION}'",
            "domain": "cloudfront",
            "cloudfront": "'${MINIO_ENDPOINT}'",
            "enable-object-prefix": true,
            "object-prefix": "wp-content/uploads/",
            "copy-to-s3": true,
            "serve-from-s3": true,
            "remove-local-file": false
        }' --format=json --quiet 2>/dev/null || true

        log_success "MinIO S3 configurato e bucket creato/verificato"
    else
        log_warn "MinIO configurato ma connessione non disponibile"
    fi
}

configure_smtp_plugin() {
    log_step "Configurazione WP Mail SMTP..."

    local smtp_settings='{
        "mail": {
            "from_email": "'${SMTP_FROM}'",
            "from_name": "'${SITE_NAME}'",
            "mailer": "smtp",
            "return_path": true,
            "from_email_force": true,
            "from_name_force": false
        },
        "smtp": {
            "host": "'${SMTP_HOST}'",
            "port": '${SMTP_PORT}',
            "encryption": "'${SMTP_ENCRYPTION,,}'",
            "auth": true,
            "user": "'${SMTP_USER}'",
            "pass": "'${SMTP_PASS}'"
        }
    }'

    wp --allow-root option update wp_mail_smtp "$smtp_settings" --format=json --quiet 2>/dev/null || true

    log_success "SMTP configurato"
}

configure_schema_plugin() {
    log_step "Configurazione Schema Plugin..."

    local schema_settings='{
        "schema_type": "Organization",
        "site_name": "'${SITE_NAME}'",
        "site_logo": "",
        "default_image": "",
        "knowledge_graph": true,
        "publisher": true,
        "social_profile": [],
        "corporate_contacts": [],
        "breadcrumb": true,
        "search_box": true
    }'

    wp --allow-root option update schema_wp_settings "$schema_settings" --format=json --quiet 2>/dev/null || true

    log_success "Schema Plugin configurato"
}

configure_google_analytics() {
    log_step "Configurazione Google Analytics..."

    local ga_settings='{
        "analytics_profile": "",
        "manual_ua_code_hidden": "",
        "hide_admin_bar_reports": "",
        "dashboards_disabled": "",
        "anonymize_ips": true,
        "demographics": true,
        "ignore_users": ["administrator"],
        "track_user": false,
        "events_mode": false,
        "affiliate_links": false,
        "download_extensions": "zip,mp3,mpeg,pdf,docx,pptx,xlsx,rar,wma,mov,wmv,avi,flv,wav"
    }'

    wp --allow-root option update exactmetrics_settings "$ga_settings" --format=json --quiet 2>/dev/null || true

    log_success "Google Analytics configurato"
}

configure_amp_plugin() {
    log_step "Configurazione AMP Plugin..."

    local amp_settings='{
        "theme_support": "standard",
        "supported_post_types": ["post", "page"],
        "analytics": {},
        "gtag_id": "",
        "enable_response_caching": true,
        "enable_ssr_style_sheets": true,
        "enable_optimizer": true
    }'

    wp --allow-root option update amp-options "$amp_settings" --format=json --quiet 2>/dev/null || true

    log_success "AMP configurato"
}

configure_gdpr_compliance() {
    log_step "Configurazione compliance GDPR/Privacy..."

    cd "/var/www/${DOMAIN}"

    # Configure Cookie Law Info (banner principale)
    configure_cookie_law_info

    # Configure Complianz GDPR
    configure_complianz_gdpr

    # Create privacy policy and cookie policy pages
    create_privacy_pages

    # Configure WordPress privacy settings
    configure_wordpress_privacy

    # Configure Google Analytics for GDPR
    configure_ga_gdpr

    # Add privacy-compliant contact forms
    configure_privacy_forms

    log_success "Compliance GDPR/Privacy configurata completamente"
}

configure_cookie_law_info() {
    log_step "Configurazione Cookie Law Info..."

    # Advanced Cookie Law Info settings
    local cli_settings='{
        "is_on": true,
        "logging_on": false,
        "show_once_yn": false,
        "notify_animate_hide": true,
        "notify_animate_show": true,
        "background": "#000000",
        "text": "#ffffff",
        "show_once": 10000,
        "border": "#b1a6a6c2",
        "border_on": true,
        "font_family": "inherit",
        "button_1_text": "Accetta",
        "button_1_action": "CONSTANT_OPEN_URL",
        "button_1_url": "#cookie_action_close_header",
        "button_1_as_button": true,
        "button_1_new_win": false,
        "button_2_text": "Leggi di più",
        "button_2_action": "CONSTANT_OPEN_URL",
        "button_2_url": "https://'${DOMAIN}'/privacy-policy/",
        "button_2_as_button": false,
        "button_2_new_win": false,
        "notify_position_horizontal": "center",
        "notify_position_vertical": "bottom",
        "scroll_close": false,
        "scroll_close_reload": false,
        "accept_close_reload": false,
        "showagain_tab": true,
        "showagain_background": "#fff",
        "showagain_border": "#000",
        "showagain_div_id": "",
        "showagain_x_position": "100px",
        "bar_heading_text": "",
        "notify_div_id": "#cookie-law-info-bar",
        "popup_overlay": true,
        "bar_heading_text": "Cookie e Privacy",
        "notify_message": "Questo sito utilizza cookie per migliorare la tua esperienza. Proseguendo la navigazione acconsenti all'\''uso dei cookie.",
        "popup_showagain_position": "bottom-right",
        "widget_position": "left"
    }'

    wp --allow-root option update cookielawinfo_settings "$cli_settings" --format=json --quiet 2>/dev/null || true

    log_success "Cookie Law Info configurato"
}

configure_complianz_gdpr() {
    log_step "Configurazione Complianz GDPR..."

    # Complianz comprehensive settings
    local complianz_settings='{
        "wizard_completed_once": true,
        "configuration_complete": true,
        "privacy_statement": true,
        "cookie_statement": true,
        "disclaimer": false,
        "impressum": false,
        "terms_conditions": false,
        "processing_agreements": true,
        "dpo": false,
        "region": "eu",
        "privacy_legislation": "gdpr",
        "cookie_domain": "'${DOMAIN}'",
        "consenttype": "optin",
        "hide_cookiebanner_on_lawful_basis": false,
        "use_country": "all",
        "compile_statistics": "no",
        "cookie_retention_in_days": 365,
        "consent_for_anonymous_tracking": true
    }'

    wp --allow-root option update complianz_options "$complianz_settings" --format=json --quiet 2>/dev/null || true

    # Configure cookie categories
    local cookie_categories='{
        "functional": {
            "name": "Cookie Funzionali",
            "description": "Necessari per il funzionamento del sito",
            "required": true
        },
        "marketing": {
            "name": "Cookie Marketing",
            "description": "Utilizzati per tracciamento e pubblicità",
            "required": false
        },
        "statistics": {
            "name": "Cookie Statistici",
            "description": "Utilizzati per analisi e statistiche",
            "required": false
        }
    }'

    wp --allow-root option update complianz_cookie_categories "$cookie_categories" --format=json --quiet 2>/dev/null || true

    log_success "Complianz GDPR configurato"
}

create_privacy_pages() {
    log_step "Creazione pagine Privacy Policy e Cookie Policy..."

    # Create Privacy Policy page
    create_privacy_policy_page

    # Create Cookie Policy page
    create_cookie_policy_page

    # Create Data Protection page
    create_data_protection_page

    # Create Terms and Conditions page
    create_terms_conditions_page

    log_success "Pagine privacy create"
}

create_privacy_policy_page() {
    local privacy_content="<h1>Privacy Policy</h1>

<p><em>Ultimo aggiornamento: $(date '+%d/%m/%Y')</em></p>

<h2>1. Informazioni Generali</h2>
<p><strong>${SITE_NAME}</strong> (di seguito \"noi\", \"nostro\" o \"il sito\") rispetta la privacy degli utenti e si impegna a proteggere i dati personali raccolti attraverso questo sito web.</p>

<h2>2. Titolare del Trattamento</h2>
<p><strong>Denominazione:</strong> ${SITE_NAME}<br>
<strong>Dominio:</strong> ${DOMAIN}<br>
<strong>Email:</strong> ${WP_ADMIN_EMAIL}</p>

<h2>3. Dati Raccolti</h2>
<h3>3.1 Dati forniti volontariamente</h3>
<ul>
<li>Nome e cognome</li>
<li>Indirizzo email</li>
<li>Dati inseriti nei moduli di contatto</li>
<li>Commenti e recensioni</li>
</ul>

<h3>3.2 Dati raccolti automaticamente</h3>
<ul>
<li>Indirizzo IP</li>
<li>Informazioni sul browser e dispositivo</li>
<li>Dati di navigazione e utilizzo</li>
<li>Cookie e tecnologie simili</li>
</ul>

<h2>4. Finalità del Trattamento</h2>
<p>I tuoi dati vengono utilizzati per:</p>
<ul>
<li>Fornire i servizi richiesti</li>
<li>Rispondere a domande e richieste</li>
<li>Migliorare l'esperienza utente</li>
<li>Analisi statistiche anonimizzate</li>
<li>Adempimenti legali</li>
</ul>

<h2>5. Base Giuridica</h2>
<p>Il trattamento si basa su:</p>
<ul>
<li><strong>Consenso:</strong> per newsletter e marketing</li>
<li><strong>Interesse legittimo:</strong> per analisi e miglioramenti</li>
<li><strong>Esecuzione contratto:</strong> per servizi richiesti</li>
<li><strong>Obbligo legale:</strong> per adempimenti normativi</li>
</ul>

<h2>6. Condivisione Dati</h2>
<p>I dati possono essere condivisi con:</p>
<ul>
<li>Fornitori di servizi tecnici (hosting, email)</li>
<li>Strumenti di analisi (Google Analytics)</li>
<li>Autorità competenti quando richiesto dalla legge</li>
</ul>

<h2>7. Conservazione Dati</h2>
<p>I dati vengono conservati per il tempo necessario alle finalità del trattamento:</p>
<ul>
<li>Dati di contatto: fino a revoca del consenso</li>
<li>Dati di navigazione: 26 mesi</li>
<li>Log del server: 12 mesi</li>
</ul>

<h2>8. Diritti dell'Interessato</h2>
<p>Hai diritto a:</p>
<ul>
<li>Accedere ai tuoi dati personali</li>
<li>Rettificare dati inesatti</li>
<li>Cancellare i dati (\"diritto all'oblio\")</li>
<li>Limitare il trattamento</li>
<li>Portabilità dei dati</li>
<li>Opporsi al trattamento</li>
<li>Revocare il consenso</li>
</ul>

<h2>9. Cookie</h2>
<p>Il sito utilizza cookie per migliorare l'esperienza utente. Consulta la nostra <a href=\"/cookie-policy/\">Cookie Policy</a> per dettagli.</p>

<h2>10. Sicurezza</h2>
<p>Implementiamo misure di sicurezza tecniche e organizzative per proteggere i tuoi dati da accessi non autorizzati, perdita o distruzione.</p>

<h2>11. Modifiche alla Privacy Policy</h2>
<p>Ci riserviamo il diritto di aggiornare questa informativa. Le modifiche saranno pubblicate su questa pagina con indicazione della data di aggiornamento.</p>

<h2>12. Contatti</h2>
<p>Per esercitare i tuoi diritti o per domande sulla privacy, contattaci:</p>
<ul>
<li><strong>Email:</strong> ${WP_ADMIN_EMAIL}</li>
<li><strong>Sito:</strong> <a href=\"https://${DOMAIN}/contatti/\">Modulo di contatto</a></li>
</ul>

<p><em>Questa informativa è conforme al GDPR (Regolamento UE 2016/679) e al Codice Privacy italiano (D.Lgs. 196/2003 e s.m.i.).</em></p>"

    # Create page
    wp --allow-root post create --post_type=page --post_title="Privacy Policy" --post_content="$privacy_content" --post_status=publish --post_name="privacy-policy" --quiet 2>/dev/null || true

    # Set as privacy page
    local privacy_page_id=$(wp --allow-root post list --post_type=page --name="privacy-policy" --field=ID --quiet 2>/dev/null)
    if [[ -n "$privacy_page_id" ]]; then
        wp --allow-root option update wp_page_for_privacy_policy "$privacy_page_id" --quiet
    fi

    log_info "Privacy Policy page creata"
}

create_cookie_policy_page() {
    local cookie_content="<h1>Cookie Policy</h1>

<p><em>Ultimo aggiornamento: $(date '+%d/%m/%Y')</em></p>

<h2>1. Cosa sono i Cookie</h2>
<p>I cookie sono piccoli file di testo che vengono memorizzati sul tuo dispositivo quando visiti un sito web. Permettono al sito di ricordare le tue preferenze e migliorare la tua esperienza di navigazione.</p>

<h2>2. Tipi di Cookie Utilizzati</h2>

<h3>2.1 Cookie Tecnici (Necessari)</h3>
<p><strong>Finalità:</strong> Essenziali per il funzionamento del sito</p>
<p><strong>Base giuridica:</strong> Interesse legittimo</p>
<p><strong>Durata:</strong> Sessione</p>
<p><strong>Esempi:</strong></p>
<ul>
<li>Cookie di sessione PHP</li>
<li>Cookie di sicurezza</li>
<li>Cookie per il carrello acquisti</li>
</ul>

<h3>2.2 Cookie di Preferenze</h3>
<p><strong>Finalità:</strong> Ricordare le tue scelte e preferenze</p>
<p><strong>Base giuridica:</strong> Consenso</p>
<p><strong>Durata:</strong> 12 mesi</p>
<p><strong>Esempi:</strong></p>
<ul>
<li>Lingua preferita</li>
<li>Tema scuro/chiaro</li>
<li>Impostazioni accessibilità</li>
</ul>

<h3>2.3 Cookie Statistici</h3>
<p><strong>Finalità:</strong> Analizzare l'utilizzo del sito per miglioramenti</p>
<p><strong>Base giuridica:</strong> Consenso</p>
<p><strong>Durata:</strong> 26 mesi</p>
<p><strong>Provider:</strong> Google Analytics</p>
<ul>
<li>_ga: Identifica utenti unici</li>
<li>_gid: Identifica utenti unici per 24h</li>
<li>_gat: Limita la frequenza di richieste</li>
</ul>

<h3>2.4 Cookie di Marketing</h3>
<p><strong>Finalità:</strong> Pubblicità personalizzata e remarketing</p>
<p><strong>Base giuridica:</strong> Consenso</p>
<p><strong>Durata:</strong> 90 giorni</p>
<p><strong>Provider:</strong> Google Ads, Facebook Pixel</p>

<h2>3. Gestione dei Cookie</h2>

<h3>3.1 Consenso</h3>
<p>Al primo accesso al sito, ti viene mostrato un banner informativo per richiedere il consenso all'uso dei cookie non tecnici.</p>

<h3>3.2 Revoca del Consenso</h3>
<p>Puoi revocare il consenso in qualsiasi momento:</p>
<ul>
<li>Utilizzando il link \"Gestisci cookie\" nel footer</li>
<li>Cancellando i cookie dal browser</li>
<li>Contattandoci via email</li>
</ul>

<h3>3.3 Configurazione Browser</h3>
<p>Puoi gestire i cookie direttamente nel tuo browser:</p>
<ul>
<li><strong>Chrome:</strong> Settings > Privacy > Cookies</li>
<li><strong>Firefox:</strong> Options > Privacy > Cookies</li>
<li><strong>Safari:</strong> Preferences > Privacy > Cookies</li>
<li><strong>Edge:</strong> Settings > Privacy > Cookies</li>
</ul>

<h2>4. Cookie di Terze Parti</h2>

<h3>4.1 Google Analytics</h3>
<p><strong>Finalità:</strong> Analisi statistica anonimizzata</p>
<p><strong>Privacy Policy:</strong> <a href=\"https://policies.google.com/privacy\">Google Privacy Policy</a></p>
<p><strong>Opt-out:</strong> <a href=\"https://tools.google.com/dlpage/gaoptout\">Google Analytics Opt-out</a></p>

<h3>4.2 Google Fonts</h3>
<p><strong>Finalità:</strong> Visualizzazione font web</p>
<p><strong>Implementazione:</strong> Self-hosted (nessun dato inviato a Google)</p>

<h3>4.3 Cloudflare</h3>
<p><strong>Finalità:</strong> CDN e sicurezza</p>
<p><strong>Cookie:</strong> __cfduid (sessione)</p>
<p><strong>Privacy Policy:</strong> <a href=\"https://www.cloudflare.com/privacy/\">Cloudflare Privacy Policy</a></p>

<h2>5. Trasferimenti Internazionali</h2>
<p>Alcuni cookie possono comportare trasferimenti di dati verso paesi terzi (USA). Questi trasferimenti sono basati su:</p>
<ul>
<li>Decisioni di adeguatezza della Commissione Europea</li>
<li>Clausole contrattuali tipo</li>
<li>Certificazioni Privacy Shield (dove applicable)</li>
</ul>

<h2>6. Diritti dell'Interessato</h2>
<p>Hai gli stessi diritti previsti nella <a href=\"/privacy-policy/\">Privacy Policy</a>, incluso il diritto di opporti al trattamento per finalità di marketing.</p>

<h2>7. Contatti</h2>
<p>Per domande sui cookie o per esercitare i tuoi diritti:</p>
<ul>
<li><strong>Email:</strong> ${WP_ADMIN_EMAIL}</li>
<li><strong>Oggetto:</strong> \"Cookie Policy - ${DOMAIN}\"</li>
</ul>

<div id=\"cookie-settings\" style=\"margin-top: 30px; padding: 20px; background: #f9f9f9; border-radius: 5px;\">
<h3>🍪 Gestisci le tue preferenze cookie</h3>
<p>Clicca sul pulsante sottostante per modificare le tue preferenze sui cookie:</p>
<button onclick=\"if(typeof(CLI)!=='undefined'){CLI.showSettings();}else{alert('Sistema di gestione cookie in caricamento...');}\" style=\"background: #007acc; color: white; padding: 10px 20px; border: none; border-radius: 5px; cursor: pointer;\">Gestisci Cookie</button>
</div>"

    # Create page
    wp --allow-root post create --post_type=page --post_title="Cookie Policy" --post_content="$cookie_content" --post_status=publish --post_name="cookie-policy" --quiet 2>/dev/null || true

    log_info "Cookie Policy page creata"
}

create_data_protection_page() {
    local data_protection_content="<h1>Protezione Dati Personali</h1>

<p><em>Ultimo aggiornamento: $(date '+%d/%m/%Y')</em></p>

<h2>1. I Tuoi Diritti GDPR</h2>
<p>Come utente del nostro sito web, hai diritti specifici riguardo ai tuoi dati personali secondo il GDPR:</p>

<h3>1.1 Diritto di Accesso (Art. 15 GDPR)</h3>
<p>Puoi richiedere una copia di tutti i dati personali che abbiamo su di te, incluso:</p>
<ul>
<li>Quali dati abbiamo</li>
<li>Perché li trattiamo</li>
<li>Chi può accedervi</li>
<li>Per quanto tempo li conserviamo</li>
</ul>

<h3>1.2 Diritto di Rettifica (Art. 16 GDPR)</h3>
<p>Puoi chiedere la correzione di dati personali inesatti o incompleti.</p>

<h3>1.3 Diritto di Cancellazione (Art. 17 GDPR)</h3>
<p>Puoi richiedere la cancellazione dei tuoi dati quando:</p>
<ul>
<li>Non sono più necessari</li>
<li>Revochi il consenso</li>
<li>Sono stati trattati illecitamente</li>
<li>Ti opponi al trattamento</li>
</ul>

<h3>1.4 Diritto di Limitazione (Art. 18 GDPR)</h3>
<p>Puoi chiedere di limitare il trattamento quando:</p>
<ul>
<li>Contesti l'esattezza dei dati</li>
<li>Il trattamento è illecito ma preferisci la limitazione</li>
<li>Ti servono per far valere un diritto in giudizio</li>
</ul>

<h3>1.5 Diritto di Portabilità (Art. 20 GDPR)</h3>
<p>Puoi ottenere i tuoi dati in formato strutturato e leggibile da una macchina.</p>

<h3>1.6 Diritto di Opposizione (Art. 21 GDPR)</h3>
<p>Puoi opporti al trattamento basato su interesse legittimo o per finalità di marketing diretto.</p>

<h2>2. Come Esercitare i Tuoi Diritti</h2>

<h3>2.1 Richiesta via Email</h3>
<p>Invia una email a: <strong>${WP_ADMIN_EMAIL}</strong></p>
<p>Specifica nell'oggetto: \"Richiesta GDPR - [Tipo di richiesta]\"</p>

<h3>2.2 Informazioni da Fornire</h3>
<ul>
<li>Nome e cognome</li>
<li>Email associata all'account</li>
<li>Descrizione dettagliata della richiesta</li>
<li>Copia di documento d'identità (per verifica)</li>
</ul>

<h3>2.3 Tempi di Risposta</h3>
<p>Risponderemo entro <strong>30 giorni</strong> dalla ricezione della richiesta.</p>

<h2>3. Misure di Sicurezza</h2>

<h3>3.1 Sicurezza Tecnica</h3>
<ul>
<li>Crittografia SSL/TLS</li>
<li>Firewall applicativo</li>
<li>Monitoraggio accessi</li>
<li>Backup crittografati</li>
<li>Aggiornamenti di sicurezza regolari</li>
</ul>

<h3>3.2 Sicurezza Organizzativa</h3>
<ul>
<li>Accesso limitato ai dati</li>
<li>Formazione del personale</li>
<li>Procedure di incident response</li>
<li>Audit periodici</li>
</ul>

<h2>4. Data Breach</h2>
<p>In caso di violazione dei dati personali:</p>
<ul>
<li>Notificheremo l'autorità competente entro 72 ore</li>
<li>Ti informeremo se sussiste un rischio elevato</li>
<li>Implementeremo misure correttive immediate</li>
</ul>

<h2>5. Bambini e Minori</h2>
<p>I nostri servizi non sono destinati a minori di 16 anni. Se veniamo a conoscenza di dati di minori raccolti senza consenso genitoriale, li cancelleremo immediatamente.</p>

<h2>6. Trasferimenti Internazionali</h2>
<p>I tuoi dati potrebbero essere trasferiti verso:</p>
<ul>
<li><strong>USA:</strong> Google (Analytics), Cloudflare</li>
<li><strong>Garanzie:</strong> Clausole contrattuali tipo, certificazioni adequacy</li>
</ul>

<h2>7. Conservazione Dati</h2>
<table border=\"1\" style=\"width:100%; border-collapse: collapse;\">
<tr><th>Tipologia Dato</th><th>Periodo di Conservazione</th><th>Base Giuridica</th></tr>
<tr><td>Dati account utente</td><td>Fino a cancellazione account</td><td>Consenso</td></tr>
<tr><td>Dati di navigazione</td><td>26 mesi</td><td>Interesse legittimo</td></tr>
<tr><td>Log di sicurezza</td><td>12 mesi</td><td>Obbligo legale</td></tr>
<tr><td>Email marketing</td><td>Fino a disiscrizione</td><td>Consenso</td></tr>
<tr><td>Commenti pubblici</td><td>Fino a richiesta cancellazione</td><td>Interesse legittimo</td></tr>
</table>

<h2>8. Autorità di Controllo</h2>
<p>Hai diritto di presentare reclamo all'autorità di controllo:</p>
<p><strong>Garante per la Protezione dei Dati Personali</strong><br>
Piazza Venezia 11, 00187 Roma<br>
Tel: 06.696771<br>
Email: garante@gpdp.it<br>
Web: <a href=\"https://www.garanteprivacy.it\">www.garanteprivacy.it</a></p>

<h2>9. Aggiornamenti</h2>
<p>Questa pagina viene aggiornata regolarmente per riflettere cambiamenti normativi o nelle nostre pratiche di trattamento dati.</p>

<h2>10. Contatti DPO</h2>
<p>Per questioni specifiche sulla protezione dati:</p>
<ul>
<li><strong>Email:</strong> ${WP_ADMIN_EMAIL}</li>
<li><strong>Oggetto:</strong> \"DPO Request - Data Protection\"</li>
</ul>"

    wp --allow-root post create --post_type=page --post_title="Protezione Dati" --post_content="$data_protection_content" --post_status=publish --post_name="data-protection" --quiet 2>/dev/null || true

    log_info "Data Protection page creata"
}

create_terms_conditions_page() {
    local terms_content="<h1>Termini e Condizioni</h1>

<p><em>Ultimo aggiornamento: $(date '+%d/%m/%Y')</em></p>

<h2>1. Accettazione dei Termini</h2>
<p>L'accesso e l'utilizzo del sito web <strong>${DOMAIN}</strong> comporta l'accettazione integrale dei presenti Termini e Condizioni.</p>

<h2>2. Descrizione del Servizio</h2>
<p><strong>${SITE_NAME}</strong> fornisce contenuti informativi e servizi attraverso il presente sito web.</p>

<h2>3. Uso Consentito</h2>
<p>È consentito utilizzare il sito per:</p>
<ul>
<li>Consultare contenuti e informazioni</li>
<li>Utilizzare i servizi offerti</li>
<li>Condividere contenuti nel rispetto delle regole</li>
</ul>

<h2>4. Uso Vietato</h2>
<p>È vietato:</p>
<ul>
<li>Utilizzare il sito per scopi illegali</li>
<li>Compromettere la sicurezza del sito</li>
<li>Copiare contenuti senza autorizzazione</li>
<li>Inviare spam o contenuti dannosi</li>
</ul>

<h2>5. Proprietà Intellettuale</h2>
<p>Tutti i contenuti del sito (testi, immagini, loghi, software) sono protetti da diritti di proprietà intellettuale e appartengono a <strong>${SITE_NAME}</strong> o ai rispettivi proprietari.</p>

<h2>6. Privacy e Dati Personali</h2>
<p>Il trattamento dei dati personali è disciplinato dalla nostra <a href=\"/privacy-policy/\">Privacy Policy</a> e dalla <a href=\"/cookie-policy/\">Cookie Policy</a>.</p>

<h2>7. Limitazione di Responsabilità</h2>
<p><strong>${SITE_NAME}</strong> non è responsabile per:</p>
<ul>
<li>Interruzioni temporanee del servizio</li>
<li>Danni derivanti dall'uso del sito</li>
<li>Contenuti di siti terzi collegati</li>
<li>Perdita di dati</li>
</ul>

<h2>8. Modifiche ai Termini</h2>
<p>Ci riserviamo il diritto di modificare i presenti termini. Le modifiche saranno pubblicate su questa pagina e entreranno in vigore dalla pubblicazione.</p>

<h2>9. Legge Applicabile</h2>
<p>I presenti termini sono disciplinati dalla legge italiana. Per controversie è competente il Foro di [Città].</p>

<h2>10. Contatti</h2>
<p>Per domande sui termini e condizioni:</p>
<ul>
<li><strong>Email:</strong> ${WP_ADMIN_EMAIL}</li>
<li><strong>Sito:</strong> ${DOMAIN}</li>
</ul>"

    wp --allow-root post create --post_type=page --post_title="Termini e Condizioni" --post_content="$terms_content" --post_status=publish --post_name="termini-condizioni" --quiet 2>/dev/null || true

    log_info "Terms and Conditions page creata"
}

configure_wordpress_privacy() {
    log_step "Configurazione privacy WordPress nativa..."

    # Enable privacy features
    wp --allow-root option update wp_privacy_policy_content_template_active 1 --quiet

    # Configure comment moderation
    wp --allow-root option update comment_moderation 1 --quiet
    wp --allow-root option update moderation_notify 1 --quiet

    # Configure user registration
    wp --allow-root option update default_role subscriber --quiet
    wp --allow-root option update users_can_register 0 --quiet

    # Configure data export/erase settings
    wp --allow-root option update wp_user_request_cleanup_interval 86400 --quiet

    log_success "WordPress privacy configurato"
}

configure_ga_gdpr() {
    log_step "Configurazione Google Analytics GDPR-compliant..."

    # Update Google Analytics settings for GDPR compliance
    local ga_gdpr_settings='{
        "anonymize_ips": true,
        "demographics": false,
        "track_user": false,
        "events_mode": false,
        "affiliate_links": false,
        "ignore_users": ["administrator", "editor"],
        "cookie_consent": true,
        "display_features": false,
        "enhanced_link_attribution": false
    }'

    wp --allow-root option update exactmetrics_settings "$ga_gdpr_settings" --format=json --quiet 2>/dev/null || true

    log_success "Google Analytics configurato per GDPR"
}

configure_privacy_forms() {
    log_step "Configurazione moduli privacy-compliant..."

    # Install Contact Form 7 if not present
    if ! wp --allow-root plugin is-installed contact-form-7 --quiet 2>/dev/null; then
        wp --allow-root plugin install contact-form-7 --activate --quiet 2>/dev/null || true
    fi

    # Create GDPR-compliant contact form
    create_privacy_contact_form

    log_success "Moduli privacy configurati"
}

create_privacy_contact_form() {
    # Contact form with GDPR compliance
    local form_content='<label> Il tuo nome (richiesto)
    [text* your-name] </label>

<label> La tua email (richiesto)
    [email* your-email] </label>

<label> Oggetto
    [text your-subject] </label>

<label> Il tuo messaggio
    [textarea your-message] </label>

[acceptance acceptance-privacy] Accetto la <a href="/privacy-policy/" target="_blank">Privacy Policy</a> e autorizzo il trattamento dei miei dati personali per rispondere alla mia richiesta. *

[acceptance acceptance-marketing] Accetto di ricevere comunicazioni marketing (opzionale)

[submit "Invia"]'

    local mail_content="Messaggio da: [your-name] <[your-email]>
Oggetto: [your-subject]

Messaggio:
[your-message]

--
Questo messaggio è stato inviato tramite il modulo di contatto su ${DOMAIN}
Privacy policy accettata: [acceptance-privacy]
Marketing accettato: [acceptance-marketing]"

    # Create contact form via WP-CLI
    wp --allow-root contact-form-7 create --title="Contatto Privacy-Compliant" --form="$form_content" --mail-body="$mail_content" --quiet 2>/dev/null || true

    log_info "Contact form GDPR-compliant creato"
}

# =============================================================================
# THEME AND TEMPLATE OPTIMIZATION
# =============================================================================

install_optimized_theme() {
    log_step "Installazione tema ottimizzato per performance..."

    cd "/var/www/${DOMAIN}"

    # Install GeneratePress (free version)
    if wp --allow-root theme install generatepress --activate --quiet; then
        log_success "GeneratePress installato e attivato"

        # Configure GeneratePress for performance
        configure_generatepress_performance

        # Install child theme for customizations
        create_child_theme

        # Optimize theme settings
        optimize_theme_settings

    else
        log_warn "Errore installazione GeneratePress, uso tema di default"
        # Configure default theme
        configure_default_theme
    fi

    # Install and configure Elementor (optional but recommended)
    install_elementor

    log_success "Tema ottimizzato configurato"
}

configure_generatepress_performance() {
    log_step "Configurazione GeneratePress per performance..."

    # GeneratePress settings optimized for speed
    local gp_settings='{
        "container_width": 1200,
        "container_alignment": "center",
        "layout_setting": "sidebar-right",
        "blog_layout_setting": "right-sidebar",
        "single_layout_setting": "right-sidebar",
        "page_layout_setting": "no-sidebar",
        "footer_layout_setting": "footer-bar",
        "back_to_top": "enable",
        "navigation_search": "",
        "navigation_alignment": "left",
        "header_layout_setting": "fluid-header",
        "site_title": "'${SITE_NAME}'",
        "hide_tagline": false,
        "logo_width": "",
        "retina_logo": "",
        "inline_logo_site_branding": false
    }'

    wp --allow-root option update generate_settings "$gp_settings" --format=json --quiet 2>/dev/null || true

    # Performance-focused customizer settings
    configure_customizer_performance

    log_success "GeneratePress configurato per performance"
}

create_child_theme() {
    log_step "Creazione child theme..."

    local theme_dir="/var/www/${DOMAIN}/wp-content/themes"
    local child_dir="${theme_dir}/generatepress-child"

    # Create child theme directory
    mkdir -p "$child_dir"

    # Create style.css
    cat > "${child_dir}/style.css" << EOF
/*
Theme Name: GeneratePress Child - Performance Optimized
Description: Child theme of GeneratePress optimized for speed and SEO
Template: generatepress
Version: 1.0.0
*/

/* Import parent theme styles */
@import url("../generatepress/style.min.css");

/* Performance optimizations */
.wp-block-image img {
    height: auto;
    max-width: 100%;
}

/* Critical CSS for above-the-fold */
.site-header {
    background: #fff;
    box-shadow: 0 2px 5px rgba(0,0,0,0.1);
}

.main-navigation {
    font-weight: 500;
}

/* Async font loading */
@font-display: swap;

/* Lazy loading optimization */
img[data-src] {
    opacity: 0;
    transition: opacity 0.3s;
}

img[data-loaded="true"] {
    opacity: 1;
}

/* Core Web Vitals optimizations */
.site-content {
    min-height: 60vh;
}

/* Mobile-first responsive design */
@media (max-width: 768px) {
    .container {
        padding: 0 20px;
    }
}
EOF

    # Create functions.php
    cat > "${child_dir}/functions.php" << 'CHILD_FUNCTIONS_EOF'
<?php
/**
 * GeneratePress Child Theme Functions
 * Performance and SEO optimized
 */

// Prevent direct access
if (!defined('ABSPATH')) {
    exit;
}

// Theme setup
add_action('after_setup_theme', 'generatepress_child_setup');
function generatepress_child_setup() {
    // Add theme support for post thumbnails
    add_theme_support('post-thumbnails');

    // Add theme support for HTML5
    add_theme_support('html5', array(
        'search-form',
        'comment-form',
        'comment-list',
        'gallery',
        'caption',
        'script',
        'style'
    ));

    // Add theme support for responsive embeds
    add_theme_support('responsive-embeds');

    // Add theme support for editor styles
    add_theme_support('editor-styles');
}

// Enqueue scripts and styles
add_action('wp_enqueue_scripts', 'generatepress_child_scripts', 15);
function generatepress_child_scripts() {
    // Dequeue parent theme styles and enqueue minified version
    wp_dequeue_style('generate-style');
    wp_enqueue_style('generate-style-min', get_template_directory_uri() . '/style.min.css');

    // Enqueue child theme styles
    wp_enqueue_style('generatepress-child-style', get_stylesheet_uri(), array('generate-style-min'));

    // Preload critical resources
    add_action('wp_head', 'add_critical_resource_hints', 5);
}

// Critical resource hints
function add_critical_resource_hints() {
    // Preload critical CSS
    echo '<link rel="preload" href="' . get_stylesheet_uri() . '" as="style" onload="this.onload=null;this.rel=\'stylesheet\'">';

    // DNS prefetch for external resources
    echo '<link rel="dns-prefetch" href="//fonts.googleapis.com">';
    echo '<link rel="dns-prefetch" href="//fonts.gstatic.com">';
}

// Performance optimizations
add_action('init', 'child_theme_performance_optimizations');
function child_theme_performance_optimizations() {
    // Remove query strings from static resources
    add_filter('script_loader_src', 'remove_script_version', 15, 1);
    add_filter('style_loader_src', 'remove_script_version', 15, 1);

    // Optimize images
    add_filter('wp_image_editors', 'child_theme_image_editors');

    // Enable SVG support
    add_filter('wp_check_filetype_and_ext', 'allow_svg_upload', 10, 4);
    add_filter('upload_mimes', 'svg_upload_allow');
}

function remove_script_version($src) {
    if (strpos($src, 'ver=')) {
        $src = remove_query_arg('ver', $src);
    }
    return $src;
}

function child_theme_image_editors($editors) {
    $editors = array('WP_Image_Editor_Imagick', 'WP_Image_Editor_GD');
    return $editors;
}

function allow_svg_upload($data, $file, $filename, $mimes) {
    $filetype = wp_check_filetype($filename, $mimes);
    return [
        'ext' => $filetype['ext'],
        'type' => $filetype['type'],
        'proper_filename' => $data['proper_filename']
    ];
}

function svg_upload_allow($mimes) {
    $mimes['svg'] = 'image/svg+xml';
    return $mimes;
}

// SEO optimizations
add_action('wp_head', 'child_theme_seo_optimizations', 1);
function child_theme_seo_optimizations() {
    // Add viewport meta tag
    echo '<meta name="viewport" content="width=device-width, initial-scale=1.0, viewport-fit=cover">';

    // Add theme color for mobile browsers
    echo '<meta name="theme-color" content="#ffffff">';

    // Add structured data breadcrumbs
    if (function_exists('yoast_breadcrumb')) {
        add_action('generate_before_main_content', 'add_yoast_breadcrumbs');
    }
}

function add_yoast_breadcrumbs() {
    yoast_breadcrumb('<nav class="breadcrumbs">', '</nav>');
}

// Core Web Vitals optimizations
add_action('wp_footer', 'add_web_vitals_optimizations');
function add_web_vitals_optimizations() {
    // Add critical JavaScript inline
    echo '<script>
        // Intersection Observer for lazy loading
        if ("IntersectionObserver" in window) {
            const imageObserver = new IntersectionObserver((entries, observer) => {
                entries.forEach(entry => {
                    if (entry.isIntersecting) {
                        const img = entry.target;
                        img.src = img.dataset.src;
                        img.classList.remove("lazy");
                        img.setAttribute("data-loaded", "true");
                        observer.unobserve(img);
                    }
                });
            });

            document.querySelectorAll("img[data-src]").forEach(img => {
                imageObserver.observe(img);
            });
        }
    </script>';
}

// Database optimization hooks
add_action('wp_loaded', 'child_theme_db_optimizations');
function child_theme_db_optimizations() {
    // Limit post revisions
    if (!defined('WP_POST_REVISIONS')) {
        define('WP_POST_REVISIONS', 3);
    }

    // Disable pingbacks
    add_filter('xmlrpc_enabled', '__return_false');
    add_filter('wp_headers', 'disable_x_pingback');
}

function disable_x_pingback($headers) {
    unset($headers['X-Pingback']);
    return $headers;
}
CHILD_FUNCTIONS_EOF

    # Activate child theme
    wp --allow-root theme activate generatepress-child --quiet 2>/dev/null || true

    chown -R www-data:www-data "$child_dir"

    log_success "Child theme creato e attivato"
}

configure_customizer_performance() {
    log_step "Configurazione Customizer per performance..."

    # Typography settings for performance
    wp --allow-root option update generate_font_manager_google_fonts '' --quiet 2>/dev/null || true

    # Color settings
    local colors='{
        "accent_color": "#007acc",
        "accent_color_hover": "#005a99",
        "text_color": "#333333",
        "link_color": "#007acc",
        "link_color_hover": "#005a99"
    }'

    wp --allow-root option update generate_colors "$colors" --format=json --quiet 2>/dev/null || true

    # Spacing settings for mobile optimization
    local spacing='{
        "mobile_menu_breakpoint": "768",
        "content_padding_top": "40px",
        "content_padding_bottom": "40px",
        "sidebar_width": "25%"
    }'

    wp --allow-root option update generate_spacing "$spacing" --format=json --quiet 2>/dev/null || true

    log_success "Customizer configurato"
}

optimize_theme_settings() {
    log_step "Ottimizzazione impostazioni tema..."

    # WordPress core settings for performance
    wp --allow-root option update thumbnail_size_w 150 --quiet
    wp --allow-root option update thumbnail_size_h 150 --quiet
    wp --allow-root option update medium_size_w 300 --quiet
    wp --allow-root option update medium_size_h 300 --quiet
    wp --allow-root option update large_size_w 1024 --quiet
    wp --allow-root option update large_size_h 1024 --quiet

    # Enable responsive images
    wp --allow-root option update medium_large_size_w 768 --quiet
    wp --allow-root option update medium_large_size_h 0 --quiet

    # Reading settings for SEO
    wp --allow-root option update posts_per_page 10 --quiet
    wp --allow-root option update posts_per_rss 10 --quiet
    wp --allow-root option update rss_use_excerpt 1 --quiet

    # Discussion settings for performance
    wp --allow-root option update default_ping_status "closed" --quiet
    wp --allow-root option update default_comment_status "open" --quiet

    log_success "Impostazioni tema ottimizzate"
}

configure_default_theme() {
    log_step "Configurazione tema di default..."

    # If GeneratePress fails, optimize default theme
    local active_theme=$(wp --allow-root theme list --status=active --field=name --quiet 2>/dev/null || echo "")

    if [[ -n "$active_theme" ]]; then
        log_info "Configurazione tema attivo: $active_theme"

        # Basic performance optimizations for any theme
        optimize_theme_settings

        # Add basic performance CSS
        local style_file="/var/www/${DOMAIN}/wp-content/themes/${active_theme}/style.css"
        if [[ -f "$style_file" ]]; then
            cat >> "$style_file" << 'DEFAULT_CSS_EOF'

/* Performance optimizations */
img {
    height: auto;
    max-width: 100%;
}

.wp-block-image {
    max-width: 100%;
    height: auto;
}

/* Mobile optimization */
@media (max-width: 768px) {
    body {
        font-size: 16px;
        line-height: 1.6;
    }
}
DEFAULT_CSS_EOF
        fi
    fi

    log_success "Tema di default configurato"
}

install_elementor() {
    log_step "Installazione Elementor (opzionale)..."

    # Install Elementor only if user wants it
    if [[ "${INSTALL_ELEMENTOR:-}" == "true" ]]; then
        if wp --allow-root plugin install elementor --activate --quiet 2>/dev/null; then
            # Configure Elementor for performance
            configure_elementor_performance
            log_success "Elementor installato e configurato"
        else
            log_warn "Errore installazione Elementor"
        fi
    else
        log_info "Elementor non richiesto, saltato"
    fi
}

configure_elementor_performance() {
    log_step "Configurazione Elementor per performance..."

    # Elementor performance settings
    local elementor_settings='{
        "css_print_method": "internal_embedding",
        "font_display": "swap",
        "disable_color_schemes": "yes",
        "disable_typography_schemes": "yes",
        "optimized_dom_output": "enabled",
        "optimized_control_loading": "enabled"
    }'

    wp --allow-root option update elementor_performance_settings "$elementor_settings" --format=json --quiet 2>/dev/null || true

    log_success "Elementor configurato per performance"
}

# =============================================================================
# SEO CONFIGURATION
# =============================================================================

configure_seo_basics() {
    log_step "Configurazione SEO di base..."

    cd "/var/www/${DOMAIN}"

    # Create robots.txt
    cat > robots.txt << EOF
User-agent: *
Allow: /

# WordPress directories
Disallow: /wp-admin/
Disallow: /wp-includes/
Disallow: /wp-content/plugins/
Disallow: /wp-content/cache/
Disallow: /wp-content/themes/
Disallow: /trackback/
Disallow: /comments/
Disallow: */trackback/
Disallow: */comments/
Disallow: *?*
Disallow: *?

# WordPress files
Disallow: /wp-login.php
Disallow: /wp-register.php
Disallow: /wp-config.php
Disallow: /readme.html
Disallow: /license.txt

# Allow important SEO files
Allow: /wp-content/uploads/
Allow: /wp-*.png
Allow: /wp-*.jpg
Allow: /wp-*.jpeg
Allow: /wp-*.gif
Allow: /wp-*.js
Allow: /wp-*.css

# Sitemap
Sitemap: https://${DOMAIN}/sitemap_index.xml
Sitemap: https://${DOMAIN}/sitemap.xml
EOF

    # Create .htaccess for Apache fallback (if needed)
    cat > .htaccess << 'HTACCESS_EOF'
# BEGIN WordPress SEO
<IfModule mod_rewrite.c>
RewriteEngine On
RewriteBase /

# Force HTTPS
RewriteCond %{HTTPS} off
RewriteRule ^(.*)$ https://%{HTTP_HOST}%{REQUEST_URI} [L,R=301]

# Remove www (optional - configure based on preference)
# RewriteCond %{HTTP_HOST} ^www\.(.*)$ [NC]
# RewriteRule ^(.*)$ https://%1/$1 [R=301,L]

# WordPress permalink structure
RewriteRule ^index\.php$ - [L]
RewriteCond %{REQUEST_FILENAME} !-f
RewriteCond %{REQUEST_FILENAME} !-d
RewriteRule . /index.php [L]
</IfModule>

# Browser caching for SEO
<IfModule mod_expires.c>
ExpiresActive on
ExpiresByType text/css "access plus 1 year"
ExpiresByType application/javascript "access plus 1 year"
ExpiresByType image/png "access plus 1 year"
ExpiresByType image/jpg "access plus 1 year"
ExpiresByType image/jpeg "access plus 1 year"
ExpiresByType image/gif "access plus 1 year"
</IfModule>

# Gzip compression
<IfModule mod_deflate.c>
AddOutputFilterByType DEFLATE text/html text/plain text/xml text/css text/javascript application/javascript application/x-javascript
</IfModule>
# END WordPress SEO
HTACCESS_EOF

    # Set WordPress SEO basics via WP-CLI
    configure_yoast_seo

    # Configure other SEO plugins
    configure_seo_plugins

    log_success "Configurazioni SEO di base applicate"
}

configure_yoast_seo() {
    log_step "Configurazione Yoast SEO..."

    # Basic Yoast SEO settings
    wp --allow-root option update wpseo '{
        "ms_defaults_set": true,
        "version": "22.0",
        "disableadvanced_meta": false,
        "onpage_indexability": true,
        "content_analysis_active": true,
        "keyword_analysis_active": true,
        "enable_admin_bar_menu": true,
        "enable_cornerstone_content": true,
        "enable_xml_sitemap": true,
        "enable_text_link_counter": true,
        "show_onboarding_notice": false,
        "first_activated_on": false,
        "myyoast_api_request_failed": false,
        "plugin_suggestions_done": true,
        "dismiss_configuration_workout_notice": true,
        "dismiss_premium_deactivated_notice": true,
        "workouts_data": false,
        "importers_deactivated": true,
        "activation_redirect_timestamp_not_installed": 1
    }' --format=json 2>/dev/null || log_warn "Yoast SEO non ancora attivo"

    # Enable XML sitemaps
    wp --allow-root option update wpseo_xml '{
        "sitemap_index": "on",
        "post_types-post": "on",
        "post_types-page": "on",
        "taxonomies-category": "on",
        "taxonomies-post_tag": "on",
        "author_sitemap": "on",
        "disable_author_sitemap": true,
        "disable_author_noposts": true
    }' --format=json 2>/dev/null || log_warn "Configurazione Yoast XML non applicata"

    log_info "Yoast SEO configurato (potrebbe richiedere configurazione manuale)"
}

configure_seo_plugins() {
    log_step "Configurazione plugin SEO aggiuntivi..."

    # Configure Schema plugin
    wp --allow-root option update schema_wp_settings '{
        "schema_type": "Organization",
        "site_name": "'"${SITE_NAME}"'",
        "site_logo": "",
        "default_image": "",
        "knowledge_graph": true,
        "publisher": true
    }' --format=json 2>/dev/null || log_warn "Schema plugin non configurato"

    # Configure Google Analytics (if plugin active)
    wp --allow-root option update exactmetrics_settings '{
        "analytics_profile": "",
        "manual_ua_code_hidden": "",
        "hide_admin_bar_reports": "",
        "dashboards_disabled": "",
        "anonymize_ips": true,
        "demographics": true,
        "ignore_users": ["administrator"]
    }' --format=json 2>/dev/null || log_warn "Google Analytics non configurato"

    # Enable AMP if installed
    wp --allow-root option update amp-options '{
        "theme_support": "standard",
        "supported_post_types": ["post", "page"],
        "analytics": {},
        "gtag_id": ""
    }' --format=json 2>/dev/null || log_warn "AMP non configurato"

    log_info "Plugin SEO aggiuntivi configurati"
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
        sed -i "s/define('FORCE_SSL_ADMIN', true);/define('FORCE_SSL_ADMIN', true);/" /var/www/"$DOMAIN"/wp-config.php

        # Update site URL
        cd "/var/www/${DOMAIN}"
        wp --allow-root option update home "https://$DOMAIN"
        wp --allow-root option update siteurl "https://$DOMAIN"

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

# Advanced Backup Jobs
# Full backup (Weekly - Sunday 3:00 AM)
0 3 * * 0 root /usr/local/bin/wp-backup-full.sh

# Incremental backup (Daily - 1:00 AM)
0 1 * * * root /usr/local/bin/wp-backup-incremental.sh

# Database backup (Every 6 hours)
0 */6 * * * root /usr/local/bin/wp-backup-db.sh
EOF

    log_success "Manutenzione automatica configurata"

    # Create advanced backup scripts
    create_backup_scripts
}

create_backup_scripts() {
    log_step "Creazione script backup avanzati..."

    # Install required backup tools
    apt install -y restic rclone s3cmd duplicity

    # Full backup script
    cat > /usr/local/bin/wp-backup-full.sh << 'BACKUP_FULL_EOF'
#!/bin/bash
# WordPress Full Backup Script - Enterprise

set -euo pipefail

# Configuration
DOMAIN="${DOMAIN}"
BACKUP_DIR="/var/backups/wordpress"
S3_BUCKET="${MINIO_BUCKET:-wordpress-backups}"
RETENTION_DAYS=30
LOG_FILE="/var/log/wordpress-backup.log"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Create backup directory
mkdir -p "$BACKUP_DIR"
cd "$BACKUP_DIR"

# Backup timestamp
BACKUP_DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_NAME="wp_full_${DOMAIN}_${BACKUP_DATE}"

log "Starting full backup: $BACKUP_NAME"

# 1. Database backup
log "Backing up database..."
if [[ -n "${DB_HOST:-}" ]]; then
    mysqldump -h"$DB_HOST" -u"$DB_USER" -p"$DB_PASS" "$DB_NAME" \
        --single-transaction --routines --triggers > "${BACKUP_NAME}_database.sql"
else
    log "WARNING: Database connection not configured"
fi

# 2. Files backup with exclusions
log "Backing up files..."
tar -czf "${BACKUP_NAME}_files.tar.gz" \
    --exclude='*.log' \
    --exclude='cache/*' \
    --exclude='tmp/*' \
    --exclude='.git/*' \
    -C "/var/www" "${DOMAIN}"

# 3. System configuration backup
log "Backing up system configuration..."
mkdir -p "${BACKUP_NAME}_config"
cp -r /etc/nginx/sites-available/ "${BACKUP_NAME}_config/"
cp -r /etc/php/*/fpm/pool.d/ "${BACKUP_NAME}_config/" 2>/dev/null || true
cp /etc/crontab "${BACKUP_NAME}_config/" 2>/dev/null || true

# 4. Create backup manifest
cat > "${BACKUP_NAME}_manifest.json" << EOF
{
    "backup_type": "full",
    "domain": "$DOMAIN",
    "timestamp": "$(date -Iseconds)",
    "files": [
        "${BACKUP_NAME}_database.sql",
        "${BACKUP_NAME}_files.tar.gz",
        "${BACKUP_NAME}_config/"
    ],
    "size_mb": $(du -sm "${BACKUP_NAME}_"* | awk '{sum+=$1} END {print sum}')
}
EOF

# 5. Upload to S3/MinIO (if configured)
if [[ -n "${MINIO_ENDPOINT:-}" ]] && [[ -n "${MINIO_ACCESS_KEY:-}" ]]; then
    log "Uploading to S3/MinIO..."

    # Configure rclone for MinIO
    cat > /tmp/rclone.conf << EOF
[minio]
type = s3
provider = Other
access_key_id = ${MINIO_ACCESS_KEY}
secret_access_key = ${MINIO_SECRET_KEY}
endpoint = ${MINIO_ENDPOINT}
EOF

    # Upload files
    rclone --config=/tmp/rclone.conf copy "${BACKUP_NAME}_"* "minio:${S3_BUCKET}/full/"
    rm /tmp/rclone.conf

    log "Backup uploaded to S3"
fi

# 6. Cleanup old backups
log "Cleaning up old backups..."
find "$BACKUP_DIR" -name "wp_full_*" -mtime +$RETENTION_DAYS -delete

# 7. Backup verification
if [[ -f "${BACKUP_NAME}_database.sql" ]] && [[ -f "${BACKUP_NAME}_files.tar.gz" ]]; then
    log "Full backup completed successfully: $BACKUP_NAME"

    # Send notification (if configured)
    if command -v curl >/dev/null 2>&1 && [[ -n "${WEBHOOK_URL:-}" ]]; then
        curl -X POST "$WEBHOOK_URL" \
            -H "Content-Type: application/json" \
            -d "{\"text\":\"✅ WordPress backup completed for $DOMAIN\"}" \
            >/dev/null 2>&1 || true
    fi
else
    log "ERROR: Backup failed!"
    exit 1
fi
BACKUP_FULL_EOF

    # Database-only backup script
    cat > /usr/local/bin/wp-backup-db.sh << 'BACKUP_DB_EOF'
#!/bin/bash
# WordPress Database Backup Script

set -euo pipefail

DOMAIN="${DOMAIN}"
BACKUP_DIR="/var/backups/wordpress/db"
RETENTION_HOURS=168  # 7 days
LOG_FILE="/var/log/wordpress-db-backup.log"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

mkdir -p "$BACKUP_DIR"
cd "$BACKUP_DIR"

BACKUP_DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="db_${DOMAIN}_${BACKUP_DATE}.sql.gz"

log "Starting database backup: $BACKUP_FILE"

if [[ -n "${DB_HOST:-}" ]]; then
    mysqldump -h"$DB_HOST" -u"$DB_USER" -p"$DB_PASS" "$DB_NAME" \
        --single-transaction --routines --triggers | gzip > "$BACKUP_FILE"

    log "Database backup completed: $BACKUP_FILE"

    # Cleanup old backups
    find "$BACKUP_DIR" -name "db_${DOMAIN}_*.sql.gz" -mtime +$((RETENTION_HOURS/24)) -delete
else
    log "ERROR: Database connection not configured"
    exit 1
fi
BACKUP_DB_EOF

    # Incremental backup script (using restic)
    cat > /usr/local/bin/wp-backup-incremental.sh << 'BACKUP_INCREMENTAL_EOF'
#!/bin/bash
# WordPress Incremental Backup with Restic

set -euo pipefail

DOMAIN="${DOMAIN}"
REPO_PATH="/var/backups/restic-repo"
LOG_FILE="/var/log/wordpress-incremental-backup.log"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Initialize restic repository if it doesn't exist
if [[ ! -d "$REPO_PATH" ]]; then
    log "Initializing restic repository..."
    export RESTIC_PASSWORD="$(openssl rand -base64 32)"
    echo "RESTIC_PASSWORD=$RESTIC_PASSWORD" > /etc/wordpress-backup.env
    restic init --repo "$REPO_PATH"
else
    source /etc/wordpress-backup.env
fi

export RESTIC_REPOSITORY="$REPO_PATH"

log "Starting incremental backup for $DOMAIN"

# Backup WordPress files
restic backup "/var/www/$DOMAIN" \
    --exclude="*.log" \
    --exclude="cache" \
    --exclude="tmp" \
    --tag="wordpress" \
    --tag="$DOMAIN" \
    --tag="$(date +%Y-%m-%d)"

# Cleanup old snapshots (keep last 30 days)
restic forget --tag="$DOMAIN" --keep-daily 30 --prune

log "Incremental backup completed"

# Show repository stats
restic stats --tag="$DOMAIN" | tee -a "$LOG_FILE"
BACKUP_INCREMENTAL_EOF

    # Make scripts executable
    chmod +x /usr/local/bin/wp-backup-*.sh

    log_success "Script backup avanzati creati"
    log_info "Full backup: /usr/local/bin/wp-backup-full.sh"
    log_info "DB backup: /usr/local/bin/wp-backup-db.sh"
    log_info "Incremental: /usr/local/bin/wp-backup-incremental.sh"
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

    # Create health check endpoint
    create_health_check_endpoint
}

create_health_check_endpoint() {
    log_step "Creazione endpoint di monitoraggio..."

    local wp_dir="/var/www/${DOMAIN}"

    # Health check PHP endpoint
    cat > "${wp_dir}/health-check.php" << 'HEALTH_CHECK_EOF'
<?php
// WordPress Health Check Endpoint - Enterprise Monitoring
header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');

$start_time = microtime(true);
$health = [
    'timestamp' => date('c'),
    'status' => 'healthy',
    'checks' => [],
    'metrics' => []
];

// Database Check
try {
    require_once('wp-config.php');
    $connection = new mysqli(DB_HOST, DB_USER, DB_PASSWORD, DB_NAME);
    if ($connection->connect_error) {
        throw new Exception("Database connection failed");
    }
    $result = $connection->query("SELECT 1");
    if (!$result) {
        throw new Exception("Database query failed");
    }
    $connection->close();
    $health['checks']['database'] = 'ok';
} catch (Exception $e) {
    $health['checks']['database'] = 'error: ' . $e->getMessage();
    $health['status'] = 'unhealthy';
}

// Redis Check (if configured)
if (defined('WP_REDIS_HOST')) {
    try {
        $redis = new Redis();
        if (!$redis->connect(WP_REDIS_HOST, WP_REDIS_PORT, 1)) {
            throw new Exception("Redis connection failed");
        }
        if (defined('WP_REDIS_PASSWORD') && WP_REDIS_PASSWORD) {
            $redis->auth(WP_REDIS_PASSWORD);
        }
        $redis->ping();
        $redis->close();
        $health['checks']['redis'] = 'ok';
    } catch (Exception $e) {
        $health['checks']['redis'] = 'error: ' . $e->getMessage();
    }
}

// Filesystem Check
$upload_dir = wp_upload_dir();
if (!is_writable($upload_dir['basedir'])) {
    $health['checks']['filesystem'] = 'error: uploads directory not writable';
    $health['status'] = 'unhealthy';
} else {
    $health['checks']['filesystem'] = 'ok';
}

// Performance Metrics
$health['metrics'] = [
    'response_time_ms' => round((microtime(true) - $start_time) * 1000, 2),
    'memory_usage_mb' => round(memory_get_usage(true) / 1024 / 1024, 2),
    'memory_peak_mb' => round(memory_get_peak_usage(true) / 1024 / 1024, 2),
    'php_version' => phpversion(),
    'wp_version' => get_bloginfo('version'),
    'disk_free_gb' => round(disk_free_space('.') / 1024 / 1024 / 1024, 2)
];

// System Load
if (function_exists('sys_getloadavg')) {
    $load = sys_getloadavg();
    $health['metrics']['system_load'] = [
        '1min' => $load[0],
        '5min' => $load[1],
        '15min' => $load[2]
    ];
}

http_response_code($health['status'] === 'healthy' ? 200 : 503);
echo json_encode($health, JSON_PRETTY_PRINT);
HEALTH_CHECK_EOF

    # Nginx location for health check
    local nginx_config="${NGINX_SITES_AVAILABLE}/${DOMAIN}"
    sed -i '/# Logs/i\
    # Health Check Endpoint\
    location = /health-check.php {\
        access_log off;\
        allow 127.0.0.1;\
        allow ::1;\
        # Add your monitoring IPs here\
        # allow 192.168.1.0/24;\
        deny all;\
        \
        fastcgi_pass unix:/run/php/php'"${PHP_VERSION}"'-fpm-wordpress.sock;\
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;\
        include fastcgi_params;\
    }\
' "$nginx_config"

    # Prometheus metrics endpoint
    cat > "${wp_dir}/metrics.php" << 'METRICS_EOF'
<?php
// Prometheus Metrics Endpoint
header('Content-Type: text/plain; version=0.0.4');

require_once('wp-config.php');

$metrics = [];

// WordPress metrics
$metrics[] = "# HELP wordpress_posts_total Total number of posts";
$metrics[] = "# TYPE wordpress_posts_total counter";
$metrics[] = "wordpress_posts_total " . wp_count_posts()->publish;

$metrics[] = "# HELP wordpress_users_total Total number of users";
$metrics[] = "# TYPE wordpress_users_total counter";
$metrics[] = "wordpress_users_total " . count_users()['total_users'];

// Performance metrics
$start = microtime(true);
$connection = new mysqli(DB_HOST, DB_USER, DB_PASSWORD, DB_NAME);
$db_time = (microtime(true) - $start) * 1000;

$metrics[] = "# HELP wordpress_db_response_time_ms Database response time in milliseconds";
$metrics[] = "# TYPE wordpress_db_response_time_ms gauge";
$metrics[] = "wordpress_db_response_time_ms " . round($db_time, 2);

$metrics[] = "# HELP wordpress_memory_usage_bytes Memory usage in bytes";
$metrics[] = "# TYPE wordpress_memory_usage_bytes gauge";
$metrics[] = "wordpress_memory_usage_bytes " . memory_get_usage(true);

echo implode("\n", $metrics) . "\n";
METRICS_EOF

    chown www-data:www-data "${wp_dir}/health-check.php" "${wp_dir}/metrics.php"
    chmod 644 "${wp_dir}/health-check.php" "${wp_dir}/metrics.php"

    # Reload Nginx
    nginx -t && systemctl reload nginx

    log_success "Health check endpoint creato: https://${DOMAIN}/health-check.php"
    log_info "Metrics endpoint: https://${DOMAIN}/metrics.php"
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

    # Theme and Template Configuration
    install_optimized_theme

    # SEO Configuration
    configure_seo_basics

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
# EXTERNAL SERVICES TESTING
# =============================================================================

test_redis_connection() {
    local redis_host="$1"
    local redis_port="$2"
    local redis_pass="$3"

    log_step "Test connessione Redis..."

    # Install redis-tools if not present
    if ! command -v redis-cli >/dev/null 2>&1; then
        apt install -y redis-tools >/dev/null 2>&1
    fi

    # Test connection
    local redis_cmd="redis-cli -h $redis_host -p $redis_port"
    if [[ -n "$redis_pass" ]]; then
        redis_cmd="$redis_cmd -a $redis_pass"
    fi

    if $redis_cmd ping 2>/dev/null | grep -q "PONG"; then
        log_success "✓ Redis connessione OK ($redis_host:$redis_port)"
        return 0
    else
        log_error "✗ Redis connessione fallita ($redis_host:$redis_port)"
        return 1
    fi
}

test_minio_connection() {
    local endpoint="$1"
    local access_key="$2"
    local secret_key="$3"

    log_step "Test connessione MinIO..."

    # Install mc (MinIO Client) if not present
    if ! command -v mc >/dev/null 2>&1; then
        curl -o /tmp/mc https://dl.min.io/client/mc/release/linux-amd64/mc
        chmod +x /tmp/mc
        mv /tmp/mc /usr/local/bin/
    fi

    # Configure mc alias
    if mc alias set testminio "$endpoint" "$access_key" "$secret_key" >/dev/null 2>&1; then
        if mc ls testminio >/dev/null 2>&1; then
            log_success "✓ MinIO connessione OK ($endpoint)"
            return 0
        fi
    fi

    log_error "✗ MinIO connessione fallita ($endpoint)"
    return 1
}

create_minio_bucket() {
    local endpoint="$1"
    local access_key="$2"
    local secret_key="$3"
    local bucket="$4"

    log_step "Verifica/creazione bucket MinIO..."

    # Configure mc alias
    mc alias set autominio "$endpoint" "$access_key" "$secret_key" >/dev/null 2>&1

    # Check if bucket exists
    if mc ls "autominio/$bucket" >/dev/null 2>&1; then
        log_info "Bucket '$bucket' già esistente"
    else
        # Create bucket
        if mc mb "autominio/$bucket" >/dev/null 2>&1; then
            log_success "Bucket '$bucket' creato con successo"

            # Set public read policy for uploads folder
            mc anonymous set download "autominio/$bucket/wp-content/uploads" >/dev/null 2>&1
        else
            log_error "Errore creazione bucket '$bucket'"
            return 1
        fi
    fi

    return 0
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