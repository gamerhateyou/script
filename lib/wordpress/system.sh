#!/bin/bash

# =============================================================================
# SYSTEM INSTALLATION FUNCTIONS
# =============================================================================

# shellcheck source=./utils.sh
source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"

update_system() {
    log_step "Aggiornamento sistema..."

    export DEBIAN_FRONTEND=noninteractive
    export LC_ALL=C.UTF-8
    export LANG=C.UTF-8

    # Update package list
    if ! retry_command 3 5 "Aggiornamento package list" apt update -y; then
        log_error "Errore aggiornamento package list dopo i retry"
        return 1
    fi

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
opcache.max_accelerated_files=20000
opcache.validate_timestamps=0
opcache.revalidate_freq=0
opcache.fast_shutdown=1
opcache.save_comments=1

; Security Settings
expose_php = Off
display_errors = Off
display_startup_errors = Off
log_errors = On
error_log = /var/log/php_errors.log

; Session Security
session.cookie_httponly = 1
session.cookie_secure = 1
session.use_strict_mode = 1

; File Upload Security
file_uploads = On
allow_url_fopen = Off
allow_url_include = Off

; Resource Limits
max_file_uploads = 20
default_socket_timeout = 60
EOF

    # Configure PHP-FPM pool
    local pool_config="${PHP_FPM_POOL}/wordpress.conf"

    cat > "$pool_config" << EOF
[wordpress]
user = www-data
group = www-data
listen = /run/php/php${PHP_VERSION}-fpm-wordpress.sock
listen.owner = www-data
listen.group = www-data
listen.mode = 0660

; Process Manager
pm = dynamic
pm.max_children = 50
pm.start_servers = 5
pm.min_spare_servers = 5
pm.max_spare_servers = 35
pm.max_requests = 1000

; Performance tuning
request_terminate_timeout = 300
request_slowlog_timeout = 30s
slowlog = /var/log/php-fpm-slow.log

; Security
php_admin_value[disable_functions] = exec,passthru,shell_exec,system,proc_open,popen
php_admin_flag[allow_url_fopen] = off
php_admin_flag[allow_url_include] = off

; Environment variables
env[HOSTNAME] = \$HOSTNAME
env[PATH] = /usr/local/bin:/usr/bin:/bin
env[TMP] = /tmp
env[TMPDIR] = /tmp
env[TEMP] = /tmp
EOF

    # Remove default pool if it exists
    [[ -f "${PHP_FPM_POOL}/www.conf" ]] && rm -f "${PHP_FPM_POOL}/www.conf"

    # Restart PHP-FPM
    systemctl restart "php${PHP_VERSION}-fpm"
    systemctl enable "php${PHP_VERSION}-fpm"

    log_success "PHP configurato"
}

install_nginx() {
    log_step "Installazione Nginx..."

    # Install Nginx
    apt install -y nginx || {
        log_error "Errore installazione Nginx"
        return 1
    }

    # Enable and start Nginx
    systemctl enable nginx
    systemctl start nginx

    log_success "Nginx installato"
}

configure_nginx_global() {
    log_step "Configurazione globale Nginx..."

    # Backup original configuration
    [[ -f /etc/nginx/nginx.conf ]] && cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.backup

    cat > /etc/nginx/nginx.conf << 'NGINX_CONF_EOF'
user www-data;
worker_processes auto;
pid /run/nginx.pid;
include /etc/nginx/modules-enabled/*.conf;

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
    types_hash_max_size 2048;
    server_tokens off;
    client_max_body_size 128M;

    # File descriptors
    worker_rlimit_nofile 65535;

    # MIME types
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    # Logging
    log_format main '\$remote_addr - \$remote_user [\$time_local] "\$request" '
                    '\$status \$body_bytes_sent "\$http_referer" '
                    '"\$http_user_agent" "\$http_x_forwarded_for" '
                    'rt=\$request_time uct="\$upstream_connect_time" '
                    'uht="\$upstream_header_time" urt="\$upstream_response_time"';

    access_log /var/log/nginx/access.log main;
    error_log /var/log/nginx/error.log warn;

    # Gzip Settings
    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_types
        text/plain
        text/css
        text/xml
        text/javascript
        application/json
        application/javascript
        application/xml+rss
        application/atom+xml
        image/svg+xml;

    # Security Headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "no-referrer-when-downgrade" always;
    add_header Content-Security-Policy "default-src 'self' http: https: data: blob: 'unsafe-inline'" always;

    # Rate Limiting
    limit_req_zone \$binary_remote_addr zone=login:10m rate=10r/m;
    limit_req_zone \$binary_remote_addr zone=general:10m rate=100r/m;

    # Include configurations
    include /etc/nginx/conf.d/*.conf;
    include /etc/nginx/sites-enabled/*;
}
NGINX_CONF_EOF

    # Create common configurations
    mkdir -p /etc/nginx/conf.d

    # WordPress common rules
    cat > /etc/nginx/conf.d/wordpress-common.conf << 'WP_COMMON_EOF'
# WordPress common rules
location = /favicon.ico {
    log_not_found off;
    access_log off;
}

location = /robots.txt {
    log_not_found off;
    access_log off;
    allow all;
}

location ~* \.(css|gif|ico|jpeg|jpg|js|png|webp|svg)$ {
    expires 1y;
    add_header Cache-Control "public, immutable";
    log_not_found off;
}

location ~ /\. {
    deny all;
}

location ~ ~$ {
    deny all;
}

location ~* ^/(wp-config\.php|wp-config-sample\.php|readme\.html|license\.txt)$ {
    deny all;
}
WP_COMMON_EOF

    # Test configuration
    if nginx -t; then
        systemctl reload nginx
        log_success "Configurazione Nginx applicata"
    else
        log_error "Errore nella configurazione Nginx"
        return 1
    fi
}