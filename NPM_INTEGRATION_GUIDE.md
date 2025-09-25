# 🔄 Nginx Proxy Manager - Integrazione Completa

## ✅ **Modifiche Implementate nel Script Principale**

Lo script WordPress ora supporta **Nginx Proxy Manager** come **opzione predefinita** con rilevamento automatico e configurazione unificata.

---

## 🎯 **Caratteristiche Integrate**

### **1. Rilevamento Automatico NPM**
```bash
🔄 Configurazione Proxy/SSL:
Hai Nginx Proxy Manager (NPM) o altro reverse proxy? [Y/n]: Y

📋 Modalità NPM Backend rilevata:
Porta interna WordPress [8080]: 8080
NPM gestisce SSL/certificati? [Y/n]: Y
```

### **2. Configurazione Nginx Adaptive**
- **NPM Backend Mode**: Porta personalizzata (8080), headers proxy, health check
- **Standalone Mode**: Configurazione tradizionale porta 80

### **3. WordPress NPM-Ready**
- **Proxy headers** automatici in wp-config.php
- **HTTPS detection** via X-Forwarded-Proto
- **Real IP** preservation
- **Force SSL Admin** when behind NPM

---

## 🏗️ **Architettura Supportata**

### **Setup NPM + WordPress Container:**
```
Internet → NPM Container (SSL/Proxy) → WordPress Container (Backend:8080)
```

### **Setup Tradizionale:**
```
Internet → WordPress Container (Frontend:80/443)
```

---

## ⚙️ **File Modificati**

### **1. `lib/wordpress.sh`**

#### **Configurazione Parametri (Linea 187-216):**
```bash
# NPM Detection and Configuration
read -p "Hai Nginx Proxy Manager (NPM)? [Y/n]: " USE_NPM

if [ "$USE_NPM" = true ]; then
    INTERNAL_PORT="${INTERNAL_PORT:-8080}"
    NPM_MODE=true
    SETUP_SSL=false  # NPM gestisce SSL
fi
```

#### **Nginx Configuration (Linea 498-726):**
```bash
if [ "$NPM_MODE" = true ]; then
    # NPM Backend Config
    listen ${INTERNAL_PORT};
    # Proxy headers support
    set_real_ip_from 172.16.0.0/12;
    real_ip_header X-Forwarded-For;
else
    # Traditional Config
    listen 80;
fi
```

#### **WordPress NPM Config (Linea 941-995):**
```php
// Trust proxy headers from NPM
if (isset($_SERVER['HTTP_X_FORWARDED_PROTO']) && $_SERVER['HTTP_X_FORWARDED_PROTO'] === 'https') {
    $_SERVER['HTTPS'] = 'on';
    define('FORCE_SSL_ADMIN', true);
}
```

---

## 🚀 **Come Usare con NPM**

### **1. Crea Container WordPress:**
```bash
# Nel container LXC
cd /root/scripts
./wp-install.sh

# Quando chiesto:
# "Hai Nginx Proxy Manager (NPM)?" → Y
# "Porta interna WordPress" → 8080
# "NPM gestisce SSL?" → Y
```

### **2. Configura NPM Proxy Host:**
```
Domain Names: your-domain.com
Forward Hostname/IP: [IP_CONTAINER_WORDPRESS]
Forward Port: 8080
✅ Cache Assets
✅ Block Common Exploits
✅ Websockets Support
```

### **3. Configura SSL Certificate:**
```
✅ Force SSL
✅ HTTP/2 Support
Certificate: Let's Encrypt
```

---

## 🧪 **Endpoint di Test**

### **Health Check:**
```bash
curl http://IP_CONTAINER:8080/health
# Output: "healthy"
```

### **Status Check:**
```bash
curl http://IP_CONTAINER:8080/status
# Output: "WordPress Backend Active - Port 8080"
```

### **WordPress Test:**
```bash
curl -H "Host: your-domain.com" http://IP_CONTAINER:8080
# Output: WordPress homepage
```

---

## 🔧 **Configurazioni Nginx Generate**

### **NPM Backend Mode:**
```nginx
server {
    listen 8080;
    server_name domain.com www.domain.com localhost;

    # NPM Headers Support
    set_real_ip_from 172.16.0.0/12;
    set_real_ip_from 192.168.0.0/16;
    set_real_ip_from 10.0.0.0/8;
    real_ip_header X-Forwarded-For;
    real_ip_recursive on;

    # Rate limiting for admin
    location /wp-admin/ {
        limit_req zone=wp_admin burst=10 nodelay;
    }

    # Health check
    location = /health {
        return 200 "healthy\n";
    }
}
```

### **Standalone Mode:**
```nginx
server {
    listen 80;
    server_name domain.com www.domain.com;

    # Traditional configuration
    # SSL handled by certbot
}
```

---

## 📊 **Vantaggi NPM Integration**

### **✅ Sicurezza:**
- **SSL centralizzato** in NPM
- **Rate limiting** applicato
- **Real IP** preservation
- **Headers proxy** sicuri

### **✅ Performance:**
- **Static caching** in NPM
- **GZIP compression** ottimizzata
- **HTTP/2** support
- **CDN-ready** configuration

### **✅ Gestione:**
- **Multi-domain** con un NPM
- **Certificati automatici** Let's Encrypt
- **Monitoring** centralizzato
- **Failover** capabilities

---

## 🔄 **Retrocompatibilità**

- ✅ **Funziona ancora** in modalità standalone
- ✅ **SSL tradizionale** con certbot mantenuto
- ✅ **Zero breaking changes** per installazioni esistenti
- ✅ **Upgrade path** smooth per NPM

---

## 💡 **Best Practices NPM**

### **1. Network Setup:**
```bash
# NPM e WordPress sulla stessa rete Docker/LXC
# o configurare routing appropriato
```

### **2. Security Headers:**
```bash
# NPM aggiunge automaticamente:
# - X-Frame-Options
# - X-Content-Type-Options
# - X-XSS-Protection
```

### **3. Cache Strategy:**
```bash
# NPM cache per static assets
# WordPress cache per dynamic content
# Database cache separato
```

---

## 🆘 **Troubleshooting**

### **Problema: NPM non raggiunge WordPress**
```bash
# Test connettività
curl http://IP_CONTAINER:8080/health

# Check nginx status
systemctl status nginx

# Check porta in ascolto
netstat -tlnp | grep 8080
```

### **Problema: SSL Loop Redirect**
```bash
# Verifica header proxy in wp-config.php
grep -A10 "NPM PROXY" /var/www/domain/wp-config.php

# Test headers NPM
curl -H "X-Forwarded-Proto: https" http://IP:8080
```

---

*Nginx Proxy Manager integrato nel script WordPress principale - Zero configurazione aggiuntiva richiesta* 🎉