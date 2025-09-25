#!/bin/bash

# =============================================================================
# SCRIPT PRINCIPALE - CREAZIONE CONTAINER LXC WORDPRESS SU PROXMOX VE
# Versione Modulare 2025.09
# =============================================================================

set -euo pipefail

# =============================================================================
# CONFIGURAZIONE SCRIPT
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/lib"
CONFIG_DIR="${SCRIPT_DIR}/config"

# File di log
LOG_FILE="/tmp/wp-container-$(date +%Y%m%d_%H%M%S).log"
export LOG_FILE

# =============================================================================
# CARICAMENTO MODULI
# =============================================================================

# Load utilities
if [[ -f "${LIB_DIR}/utils.sh" ]]; then
    # shellcheck source=lib/utils.sh
    source "${LIB_DIR}/utils.sh"
else
    echo "ERRORE: File utils.sh non trovato in ${LIB_DIR}"
    exit 1
fi

# Load Proxmox functions
if [[ -f "${LIB_DIR}/proxmox.sh" ]]; then
    # shellcheck source=lib/proxmox.sh
    source "${LIB_DIR}/proxmox.sh"
else
    log_error "File proxmox.sh non trovato in ${LIB_DIR}"
    exit 1
fi

# Load WordPress functions
if [[ -f "${LIB_DIR}/wordpress.sh" ]]; then
    # shellcheck source=lib/wordpress.sh
    source "${LIB_DIR}/wordpress.sh"
else
    log_error "File wordpress.sh non trovato in ${LIB_DIR}"
    exit 1
fi

# Load default configuration
if [[ -f "${CONFIG_DIR}/default.conf" ]]; then
    # shellcheck source=config/default.conf
    source "${CONFIG_DIR}/default.conf"
else
    log_warn "File configurazione default non trovato, uso valori predefiniti"
fi

# =============================================================================
# FUNZIONI CONFIGURAZIONE CONTAINER
# =============================================================================

configure_container_params() {
    log_step "Configurazione parametri container..."

    echo "============================================================="
    echo "🚀 CREAZIONE CONTAINER LXC WORDPRESS SU PROXMOX VE"
    echo "============================================================="
    echo "Versione: 2025.09 - Script Modulare"
    echo "Log: $LOG_FILE"
    echo "============================================================="
    echo
    echo "Inserisci i parametri per il nuovo container:"
    echo

    # Container ID con validazione
    while true; do
        CTID=$(prompt_input "ID Container (100-999999)" "" validate_ctid)
        if validate_ctid "$CTID"; then
            break
        else
            log_error "ID non valido o già esistente: $CTID"
        fi
    done

    # Hostname
    while true; do
        HOSTNAME=$(prompt_input "Hostname container")
        if validate_hostname "$HOSTNAME"; then
            break
        else
            log_error "Hostname non valido: $HOSTNAME"
        fi
    done

    # Password root
    ROOT_PASSWORD=$(prompt_password "Password root")

    # Risorse
    MEMORY=$(prompt_input "Memoria RAM (MB)" "$DEFAULT_MEMORY")
    DISK_SIZE=$(prompt_input "Spazio disco (GB)" "$DEFAULT_DISK_SIZE")
    CORES=$(prompt_input "CPU cores" "$DEFAULT_CORES")

    # Rete
    echo
    echo "Configurazione di rete:"
    BRIDGE=$(prompt_input "Bridge di rete" "$DEFAULT_BRIDGE")

    while true; do
        IP_ADDRESS=$(prompt_input "Indirizzo IP (es: 192.168.1.100/24)")
        if validate_ip "$IP_ADDRESS"; then
            break
        else
            log_error "Indirizzo IP non valido: $IP_ADDRESS"
        fi
    done

    GATEWAY=$(prompt_input "Gateway (es: 192.168.1.1)")
    DNS=$(prompt_input "DNS" "$DEFAULT_DNS")

    # Storage
    echo
    echo "Storage disponibili:"
    list_storages
    echo
    STORAGE=$(prompt_input "Storage per container" "$DEFAULT_STORAGE")

    log_success "Parametri configurati per container $CTID"
}

