#!/bin/bash

# =============================================================================
# WORDPRESS VALIDATION FUNCTIONS - Enhanced Error Handling
# =============================================================================

# Error codes
readonly E_INVALID_DOMAIN=10
readonly E_INVALID_EMAIL=11
readonly E_INVALID_IP=12
readonly E_INVALID_PASSWORD=13
readonly E_INVALID_PATH=14
readonly E_INVALID_PORT=15
readonly E_MISSING_DEPENDENCY=16
readonly E_INSUFFICIENT_RESOURCES=17
readonly E_PERMISSION_DENIED=18
readonly E_NETWORK_ERROR=19

# Validation results tracking
VALIDATION_ERRORS=()
VALIDATION_WARNINGS=()

validate_domain() {
    local domain="$1"
    local error_prefix="${2:-Dominio}"

    # Check if domain is empty
    if [[ -z "$domain" ]]; then
        add_validation_error "$error_prefix non può essere vuoto" $E_INVALID_DOMAIN
        return $E_INVALID_DOMAIN
    fi

    # Check domain length
    if [[ ${#domain} -gt 253 ]]; then
        add_validation_error "$error_prefix troppo lungo (max 253 caratteri): $domain" $E_INVALID_DOMAIN
        return $E_INVALID_DOMAIN
    fi

    # Check domain format
    local regex='^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$'
    if [[ ! $domain =~ $regex ]]; then
        add_validation_error "$error_prefix formato non valido: $domain" $E_INVALID_DOMAIN
        return $E_INVALID_DOMAIN
    fi

    # Check if domain contains consecutive dots or starts/ends with dot/hyphen
    if [[ $domain =~ \.\.|\.$ ||^\. || ^- || -$ ]]; then
        add_validation_error "$error_prefix contiene caratteri non validi: $domain" $E_INVALID_DOMAIN
        return $E_INVALID_DOMAIN
    fi

    # DNS resolution check (optional warning)
    if command -v dig >/dev/null 2>&1; then
        if ! dig +short "$domain" >/dev/null 2>&1; then
            add_validation_warning "$error_prefix non risolve DNS: $domain"
        fi
    fi

    return 0
}

validate_email() {
    local email="$1"
    local error_prefix="${2:-Email}"

    # Check if email is empty
    if [[ -z "$email" ]]; then
        add_validation_error "$error_prefix non può essere vuota" $E_INVALID_EMAIL
        return $E_INVALID_EMAIL
    fi

    # Check email length
    if [[ ${#email} -gt 254 ]]; then
        add_validation_error "$error_prefix troppo lunga (max 254 caratteri): $email" $E_INVALID_EMAIL
        return $E_INVALID_EMAIL
    fi

    # Check basic email format
    local regex='^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'
    if [[ ! $email =~ $regex ]]; then
        add_validation_error "$error_prefix formato non valido: $email" $E_INVALID_EMAIL
        return $E_INVALID_EMAIL
    fi

    # Extract and validate domain part
    local domain="${email##*@}"
    if ! validate_domain "$domain" "Dominio email"; then
        add_validation_error "$error_prefix ha dominio non valido: $domain" $E_INVALID_EMAIL
        return $E_INVALID_EMAIL
    fi

    # Check for consecutive dots in local part
    local local_part="${email%%@*}"
    if [[ $local_part =~ \.\. ]]; then
        add_validation_error "$error_prefix contiene punti consecutivi: $email" $E_INVALID_EMAIL
        return $E_INVALID_EMAIL
    fi

    return 0
}

validate_ip() {
    local ip="$1"
    local error_prefix="${2:-Indirizzo IP}"

    if [[ -z "$ip" ]]; then
        add_validation_error "$error_prefix non può essere vuoto" $E_INVALID_IP
        return $E_INVALID_IP
    fi

    # Check IPv4 format
    local regex='^([0-9]{1,3}\.){3}[0-9]{1,3}$'
    if [[ ! $ip =~ $regex ]]; then
        add_validation_error "$error_prefix formato non valido: $ip" $E_INVALID_IP
        return $E_INVALID_IP
    fi

    # Validate each octet
    IFS='.' read -ra OCTETS <<< "$ip"
    for octet in "${OCTETS[@]}"; do
        if [[ $octet -lt 0 || $octet -gt 255 ]]; then
            add_validation_error "$error_prefix octetto non valido ($octet): $ip" $E_INVALID_IP
            return $E_INVALID_IP
        fi

        # Check for leading zeros (except for "0")
        if [[ ${#octet} -gt 1 && $octet =~ ^0 ]]; then
            add_validation_error "$error_prefix contiene zeri iniziali: $ip" $E_INVALID_IP
            return $E_INVALID_IP
        fi
    done

    return 0
}

validate_wordpress_config() {
    local wp_config="$1"
    local error_prefix="${2:-wp-config.php}"

    if [[ ! -f "$wp_config" ]]; then
        add_validation_error "File $error_prefix non trovato: $wp_config" $E_INVALID_PATH
        return $E_INVALID_PATH
    fi

    # Check file permissions
    if [[ ! -r "$wp_config" ]]; then
        add_validation_error "File $error_prefix non leggibile: $wp_config" $E_PERMISSION_DENIED
        return $E_PERMISSION_DENIED
    fi

    local required_constants=(
        "DB_NAME"
        "DB_USER"
        "DB_PASSWORD"
        "DB_HOST"
        "AUTH_KEY"
        "SECURE_AUTH_KEY"
        "LOGGED_IN_KEY"
        "NONCE_KEY"
        "SECURE_AUTH_SALT"
        "LOGGED_IN_SALT"
        "NONCE_SALT"
    )

    local missing_constants=()
    local weak_constants=()

    for constant in "${required_constants[@]}"; do
        if ! grep -q "define.*${constant}" "$wp_config"; then
            missing_constants+=("$constant")
        else
            # Check for weak/default values
            local value
            value=$(grep "define.*${constant}" "$wp_config" | sed "s/.*define.*${constant}[^']*'\([^']*\)'.*/\1/")
            if [[ ${#value} -lt 32 || $value == "put your unique phrase here" ]]; then
                weak_constants+=("$constant")
            fi
        fi
    done

    if [[ ${#missing_constants[@]} -gt 0 ]]; then
        add_validation_error "Costanti mancanti in $error_prefix: ${missing_constants[*]}" $E_INVALID_PATH
        return $E_INVALID_PATH
    fi

    if [[ ${#weak_constants[@]} -gt 0 ]]; then
        add_validation_warning "Costanti deboli in $error_prefix: ${weak_constants[*]}"
    fi

    # Check for dangerous configurations
    if grep -q "define.*WP_DEBUG.*true" "$wp_config"; then
        add_validation_warning "WP_DEBUG attivo in $error_prefix - disabilitare in produzione"
    fi

    if grep -q "define.*DISALLOW_FILE_EDIT.*false" "$wp_config"; then
        add_validation_warning "DISALLOW_FILE_EDIT disabilitato in $error_prefix - rischio sicurezza"
    fi

    return 0
}

# =============================================================================
# ADVANCED VALIDATION FUNCTIONS
# =============================================================================

validate_password_strength() {
    local password="$1"
    local min_length="${2:-8}"
    local error_prefix="${3:-Password}"

    if [[ -z "$password" ]]; then
        add_validation_error "$error_prefix non può essere vuota" $E_INVALID_PASSWORD
        return $E_INVALID_PASSWORD
    fi

    if [[ ${#password} -lt $min_length ]]; then
        add_validation_error "$error_prefix troppo corta (minimo $min_length caratteri)" $E_INVALID_PASSWORD
        return $E_INVALID_PASSWORD
    fi

    local strength_score=0
    local recommendations=()

    # Check for lowercase letters
    [[ $password =~ [a-z] ]] && ((strength_score++)) || recommendations+=("lettere minuscole")

    # Check for uppercase letters
    [[ $password =~ [A-Z] ]] && ((strength_score++)) || recommendations+=("lettere maiuscole")

    # Check for digits
    [[ $password =~ [0-9] ]] && ((strength_score++)) || recommendations+=("numeri")

    # Check for special characters
    [[ $password =~ [^a-zA-Z0-9] ]] && ((strength_score++)) || recommendations+=("caratteri speciali")

    if [[ $strength_score -lt 3 ]]; then
        add_validation_warning "$error_prefix debole. Aggiungi: ${recommendations[*]}"
    fi

    # Check for common weak patterns
    local weak_patterns=(
        "123" "abc" "qwe" "password" "admin" "test" "user"
        "$(date +%Y)" "$(date +%m%d)" "welcome" "login"
    )

    for pattern in "${weak_patterns[@]}"; do
        if [[ ${password,,} == *"$pattern"* ]]; then
            add_validation_warning "$error_prefix contiene pattern comune: $pattern"
            break
        fi
    done

    return 0
}

validate_port() {
    local port="$1"
    local error_prefix="${2:-Porta}"

    if [[ -z "$port" ]]; then
        add_validation_error "$error_prefix non può essere vuota" $E_INVALID_PORT
        return $E_INVALID_PORT
    fi

    if ! [[ $port =~ ^[0-9]+$ ]]; then
        add_validation_error "$error_prefix deve essere numerica: $port" $E_INVALID_PORT
        return $E_INVALID_PORT
    fi

    if [[ $port -lt 1 || $port -gt 65535 ]]; then
        add_validation_error "$error_prefix fuori range (1-65535): $port" $E_INVALID_PORT
        return $E_INVALID_PORT
    fi

    # Check for well-known ports
    if [[ $port -lt 1024 ]]; then
        add_validation_warning "$error_prefix è privilegiata (<1024): $port"
    fi

    return 0
}

validate_path() {
    local path="$1"
    local should_exist="${2:-false}"
    local error_prefix="${3:-Path}"

    if [[ -z "$path" ]]; then
        add_validation_error "$error_prefix non può essere vuoto" $E_INVALID_PATH
        return $E_INVALID_PATH
    fi

    # Check for dangerous characters
    if [[ $path =~ [[:cntrl:]] ]]; then
        add_validation_error "$error_prefix contiene caratteri di controllo" $E_INVALID_PATH
        return $E_INVALID_PATH
    fi

    # Check path length
    if [[ ${#path} -gt 4096 ]]; then
        add_validation_error "$error_prefix troppo lungo (max 4096): $path" $E_INVALID_PATH
        return $E_INVALID_PATH
    fi

    if [[ "$should_exist" == "true" ]]; then
        if [[ ! -e "$path" ]]; then
            add_validation_error "$error_prefix non esiste: $path" $E_INVALID_PATH
            return $E_INVALID_PATH
        fi
    fi

    return 0
}

validate_disk_space() {
    local required_mb="${1:-1000}"
    local path="${2:-.}"
    local error_prefix="${3:-Spazio disco}"

    if ! command -v df >/dev/null 2>&1; then
        add_validation_warning "Comando 'df' non disponibile per controllo spazio disco"
        return 0
    fi

    local available_kb
    available_kb=$(df "$path" | awk 'NR==2 {print $4}')
    local available_mb=$((available_kb / 1024))

    if [[ $available_mb -lt $required_mb ]]; then
        add_validation_error "$error_prefix insufficiente: ${available_mb}MB disponibili, ${required_mb}MB richiesti" $E_INSUFFICIENT_RESOURCES
        return $E_INSUFFICIENT_RESOURCES
    fi

    if [[ $available_mb -lt $((required_mb * 2)) ]]; then
        add_validation_warning "$error_prefix limitato: ${available_mb}MB disponibili"
    fi

    return 0
}

validate_memory() {
    local required_mb="${1:-512}"
    local error_prefix="${2:-Memoria}"

    if ! command -v free >/dev/null 2>&1; then
        add_validation_warning "Comando 'free' non disponibile per controllo memoria"
        return 0
    fi

    local available_mb
    available_mb=$(free -m | awk 'NR==2{print $7}')

    if [[ -z "$available_mb" ]]; then
        available_mb=$(free -m | awk 'NR==2{print $4}')
    fi

    if [[ $available_mb -lt $required_mb ]]; then
        add_validation_error "$error_prefix insufficiente: ${available_mb}MB disponibili, ${required_mb}MB richiesti" $E_INSUFFICIENT_RESOURCES
        return $E_INSUFFICIENT_RESOURCES
    fi

    if [[ $available_mb -lt $((required_mb * 2)) ]]; then
        add_validation_warning "$error_prefix limitata: ${available_mb}MB disponibili"
    fi

    return 0
}

validate_network_connectivity() {
    local host="${1:-8.8.8.8}"
    local port="${2:-53}"
    local timeout="${3:-5}"

    if ! command -v nc >/dev/null 2>&1 && ! command -v telnet >/dev/null 2>&1; then
        add_validation_warning "Nessun strumento di test rete disponibile (nc/telnet)"
        return 0
    fi

    local test_result=1

    if command -v nc >/dev/null 2>&1; then
        if nc -z -w"$timeout" "$host" "$port" >/dev/null 2>&1; then
            test_result=0
        fi
    elif command -v telnet >/dev/null 2>&1; then
        if timeout "$timeout" telnet "$host" "$port" </dev/null >/dev/null 2>&1; then
            test_result=0
        fi
    fi

    if [[ $test_result -ne 0 ]]; then
        add_validation_error "Connettività rete non disponibile verso $host:$port" $E_NETWORK_ERROR
        return $E_NETWORK_ERROR
    fi

    return 0
}

# =============================================================================
# ERROR HANDLING UTILITY FUNCTIONS
# =============================================================================

add_validation_error() {
    local message="$1"
    local code="${2:-1}"
    VALIDATION_ERRORS+=("[$code] $message")
    log_error "$message"
}

add_validation_warning() {
    local message="$1"
    VALIDATION_WARNINGS+=("$message")
    log_warn "$message"
}

has_validation_errors() {
    [[ ${#VALIDATION_ERRORS[@]} -gt 0 ]]
}

has_validation_warnings() {
    [[ ${#VALIDATION_WARNINGS[@]} -gt 0 ]]
}

get_validation_errors() {
    printf '%s\n' "${VALIDATION_ERRORS[@]}"
}

get_validation_warnings() {
    printf '%s\n' "${VALIDATION_WARNINGS[@]}"
}

clear_validation_results() {
    VALIDATION_ERRORS=()
    VALIDATION_WARNINGS=()
}

show_validation_summary() {
    local title="${1:-Risultati Validazione}"

    echo
    log_step "$title"

    if has_validation_errors; then
        echo
        log_error "❌ ERRORI TROVATI (${#VALIDATION_ERRORS[@]}):"
        get_validation_errors | sed 's/^/   • /'
    fi

    if has_validation_warnings; then
        echo
        log_warn "⚠️  AVVERTIMENTI (${#VALIDATION_WARNINGS[@]}):"
        get_validation_warnings | sed 's/^/   • /'
    fi

    if ! has_validation_errors && ! has_validation_warnings; then
        echo
        log_success "✅ Validazione completata senza problemi"
    fi

    echo
}