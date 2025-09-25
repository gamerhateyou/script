#!/bin/bash

# =============================================================================
# PROXMOX FUNCTIONS
# =============================================================================

# shellcheck source=./utils.sh
source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"

# =============================================================================
# PROXMOX VALIDATION
# =============================================================================

check_proxmox() {
    log_step "Verifica ambiente Proxmox..."

    if ! command -v pct &> /dev/null; then
        log_error "Questo script deve essere eseguito su un nodo Proxmox VE"
        log_error "Comando 'pct' non trovato"
        exit 1
    fi

    if [[ $EUID -ne 0 ]]; then
        log_error "Questo script deve essere eseguito come root"
        exit 1
    fi

    # Verifica versione Proxmox
    if command -v pveversion &> /dev/null; then
        local pve_version
        pve_version=$(pveversion | head -1 | awk '{print $2}')
        log_info "Proxmox VE versione: $pve_version"
    fi

    log_success "Ambiente Proxmox verificato"
}

# =============================================================================
# STORAGE FUNCTIONS
# =============================================================================

list_storages() {
    log_step "Elenco storage disponibili..."

    if ! pvesm status; then
        log_error "Errore nel recuperare informazioni storage"
        return 1
    fi
}

validate_storage() {
    local storage="$1"

    if ! pvesm status | grep -q "^$storage "; then
        log_error "Storage '$storage' non trovato"
        return 1
    fi

    # Verifica spazio disponibile
    local available_space
    available_space=$(pvesm status | awk -v storage="$storage" '$1==storage {print $5}')

    if [[ -n "$available_space" ]] && [[ "$available_space" != "-" ]]; then
        log_info "Spazio disponibile su $storage: $available_space"
    fi

    return 0
}

# =============================================================================
# TEMPLATE FUNCTIONS
# =============================================================================

download_template() {
    local template_name="$1"
    local storage="${2:-local}"

    log_step "Verifica template: $template_name..."

    local template_path="${TEMPLATE_DIR}/${template_name}"

    if [[ -f "$template_path" ]]; then
        log_info "Template già disponibile: $template_name"
        return 0
    fi

    log_info "Download template in corso..."

    # Aggiorna lista template
    if ! pveam update; then
        log_error "Errore aggiornamento lista template"
        return 1
    fi

    # Download template
    if pveam download "$storage" "$template_name"; then
        log_success "Template scaricato: $template_name"
        return 0
    else
        log_error "Errore download template: $template_name"
        return 1
    fi
}

list_templates() {
    log_step "Template disponibili..."
    pveam available | grep -E "(ubuntu|debian|centos|alpine)"
}

# =============================================================================
# CONTAINER FUNCTIONS
# =============================================================================

create_container() {
    local ctid="$1"
    local template_path="$2"
    local config="$3"

    log_step "Creazione container $ctid..."

    # Estrazione parametri dalla configurazione
    local hostname memory swap cores rootfs net nameserver

    hostname=$(echo "$config" | grep "hostname=" | cut -d'=' -f2)
    memory=$(echo "$config" | grep "memory=" | cut -d'=' -f2)
    swap=$(echo "$config" | grep "swap=" | cut -d'=' -f2)
    cores=$(echo "$config" | grep "cores=" | cut -d'=' -f2)
    rootfs=$(echo "$config" | grep "rootfs=" | cut -d'=' -f2)
    net=$(echo "$config" | grep "net0=" | cut -d'=' -f2-)
    nameserver=$(echo "$config" | grep "nameserver=" | cut -d'=' -f2)

    # Creazione container con parametri dinamici
    local pct_args=(
        "create" "$ctid" "$template_path"
        "--hostname" "$hostname"
        "--memory" "$memory"
        "--swap" "$swap"
        "--cores" "$cores"
        "--rootfs" "$rootfs"
        "--net0" "$net"
        "--nameserver" "$nameserver"
        "--onboot" "1"
        "--unprivileged" "1"
        "--features" "nesting=1"
    )

    # Aggiunta password se specificata
    if echo "$config" | grep -q "password="; then
        local password
        password=$(echo "$config" | grep "password=" | cut -d'=' -f2)
        pct_args+=("--password" "$password")
    fi

    if pct "${pct_args[@]}"; then
        log_success "Container $ctid creato con successo"
    else
        log_error "Errore durante la creazione del container $ctid"
        return 1
    fi

    # Applicazione configurazioni avanzate
    apply_container_optimizations "$ctid"
}

apply_container_optimizations() {
    local ctid="$1"
    local conf_file="/etc/pve/lxc/${ctid}.conf"

    log_step "Applicazione ottimizzazioni container $ctid..."

    if [[ ! -f "$conf_file" ]]; then
        log_error "File di configurazione non trovato: $conf_file"
        return 1
    fi

    # Backup configurazione originale
    backup_file "$conf_file"

    # Aggiunta ottimizzazioni
    cat >> "$conf_file" << EOF

# WordPress Performance Optimizations - 2025
lxc.apparmor.profile: generated
lxc.apparmor.allow_nesting: 1
lxc.mount.auto: cgroup:rw
EOF

    log_success "Ottimizzazioni applicate al container $ctid"
}

start_container() {
    local ctid="$1"
    local wait_time="${2:-30}"

    log_step "Avvio container $ctid..."

    if pct start "$ctid"; then
        log_info "Container $ctid avviato, attesa stabilizzazione ($wait_time s)..."
        sleep "$wait_time"

        if pct status "$ctid" | grep -q "running"; then
            log_success "Container $ctid in esecuzione"
            return 0
        else
            log_error "Container $ctid non si è avviato correttamente"
            return 1
        fi
    else
        log_error "Errore avvio container $ctid"
        return 1
    fi
}

