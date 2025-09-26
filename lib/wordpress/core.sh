#!/bin/bash

# =============================================================================
# WORDPRESS CORE INSTALLATION FUNCTIONS
# =============================================================================

# shellcheck source=./utils.sh
source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"
# shellcheck source=./validation.sh
source "$(dirname "${BASH_SOURCE[0]}")/validation.sh"

install_wpcli() {
    log_step "Installazione WP-CLI..."

    if command -v wp >/dev/null 2>&1; then
        log_info "WP-CLI già installato"
        return 0
    fi

    # Download latest WP-CLI
    curl -o /tmp/wp-cli.phar https://raw.githubusercontent.com/wp-cli/wp-cli/gh-pages/wp-cli.phar

    # Verify download
    if [[ ! -f /tmp/wp-cli.phar ]]; then
        log_error "Errore download WP-CLI"
        return 1
    fi

    # Make executable and move to PATH
    chmod +x /tmp/wp-cli.phar
    mv /tmp/wp-cli.phar /usr/local/bin/wp

    # Verify installation
    if wp --version >/dev/null 2>&1; then
        log_success "WP-CLI installato"
    else
        log_error "Errore verifica installazione WP-CLI"
        return 1
    fi
}

configure_wpcli_for_lxc() {
    log_step "Configurazione WP-CLI per container LXC..."

    # Create wp-cli configuration
    mkdir -p /var/www/.wp-cli
    cat > /var/www/.wp-cli/config.yml << 'WPCLI_CONFIG_EOF'
# WP-CLI Configuration for LXC
path: /var/www
url: http://localhost
user: www-data
core download:
    version: latest
    locale: it_IT
core config:
    dbhost: localhost
    extra-php: |
        define('WP_DEBUG', false);
        define('WP_DEBUG_LOG', false);
        define('WP_DEBUG_DISPLAY', false);
        define('SCRIPT_DEBUG', false);
        define('WP_MEMORY_LIMIT', '512M');
        define('WP_MAX_MEMORY_LIMIT', '512M');
WPCLI_CONFIG_EOF

    chown -R www-data:www-data /var/www/.wp-cli
    log_success "WP-CLI configurato per LXC"
}

get_wp_admin_user() {
    if [[ -n "$WP_ADMIN_USER" ]]; then
        echo "$WP_ADMIN_USER"
        return 0
    fi

    if [[ -n "$ADMIN_EMAIL" ]]; then
        echo "${ADMIN_EMAIL%%@*}"
        return 0
    fi

    echo "admin"
}

install_wordpress() {
    log_step "Installazione WordPress..."

    local wp_dir="/var/www/${DOMAIN}"

    # Create directory
    mkdir -p "$wp_dir"
    if [ ! -d "$wp_dir" ]; then
        log_error "Impossibile creare directory: $wp_dir"
        return 1
    fi
    cd "$wp_dir" || {
        log_error "Impossibile accedere a: $wp_dir"
        return 1
    }

    # Download WordPress with retry logic
    if ! retry_command 3 10 "Download WordPress" wp --allow-root core download --locale="$WP_LOCALE" --path="$wp_dir"; then
        log_error "Errore download WordPress dopo i retry"
        return 1
    fi

    # Fix permissions immediately after download
    chown -R www-data:www-data "$wp_dir"
    find "$wp_dir" -type d -exec chmod 755 {} \;
    find "$wp_dir" -type f -exec chmod 644 {} \;

    # Generate secure database prefix and salts
    local db_prefix="wp_$(openssl rand -hex 3)_"

    # Debug: Log current working directory before wp-config creation
    log_info "Directory corrente: $(pwd)"
    log_info "Creazione wp-config.php in: $wp_dir"

    # Create wp-config.php
    wp --allow-root config create \
        --dbname="$DB_NAME" \
        --dbuser="$DB_USER" \
        --dbpass="$DB_PASS" \
        --dbhost="$DB_HOST" \
        --dbprefix="$db_prefix" \
        --path="$wp_dir" || {
        log_error "Errore creazione wp-config.php"
        log_error "Directory corrente durante errore: $(pwd)"
        return 1
    }

    # Verify wp-config.php was created before fixing permissions
    if [[ -f "$wp_dir/wp-config.php" ]]; then
        # Fix permissions after wp-config creation
        chown www-data:www-data "$wp_dir/wp-config.php"
        chmod 640 "$wp_dir/wp-config.php"
        log_info "Permessi wp-config.php aggiornati"
    else
        log_error "wp-config.php non trovato dopo la creazione in: $wp_dir/wp-config.php"
        # List directory contents for debugging
        log_info "Contenuto directory $wp_dir:"
        ls -la "$wp_dir/" || log_error "Impossibile elencare contenuto directory"
        return 1
    fi

    configure_wordpress_advanced "$wp_dir"

    # Install WordPress with appropriate URL
    local wp_url="http://$DOMAIN"
    if [ "$NPM_MODE" = true ] && [ "${NPM_SSL:-true}" = true ]; then
        wp_url="https://$DOMAIN"
        log_info "Installazione WordPress per NPM con HTTPS: $wp_url"
    else
        log_info "Installazione WordPress: $wp_url"
    fi

    if ! retry_command 3 5 "Installazione WordPress" wp --allow-root core install \
        --url="$wp_url" \
        --title="$SITE_NAME" \
        --admin_user="$WP_ADMIN_USER" \
        --admin_password="$WP_ADMIN_PASS" \
        --admin_email="$WP_ADMIN_EMAIL" \
        --skip-email \
        --path="$wp_dir"; then
        log_error "Errore installazione WordPress dopo i retry"
        return 1
    fi

    # Configure WordPress for NPM if needed
    if [ "$NPM_MODE" = true ]; then
        configure_wordpress_for_npm
    fi

    log_success "WordPress installato"
}

