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

    # Core PHP packages
    local php_packages=(
        "php${PHP_VERSION}" "php${PHP_VERSION}-fpm" "php${PHP_VERSION}-mysql"
        "php${PHP_VERSION}-curl" "php${PHP_VERSION}-gd" "php${PHP_VERSION}-intl"
        "php${PHP_VERSION}-mbstring" "php${PHP_VERSION}-xml" "php${PHP_VERSION}-zip"
        "php${PHP_VERSION}-opcache" "php${PHP_VERSION}-cli" "php${PHP_VERSION}-common"
        "php${PHP_VERSION}-imagick" "php${PHP_VERSION}-bcmath" "php${PHP_VERSION}-soap"
        "php${PHP_VERSION}-xmlrpc"
        # SEO Image optimization packages
        "imagemagick" "webp" "jpegoptim" "optipng" "pngquant"
        "php${PHP_VERSION}-dev" "php${PHP_VERSION}-pear"
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

    # Verify installation with timeout
    if timeout 10 wp --info >/dev/null 2>&1; then
        log_success "WP-CLI installato e verificato"
        wp --version
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
    sudo -u www-data wp config shuffle-salts

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

    # Install and activate plugins
    for plugin in "${plugins[@]}"; do
        if sudo -u www-data wp plugin install "$plugin" --activate; then
            log_success "Plugin installato: $plugin"
        else
            log_warn "Errore installazione plugin: $plugin"
        fi
    done

    # Configure Redis Cache if available
    if [[ "${USE_REDIS:-}" == "y"* ]] || [[ "${USE_REDIS,,}" =~ ^(yes|s|si)$ ]]; then
        # Test Redis connection first
        if test_redis_connection "$REDIS_HOST" "$REDIS_PORT" "$REDIS_PASS"; then
            if sudo -u www-data wp redis enable; then
                log_success "Redis Object Cache attivato e connessione testata"
            else
                log_warn "Errore attivazione Redis Cache"
            fi
        else
            log_warn "Redis configurato ma connessione non disponibile"
        fi
    fi

    # Configure MinIO S3 if available
    if [[ "${USE_MINIO:-}" == "y"* ]] || [[ "${USE_MINIO,,}" =~ ^(yes|s|si)$ ]]; then
        if test_minio_connection "$MINIO_ENDPOINT" "$MINIO_ACCESS_KEY" "$MINIO_SECRET_KEY"; then
            # Create bucket if it doesn't exist
            create_minio_bucket "$MINIO_ENDPOINT" "$MINIO_ACCESS_KEY" "$MINIO_SECRET_KEY" "$MINIO_BUCKET"
            log_success "MinIO S3 configurato e bucket creato/verificato"
        else
            log_warn "MinIO configurato ma connessione non disponibile"
        fi
    fi
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
    sudo -u www-data wp option update wpseo '{
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
    sudo -u www-data wp option update wpseo_xml '{
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
    sudo -u www-data wp option update schema_wp_settings '{
        "schema_type": "Organization",
        "site_name": "'"${SITE_NAME}"'",
        "site_logo": "",
        "default_image": "",
        "knowledge_graph": true,
        "publisher": true
    }' --format=json 2>/dev/null || log_warn "Schema plugin non configurato"

    # Configure Google Analytics (if plugin active)
    sudo -u www-data wp option update exactmetrics_settings '{
        "analytics_profile": "",
        "manual_ua_code_hidden": "",
        "hide_admin_bar_reports": "",
        "dashboards_disabled": "",
        "anonymize_ips": true,
        "demographics": true,
        "ignore_users": ["administrator"]
    }' --format=json 2>/dev/null || log_warn "Google Analytics non configurato"

    # Enable AMP if installed
    sudo -u www-data wp option update amp-options '{
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