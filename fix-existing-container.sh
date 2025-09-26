#!/bin/bash

# =============================================================================
# SCRIPT DI RECUPERO - CONTAINER LXC WORDPRESS ESISTENTI
# Fix per installazioni WordPress incomplete o problematiche
# =============================================================================

set -euo pipefail

# Caricamento librerie esistenti se disponibili
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/lib"

# File di log
LOG_FILE="/tmp/wp-container-fix-$(date +%Y%m%d_%H%M%S).log"

# Colori per output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Funzioni di logging base
log_info() {
    echo -e "${BLUE}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

log_step() {
    echo -e "${BLUE}[STEP]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# =============================================================================
# FUNZIONI PRINCIPALI
# =============================================================================

show_banner() {
    clear
    echo "============================================================="
    echo "🔧 RECOVERY SCRIPT - CONTAINER LXC WORDPRESS ESISTENTI"
    echo "============================================================="
    echo "Questo script risolve problemi comuni in installazioni WordPress"
    echo "incomplete o problematiche nei container LXC Proxmox."
    echo
    echo "🔍 Problemi che risolve:"
    echo "   • Error: Invalid user ID, email or login: 'root'"
    echo "   • Plugin non installati o non attivati"
    echo "   • Configurazione WP-CLI incorretta"
    echo "   • Installazione WordPress incompleta"
    echo
    echo "📁 Log: $LOG_FILE"
    echo "============================================================="
    echo
}

detect_container_environment() {
    log_step "Rilevamento ambiente container..."

    # Verifica se siamo in un container LXC
    if [ -f /.dockerenv ] || [ -f /run/.containerenv ] || grep -q 'container=' /proc/1/environ 2>/dev/null; then
        log_success "Ambiente container rilevato"
    else
        log_warn "Non sembra essere un ambiente container"
    fi

    # Verifica sistema operativo
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        log_info "OS rilevato: $NAME $VERSION"
    fi

    # Verifica se WordPress è installato
    if [ -d "/var/www" ]; then
        log_success "Directory /var/www trovata"

        # Cerca installazioni WordPress
        for wp_dir in /var/www/*/; do
            if [ -f "$wp_dir/wp-config.php" ]; then
                WP_PATH="$wp_dir"
                log_success "WordPress trovato in: $WP_PATH"
                break
            fi
        done
    fi

    # Verifica WP-CLI
    if command -v wp >/dev/null 2>&1; then
        log_success "WP-CLI installato"
        WP_CLI_VERSION=$(wp --version 2>/dev/null || echo "Versione non disponibile")
        log_info "WP-CLI: $WP_CLI_VERSION"
    else
        log_warn "WP-CLI non installato"
    fi
}

fix_wpcli_configuration() {
    log_step "Correzione configurazione WP-CLI..."

    # Backup configurazione esistente
    if [ -f "/root/.wp-cli/config.yml" ]; then
        cp "/root/.wp-cli/config.yml" "/root/.wp-cli/config.yml.backup.$(date +%Y%m%d_%H%M%S)"
        log_info "Backup configurazione WP-CLI creato"
    fi

    # Crea directory se non esiste
    mkdir -p /root/.wp-cli

    # Crea configurazione corretta
    cat > /root/.wp-cli/config.yml << 'EOF'
# WP-CLI configuration for LXC container (FIXED VERSION)
# This configuration allows safe root operation in containerized environments
path: /var/www
apache_modules:
  - mod_rewrite
disabled_commands: []

# Suppress warnings for containerized environments
quiet: false
color: true
EOF

    # Configura variabili d'ambiente
    if ! grep -q "WP_CLI_CONFIG_PATH" /root/.bashrc 2>/dev/null; then
        echo 'export WP_CLI_CONFIG_PATH="/root/.wp-cli/config.yml"' >> /root/.bashrc
        echo 'export WP_CLI_ALLOW_ROOT=1' >> /root/.bashrc
        echo 'alias wp="/usr/local/bin/wp --allow-root"' >> /root/.bashrc
    fi

    # Applica immediatamente
    export WP_CLI_CONFIG_PATH="/root/.wp-cli/config.yml"
    export WP_CLI_ALLOW_ROOT=1

    log_success "Configurazione WP-CLI corretta"
}

install_missing_wpcli() {
    log_step "Installazione/Aggiornamento WP-CLI..."

    local wpcli_phar="/tmp/wp-cli.phar"

    # Remove existing file if present
    rm -f "$wpcli_phar"

    # Download WP-CLI
    if curl -L -o "$wpcli_phar" "https://github.com/wp-cli/wp-cli/releases/download/v2.8.1/wp-cli-2.8.1.phar"; then
        log_info "WP-CLI scaricato"
    elif wget -O "$wpcli_phar" "https://github.com/wp-cli/wp-cli/releases/download/v2.8.1/wp-cli-2.8.1.phar"; then
        log_info "WP-CLI scaricato (fallback wget)"
    else
        log_error "Impossibile scaricare WP-CLI"
        return 1
    fi

    # Verifica e installa
    if [ -f "$wpcli_phar" ] && [ -s "$wpcli_phar" ]; then
        chmod +x "$wpcli_phar"
        mv "$wpcli_phar" /usr/local/bin/wp
        log_success "WP-CLI installato/aggiornato"
    else
        log_error "File WP-CLI non valido"
        return 1
    fi
}

detect_wordpress_details() {
    log_step "Rilevamento dettagli WordPress..."

    if [ -z "${WP_PATH:-}" ]; then
        log_error "WordPress non trovato"
        return 1
    fi

    cd "$WP_PATH"

    # Ottieni URL del sito
    WP_URL=$(wp --allow-root option get home 2>/dev/null || echo "")
    if [ -n "$WP_URL" ]; then
        log_success "URL WordPress: $WP_URL"
    fi

    # Ottieni utente admin
    WP_ADMIN_USER=$(wp --allow-root user list --role=administrator --field=user_login --format=csv 2>/dev/null | head -1 || echo "")
    if [ -n "$WP_ADMIN_USER" ]; then
        log_success "Utente admin: $WP_ADMIN_USER"
    else
        log_warn "Nessun utente admin trovato"
    fi

    # Verifica database
    if wp --allow-root db check 2>/dev/null; then
        log_success "Database WordPress OK"
    else
        log_warn "Problemi con database WordPress"
    fi
}

fix_plugin_installation() {
    log_step "Riparazione installazione plugin..."

    if [ -z "${WP_PATH:-}" ]; then
        log_error "WordPress non trovato"
        return 1
    fi

    cd "$WP_PATH"

    # Lista plugin essenziali con nomi corretti
    local plugins=(
        "wordfence"
        "wp-optimize"
        "updraftplus"
        "limit-login-attempts-reloaded"
        "ssl-insecure-content-fixer"
        "wordpress-seo"
        "wp-super-cache"
        "autoptimize"
        "wp-smushit"
        "broken-link-checker"
        "google-analytics-dashboard-for-wp"
        "cookie-law-info"
    )

    log_info "Installazione/Riparazione plugin essenziali..."

    for plugin in "${plugins[@]}"; do
        # Controlla se il plugin è già installato
        if wp --allow-root plugin is-installed "$plugin" 2>/dev/null; then
            # Se installato ma non attivo, attivalo
            if ! wp --allow-root plugin is-active "$plugin" 2>/dev/null; then
                if wp --allow-root plugin activate "$plugin" --quiet 2>/dev/null; then
                    log_success "Plugin attivato: $plugin"
                else
                    log_warn "Errore attivazione plugin: $plugin"
                fi
            else
                log_info "Plugin già attivo: $plugin"
            fi
        else
            # Installa il plugin con retry e fallback
            local installed=false
            local attempts=3

            # Tentativo installazione principale
            for ((i=1; i<=attempts; i++)); do
                if wp --allow-root plugin install "$plugin" --quiet 2>/dev/null; then
                    if wp --allow-root plugin activate "$plugin" --quiet 2>/dev/null; then
                        log_success "Plugin installato e attivato: $plugin"
                        installed=true
                        break
                    else
                        log_warn "Plugin installato ma non attivato: $plugin"
                        installed=true
                        break
                    fi
                fi

                if [ $i -lt $attempts ]; then
                    log_info "Retry $i/$attempts per $plugin..."
                    sleep 2
                fi
            done

            # Fallback per plugin con nomi alternativi
            if [ "$installed" = false ]; then
                case "$plugin" in
                    "wp-smushit")
                        log_info "Tentativo fallback: smush"
                        if wp --allow-root plugin install "smush" --activate --quiet 2>/dev/null; then
                            log_success "Plugin fallback installato: smush"
                        elif wp --allow-root plugin install "shortpixel-image-optimiser" --activate --quiet 2>/dev/null; then
                            log_success "Plugin alternativo installato: shortpixel-image-optimiser"
                        else
                            log_warn "Errore installazione plugin: $plugin (e fallback)"
                        fi
                        ;;
                    *)
                        log_warn "Errore installazione plugin: $plugin"
                        ;;
                esac
            fi
        fi
    done
}

run_wordpress_optimization() {
    log_step "Ottimizzazioni WordPress..."

    if [ -z "${WP_PATH:-}" ]; then
        log_error "WordPress non trovato"
        return 1
    fi

    cd "$WP_PATH"

    # Flush rewrite rules
    wp --allow-root rewrite flush --quiet 2>/dev/null || true

    # Update permalink structure
    wp --allow-root rewrite structure '/%postname%/' --quiet 2>/dev/null || true

    # Flush cache
    wp --allow-root cache flush --quiet 2>/dev/null || true

    # Update database
    wp --allow-root core update-db --quiet 2>/dev/null || true

    # Fix file permissions with better error handling
    log_info "Correzione permessi file WordPress..."

    # Ensure www-data user exists
    if ! id www-data >/dev/null 2>&1; then
        useradd -r -s /bin/bash www-data 2>/dev/null || true
        log_info "Utente www-data creato"
    fi

    # Fix ownership with fallback
    if ! chown -R www-data:www-data "$WP_PATH" 2>/dev/null; then
        log_warn "Impossibile impostare ownership www-data, provo nginx"
        chown -R nginx:nginx "$WP_PATH" 2>/dev/null || {
            log_warn "Fallback nginx failed, mantengo owner corrente"
        }
    fi

    # Set directory permissions
    if ! find "$WP_PATH" -type d -exec chmod 755 {} \; 2>/dev/null; then
        log_warn "Errore impostazione permessi directory"
    fi

    # Set file permissions
    if ! find "$WP_PATH" -type f -exec chmod 644 {} \; 2>/dev/null; then
        log_warn "Errore impostazione permessi file"
    fi

    # Special permissions for sensitive files
    if [ -f "$WP_PATH/wp-config.php" ]; then
        chmod 640 "$WP_PATH/wp-config.php" 2>/dev/null || {
            log_warn "Errore permessi wp-config.php, uso 644"
            chmod 644 "$WP_PATH/wp-config.php" 2>/dev/null || true
        }
    fi

    # Make uploads writable
    if [ -d "$WP_PATH/wp-content/uploads" ]; then
        chmod 755 "$WP_PATH/wp-content/uploads" 2>/dev/null || true
    fi

    log_success "Permessi file corretti"

    log_success "Ottimizzazioni applicate"
}

show_final_status() {
    log_step "Generazione report finale..."

    echo
    echo "==========================================================="
    echo "🎉 RECOVERY COMPLETATO!"
    echo "==========================================================="
    echo

    if [ -n "${WP_PATH:-}" ]; then
        cd "$WP_PATH"

        echo "📋 STATUS WORDPRESS:"
        wp --allow-root core version 2>/dev/null && echo "✅ WordPress installato" || echo "❌ Problemi WordPress"

        echo
        echo "🔌 PLUGIN ATTIVI:"
        wp --allow-root plugin list --status=active --format=table 2>/dev/null || echo "❌ Errore lettura plugin"

        echo
        echo "👤 UTENTI AMMINISTRATORI:"
        wp --allow-root user list --role=administrator --format=table 2>/dev/null || echo "❌ Errore lettura utenti"
    fi

    echo
    echo "🔧 COMANDI UTILI POST-RECOVERY:"
    echo "   • Test WordPress: wp --allow-root core verify-checksums"
    echo "   • Lista plugin: wp --allow-root plugin list"
    echo "   • Stato database: wp --allow-root db check"
    echo "   • Cache flush: wp --allow-root cache flush"
    echo
    echo "📁 Log completo: $LOG_FILE"
    echo "==========================================================="
    echo
}

# =============================================================================
# FUNZIONE PRINCIPALE
# =============================================================================

main() {
    show_banner

    # Controlli preliminari
    if [ "$EUID" -ne 0 ]; then
        log_error "Questo script deve essere eseguito come root"
        exit 1
    fi

    log_info "=== INIZIO RECOVERY CONTAINER LXC WORDPRESS ==="

    # Fasi di recovery
    detect_container_environment

    # Installa/aggiorna WP-CLI se necessario
    if ! command -v wp >/dev/null 2>&1; then
        install_missing_wpcli
    fi

    fix_wpcli_configuration
    detect_wordpress_details
    fix_plugin_installation
    run_wordpress_optimization
    show_final_status

    log_success "🎉 Recovery completato!"
    echo
    echo "🔄 Per applicare le nuove configurazioni, esegui:"
    echo "   source /root/.bashrc"
    echo
}

# =============================================================================
# HELP E PARSING ARGOMENTI
# =============================================================================

show_help() {
    echo "Recovery Script per Container LXC WordPress"
    echo
    echo "Usage: $0 [options]"
    echo
    echo "Options:"
    echo "  -h, --help     Mostra questo help"
    echo "  -v, --verbose  Output verboso"
    echo
    echo "Questo script risolve:"
    echo "  ✅ Error: Invalid user ID, email or login: 'root'"
    echo "  ✅ Plugin non installati/attivati"
    echo "  ✅ Configurazione WP-CLI incorretta"
    echo "  ✅ Installazione WordPress incompleta"
    echo
}

# Parsing argomenti
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -v|--verbose)
            set -x
            shift
            ;;
        *)
            log_error "Opzione non riconosciuta: $1"
            show_help
            exit 1
            ;;
    esac
done

# Esecuzione main se script lanciato direttamente
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi