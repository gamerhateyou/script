#!/bin/bash

# =============================================================================
# WORDPRESS UTILITY FUNCTIONS
# =============================================================================

# shellcheck source=../utils.sh
source "$(dirname "${BASH_SOURCE[0]}")/../utils.sh"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging functions
log_info() { echo -e "${GREEN}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"; }

# Configuration defaults
WP_VERSION="latest"
WP_LOCALE="it_IT"
PHP_VERSION="8.3"

# Directory paths
NGINX_SITES_AVAILABLE="/etc/nginx/sites-available"
NGINX_SITES_ENABLED="/etc/nginx/sites-enabled"
PHP_FPM_POOL="/etc/php/${PHP_VERSION}/fpm/pool.d"
PHP_FPM_CONF="/etc/php/${PHP_VERSION}/fpm/conf.d"

# Retry mechanism with exponential backoff
retry_command() {
    local max_attempts="${1:-3}"
    local delay="${2:-5}"
    local description="${3:-command}"
    shift 3
    local command=("$@")

    local attempt=1
    local current_delay="$delay"

    while [ $attempt -le $max_attempts ]; do
        log_info "Tentativo $attempt/$max_attempts: $description"

        if "${command[@]}"; then
            log_success "$description completato al tentativo $attempt"
            return 0
        fi

        if [ $attempt -lt $max_attempts ]; then
            log_warn "Tentativo $attempt fallito, riprovo tra ${current_delay}s..."
            sleep "$current_delay"
            current_delay=$((current_delay * 2))  # Exponential backoff
        fi

        ((attempt++))
    done

    log_error "$description fallito dopo $max_attempts tentativi"
    return 1
}

# Test database connection with retry mechanism
test_database_connection_with_retry() {
    local db_host="${1:-localhost}"
    local db_user="$2"
    local db_pass="$3"
    local db_name="$4"

    log_step "Testing database connection..."

    local test_cmd=(
        mysql
        -h "$db_host"
        -u "$db_user"
        "-p$db_pass"
        -e "USE $db_name; SELECT 1;"
        --silent
    )

    if retry_command 3 5 "test connessione database" "${test_cmd[@]}"; then
        log_success "Connessione database verificata"
        return 0
    else
        log_error "Impossibile connettersi al database"
        return 1
    fi
}

# Test database connection (simple version)
test_database_connection() {
    mysql -h localhost -u "$DB_USER" -p"$DB_PASS" -e "USE $DB_NAME; SELECT 1;" >/dev/null 2>&1
}

# =============================================================================
# ENHANCED ERROR HANDLING FUNCTIONS
# =============================================================================

# Error cleanup functions
cleanup_on_exit() {
    local exit_code=$?
    log_info "Pulizia in corso... (exit code: $exit_code)"

    # Stop services if they were started
    if [[ -n "${SERVICES_STARTED:-}" ]]; then
        for service in $SERVICES_STARTED; do
            log_info "Arresto servizio: $service"
            systemctl stop "$service" >/dev/null 2>&1 || true
        done
    fi

    # Clean temporary files
    if [[ -n "${TEMP_FILES:-}" ]]; then
        for temp_file in $TEMP_FILES; do
            [[ -f "$temp_file" ]] && rm -f "$temp_file"
        done
    fi

    # Clean temporary directories
    if [[ -n "${TEMP_DIRS:-}" ]]; then
        for temp_dir in $TEMP_DIRS; do
            [[ -d "$temp_dir" ]] && rm -rf "$temp_dir"
        done
    fi

    if [[ $exit_code -ne 0 ]]; then
        log_error "Script terminato con errori"
        echo "Per supporto, condividi i log da: /var/log/"
    else
        log_success "Script completato con successo"
    fi

    exit $exit_code
}

# Set up error handling
setup_error_handling() {
    # Exit on any error
    set -euo pipefail

    # Trap signals for cleanup
    trap cleanup_on_exit EXIT
    trap 'log_error "Script interrotto"; exit 130' INT
    trap 'log_error "Script terminato"; exit 143' TERM

    # Enable debug if requested
    if [[ "${DEBUG:-}" == "true" ]]; then
        set -x
        log_info "Modalità debug abilitata"
    fi
}

# Enhanced command execution with error handling
execute_with_error_handling() {
    local command="$1"
    local description="${2:-command}"
    local max_attempts="${3:-1}"
    local delay="${4:-0}"
    local continue_on_error="${5:-false}"

    local attempt=1

    while [[ $attempt -le $max_attempts ]]; do
        log_info "Esecuzione ($attempt/$max_attempts): $description"

        if eval "$command"; then
            log_success "$description completato"
            return 0
        else
            local exit_code=$?

            if [[ $attempt -lt $max_attempts ]]; then
                log_warn "$description fallito (tentativo $attempt), riprovo tra ${delay}s..."
                sleep "$delay"
                ((attempt++))
            else
                if [[ "$continue_on_error" == "true" ]]; then
                    log_warn "$description fallito dopo $max_attempts tentativi (ignorato)"
                    return 0
                else
                    log_error "$description fallito dopo $max_attempts tentativi"
                    return $exit_code
                fi
            fi
        fi
    done
}

