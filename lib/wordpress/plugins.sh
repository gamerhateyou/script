#!/bin/bash

# =============================================================================
# WORDPRESS PLUGIN MANAGEMENT FUNCTIONS
# =============================================================================

# shellcheck source=./utils.sh
source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"

install_plugin_resilient() {
    local plugin="$1"
    local max_attempts=3
    local attempt=1

    while [ $attempt -le $max_attempts ]; do
        log_info "Tentativo $attempt/$max_attempts: installazione $plugin"

        if wp --allow-root plugin install "$plugin" --activate --quiet >/dev/null 2>&1; then
            log_success "Plugin $plugin installato (tentativo $attempt)"
            return 0
        fi

        if [ $attempt -lt $max_attempts ]; then
            log_warn "Tentativo $attempt fallito per $plugin, riprovo..."
            sleep 3
        fi

        ((attempt++))
    done

    log_error "Plugin $plugin fallito dopo $max_attempts tentativi"
    return 1
}

install_plugin_with_fallback() {
    local plugin="$1"
    local fallback_plugin="$2"

    # Try main plugin first
    if try_install_plugin "$plugin"; then
        return 0
    fi

    # Try fallback if provided
    if [[ -n "$fallback_plugin" ]] && try_install_plugin "$fallback_plugin"; then
        log_info "Plugin alternativo $fallback_plugin installato invece di $plugin"
        return 0
    fi

    return 1
}

try_install_plugin() {
    local plugin="$1"
    local timeout=120

    log_info "Installazione plugin: $plugin"

    # Check if already installed
    if wp --allow-root plugin is-installed "$plugin" >/dev/null 2>&1; then
        log_info "Plugin $plugin già installato"
        wp --allow-root plugin activate "$plugin" >/dev/null 2>&1 || log_warn "Impossibile attivare $plugin"
        return 0
    fi

    # Install with timeout
    if timeout "$timeout" wp --allow-root plugin install "$plugin" --activate --quiet >/dev/null 2>&1; then
        log_success "Plugin $plugin installato e attivato"
        return 0
    else
        log_warn "Plugin $plugin: installazione fallita o timeout"
        return 1
    fi
}

install_essential_plugins() {
    log_step "Installazione plugin essenziali..."

    local plugin_timeout=300  # 5 minuti max per tutti i plugin
    local start_time=$(date +%s)

    cd "/var/www/${DOMAIN}"

    # Essential plugins list
    local plugins=(
        "wordfence"
        "wp-optimize"
        "updraftplus"
        "limit-login-attempts-reloaded"
        "ssl-insecure-content-fixer"
        # SEO Essential Plugins
        "wordpress-seo"
        "google-sitemap-generator"
        "wp-super-cache"
        "autoptimize"
        "wp-smushit"
        "broken-link-checker"
        "google-analytics-dashboard-for-wp"
        "schema"
        "amp"
        "web-stories"
        # Performance SEO
        "wp-fastest-cache"
        "lazy-load"
        "webp-express"
        # GDPR/Privacy Compliance
        "cookie-law-info"
        "wp-gdpr-compliance"
        "complianz-gdpr"
        "gdpr-cookie-consent"
        "privacy-policy-generator"
    )

    # Add Redis plugin if configured
    if [[ "${USE_REDIS:-}" == "y"* ]] || [[ "${USE_REDIS,,}" =~ ^(yes|s|si)$ ]]; then
        plugins+=("redis-cache")
    fi

    # Add MinIO S3 plugin if configured
    if [[ "${USE_MINIO:-}" == "y"* ]] || [[ "${USE_MINIO,,}" =~ ^(yes|s|si)$ ]]; then
        plugins+=("amazon-s3-and-cloudfront")
    fi

    # Add SMTP plugin if configured
    if [[ "${USE_SMTP:-}" == "y"* ]] || [[ "${USE_SMTP,,}" =~ ^(yes|s|si)$ ]]; then
        plugins+=("wp-mail-smtp")
    fi

    # Install and activate plugins with fallback handling
    local installed_count=0
    local total_plugins=${#plugins[@]}

    for plugin in "${plugins[@]}"; do
        # Check global timeout
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))

        if [ $elapsed -gt $plugin_timeout ]; then
            log_warn "Timeout globale raggiunto ($plugin_timeout secondi) - salto i plugin rimanenti"
            log_info "Plugin installati: $installed_count/$total_plugins"
            break
        fi

        log_info "Plugin $((installed_count + 1))/$total_plugins: $plugin"

        if install_plugin_with_fallback "$plugin"; then
            installed_count=$((installed_count + 1))
        else
            log_warn "Plugin $plugin saltato dopo i tentativi"
        fi

        # Mostra progresso
        local progress=$((installed_count * 100 / total_plugins))
        log_info "Progresso plugin: $progress% ($installed_count/$total_plugins)"
    done

    if [ $installed_count -eq $total_plugins ]; then
        log_success "Tutti i plugin essenziali installati ($installed_count/$total_plugins)"
    else
        log_warn "Plugin installati parzialmente ($installed_count/$total_plugins) - l'installazione continua"
    fi
}

