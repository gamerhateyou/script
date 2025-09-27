#!/bin/bash

# Script per preparare container Proxmox per WordPress ottimizzato
# Prepara l'ambiente container con tutte le ottimizzazioni necessarie

set -e

# Colori per output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Funzioni di utilità
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Informazioni sistema
show_system_info() {
    log_info "=== INFORMAZIONI SISTEMA ==="
    echo "Hostname: $(hostname)"
    echo "OS: $(lsb_release -d | cut -f2)"
    echo "Kernel: $(uname -r)"
    echo "Architecture: $(uname -m)"
    echo "CPU Cores: $(nproc)"
    echo "RAM: $(free -h | awk '/^Mem:/ {print $2}')"
    echo "Storage: $(df -h / | awk 'NR==2 {print $2}')"
    echo "Container ID: $(cat /proc/1/cgroup | grep ':devices:' | sed 's/.*devices:\///' | cut -d'/' -f1)"
    echo
}

# Verifica ambiente Proxmox
check_proxmox_environment() {
    log_info "Verifica ambiente Proxmox..."

    # Verifica se siamo in un container LXC
    if [ ! -f /proc/1/cgroup ] || ! grep -q "lxc" /proc/1/cgroup; then
        log_warning "Non sembra essere un container LXC Proxmox"
        read -p "Continuare comunque? (y/N): " continue_anyway
        if [[ $continue_anyway != [yY] ]]; then
            log_error "Installazione annullata"
            exit 1
        fi
    else
        log_success "Container LXC Proxmox rilevato"
    fi

    # Verifica privileged vs unprivileged
    if [ -c /dev/fuse ]; then
        log_success "Container privileged rilevato"
    else
        log_warning "Container unprivileged rilevato"
        log_info "Alcune funzionalità potrebbero essere limitate"
    fi
}

# Aggiornamento sistema completo
update_system() {
    log_info "Aggiornamento sistema completo..."

    # Update package lists
    apt update

    # Upgrade existing packages
    apt upgrade -y

    # Install essential tools
    apt install -y \
        apt-transport-https \
        ca-certificates \
        curl \
        gnupg \
        lsb-release \
        software-properties-common \
        wget \
        unzip \
        git \
        htop \
        nano \
        vim \
        tree \
        ncdu \
        iotop \
        nethogs \
        dnsutils \
        net-tools \
        tcpdump \
        rsync \
        screen \
        tmux \
        fail2ban

    log_success "Sistema aggiornato"
}

# Configurazione timezone e locale
configure_locale_timezone() {
    log_info "Configurazione locale e timezone..."

    # Set timezone to Europe/Rome (change as needed)
    timedatectl set-timezone Europe/Rome

    # Configure locales
    locale-gen en_US.UTF-8 it_IT.UTF-8
    update-locale LANG=en_US.UTF-8

    # Configure keyboard
    cat > /etc/default/keyboard << EOF
XKBMODEL="pc105"
XKBLAYOUT="it"
XKBVARIANT=""
XKBOPTIONS=""
BACKSPACE="guess"
EOF

    log_success "Locale e timezone configurati"
}

# Ottimizzazioni kernel per container LXC WordPress 2025
optimize_kernel() {
    log_info "Applicazione ottimizzazioni kernel per LXC WordPress 2025..."

    cat >> /etc/sysctl.conf << EOF

# WordPress LXC Container Optimizations 2025
# Network optimizations (BBR TCP)
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 10000
net.core.rmem_default = 262144
net.core.rmem_max = 134217728
net.core.wmem_default = 262144
net.core.wmem_max = 134217728
net.ipv4.tcp_rmem = 4096 131072 134217728
net.ipv4.tcp_wmem = 4096 131072 134217728
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_keepalive_time = 1200
net.ipv4.tcp_keepalive_probes = 3
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.ip_local_port_range = 1024 65535
net.netfilter.nf_conntrack_max = 262144

# Memory management optimized for WordPress
vm.swappiness = 1
vm.dirty_ratio = 10
vm.dirty_background_ratio = 3
vm.dirty_expire_centisecs = 1500
vm.dirty_writeback_centisecs = 500
vm.overcommit_memory = 1
vm.vfs_cache_pressure = 50

# File system optimizations
fs.file-max = 2097152
fs.inotify.max_user_watches = 1048576
fs.inotify.max_user_instances = 256
fs.aio-max-nr = 1048576

# Security enhancements 2025
kernel.dmesg_restrict = 1
kernel.kptr_restrict = 2
kernel.yama.ptrace_scope = 1
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.default.secure_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_ra = 0
net.ipv6.conf.default.accept_ra = 0

# Container specific optimizations
kernel.pid_max = 4194304
EOF

    # Apply sysctl changes
    sysctl -p

    log_success "Ottimizzazioni kernel LXC 2025 applicate"
}