# =============================================================================
# FUNZIONI CREAZIONE CONTAINER
# =============================================================================

create_lxc_container() {
    log_step "Creazione container LXC..."

    # Verifica e download template
    local template_path="${TEMPLATE_DIR}/${DEFAULT_TEMPLATE_NAME}"

    if ! download_template "$DEFAULT_TEMPLATE_NAME" "$STORAGE"; then
        log_error "Impossibile ottenere il template"
        return 1
    fi

    # Preparazione configurazione container
    local container_config="
hostname=$HOSTNAME
memory=$MEMORY
swap=$((MEMORY / 2))
cores=$CORES
rootfs=$STORAGE:$DISK_SIZE
net0=name=eth0,bridge=$BRIDGE,ip=$IP_ADDRESS,gw=$GATEWAY
nameserver=$DNS
password=$ROOT_PASSWORD
"

    # Creazione container
    if ! create_container "$CTID" "$template_path" "$container_config"; then
        log_error "Errore creazione container"
        return 1
    fi

    log_success "Container $CTID creato con successo"
}

configure_container_system() {
    log_step "Configurazione sistema container..."

    # Avvio container
    if ! start_container "$CTID" 30; then
        log_error "Impossibile avviare il container"
        return 1
    fi

    # Aggiornamento sistema base
    log_info "Aggiornamento sistema nel container..."

    local update_commands="
        export DEBIAN_FRONTEND=noninteractive
        export LC_ALL=C.UTF-8
        export LANG=C.UTF-8
        apt update -y
        apt upgrade -y
        apt install -y curl wget git nano htop net-tools openssh-server bc unzip zip locales
        locale-gen it_IT.UTF-8 en_US.UTF-8
        update-locale LANG=it_IT.UTF-8
        timedatectl set-timezone Europe/Rome
        apt autoremove -y
        apt autoclean
    "

    if ! container_exec "$CTID" "$update_commands"; then
        log_error "Errore configurazione sistema base"
        return 1
    fi

    log_success "Sistema container configurato"
}

install_wordpress_script() {
    log_step "Installazione script WordPress nel container..."

    # Creazione directory script nel container
    container_exec "$CTID" "mkdir -p $SCRIPTS_DIR"

    # Generazione script WordPress
    local temp_wp_script="/tmp/wp-install-${CTID}.sh"

    if ! generate_wordpress_script "$temp_wp_script"; then
        log_error "Errore generazione script WordPress"
        return 1
    fi

    # Push script nel container
    if ! container_push "$CTID" "$temp_wp_script" "${SCRIPTS_DIR}/wp-install.sh" "755"; then
        log_error "Errore trasferimento script WordPress"
        return 1
    fi

    # Cleanup
    rm -f "$temp_wp_script"

    log_success "Script WordPress installato nel container"
}

# =============================================================================
# FUNZIONI TESTING
# =============================================================================

perform_container_tests() {
    log_step "Esecuzione test container..."

    # Test connettività base
    if ! test_container_connectivity "$CTID"; then
        log_warn "Alcuni test di connettività sono falliti"
        return 1
    fi

    log_success "Test container completati"
}

# =============================================================================
# FUNZIONI BACKUP
# =============================================================================

configure_automatic_backup() {
    log_step "Configurazione backup automatico..."

    if [[ "$DEFAULT_BACKUP_ENABLED" == "true" ]]; then
        setup_container_backup "$CTID" "$STORAGE" "$DEFAULT_BACKUP_TIME" "$DEFAULT_BACKUP_RETENTION"
        log_success "Backup automatico configurato"
    else
        log_info "Backup automatico disabilitato per configurazione"
    fi
}

# =============================================================================
# RIEPILOGO FINALE
# =============================================================================