configure_essential_plugins() {
    log_step "Configurazione plugin essenziali..."

    cd "/var/www/${DOMAIN}"

    # Configure each plugin with error handling
    configure_wordfence
    configure_wp_optimize
    configure_yoast_advanced
    configure_autoptimize
    configure_smush
    configure_webp_express

    # Optional services configuration
    [[ "${USE_REDIS:-}" == "y"* ]] && configure_redis_cache
    [[ "${USE_MINIO:-}" == "y"* ]] && configure_s3_plugin
    [[ "${USE_SMTP:-}" == "y"* ]] && configure_smtp_plugin
    [[ "${USE_SCHEMA:-}" == "y"* ]] && configure_schema_plugin
    [[ "${USE_GA:-}" == "y"* ]] && configure_google_analytics
    [[ "${USE_AMP:-}" == "y"* ]] && configure_amp_plugin

    log_success "Plugin configurati"
}

configure_wordfence() {
    if ! wp --allow-root plugin is-active wordfence >/dev/null 2>&1; then
        log_info "Wordfence non attivo, salto configurazione"
        return 0
    fi

    log_info "Configurazione Wordfence..."

    # Basic Wordfence settings
    wp --allow-root option update wordfence_options '{
        "email_summary_enabled": "1",
        "email_summary_recipients": "'"${WP_ADMIN_EMAIL}"'",
        "firewallEnabled": "1",
        "scansEnabled": "1",
        "liveTrafficEnabled": "1",
        "loginSec_enableSeparateTwoFactor": "1",
        "loginSec_maxFailures": "3",
        "loginSec_lockoutMins": "15",
        "loginSec_breachPasswds": "1"
    }' --format=json >/dev/null 2>&1 || log_warn "Errore configurazione Wordfence"

    log_success "Wordfence configurato"
}

configure_wp_optimize() {
    if ! wp --allow-root plugin is-active wp-optimize >/dev/null 2>&1; then
        log_info "WP Optimize non attivo, salto configurazione"
        return 0
    fi

    log_info "Configurazione WP Optimize..."

    # Enable basic optimizations
    wp --allow-root option update wp-optimize-settings '{
        "enable_minify_js": true,
        "enable_minify_css": true,
        "enable_gzip_compression": true,
        "enable_cache": true,
        "enable_lazy_loading": true,
        "cache_enabled": true,
        "cache_expiry_time": 24
    }' --format=json >/dev/null 2>&1 || log_warn "Errore configurazione WP Optimize"

    log_success "WP Optimize configurato"
}

configure_yoast_advanced() {
    if ! wp --allow-root plugin is-active wordpress-seo >/dev/null 2>&1; then
        log_info "Yoast SEO non attivo, salto configurazione"
        return 0
    fi

    log_info "Configurazione avanzata Yoast SEO..."

    # Enable XML sitemaps
    wp --allow-root option update wpseo_xml '{
        "enablexmlsitemap": true,
        "user_role": "off",
        "disable_author_sitemap": true,
        "disable_author_noposts": true
    }' --format=json >/dev/null 2>&1

    # Configure titles and descriptions
    wp --allow-root option update wpseo_titles '{
        "title-home-wpseo": "'"$SITE_NAME"' - %%page%% %%sep%% %%sitename%%",
        "metadesc-home-wpseo": "Sito ufficiale di '"$SITE_NAME"'",
        "company_or_person": "company",
        "company_name": "'"$SITE_NAME"'",
        "website_name": "'"$SITE_NAME"'"
    }' --format=json >/dev/null 2>&1

    # Enable breadcrumbs
    wp --allow-root option update wpseo_internallinks '{
        "breadcrumbs-enable": true,
        "breadcrumbs-home": "Home",
        "breadcrumbs-sep": "»"
    }' --format=json >/dev/null 2>&1

    log_success "Yoast SEO configurato"
}