# Check system prerequisites with detailed validation
check_system_prerequisites() {
    log_step "Controllo prerequisiti sistema..."

    clear_validation_results

    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        add_validation_error "Script deve essere eseguito come root" 1
    fi

    # Check system architecture
    local arch
    arch=$(uname -m)
    if [[ ! $arch =~ ^(x86_64|aarch64)$ ]]; then
        add_validation_warning "Architettura non testata: $arch"
    fi

    # Check operating system
    if [[ ! -f /etc/os-release ]]; then
        add_validation_error "Sistema operativo non identificabile" 1
    else
        local os_id
        os_id=$(grep "^ID=" /etc/os-release | cut -d'=' -f2 | tr -d '"')
        case $os_id in
            ubuntu|debian)
                log_info "Sistema operativo supportato: $os_id"
                ;;
            *)
                add_validation_warning "Sistema operativo non testato: $os_id"
                ;;
        esac
    fi

    # Check available commands
    local required_commands=("curl" "wget" "mysql" "systemctl")
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            add_validation_error "Comando richiesto non trovato: $cmd" $E_MISSING_DEPENDENCY
        fi
    done

    # System resources validation
    validate_disk_space 2000 "/" "Spazio disco root"
    validate_disk_space 1000 "/var" "Spazio disco /var"
    validate_memory 512 "Memoria RAM"
    validate_network_connectivity "archive.ubuntu.com" 80

    # Check if ports are available
    local required_ports=(80 443)
    for port in "${required_ports[@]}"; do
        if command -v netstat >/dev/null 2>&1; then
            if netstat -ln | grep -q ":$port "; then
                add_validation_warning "Porta $port già in uso"
            fi
        fi
    done

    show_validation_summary "Prerequisiti Sistema"

    if has_validation_errors; then
        log_error "❌ Prerequisiti non soddisfatti"
        return 1
    fi

    log_success "✅ Prerequisiti sistema verificati"
    return 0
}

# Enhanced service management with error handling
manage_service() {
    local service="$1"
    local action="${2:-start}"
    local timeout="${3:-30}"

    log_info "Gestione servizio $service: $action"

    case $action in
        start)
            if systemctl is-active --quiet "$service"; then
                log_info "Servizio $service già attivo"
                return 0
            fi

            if systemctl start "$service"; then
                # Track started services for cleanup
                SERVICES_STARTED="${SERVICES_STARTED:-} $service"

                # Wait for service to be ready
                local count=0
                while [[ $count -lt $timeout ]] && ! systemctl is-active --quiet "$service"; do
                    sleep 1
                    ((count++))
                done

                if systemctl is-active --quiet "$service"; then
                    log_success "Servizio $service avviato"
                    return 0
                else
                    log_error "Servizio $service non si è avviato entro ${timeout}s"
                    return 1
                fi
            else
                log_error "Impossibile avviare servizio $service"
                return 1
            fi
            ;;

        stop)
            if ! systemctl is-active --quiet "$service"; then
                log_info "Servizio $service già fermato"
                return 0
            fi

            if systemctl stop "$service"; then
                log_success "Servizio $service fermato"
                return 0
            else
                log_error "Impossibile fermare servizio $service"
                return 1
            fi
            ;;

        restart)
            manage_service "$service" stop
            manage_service "$service" start
            ;;

        *)
            log_error "Azione non supportata: $action"
            return 1
            ;;
    esac
}

# Progress tracking functions
init_progress() {
    local total_steps="$1"
    local description="${2:-Operazione}"

    export PROGRESS_TOTAL="$total_steps"
    export PROGRESS_CURRENT=0
    export PROGRESS_DESCRIPTION="$description"

    log_step "$description (0/$total_steps)"
}

update_progress() {
    local step_description="$1"
    local increment="${2:-1}"

    PROGRESS_CURRENT=$((PROGRESS_CURRENT + increment))

    local percentage=$(( (PROGRESS_CURRENT * 100) / PROGRESS_TOTAL ))

    log_step "$PROGRESS_DESCRIPTION ($PROGRESS_CURRENT/$PROGRESS_TOTAL - ${percentage}%): $step_description"
}

# File operation with error handling
safe_file_operation() {
    local operation="$1"
    local source="$2"
    local destination="${3:-}"
    local backup="${4:-true}"

    case $operation in
        copy)
            if [[ "$backup" == "true" && -f "$destination" ]]; then
                local backup_file="${destination}.backup.$(date +%s)"
                cp "$destination" "$backup_file"
                log_info "Backup creato: $backup_file"
            fi

            if cp "$source" "$destination"; then
                log_success "File copiato: $source → $destination"
                return 0
            else
                log_error "Errore copia file: $source → $destination"
                return 1
            fi
            ;;

        move)
            if [[ "$backup" == "true" && -f "$destination" ]]; then
                local backup_file="${destination}.backup.$(date +%s)"
                cp "$destination" "$backup_file"
                log_info "Backup creato: $backup_file"
            fi

            if mv "$source" "$destination"; then
                log_success "File spostato: $source → $destination"
                return 0
            else
                log_error "Errore spostamento file: $source → $destination"
                return 1
            fi
            ;;

        delete)
            if [[ "$backup" == "true" && -f "$source" ]]; then
                local backup_file="/tmp/$(basename "$source").backup.$(date +%s)"
                cp "$source" "$backup_file"
                TEMP_FILES="${TEMP_FILES:-} $backup_file"
                log_info "Backup creato: $backup_file"
            fi

            if rm -f "$source"; then
                log_success "File eliminato: $source"
                return 0
            else
                log_error "Errore eliminazione file: $source"
                return 1
            fi
            ;;

        *)
            log_error "Operazione file non supportata: $operation"
            return 1
            ;;
    esac
}