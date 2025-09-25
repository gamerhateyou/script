# WordPress LXC Container Creator - Versione Modulare

Script modulare e ottimizzato per la creazione automatica di container LXC WordPress su Proxmox VE.

## 🚀 Caratteristiche

### ✨ Nuove Funzionalità Modulari
- **Architettura modulare** - Codice organizzato in librerie separate
- **Configurazione centralizzata** - File di configurazione modificabili
- **Gestione errori avanzata** - Rollback automatico in caso di errore
- **Logging completo** - Tracciamento dettagliato di tutte le operazioni
- **Validazione input** - Controlli rigorosi su tutti i parametri
- **Manutenibilità elevata** - Codice seguendo principi DRY e KISS

### 🔧 Stack Tecnologico
- **OS**: Ubuntu 24.04 LTS
- **Web Server**: Nginx (ottimizzato per performance)
- **PHP**: 8.3 con FPM e OPcache
- **Database**: MySQL esterno + Redis Object Cache (opzionale)
- **SSL**: Let's Encrypt automatico
- **Sicurezza**: Fail2ban + UFW + Wordfence

### 🛡️ Sicurezza Integrata
- Firewall UFW preconfigurato
- Fail2ban con regole WordPress
- File permissions corretti
- Plugin sicurezza preinstallati
- SSL/TLS automatico

## 📁 Struttura del Progetto

```
script/
├── create-wordpress-container.sh    # Script principale
├── config/
│   └── default.conf                # Configurazione predefinita
├── lib/
│   ├── utils.sh                    # Funzioni utilities
│   ├── proxmox.sh                  # Funzioni Proxmox VE
│   └── wordpress.sh                # Funzioni WordPress
└── README.md                       # Questa documentazione
```

## 🔧 Requisiti

### Sistema Host (Proxmox VE)
- Proxmox VE 7.0+
- Accesso root
- Connessione internet
- Storage con almeno 50GB disponibili

### Servizi Esterni Richiesti
- **Server MySQL/MariaDB** con database e utente configurati
- **Server Redis** (opzionale, per object cache)
- **Server MinIO** (opzionale, per media storage)

## 🚀 Installazione Rapida

### 1. Download e Preparazione
```bash
# Download script
wget -O create-wordpress-container.sh https://your-repo/create-wordpress-container.sh
chmod +x create-wordpress-container.sh

# Oppure clona il repository completo
git clone https://your-repo/wordpress-lxc.git
cd wordpress-lxc
```

### 2. Esecuzione Standard
```bash
# Esecuzione interattiva
./create-wordpress-container.sh

# Con debug abilitato
./create-wordpress-container.sh --debug

# Con configurazione personalizzata
./create-wordpress-container.sh --config config/production.conf
```

### 3. Completamento nel Container
```bash
# Accedi al container creato
pct enter <CONTAINER_ID>

# Esegui installazione WordPress
cd /root/scripts
./wp-install.sh
```

## ⚙️ Configurazione

### File di Configurazione
Modifica `config/default.conf` per personalizzare i valori predefiniti:

```bash
# Template settings
DEFAULT_TEMPLATE_NAME="ubuntu-24.04-standard_24.04-2_amd64.tar.zst"
DEFAULT_MEMORY=4096
DEFAULT_DISK_SIZE=50
DEFAULT_CORES=4

# Backup settings
DEFAULT_BACKUP_ENABLED=true
DEFAULT_BACKUP_TIME="0 2 * * *"
DEFAULT_BACKUP_RETENTION=7
```

### Configurazioni Personalizzate
Crea file personalizzati in `config/`:

```bash
# config/production.conf
DEFAULT_MEMORY=8192
DEFAULT_DISK_SIZE=100
DEFAULT_BACKUP_RETENTION=30

# config/development.conf
DEFAULT_MEMORY=2048
DEFAULT_DISK_SIZE=20
DEFAULT_BACKUP_ENABLED=false
```

## 🛠️ Utilizzo Avanzato

### Parametri Script Principale

```bash
./create-wordpress-container.sh [OPTIONS]

Options:
  -h, --help          Mostra help
  -d, --debug         Abilita debug mode
  -c, --config FILE   Usa configurazione personalizzata
```

### Esempi d'Uso

```bash
# Ambiente di produzione
./create-wordpress-container.sh --config config/production.conf

# Ambiente di sviluppo con debug
./create-wordpress-container.sh --debug --config config/development.conf

# Test con valori personalizzati
./create-wordpress-container.sh --debug
```

## 🎯 Parametri di Installazione

### Container LXC
Durante l'esecuzione, verranno richiesti:

- **ID Container**: Numero univoco (100-999999)
- **Hostname**: Nome del container
- **Password root**: Password di accesso
- **Risorse**: RAM, Disk, CPU cores
- **Rete**: IP, Gateway, DNS
- **Storage**: Storage Proxmox per il container

### WordPress (nel container)
Durante l'installazione WordPress:

- **Sito**: Nome e dominio
- **Database**: IP server, credenziali
- **Admin**: Username, password, email
- **Servizi opzionali**: Redis, MinIO
- **SSL**: Configurazione automatica

## 🔍 Monitoraggio e Manutenzione