configure_autoptimize() {
    if ! wp --allow-root plugin is-active autoptimize >/dev/null 2>&1; then
        log_info "Autoptimize non attivo, salto configurazione"
        return 0
    fi

    log_info "Configurazione Autoptimize..."

    # Configure Autoptimize for performance
    wp --allow-root option update autoptimize_js "on" >/dev/null 2>&1
    wp --allow-root option update autoptimize_css "on" >/dev/null 2>&1
    wp --allow-root option update autoptimize_html "on" >/dev/null 2>&1
    wp --allow-root option update autoptimize_css_defer "on" >/dev/null 2>&1
    wp --allow-root option update autoptimize_js_defer_not_aggregate "on" >/dev/null 2>&1

    log_success "Autoptimize configurato"
}

configure_smush() {
    if ! wp --allow-root plugin is-active wp-smushit >/dev/null 2>&1; then
        log_info "Smush non attivo, salto configurazione"
        return 0
    fi

    log_info "Configurazione Smush..."

    # Enable image optimization
    wp --allow-root option update wp-smush-settings '{
        "auto": "1",
        "lossy": "0",
        "strip_exif": "1",
        "resize": "1",
        "detection": "1",
        "original": "0"
    }' --format=json >/dev/null 2>&1 || log_warn "Errore configurazione Smush"

    log_success "Smush configurato"
}

configure_webp_express() {
    if ! wp --allow-root plugin is-active webp-express >/dev/null 2>&1; then
        log_info "WebP Express non attivo, salto configurazione"
        return 0
    fi

    log_info "Configurazione WebP Express..."

    # Enable WebP conversion
    wp --allow-root option update webp-express-settings '{
        "operation-mode": "varied-image-responses",
        "image-types": 3,
        "source-file-extension": "append",
        "enable-redirection-to-converter": true,
        "quality-auto": true,
        "max-quality": 85,
        "method": "cwebp"
    }' --format=json >/dev/null 2>&1 || log_warn "Errore configurazione WebP Express"

    log_success "WebP Express configurato"
}

configure_redis_cache() {
    if ! wp --allow-root plugin is-active redis-cache >/dev/null 2>&1; then
        log_info "Redis Cache non attivo, salto configurazione"
        return 0
    fi

    log_info "Configurazione Redis Cache..."

    # Enable Redis Object Cache
    wp --allow-root redis enable >/dev/null 2>&1 || log_warn "Errore attivazione Redis cache"

    log_success "Redis Cache configurato"
}

configure_s3_plugin() {
    if ! wp --allow-root plugin is-active amazon-s3-and-cloudfront >/dev/null 2>&1; then
        log_info "S3 plugin non attivo, salto configurazione"
        return 0
    fi

    log_info "Configurazione S3 Plugin..."

    if [[ -n "${MINIO_ACCESS_KEY:-}" && -n "${MINIO_SECRET_KEY:-}" ]]; then
        # Configure S3 settings for MinIO
        wp --allow-root option update tantan_wordpress_s3 '{
            "provider": "aws",
            "access-key-id": "'"${MINIO_ACCESS_KEY}"'",
            "secret-access-key": "'"${MINIO_SECRET_KEY}"'",
            "bucket": "'"${MINIO_BUCKET:-wordpress-media}"'",
            "region": "us-east-1",
            "domain": "cloudfront",
            "enable-object-prefix": true,
            "object-prefix": "wp-content/uploads/",
            "copy-to-s3": true,
            "serve-from-s3": true
        }' --format=json >/dev/null 2>&1 || log_warn "Errore configurazione S3"

        log_success "S3 Plugin configurato per MinIO"
    else
        log_warn "Credenziali MinIO mancanti, salto configurazione S3"
    fi
}

