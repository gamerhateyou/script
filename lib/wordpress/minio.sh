#!/bin/bash

# =============================================================================
# MINIO S3 INTEGRATION FUNCTIONS
# =============================================================================

# shellcheck source=./utils.sh
source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"

test_redis_connection() {
    if [[ "${USE_REDIS:-}" != "y"* ]]; then
        log_info "Redis non configurato, salto test"
        return 0
    fi

    log_info "Test connessione Redis..."

    local redis_host="${REDIS_HOST:-localhost}"
    local redis_port="${REDIS_PORT:-6379}"

    if command -v redis-cli >/dev/null 2>&1; then
        if timeout 5 redis-cli -h "$redis_host" -p "$redis_port" ping >/dev/null 2>&1; then
            log_success "Connessione Redis OK"
            return 0
        else
            log_error "Connessione Redis fallita"
            return 1
        fi
    else
        log_warn "redis-cli non disponibile, impossibile testare Redis"
        return 0
    fi
}

test_minio_connection() {
    if [[ "${USE_MINIO:-}" != "y"* ]]; then
        log_info "MinIO non configurato, salto test"
        return 0
    fi

    log_info "Test connessione MinIO..."

    local minio_endpoint="${MINIO_ENDPOINT:-localhost:9000}"
    local minio_host="${minio_endpoint%%:*}"
    local minio_port="${minio_endpoint##*:}"

    # Test basic connectivity
    if command -v nc >/dev/null 2>&1; then
        if timeout 5 nc -z "$minio_host" "$minio_port" >/dev/null 2>&1; then
            log_success "Connessione MinIO OK"

            # Try to create bucket and user if connection works
            create_minio_bucket
            create_minio_user
            return 0
        else
            log_error "Connessione MinIO fallita a $minio_endpoint"
            return 1
        fi
    else
        log_warn "nc non disponibile, impossibile testare MinIO"
        return 0
    fi
}

create_minio_bucket() {
    if [[ "${USE_MINIO:-}" != "y"* ]]; then
        return 0
    fi

    log_info "Creazione bucket MinIO..."

    local bucket_name="${MINIO_BUCKET:-wordpress-media}"
    local minio_endpoint="${MINIO_ENDPOINT:-localhost:9000}"

    # Check if mc (MinIO Client) is available
    if ! command -v mc >/dev/null 2>&1; then
        log_warn "MinIO Client (mc) non disponibile - installazione manuale richiesta"
        log_info "Per installare: wget https://dl.min.io/client/mc/release/linux-amd64/mc && chmod +x mc && sudo mv mc /usr/local/bin/"
        return 1
    fi

    # Configure MinIO client
    if mc alias set myminio "http://$minio_endpoint" "$MINIO_ACCESS_KEY" "$MINIO_SECRET_KEY" >/dev/null 2>&1; then
        log_success "MinIO client configurato"

        # Create bucket if it doesn't exist
        if mc ls "myminio/$bucket_name" >/dev/null 2>&1; then
            log_info "Bucket $bucket_name già esistente"
        else
            if mc mb "myminio/$bucket_name" >/dev/null 2>&1; then
                log_success "Bucket $bucket_name creato"
            else
                log_error "Errore creazione bucket $bucket_name"
                return 1
            fi
        fi

        # Set bucket policy for public read
        create_minio_policy "$bucket_name"
    else
        log_error "Errore configurazione MinIO client"
        return 1
    fi
}

create_minio_policy() {
    local bucket_name="${1:-wordpress-media}"

    log_info "Configurazione policy bucket $bucket_name..."

    # Create policy file
    local policy_file="/tmp/minio-policy-$bucket_name.json"
    cat > "$policy_file" << POLICY_EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "AWS": ["*"]
            },
            "Action": ["s3:GetObject"],
            "Resource": ["arn:aws:s3:::$bucket_name/*"]
        },
        {
            "Effect": "Allow",
            "Principal": {
                "AWS": ["*"]
            },
            "Action": ["s3:ListBucket"],
            "Resource": ["arn:aws:s3:::$bucket_name"]
        }
    ]
}
POLICY_EOF

    # Apply policy
    if mc anonymous set public "myminio/$bucket_name" >/dev/null 2>&1; then
        log_success "Policy pubblica applicata a $bucket_name"
    else
        log_warn "Impossibile applicare policy pubblica a $bucket_name"
    fi

    # Clean up
    rm -f "$policy_file"
}