### Script di Status
```bash
# Nel container, dopo installazione WordPress
wp-status.sh
```

Output esempio:
```
=== WordPress Status per example.com ===
=== Servizi ===
✓ Nginx: Running
✓ PHP-FPM: Running
✓ Fail2ban: Running

=== Performance ===
CPU: 15.2%
Memory: Used: 2.1G/4.0G (52.5%)
Disk: 8.1G/45G (18%)

=== WordPress ===
Version: 6.4.1
Plugins: 6 active
```

### Comandi Utili

```bash
# Proxmox Host
pct status <ID>              # Status container
pct enter <ID>               # Accesso container
pct start/stop <ID>          # Start/stop container
vzdump <ID>                  # Backup manuale

# Nel Container
systemctl status nginx       # Status web server
tail -f /var/log/nginx/error.log  # Log errori
wp core update               # Aggiorna WordPress
wp plugin list               # Lista plugin
```

## 📊 Backup e Sicurezza

### Backup Automatici
- **Frequenza**: Giornaliera alle 2:00 AM (configurabile)
- **Retention**: 7 giorni (configurabile)
- **Tipo**: Snapshot LXC con compressione
- **Storage**: Configurabile per storage

### Sicurezza
- **Firewall**: UFW con regole HTTP/HTTPS/SSH
- **Fail2ban**: Protezione login WordPress
- **SSL**: Let's Encrypt automatico
- **Updates**: Core e plugin aggiornamenti automatici
- **Permissions**: File system hardening

### Manutenzione Programmata
Automaticamente configurata:
- Aggiornamenti core WordPress (domenica 2:00)
- Aggiornamenti plugin (domenica 2:30)
- Ottimizzazione database (domenica 4:00)
- Pulizia transients (giornaliera 5:00)

## 🐛 Troubleshooting

### Problemi Comuni

#### Container non si avvia
```bash
# Verifica configurazione
pct config <ID>

# Controlla log
pct enter <ID>
journalctl -xe
```

#### WordPress non accessibile
```bash
# Nel container
systemctl status nginx php8.3-fpm
nginx -t
```

#### Database non raggiungibile
```bash
# Test connessione
mysql -h<IP> -u<USER> -p<PASS> <DB_NAME>

# Verifica firewall database server
ufw status
```

#### SSL non funziona
```bash
# Verifica certificati
certbot certificates

# Rinnovo manuale
certbot renew --dry-run
```

### Log Files
- **Script**: `/tmp/wp-container-YYYYMMDD_HHMMSS.log`
- **Nginx**: `/var/log/nginx/domain.error.log`
- **PHP**: `/var/log/php8.3-fpm.log`
- **WordPress**: `/var/www/domain/wp-content/debug.log`

## 🔧 Personalizzazione e Estensione

### Aggiungere Nuove Funzionalità

#### 1. Estendere Utilities
```bash
# lib/utils.sh
my_custom_function() {
    log_info "Funzione personalizzata"
    # Il tuo codice qui
}
```

#### 2. Aggiungere Configurazioni
```bash
# config/custom.conf
CUSTOM_SETTING="valore"
CUSTOM_FEATURE_ENABLED=true
```

#### 3. Modificare WordPress Script
```bash
# lib/wordpress.sh - funzione generate_wordpress_script()
# Aggiungi le tue personalizzazioni al template
```

### Profili Ambiente
Crea profili specifici per diversi ambienti:

```bash
# config/staging.conf
DEFAULT_MEMORY=2048
DEFAULT_SSL_ENABLED=false
DEFAULT_BACKUP_ENABLED=false

# config/production.conf
DEFAULT_MEMORY=8192
DEFAULT_SSL_ENABLED=true
DEFAULT_BACKUP_RETENTION=30
```

## 📈 Performance e Ottimizzazione

### Ottimizzazioni Incluse

#### Nginx
- Worker processes automatici
- Compressione gzip ottimizzata
- Cache statica
- Security headers

#### PHP 8.3
- OPcache configurato
- Memory limit 512MB
- Pool FPM dedicato
- Timeout ottimizzati

#### WordPress
- Object cache Redis
- Plugin performance
- Database optimization
- Static file caching

### Tuning Personalizzato
Modifica i template in `lib/wordpress.sh` per:
- Configurazioni PHP specifiche
- Regole Nginx personalizzate
- Plugin aggiuntivi
- Ottimizzazioni database

## 🤝 Contributi

### Struttura per Contributi
1. Mantieni la modularità
2. Aggiungi test per nuove funzioni
3. Aggiorna documentazione
4. Segui lo stile di logging esistente

### Pull Request
- Descrizione dettagliata delle modifiche
- Test in ambiente Proxmox
- Compatibilità con versioni esistenti

## 📜 Licenza

Script distribuito sotto licenza MIT. Vedi file LICENSE per dettagli.

## 📞 Supporto

### Issues
- Problemi di installazione
- Bug report
- Richieste di funzionalità

### Community
- Condivisione configurazioni
- Best practices
- Ottimizzazioni

---

**Versione**: 2025.09
**Autore**: Script WordPress LXC Team
**Ultima modifica**: Settembre 2025