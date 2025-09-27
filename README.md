# WordPress Ottimizzato per Container Proxmox

Script di installazione automatica per WordPress ottimizzato con servizi esterni (Redis, MinIO, MySQL).

## Architettura

Il container WordPress si connette a **quattro servizi esterni**:

- **Nginx Proxy Manager** - Proxy reverso con SSL automatico
- **MySQL/MariaDB** - Database esterno
- **Redis** - Cache oggetti esterno
- **MinIO** - Storage S3 compatibile esterno

## Servizi installati nel container

- **PHP 8.3-FPM** - Con JIT OPcache e ottimizzazioni 2025 (porta 9000)
- **WordPress** - Ultima versione
- **WP-CLI** - Command line interface
- **Plugin essenziali** - Cache, SEO, sicurezza

## Prerequisiti

### Container di servizi esterni

1. **Container Nginx Proxy Manager**
   - Porta 80, 443 (web) e 81 (admin) esposte
   - Configurato per proxy reverso verso container WordPress

2. **Container MySQL/MariaDB**
   - Porta 3306 esposta
   - Database e utente creati (o permessi di creazione)

3. **Container Redis**
   - Porta 6379 esposta
   - Accessibile da rete

4. **Container MinIO**
   - Porta 9000 esposta
   - Credenziali admin configurate

## Installazione

1. **Copia lo script nel container WordPress:**
   ```bash
   wget https://raw.githubusercontent.com/user/repo/main/setup-wordpress-optimized.sh
   chmod +x setup-wordpress-optimized.sh
   ```

2. **Esegui come root:**
   ```bash
   sudo ./setup-wordpress-optimized.sh
   ```

3. **Segui la configurazione guidata:**
   - Inserisci host/porta dei servizi esterni
   - Configura credenziali database, Redis, MinIO
   - Imposta admin WordPress e dominio

## Configurazione richiesta

### Database esterno
- **Host**: IP/hostname del container MySQL
- **Porta**: 3306 (default)
- **Database**: Nome database WordPress
- **Utente/Password**: Credenziali database

### Redis esterno
- **Host**: IP/hostname del container Redis
- **Porta**: 6379 (default)

### MinIO esterno
- **Host**: IP/hostname del container MinIO
- **Porta**: 9000 (default)
- **Access Key/Secret**: Credenziali MinIO admin
- **Bucket**: Nome bucket per media WordPress

### WordPress
- **URL sito**: Dominio completo (es: https://example.com)
- **Titolo sito**: Nome del sito
- **Admin**: Username, password, email amministratore

## Funzionalità

### Plugin installati automaticamente

**Cache e Performance:**
- Redis Object Cache
- Autoptimize
- WP Optimize

**SEO:**
- Yoast SEO

**Sicurezza:**
- Wordfence Security
- WP Security Audit Log

**Storage:**
- Amazon S3 and CloudFront (per MinIO)

### Ottimizzazioni applicate

**PHP:**
- OPcache abilitato
- Memory limit 256MB
- Upload fino a 64MB
- Max execution time 300s

**Nginx:**
- Compressione Gzip
- Cache file statici
- Security headers
- Ottimizzazioni WordPress

**Sistema:**
- Backup automatici giornalieri
- Logrotate configurato
- SSL Let's Encrypt (opzionale)
- Ottimizzazioni kernel

## Test e verifica

Lo script esegue test automatici di:
- Connessione database esterno
- Connessione Redis esterno
- Connessione MinIO esterno
- Funzionamento servizi locali
- Configurazione WordPress

## Backup

**Automatico giornaliero** alle 02:00:
- Database dump via mysqldump
- File WordPress compressi
- Retention 7 giorni

**Percorso backup:** `/opt/backup/`

## Monitoraggio

**Servizi locali:**
- Nginx: `systemctl status nginx`
- PHP-FPM: `systemctl status php8.3-fpm`

**Connessioni esterne:**
- Database: `mysql -h HOST -P PORT -u USER -p`
- Redis: `redis-cli -h HOST -p PORT ping`
- MinIO: `mc alias list`

## Troubleshooting

### Connessione database fallita
1. Verifica che il container MySQL sia avviato
2. Controlla IP/porta del database
3. Verifica credenziali utente
4. Testa connessione: `mysql -h HOST -P PORT -u USER -p`

### Connessione Redis fallita
1. Verifica che il container Redis sia avviato
2. Controlla IP/porta Redis
3. Testa connessione: `redis-cli -h HOST -p PORT ping`

### Connessione MinIO fallita
1. Verifica che il container MinIO sia avviato
2. Controlla IP/porta MinIO
3. Verifica credenziali access/secret key
4. Testa connessione via browser: `http://HOST:PORT`

### WordPress non accessibile
1. Verifica stato Nginx: `systemctl status nginx`
2. Controlla logs: `tail -f /var/log/nginx/error.log`
3. Verifica DNS/dominio configurato
4. Controlla firewall container

## File di configurazione

- **WordPress**: `/var/www/html/wp-config.php`
- **Nginx**: `/etc/nginx/sites-available/wordpress`
- **PHP**: `/etc/php/8.3/fpm/conf.d/99-wordpress-2025.ini`
- **Backup**: `/opt/backup/wordpress-backup.sh`

## Sicurezza

**WordPress hardening applicato:**
- File editing disabilitato
- Force SSL admin
- Security headers Nginx
- Hide PHP version
- Blocco accesso file sensibili

**Aggiornamenti:**
- WordPress core: automatici minori
- Plugin: manuali
- PHP/sistema: manuali

## Performance

**Aspettative di performance:**
- Time to First Byte < 200ms
- Cache hit ratio Redis > 90%
- Page load time < 2s
- GTMetrix/PageSpeed > 90

**Monitoraggio performance:**
- Plugin Query Monitor
- Redis cache statistics
- Nginx access logs
- PHP-FPM status page