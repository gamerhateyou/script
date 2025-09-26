#!/bin/bash

# =============================================================================
# WORDPRESS SECURITY AND OPTIMIZATION FUNCTIONS
# =============================================================================

# shellcheck source=./utils.sh
source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"

setup_ssl_certificates() {
    log_step "Configurazione certificati SSL..."

    # Install certbot if not present
    if ! command -v certbot >/dev/null 2>&1; then
        apt install -y certbot python3-certbot-nginx
    fi

    # Generate SSL certificate
    if [ "$NPM_MODE" != true ]; then
        log_info "Generazione certificato SSL per $DOMAIN..."

        # Try to obtain certificate
        if certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos --email "$WP_ADMIN_EMAIL" --redirect; then
            log_success "Certificato SSL installato per $DOMAIN"
        else
            log_warn "Impossibile ottenere certificato SSL automaticamente"
            log_info "Configura manualmente il certificato SSL se necessario"
        fi
    else
        log_info "Modalità NPM attiva - SSL gestito da Nginx Proxy Manager"
    fi
}

configure_security() {
    log_step "Configurazione sicurezza WordPress..."

    local wp_dir="/var/www/${DOMAIN}"
    cd "$wp_dir" || return 1

    # Disable XML-RPC if not needed
    wp --allow-root option update default_pingback_flag 0 >/dev/null 2>&1

    # Disable file editing from admin panel
    if ! grep -q "DISALLOW_FILE_EDIT" wp-config.php; then
        sed -i "/wp-settings.php/i define('DISALLOW_FILE_EDIT', true);" wp-config.php
    fi

    # Configure automatic updates
    if ! grep -q "WP_AUTO_UPDATE_CORE" wp-config.php; then
        sed -i "/wp-settings.php/i define('WP_AUTO_UPDATE_CORE', 'minor');" wp-config.php
    fi

    # Remove default admin user if exists
    if wp --allow-root user get admin >/dev/null 2>&1; then
        if [[ "$WP_ADMIN_USER" != "admin" ]]; then
            wp --allow-root user delete admin --yes >/dev/null 2>&1 || log_warn "Impossibile rimuovere utente admin"
        fi
    fi

    # Set strong password policy
    wp --allow-root option update medium_large_size_w 0 >/dev/null 2>&1
    wp --allow-root option update medium_large_size_h 0 >/dev/null 2>&1

    log_success "Sicurezza WordPress configurata"
}

configure_firewall() {
    log_step "Configurazione firewall..."

    # Install UFW if not present
    if ! command -v ufw >/dev/null 2>&1; then
        apt install -y ufw
    fi

    # Reset UFW to defaults
    ufw --force reset >/dev/null 2>&1

    # Default policies
    ufw default deny incoming >/dev/null 2>&1
    ufw default allow outgoing >/dev/null 2>&1

    # Allow essential services
    ufw allow 22/tcp comment "SSH" >/dev/null 2>&1
    ufw allow 80/tcp comment "HTTP" >/dev/null 2>&1
    ufw allow 443/tcp comment "HTTPS" >/dev/null 2>&1

    # Enable UFW
    ufw --force enable >/dev/null 2>&1

    log_success "Firewall configurato"
}

set_wordpress_permissions() {
    log_step "Impostazione permessi WordPress..."

    local wp_dir="/var/www/${DOMAIN}"

    if [[ ! -d "$wp_dir" ]]; then
        log_error "Directory WordPress non trovata: $wp_dir"
        return 1
    fi

    # Set ownership
    chown -R www-data:www-data "$wp_dir"

    # Set directory permissions
    find "$wp_dir" -type d -exec chmod 755 {} \;

    # Set file permissions
    find "$wp_dir" -type f -exec chmod 644 {} \;

    # Secure wp-config.php
    if [[ -f "$wp_dir/wp-config.php" ]]; then
        chmod 640 "$wp_dir/wp-config.php"
    fi

    # Secure .htaccess
    if [[ -f "$wp_dir/.htaccess" ]]; then
        chmod 644 "$wp_dir/.htaccess"
    fi

    # Make wp-content/uploads writable
    if [[ -d "$wp_dir/wp-content/uploads" ]]; then
        chmod -R 755 "$wp_dir/wp-content/uploads"
    fi

    log_success "Permessi WordPress impostati"
}