create_minio_user() {
    if [[ "${USE_MINIO:-}" != "y"* ]]; then
        return 0
    fi

    log_info "Configurazione utente MinIO per WordPress..."

    local wp_user="wordpress-user"
    local wp_user_key="${MINIO_ACCESS_KEY}"
    local wp_user_secret="${MINIO_SECRET_KEY}"

    # Check if user already exists
    if mc admin user list myminio | grep -q "$wp_user" 2>/dev/null; then
        log_info "Utente MinIO $wp_user già esistente"
    else
        # Create user
        if mc admin user add myminio "$wp_user_key" "$wp_user_secret" >/dev/null 2>&1; then
            log_success "Utente MinIO $wp_user creato"

            # Create policy for WordPress bucket access
            local policy_name="wordpress-policy"
            local policy_file="/tmp/$policy_name.json"

            cat > "$policy_file" << WP_POLICY_EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "s3:PutObject",
                "s3:DeleteObject",
                "s3:ListBucket"
            ],
            "Resource": [
                "arn:aws:s3:::${MINIO_BUCKET:-wordpress-media}",
                "arn:aws:s3:::${MINIO_BUCKET:-wordpress-media}/*"
            ]
        }
    ]
}
WP_POLICY_EOF

            # Add policy
            if mc admin policy add myminio "$policy_name" "$policy_file" >/dev/null 2>&1; then
                log_success "Policy $policy_name creata"

                # Attach policy to user
                if mc admin policy set myminio "$policy_name" user="$wp_user_key" >/dev/null 2>&1; then
                    log_success "Policy applicata all'utente WordPress"
                else
                    log_warn "Errore applicazione policy utente"
                fi
            else
                log_warn "Errore creazione policy WordPress"
            fi

            # Clean up
            rm -f "$policy_file"
        else
            log_error "Errore creazione utente MinIO"
            return 1
        fi
    fi
}

configure_minio_wordpress_integration() {
    if [[ "${USE_MINIO:-}" != "y"* ]]; then
        return 0
    fi

    log_step "Configurazione integrazione MinIO-WordPress..."

    # Test connections
    test_minio_connection

    # Configure WordPress to use MinIO
    local wp_dir="/var/www/${DOMAIN}"
    cd "$wp_dir" || return 1

    # Add MinIO configuration to wp-config.php
    local minio_config="
// MinIO S3 Configuration
define('AWS_ACCESS_KEY_ID', '${MINIO_ACCESS_KEY}');
define('AWS_SECRET_ACCESS_KEY', '${MINIO_SECRET_KEY}');
define('AS3CF_SETTINGS', serialize(array(
    'provider' => 'aws',
    'access-key-id' => '${MINIO_ACCESS_KEY}',
    'secret-access-key' => '${MINIO_SECRET_KEY}',
    'bucket' => '${MINIO_BUCKET:-wordpress-media}',
    'region' => 'us-east-1',
    'domain' => 'path',
    'enable-object-prefix' => true,
    'object-prefix' => 'wp-content/uploads/',
    'copy-to-s3' => true,
    'serve-from-s3' => true,
    'remove-local-file' => false,
    'object-versioning' => true
)));
"

    # Add configuration before wp-settings.php
    if grep -q "wp-settings.php" wp-config.php; then
        # Create temporary file with new configuration
        sed "/wp-settings.php/i\\$minio_config" wp-config.php > wp-config-tmp.php
        mv wp-config-tmp.php wp-config.php
        chown www-data:www-data wp-config.php
        chmod 640 wp-config.php
        log_success "Configurazione MinIO aggiunta a wp-config.php"
    else
        log_error "Impossibile trovare wp-settings.php in wp-config.php"
        return 1
    fi

    log_success "Integrazione MinIO-WordPress configurata"
}