configure_wordpress_for_npm() {
    log_step "Configurazione WordPress per NPM Backend..."

    cd "/var/www/$DOMAIN"

    # NPM Proxy Configuration in wp-config.php
    log_info "Aggiunta configurazione proxy NPM a wp-config.php..."

    local wp_config_additions
    wp_config_additions=$(cat << 'NPM_CONFIG_EOF'

// NPM Proxy Configuration
if (isset($_SERVER['HTTP_X_FORWARDED_PROTO']) && $_SERVER['HTTP_X_FORWARDED_PROTO'] === 'https') {
    $_SERVER['HTTPS'] = 'on';
    define('FORCE_SSL_ADMIN', true);
}

if (isset($_SERVER['HTTP_X_FORWARDED_HOST'])) {
    $_SERVER['HTTP_HOST'] = $_SERVER['HTTP_X_FORWARDED_HOST'];
}

// Trust proxy headers
if (isset($_SERVER['HTTP_X_REAL_IP'])) {
    $_SERVER['REMOTE_ADDR'] = $_SERVER['HTTP_X_REAL_IP'];
}

// WordPress URL Configuration for NPM
if (isset($_SERVER['HTTP_X_FORWARDED_PROTO'])) {
    $protocol = $_SERVER['HTTP_X_FORWARDED_PROTO'];
} else {
    $protocol = 'http';
}

$domain = $_SERVER['HTTP_HOST'] ?? 'DOMAIN_PLACEHOLDER';
define('WP_HOME', $protocol . '://' . $domain);
define('WP_SITEURL', $protocol . '://' . $domain);

// Disable file editing
define('DISALLOW_FILE_EDIT', true);
define('DISALLOW_FILE_MODS', false);

NPM_CONFIG_EOF
)

    # Replace placeholder with actual domain
    wp_config_additions=${wp_config_additions//DOMAIN_PLACEHOLDER/$DOMAIN}

    # Add configuration before the WordPress loading line
    if grep -q "wp-settings.php" wp-config.php; then
        # Create temporary file with new configuration
        sed "/wp-settings.php/i\\$wp_config_additions" wp-config.php > wp-config-tmp.php
        mv wp-config-tmp.php wp-config.php
        chown www-data:www-data wp-config.php
        chmod 640 wp-config.php
        log_success "Configurazione NPM aggiunta a wp-config.php"
    else
        log_error "Impossibile trovare wp-settings.php in wp-config.php"
        return 1
    fi

    # Configure WordPress URLs via WP-CLI
    local npm_url="https://$DOMAIN"
    wp --allow-root option update home "$npm_url" --path="/var/www/$DOMAIN"
    wp --allow-root option update siteurl "$npm_url" --path="/var/www/$DOMAIN"

    log_success "WordPress configurato per NPM"
}

configure_wordpress_advanced() {
    local wp_dir="$1"
    log_step "Configurazione avanzata WordPress..."

    cd "$wp_dir" || return 1

    # Add advanced WordPress configurations to wp-config.php
    local wp_config="$wp_dir/wp-config.php"

    # Backup original config
    cp "$wp_config" "${wp_config}.backup"

    # Add advanced configuration before the WordPress loading line
    local advanced_config
    advanced_config=$(cat << 'ADVANCED_CONFIG_EOF'

// Advanced WordPress Configuration - September 2025

// Performance Settings
define('WP_MEMORY_LIMIT', '512M');
define('WP_MAX_MEMORY_LIMIT', '512M');
define('WP_CACHE', true);
define('COMPRESS_CSS', true);
define('COMPRESS_SCRIPTS', true);
define('CONCATENATE_SCRIPTS', false);
define('ENFORCE_GZIP', true);

// Security Settings
define('DISALLOW_FILE_EDIT', true);
define('FORCE_SSL_ADMIN', true);
define('WP_AUTO_UPDATE_CORE', 'minor');
define('AUTOMATIC_UPDATER_DISABLED', false);

// Debug Settings (disable in production)
define('WP_DEBUG', false);
define('WP_DEBUG_LOG', false);
define('WP_DEBUG_DISPLAY', false);
define('SCRIPT_DEBUG', false);

// Revision and Autosave Settings
define('WP_POST_REVISIONS', 3);
define('AUTOSAVE_INTERVAL', 300);

// Trash and Cleanup
define('EMPTY_TRASH_DAYS', 7);
define('WP_CRON_LOCK_TIMEOUT', 60);

// Media Settings
define('ALLOW_UNFILTERED_UPLOADS', false);
define('WP_ALLOW_MULTISITE', false);

// Cookie Settings
define('COOKIEHASH', md5('DOMAIN_PLACEHOLDER' . 'secure_salt_' . time()));

ADVANCED_CONFIG_EOF
)

    # Replace placeholder with actual domain
    advanced_config=${advanced_config//DOMAIN_PLACEHOLDER/$DOMAIN}

    # Add configuration before the WordPress loading line
    if grep -q "wp-settings.php" "$wp_config"; then
        # Create temporary file with new configuration
        sed "/wp-settings.php/i\\$advanced_config" "$wp_config" > "${wp_config}.tmp"
        mv "${wp_config}.tmp" "$wp_config"
        chown www-data:www-data "$wp_config"
        chmod 640 "$wp_config"
        log_success "Configurazione avanzata WordPress applicata"
    else
        log_error "Impossibile trovare wp-settings.php in wp-config.php"
        return 1
    fi
}