#!/bin/bash

# WordPress Optimized Setup Script for Proxmox Container
# Configura WordPress con Redis, MinIO, ottimizzazioni SEO e performance

set -e

# Colori per output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Funzioni di utilità
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Configurazione predefinita
DEFAULT_DB_NAME="wordpress"
DEFAULT_DB_USER="wpuser"
DEFAULT_DB_PORT="3306"
DEFAULT_WP_ADMIN="admin"
DEFAULT_SITE_TITLE="WordPress Ottimizzato"
DEFAULT_REDIS_HOST=""
DEFAULT_REDIS_PORT="6379"

# Funzione per input utente con default
read_input() {
    local prompt="$1"
    local default="$2"
    local var_name="$3"

    if [ -n "$default" ]; then
        read -p "$prompt [$default]: " input
        eval "$var_name=\"\${input:-$default}\""
    else
        read -p "$prompt: " input
        eval "$var_name=\"$input\""
    fi
}

# Funzione per input password sicuro
read_password() {
    local prompt="$1"
    local var_name="$2"

    while true; do
        read -s -p "$prompt: " password
        echo
        read -s -p "Conferma password: " password_confirm
        echo

        if [ "$password" = "$password_confirm" ]; then
            eval "$var_name=\"$password\""
            break
        else
            log_error "Le password non coincidono. Riprova."
        fi
    done
}

# Raccolta configurazioni
collect_config() {
    log_info "=== Configurazione WordPress Ottimizzato ==="
    echo

    # Database esterno
    log_info "Configurazione Database MySQL/MariaDB esterno:"
    read_input "Host database" "" "DB_HOST"
    read_input "Porta database" "$DEFAULT_DB_PORT" "DB_PORT"
    read_input "Nome database" "$DEFAULT_DB_NAME" "DB_NAME"
    read_input "Utente database" "$DEFAULT_DB_USER" "DB_USER"
    read_password "Password database" "DB_PASSWORD"
    echo

    # WordPress Admin
    log_info "Configurazione Amministratore WordPress:"
    read_input "Username admin" "$DEFAULT_WP_ADMIN" "WP_ADMIN_USER"
    read_password "Password admin WordPress" "WP_ADMIN_PASSWORD"
    read_input "Email admin" "" "WP_ADMIN_EMAIL"
    read_input "Titolo sito" "$DEFAULT_SITE_TITLE" "SITE_TITLE"
    read_input "URL sito" "" "SITE_URL"
    echo

    # Redis esterno
    log_info "Configurazione Redis esterno:"
    read_input "Host Redis" "$DEFAULT_REDIS_HOST" "REDIS_HOST"
    read_input "Porta Redis" "$DEFAULT_REDIS_PORT" "REDIS_PORT"
    echo

    # MinIO
    log_info "Configurazione MinIO:"
    read_input "Host MinIO" "" "MINIO_HOST"
    read_input "Porta MinIO" "9000" "MINIO_PORT"
    read_input "Username MinIO" "" "MINIO_USER"
    read_password "Password MinIO" "MINIO_PASSWORD"
    read_input "Nome bucket" "wordpress-media" "MINIO_BUCKET"
    echo
}

# Aggiornamento sistema
update_system() {
    log_info "Aggiornamento sistema..."
    apt update && apt upgrade -y
    log_success "Sistema aggiornato"
}

# Installazione pacchetti base
install_base_packages() {
    log_info "Installazione pacchetti base..."
    apt install -y \
        nginx \
        php8.2-fpm \
        php8.2-mysql \
        php8.2-redis \
        php8.2-curl \
        php8.2-gd \
        php8.2-intl \
        php8.2-mbstring \
        php8.2-soap \
        php8.2-xml \
        php8.2-xmlrpc \
        php8.2-zip \
        php8.2-imagick \
        php8.2-cli \
        mysql-client \
        redis-tools \
        wget \
        curl \
        unzip \
        certbot \
        python3-certbot-nginx \
        htop \
        nano \
        git

    log_success "Pacchetti base installati"
}