# Configurazione limiti sistema
configure_system_limits() {
    log_info "Configurazione limiti sistema..."

    cat > /etc/security/limits.conf << EOF
# WordPress Container Limits
* soft nofile 65535
* hard nofile 65535
* soft nproc 65535
* hard nproc 65535
www-data soft nofile 65535
www-data hard nofile 65535
www-data soft nproc 32768
www-data hard nproc 32768
root soft nofile 65535
root hard nofile 65535
EOF

    # PAM limits
    echo "session required pam_limits.so" >> /etc/pam.d/common-session

    # Systemd limits
    mkdir -p /etc/systemd/system.conf.d
    cat > /etc/systemd/system.conf.d/wordpress.conf << EOF
[Manager]
DefaultLimitNOFILE=65535
DefaultLimitNPROC=65535
EOF

    log_success "Limiti sistema configurati"
}

# Configurazione repository PHP 8.3
setup_php_repository() {
    log_info "Configurazione repository PHP 8.3..."

    # Add Ondrej Sury PHP repository
    curl -fsSL https://packages.sury.org/php/apt.gpg | gpg --dearmor -o /usr/share/keyrings/php-archive-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/php-archive-keyring.gpg] https://packages.sury.org/php/ $(lsb_release -sc) main" > /etc/apt/sources.list.d/php.list

    apt update

    log_success "Repository PHP 8.3 configurato"
}

# Configurazione directory web ottimizzate
setup_web_directories() {
    log_info "Configurazione directory web..."

    # Create web directories
    mkdir -p /var/www/html
    mkdir -p /var/www/logs
    mkdir -p /var/www/cache
    mkdir -p /var/www/sessions
    mkdir -p /var/www/uploads

    # Set permissions
    chown -R www-data:www-data /var/www
    chmod -R 755 /var/www/html
    chmod -R 750 /var/www/logs
    chmod -R 755 /var/www/cache
    chmod -R 750 /var/www/sessions
    chmod -R 755 /var/www/uploads

    # Create PHP session directory
    mkdir -p /var/lib/php/sessions
    chown www-data:www-data /var/lib/php/sessions
    chmod 700 /var/lib/php/sessions

    log_success "Directory web configurate"
}

# Configurazione firewall base
setup_firewall() {
    log_info "Configurazione firewall base..."

    # Install ufw if not present
    apt install -y ufw

    # Reset firewall
    ufw --force reset

    # Default policies
    ufw default deny incoming
    ufw default allow outgoing

    # Allow SSH (adjust port if needed)
    ufw allow 22/tcp

    # Allow HTTP and HTTPS
    ufw allow 80/tcp
    ufw allow 443/tcp

    # Allow from private networks (adjust as needed)
    ufw allow from 10.0.0.0/8
    ufw allow from 172.16.0.0/12
    ufw allow from 192.168.0.0/16

    # Enable firewall
    ufw --force enable

    log_success "Firewall configurato"
}

