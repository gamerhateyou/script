# 🔧 Guida Recovery Container LXC WordPress

## 📋 Per chi ha già il container LXC creato

Se hai già un container LXC con installazione WordPress problematica o incompleta, usa questa procedura per risolverla.

### ⚠️ Problemi che risolve:

- ❌ `Error: Invalid user ID, email or login: 'root'`
- ❌ Plugin non installati o non attivati
- ❌ Configurazione WP-CLI incorretta
- ❌ Installazione WordPress incompleta

---

## 🚀 Procedura di Recovery

### **Passo 1: Accedi al Container**
```bash
# Dal server Proxmox
pct enter <CONTAINER_ID>
```

### **Passo 2: Scarica lo Script di Recovery**
```bash
# Opzione A: Se hai già gli script
cd /root/scripts
wget https://raw.githubusercontent.com/[your-repo]/script/fix-existing-container.sh
chmod +x fix-existing-container.sh

# Opzione B: Download diretto
curl -L -o fix-existing-container.sh https://example.com/fix-existing-container.sh
chmod +x fix-existing-container.sh
```

### **Passo 3: Esegui lo Script di Recovery**
```bash
# Esecuzione standard
./fix-existing-container.sh

# Con output verboso (per debug)
./fix-existing-container.sh -v
```

---

## 🔍 Cosa fa lo Script

### ✅ **Controlli Automatici**
- Rileva l'ambiente container LXC
- Verifica installazione WordPress esistente
- Controlla stato WP-CLI
- Identifica plugin installati

### 🔧 **Correzioni Applicate**
1. **Corregge configurazione WP-CLI**
   - Rimuove `user: root` problematico
   - Configura ambiente LXC corretto
   - Aggiunge alias e variabili

2. **Ripara installazione plugin**
   - Installa plugin mancanti
   - Attiva plugin installati ma inattivi
   - Gestisce errori di utente root

3. **Ottimizza WordPress**
   - Corregge permessi file
   - Aggiorna database
   - Flush cache e rewrite rules

---

## 📊 Output Esempio

```
🔧 RECOVERY SCRIPT - CONTAINER LXC WORDPRESS ESISTENTI
============================================================
[STEP] Rilevamento ambiente container...
[SUCCESS] Ambiente container rilevato
[SUCCESS] WordPress trovato in: /var/www/example.com/
[STEP] Correzione configurazione WP-CLI...
[SUCCESS] Configurazione WP-CLI corretta
[STEP] Riparazione installazione plugin...
[SUCCESS] Plugin attivato: wordfence
[SUCCESS] Plugin installato e attivato: wp-optimize
[SUCCESS] 🎉 Recovery completato!
```

---

## 🛠️ Comandi Post-Recovery

Dopo il recovery, puoi usare questi comandi:

```bash
# Ricarica configurazione bash
source /root/.bashrc

# Test WordPress
wp core verify-checksums

# Lista plugin attivi
wp plugin list --status=active

# Stato database
wp db check

# Flush cache
wp cache flush

# Controlla utenti admin
wp user list --role=administrator
```

---

## 🔄 Se il Recovery Fallisce

### **Opzione 1: Re-run con Debug**
```bash
./fix-existing-container.sh -v 2>&1 | tee recovery-debug.log
```

### **Opzione 2: Recovery Manuale**
```bash
# Correggi WP-CLI manualmente
rm -f /root/.wp-cli/config.yml
mkdir -p /root/.wp-cli
cat > /root/.wp-cli/config.yml << 'EOF'
path: /var/www
apache_modules:
  - mod_rewrite
disabled_commands: []
quiet: false
color: true
EOF

# Configura ambiente
export WP_CLI_ALLOW_ROOT=1
alias wp="/usr/local/bin/wp --allow-root"

# Test
wp --allow-root core version
```

### **Opzione 3: Recovery WordPress Completo**
```bash
# Vai nella directory WordPress
cd /var/www/your-domain.com

# Reinstalla core (mantiene contenuti)
wp --allow-root core download --force

# Ripara database
wp --allow-root core update-db

# Reinstalla plugin essenziali
wp --allow-root plugin install wordfence wp-optimize --activate
```

---

## 📁 File Importanti

- **Log Recovery**: `/tmp/wp-container-fix-YYYYMMDD_HHMMSS.log`
- **Config WP-CLI**: `/root/.wp-cli/config.yml`
- **Backup Config**: `/root/.wp-cli/config.yml.backup.TIMESTAMP`
- **WordPress**: `/var/www/[domain]/`

---

## ❓ FAQ

### **Q: Lo script è sicuro da eseguire?**
✅ **A**: Sì, crea backup automatici e non modifica contenuti WordPress

### **Q: Cosa succede ai miei dati?**
✅ **A**: I dati WordPress rimangono intatti, vengono solo corrette configurazioni

### **Q: Posso eseguire lo script più volte?**
✅ **A**: Sì, è idempotente e sicuro da ripetere

### **Q: Funziona su tutti i container LXC?**
✅ **A**: Sì, compatibile con Ubuntu 20.04+ e Debian 10+

---

## 🆘 Supporto

Se hai problemi:

1. **Controlla i log**: `tail -f /tmp/wp-container-fix-*.log`
2. **Verifica permessi**: Esegui come root nel container
3. **Test connessione**: `ping google.com` per verificare rete
4. **Verifica spazio**: `df -h` per controllare storage

---

*Recovery script creato per risolvere problemi comuni nei container LXC WordPress Proxmox* 🚀