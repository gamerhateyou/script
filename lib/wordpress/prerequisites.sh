#!/bin/bash

# =============================================================================
# WORDPRESS PREREQUISITES VALIDATION
# =============================================================================

# shellcheck source=./utils.sh
source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"
# shellcheck source=./validation.sh
source "$(dirname "${BASH_SOURCE[0]}")/validation.sh"

# =============================================================================
# SYSTEM PREREQUISITES VALIDATION
# =============================================================================

validate_system_prerequisites() {
    log_step "🔍 Validazione prerequisiti sistema..."

    setup_error_handling
    clear_validation_results

    init_progress 10 "Validazione prerequisiti"

    # Check if running as root
    update_progress "Controllo privilegi root"
    if [[ $EUID -ne 0 ]]; then
        add_validation_error "Script deve essere eseguito come root (sudo)" $E_PERMISSION_DENIED
    fi

    # System architecture check
    update_progress "Controllo architettura sistema"
    local arch
    arch=$(uname -m)
    case $arch in
        x86_64|amd64)
            log_info "Architettura supportata: $arch"
            ;;
        aarch64|arm64)
            log_info "Architettura supportata: $arch"
            ;;
        *)
            add_validation_warning "Architettura non testata: $arch"
            ;;
    esac

    # Operating system check
    update_progress "Controllo sistema operativo"
    if [[ -f /etc/os-release ]]; then
        local os_id os_version
        os_id=$(grep "^ID=" /etc/os-release | cut -d'=' -f2 | tr -d '"')
        os_version=$(grep "^VERSION_ID=" /etc/os-release | cut -d'=' -f2 | tr -d '"')

        case $os_id in
            ubuntu)
                if [[ $(echo "$os_version >= 20.04" | bc 2>/dev/null || echo 0) -eq 1 ]]; then
                    log_success "Ubuntu $os_version supportata"
                else
                    add_validation_warning "Ubuntu $os_version non testata (consigliato >= 20.04)"
                fi
                ;;
            debian)
                if [[ $(echo "$os_version >= 11" | bc 2>/dev/null || echo 0) -eq 1 ]]; then
                    log_success "Debian $os_version supportata"
                else
                    add_validation_warning "Debian $os_version non testata (consigliato >= 11)"
                fi
                ;;
            *)
                add_validation_warning "Sistema operativo non testato: $os_id $os_version"
                ;;
        esac
    else
        add_validation_error "Sistema operativo non identificabile" 1
    fi

    # Required commands check
    update_progress "Controllo comandi richiesti"
    local required_commands=(
        "curl:per download file"
        "wget:per download alternativi"
        "systemctl:per gestione servizi"
        "apt:per installazione pacchetti"
        "mysql:client database MySQL"
        "openssl:per generazione chiavi"
        "tar:per archivi"
        "gzip:per compressione"
    )

    for cmd_info in "${required_commands[@]}"; do
        local cmd="${cmd_info%%:*}"
        local desc="${cmd_info##*:}"

        if ! command -v "$cmd" >/dev/null 2>&1; then
            add_validation_error "Comando richiesto non trovato: $cmd ($desc)" $E_MISSING_DEPENDENCY
        fi
    done

    # System resources validation
    update_progress "Controllo risorse sistema"
    validate_disk_space 3000 "/" "Spazio disco root"
    validate_disk_space 1000 "/var" "Spazio disco /var"
    validate_disk_space 500 "/tmp" "Spazio disco /tmp"
    validate_memory 1024 "Memoria RAM"

    # Network connectivity check
    update_progress "Controllo connettività rete"
    validate_network_connectivity "archive.ubuntu.com" 80
    validate_network_connectivity "wordpress.org" 443
    validate_network_connectivity "downloads.wordpress.org" 443

    # Port availability check
    update_progress "Controllo porte disponibili"
    local required_ports=(80 443)
    for port in "${required_ports[@]}"; do
        if command -v ss >/dev/null 2>&1; then
            if ss -tlnp | grep -q ":$port "; then
                add_validation_warning "Porta $port già in uso"
            fi
        elif command -v netstat >/dev/null 2>&1; then
            if netstat -tlnp | grep -q ":$port "; then
                add_validation_warning "Porta $port già in uso"
            fi
        fi
    done

    # Database connectivity check (if parameters provided)
    update_progress "Controllo connessione database"
    if [[ -n "${DB_HOST:-}" && -n "${DB_USER:-}" && -n "${DB_PASS:-}" && -n "${DB_NAME:-}" ]]; then
        if ! test_database_connection_with_retry "$DB_HOST" "$DB_USER" "$DB_PASS" "$DB_NAME"; then
            add_validation_error "Impossibile connettersi al database $DB_NAME su $DB_HOST" $E_NETWORK_ERROR
        fi
    else
        log_info "Parametri database non forniti, salto test connessione"
    fi

    # Check for potential conflicts
    update_progress "Controllo conflitti software"
    check_software_conflicts

    # Security check
    update_progress "Controllo sicurezza sistema"
    check_security_requirements

    update_progress "Validazione completata"

    show_validation_summary "Prerequisiti Sistema"

    if has_validation_errors; then
        log_error "❌ Prerequisiti non soddisfatti - impossibile continuare"
        return 1
    fi

    if has_validation_warnings; then
        log_warn "⚠️ Trovati avvertimenti - si consiglia di risolverli"
        echo
        read -p "Continuare comunque? [y/N]: " continue_anyway
        if [[ ! "$continue_anyway" =~ ^[Yy] ]]; then
            log_info "Installazione annullata dall'utente"
            return 1
        fi
    fi

    log_success "✅ Tutti i prerequisiti sono soddisfatti"
    return 0
}