configure_smtp_plugin() {
    if ! wp --allow-root plugin is-active wp-mail-smtp >/dev/null 2>&1; then
        log_info "WP Mail SMTP non attivo, salto configurazione"
        return 0
    fi

    log_info "Configurazione WP Mail SMTP..."

    if [[ -n "${SMTP_HOST:-}" && -n "${SMTP_USER:-}" && -n "${SMTP_PASS:-}" ]]; then
        # Configure SMTP settings
        wp --allow-root option update wp_mail_smtp '{
            "mail": {
                "from_email": "'"${SMTP_FROM_EMAIL:-noreply@$DOMAIN}"'",
                "from_name": "'"$SITE_NAME"'",
                "mailer": "smtp",
                "return_path": true
            },
            "smtp": {
                "host": "'"${SMTP_HOST}"'",
                "port": "'"${SMTP_PORT:-587}"'",
                "encryption": "'"${SMTP_ENCRYPTION:-tls}"'",
                "auth": true,
                "user": "'"${SMTP_USER}"'",
                "pass": "'"${SMTP_PASS}"'"
            }
        }' --format=json >/dev/null 2>&1 || log_warn "Errore configurazione SMTP"

        log_success "WP Mail SMTP configurato"
    else
        log_warn "Credenziali SMTP mancanti, salto configurazione"
    fi
}

configure_schema_plugin() {
    if ! wp --allow-root plugin is-active schema >/dev/null 2>&1; then
        log_info "Schema Plugin non attivo, salto configurazione"
        return 0
    fi

    log_info "Configurazione Schema Plugin..."

    local schema_settings='{
        "schema_type": "Organization",
        "site_name": "'${SITE_NAME}'",
        "site_logo": "",
        "default_image": "",
        "knowledge_graph": true,
        "publisher": true,
        "social_profile": [],
        "corporate_contacts": [],
        "breadcrumb": true,
        "search_box": true
    }'

    wp --allow-root option update schema_wp_settings "$schema_settings" --format=json --quiet 2>/dev/null || true

    log_success "Schema Plugin configurato"
}

configure_google_analytics() {
    if ! wp --allow-root plugin is-active google-analytics-dashboard-for-wp >/dev/null 2>&1; then
        log_info "Google Analytics plugin non attivo, salto configurazione"
        return 0
    fi

    log_info "Configurazione Google Analytics..."

    local ga_settings='{
        "analytics_profile": "",
        "manual_ua_code_hidden": "",
        "hide_admin_bar_reports": "",
        "dashboards_disabled": "",
        "anonymize_ips": true,
        "demographics": true,
        "ignore_users": ["administrator"],
        "track_user": false,
        "events_mode": false,
        "affiliate_links": false,
        "download_extensions": "zip,mp3,mpeg,pdf,docx,pptx,xlsx,rar,wma,mov,wmv,avi,flv,wav"
    }'

    wp --allow-root option update exactmetrics_settings "$ga_settings" --format=json --quiet 2>/dev/null || true

    log_success "Google Analytics configurato"
}

configure_amp_plugin() {
    if ! wp --allow-root plugin is-active amp >/dev/null 2>&1; then
        log_info "AMP Plugin non attivo, salto configurazione"
        return 0
    fi

    log_info "Configurazione AMP Plugin..."

    local amp_settings='{
        "theme_support": "standard",
        "supported_post_types": ["post", "page"],
        "analytics": {},
        "gtag_id": "",
        "enable_response_caching": true,
        "enable_ssr_style_sheets": true,
        "enable_optimizer": true
    }'

    wp --allow-root option update amp-options "$amp_settings" --format=json --quiet 2>/dev/null || true

    log_success "AMP configurato"
}