show_final_summary() {
    log_step "Generazione riepilogo finale..."

    echo
    echo "==========================================================="
    echo "🎉 CONTAINER LXC WORDPRESS CREATO CON SUCCESSO!"
    echo "==========================================================="
    echo
    echo "📋 DETTAGLI CONTAINER:"
    echo "   • ID Container: ${CTID}"
    echo "   • Hostname: ${HOSTNAME}"
    echo "   • IP Address: ${IP_ADDRESS}"
    echo "   • RAM: ${MEMORY} MB"
    echo "   • Disk: ${DISK_SIZE} GB su ${STORAGE}"
    echo "   • CPU Cores: ${CORES}"
    echo "   • Bridge: ${BRIDGE}"
    echo "   • DNS: ${DNS}"
    echo
    echo "🔧 SERVIZI CONFIGURATI:"
    echo "   • ✅ Ubuntu 24.04 LTS aggiornato"
    echo "   • ✅ SSH Server attivo"
    echo "   • ✅ Timezone Europe/Rome"
    echo "   • ✅ Tools di base installati"
    echo "   • ✅ Script WordPress modulare"
    if [[ "$DEFAULT_BACKUP_ENABLED" == "true" ]]; then
        echo "   • ✅ Backup automatico programmato"
    fi
    echo
    echo "🚀 PROSSIMI PASSI:"
    echo
    echo "   1. 🔑 ACCEDI AL CONTAINER:"
    echo "      pct enter ${CTID}"
    echo
    echo "   2. 🔧 ESEGUI INSTALLAZIONE WORDPRESS:"
    echo "      cd ${SCRIPTS_DIR}"
    echo "      ./wp-install.sh"
    echo
    echo "   3. ⚙️ DURANTE L'INSTALLAZIONE CONFIGURA:"
    echo "      • Nome del sito e dominio"
    echo "      • IP e credenziali server MySQL esterno"
    echo "      • Credenziali admin WordPress"
    echo "      • IP server Redis (opzionale)"
    echo "      • IP server MinIO (opzionale)"
    echo "      • Configurazione SSL automatica"
    echo
    echo "🔧 COMANDI UTILI PROXMOX:"
    echo "   • Status: pct status ${CTID}"
    echo "   • Start: pct start ${CTID}"
    echo "   • Stop: pct stop ${CTID}"
    echo "   • Console: pct enter ${CTID}"
    echo "   • Config: pct config ${CTID}"
    echo "   • Logs: tail -f ${LOG_FILE}"
    echo
    echo "🌐 ACCESSO REMOTO (dopo installazione WordPress):"
    echo "   • SSH: ssh root@$(echo "$IP_ADDRESS" | cut -d'/' -f1)"
    echo "   • WordPress: http://your-domain.com"
    echo "   • WP Admin: http://your-domain.com/wp-admin"
    echo
    if [[ "$DEFAULT_BACKUP_ENABLED" == "true" ]]; then
        echo "💾 BACKUP:"
        echo "   • Automatico: ${DEFAULT_BACKUP_TIME}"
        echo "   • Retention: ${DEFAULT_BACKUP_RETENTION} giorni"
        echo "   • Storage: ${STORAGE}"
        echo "   • Comando manuale: vzdump ${CTID} --storage ${STORAGE}"
        echo
    fi
    echo "📖 CARATTERISTICHE SCRIPT WORDPRESS MODULARE:"
    echo "   • 🔧 PHP 8.3 con OPcache ottimizzato"
    echo "   • 🚀 Nginx con configurazione performance"
    echo "   • 🗄️ Supporto MySQL esterno + Redis object cache"
    echo "   • 🔒 SSL Let's Encrypt automatico"
    echo "   • 🛡️ Sicurezza: Fail2ban + UFW + Wordfence"
    echo "   • 🔌 Plugin essenziali pre-installati"
    echo "   • ⚡ Manutenzione automatica programmata"
    echo "   • 📊 Script di monitoraggio (wp-status.sh)"
    echo "   • 🛠️ Gestione modulare e manutenibile"
    echo
    echo "📁 STRUTTURA FILE:"
    echo "   • Script principale: ${SCRIPT_DIR}/create-wordpress-container.sh"
    echo "   • Librerie: ${LIB_DIR}/"
    echo "   • Configurazioni: ${CONFIG_DIR}/"
    echo "   • Log installazione: ${LOG_FILE}"
    echo
    echo "🔧 PERSONALIZZAZIONE:"
    echo "   • Modifica config/default.conf per valori predefiniti"
    echo "   • Estendi lib/*.sh per funzionalità aggiuntive"
    echo "   • Crea nuovi profili in config/ per ambienti diversi"
    echo
    echo "==========================================================="
    echo "✅ Container pronto per installazione WordPress!"
    echo "Procedi con: pct enter ${CTID}"
    echo "==========================================================="
    echo
    echo "📝 Per assistenza:"
    echo "   • Log completo: cat ${LOG_FILE}"
    echo "   • Status container: container_status ${CTID}"
    echo "   • Test connettività: test_container_connectivity ${CTID}"
    echo
}