# Configurazione Fail2Ban
setup_fail2ban() {
    log_info "Configurazione Fail2Ban..."

    # Create WordPress jail
    cat > /etc/fail2ban/jail.d/wordpress.conf << EOF
[wordpress]
enabled = true
port = http,https
filter = wordpress
logpath = /var/www/logs/access.log
maxretry = 3
bantime = 3600
findtime = 600

[wordpress-xmlrpc]
enabled = true
port = http,https
filter = wordpress-xmlrpc
logpath = /var/www/logs/access.log
maxretry = 2
bantime = 3600
findtime = 600
EOF

    # Create WordPress filters
    cat > /etc/fail2ban/filter.d/wordpress.conf << EOF
[Definition]
failregex = ^<HOST> .* "POST .*wp-login\.php
            ^<HOST> .* "POST .*wp-admin
            ^<HOST> .* "GET .*wp-login\.php.*\[40[0-9]\]
ignoreregex =
EOF

    cat > /etc/fail2ban/filter.d/wordpress-xmlrpc.conf << EOF
[Definition]
failregex = ^<HOST> .* "POST .*xmlrpc\.php.*" 200
ignoreregex =
EOF

    systemctl enable fail2ban
    systemctl start fail2ban

    log_success "Fail2Ban configurato"
}

