# 🚀 GUIDA COMPLETA - WORDPRESS CONTAINER LXC SU PROXMOX

## Versione 2025.09 - Setup Enterprise con Cloudflare Zero Trust

---

## 📋 **INDICE**

1. [Prerequisiti](#prerequisiti)
2. [Esecuzione Script Container](#esecuzione-script-container)
3. [Installazione WordPress](#installazione-wordpress)
4. [Configurazione WordPress Ottimale](#configurazione-wordpress-ottimale)
5. [Integrazione Cloudflare Zero Trust](#integrazione-cloudflare-zero-trust)
6. [Configurazione Nginx Proxy Separato](#configurazione-nginx-proxy-separato)
7. [Monitoring e Manutenzione](#monitoring-e-manutenzione)
8. [Troubleshooting](#troubleshooting)

---

## 🔧 **PREREQUISITI**

### Server Proxmox
- **RAM**: Minimo 8GB (consigliato 16GB+)
- **CPU**: 4+ cores
- **Storage**: 100GB+ liberi
- **Rete**: Bridge configurato (vmbr0)
- **OS**: Proxmox VE 7.0+

### Servizi Esterni (Opzionali ma Consigliati)
- **Database MySQL**: Server dedicato o cluster
- **Redis**: Server cache dedicato
- **MinIO**: Object storage (per media files)
- **Cloudflare**: Account Pro+ per Zero Trust

### Informazioni da Preparare
- **Dominio**: registrato e configurabile su Cloudflare
- **IP pubblico**: per il server Proxmox
- **Credenziali database**: se usi MySQL esterno
- **Email**: per certificati SSL e notifiche

---

## 🚀 **ESECUZIONE SCRIPT CONTAINER**

### 1. Preparazione Script

```bash
# Su nodo Proxmox, come root
cd /root
git clone [repository-url] wordpress-container
cd wordpress-container

# Verifica permessi
chmod +x create-wordpress-container.sh
chmod +x lib/*.sh
```

### 2. Esecuzione Standard

```bash
# Avvio interattivo standard
./create-wordpress-container.sh

# Con debug abilitato
./create-wordpress-container.sh --debug

# Con configurazione personalizzata
./create-wordpress-container.sh --config config/production.conf
```

### 3. Parametri Richiesti Durante Setup

**Container LXC:**
- **Container ID**: es. `200` (100-999999)
- **Hostname**: es. `wp-production`
- **Password root**: password sicura
- **RAM**: `4096MB` (consigliato per performance)
- **Disk**: `50GB` (adeguato per sito medio-grande)
- **CPU**: `4 cores`

**Rete:**
- **Bridge**: `vmbr0` (default)
- **IP Address**: es. `192.168.1.100/24`
- **Gateway**: es. `192.168.1.1`
- **DNS**: `8.8.8.8` o DNS locale

**Storage:**
- **Storage**: `local` o storage SSD dedicato

### 4. Output Atteso

```
🎉 CONTAINER LXC WORDPRESS CREATO CON SUCCESSO!
=========================================================
📋 DETTAGLI CONTAINER:
   • ID Container: 200
   • Hostname: wp-production
   • IP Address: 192.168.1.100/24
   • RAM: 4096 MB
   • Disk: 50 GB su local
```

---

## ⚙️ **INSTALLAZIONE WORDPRESS**

### 1. Accesso al Container

```bash
# Dal nodo Proxmox
pct enter 200
```

### 2. Esecuzione Script WordPress

```bash
# Nel container
cd /root/scripts
./wp-install.sh
```

### 3. Configurazione WordPress

**Informazioni Sito:**
```
Nome del sito: [Il Mio Sito WordPress]
Dominio: [esempio.com]
```

**Database (MySQL Esterno Consigliato):**
```
IP server MySQL: [192.168.1.50]
Nome database: [wp_production]
Username database: [wp_user]
Password database: [password_sicura]
```

**Admin WordPress:**
```
Email admin WordPress: [admin@esempio.com]
Username admin WordPress: [admin]
Password admin WordPress: [password_forte]
```

**Servizi Opzionali:**
```
IP server Redis: [192.168.1.60]  # Per object cache
IP server MinIO: [192.168.1.70]  # Per media storage
SSL automatico: [y]              # Let's Encrypt
```

### 4. Completamento Installazione

Lo script configurerà automaticamente:
- ✅ PHP 8.3 + OPcache ottimizzato
- ✅ Nginx con configuration performance
- ✅ WordPress + plugin essenziali
- ✅ Sicurezza (Fail2ban, UFW, Wordfence)
- ✅ SSL Let's Encrypt (se dominio pubblico)
- ✅ Backup automatici
- ✅ Manutenzione programmata

---

## 🎯 **CONFIGURAZIONE WORDPRESS OTTIMALE**

### 1. Primo Accesso Admin

```
URL: https://esempio.com/wp-admin
Username: [quello configurato]
Password: [quella configurata]
```

### 2. Plugin Pre-installati da Configurare

#### **Wordfence Security**
```
1. Vai su Wordfence > All Options
2. Firewall Settings:
   - Learning Mode: OFF
   - Protection Level: High
3. Scan Settings:
   - Enable High Sensitivity
   - Enable Malware Scan
4. Login Security:
   - Enable 2FA
   - Limit login attempts: 5
```

#### **WP Optimize**
```
1. Cache Settings:
   - Enable Page Caching
   - Enable GZIP Compression
   - Enable Browser Caching
2. Database Optimization:
   - Schedule weekly cleanup
   - Remove spam/trash automatically
```

#### **UpdraftPlus Backup**
```
1. Settings > UpdraftPlus Backups
2. Remote Storage: Configure S3/MinIO
3. Schedule: Daily (files) + Database
4. Retention: 30 days
5. Test restore functionality
```

### 3. Tema e Performance

#### **Tema Consigliato: GeneratePress Pro**
```
1. Install > GeneratePress + Pro addon
2. Site Library: Import performance-optimized template
3. Customizer: Configure colori/font brand
4. Performance: Enable lazy loading
```

#### **Plugin Performance Aggiuntivi**
```
# Install solo se necessari
- WP Rocket (cache premium)
- Smush Pro (image optimization)
- ShortPixel (image compression)
- W3 Total Cache (alternativa a WP Optimize)
```

### 4. Configurazioni WordPress Avanzate

#### **wp-config.php Tuning**
```bash
# Nel container, modifica wp-config.php
nano /var/www/esempio.com/wp-config.php

# Aggiungi queste configurazioni
define('WP_MEMORY_LIMIT', '512M');
define('WP_MAX_MEMORY_LIMIT', '1024M');
define('WP_DEBUG', false);
define('WP_CACHE', true);
define('AUTOMATIC_UPDATER_DISABLED', false);
define('WP_AUTO_UPDATE_CORE', true);
define('DISALLOW_FILE_EDIT', true);
define('FORCE_SSL_ADMIN', true);

# Redis Object Cache (se disponibile)
define('WP_REDIS_HOST', '192.168.1.60');
define('WP_REDIS_PORT', 6379);
define('WP_REDIS_DATABASE', 0);
```

---

## ☁️ **INTEGRAZIONE CLOUDFLARE ZERO TRUST**

### 1. Setup Cloudflare Tunnel (Cloudflared)

#### **Dashboard Cloudflare**
```
1. Login su Cloudflare Dashboard
2. Zero Trust > Access > Tunnels
3. Create Tunnel > Nome: "wp-production"
4. Copia il token mostrato
```

#### **Installazione nel Container**
```bash
# Nel container WordPress
wget -q https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
dpkg -i cloudflared-linux-amd64.deb

# Autenticazione con token
cloudflared service install TOKEN_COPIATO_DA_DASHBOARD
```

#### **Configurazione Tunnel**
```bash
# Crea configurazione tunnel
nano /etc/cloudflared/config.yml

# Contenuto:
tunnel: TUNNEL_ID_DA_DASHBOARD
credentials-file: /root/.cloudflared/TUNNEL_ID.json

ingress:
  - hostname: esempio.com
    service: http://localhost:80
  - hostname: www.esempio.com
    service: http://localhost:80
  - service: http_status:404

# Avvia servizio
systemctl enable cloudflared
systemctl start cloudflared
systemctl status cloudflared
```

### 2. DNS Configuration

#### **Su Cloudflare Dashboard**
```
1. DNS > Records
2. Add Record:
   - Type: CNAME
   - Name: esempio.com
   - Target: TUNNEL_ID.cfargotunnel.com
   - Proxy: ON (orange cloud)
3. Add Record:
   - Type: CNAME
   - Name: www
   - Target: TUNNEL_ID.cfargotunnel.com
   - Proxy: ON (orange cloud)
```

### 3. Cloudflare Optimization

#### **Speed Settings**
```
1. Speed > Optimization:
   - Auto Minify: JS, CSS, HTML = ON
   - Brotli Compression: ON
   - Early Hints: ON
   - Rocket Loader: ON (test first)

2. Caching > Configuration:
   - Caching Level: Standard
   - Browser Cache TTL: 4 hours
   - Always Online: ON
```

#### **Security Settings**
```
1. Security > Settings:
   - Security Level: Medium
   - Challenge Passage: 30 minutes
   - Browser Integrity Check: ON

2. SSL/TLS > Overview:
   - SSL/TLS encryption mode: Full (strict)
   - Always Use HTTPS: ON
   - HSTS: Enable with subdomains
```

#### **Page Rules (se necessario)**
```
1. Rules > Page Rules:
   - esempio.com/wp-admin/*
     Settings: Security Level = High, Disable Apps

   - esempio.com/wp-content/uploads/*
     Settings: Cache Level = Cache Everything, Edge Cache TTL = 1 month
```

---

## 🔄 **CONFIGURAZIONE NGINX PROXY SEPARATO**

### 1. Server Nginx Separato (Opzionale)

Se hai un Nginx separato che fa da proxy verso il container:

#### **Installazione Nginx Proxy**
```bash
# Su server separato
apt update && apt install nginx

# Configurazione proxy
nano /etc/nginx/sites-available/wordpress-proxy

# Contenuto configurazione:
server {
    listen 80;
    server_name esempio.com www.esempio.com;
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    server_name esempio.com www.esempio.com;

    # SSL Configuration (se non usi Cloudflare)
    ssl_certificate /path/to/certificate.pem;
    ssl_certificate_key /path/to/private.key;

    # Security Headers
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" always;
    add_header X-Frame-Options DENY always;
    add_header X-Content-Type-Options nosniff always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;

    # Proxy Settings
    location / {
        proxy_pass http://192.168.1.100:80;  # IP del container
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Host $host;

        # Proxy Buffers
        proxy_buffering on;
        proxy_buffer_size 128k;
        proxy_buffers 4 256k;
        proxy_busy_buffers_size 256k;

        # Timeouts
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }

    # Static files caching
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$ {
        proxy_pass http://192.168.1.100:80;
        proxy_set_header Host $host;
        expires 1y;
        add_header Cache-Control "public, immutable";
        access_log off;
    }
}

# Attiva sito
ln -sf /etc/nginx/sites-available/wordpress-proxy /etc/nginx/sites-enabled/
nginx -t && systemctl reload nginx
```

### 2. Modifica Container per Proxy

#### **Aggiorna wp-config.php nel Container**
```bash
# Nel container
nano /var/www/esempio.com/wp-config.php

# Aggiungi per proxy support
if (isset($_SERVER['HTTP_X_FORWARDED_PROTO']) && $_SERVER['HTTP_X_FORWARDED_PROTO'] == 'https') {
    $_SERVER['HTTPS'] = 'on';
    $_SERVER['SERVER_PORT'] = 443;
}

# Trusted proxies
define('WP_PROXY_TRUST', true);
```

---

## 📊 **MONITORING E MANUTENZIONE**

### 1. Script di Monitoraggio

#### **Status Check**
```bash
# Nel container
wp-status.sh

# Output atteso:
=== WordPress Status per esempio.com ===
✓ Nginx: Running
✓ PHP-FPM: Running
✓ Fail2ban: Running
CPU: 15.2%
Memory: Used: 2.1G/4.0G (52.5%)
```

#### **Log Monitoring**
```bash
# Logs WordPress
tail -f /var/log/nginx/esempio.com.access.log
tail -f /var/log/nginx/esempio.com.error.log

# Logs Sistema
tail -f /var/log/syslog
tail -f /var/log/auth.log

# PHP Logs
tail -f /var/log/php8.3-fpm.log
```

### 2. Backup e Restore

#### **Backup Completo**
```bash
# Backup container Proxmox
vzdump 200 --storage local --notes "WordPress backup $(date)"

# Backup WordPress files
cd /var/www/esempio.com
tar -czf /backup/wp-files-$(date +%Y%m%d).tar.gz .

# Backup Database
mysqldump -h DB_HOST -u DB_USER -p DB_NAME > /backup/wp-db-$(date +%Y%m%d).sql
```

### 3. Performance Monitoring

#### **Tools Integrati**
- **wp-status.sh**: Status generale sistema
- **htop**: Monitor real-time risorse
- **nginx status**: Performance web server
- **WordPress Health Check**: Dashboard WP

#### **Monitoring Esterno (Consigliato)**
- **Uptime Robot**: Monitoring uptime
- **GTmetrix**: Performance web
- **Pingdom**: Speed test
- **Cloudflare Analytics**: Traffico e security

---

## 🔧 **TROUBLESHOOTING**

### 1. Problemi Comuni

#### **Container Non Si Avvia**
```bash
# Verifica status
pct status 200

# Verifica configurazione
pct config 200

# Verifica log
tail -f /var/log/pve-firewall.log

# Fix comuni
pct start 200 --debug
```

#### **Nginx Non Risponde**
```bash
# Nel container
systemctl status nginx
nginx -t

# Restart servizi
systemctl restart nginx
systemctl restart php8.3-fpm

# Verifica porte
netstat -tulpn | grep :80
```

#### **WordPress Lento**
```bash
# Verifica OPcache
php -m | grep -i opcache

# Status OPcache
curl -s http://localhost/opcache-status.php

# Restart PHP-FPM
systemctl restart php8.3-fpm

# Verifica Redis (se configurato)
redis-cli ping
```

### 2. Debug WordPress

#### **Abilita Debug Mode**
```bash
# wp-config.php
define('WP_DEBUG', true);
define('WP_DEBUG_LOG', true);
define('WP_DEBUG_DISPLAY', false);

# Visualizza log
tail -f /var/www/esempio.com/wp-content/debug.log
```

#### **Query Debug**
```php
// Nel tema functions.php (temporaneo)
define('SAVEQUERIES', true);

// Mostra query nel footer
function show_queries() {
    global $wpdb;
    echo "<!-- Query Debug: ";
    print_r($wpdb->queries);
    echo " -->";
}
add_action('wp_footer', 'show_queries');
```

### 3. Performance Issues

#### **Memory Issues**
```bash
# Aumenta memory PHP
nano /etc/php/8.3/fpm/conf.d/99-wordpress.ini
# memory_limit = 1024M

# Restart PHP-FPM
systemctl restart php8.3-fpm
```

#### **Database Slow**
```bash
# Nel container
cd /var/www/esempio.com

# Ottimizza database
wp db optimize

# Verifica dimensioni
wp db size

# Query lente (MySQL)
mysql -h DB_HOST -u DB_USER -p -e "SHOW PROCESSLIST;"
```

---

## 🎯 **CHECKLIST FINALE**

### ✅ Pre-Produzione
- [ ] Container LXC creato e funzionante
- [ ] WordPress installato e configurato
- [ ] Plugin essenziali attivati e configurati
- [ ] Tema installato e personalizzato
- [ ] SSL certificato attivo
- [ ] Backup automatici configurati
- [ ] Cloudflare tunnel attivo
- [ ] Performance test eseguiti (GTmetrix, Pingdom)
- [ ] Security test completati
- [ ] Monitoring configurato

### ✅ Sicurezza
- [ ] Wordfence configurato e attivo
- [ ] Fail2ban in funzione
- [ ] UFW firewall attivo
- [ ] Login 2FA abilitato
- [ ] File permissions corretti
- [ ] Database prefix randomico
- [ ] wp-config.php protetto

### ✅ Performance
- [ ] OPcache attivo e configurato
- [ ] Redis object cache funzionante (se configurato)
- [ ] Nginx gzip compression attiva
- [ ] Static files caching configurato
- [ ] Database ottimizzato
- [ ] Images ottimizzate

### ✅ Cloudflare
- [ ] Tunnel attivo e stabile
- [ ] DNS records configurati
- [ ] SSL mode Full (strict)
- [ ] Security rules attive
- [ ] Performance settings ottimizzate
- [ ] Analytics configurate

---

## 📞 **SUPPORTO E RISORSE**

### Script Management
- **Status**: `wp-status.sh`
- **Logs**: `/var/log/nginx/` e `/var/log/wp-container/`
- **Config**: `/etc/nginx/sites-available/`
- **WordPress**: `/var/www/esempio.com/`

### Community e Documentazione
- **WordPress Codex**: https://codex.wordpress.org/
- **Nginx Docs**: http://nginx.org/en/docs/
- **Cloudflare Docs**: https://developers.cloudflare.com/
- **Proxmox Wiki**: https://pve.proxmox.com/wiki/

### Performance Tools
- **GTmetrix**: https://gtmetrix.com/
- **Pingdom**: https://tools.pingdom.com/
- **WebPageTest**: https://www.webpagetest.org/

---

**🚀 Con questa guida hai un setup WordPress enterprise-grade pronto per migliaia di visitatori simultanei!**