# Configurazione MySQL/MariaDB
test_mysql_connection() {
    log_info "Test connessione database esterno..."

    # Test connessione
    if mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASSWORD" -e "SELECT 1;" &>/dev/null; then
        log_success "Connessione database OK"
    else
        log_error "Impossibile connettersi al database esterno"
        log_error "Verifica: host=$DB_HOST, porta=$DB_PORT, utente=$DB_USER"
        exit 1
    fi

    # Verifica esistenza database
    if mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASSWORD" -e "USE $DB_NAME;" &>/dev/null; then
        log_success "Database $DB_NAME esistente"
    else
        log_warning "Database $DB_NAME non trovato, creazione necessaria"
        read -p "Creare il database $DB_NAME? (y/N): " create_db
        if [[ $create_db == [yY] ]]; then
            mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASSWORD" -e "CREATE DATABASE $DB_NAME DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
            log_success "Database $DB_NAME creato"
        else
            log_error "Database necessario per continuare"
            exit 1
        fi
    fi
}

# Test connessione Redis esterno
test_redis_connection() {
    log_info "Test connessione Redis esterno..."

    # Test connessione Redis
    if redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" ping &>/dev/null; then
        log_success "Connessione Redis OK"
    else
        log_error "Impossibile connettersi a Redis esterno"
        log_error "Verifica: host=$REDIS_HOST, porta=$REDIS_PORT"
        exit 1
    fi
}