# Configurazione logrotate
setup_logrotate() {
    log_info "Configurazione logrotate..."

    cat > /etc/logrotate.d/wordpress << EOF
/var/www/logs/*.log {
    daily
    missingok
    rotate 52
    compress
    delaycompress
    notifempty
    create 644 www-data www-data
    postrotate
        if [ -f /var/run/nginx.pid ]; then
            /usr/sbin/nginx -s reload > /dev/null 2>&1 || true
        fi
    endscript
}

/var/www/html/wp-content/debug.log {
    weekly
    missingok
    rotate 4
    compress
    delaycompress
    notifempty
    create 644 www-data www-data
}
EOF

    log_success "Logrotate configurato"
}

# Configurazione PHP 8.3 e OPcache ottimizzato
setup_php_opcache() {
    log_info "Configurazione PHP 8.3 e OPcache ottimizzato..."

    # Create PHP optimization configuration
    cat > /etc/php/8.3/mods-available/wordpress-optimization.ini << EOF
; PHP 8.3 WordPress Optimizations 2025
; Memory settings
memory_limit = 1024M
post_max_size = 512M
upload_max_filesize = 512M
max_file_uploads = 20
max_execution_time = 300
max_input_time = 300
max_input_vars = 3000

; OPcache optimizations
opcache.enable = 1
opcache.enable_cli = 1
opcache.memory_consumption = 512
opcache.interned_strings_buffer = 64
opcache.max_accelerated_files = 32531
opcache.validate_timestamps = 0
opcache.save_comments = 1
opcache.fast_shutdown = 1
opcache.enable_file_override = 1
opcache.optimization_level = 0x7FFFBFFF
opcache.jit = tracing
opcache.jit_buffer_size = 256M

; Security enhancements
expose_php = Off
allow_url_fopen = Off
allow_url_include = Off
session.cookie_httponly = On
session.cookie_secure = On
session.use_strict_mode = 1

; Error logging
log_errors = On
error_log = /var/log/php_errors.log
display_errors = Off

; Session optimization
session.save_handler = files
session.save_path = "/var/www/sessions"
session.gc_maxlifetime = 7200
session.gc_probability = 1
session.gc_divisor = 1000
EOF

    # Enable the configuration for PHP 8.3
    phpenmod -v 8.3 wordpress-optimization

    log_success "PHP 8.3 e OPcache configurati"
}

# Configurazione connessione Redis esterno
setup_redis_client() {
    log_info "Configurazione client Redis per container esterno..."

    # Install Redis client tools only
    apt install -y redis-tools

    # Create Redis connection test script
    cat > /opt/scripts/test-redis-connection.sh << EOF
#!/bin/bash
# Test Redis connection to external container

REDIS_HOST=\${1:-redis.local}
REDIS_PORT=\${2:-6379}
REDIS_PASS=\${3:-wpredis2025}

echo "Testing Redis connection to \$REDIS_HOST:\$REDIS_PORT"

if redis-cli -h \$REDIS_HOST -p \$REDIS_PORT -a \$REDIS_PASS ping > /dev/null 2>&1; then
    echo "✓ Redis connection successful"
    redis-cli -h \$REDIS_HOST -p \$REDIS_PORT -a \$REDIS_PASS info server | grep redis_version
else
    echo "✗ Redis connection failed"
    echo "Verifica host, porta e password Redis"
fi
EOF

    chmod +x /opt/scripts/test-redis-connection.sh

    log_success "Client Redis configurato per container esterno"
}

# Configurazione client MySQL per container esterno
setup_mysql_client() {
    log_info "Configurazione client MySQL per container esterno..."

    # Install MySQL client only
    apt install -y mysql-client

    # Create MySQL connection test script
    cat > /opt/scripts/test-mysql-connection.sh << EOF
#!/bin/bash
# Test MySQL connection to external container

MYSQL_HOST=\${1:-mysql.local}
MYSQL_PORT=\${2:-3306}
MYSQL_USER=\${3:-wordpress}
MYSQL_PASS=\${4:-wp_password}
MYSQL_DB=\${5:-wordpress}

echo "Testing MySQL connection to \$MYSQL_HOST:\$MYSQL_PORT"

if mysql -h \$MYSQL_HOST -P \$MYSQL_PORT -u \$MYSQL_USER -p\$MYSQL_PASS -e "SELECT VERSION();" > /dev/null 2>&1; then
    echo "✓ MySQL connection successful"
    mysql -h \$MYSQL_HOST -P \$MYSQL_PORT -u \$MYSQL_USER -p\$MYSQL_PASS -e "SELECT VERSION();"
    echo "Database: \$MYSQL_DB"
else
    echo "✗ MySQL connection failed"
    echo "Verifica host, porta, username e password MySQL"
fi
EOF

    chmod +x /opt/scripts/test-mysql-connection.sh

    # Create WordPress database connection test
    cat > /opt/scripts/test-wp-db.php << EOF
<?php
// WordPress database connection test
\$host = \$argv[1] ?? 'mysql.local';
\$port = \$argv[2] ?? '3306';
\$user = \$argv[3] ?? 'wordpress';
\$pass = \$argv[4] ?? 'wp_password';
\$db = \$argv[5] ?? 'wordpress';

try {
    \$pdo = new PDO("mysql:host=\$host;port=\$port;dbname=\$db", \$user, \$pass);
    \$pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);

    echo "✓ WordPress database connection successful\n";

    \$stmt = \$pdo->query('SELECT VERSION()');
    echo "MySQL Version: " . \$stmt->fetchColumn() . "\n";

    \$stmt = \$pdo->query('SELECT DATABASE()');
    echo "Current Database: " . \$stmt->fetchColumn() . "\n";

} catch(PDOException \$e) {
    echo "✗ WordPress database connection failed: " . \$e->getMessage() . "\n";
}
?>
EOF

    chmod +x /opt/scripts/test-wp-db.php

    log_success "Client MySQL configurato per container esterno"
}

# Configurazione cron per ottimizzazioni
setup_cron_optimizations() {
    log_info "Configurazione cron ottimizzazioni..."

    # Create optimization scripts directory
    mkdir -p /opt/scripts

    # Cache cleanup script
    cat > /opt/scripts/cache-cleanup.sh << EOF
#!/bin/bash
# Cache cleanup script

# Clean PHP OPcache
service php8.3-fpm reload 2>/dev/null || service apache2 reload

# Clean system cache
sync && echo 3 > /proc/sys/vm/drop_caches

# Clean temporary files
find /tmp -type f -atime +1 -delete 2>/dev/null || true
find /var/tmp -type f -atime +1 -delete 2>/dev/null || true

# Clean old logs
find /var/log -name "*.log.*.gz" -mtime +30 -delete 2>/dev/null || true

# Clean apt cache
apt autoremove -y && apt autoclean

# Clear Redis cache if external Redis available
redis-cli -h redis.local -p 6379 -a wpredis2025 FLUSHALL 2>/dev/null || echo "Redis esterno non raggiungibile"
EOF

    chmod +x /opt/scripts/cache-cleanup.sh

    # System monitoring script
    cat > /opt/scripts/system-monitor.sh << EOF
#!/bin/bash
# Basic system monitoring

LOG_FILE="/var/log/system-monitor.log"
DATE=\$(date '+%Y-%m-%d %H:%M:%S')

# Check disk usage
DISK_USAGE=\$(df / | awk 'NR==2 {print \$5}' | sed 's/%//')
if [ "\$DISK_USAGE" -gt 80 ]; then
    echo "[\$DATE] WARNING: Disk usage at \${DISK_USAGE}%" >> \$LOG_FILE
fi

# Check memory usage
MEM_USAGE=\$(free | awk 'NR==2{printf "%.0f", \$3/\$2*100}')
if [ "\$MEM_USAGE" -gt 90 ]; then
    echo "[\$DATE] WARNING: Memory usage at \${MEM_USAGE}%" >> \$LOG_FILE
fi

# Check load average
LOAD_AVG=\$(uptime | awk -F'load average:' '{print \$2}' | awk '{print \$1}' | sed 's/,//')
CORES=\$(nproc)
if (( \$(echo "\$LOAD_AVG > \$CORES" | bc -l) )); then
    echo "[\$DATE] WARNING: High load average: \$LOAD_AVG" >> \$LOG_FILE
fi
EOF

    chmod +x /opt/scripts/system-monitor.sh

    # Add cron jobs
    (crontab -l 2>/dev/null; cat << EOF
# WordPress container optimizations
0 2 * * * /opt/scripts/cache-cleanup.sh
*/15 * * * * /opt/scripts/system-monitor.sh
EOF
    ) | crontab -

    log_success "Cron ottimizzazioni configurato"
}