check_software_conflicts() {
    log_info "Controllo conflitti software..."

    # Check for existing web servers
    local web_servers=("apache2" "httpd" "lighttpd")
    for server in "${web_servers[@]}"; do
        if systemctl is-active --quiet "$server" 2>/dev/null; then
            add_validation_warning "Server web $server già attivo - possibili conflitti con Nginx"
        fi
    done

    # Check for existing PHP installations
    if command -v php >/dev/null 2>&1; then
        local current_php_version
        current_php_version=$(php -r "echo PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION;")
        if [[ "$current_php_version" != "${PHP_VERSION}" ]]; then
            add_validation_warning "PHP $current_php_version già installato, si installerà PHP $PHP_VERSION"
        fi
    fi

    # Check for existing MySQL/MariaDB
    local db_services=("mysql" "mariadb" "mysqld")
    for service in "${db_services[@]}"; do
        if systemctl is-active --quiet "$service" 2>/dev/null; then
            log_info "Servizio database $service attivo"
            break
        fi
    done

    # Check for Docker/containerization
    if command -v docker >/dev/null 2>&1 && systemctl is-active --quiet docker 2>/dev/null; then
        add_validation_warning "Docker attivo - verificare potenziali conflitti di rete"
    fi
}

check_security_requirements() {
    log_info "Controllo requisiti sicurezza..."

    # Check firewall status
    if command -v ufw >/dev/null 2>&1; then
        if ufw status | grep -q "Status: active"; then
            log_info "UFW firewall attivo"

            # Check if required ports are allowed
            local required_ports=(22 80 443)
            for port in "${required_ports[@]}"; do
                if ! ufw status | grep -q "$port"; then
                    add_validation_warning "Porta $port non configurata nel firewall"
                fi
            done
        else
            add_validation_warning "UFW firewall non attivo"
        fi
    elif command -v iptables >/dev/null 2>&1; then
        local rules_count
        rules_count=$(iptables -L | wc -l)
        if [[ $rules_count -gt 10 ]]; then
            add_validation_warning "Regole iptables personalizzate rilevate - verificare compatibilità"
        fi
    fi

    # Check SELinux/AppArmor
    if command -v getenforce >/dev/null 2>&1; then
        local selinux_status
        selinux_status=$(getenforce 2>/dev/null || echo "Disabled")
        if [[ "$selinux_status" != "Disabled" ]]; then
            add_validation_warning "SELinux attivo ($selinux_status) - possibili restrizioni"
        fi
    fi

    if command -v aa-status >/dev/null 2>&1; then
        if aa-status --enabled >/dev/null 2>&1; then
            add_validation_warning "AppArmor attivo - possibili restrizioni"
        fi
    fi

    # Check system updates
    if command -v apt >/dev/null 2>&1; then
        local updates_available
        apt list --upgradable 2>/dev/null | grep -c upgradable || true
        if [[ $updates_available -gt 20 ]]; then
            add_validation_warning "Molti aggiornamenti sistema disponibili ($updates_available)"
        fi
    fi

    # Check SSH configuration
    if [[ -f /etc/ssh/sshd_config ]]; then
        if grep -q "PermitRootLogin yes" /etc/ssh/sshd_config; then
            add_validation_warning "SSH root login abilitato - rischio sicurezza"
        fi

        if ! grep -q "Protocol 2" /etc/ssh/sshd_config && ! grep -q "Protocol.*2" /etc/ssh/sshd_config; then
            add_validation_warning "SSH potrebbe usare protocollo non sicuro"
        fi
    fi
}