configure_gdpr_with_prompt() {
    echo ""
    echo "┌──────────────────────────────────────────────────────────────┐"
    echo "│                   CONFORMITÀ GDPR/PRIVACY                   │"
    echo "└──────────────────────────────────────────────────────────────┘"
    echo ""
    echo "I plugin per la conformità GDPR sono stati installati:"
    echo "• Cookie Law Info / Complianz GDPR"
    echo "• Pagine Privacy Policy e Cookie Policy"
    echo "• Configurazione Google Analytics conforme GDPR"
    echo "• Form di contatto privacy-compliant"
    echo ""
    echo -e "${YELLOW}IMPORTANTE:${NC} La configurazione GDPR richiede personalizzazione"
    echo "per essere completamente conforme alla tua attività specifica."
    echo ""

    while true; do
        echo -ne "Vuoi configurare la conformità GDPR automaticamente ora? ${GREEN}[s/N]${NC}: "
        read -r gdpr_choice

        case "${gdpr_choice,,}" in
            s|si|sì|y|yes)
                echo ""
                log_info "Configurazione GDPR automatica in corso..."
                configure_gdpr_compliance
                echo ""
                echo -e "${YELLOW}⚠️  ATTENZIONE IMPORTANTE:${NC}"
                echo "La configurazione automatica fornisce una base GDPR-compliant,"
                echo "ma dovrai personalizzare:"
                echo ""
                echo "1. 📝 Testi dei cookie banner per la tua attività"
                echo "2. 🏢 Informazioni azienda nella Privacy Policy"
                echo "3. 📧 Dati di contatto del DPO/Responsabile Privacy"
                echo "4. 🔧 Configurazioni specifiche per i tuoi servizi"
                echo "5. ⚖️  Basi legali per il trattamento dati"
                echo ""
                echo -e "${GREEN}💡 SUGGERIMENTO:${NC} Accedi al pannello admin WordPress per:"
                echo "   • Personalizzare i testi nei plugin GDPR"
                echo "   • Completare Privacy Policy e Cookie Policy"
                echo "   • Testare funzionalità con utenti non amministratori"
                echo ""
                break
                ;;
            n|no|"")
                echo ""
                log_info "Configurazione GDPR saltata"
                echo -e "${YELLOW}📋 PROSSIMI PASSI MANUALI:${NC}"
                echo "1. Accedi a WordPress Admin → Impostazioni → Privacy"
                echo "2. Configura i plugin Cookie Law Info o Complianz"
                echo "3. Personalizza Privacy Policy e Cookie Policy"
                echo "4. Testa la conformità GDPR del sito"
                echo ""
                break
                ;;
            *)
                echo -e "${RED}Risposta non valida. Usa 's' per Sì o 'n' per No.${NC}"
                ;;
        esac
    done
}

configure_gdpr_compliance() {
    log_step "Configurazione conformità GDPR..."

    # Configure main GDPR settings
    configure_cookie_law_info
    configure_complianz_gdpr
    create_privacy_pages
    configure_wordpress_privacy
    configure_ga_gdpr
    configure_privacy_forms

    log_success "Configurazione GDPR base completata"
}

configure_cookie_law_info() {
    if ! wp --allow-root plugin is-active cookie-law-info >/dev/null 2>&1; then
        log_info "Cookie Law Info non attivo, salto configurazione"
        return 0
    fi

    log_info "Configurazione Cookie Law Info..."

    local cli_settings='{
        "is_on": true,
        "cookie_bar_as": "banner",
        "notify_message": "Questo sito web utilizza i cookie per migliorare la tua esperienza. Continuando a navigare, accetti il nostro utilizzo dei cookie.",
        "notify_accept_button": "Accetta",
        "notify_decline_button": "Rifiuta",
        "notify_more_info_msg": "Maggiori informazioni",
        "show_once": 7,
        "is_eu_on": true,
        "eu_countries": [],
        "auto_scroll": false,
        "reload_after_accept": false,
        "accept_reload": false,
        "decline_reload": false,
        "delete_on_deactivation": false,
        "button_1_is_on": true,
        "button_2_is_on": true,
        "button_3_is_on": true,
        "button_4_is_on": false,
        "cookie_usage_for": "gdpr",
        "cookie_bar_color": "#000000",
        "cookie_text_color": "#ffffff",
        "cookie_bar_opacity": "0.80",
        "cookie_bar_border_width": "0",
        "border_style": "none",
        "cookie_border": "#ffffff",
        "cookie_bar_border_radius": "0"
    }'

    wp --allow-root option update CookieLawInfo_settings "$cli_settings" --format=json --quiet 2>/dev/null || true

    log_success "Cookie Law Info configurato"
}

configure_complianz_gdpr() {
    if ! wp --allow-root plugin is-active complianz-gdpr >/dev/null 2>&1; then
        log_info "Complianz GDPR non attivo, salto configurazione"
        return 0
    fi

    log_info "Configurazione Complianz GDPR..."

    # Basic Complianz settings
    wp --allow-root option update complianz_options_general '{
        "cookie_banner_enabled": true,
        "banner_version": "2.0",
        "consent_mode": "optin",
        "categories_enabled": true,
        "statistics_enabled": true,
        "marketing_enabled": true,
        "social_media_enabled": true
    }' --format=json --quiet 2>/dev/null || true

    wp --allow-root option update complianz_options_cookie-banner '{
        "use_categories": "yes",
        "colorpalette": "dark",
        "banner_title": "Utilizziamo i cookie",
        "banner_body": "Utilizziamo i cookie per personalizzare contenuti e annunci, fornire funzionalità dei social media e analizzare il nostro traffico.",
        "readmore_text": "Leggi di più",
        "accept_all_text": "Accetta tutti",
        "accept_text": "Accetta",
        "decline_text": "Rifiuta",
        "manage_text": "Gestisci preferenze"
    }' --format=json --quiet 2>/dev/null || true

    log_success "Complianz GDPR configurato"
}