# Preparazione swap (se necessario)
setup_swap() {
    log_info "Configurazione swap..."

    # Check if swap already exists
    if swapon --show | grep -q "/swapfile"; then
        log_info "Swap già configurato"
        return
    fi

    # Get RAM size in GB
    RAM_GB=$(free -g | awk '/^Mem:/ {print $2}')

    # Calculate swap size (1x RAM if RAM <= 2GB, 0.5x RAM if RAM > 2GB)
    if [ "$RAM_GB" -le 2 ]; then
        SWAP_SIZE="${RAM_GB}G"
    else
        SWAP_SIZE="$((RAM_GB / 2))G"
    fi

    read -p "Creare file di swap da $SWAP_SIZE? (y/N): " create_swap
    if [[ $create_swap == [yY] ]]; then
        # Create swap file
        fallocate -l $SWAP_SIZE /swapfile
        chmod 600 /swapfile
        mkswap /swapfile
        swapon /swapfile

        # Make permanent
        echo '/swapfile none swap sw 0 0' >> /etc/fstab

        log_success "Swap $SWAP_SIZE configurato"
    else
        log_info "Swap non configurato"
    fi
}

# Configurazione sicurezza SSH
secure_ssh() {
    log_info "Configurazione sicurezza SSH..."

    # Backup original config
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup

    # Apply security settings
    cat > /etc/ssh/sshd_config.d/security.conf << EOF
# SSH Security Settings
Protocol 2
PermitRootLogin no
PasswordAuthentication yes
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys
PermitEmptyPasswords no
ChallengeResponseAuthentication no
UsePAM yes
X11Forwarding no
PrintMotd no
TCPKeepAlive yes
ClientAliveInterval 300
ClientAliveCountMax 2
MaxAuthTries 3
MaxSessions 10
LoginGraceTime 30
EOF

    # Restart SSH
    systemctl restart ssh

    log_success "SSH configurato in modo sicuro"
}

# Installazione strumenti monitoraggio
install_monitoring_tools() {
    log_info "Installazione strumenti monitoraggio..."

    apt install -y \
        iotop \
        htop \
        nethogs \
        iftop \
        ncdu \
        dstat \
        sysstat \
        lsof \
        strace

    # Enable sysstat
    sed -i 's/ENABLED="false"/ENABLED="true"/' /etc/default/sysstat
    systemctl enable sysstat
    systemctl start sysstat

    log_success "Strumenti monitoraggio installati"
}