# Download e installazione WordPress
install_wordpress() {
    log_info "Download e installazione WordPress..."

    cd /tmp
    wget https://wordpress.org/latest.tar.gz
    tar xzvf latest.tar.gz

    # Creazione directory web
    mkdir -p /var/www/html
    cp -R wordpress/* /var/www/html/
    chown -R www-data:www-data /var/www/html
    chmod -R 755 /var/www/html

    log_success "WordPress installato"
}

# Configurazione WordPress
configure_wordpress() {
    log_info "Configurazione WordPress..."

    cd /var/www/html

    # Configurazione wp-config.php
    cat > wp-config.php << EOF
<?php
define('DB_NAME', '$DB_NAME');
define('DB_USER', '$DB_USER');
define('DB_PASSWORD', '$DB_PASSWORD');
define('DB_HOST', '$DB_HOST:$DB_PORT');
define('DB_CHARSET', 'utf8mb4');
define('DB_COLLATE', '');

// Redis Cache
define('WP_REDIS_HOST', '$REDIS_HOST');
define('WP_REDIS_PORT', $REDIS_PORT);
define('WP_REDIS_DATABASE', 0);
define('WP_CACHE_KEY_SALT', '$SITE_URL');

// MinIO S3 Configuration
define('AS3CF_SETTINGS', serialize(array(
    'provider' => 'other',
    'access-key-id' => '$MINIO_USER',
    'secret-access-key' => '$MINIO_PASSWORD',
    'bucket' => '$MINIO_BUCKET',
    'region' => 'us-east-1',
    'copy-to-s3' => true,
    'serve-from-s3' => true,
    'domain' => 'path',
    'cloudfront' => '',
    'object-prefix' => '',
    'use-server-roles' => false,
    'endpoint' => '$MINIO_HOST:$MINIO_PORT',
    'use-ssl' => false,
)));

// Security keys (generate these!)
define('AUTH_KEY',         'put your unique phrase here');
define('SECURE_AUTH_KEY',  'put your unique phrase here');
define('LOGGED_IN_KEY',    'put your unique phrase here');
define('NONCE_KEY',        'put your unique phrase here');
define('AUTH_SALT',        'put your unique phrase here');
define('SECURE_AUTH_SALT', 'put your unique phrase here');
define('LOGGED_IN_SALT',   'put your unique phrase here');
define('NONCE_SALT',       'put your unique phrase here');

// WordPress Performance
define('WP_CACHE', true);
define('COMPRESS_CSS', true);
define('COMPRESS_SCRIPTS', true);
define('CONCATENATE_SCRIPTS', true);
define('ENFORCE_GZIP', true);

// WordPress Security
define('DISALLOW_FILE_EDIT', true);
define('DISALLOW_FILE_MODS', true);
define('FORCE_SSL_ADMIN', true);
define('WP_AUTO_UPDATE_CORE', 'minor');

// Debug (disable in production)
define('WP_DEBUG', false);
define('WP_DEBUG_LOG', false);
define('WP_DEBUG_DISPLAY', false);

\$table_prefix = 'wp_';

if ( ! defined( 'ABSPATH' ) ) {
    define( 'ABSPATH', __DIR__ . '/' );
}

require_once ABSPATH . 'wp-settings.php';
EOF

    chown www-data:www-data wp-config.php
    chmod 600 wp-config.php

    log_success "WordPress configurato"
}

# Installazione WP-CLI
install_wp_cli() {
    log_info "Installazione WP-CLI..."

    curl -O https://raw.githubusercontent.com/wp-cli/wp-cli/master/utils/wp-cli.phar
    chmod +x wp-cli.phar
    mv wp-cli.phar /usr/local/bin/wp

    log_success "WP-CLI installato"
}

# Configurazione iniziale WordPress via WP-CLI
setup_wordpress_cli() {
    log_info "Configurazione iniziale WordPress..."

    cd /var/www/html

    # Installazione WordPress
    sudo -u www-data wp core install \
        --url="$SITE_URL" \
        --title="$SITE_TITLE" \
        --admin_user="$WP_ADMIN_USER" \
        --admin_password="$WP_ADMIN_PASSWORD" \
        --admin_email="$WP_ADMIN_EMAIL"

    log_success "WordPress inizializzato"
}

# Installazione plugin essenziali
install_plugins() {
    log_info "Installazione plugin essenziali..."

    cd /var/www/html

    # Plugin per cache e performance
    sudo -u www-data wp plugin install redis-cache --activate
    sudo -u www-data wp plugin install w3-total-cache --activate
    sudo -u www-data wp plugin install wp-rocket --activate || log_warning "WP Rocket richiede licenza"

    # Plugin per SEO
    sudo -u www-data wp plugin install wordpress-seo --activate
    sudo -u www-data wp plugin install rankmath --activate

    # Plugin per sicurezza
    sudo -u www-data wp plugin install wordfence --activate
    sudo -u www-data wp plugin install wp-security-audit-log --activate

    # Plugin per MinIO/S3
    sudo -u www-data wp plugin install amazon-s3-and-cloudfront --activate

    # Plugin per performance
    sudo -u www-data wp plugin install autoptimize --activate
    sudo -u www-data wp plugin install wp-optimize --activate
    sudo -u www-data wp plugin install imagify --activate

    # Attivazione cache Redis
    sudo -u www-data wp redis enable

    log_success "Plugin installati e configurati"
}

# Configurazione Nginx
setup_nginx() {
    log_info "Configurazione Nginx..."

    cat > /etc/nginx/sites-available/wordpress << EOF
server {
    listen 80;
    server_name $SITE_URL www.$SITE_URL;
    root /var/www/html;
    index index.php index.html index.htm;

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "no-referrer-when-downgrade" always;
    add_header Content-Security-Policy "default-src 'self' http: https: data: blob: 'unsafe-inline'" always;

    # Gzip compression
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_proxied expired no-cache no-store private auth;
    gzip_types text/plain text/css text/xml text/javascript application/x-javascript application/xml+rss;

    # Cache static files
    location ~* \.(jpg|jpeg|png|gif|ico|css|js|woff|woff2|ttf|svg)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
    }

    # WordPress security
    location = /favicon.ico { log_not_found off; access_log off; }
    location = /robots.txt { log_not_found off; access_log off; allow all; }
    location ~* /(?:uploads|files)/.*\.php$ { deny all; }
    location ~ /\. { deny all; }
    location ~ ~$ { deny all; }

    # WordPress permalinks
    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }

    # PHP processing
    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php8.2-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;

        # Security
        fastcgi_hide_header X-Powered-By;

        # Cache
        fastcgi_cache_valid 200 60m;
    }

    # Block access to sensitive files
    location ~* /(?:wp-config\.php|wp-admin/includes|wp-includes/.*\.php|wp-content/uploads/.*\.php)$ {
        deny all;
    }
}
EOF

    # Rimozione configurazione default
    rm -f /etc/nginx/sites-enabled/default

    # Attivazione sito
    ln -sf /etc/nginx/sites-available/wordpress /etc/nginx/sites-enabled/

    # Test configurazione
    nginx -t
    systemctl restart nginx
    systemctl enable nginx

    log_success "Nginx configurato"
}

# Configurazione PHP-FPM ottimizzata
optimize_php() {
    log_info "Ottimizzazione PHP-FPM..."

    # Configurazione PHP-FPM
    cat > /etc/php/8.2/fpm/pool.d/www.conf << EOF
[www]
user = www-data
group = www-data
listen = /var/run/php/php8.2-fpm.sock
listen.owner = www-data
listen.group = www-data
pm = dynamic
pm.max_children = 50
pm.start_servers = 5
pm.min_spare_servers = 5
pm.max_spare_servers = 35
pm.process_idle_timeout = 10s
pm.max_requests = 500
request_terminate_timeout = 300
rlimit_files = 1024
rlimit_core = 0
catch_workers_output = yes
EOF

    # Configurazione PHP ottimizzata
    cat > /etc/php/8.2/fpm/conf.d/99-wordpress.ini << EOF
; WordPress optimizations
memory_limit = 256M
upload_max_filesize = 64M
post_max_size = 64M
max_execution_time = 300
max_input_vars = 3000
max_input_time = 300

; OPcache
opcache.enable = 1
opcache.memory_consumption = 128
opcache.interned_strings_buffer = 8
opcache.max_accelerated_files = 10000
opcache.revalidate_freq = 2
opcache.fast_shutdown = 1
opcache.enable_cli = 1

; Security
expose_php = Off
allow_url_fopen = Off
allow_url_include = Off
session.cookie_httponly = 1
session.cookie_secure = 1
session.use_strict_mode = 1
EOF

    systemctl restart php8.2-fpm
    systemctl enable php8.2-fpm

    log_success "PHP-FPM ottimizzato"
}

# Test connessione e configurazione MinIO esterno
test_minio_connection() {
    log_info "Test connessione MinIO esterno..."

    # Installazione MinIO Client
    wget https://dl.min.io/client/mc/release/linux-amd64/mc -O /usr/local/bin/mc
    chmod +x /usr/local/bin/mc

    # Test connessione MinIO
    if /usr/local/bin/mc alias set minio http://$MINIO_HOST:$MINIO_PORT $MINIO_USER $MINIO_PASSWORD &>/dev/null; then
        log_success "Connessione MinIO OK"
    else
        log_error "Impossibile connettersi a MinIO esterno"
        log_error "Verifica: host=$MINIO_HOST, porta=$MINIO_PORT, credenziali"
        exit 1
    fi

    # Verifica esistenza bucket
    if /usr/local/bin/mc ls minio/$MINIO_BUCKET &>/dev/null; then
        log_success "Bucket $MINIO_BUCKET esistente"
    else
        log_warning "Bucket $MINIO_BUCKET non trovato, creazione necessaria"
        read -p "Creare il bucket $MINIO_BUCKET? (y/N): " create_bucket
        if [[ $create_bucket == [yY] ]]; then
            /usr/local/bin/mc mb minio/$MINIO_BUCKET
            /usr/local/bin/mc policy set download minio/$MINIO_BUCKET
            log_success "Bucket $MINIO_BUCKET creato e configurato"
        else
            log_error "Bucket necessario per continuare"
            exit 1
        fi
    fi
}

# Ottimizzazioni sistema
system_optimizations() {
    log_info "Applicazione ottimizzazioni sistema..."

    # Ottimizzazioni kernel
    cat >> /etc/sysctl.conf << EOF

# WordPress optimizations
vm.swappiness = 10
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
net.ipv4.tcp_congestion_control = bbr
EOF

    sysctl -p

    # Configurazione logrotate per WordPress
    cat > /etc/logrotate.d/wordpress << EOF
/var/www/html/wp-content/debug.log {
    weekly
    missingok
    rotate 52
    compress
    delaycompress
    notifempty
    create 644 www-data www-data
}
EOF

    log_success "Ottimizzazioni sistema applicate"
}

# Configurazione backup automatico
setup_backup() {
    log_info "Configurazione backup automatico..."

    mkdir -p /opt/backup

    cat > /opt/backup/wordpress-backup.sh << EOF
#!/bin/bash
BACKUP_DIR="/opt/backup"
DATE=\$(date +%Y%m%d_%H%M%S)
WP_DIR="/var/www/html"

# Backup database esterno
mysqldump -h '$DB_HOST' -P '$DB_PORT' -u '$DB_USER' -p'$DB_PASSWORD' '$DB_NAME' > \$BACKUP_DIR/db_\$DATE.sql

# Backup files
tar -czf \$BACKUP_DIR/wp_\$DATE.tar.gz -C \$WP_DIR .

# Cleanup old backups (keep last 7 days)
find \$BACKUP_DIR -name "*.sql" -mtime +7 -delete
find \$BACKUP_DIR -name "*.tar.gz" -mtime +7 -delete
EOF

    chmod +x /opt/backup/wordpress-backup.sh

    # Cron job per backup giornaliero
    (crontab -l 2>/dev/null; echo "0 2 * * * /opt/backup/wordpress-backup.sh") | crontab -

    log_success "Backup automatico configurato"
}

# Configurazione SSL (Let's Encrypt)
setup_ssl() {
    log_info "Configurazione SSL..."

    certbot --nginx -d $SITE_URL -d www.$SITE_URL --non-interactive --agree-tos --email $WP_ADMIN_EMAIL

    # Auto-renewal
    (crontab -l 2>/dev/null; echo "0 12 * * * /usr/bin/certbot renew --quiet") | crontab -

    log_success "SSL configurato"
}

# Pulizia finale
cleanup() {
    log_info "Pulizia finale..."

    apt autoremove -y
    apt autoclean

    # Rimozione file temporanei
    rm -rf /tmp/wordpress*
    rm -rf /tmp/latest.tar.gz

    log_success "Pulizia completata"
}

# Test finale
final_test() {
    log_info "Test finale del sistema..."

    # Test servizi
    systemctl is-active --quiet nginx && log_success "Nginx: OK" || log_error "Nginx: ERRORE"
    systemctl is-active --quiet php8.2-fpm && log_success "PHP-FPM: OK" || log_error "PHP-FPM: ERRORE"

    # Test connessione database esterno
    mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASSWORD" -e "SELECT 1;" "$DB_NAME" &>/dev/null && log_success "Database: OK" || log_error "Database: ERRORE"

    # Test Redis esterno
    redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" ping &>/dev/null && log_success "Redis ping: OK" || log_error "Redis ping: ERRORE"

    log_success "Test completati"
}

# Funzione principale
main() {
    log_info "=== SETUP WORDPRESS OTTIMIZZATO ==="
    log_info "Script per installazione WordPress con Redis, MinIO e ottimizzazioni"
    echo

    # Verifica root
    if [[ $EUID -ne 0 ]]; then
        log_error "Questo script deve essere eseguito come root"
        exit 1
    fi

    # Raccolta configurazioni
    collect_config

    # Conferma configurazione
    echo
    log_warning "=== RIEPILOGO CONFIGURAZIONE ==="
    echo "Database esterno: $DB_HOST:$DB_PORT/$DB_NAME (utente: $DB_USER)"
    echo "Redis esterno: $REDIS_HOST:$REDIS_PORT"
    echo "MinIO esterno: $MINIO_HOST:$MINIO_PORT (bucket: $MINIO_BUCKET)"
    echo "WordPress Admin: $WP_ADMIN_USER ($WP_ADMIN_EMAIL)"
    echo "Sito: $SITE_TITLE ($SITE_URL)"
    echo

    read -p "Confermi la configurazione? (y/N): " confirm
    if [[ $confirm != [yY] ]]; then
        log_error "Installazione annullata"
        exit 1
    fi

    # Esecuzione installazione
    log_info "Avvio installazione..."

    update_system
    install_base_packages
    test_mysql_connection
    test_redis_connection
    test_minio_connection
    install_wordpress
    configure_wordpress
    install_wp_cli
    setup_wordpress_cli
    install_plugins
    setup_nginx
    optimize_php
    system_optimizations
    setup_backup

    # SSL opzionale
    read -p "Configurare SSL con Let's Encrypt? (y/N): " ssl_confirm
    if [[ $ssl_confirm == [yY] ]]; then
        setup_ssl
    fi

    cleanup
    final_test

    echo
    log_success "=== INSTALLAZIONE COMPLETATA ==="
    log_success "WordPress è ora disponibile su: $SITE_URL"
    log_success "Admin: $SITE_URL/wp-admin"
    log_success "Username: $WP_ADMIN_USER"
    echo
    log_info "Servizi esterni configurati:"
    echo "- Database MySQL: $DB_HOST:$DB_PORT"
    echo "- Redis Cache: $REDIS_HOST:$REDIS_PORT"
    echo "- MinIO S3: $MINIO_HOST:$MINIO_PORT"
    echo
    log_info "Prossimi passi:"
    echo "1. Configura i plugin installati"
    echo "2. Personalizza il tema"
    echo "3. Verifica configurazione MinIO S3 nel plugin"
    echo "4. Testa la cache Redis"
    echo "5. Verifica le performance"
    echo
}

# Esecuzione script
main "$@"