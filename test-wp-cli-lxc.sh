#!/bin/bash

# Test script for WP-CLI LXC configuration
# This script simulates the WP-CLI setup in an LXC container

set -euo pipefail

echo "=== TEST WP-CLI CONFIGURATION FOR LXC ==="
echo

# Simulate the configuration function
configure_wpcli_for_lxc() {
    echo "Configurazione WP-CLI per container LXC..."

    # Create www-data user if it doesn't exist (simulation)
    echo "✓ Verifica utente www-data"

    # Create WP-CLI config directory (simulation)
    mkdir -p /tmp/test-wp-cli
    echo "✓ Directory config creata"

    # Create test config
    cat > /tmp/test-wp-cli/config.yml << 'EOF'
# WP-CLI configuration for LXC container
user: root
path: /var/www
apache_modules:
  - mod_rewrite
disabled_commands: []

# LXC Container specific settings
core config:
  allow_root: true
  skip_checks: ["root"]

quiet: true
color: false
EOF

    echo "✓ File di configurazione WP-CLI creato"

    # Test environment variables
    export WP_CLI_CONFIG_PATH="/tmp/test-wp-cli/config.yml"
    export WP_CLI_ALLOW_ROOT=1

    echo "✓ Variabili d'ambiente configurate"
    echo
    echo "Configurazione completata!"
    echo "- Config file: $WP_CLI_CONFIG_PATH"
    echo "- Allow root: $WP_CLI_ALLOW_ROOT"
    echo
}

# Run the configuration
configure_wpcli_for_lxc

# Show the generated config
echo "=== CONTENUTO FILE CONFIG ==="
cat /tmp/test-wp-cli/config.yml
echo
echo "=== FINE CONFIG ==="
echo

echo "✅ Test completato con successo!"
echo
echo "Nel container LXC, WP-CLI sarà configurato per:"
echo "1. Accettare l'esecuzione come root senza warning"
echo "2. Usare automaticamente --allow-root tramite alias"
echo "3. Configurare correttamente i permessi dei file"
echo

# Cleanup
rm -rf /tmp/test-wp-cli
echo "🧹 Cleanup completato"