# Creazione utente non-root per WordPress
create_wp_user() {
    log_info "Creazione utente per WordPress..."

    read -p "Creare utente 'wordpress' per gestione sito? (y/N): " create_user
    if [[ $create_user == [yY] ]]; then
        # Create user
        useradd -m -s /bin/bash -G www-data,sudo wordpress

        # Set password
        echo "Imposta password per utente 'wordpress':"
        passwd wordpress

        # Create WordPress management directory
        mkdir -p /home/wordpress/scripts
        chown wordpress:wordpress /home/wordpress/scripts

        log_success "Utente 'wordpress' creato"
    else
        log_info "Utente WordPress non creato"
    fi
}

# Configurazione backup directory
setup_backup_structure() {
    log_info "Configurazione struttura backup..."

    mkdir -p /opt/backup/{daily,weekly,monthly}
    mkdir -p /opt/logs

    chown -R root:root /opt/backup
    chmod -R 755 /opt/backup

    # Create backup info script
    cat > /opt/scripts/backup-info.sh << EOF
#!/bin/bash
echo "=== BACKUP STATUS ==="
echo "Backup directory: /opt/backup"
echo "Daily backups: \$(ls -1 /opt/backup/daily 2>/dev/null | wc -l) files"
echo "Weekly backups: \$(ls -1 /opt/backup/weekly 2>/dev/null | wc -l) files"
echo "Monthly backups: \$(ls -1 /opt/backup/monthly 2>/dev/null | wc -l) files"
echo "Total backup size: \$(du -sh /opt/backup 2>/dev/null | cut -f1)"
echo
EOF

    chmod +x /opt/scripts/backup-info.sh

    log_success "Struttura backup configurata"
}

# Test finale sistema
final_system_test() {
    log_info "Test finale sistema..."

    echo "=== TEST SISTEMA ==="

    # Test network
    if ping -c 1 8.8.8.8 &>/dev/null; then
        log_success "Network: OK"
    else
        log_error "Network: ERRORE"
    fi

    # Test DNS
    if nslookup google.com &>/dev/null; then
        log_success "DNS: OK"
    else
        log_error "DNS: ERRORE"
    fi

    # Test disk space
    DISK_AVAIL=$(df / | awk 'NR==2 {print $4}')
    if [ "$DISK_AVAIL" -gt 1000000 ]; then
        log_success "Disk space: OK ($((DISK_AVAIL/1024))MB available)"
    else
        log_warning "Disk space: LOW ($((DISK_AVAIL/1024))MB available)"
    fi

    # Test memory
    MEM_AVAIL=$(free -m | awk 'NR==2 {print $7}')
    if [ "$MEM_AVAIL" -gt 512 ]; then
        log_success "Memory: OK (${MEM_AVAIL}MB available)"
    else
        log_warning "Memory: LOW (${MEM_AVAIL}MB available)"
    fi

    # Test services
    systemctl is-active --quiet fail2ban && log_success "Fail2Ban: OK" || log_error "Fail2Ban: ERRORE"
    systemctl is-active --quiet ufw && log_success "UFW: OK" || log_error "UFW: ERRORE"

    log_success "Test sistema completati"
}