# =============================================================================
# GESTIONE ERRORI E CLEANUP
# =============================================================================

cleanup_on_error() {
    local exit_code=$?

    if [[ $exit_code -ne 0 ]]; then
        log_error "Script terminato con errore (exit code: $exit_code)"

        if [[ -n "${CTID:-}" ]] && [[ "$CTID" != "" ]]; then
            log_warn "Container $CTID potrebbe essere in stato inconsistente"

            if prompt_confirm "Vuoi eseguire il cleanup del container $CTID?"; then
                cleanup_failed_container "$CTID"
            fi
        fi
    fi

    log_info "Log completo disponibile in: $LOG_FILE"
}

setup_script_error_handling() {
    trap cleanup_on_error EXIT
    trap 'log_error "Script interrotto dall utente"; exit 130' INT TERM
}

# =============================================================================
# FUNZIONE PRINCIPALE
# =============================================================================

main() {
    local start_time
    start_time=$(date +%s)

    # Setup error handling
    setup_script_error_handling

    # Log iniziale
    log_info "=== AVVIO CREAZIONE CONTAINER WORDPRESS ==="
    log_info "Versione: 2025.09 - Script Modulare"
    log_info "Data: $(date)"
    log_info "Utente: $(whoami)"
    log_info "Directory: $(pwd)"
    log_info "Log file: $LOG_FILE"

    # Controlli preliminari
    log_step "Esecuzione controlli preliminari..."
    check_proxmox
    check_system_requirements

    # Configurazione parametri
    configure_container_params

    # Validazione storage
    if ! validate_storage "$STORAGE"; then
        log_error "Storage non valido: $STORAGE"
        exit 1
    fi

    # Creazione e configurazione container
    create_lxc_container
    configure_container_system
    install_wordpress_script

    # Test funzionalità
    perform_container_tests

    # Configurazione backup
    configure_automatic_backup

    # Riepilogo finale
    show_final_summary

    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - start_time))

    log_success "🎉 Container LXC creato con successo!"
    log_info "⏱️ Tempo totale: ${duration} secondi"
    log_info "📋 Container ID: ${CTID}"
    log_info "🔑 Prossimo passo: pct enter ${CTID}"
}

# =============================================================================
# VERIFICA ESECUZIONE SCRIPT
# =============================================================================

show_help() {
    echo "Usage: $0 [options]"
    echo
    echo "Options:"
    echo "  -h, --help     Mostra questo help"
    echo "  -d, --debug    Abilita debug mode"
    echo "  -c, --config   Specifica file di configurazione personalizzato"
    echo
    echo "Examples:"
    echo "  $0                                 # Installazione interattiva standard"
    echo "  $0 --debug                        # Installazione con debug abilitato"
    echo "  $0 --config config/production.conf # Usa configurazione personalizzata"
    echo
}

# Parsing argomenti
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -d|--debug)
            export DEBUG=true
            log_info "Debug mode abilitato"
            shift
            ;;
        -c|--config)
            CUSTOM_CONFIG="$2"
            if [[ -f "$CUSTOM_CONFIG" ]]; then
                # shellcheck source=/dev/null
                source "$CUSTOM_CONFIG"
                log_info "Configurazione personalizzata caricata: $CUSTOM_CONFIG"
            else
                log_error "File configurazione non trovato: $CUSTOM_CONFIG"
                exit 1
            fi
            shift 2
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