setup_maintenance_jobs() {
    log_step "Configurazione job di manutenzione..."

    # Create maintenance scripts directory
    mkdir -p /opt/wordpress-maintenance

    # WordPress cleanup script
    cat > /opt/wordpress-maintenance/cleanup.sh << 'CLEANUP_SCRIPT_EOF'
#!/bin/bash

# WordPress Maintenance Cleanup Script
WP_PATH="/var/www"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Clean WordPress transients
for site in "$WP_PATH"/*; do
    if [[ -d "$site" && -f "$site/wp-config.php" ]]; then
        domain=$(basename "$site")
        log "Pulizia transients per $domain"
        wp --allow-root --path="$site" transient delete --all >/dev/null 2>&1 || true

        # Clean spam comments
        wp --allow-root --path="$site" comment delete --all --force >/dev/null 2>&1 || true

        # Optimize database
        wp --allow-root --path="$site" db optimize >/dev/null 2>&1 || true
    fi
done

# Clean system logs
find /var/log -name "*.log" -mtime +30 -delete 2>/dev/null || true
find /tmp -type f -mtime +7 -delete 2>/dev/null || true

log "Manutenzione completata"
CLEANUP_SCRIPT_EOF

    chmod +x /opt/wordpress-maintenance/cleanup.sh

    # Add to crontab
    (crontab -l 2>/dev/null; echo "0 2 * * 0 /opt/wordpress-maintenance/cleanup.sh >> /var/log/wp-maintenance.log 2>&1") | crontab -

    log_success "Job di manutenzione configurati"
}

create_backup_scripts() {
    log_step "Creazione script di backup..."

    mkdir -p /opt/wordpress-backup

    # Backup script
    cat > /opt/wordpress-backup/backup.sh << 'BACKUP_SCRIPT_EOF'
#!/bin/bash

WP_PATH="/var/www"
BACKUP_PATH="/opt/backups"
DATE=$(date +%Y%m%d_%H%M%S)

mkdir -p "$BACKUP_PATH"

for site in "$WP_PATH"/*; do
    if [[ -d "$site" && -f "$site/wp-config.php" ]]; then
        domain=$(basename "$site")

        # Database backup
        wp --allow-root --path="$site" db export "$BACKUP_PATH/${domain}_${DATE}.sql" >/dev/null 2>&1

        # Files backup (exclude uploads for space)
        tar -czf "$BACKUP_PATH/${domain}_files_${DATE}.tar.gz" \
            --exclude="$site/wp-content/uploads" \
            "$site" >/dev/null 2>&1
    fi
done

# Clean old backups (keep 7 days)
find "$BACKUP_PATH" -name "*.sql" -mtime +7 -delete 2>/dev/null
find "$BACKUP_PATH" -name "*.tar.gz" -mtime +7 -delete 2>/dev/null
BACKUP_SCRIPT_EOF

    chmod +x /opt/wordpress-backup/backup.sh

    # Add to crontab
    (crontab -l 2>/dev/null; echo "0 1 * * * /opt/wordpress-backup/backup.sh") | crontab -

    log_success "Script di backup configurati"
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

create_health_check_endpoint() {
    log_step "Creazione endpoint di health check..."

    local wp_dir="/var/www/${DOMAIN}"

    # Create health check script
    cat > "$wp_dir/health.php" << 'HEALTH_CHECK_EOF'
<?php
// Simple WordPress Health Check
header('Content-Type: application/json');

$health = array(
    'status' => 'ok',
    'timestamp' => date('c'),
    'checks' => array()
);

// Check database connection
try {
    require_once 'wp-config.php';
    $db = new PDO("mysql:host=" . DB_HOST . ";dbname=" . DB_NAME, DB_USER, DB_PASSWORD);
    $health['checks']['database'] = 'ok';
} catch (Exception $e) {
    $health['status'] = 'error';
    $health['checks']['database'] = 'error';
}

// Check file permissions
$health['checks']['writable'] = is_writable('wp-content/uploads') ? 'ok' : 'warning';

// Check disk space
$free_bytes = disk_free_space('.');
$total_bytes = disk_total_space('.');
$usage_percent = round((($total_bytes - $free_bytes) / $total_bytes) * 100, 2);

$health['checks']['disk_usage'] = array(
    'percent' => $usage_percent,
    'status' => $usage_percent > 90 ? 'warning' : 'ok'
);

echo json_encode($health, JSON_PRETTY_PRINT);
?>
HEALTH_CHECK_EOF

    chown www-data:www-data "$wp_dir/health.php"
    chmod 644 "$wp_dir/health.php"

    log_success "Health check endpoint creato: http://$DOMAIN/health.php"
}

optimize_theme_settings() {
    log_step "Ottimizzazione impostazioni tema..."

    local wp_dir="/var/www/${DOMAIN}"
    cd "$wp_dir" || return 1

    # Disable unnecessary WordPress features
    wp --allow-root option update use_smilies 0 >/dev/null 2>&1
    wp --allow-root option update enable_app 0 >/dev/null 2>&1
    wp --allow-root option update enable_xmlrpc 0 >/dev/null 2>&1

    # Set optimal image sizes
    wp --allow-root option update thumbnail_size_w 150 >/dev/null 2>&1
    wp --allow-root option update thumbnail_size_h 150 >/dev/null 2>&1
    wp --allow-root option update medium_size_w 300 >/dev/null 2>&1
    wp --allow-root option update medium_size_h 300 >/dev/null 2>&1
    wp --allow-root option update large_size_w 1024 >/dev/null 2>&1
    wp --allow-root option update large_size_h 1024 >/dev/null 2>&1

    # Disable pingbacks
    wp --allow-root option update default_pingback_flag 0 >/dev/null 2>&1
    wp --allow-root option update default_ping_status closed >/dev/null 2>&1

    # Set optimal permalink structure
    wp --allow-root rewrite structure '/%postname%/' >/dev/null 2>&1

    log_success "Impostazioni tema ottimizzate"
}

configure_nginx_site() {
    local domain="$1"
    local php_version="${PHP_VERSION:-8.3}"

    log_step "Configurazione sito Nginx per $domain..."

    # Check if domain parameter is provided
    if [[ -z "$domain" ]]; then
        log_error "Dominio non specificato per configurazione Nginx"
        return 1
    fi

    local site_config="$NGINX_SITES_AVAILABLE/$domain"
    local wp_root="/var/www/$domain"

    # Create WordPress Nginx configuration
    cat > "$site_config" << NGINX_SITE_EOF
server {
    listen 80;
    listen [::]:80;
    server_name $domain www.$domain;
    root $wp_root;
    index index.php index.html index.htm;

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header X-Content-Type-Options "nosniff" always;

    # WordPress specific rules
    include /etc/nginx/conf.d/wordpress-common.conf;

    # Main location block
    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }

    # PHP-FPM configuration
    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php$php_version-fpm-wordpress.sock;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;

        # Security
        fastcgi_hide_header X-Powered-By;
        fastcgi_read_timeout 300;
    }

    # Rate limiting for login pages
    location ~ ^/(wp-admin|wp-login\.php) {
        limit_req zone=login burst=5 nodelay;
        try_files \$uri \$uri/ /index.php?\$args;

        location ~ \.php\$ {
            include snippets/fastcgi-php.conf;
            fastcgi_pass unix:/run/php/php$php_version-fpm-wordpress.sock;
            fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
            include fastcgi_params;
        }
    }

    # Deny access to sensitive files
    location ~ /\. {
        deny all;
    }

    location ~ ~\$ {
        deny all;
    }

    # WordPress security
    location ~* ^/(wp-config\.php|wp-config-sample\.php|readme\.html|license\.txt)\$ {
        deny all;
    }

    # Optimize static files
    location ~* \.(css|gif|ico|jpeg|jpg|js|png|webp|svg|woff|woff2|ttf|eot)\$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
        add_header Vary Accept-Encoding;
        access_log off;
    }

    # Gzip compression
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
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
}
NGINX_SITE_EOF

    # Enable the site
    ln -sf "$site_config" "$NGINX_SITES_ENABLED/"

    # Test Nginx configuration
    if nginx -t >/dev/null 2>&1; then
        systemctl reload nginx
        log_success "Sito Nginx $domain configurato e attivato"
    else
        log_error "Errore nella configurazione Nginx per $domain"
        return 1
    fi
}