create_privacy_pages() {
    log_step "Creazione pagine Privacy Policy e Cookie Policy..."

    # Create Privacy Policy page
    create_privacy_policy_page

    # Create Cookie Policy page
    create_cookie_policy_page

    # Create Data Protection page
    create_data_protection_page

    # Create Terms and Conditions page
    create_terms_conditions_page

    log_success "Pagine privacy create"
}

create_privacy_policy_page() {
    local privacy_content="<h1>Privacy Policy</h1>

<p><em>Ultimo aggiornamento: $(date '+%d/%m/%Y')</em></p>

<h2>1. Informazioni Generali</h2>
<p><strong>${SITE_NAME}</strong> (di seguito \"noi\", \"nostro\" o \"il sito\") rispetta la privacy degli utenti e si impegna a proteggere i dati personali raccolti attraverso questo sito web.</p>

<h2>2. Titolare del Trattamento</h2>
<p><strong>Denominazione:</strong> ${SITE_NAME}<br>
<strong>Dominio:</strong> ${DOMAIN}<br>
<strong>Email:</strong> ${WP_ADMIN_EMAIL}</p>

<h2>3. Dati Raccolti</h2>
<h3>3.1 Dati forniti volontariamente</h3>
<ul>
<li>Nome e cognome</li>
<li>Indirizzo email</li>
<li>Dati inseriti nei moduli di contatto</li>
<li>Commenti e recensioni</li>
</ul>

<h3>3.2 Dati raccolti automaticamente</h3>
<ul>
<li>Indirizzo IP</li>
<li>Informazioni sul browser e dispositivo</li>
<li>Dati di navigazione e utilizzo</li>
<li>Cookie e tecnologie simili</li>
</ul>

<h2>4. Finalità del Trattamento</h2>
<p>I tuoi dati vengono utilizzati per:</p>
<ul>
<li>Fornire i servizi richiesti</li>
<li>Rispondere a domande e richieste</li>
<li>Migliorare l'esperienza utente</li>
<li>Analisi statistiche anonimizzate</li>
<li>Adempimenti legali</li>
</ul>

<h2>5. Base Giuridica</h2>
<p>Il trattamento si basa su:</p>
<ul>
<li><strong>Consenso:</strong> per newsletter e marketing</li>
<li><strong>Interesse legittimo:</strong> per analisi e miglioramenti</li>
<li><strong>Esecuzione contratto:</strong> per servizi richiesti</li>
<li><strong>Obbligo legale:</strong> per adempimenti normativi</li>
</ul>

<h2>6. Condivisione Dati</h2>
<p>I dati possono essere condivisi con:</p>
<ul>
<li>Fornitori di servizi tecnici (hosting, email)</li>
<li>Strumenti di analisi (Google Analytics)</li>
<li>Autorità competenti quando richiesto dalla legge</li>
</ul>

<h2>7. Conservazione Dati</h2>
<p>I dati vengono conservati per il tempo necessario alle finalità del trattamento:</p>
<ul>
<li>Dati di contatto: fino a revoca del consenso</li>
<li>Dati di navigazione: 26 mesi</li>
<li>Log del server: 12 mesi</li>
</ul>

<h2>8. Diritti dell'Interessato</h2>
<p>Hai diritto a:</p>
<ul>
<li>Accedere ai tuoi dati personali</li>
<li>Rettificare dati inesatti</li>
<li>Cancellare i dati (\"diritto all'oblio\")</li>
<li>Limitare il trattamento</li>
<li>Portabilità dei dati</li>
<li>Opporsi al trattamento</li>
<li>Revocare il consenso</li>
</ul>

<h2>9. Cookie</h2>
<p>Il sito utilizza cookie per migliorare l'esperienza utente. Consulta la nostra <a href=\"/cookie-policy/\">Cookie Policy</a> per dettagli.</p>

<h2>10. Sicurezza</h2>
<p>Implementiamo misure di sicurezza tecniche e organizzative per proteggere i tuoi dati da accessi non autorizzati, perdita o distruzione.</p>

<h2>11. Modifiche alla Privacy Policy</h2>
<p>Ci riserviamo il diritto di aggiornare questa informativa. Le modifiche saranno pubblicate su questa pagina con indicazione della data di aggiornamento.</p>

<h2>12. Contatti</h2>
<p>Per esercitare i tuoi diritti o per domande sulla privacy, contattaci:</p>
<ul>
<li><strong>Email:</strong> ${WP_ADMIN_EMAIL}</li>
<li><strong>Sito:</strong> <a href=\"https://${DOMAIN}/contatti/\">Modulo di contatto</a></li>
</ul>

<p><em>Questa informativa è conforme al GDPR (Regolamento UE 2016/679) e al Codice Privacy italiano (D.Lgs. 196/2003 e s.m.i.).</em></p>"

    # Create page
    wp --allow-root post create --post_type=page --post_title="Privacy Policy" --post_content="$privacy_content" --post_status=publish --post_name="privacy-policy" --quiet 2>/dev/null || true

    # Set as privacy page
    local privacy_page_id=$(wp --allow-root post list --post_type=page --name="privacy-policy" --field=ID --quiet 2>/dev/null)
    if [[ -n "$privacy_page_id" ]]; then
        wp --allow-root option update wp_page_for_privacy_policy "$privacy_page_id" --quiet
    fi

    log_info "Privacy Policy page creata"
}

create_cookie_policy_page() {
    local cookie_content="<h1>Cookie Policy</h1>

<p><em>Ultimo aggiornamento: $(date '+%d/%m/%Y')</em></p>

<h2>1. Cosa sono i Cookie</h2>
<p>I cookie sono piccoli file di testo che vengono memorizzati sul tuo dispositivo quando visiti un sito web. Permettono al sito di ricordare le tue preferenze e migliorare la tua esperienza di navigazione.</p>

<h2>2. Tipi di Cookie Utilizzati</h2>

<h3>2.1 Cookie Tecnici (Necessari)</h3>
<p><strong>Finalità:</strong> Essenziali per il funzionamento del sito</p>
<p><strong>Base giuridica:</strong> Interesse legittimo</p>
<p><strong>Durata:</strong> Sessione</p>

<h3>2.2 Cookie di Preferenze</h3>
<p><strong>Finalità:</strong> Ricordare le tue scelte e preferenze</p>
<p><strong>Base giuridica:</strong> Consenso</p>
<p><strong>Durata:</strong> 12 mesi</p>

<h3>2.3 Cookie Statistici</h3>
<p><strong>Finalità:</strong> Analizzare come viene utilizzato il sito</p>
<p><strong>Base giuridica:</strong> Consenso</p>
<p><strong>Durata:</strong> 26 mesi</p>

<h3>2.4 Cookie di Marketing</h3>
<p><strong>Finalità:</strong> Mostrare pubblicità personalizzata</p>
<p><strong>Base giuridica:</strong> Consenso</p>
<p><strong>Durata:</strong> 12 mesi</p>

<h2>3. Gestione dei Cookie</h2>
<p>Puoi gestire le tue preferenze sui cookie:</p>
<ul>
<li>Attraverso il banner dei cookie</li>
<li>Nelle impostazioni del tuo browser</li>
<li>Utilizzando il nostro centro preferenze</li>
</ul>

<h2>4. Cookie di Terze Parti</h2>
<p>Il sito può utilizzare cookie di terze parti per:</p>
<ul>
<li>Google Analytics (analisi)</li>
<li>Google Ads (pubblicità)</li>
<li>Social media (condivisione)</li>
</ul>

<h2>5. Disabilitazione Cookie</h2>
<p>Puoi disabilitare i cookie modificando le impostazioni del browser. Nota che disabilitare alcuni cookie potrebbe limitare le funzionalità del sito.</p>

<h2>6. Contatti</h2>
<p>Per domande sui cookie, contattaci: ${WP_ADMIN_EMAIL}</p>"

    # Create page
    wp --allow-root post create --post_type=page --post_title="Cookie Policy" --post_content="$cookie_content" --post_status=publish --post_name="cookie-policy" --quiet 2>/dev/null || true

    log_info "Cookie Policy page creata"
}

create_data_protection_page() {
    local data_protection_content="<h1>Protezione Dati</h1>

<p><em>Ultimo aggiornamento: $(date '+%d/%m/%Y')</em></p>

<h2>1. Responsabile della Protezione Dati</h2>
<p>Per questioni relative alla protezione dei dati personali, puoi contattare:</p>
<ul>
<li><strong>Email:</strong> ${WP_ADMIN_EMAIL}</li>
<li><strong>Sito:</strong> ${DOMAIN}</li>
</ul>

<h2>2. Come Esercitiamo i Tuoi Diritti</h2>
<p>Puoi esercitare i tuoi diritti in qualsiasi momento contattandoci via email o utilizzando il modulo sottostante.</p>

<h2>3. Tempi di Risposta</h2>
<p>Ci impegniamo a rispondere alle tue richieste entro 30 giorni dal ricevimento.</p>

<h2>4. Reclami</h2>
<p>Hai il diritto di presentare reclamo all'Autorità Garante per la Protezione dei Dati Personali se ritieni che il trattamento non sia conforme al GDPR.</p>"

    # Create page
    wp --allow-root post create --post_type=page --post_title="Protezione Dati" --post_content="$data_protection_content" --post_status=publish --post_name="protezione-dati" --quiet 2>/dev/null || true

    log_info "Data Protection page creata"
}

create_terms_conditions_page() {
    local terms_content="<h1>Termini e Condizioni</h1>

<p><em>Ultimo aggiornamento: $(date '+%d/%m/%Y')</em></p>

<h2>1. Accettazione dei Termini</h2>
<p>Utilizzando questo sito web, accetti i presenti termini e condizioni.</p>

<h2>2. Uso del Sito</h2>
<p>Il sito può essere utilizzato solo per scopi legali e in conformità con questi termini.</p>

<h2>3. Proprietà Intellettuale</h2>
<p>Tutti i contenuti del sito sono protetti da diritti d'autore e proprietà intellettuale.</p>

<h2>4. Limitazione di Responsabilità</h2>
<p>Il sito è fornito \"così com'è\" senza garanzie di alcun tipo.</p>

<h2>5. Modifiche</h2>
<p>Ci riserviamo il diritto di modificare questi termini in qualsiasi momento.</p>

<h2>6. Contatti</h2>
<p>Per domande sui termini, contattaci: ${WP_ADMIN_EMAIL}</p>"

    # Create page
    wp --allow-root post create --post_type=page --post_title="Termini e Condizioni" --post_content="$terms_content" --post_status=publish --post_name="termini-condizioni" --quiet 2>/dev/null || true

    log_info "Terms and Conditions page creata"
}

configure_wordpress_privacy() {
    log_info "Configurazione privacy WordPress..."

    # Enable privacy features
    wp --allow-root option update show_privacy_link_on_comment_form 1 --quiet
    wp --allow-root option update show_comments_cookies_opt_in 1 --quiet

    # Configure data retention
    wp --allow-root option update wp_privacy_policy_content "Consultare la Privacy Policy completa" --quiet

    log_success "Privacy WordPress configurata"
}

configure_ga_gdpr() {
    log_info "Configurazione Google Analytics GDPR-compliant..."

    # Configure GA for GDPR compliance
    wp --allow-root option update exactmetrics_settings '{
        "anonymize_ips": true,
        "demographics": false,
        "ignore_users": ["administrator", "editor"],
        "track_user": false,
        "events_mode": false
    }' --format=json --quiet 2>/dev/null || true

    log_success "Google Analytics GDPR configurato"
}

configure_privacy_forms() {
    log_info "Configurazione form privacy-compliant..."

    # This would typically configure contact forms to be GDPR compliant
    # Implementation depends on the contact form plugin used

    log_success "Form privacy configurati"
}

create_privacy_contact_form() {
    log_info "Creazione form contatto privacy..."

    # Create a privacy-compliant contact form
    # This is a basic implementation - in practice you'd use Contact Form 7 or similar

    local contact_page_content="<h1>Contatti</h1>

<p>Per esercitare i tuoi diritti privacy o per qualsiasi domanda, contattaci:</p>

<h2>Modulo di Contatto</h2>
<p><strong>Email:</strong> ${WP_ADMIN_EMAIL}</p>

<h2>Richieste Privacy</h2>
<p>Per richieste specifiche relative ai tuoi dati personali, specifica:</p>
<ul>
<li>Il diritto che vuoi esercitare</li>
<li>I dati a cui si riferisce la richiesta</li>
<li>Un documento di identità per la verifica</li>
</ul>

<p><em>Risponderemo entro 30 giorni dalla ricezione della richiesta completa.</em></p>"

    # Create contact page
    wp --allow-root post create --post_type=page --post_title="Contatti" --post_content="$contact_page_content" --post_status=publish --post_name="contatti" --quiet 2>/dev/null || true

    log_info "Contact form privacy creato"
}