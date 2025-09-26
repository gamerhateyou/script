#!/bin/bash

# =============================================================================
# WORDPRESS INSTALLATION ORCHESTRATOR
# Version 2025.09 - Refactored Modular
# =============================================================================

set -euo pipefail

# Source all modular components
SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
WP_LIB_DIR="$SCRIPT_DIR/wordpress"

# shellcheck source=./utils.sh
source "$SCRIPT_DIR/utils.sh"

# WordPress specific modules
# shellcheck source=./wordpress/utils.sh
source "$WP_LIB_DIR/utils.sh"
# shellcheck source=./wordpress/validation.sh
source "$WP_LIB_DIR/validation.sh"
# shellcheck source=./wordpress/config.sh
source "$WP_LIB_DIR/config.sh"
# shellcheck source=./wordpress/system.sh
source "$WP_LIB_DIR/system.sh"
# shellcheck source=./wordpress/core.sh
source "$WP_LIB_DIR/core.sh"
# shellcheck source=./wordpress/plugins.sh
source "$WP_LIB_DIR/plugins.sh"
# shellcheck source=./wordpress/security.sh
source "$WP_LIB_DIR/security.sh"
# shellcheck source=./wordpress/prerequisites.sh
source "$WP_LIB_DIR/prerequisites.sh"
# shellcheck source=./wordpress/themes.sh
source "$WP_LIB_DIR/themes.sh"
# shellcheck source=./wordpress/minio.sh
source "$WP_LIB_DIR/minio.sh"

# =============================================================================
# MAIN WORDPRESS INSTALLATION ORCHESTRATOR
# =============================================================================

