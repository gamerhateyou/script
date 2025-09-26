#!/bin/bash

# =============================================================================
# WORDPRESS CONFIGURATION FUNCTIONS
# =============================================================================

# shellcheck source=./utils.sh
source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"
# shellcheck source=./validation.sh
source "$(dirname "${BASH_SOURCE[0]}")/validation.sh"

configure_params() {
    log_step "Configurazione parametri WordPress..."

    # Setup error handling for configuration
    setup_error_handling

    # Initialize progress tracking
    init_progress 12 "Configurazione WordPress"

    clear_validation_results

    echo "=== CONFIGURAZIONE WORDPRESS ==="

    # Site information
    update_progress "Raccolta informazioni sito"
    while true; do
        read -p "Nome del sito: " SITE_NAME
        if [[ -n "$SITE_NAME" && ${#SITE_NAME} -le 100 ]]; then
            break
        else
            if [[ -z "$SITE_NAME" ]]; then
                log_error "Il nome del sito non può essere vuoto"
            else
                log_error "Il nome del sito è troppo lungo (max 100 caratteri)"
            fi
        fi
    done

    while true; do
        read -p "Dominio (es: example.com): " DOMAIN
        if validate_domain "$DOMAIN" "Dominio sito"; then
            break
        fi
    done

    while true; do
        read -p "Email amministratore: " WP_ADMIN_EMAIL
        if validate_email "$WP_ADMIN_EMAIL" "Email amministratore"; then
            break
        fi
    done

    # Database configuration
    update_progress "Configurazione database"
    echo -e "\n=== CONFIGURAZIONE DATABASE ==="
    while true; do
        read -p "Nome database: " DB_NAME
        if [[ -n "$DB_NAME" && ${#DB_NAME} -le 64 && $DB_NAME =~ ^[a-zA-Z0-9_]+$ ]]; then
            break
        else
            if [[ -z "$DB_NAME" ]]; then
                log_error "Il nome del database non può essere vuoto"
            elif [[ ${#DB_NAME} -gt 64 ]]; then
                log_error "Nome database troppo lungo (max 64 caratteri)"
            else
                log_error "Nome database non valido (solo lettere, numeri e underscore)"
            fi
        fi
    done

    while true; do
        read -p "Utente database: " DB_USER
        if [[ -n "$DB_USER" && ${#DB_USER} -le 32 && $DB_USER =~ ^[a-zA-Z0-9_]+$ ]]; then
            break
        else
            if [[ -z "$DB_USER" ]]; then
                log_error "L'utente del database non può essere vuoto"
            elif [[ ${#DB_USER} -gt 32 ]]; then
                log_error "Nome utente database troppo lungo (max 32 caratteri)"
            else
                log_error "Nome utente database non valido (solo lettere, numeri e underscore)"
            fi
        fi
    done

    while true; do
        read -s -p "Password database: " DB_PASS
        echo
        if validate_password_strength "$DB_PASS" 8 "Password database"; then
            break
        fi
    done

    read -p "Host database [localhost]: " DB_HOST
    DB_HOST=${DB_HOST:-localhost}

    # Validate database host
    if [[ "$DB_HOST" != "localhost" && "$DB_HOST" != "127.0.0.1" ]]; then
        if ! validate_domain "$DB_HOST" "Host database" && ! validate_ip "$DB_HOST" "Host database"; then
            log_error "Host database non valido"
            return 1
        fi
    fi

    # WordPress admin configuration
    update_progress "Configurazione amministratore WordPress"
    echo -e "\n=== CONFIGURAZIONE AMMINISTRATORE WORDPRESS ==="
    while true; do
        read -p "Username admin [admin]: " WP_ADMIN_USER
        WP_ADMIN_USER=${WP_ADMIN_USER:-admin}

        if [[ ${#WP_ADMIN_USER} -ge 3 && ${#WP_ADMIN_USER} -le 60 && $WP_ADMIN_USER =~ ^[a-zA-Z0-9_-]+$ ]]; then
            break
        else
            log_error "Username admin non valido (3-60 caratteri, solo lettere, numeri, - e _)"
        fi
    done

    while true; do
        read -s -p "Password admin WordPress: " WP_ADMIN_PASS
        echo
        if validate_password_strength "$WP_ADMIN_PASS" 12 "Password amministratore"; then
            break
        fi
    done

    # Optional services
    echo -e "\n=== SERVIZI OPZIONALI ==="
    read -p "Utilizzare Redis per cache? [y/N]: " USE_REDIS
    read -p "Utilizzare MinIO S3? [y/N]: " USE_MINIO
    read -p "Configurare SMTP? [y/N]: " USE_SMTP
    read -p "Modalità NPM (Nginx Proxy Manager)? [y/N]: " NPM_MODE

    # NPM specific configuration
    if [[ "$NPM_MODE" =~ ^[Yy] ]]; then
        NPM_MODE=true
        read -p "NPM con SSL? [Y/n]: " NPM_SSL
        NPM_SSL=${NPM_SSL:-Y}
        [[ "$NPM_SSL" =~ ^[Yy] ]] && NPM_SSL=true || NPM_SSL=false
    else
        NPM_MODE=false
    fi

    # MinIO configuration
    if [[ "$USE_MINIO" =~ ^[Yy] ]]; then
        echo -e "\n=== CONFIGURAZIONE MINIO ==="
        read -p "MinIO Access Key: " MINIO_ACCESS_KEY
        read -s -p "MinIO Secret Key: " MINIO_SECRET_KEY
        echo
        read -p "MinIO Bucket [wordpress-media]: " MINIO_BUCKET
        MINIO_BUCKET=${MINIO_BUCKET:-wordpress-media}
        read -p "MinIO Endpoint [localhost:9000]: " MINIO_ENDPOINT
        MINIO_ENDPOINT=${MINIO_ENDPOINT:-localhost:9000}
    fi

    # SMTP configuration
    if [[ "$USE_SMTP" =~ ^[Yy] ]]; then
        echo -e "\n=== CONFIGURAZIONE SMTP ==="
        read -p "SMTP Host: " SMTP_HOST
        read -p "SMTP Port [587]: " SMTP_PORT
        SMTP_PORT=${SMTP_PORT:-587}
        read -p "SMTP User: " SMTP_USER
        read -s -p "SMTP Password: " SMTP_PASS
        echo
        read -p "SMTP Encryption [tls]: " SMTP_ENCRYPTION
        SMTP_ENCRYPTION=${SMTP_ENCRYPTION:-tls}
        read -p "From Email [noreply@$DOMAIN]: " SMTP_FROM_EMAIL
        SMTP_FROM_EMAIL=${SMTP_FROM_EMAIL:-noreply@$DOMAIN}
    fi

    # Export all variables
    export SITE_NAME DOMAIN WP_ADMIN_EMAIL
    export DB_NAME DB_USER DB_PASS DB_HOST
    export WP_ADMIN_USER WP_ADMIN_PASS
    export USE_REDIS USE_MINIO USE_SMTP NPM_MODE NPM_SSL
    export MINIO_ACCESS_KEY MINIO_SECRET_KEY MINIO_BUCKET MINIO_ENDPOINT
    export SMTP_HOST SMTP_PORT SMTP_USER SMTP_PASS SMTP_ENCRYPTION SMTP_FROM_EMAIL

    log_success "Configurazione completata"
}

show_installation_summary() {
    log_step "Riepilogo installazione"

    cat << SUMMARY_EOF

==========================================================
           🚀 WORDPRESS INSTALLAZIONE COMPLETATA 🚀
==========================================================

📋 INFORMAZIONI SITO:
   • Nome: $SITE_NAME
   • Dominio: $DOMAIN
   • URL: $([ "$NPM_MODE" = true ] && [ "$NPM_SSL" = true ] && echo "https://$DOMAIN" || echo "http://$DOMAIN")

🔐 ACCESSO AMMINISTRATORE:
   • URL Admin: $([ "$NPM_MODE" = true ] && [ "$NPM_SSL" = true ] && echo "https://$DOMAIN/wp-admin" || echo "http://$DOMAIN/wp-admin")
   • Username: $WP_ADMIN_USER
   • Email: $WP_ADMIN_EMAIL

💾 DATABASE:
   • Nome: $DB_NAME
   • Host: $DB_HOST
   • Utente: $DB_USER

🔧 SERVIZI CONFIGURATI:
   • Redis Cache: $([ "$USE_REDIS" = "y"* ] && echo "✅ Attivo" || echo "❌ Disattivo")
   • MinIO S3: $([ "$USE_MINIO" = "y"* ] && echo "✅ Attivo" || echo "❌ Disattivo")
   • SMTP: $([ "$USE_SMTP" = "y"* ] && echo "✅ Attivo" || echo "❌ Disattivo")
   • NPM Mode: $([ "$NPM_MODE" = true ] && echo "✅ Attivo" || echo "❌ Disattivo")

📊 HEALTH CHECK:
   • Endpoint: $([ "$NPM_MODE" = true ] && [ "$NPM_SSL" = true ] && echo "https://$DOMAIN/health.php" || echo "http://$DOMAIN/health.php")

📁 PERCORSI IMPORTANTI:
   • Root WordPress: /var/www/$DOMAIN
   • Configurazione Nginx: /etc/nginx/sites-available/$DOMAIN
   • Log Nginx: /var/log/nginx/
   • Log PHP: /var/log/php_errors.log

==========================================================
          ✨ Installazione completata con successo! ✨
==========================================================

SUMMARY_EOF

    log_success "WordPress pronto all'uso!"
}