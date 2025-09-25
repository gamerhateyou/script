#!/bin/bash

# =============================================================================
# UTILITIES E FUNZIONI COMUNI
# =============================================================================

set -euo pipefail

# Colori per output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# =============================================================================
# LOGGING FUNCTIONS
# =============================================================================

log_info() {
    echo -e "${GREEN}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "${LOG_FILE:-/tmp/wp-container.log}"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "${LOG_FILE:-/tmp/wp-container.log}"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "${LOG_FILE:-/tmp/wp-container.log}"
}

log_step() {
    echo -e "${BLUE}[STEP]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "${LOG_FILE:-/tmp/wp-container.log}"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "${LOG_FILE:-/tmp/wp-container.log}"
}

log_debug() {
    if [[ "${DEBUG:-false}" == "true" ]]; then
        echo -e "${PURPLE}[DEBUG]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "${LOG_FILE:-/tmp/wp-container.log}"
    fi
}

# =============================================================================
# VALIDATION FUNCTIONS
# =============================================================================

validate_ctid() {
    local ctid="$1"

    if [[ ! "$ctid" =~ ^[0-9]+$ ]]; then
        return 1
    fi

    if [ "$ctid" -lt 100 ] || [ "$ctid" -gt 999999 ]; then
        return 1
    fi

    if pct status "$ctid" &>/dev/null; then
        return 1
    fi

    return 0
}

validate_ip() {
    local ip="$1"
    local regex='^([0-9]{1,3}\.){3}[0-9]{1,3}(/[0-9]{1,2})?$'

    if [[ ! $ip =~ $regex ]]; then
        return 1
    fi

    # Validate each octet
    IFS='/' read -r ip_addr cidr <<< "$ip"
    IFS='.' read -ra octets <<< "$ip_addr"

    for octet in "${octets[@]}"; do
        if [ "$octet" -gt 255 ]; then
            return 1
        fi
    done

    return 0
}

validate_hostname() {
    local hostname="$1"
    local regex='^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$'

    [[ $hostname =~ $regex ]]
}

validate_email() {
    local email="$1"
    local regex='^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'

    [[ $email =~ $regex ]]
}

validate_domain() {
    local domain="$1"
    local regex='^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$'

    [[ $domain =~ $regex ]]
}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

check_command() {
    local cmd="$1"
    if ! command -v "$cmd" &> /dev/null; then
        log_error "Comando richiesto non trovato: $cmd"
        return 1
    fi
    return 0
}

check_file() {
    local file="$1"
    if [[ ! -f "$file" ]]; then
        log_error "File non trovato: $file"
        return 1
    fi
    return 0
}

check_directory() {
    local dir="$1"
    if [[ ! -d "$dir" ]]; then
        log_error "Directory non trovata: $dir"
        return 1
    fi
    return 0
}

create_directory() {
    local dir="$1"
    local mode="${2:-755}"

    if [[ ! -d "$dir" ]]; then
        mkdir -p "$dir"
        chmod "$mode" "$dir"
        log_info "Directory creata: $dir"
    fi
}

backup_file() {
    local file="$1"
    local backup_file="${file}.backup.$(date +%Y%m%d_%H%M%S)"

    if [[ -f "$file" ]]; then
        cp "$file" "$backup_file"
        log_info "Backup creato: $backup_file"
    fi
}

generate_password() {
    local length="${1:-16}"
    openssl rand -base64 "$length" | tr -d "=+/" | cut -c1-"$length"
}

generate_random_string() {
    local length="${1:-8}"
    openssl rand -hex "$((length/2))" | cut -c1-"$length"
}

# =============================================================================
# NETWORK FUNCTIONS
# =============================================================================

test_connectivity() {
    local host="${1:-8.8.8.8}"
    local timeout="${2:-5}"

    if timeout "$timeout" ping -c 1 "$host" &>/dev/null; then
        return 0
    else
        return 1
    fi
}

test_port() {
    local host="$1"
    local port="$2"
    local timeout="${3:-5}"

    if timeout "$timeout" bash -c "</dev/tcp/$host/$port" &>/dev/null; then
        return 0
    else
        return 1
    fi
}

