#!/bin/bash

# =============================================================================
# QUICK FIX - WP-CLI Root User Error
# Script veloce per risolvere "Invalid user ID, email or login: 'root'"
# =============================================================================

set -euo pipefail

echo "🔧 QUICK FIX - WP-CLI Root User Error"
echo "============================================"

# Controlla se siamo root
if [ "$EUID" -ne 0 ]; then
    echo "❌ Esegui come root: sudo $0"
    exit 1
fi

echo "🔍 Diagnostica problema..."

# Backup configurazione WP-CLI esistente
if [ -f "/root/.wp-cli/config.yml" ]; then
    echo "💾 Backup configurazione esistente..."
    cp "/root/.wp-cli/config.yml" "/root/.wp-cli/config.yml.backup.$(date +%Y%m%d_%H%M%S)"
fi

# Crea configurazione WP-CLI corretta
echo "🔧 Correzione configurazione WP-CLI..."
mkdir -p /root/.wp-cli

cat > /root/.wp-cli/config.yml << 'EOF'
# WP-CLI configuration for LXC container (FIXED)
path: /var/www
apache_modules:
  - mod_rewrite
disabled_commands: []
quiet: false
color: true
EOF

# Configura ambiente
echo "⚙️ Configurazione ambiente..."
export WP_CLI_CONFIG_PATH="/root/.wp-cli/config.yml"
export WP_CLI_ALLOW_ROOT=1

# Aggiungi a bashrc se non presente
if ! grep -q "WP_CLI_ALLOW_ROOT" /root/.bashrc 2>/dev/null; then
    echo 'export WP_CLI_CONFIG_PATH="/root/.wp-cli/config.yml"' >> /root/.bashrc
    echo 'export WP_CLI_ALLOW_ROOT=1' >> /root/.bashrc
    echo 'alias wp="/usr/local/bin/wp --allow-root"' >> /root/.bashrc
    echo "✅ Configurazione aggiunta a .bashrc"
fi

# Test WP-CLI
echo "🧪 Test WP-CLI..."
if command -v wp >/dev/null 2>&1; then
    if wp --allow-root --info >/dev/null 2>&1; then
        echo "✅ WP-CLI funziona correttamente!"
    else
        echo "⚠️ WP-CLI installato ma con problemi"
    fi
else
    echo "❌ WP-CLI non installato"
    echo "💡 Installa con: curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar && chmod +x wp-cli.phar && mv wp-cli.phar /usr/local/bin/wp"
fi

# Test WordPress se presente
if [ -d "/var/www" ]; then
    echo "🔍 Ricerca installazioni WordPress..."

    for wp_dir in /var/www/*/; do
        if [ -f "$wp_dir/wp-config.php" ]; then
            echo "📁 WordPress trovato: $wp_dir"
            cd "$wp_dir"

            # Test base
            if wp --allow-root core version >/dev/null 2>&1; then
                WP_VERSION=$(wp --allow-root core version 2>/dev/null)
                echo "✅ WordPress $WP_VERSION - OK"

                # Test utenti
                ADMIN_USER=$(wp --allow-root user list --role=administrator --field=user_login --format=csv 2>/dev/null | head -1)
                if [ -n "$ADMIN_USER" ]; then
                    echo "👤 Utente admin: $ADMIN_USER"
                else
                    echo "⚠️ Nessun utente amministratore trovato"
                fi
            else
                echo "❌ Problemi con WordPress in $wp_dir"
            fi
            break
        fi
    done
fi

echo
echo "✅ QUICK FIX COMPLETATO!"
echo "========================="
echo
echo "🔄 Per applicare le modifiche:"
echo "   source /root/.bashrc"
echo
echo "🧪 Test comandi:"
echo "   wp --allow-root core version"
echo "   wp --allow-root plugin list"
echo
echo "💡 Se hai ancora problemi, usa lo script completo:"
echo "   ./fix-existing-container.sh"
echo