main() {
    log_step "🚀 Avvio installazione WordPress modulare con error handling avanzato..."

    # Setup comprehensive error handling
    setup_error_handling

    # Initialize main progress tracking
    init_progress 15 "Installazione WordPress"

    # Phase 1: Prerequisites validation
    update_progress "Validazione prerequisiti sistema"
    if ! validate_system_prerequisites; then
        log_error "❌ Prerequisiti non soddisfatti - installazione interrotta"
        exit 1
    fi

    # Phase 2: Configuration collection and validation
    update_progress "Configurazione parametri"
    configure_params

    update_progress "Validazione configurazione"
    if ! validate_configuration; then
        log_error "❌ Configurazione non valida - installazione interrotta"
        exit 1
    fi

    # Phase 3: Database connectivity test
    update_progress "Test connessione database"
    if ! test_database_connection_with_retry "$DB_HOST" "$DB_USER" "$DB_PASS" "$DB_NAME"; then
        log_error "❌ Connessione database fallita - verificare credenziali"
        exit 1
    fi

    # Phase 4: System preparation with error handling
    update_progress "Preparazione sistema"
    execute_with_error_handling "update_system" "Aggiornamento sistema" 2 5 false
    execute_with_error_handling "install_php" "Installazione PHP" 2 5 false
    execute_with_error_handling "configure_php" "Configurazione PHP" 1 0 false
    execute_with_error_handling "install_nginx" "Installazione Nginx" 2 5 false
    execute_with_error_handling "configure_nginx_global" "Configurazione Nginx" 1 0 false

    # Phase 5: WordPress core installation
    update_progress "Installazione WordPress core"
    execute_with_error_handling "install_wpcli" "Installazione WP-CLI" 3 5 false

    # Configure WP-CLI for LXC if needed
    if [[ -f /proc/1/cgroup ]] && grep -q lxc /proc/1/cgroup; then
        execute_with_error_handling "configure_wpcli_for_lxc" "Configurazione WP-CLI per LXC" 1 0 true
    fi

    execute_with_error_handling "install_wordpress" "Installazione WordPress" 2 10 false

    # Phase 6: Site configuration
    update_progress "Configurazione sito web"
    if [ "$NPM_MODE" != true ]; then
        execute_with_error_handling "configure_nginx_site \"$DOMAIN\"" "Configurazione sito Nginx" 1 0 false
    fi

    # Phase 7: Plugin installation with enhanced error handling
    update_progress "Installazione plugin essenziali"
    execute_with_error_handling "install_essential_plugins" "Installazione plugin" 1 0 true

    update_progress "Configurazione plugin"
    execute_with_error_handling "configure_essential_plugins" "Configurazione plugin" 1 0 true

    # Configure additional plugins and features
    if [[ "${USE_SCHEMA:-}" == "y"* ]]; then
        execute_with_error_handling "configure_schema_plugin" "Configurazione Schema" 1 0 true
    fi

    if [[ "${USE_GA:-}" == "y"* ]]; then
        execute_with_error_handling "configure_google_analytics" "Configurazione Analytics" 1 0 true
    fi

    if [[ "${USE_AMP:-}" == "y"* ]]; then
        execute_with_error_handling "configure_amp_plugin" "Configurazione AMP" 1 0 true
    fi

    # Phase 8: Theme and SEO
    update_progress "Configurazione tema e SEO"
    execute_with_error_handling "install_optimized_theme" "Installazione tema ottimizzato" 1 0 true
    execute_with_error_handling "configure_seo_basics" "Configurazione SEO base" 1 0 true
    execute_with_error_handling "configure_yoast_seo" "Configurazione Yoast SEO" 1 0 true

    # Phase 9: Security hardening
    update_progress "Configurazione sicurezza"
    execute_with_error_handling "configure_security" "Configurazione sicurezza WordPress" 1 0 false
    execute_with_error_handling "set_wordpress_permissions" "Impostazione permessi" 1 0 false

    if [ "$NPM_MODE" != true ]; then
        execute_with_error_handling "setup_ssl_certificates" "Configurazione SSL" 2 10 true
    fi

    execute_with_error_handling "configure_firewall" "Configurazione firewall" 1 0 true

    # Phase 10: GDPR/Privacy if requested
    if [[ "${CONFIGURE_GDPR:-}" == "y"* ]]; then
        update_progress "Configurazione GDPR/Privacy"
        execute_with_error_handling "configure_gdpr_with_prompt" "Configurazione GDPR" 1 0 true
    fi

    # Phase 11: MinIO integration if configured
    if [[ "${USE_MINIO:-}" == "y"* ]]; then
        update_progress "Configurazione MinIO S3"
        execute_with_error_handling "configure_minio_wordpress_integration" "Integrazione MinIO" 1 0 true
        execute_with_error_handling "create_minio_management_scripts" "Script gestione MinIO" 1 0 true
    fi

    # Phase 12: Redis testing if configured
    if [[ "${USE_REDIS:-}" == "y"* ]]; then
        execute_with_error_handling "test_redis_connection" "Test connessione Redis" 1 0 true
    fi

    # Phase 13: Maintenance and monitoring setup
    update_progress "Configurazione manutenzione"
    execute_with_error_handling "setup_maintenance_jobs" "Setup job manutenzione" 1 0 true
    execute_with_error_handling "create_backup_scripts" "Creazione script backup" 1 0 true
    execute_with_error_handling "create_management_scripts" "Creazione script gestione" 1 0 true
    execute_with_error_handling "create_health_check_endpoint" "Creazione health check" 1 0 true

    # Phase 14: Final optimizations
    update_progress "Ottimizzazioni finali"
    execute_with_error_handling "optimize_theme_settings" "Ottimizzazione tema" 1 0 true

    # Phase 15: Final validation and summary
    update_progress "Validazione finale installazione"
    if validate_wordpress_config "/var/www/$DOMAIN/wp-config.php"; then
        log_success "✅ Validazione WordPress completata"
    else
        log_warn "⚠️ Alcuni controlli finali falliti - controllare manualmente"
    fi

    update_progress "Installazione completata"
    show_installation_summary

    log_success "✨ Installazione WordPress completata con successo!"
    log_info "🌐 Il tuo sito è disponibile all'indirizzo: $([ "$NPM_MODE" = true ] && [ "$NPM_SSL" = true ] && echo "https://$DOMAIN" || echo "http://$DOMAIN")"
}

# Execute main if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi