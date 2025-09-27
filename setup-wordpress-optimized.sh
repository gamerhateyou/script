#!/bin/bash

# WordPress Optimized Setup Script for Proxmox Container 2025
# Configura WordPress con PHP 8.3, Redis, MinIO, ottimizzazioni SEO e performance

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
DEFAULT_DB_HOST="mysql.local"
DEFAULT_DB_NAME="wordpress"
DEFAULT_DB_USER="wpuser"
DEFAULT_DB_PORT="3306"
DEFAULT_WP_ADMIN="admin"
DEFAULT_SITE_TITLE="WordPress Ottimizzato"
DEFAULT_REDIS_HOST="redis.local"
DEFAULT_REDIS_PORT="6379"
DEFAULT_REDIS_PASSWORD=""
DEFAULT_MINIO_HOST="minio.local"
DEFAULT_MINIO_PORT="9000"
DEFAULT_MINIO_BUCKET="wordpress-media"

# Funzione di retry per connessioni
retry_connection() {
    local service_name="$1"
    local test_command="$2"
    local max_retries=3
    local retry_count=0

    while [ $retry_count -lt $max_retries ]; do
        log_info "Test connessione $service_name (tentativo $((retry_count + 1))/$max_retries)..."

        if eval "$test_command"; then
            log_success "Connessione $service_name OK"
            return 0
        else
            retry_count=$((retry_count + 1))
            if [ $retry_count -lt $max_retries ]; then
                log_warning "Connessione $service_name fallita, riprovo in 3 secondi..."
                sleep 3
            fi
        fi
    done

    log_error "Connessione $service_name fallita dopo $max_retries tentativi"
    log_error "Vuoi riconfigurare $service_name? (y/N)"
    read -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        return 1  # Indica che bisogna riconfigurare
    else
        exit 1
    fi
}

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

    # Database esterno con test immediato
    while true; do
        log_info "Configurazione Database MySQL/MariaDB esterno:"
        read_input "Host database" "$DEFAULT_DB_HOST" "DB_HOST"
        read_input "Porta database" "$DEFAULT_DB_PORT" "DB_PORT"
        read_input "Nome database" "$DEFAULT_DB_NAME" "DB_NAME"
        read_input "Utente database" "$DEFAULT_DB_USER" "DB_USER"
        read_password "Password database" "DB_PASSWORD"

        # Test immediato connessione MySQL
        test_cmd="mysql -h \"$DB_HOST\" -P \"$DB_PORT\" -u \"$DB_USER\" -p\"$DB_PASSWORD\" -e 'SELECT 1;' &>/dev/null"
        if retry_connection "MySQL" "$test_cmd"; then
            # Test esistenza database
            db_test_cmd="mysql -h \"$DB_HOST\" -P \"$DB_PORT\" -u \"$DB_USER\" -p\"$DB_PASSWORD\" -e 'USE $DB_NAME;' &>/dev/null"
            if eval "$db_test_cmd"; then
                log_success "Database $DB_NAME verificato"
                break
            else
                log_warning "Database $DB_NAME non esistente"
                read -p "Creare il database $DB_NAME? (y/N): " create_db
                if [[ $create_db =~ ^[Yy]$ ]]; then
                    if mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASSWORD" -e "CREATE DATABASE IF NOT EXISTS $DB_NAME CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" &>/dev/null; then
                        log_success "Database $DB_NAME creato"
                        break
                    else
                        log_error "Errore nella creazione del database"
                    fi
                fi
            fi
        else
            log_warning "Riconfigurazione database necessaria..."
            continue
        fi
    done
    echo

    # WordPress Admin
    log_info "Configurazione Amministratore WordPress:"
    read_input "Username admin" "$DEFAULT_WP_ADMIN" "WP_ADMIN_USER"
    read_password "Password admin WordPress" "WP_ADMIN_PASSWORD"
    read_input "Email admin" "" "WP_ADMIN_EMAIL"
    read_input "Titolo sito" "$DEFAULT_SITE_TITLE" "SITE_TITLE"
    read_input "URL sito" "" "SITE_URL"
    echo

    # Redis esterno con test immediato
    while true; do
        log_info "Configurazione Redis esterno:"
        read_input "Host Redis" "$DEFAULT_REDIS_HOST" "REDIS_HOST"
        read_input "Porta Redis" "$DEFAULT_REDIS_PORT" "REDIS_PORT"
        read_input "Password Redis (lascia vuoto se non protetto)" "$DEFAULT_REDIS_PASSWORD" "REDIS_PASSWORD"

        # Installa redis-cli se non presente
        if ! command -v redis-cli &> /dev/null; then
            log_info "Installazione redis-cli..."
            apt update && apt install -y redis-tools
        fi

        # Test immediato connessione Redis
        if [ -n "$REDIS_PASSWORD" ]; then
            test_cmd="redis-cli -h \"$REDIS_HOST\" -p \"$REDIS_PORT\" -a \"$REDIS_PASSWORD\" ping &>/dev/null"
        else
            test_cmd="redis-cli -h \"$REDIS_HOST\" -p \"$REDIS_PORT\" ping &>/dev/null"
        fi

        if retry_connection "Redis" "$test_cmd"; then
            if [ -n "$REDIS_PASSWORD" ]; then
                log_success "Redis connesso con autenticazione"
            else
                log_success "Redis connesso senza autenticazione"
            fi
            break
        else
            log_warning "Riconfigurazione Redis necessaria..."
            continue
        fi
    done
    echo

    # MinIO con test immediato
    while true; do
        log_info "Configurazione MinIO:"
        read_input "Host MinIO" "$DEFAULT_MINIO_HOST" "MINIO_HOST"
        read_input "Porta MinIO" "$DEFAULT_MINIO_PORT" "MINIO_PORT"

        log_info "Credenziali MinIO Admin (per creare utente e bucket):"
        read_input "Username Admin MinIO" "" "MINIO_ADMIN_USER"
        read_password "Password Admin MinIO" "MINIO_ADMIN_PASSWORD"

        # Installa MinIO Client se non presente
        if ! command -v mc &> /dev/null; then
            log_info "Installazione MinIO Client..."
            wget https://dl.min.io/client/mc/release/linux-amd64/mc -O /usr/local/bin/mc &>/dev/null
            chmod +x /usr/local/bin/mc
        fi

        # Pulisci URL MinIO se contiene protocollo
        CLEAN_MINIO_HOST=$(echo "$MINIO_HOST" | sed 's|https\?://||')

        # Determina protocollo
        if [[ "$MINIO_PORT" == "443" ]] || [[ "$MINIO_HOST" =~ ^https:// ]]; then
            MINIO_PROTOCOL="https"
        else
            MINIO_PROTOCOL="http"
        fi

        # Test immediato connessione MinIO Admin
        test_cmd="/usr/local/bin/mc alias set test-admin $MINIO_PROTOCOL://$CLEAN_MINIO_HOST:$MINIO_PORT $MINIO_ADMIN_USER $MINIO_ADMIN_PASSWORD &>/dev/null"
        if retry_connection "MinIO Admin" "$test_cmd"; then
            log_success "MinIO Admin autenticato"
            /usr/local/bin/mc alias remove test-admin &>/dev/null

            log_info "Nuovo utente WordPress per MinIO:"
            read_input "Username WordPress MinIO" "" "MINIO_USER"
            read_password "Password WordPress MinIO" "MINIO_PASSWORD"
            read_input "Nome bucket" "$DEFAULT_MINIO_BUCKET" "MINIO_BUCKET"

            log_info "URL pubblico MinIO (per serving immagini ai visitatori):"
            read_input "URL pubblico MinIO" "https://$CLEAN_MINIO_HOST" "MINIO_PUBLIC_URL"
            break
        else
            log_warning "Riconfigurazione MinIO necessaria..."
            continue
        fi
    done
    echo
}

# Aggiornamento sistema
update_system() {
    log_info "Aggiornamento sistema..."
    apt update && apt upgrade -y
    log_success "Sistema aggiornato"
}

# Installazione pacchetti base PHP 8.3
install_base_packages() {
    log_info "Installazione pacchetti base PHP 8.3..."
    apt install -y \
        php8.3-fpm \
        php8.3-mysql \
        php8.3-redis \
        php8.3-curl \
        php8.3-gd \
        php8.3-intl \
        php8.3-mbstring \
        php8.3-soap \
        php8.3-xml \
        php8.3-xmlrpc \
        php8.3-zip \
        php8.3-imagick \
        php8.3-cli \
        php8.3-bcmath \
        php8.3-opcache \
        mysql-client \
        redis-tools \
        wget \
        curl \
        unzip \
        certbot \
        htop \
        nano \
        git \
        imagemagick \
        webp

    log_success "Pacchetti PHP 8.3 installati"
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

    # Installa redis-cli se non presente
    if ! command -v redis-cli &> /dev/null; then
        log_info "Installazione redis-cli..."
        apt install -y redis-tools
    fi

    # Test connessione Redis
    if [ -n "$REDIS_PASSWORD" ]; then
        if redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" -a "$REDIS_PASSWORD" ping &>/dev/null; then
            log_success "Connessione Redis OK (con password)"
        else
            log_error "Impossibile connettersi a Redis con password"
            log_error "Verifica: host=$REDIS_HOST, porta=$REDIS_PORT, password"
            exit 1
        fi
    else
        if redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" ping &>/dev/null; then
            log_success "Connessione Redis OK (senza password)"
        else
            log_error "Impossibile connettersi a Redis esterno"
            log_error "Verifica: host=$REDIS_HOST, porta=$REDIS_PORT"
            exit 1
        fi
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
$([ -n "$REDIS_PASSWORD" ] && echo "define('WP_REDIS_PASSWORD', '$REDIS_PASSWORD');")

// MinIO S3 Configuration - Doppia configurazione per performance
define('AS3CF_SETTINGS', serialize(array(
    'provider' => 'other',
    'access-key-id' => '$MINIO_USER',
    'secret-access-key' => '$MINIO_PASSWORD',
    'bucket' => '$MINIO_BUCKET',
    'region' => 'us-east-1',
    'copy-to-s3' => true,
    'serve-from-s3' => true,
    'domain' => 'cloudfront',
    'cloudfront' => '$MINIO_PUBLIC_URL',
    'object-prefix' => '',
    'use-server-roles' => false,
    'endpoint' => '$CLEAN_MINIO_HOST:$MINIO_PORT',
    'use-ssl' => $([ "$MINIO_PROTOCOL" == "https" ] && echo "true" || echo "false"),
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

// WordPress Security 2025
define('DISALLOW_FILE_EDIT', true);
define('DISALLOW_FILE_MODS', true);
define('FORCE_SSL_ADMIN', true);
define('WP_AUTO_UPDATE_CORE', 'minor');
define('AUTOMATIC_UPDATER_DISABLED', false);
define('WP_HTTP_BLOCK_EXTERNAL', false);
define('WP_ACCESSIBLE_HOSTS', '$REDIS_HOST,$DB_HOST,$MINIO_HOST');
define('COOKIE_DOMAIN', '.$SITE_URL');
define('COOKIEHASH', md5('$SITE_URL'));

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

    # Rimuovi eventuali versioni precedenti
    rm -f /usr/local/bin/wp wp-cli.phar

    # Download WP-CLI con verifiche (URL ufficiale)
    if curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar; then
        # Verifica che il file sia stato scaricato correttamente
        if [ -s wp-cli.phar ] && (file wp-cli.phar | grep -q "PHP\|PHAR\|executable" || php wp-cli.phar --version &>/dev/null); then
            chmod +x wp-cli.phar
            mv wp-cli.phar /usr/local/bin/wp

            # Test WP-CLI
            if /usr/local/bin/wp --info &>/dev/null; then
                log_success "WP-CLI installato e funzionante"
            else
                log_error "WP-CLI installato ma non funziona correttamente"
                exit 1
            fi
        else
            log_error "Download WP-CLI fallito o file corrotto"
            exit 1
        fi
    else
        log_error "Impossibile scaricare WP-CLI"
        exit 1
    fi
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

# Installazione plugin essenziali ottimizzati 2025
install_plugins() {
    log_info "Installazione plugin essenziali WordPress 2025..."

    cd /var/www/html

    # Plugin per cache e performance (solo Redis, no conflitti)
    sudo -u www-data wp plugin install redis-cache --activate
    log_info "Redis Cache: installato e attivato"

    # Plugin per SEO (scegli uno solo per evitare conflitti)
    sudo -u www-data wp plugin install wordpress-seo --activate
    log_info "Yoast SEO: installato e attivato"

    # Plugin per sicurezza essenziali
    sudo -u www-data wp plugin install wordfence --activate
    sudo -u www-data wp plugin install wp-security-audit-log --activate
    log_info "Plugin sicurezza: installati"

    # Plugin per MinIO/S3
    sudo -u www-data wp plugin install amazon-s3-and-cloudfront --activate
    log_info "S3 Plugin: installato per MinIO"

    # Plugin per ottimizzazione immagini e performance
    sudo -u www-data wp plugin install autoptimize --activate
    sudo -u www-data wp plugin install wp-optimize --activate
    sudo -u www-data wp plugin install imagify --activate
    sudo -u www-data wp plugin install webp-express --activate
    log_info "Plugin performance: installati"

    # Plugin per backup (compatibile con MinIO)
    sudo -u www-data wp plugin install updraftplus --activate
    log_info "UpdraftPlus: installato per backup"

    # Configurazione Redis Cache
    sudo -u www-data wp redis enable
    sudo -u www-data wp config set WP_REDIS_HOST "$REDIS_HOST"
    sudo -u www-data wp config set WP_REDIS_PORT "$REDIS_PORT"
    sudo -u www-data wp config set WP_REDIS_DATABASE 0

    # Configurazione base Autoptimize
    sudo -u www-data wp option update autoptimize_css 1
    sudo -u www-data wp option update autoptimize_js 1
    sudo -u www-data wp option update autoptimize_html 1
    sudo -u www-data wp option update autoptimize_css_defer 1

    log_success "Plugin WordPress 2025 installati e configurati"
}

# Configurazione PHP-FPM per Nginx Proxy Manager esterno
setup_phpfpm_for_proxy() {
    log_info "Configurazione PHP-FPM per Nginx Proxy Manager esterno..."

    # Configura PHP-FPM per ascoltare su porta TCP invece di socket
    sed -i 's|listen = /var/run/php/php8.3-fpm.sock|listen = 9000|' /etc/php/8.3/fpm/pool.d/www.conf
    sed -i 's|listen = /run/php/php8.3-fpm.sock|listen = 9000|' /etc/php/8.3/fpm/pool.d/www.conf
    sed -i 's/;listen.allowed_clients = 127.0.0.1/listen.allowed_clients = any/' /etc/php/8.3/fpm/pool.d/www.conf

    # Configura user e group
    sed -i 's/user = www-data/user = www-data/' /etc/php/8.3/fpm/pool.d/www.conf
    sed -i 's/group = www-data/group = www-data/' /etc/php/8.3/fpm/pool.d/www.conf

    # Ottimizzazioni per container
    echo "; Container optimizations" >> /etc/php/8.3/fpm/pool.d/www.conf
    echo "clear_env = no" >> /etc/php/8.3/fpm/pool.d/www.conf
    echo "catch_workers_output = yes" >> /etc/php/8.3/fpm/pool.d/www.conf

    # Restart e abilita PHP-FPM
    systemctl restart php8.3-fpm
    systemctl enable php8.3-fpm

    # Verifica che PHP-FPM stia ascoltando sulla porta 9000
    sleep 2  # Aspetta che PHP-FPM si riavvii
    if ss -ln | grep -q ":9000" || netstat -ln | grep -q ":9000"; then
        log_success "PHP-FPM configurato correttamente sulla porta 9000"
    else
        log_error "Errore: PHP-FPM non sta ascoltando sulla porta 9000"
        log_info "Configurazione attuale:"
        grep "listen = " /etc/php/8.3/fpm/pool.d/www.conf
        log_info "Porte in ascolto:"
        ss -ln | grep ":900[0-9]" || netstat -ln | grep ":900[0-9]" || echo "Nessuna porta 900x in ascolto"
        exit 1
    fi

    log_success "PHP-FPM configurato per proxy esterno"
}

# Configurazione PHP 8.3-FPM ottimizzata per WordPress 2025
optimize_php() {
    log_info "Ottimizzazione PHP 8.3-FPM per WordPress 2025..."

    # Configurazione PHP-FPM pool ottimizzata
    cat > /etc/php/8.3/fpm/pool.d/www.conf << EOF
[www]
user = www-data
group = www-data
listen = /var/run/php/php8.3-fpm.sock
listen.owner = www-data
listen.group = www-data
listen.mode = 0660
pm = dynamic
pm.max_children = 75
pm.start_servers = 8
pm.min_spare_servers = 5
pm.max_spare_servers = 25
pm.process_idle_timeout = 10s
pm.max_requests = 1000
request_terminate_timeout = 300
rlimit_files = 65535
rlimit_core = 0
catch_workers_output = yes
php_admin_value[error_log] = /var/log/php8.3-fpm.log
php_admin_flag[log_errors] = on
EOF

    # Configurazione PHP 8.3 ottimizzata per WordPress
    cat > /etc/php/8.3/fpm/conf.d/99-wordpress-2025.ini << EOF
; WordPress 2025 optimizations for PHP 8.3
memory_limit = 1024M
upload_max_filesize = 512M
post_max_size = 512M
max_execution_time = 300
max_input_vars = 5000
max_input_time = 300
max_file_uploads = 20

; OPcache optimizations for WordPress 2025
opcache.enable = 1
opcache.enable_cli = 1
opcache.memory_consumption = 512
opcache.interned_strings_buffer = 64
opcache.max_accelerated_files = 32531
opcache.validate_timestamps = 0
opcache.save_comments = 1
opcache.fast_shutdown = 1
opcache.enable_file_override = 1
opcache.optimization_level = 0x7FFFBFFF
opcache.jit = tracing
opcache.jit_buffer_size = 256M

; Security enhancements 2025
expose_php = Off
allow_url_fopen = Off
allow_url_include = Off
session.cookie_httponly = On
session.cookie_secure = On
session.use_strict_mode = 1
session.cookie_samesite = "Strict"

; Performance enhancements
realpath_cache_size = 4096K
realpath_cache_ttl = 600

; Error logging
log_errors = On
error_log = /var/log/php_errors.log
display_errors = Off
log_errors_max_len = 1024

; Session optimization
session.save_handler = files
session.save_path = "/var/www/sessions"
session.gc_maxlifetime = 7200
session.gc_probability = 1
session.gc_divisor = 1000
EOF

    # Restart and enable PHP 8.3-FPM
    systemctl restart php8.3-fpm
    systemctl enable php8.3-fpm

    log_success "PHP 8.3-FPM ottimizzato per WordPress 2025"
}

# Test connessione e configurazione MinIO esterno
test_minio_connection() {
    log_info "Test connessione MinIO esterno..."

    # Installazione MinIO Client
    wget https://dl.min.io/client/mc/release/linux-amd64/mc -O /usr/local/bin/mc
    chmod +x /usr/local/bin/mc

    # Pulisci URL MinIO se contiene protocollo
    CLEAN_MINIO_HOST=$(echo "$MINIO_HOST" | sed 's|https\?://||')

    # Determina protocollo (HTTPS se porta 443 o host contiene https)
    if [[ "$MINIO_PORT" == "443" ]] || [[ "$MINIO_HOST" =~ ^https:// ]]; then
        MINIO_PROTOCOL="https"
    else
        MINIO_PROTOCOL="http"
    fi

    # Test connessione MinIO con admin
    if /usr/local/bin/mc alias set minio-admin $MINIO_PROTOCOL://$CLEAN_MINIO_HOST:$MINIO_PORT $MINIO_ADMIN_USER $MINIO_ADMIN_PASSWORD &>/dev/null; then
        log_success "Connessione MinIO Admin OK"
    else
        log_error "Impossibile connettersi a MinIO con credenziali admin"
        log_error "Verifica: host=$MINIO_HOST, porta=$MINIO_PORT, admin credenziali"
        exit 1
    fi

    # Crea utente WordPress per MinIO
    log_info "Creazione utente WordPress per MinIO..."
    /usr/local/bin/mc admin user add minio-admin $MINIO_USER $MINIO_PASSWORD &>/dev/null || log_warning "Utente già esistente"

    # Crea policy per il bucket
    cat > /tmp/wp-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetBucketLocation",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::$MINIO_BUCKET"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject"
      ],
      "Resource": [
        "arn:aws:s3:::$MINIO_BUCKET/*"
      ]
    }
  ]
}
EOF

    /usr/local/bin/mc admin policy create minio-admin wp-policy /tmp/wp-policy.json
    /usr/local/bin/mc admin policy attach minio-admin wp-policy --user=$MINIO_USER
    rm /tmp/wp-policy.json

    # Verifica/Crea bucket
    if /usr/local/bin/mc ls minio-admin/$MINIO_BUCKET &>/dev/null; then
        log_success "Bucket $MINIO_BUCKET esistente"
    else
        log_info "Creazione bucket $MINIO_BUCKET..."
        /usr/local/bin/mc mb minio-admin/$MINIO_BUCKET
        /usr/local/bin/mc policy set download minio-admin/$MINIO_BUCKET
        log_success "Bucket $MINIO_BUCKET creato e configurato"
    fi

    # Test con utente WordPress
    if /usr/local/bin/mc alias set minio-wp $MINIO_PROTOCOL://$CLEAN_MINIO_HOST:$MINIO_PORT $MINIO_USER $MINIO_PASSWORD &>/dev/null; then
        log_success "Utente WordPress MinIO configurato correttamente"
    else
        log_error "Errore configurazione utente WordPress MinIO"
        exit 1
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

# Installazione strumenti monitoring avanzato
install_monitoring_tools() {
    log_info "Installazione strumenti monitoring avanzato..."

    # New Relic PHP Agent (opzionale)
    read -p "Installare New Relic PHP Agent? (y/N): " install_newrelic
    if [[ $install_newrelic == [yY] ]]; then
        curl -L https://download.newrelic.com/php_agent/scripts/newrelic-install.sh | bash
        log_success "New Relic installato"
    fi

    # Script di monitoraggio WordPress
    cat > /opt/scripts/wp-monitor.sh << EOF
#!/bin/bash
# WordPress monitoring script

LOG_FILE="/var/log/wp-monitor.log"
DATE=\$(date '+%Y-%m-%d %H:%M:%S')

# Check WordPress response time
RESPONSE_TIME=\$(curl -o /dev/null -s -w '%{time_total}' http://localhost)
echo "[\$DATE] Response time: \$RESPONSE_TIME seconds" >> \$LOG_FILE

# Check Redis connection
if [ -n "$REDIS_PASSWORD" ]; then
    if redis-cli -h $REDIS_HOST -p $REDIS_PORT -a $REDIS_PASSWORD ping > /dev/null 2>&1; then
        echo "[\$DATE] Redis: OK" >> \$LOG_FILE
    else
        echo "[\$DATE] Redis: ERROR" >> \$LOG_FILE
    fi
else
    if redis-cli -h $REDIS_HOST -p $REDIS_PORT ping > /dev/null 2>&1; then
        echo "[\$DATE] Redis: OK" >> \$LOG_FILE
    else
        echo "[\$DATE] Redis: ERROR" >> \$LOG_FILE
    fi
fi

# Check database connection
if mysql -h $DB_HOST -P $DB_PORT -u $DB_USER -p$DB_PASSWORD -e "SELECT 1;" $DB_NAME > /dev/null 2>&1; then
    echo "[\$DATE] Database: OK" >> \$LOG_FILE
else
    echo "[\$DATE] Database: ERROR" >> \$LOG_FILE
fi

# Check disk usage
DISK_USAGE=\$(df / | awk 'NR==2 {print \$5}' | sed 's/%//')
if [ "\$DISK_USAGE" -gt 80 ]; then
    echo "[\$DATE] WARNING: Disk usage at \${DISK_USAGE}%" >> \$LOG_FILE
fi

# Check PHP-FPM processes
PHP_PROCESSES=\$(ps aux | grep php8.3-fpm | grep -v grep | wc -l)
echo "[\$DATE] PHP-FPM processes: \$PHP_PROCESSES" >> \$LOG_FILE
EOF

    chmod +x /opt/scripts/wp-monitor.sh

    # Performance test script
    cat > /opt/scripts/wp-performance-test.sh << EOF
#!/bin/bash
# WordPress performance test

echo "=== WordPress Performance Test ==="

# Test homepage load time
echo "Testing homepage load time..."
curl -o /dev/null -s -w "Time: %{time_total}s | Size: %{size_download} bytes | Speed: %{speed_download} bytes/s\n" "http://localhost"

# Test wp-admin load time
echo "Testing wp-admin load time..."
curl -o /dev/null -s -w "Time: %{time_total}s | Size: %{size_download} bytes | Speed: %{speed_download} bytes/s\n" "http://localhost/wp-admin/"

# PHP OPcache status
echo "\nPHP OPcache Status:"
php -r "if(function_exists('opcache_get_status')){\$status=opcache_get_status();echo 'Enabled: '.var_export(\$status['opcache_enabled'],true).'\\n';echo 'Hit Rate: '.number_format(\$status['opcache_statistics']['opcache_hit_rate'],2).'%\\n';echo 'Memory Usage: '.number_format(\$status['memory_usage']['used_memory']/1024/1024,2).'MB\\n';}else{echo 'OPcache not available\\n';}"

# Redis performance test
echo "\nRedis Performance Test:"
redis-cli -h $REDIS_HOST -p $REDIS_PORT --latency-history -i 1 -c 5 2>/dev/null || echo "Redis non raggiungibile"
EOF

    chmod +x /opt/scripts/wp-performance-test.sh

    # Add monitoring cron job
    (crontab -l 2>/dev/null; echo "*/5 * * * * /opt/scripts/wp-monitor.sh") | crontab -

    log_success "Strumenti monitoring installati"
}

# Test finale
final_test() {
    log_info "Test finale del sistema..."

    # Test servizi
    systemctl is-active --quiet php8.3-fpm && log_success "PHP-FPM: OK" || log_error "PHP-FPM: ERRORE"
    systemctl is-active --quiet php8.3-fpm && log_success "PHP-FPM: OK" || log_error "PHP-FPM: ERRORE"

    # I test dei servizi esterni sono già stati fatti durante la configurazione
    log_info "Servizi esterni già verificati durante la configurazione"

    # Test WordPress specifici
    if curl -s -o /dev/null -w "%{http_code}" "http://localhost" | grep -q "200"; then
        log_success "WordPress HTTP: OK"
    else
        log_error "WordPress HTTP: ERRORE"
    fi

    # Test PHP OPcache
    php -v | grep -q "with Zend OPcache" && log_success "PHP OPcache: OK" || log_error "PHP OPcache: ERRORE"

    # Test PHP JIT
    php -v | grep -q "JIT" && log_success "PHP JIT: OK" || log_warning "PHP JIT: Non rilevato"

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
    setup_phpfpm_for_proxy
    optimize_php
    system_optimizations
    setup_backup
    install_monitoring_tools

    log_info "SSL configurazione saltata - usa Nginx Proxy Manager per SSL/TLS"

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
    log_info "Strumenti disponibili:"
    echo "- Performance test: /opt/scripts/wp-performance-test.sh"
    echo "- Monitoring log: tail -f /var/log/wp-monitor.log"
    echo "- Test connessioni: /opt/scripts/test-redis-connection.sh && /opt/scripts/test-mysql-connection.sh"
    echo
    log_info "Prossimi passi:"
    echo "1. Configura i plugin installati (Yoast SEO, Wordfence, etc.)"
    echo "2. Personalizza il tema"
    echo "3. Verifica configurazione MinIO S3 nel plugin"
    echo "4. Testa la cache Redis con WP-CLI"
    echo "5. Esegui test performance: /opt/scripts/wp-performance-test.sh"
    echo "6. Configura Nginx Proxy Manager per SSL e dominio"
    echo
}

# Esecuzione script
main "$@"