# =============================================================================
# SYSTEM FUNCTIONS
# =============================================================================

get_system_info() {
    echo "=== SYSTEM INFORMATION ==="
    echo "OS: $(lsb_release -d 2>/dev/null | cut -f2 || echo 'Unknown')"
    echo "Kernel: $(uname -r)"
    echo "Memory: $(free -h | awk 'NR==2{print $2}')"
    echo "CPU: $(nproc) cores"
    echo "Disk Space: $(df -h / | awk 'NR==2{print $4}' | sed 's/G/ GB/')"
    echo "Uptime: $(uptime -p 2>/dev/null || uptime | cut -d',' -f1)"
}

check_system_requirements() {
    local required_memory=2048
    local required_disk=10

    # Check memory (in MB)
    local memory_mb=$(free -m | awk 'NR==2{print $2}')
    if [ "$memory_mb" -lt "$required_memory" ]; then
        log_error "Memoria insufficiente. Richiesti: ${required_memory}MB, Disponibili: ${memory_mb}MB"
        return 1
    fi

    # Check disk space (in GB)
    local disk_gb=$(df / | awk 'NR==2{print int($4/1024/1024)}')
    if [ "$disk_gb" -lt "$required_disk" ]; then
        log_error "Spazio disco insufficiente. Richiesti: ${required_disk}GB, Disponibili: ${disk_gb}GB"
        return 1
    fi

    return 0
}

# =============================================================================
# ERROR HANDLING
# =============================================================================

cleanup_on_exit() {
    local exit_code=$?
    log_debug "Cleanup eseguito con codice di uscita: $exit_code"

    # Cleanup specifico può essere aggiunto qui
    if [[ -n "${TEMP_DIR:-}" ]] && [[ -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR"
        log_debug "Directory temporanea rimossa: $TEMP_DIR"
    fi
}

setup_error_handling() {
    trap cleanup_on_exit EXIT
    trap 'log_error "Script interrotto dall utente"; exit 130' INT TERM
}

# =============================================================================
# CONFIGURATION LOADING
# =============================================================================

load_config() {
    local config_file="${1:-config/default.conf}"

    if [[ -f "$config_file" ]]; then
        # shellcheck source=/dev/null
        source "$config_file"
        log_info "Configurazione caricata: $config_file"
    else
        log_warn "File di configurazione non trovato: $config_file"
        return 1
    fi
}

# =============================================================================
# INTERACTIVE INPUT
# =============================================================================

prompt_input() {
    local prompt="$1"
    local default="${2:-}"
    local validator="${3:-}"
    local result

    while true; do
        if [[ -n "$default" ]]; then
            read -p "$prompt [default: $default]: " result
            result="${result:-$default}"
        else
            read -p "$prompt: " result
        fi

        if [[ -n "$validator" ]] && ! "$validator" "$result"; then
            log_error "Input non valido. Riprova."
            continue
        fi

        echo "$result"
        return 0
    done
}

prompt_password() {
    local prompt="$1"
    local result

    while true; do
        read -s -p "$prompt: " result
        echo
        if [[ -n "$result" ]]; then
            echo "$result"
            return 0
        fi
        log_error "Password non può essere vuota. Riprova."
    done
}

prompt_confirm() {
    local prompt="$1"
    local default="${2:-n}"
    local result

    while true; do
        read -p "$prompt [y/N]: " result
        result="${result:-$default}"

        case "${result,,}" in
            y|yes|s|si)
                return 0
                ;;
            n|no)
                return 1
                ;;
            *)
                log_error "Risposta non valida. Usa y/n."
                ;;
        esac
    done
}

# =============================================================================
# INITIALIZATION
# =============================================================================

init_utils() {
    # Setup error handling
    setup_error_handling

    # Create temporary directory
    TEMP_DIR=$(mktemp -d)
    export TEMP_DIR

    log_debug "Utils inizializzati. TEMP_DIR: $TEMP_DIR"
}

# Auto-initialize if sourced
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    init_utils
fi