# =============================================================================
# CONFIGURATION VALIDATION
# =============================================================================

validate_configuration() {
    log_step "🔧 Validazione configurazione WordPress..."

    clear_validation_results

    # Validate all required variables are set
    local required_vars=(
        "SITE_NAME:Nome del sito"
        "DOMAIN:Dominio"
        "WP_ADMIN_EMAIL:Email amministratore"
        "DB_NAME:Nome database"
        "DB_USER:Utente database"
        "DB_PASS:Password database"
        "DB_HOST:Host database"
        "WP_ADMIN_USER:Username amministratore"
        "WP_ADMIN_PASS:Password amministratore"
    )

    for var_info in "${required_vars[@]}"; do
        local var_name="${var_info%%:*}"
        local var_desc="${var_info##*:}"

        if [[ -z "${!var_name:-}" ]]; then
            add_validation_error "$var_desc non configurato ($var_name)" 1
        fi
    done

    # Re-validate all inputs with enhanced checks
    if [[ -n "${DOMAIN:-}" ]]; then
        validate_domain "$DOMAIN" "Dominio"
    fi

    if [[ -n "${WP_ADMIN_EMAIL:-}" ]]; then
        validate_email "$WP_ADMIN_EMAIL" "Email amministratore"
    fi

    if [[ -n "${WP_ADMIN_PASS:-}" ]]; then
        validate_password_strength "$WP_ADMIN_PASS" 12 "Password amministratore"
    fi

    if [[ -n "${DB_PASS:-}" ]]; then
        validate_password_strength "$DB_PASS" 8 "Password database"
    fi

    # Validate optional service configurations
    if [[ "${USE_SMTP:-}" =~ ^[Yy] ]]; then
        validate_smtp_config
    fi

    if [[ "${USE_MINIO:-}" =~ ^[Yy] ]]; then
        validate_minio_config
    fi

    show_validation_summary "Configurazione WordPress"

    if has_validation_errors; then
        log_error "❌ Configurazione non valida"
        return 1
    fi

    log_success "✅ Configurazione validata"
    return 0
}

validate_smtp_config() {
    if [[ -n "${SMTP_HOST:-}" ]]; then
        validate_domain "$SMTP_HOST" "SMTP Host" || validate_ip "$SMTP_HOST" "SMTP Host"
    else
        add_validation_error "SMTP Host non configurato" 1
    fi

    if [[ -n "${SMTP_PORT:-}" ]]; then
        validate_port "$SMTP_PORT" "SMTP Port"
    fi

    if [[ -z "${SMTP_USER:-}" ]]; then
        add_validation_error "SMTP User non configurato" 1
    fi

    if [[ -z "${SMTP_PASS:-}" ]]; then
        add_validation_error "SMTP Password non configurata" 1
    fi
}

validate_minio_config() {
    if [[ -z "${MINIO_ACCESS_KEY:-}" ]]; then
        add_validation_error "MinIO Access Key non configurata" 1
    fi

    if [[ -z "${MINIO_SECRET_KEY:-}" ]]; then
        add_validation_error "MinIO Secret Key non configurata" 1
    fi

    if [[ -n "${MINIO_ENDPOINT:-}" ]]; then
        local endpoint_host="${MINIO_ENDPOINT%%:*}"
        validate_domain "$endpoint_host" "MinIO Endpoint" || validate_ip "$endpoint_host" "MinIO Endpoint"

        if [[ "$MINIO_ENDPOINT" =~ : ]]; then
            local endpoint_port="${MINIO_ENDPOINT##*:}"
            validate_port "$endpoint_port" "MinIO Port"
        fi
    fi
}