# Create management scripts for MinIO
create_minio_management_scripts() {
    if [[ "${USE_MINIO:-}" != "y"* ]]; then
        return 0
    fi

    log_info "Creazione script gestione MinIO..."

    mkdir -p /opt/minio-scripts

    # MinIO backup script
    cat > /opt/minio-scripts/backup-to-minio.sh << 'MINIO_BACKUP_EOF'
#!/bin/bash

# MinIO Backup Script for WordPress
MINIO_ALIAS="myminio"
BUCKET_NAME="wordpress-backups"
WP_PATH="/var/www"
DATE=$(date +%Y%m%d_%H%M%S)

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Create backup bucket if not exists
mc ls "$MINIO_ALIAS/$BUCKET_NAME" >/dev/null 2>&1 || mc mb "$MINIO_ALIAS/$BUCKET_NAME"

for site in "$WP_PATH"/*; do
    if [[ -d "$site" && -f "$site/wp-config.php" ]]; then
        domain=$(basename "$site")
        log "Backup $domain to MinIO..."

        # Database backup
        wp --allow-root --path="$site" db export "/tmp/${domain}_${DATE}.sql" >/dev/null 2>&1

        # Upload database backup
        mc cp "/tmp/${domain}_${DATE}.sql" "$MINIO_ALIAS/$BUCKET_NAME/databases/"
        rm -f "/tmp/${domain}_${DATE}.sql"

        # Files backup (exclude uploads to avoid duplication if already on MinIO)
        tar -czf "/tmp/${domain}_files_${DATE}.tar.gz" \
            --exclude="$site/wp-content/uploads" \
            "$site" >/dev/null 2>&1

        # Upload files backup
        mc cp "/tmp/${domain}_files_${DATE}.tar.gz" "$MINIO_ALIAS/$BUCKET_NAME/files/"
        rm -f "/tmp/${domain}_files_${DATE}.tar.gz"

        log "Backup $domain completato"
    fi
done

# Clean old backups (keep 7 days)
mc find "$MINIO_ALIAS/$BUCKET_NAME" --older-than 7d --exec "mc rm {}"

log "Backup MinIO completato"
MINIO_BACKUP_EOF

    chmod +x /opt/minio-scripts/backup-to-minio.sh

    # MinIO sync script
    cat > /opt/minio-scripts/sync-uploads.sh << 'MINIO_SYNC_EOF'
#!/bin/bash

# MinIO WordPress Uploads Sync Script
MINIO_ALIAS="myminio"
BUCKET_NAME="${MINIO_BUCKET:-wordpress-media}"
WP_PATH="/var/www"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

for site in "$WP_PATH"/*; do
    if [[ -d "$site" && -f "$site/wp-config.php" ]]; then
        domain=$(basename "$site")
        uploads_dir="$site/wp-content/uploads"

        if [[ -d "$uploads_dir" ]]; then
            log "Sync uploads $domain to MinIO..."
            mc mirror "$uploads_dir" "$MINIO_ALIAS/$BUCKET_NAME/$domain/wp-content/uploads" --overwrite
        fi
    fi
done

log "Sync uploads MinIO completato"
MINIO_SYNC_EOF

    chmod +x /opt/minio-scripts/sync-uploads.sh

    # Add to crontab if requested
    log_info "Script MinIO creati in /opt/minio-scripts/"
    log_info "Per automatizzare, aggiungi a crontab:"
    log_info "0 2 * * * /opt/minio-scripts/backup-to-minio.sh"
    log_info "*/30 * * * * /opt/minio-scripts/sync-uploads.sh"
}