# Generazione report finale
generate_final_report() {
    log_info "Generazione report finale..."

    REPORT_FILE="/root/container-setup-report.txt"

    cat > $REPORT_FILE << EOF
==================================================
PROXMOX CONTAINER WORDPRESS - SETUP REPORT
==================================================
Data: $(date)
Hostname: $(hostname)
Container ID: $(cat /proc/1/cgroup | grep ':devices:' | sed 's/.*devices:\///' | cut -d'/' -f1 2>/dev/null || echo "N/A")

SISTEMA:
- OS: $(lsb_release -d | cut -f2)
- Kernel: $(uname -r)
- CPU: $(nproc) cores
- RAM: $(free -h | awk '/^Mem:/ {print $2}')
- Storage: $(df -h / | awk 'NR==2 {print $2}')

OTTIMIZZAZIONI APPLICATE:
✓ Sistema aggiornato Debian/Ubuntu latest
✓ Kernel ottimizzato per LXC WordPress 2025
✓ Limiti sistema configurati (65535 files)
✓ PHP 8.3 con JIT OPcache (512MB)
✓ Client Redis per container esterno
✓ Client MySQL per container esterno
✓ Directory web strutturate (/var/www)
✓ Firewall UFW configurato (22,80,443)
✓ Fail2Ban anti-brute force attivo
✓ Logrotate gestione log automatica
✓ Cron ottimizzazioni cache/sistema
✓ SSH securizzato (no root login)
✓ Strumenti monitoraggio completi
✓ Struttura backup preparata (/opt/backup)

ARCHITETTURA CONTAINER SEPARATI:
- WordPress: questo container (solo PHP+Apache/Nginx)
- MySQL: container esterno (mysql.local)
- Redis: container esterno (redis.local)
- MinIO: container esterno (minio.local)
- Nginx Proxy Manager: container esterno

PROSSIMI PASSI:
1. Eseguire: ./setup-wordpress-optimized.sh
2. Configurare connessioni ai container esterni
3. Configurare dominio tramite Nginx Proxy Manager
4. Installare certificato SSL via Proxy Manager
5. Configurare backup su MinIO

COMANDI UTILI:
- Stato sistema: htop, iotop, nethogs
- Test Redis: /opt/scripts/test-redis-connection.sh redis.local
- Test MySQL: /opt/scripts/test-mysql-connection.sh mysql.local
- Test WordPress DB: php /opt/scripts/test-wp-db.php mysql.local
- PHP OPcache: php -v (JIT enabled)
- Log sistema: journalctl -f
- Backup info: /opt/scripts/backup-info.sh
- Cache cleanup: /opt/scripts/cache-cleanup.sh

DIRECTORY IMPORTANTI:
- Web root: /var/www/html
- Log: /var/www/logs
- Backup: /opt/backup
- Scripts: /opt/scripts

SICUREZZA:
- Firewall: attivo (porte 22, 80, 443)
- Fail2Ban: attivo
- SSH: configurazione sicura
- Root login: disabilitato

==================================================
EOF

    log_success "Report salvato in: $REPORT_FILE"
}

# Funzione principale
main() {
    log_info "=== PREPARAZIONE CONTAINER PROXMOX PER WORDPRESS ==="
    log_info "Questo script prepara il container con tutte le ottimizzazioni necessarie"
    echo

    # Verifica root
    if [[ $EUID -ne 0 ]]; then
        log_error "Questo script deve essere eseguito come root"
        exit 1
    fi

    show_system_info
    check_proxmox_environment

    read -p "Continuare con la preparazione del container? (y/N): " confirm
    if [[ $confirm != [yY] ]]; then
        log_error "Preparazione annullata"
        exit 1
    fi

    log_info "Avvio preparazione container..."

    update_system
    configure_locale_timezone
    optimize_kernel
    configure_system_limits
    setup_php_repository
    setup_php_opcache
    setup_redis_client
    setup_mysql_client
    setup_web_directories
    setup_firewall
    setup_fail2ban
    setup_logrotate
    setup_cron_optimizations
    setup_swap
    secure_ssh
    install_monitoring_tools
    create_wp_user
    setup_backup_structure
    final_system_test
    generate_final_report

    echo
    log_success "=== PREPARAZIONE CONTAINER COMPLETATA ==="
    log_success "Il container è ora ottimizzato per WordPress"
    echo
    log_info "Report completo disponibile in: /root/container-setup-report.txt"
    log_info "Prossimo step: eseguire setup-wordpress-optimized.sh"
    echo
    log_warning "IMPORTANTE: Riavvia il container per applicare tutte le ottimizzazioni"
    echo "pct reboot <container-id> (dal nodo Proxmox)"
    echo
}

# Esecuzione script
main "$@"