stop_container() {
    local ctid="$1"

    log_step "Arresto container $ctid..."

    if pct stop "$ctid"; then
        log_success "Container $ctid arrestato"
    else
        log_error "Errore arresto container $ctid"
        return 1
    fi
}

container_exec() {
    local ctid="$1"
    shift
    local command="$*"

    log_debug "Esecuzione comando nel container $ctid: $command"

    if pct exec "$ctid" -- bash -c "$command"; then
        return 0
    else
        log_error "Errore esecuzione comando nel container $ctid"
        return 1
    fi
}

container_push() {
    local ctid="$1"
    local source="$2"
    local destination="$3"
    local permissions="${4:-644}"

    log_debug "Push file nel container $ctid: $source -> $destination"

    if pct push "$ctid" "$source" "$destination"; then
        container_exec "$ctid" "chmod $permissions '$destination'"
        log_debug "File pushato: $destination"
        return 0
    else
        log_error "Errore push file nel container $ctid"
        return 1
    fi
}

# =============================================================================
# BACKUP FUNCTIONS
# =============================================================================

setup_container_backup() {
    local ctid="$1"
    local storage="${2:-local}"
    local schedule="${3:-0 2 * * *}"
    local retention="${4:-7}"

    log_step "Configurazione backup automatico container $ctid..."

    local job_id="backup-wordpress-${ctid}"
    local jobs_file="/etc/pve/jobs.cfg"

    # Verifica se job già esiste
    if grep -q "$job_id" "$jobs_file" 2>/dev/null; then
        log_warn "Job di backup già esistente: $job_id"
        return 0
    fi

    # Backup file jobs
    backup_file "$jobs_file"

    # Aggiunta job backup
    cat >> "$jobs_file" << EOF

backup: ${job_id}
    enabled 1
    schedule ${schedule}
    storage ${storage}
    vmid ${ctid}
    compress lzo
    mode snapshot
    maxfiles ${retention}
    notes WordPress Container Backup Auto-generated $(date)
EOF

    log_success "Backup automatico configurato per container $ctid"
    log_info "Schedule: $schedule"
    log_info "Storage: $storage"
    log_info "Retention: $retention giorni"
}

manual_backup() {
    local ctid="$1"
    local storage="${2:-local}"
    local note="${3:-Manual backup $(date)}"

    log_step "Backup manuale container $ctid..."

    if vzdump "$ctid" --storage "$storage" --notes "$note"; then
        log_success "Backup completato per container $ctid"
    else
        log_error "Errore durante il backup del container $ctid"
        return 1
    fi
}

# =============================================================================
# MONITORING FUNCTIONS
# =============================================================================

container_status() {
    local ctid="$1"

    echo "=== STATUS CONTAINER $ctid ==="
    pct status "$ctid" 2>/dev/null || echo "Container non trovato"
    echo

    if pct status "$ctid" 2>/dev/null | grep -q "running"; then
        echo "=== RISORSE ==="
        pct exec "$ctid" -- bash -c "
            echo 'CPU: $(top -bn1 | grep \"Cpu(s)\" | awk \"{print \\\$2}\" | cut -d'%' -f1)%'
            echo 'Memory: $(free -h | awk \"NR==2{printf \\\"%s/%s (%.1f%%)\\\", \\\$3,\\\$2,\\\$3*100/\\\$2}\")'
            echo 'Disk: $(df -h / | awk \"NR==2{print \\\$3\\\"/\\\"\\\$2\\\" (\\\"\\\$5\\\")\\\"}\")'
            echo 'Uptime: $(uptime -p)'
        " 2>/dev/null || echo "Impossibile recuperare informazioni risorse"
    fi
}

test_container_connectivity() {
    local ctid="$1"

    log_step "Test connettività container $ctid..."

    # Test container running
    if ! pct status "$ctid" | grep -q "running"; then
        log_error "Container $ctid non in esecuzione"
        return 1
    fi

    # Test internet connectivity
    if container_exec "$ctid" "ping -c 3 8.8.8.8 >/dev/null 2>&1"; then
        log_success "✓ Connettività internet OK"
    else
        log_error "✗ Problema connettività internet"
        return 1
    fi

    # Test DNS resolution
    if container_exec "$ctid" "nslookup google.com >/dev/null 2>&1"; then
        log_success "✓ Risoluzione DNS OK"
    else
        log_error "✗ Problema risoluzione DNS"
        return 1
    fi

    return 0
}

# =============================================================================
# CLEANUP FUNCTIONS
# =============================================================================

cleanup_failed_container() {
    local ctid="$1"

    log_warn "Cleanup container fallito $ctid..."

    # Stop container se running
    if pct status "$ctid" 2>/dev/null | grep -q "running"; then
        pct stop "$ctid" || true
    fi

    # Rimozione container
    if pct status "$ctid" &>/dev/null; then
        if prompt_confirm "Rimuovere container $ctid fallito?"; then
            pct destroy "$ctid" --purge
            log_info "Container $ctid rimosso"
        fi
    fi

    # Cleanup job backup se esiste
    local job_id="backup-wordpress-${ctid}"
    local jobs_file="/etc/pve/jobs.cfg"

    if grep -q "$job_id" "$jobs_file" 2>/dev/null; then
        sed -i "/backup: ${job_id}/,/notes.*$/d" "$jobs_file"
        log_info "Job backup rimosso"
    fi
}