#!/bin/bash

# =============================================================================
# WORDPRESS THEME AND SEO FUNCTIONS
# =============================================================================

# shellcheck source=./utils.sh
source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"

install_optimized_theme() {
    log_step "Installazione tema ottimizzato..."

    # Install GeneratePress (free lightweight theme)
    if wp --allow-root theme install generatepress --activate --quiet >/dev/null 2>&1; then
        log_success "GeneratePress installato e attivato"
        configure_generatepress_performance
    else
        log_warn "Errore installazione GeneratePress, uso tema di default"
        configure_default_theme
    fi

    # Create child theme for customizations
    create_child_theme
}

configure_generatepress_performance() {
    log_info "Configurazione performance GeneratePress..."

    # Configure GeneratePress options for performance
    wp --allow-root option update generate_settings '{
        "font_manager": [],
        "disable_google_fonts": true,
        "combine_css": true,
        "dynamic_css_cache": true,
        "fontawesome_essentials": true,
        "back_to_top": false,
        "smooth_scrolling": false
    }' --format=json --quiet 2>/dev/null || true

    log_success "GeneratePress configurato per performance"
}

create_child_theme() {
    log_info "Creazione child theme..."

    local wp_dir="/var/www/${DOMAIN}"
    local themes_dir="$wp_dir/wp-content/themes"
    local child_theme_dir="$themes_dir/generatepress-child"

    # Create child theme directory
    mkdir -p "$child_theme_dir"

    # Create style.css for child theme
    cat > "$child_theme_dir/style.css" << CHILD_STYLE_EOF
/*
Theme Name: GeneratePress Child
Description: Child theme of GeneratePress for ${SITE_NAME}
Author: WordPress Auto-installer
Template: generatepress
Version: 1.0.0
*/

/* Importa gli stili del tema padre */
@import url("../generatepress/style.css");

/* Personalizzazioni per ${SITE_NAME} */
body {
    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
}

/* Ottimizzazioni performance */
.site-header {
    will-change: transform;
}

.main-navigation {
    contain: layout;
}

/* Stili personalizzati aggiuntivi qui */
CHILD_STYLE_EOF

    # Create functions.php for child theme
    cat > "$child_theme_dir/functions.php" << 'CHILD_FUNCTIONS_EOF'
<?php
/**
 * GeneratePress Child Theme Functions
 */

// Prevent direct access
if (!defined('ABSPATH')) {
    exit;
}

/**
 * Enqueue parent and child theme styles
 */
function generatepress_child_enqueue_styles() {
    // Enqueue parent theme style
    wp_enqueue_style(
        'generatepress-style',
        get_template_directory_uri() . '/style.css',
        array(),
        wp_get_theme()->get('Version')
    );

    // Enqueue child theme style
    wp_enqueue_style(
        'generatepress-child-style',
        get_stylesheet_directory_uri() . '/style.css',
        array('generatepress-style'),
        wp_get_theme()->get('Version')
    );
}
add_action('wp_enqueue_scripts', 'generatepress_child_enqueue_styles');

/**
 * Performance optimizations
 */
function generatepress_child_performance() {
    // Remove unnecessary WordPress features
    remove_action('wp_head', 'wp_generator');
    remove_action('wp_head', 'wlwmanifest_link');
    remove_action('wp_head', 'rsd_link');
    remove_action('wp_head', 'wp_shortlink_wp_head');

    // Disable emoji scripts
    remove_action('wp_head', 'print_emoji_detection_script', 7);
    remove_action('wp_print_styles', 'print_emoji_styles');
    remove_action('admin_print_scripts', 'print_emoji_detection_script');
    remove_action('admin_print_styles', 'print_emoji_styles');

    // Remove query strings from static resources
    add_filter('script_loader_src', 'remove_query_strings', 15, 1);
    add_filter('style_loader_src', 'remove_query_strings', 15, 1);
}
add_action('init', 'generatepress_child_performance');

/**
 * Remove query strings from static resources
 */
function remove_query_strings($src) {
    if (strpos($src, '?ver=')) {
        $src = remove_query_arg('ver', $src);
    }
    return $src;
}

/**
 * Customize WordPress dashboard for this site
 */
function generatepress_child_custom_dashboard() {
    // Add custom dashboard widget
    wp_add_dashboard_widget(
        'site_info_widget',
        'Informazioni Sito',
        'site_info_dashboard_widget'
    );
}
add_action('wp_dashboard_setup', 'generatepress_child_custom_dashboard');

function site_info_dashboard_widget() {
    echo '<p><strong>Sito:</strong> ' . get_bloginfo('name') . '</p>';
    echo '<p><strong>URL:</strong> ' . get_bloginfo('url') . '</p>';
    echo '<p><strong>Tema:</strong> ' . wp_get_theme()->get('Name') . '</p>';
    echo '<p><strong>Versione WordPress:</strong> ' . get_bloginfo('version') . '</p>';
    echo '<p><strong>PHP:</strong> ' . PHP_VERSION . '</p>';
}

/**
 * Security enhancements
 */
function generatepress_child_security() {
    // Hide WordPress version
    add_filter('the_generator', '__return_empty_string');

    // Disable file editing
    if (!defined('DISALLOW_FILE_EDIT')) {
        define('DISALLOW_FILE_EDIT', true);
    }

    // Remove version from scripts and styles
    add_filter('style_loader_src', 'remove_wp_version_strings');
    add_filter('script_loader_src', 'remove_wp_version_strings');
}
add_action('init', 'generatepress_child_security');

function remove_wp_version_strings($src) {
    global $wp_version;
    parse_str(parse_url($src, PHP_URL_QUERY), $query);
    if (isset($query['ver']) && $query['ver'] === $wp_version) {
        $src = remove_query_arg('ver', $src);
    }
    return $src;
}

// Additional custom functions can be added here
CHILD_FUNCTIONS_EOF

    # Set proper permissions
    chown -R www-data:www-data "$child_theme_dir"
    find "$child_theme_dir" -type f -exec chmod 644 {} \;

    # Activate child theme
    wp --allow-root theme activate generatepress-child --quiet 2>/dev/null || true

    log_success "Child theme creato e attivato"
}

configure_customizer_performance() {
    log_info "Configurazione Customizer per performance..."

    # Configure WordPress Customizer settings for performance
    wp --allow-root option update theme_mods_generatepress '{
        "header_layout_setting": "fluid-header",
        "container_width": 1200,
        "blog_layout_setting": "no-sidebar",
        "single_layout_setting": "no-sidebar",
        "page_layout_setting": "no-sidebar"
    }' --format=json --quiet 2>/dev/null || true

    # Disable unnecessary customizer features
    wp --allow-root option update customize_stacked_on_mobile 0 --quiet
    wp --allow-root option update custom_logo 0 --quiet

    log_success "Customizer configurato"
}

configure_default_theme() {
    log_info "Configurazione tema di default..."

    # If GeneratePress fails, configure the default theme
    local active_theme=$(wp --allow-root theme list --status=active --field=name --quiet 2>/dev/null | head -1)

    if [[ "$active_theme" == "twentytwentythree" ]] || [[ "$active_theme" == "twentytwentyfour" ]]; then
        # Configure Twenty Twenty-Three/Four for performance
        wp --allow-root option update show_on_front 'page' --quiet
        wp --allow-root option update page_on_front 0 --quiet

        # Create a simple homepage
        local homepage_content="<h1>Benvenuto su ${SITE_NAME}</h1>
<p>Il tuo sito WordPress è stato configurato con successo!</p>
<p>Puoi iniziare a personalizzare il contenuto accedendo al <a href=\"/wp-admin/\">pannello di amministrazione</a>.</p>"

        wp --allow-root post create --post_type=page --post_title="Home" --post_content="$homepage_content" --post_status=publish --post_name="home" --quiet 2>/dev/null || true

        local home_page_id=$(wp --allow-root post list --post_type=page --name="home" --field=ID --quiet 2>/dev/null)
        if [[ -n "$home_page_id" ]]; then
            wp --allow-root option update page_on_front "$home_page_id" --quiet
        fi
    fi

    log_success "Tema di default configurato"
}

install_elementor() {
    if wp --allow-root plugin is-installed elementor >/dev/null 2>&1; then
        log_info "Elementor già installato"
        configure_elementor_performance
        return 0
    fi

    log_info "Installazione Elementor..."

    if wp --allow-root plugin install elementor --activate --quiet >/dev/null 2>&1; then
        log_success "Elementor installato"
        configure_elementor_performance
    else
        log_warn "Errore installazione Elementor"
        return 1
    fi
}

configure_elementor_performance() {
    if ! wp --allow-root plugin is-active elementor >/dev/null 2>&1; then
        return 0
    fi

    log_info "Configurazione Elementor per performance..."

    # Configure Elementor performance settings
    wp --allow-root option update elementor_options '{
        "css_print_method": "internal",
        "font_display": "swap",
        "optimized_dom_output": "enabled",
        "optimized_control_loading": "enabled",
        "experiment-e_dom_optimization": "active",
        "experiment-e_optimized_assets_loading": "active",
        "experiment-additional_custom_breakpoints": "active"
    }' --format=json --quiet 2>/dev/null || true

    log_success "Elementor configurato per performance"
}

configure_seo_basics() {
    log_step "Configurazione SEO di base..."

    # Configure basic SEO settings
    wp --allow-root option update blogdescription "Sito web professionale - ${SITE_NAME}" --quiet

    # Configure permalinks for SEO
    wp --allow-root rewrite structure '/%postname%/' --quiet
    wp --allow-root rewrite flush --quiet

    # Enable/disable features for SEO
    wp --allow-root option update default_ping_status 'closed' --quiet
    wp --allow-root option update default_comment_status 'closed' --quiet

    # Create robots.txt
    create_robots_txt

    # Configure sitemap (if Yoast is not available)
    configure_basic_sitemap

    log_success "SEO di base configurato"
}

create_robots_txt() {
    local wp_dir="/var/www/${DOMAIN}"
    local robots_file="$wp_dir/robots.txt"

    cat > "$robots_file" << ROBOTS_EOF
User-agent: *
Allow: /

# WordPress specific
Disallow: /wp-admin/
Disallow: /wp-includes/
Disallow: /wp-content/plugins/
Disallow: /wp-content/cache/
Disallow: /wp-content/themes/
Disallow: /trackback/
Disallow: /feed/
Disallow: /comments/
Disallow: /category/*/*
Disallow: */trackback/
Disallow: */feed/
Disallow: */comments/
Disallow: /*?*
Disallow: /*?

# Allow specific files
Allow: /wp-content/uploads/
Allow: /wp-content/themes/*/css/
Allow: /wp-content/themes/*/js/
Allow: /wp-content/themes/*/images/

# Sitemap
Sitemap: https://${DOMAIN}/sitemap_index.xml
Sitemap: https://${DOMAIN}/sitemap.xml
ROBOTS_EOF

    chown www-data:www-data "$robots_file"
    chmod 644 "$robots_file"

    log_info "robots.txt creato"
}

configure_basic_sitemap() {
    # Enable XML sitemaps if available
    wp --allow-root option update blog_public 1 --quiet

    # If no SEO plugin handles sitemaps, enable WordPress core sitemaps (WP 5.5+)
    if ! wp --allow-root plugin is-active wordpress-seo >/dev/null 2>&1; then
        wp --allow-root option update wp_page_numbers 1 --quiet
        log_info "WordPress core sitemaps abilitati"
    fi
}

configure_yoast_seo() {
    if ! wp --allow-root plugin is-active wordpress-seo >/dev/null 2>&1; then
        log_info "Yoast SEO non attivo, salto configurazione avanzata"
        return 0
    fi

    log_info "Configurazione avanzata Yoast SEO..."

    # Configure Yoast SEO options
    wp --allow-root option update wpseo '{
        "website_name": "'${SITE_NAME}'",
        "company_or_person": "company",
        "company_name": "'${SITE_NAME}'",
        "website_name": "'${SITE_NAME}'",
        "alternate_website_name": "",
        "company_logo": "",
        "person_name": "",
        "company_or_person_user_id": false,
        "disableadvanced_meta": true,
        "ryte_indexability": true,
        "baiduverify": "",
        "googleverify": "",
        "msverify": "",
        "yandexverify": ""
    }' --format=json --quiet 2>/dev/null || true

    # Configure title templates
    wp --allow-root option update wpseo_titles '{
        "separator": "dash",
        "title-home-wpseo": "'${SITE_NAME}' %%sep%% %%sitedesc%%",
        "title-author-wpseo": "%%name%% %%sep%% %%sitename%%",
        "title-archive-wpseo": "%%date%% %%sep%% %%sitename%%",
        "title-search-wpseo": "Risultati per: %%searchphrase%% %%sep%% %%sitename%%",
        "title-404-wpseo": "Pagina non trovata %%sep%% %%sitename%%"
    }' --format=json --quiet 2>/dev/null || true

    log_success "Yoast SEO configurato"
}

configure_seo_plugins() {
    log_info "Configurazione plugin SEO aggiuntivi..."

    # Configure additional SEO plugins if installed
    if wp --allow-root plugin is-active broken-link-checker >/dev/null 2>&1; then
        wp --allow-root option update wsblc_options '{
            "max_execution_time": 30,
            "check_threshold": 72,
            "recheck_threshold": 24,
            "run_in_dashboard": false,
            "email_notifications": false
        }' --format=json --quiet 2>/dev/null || true
        log_info "Broken Link Checker configurato"
    fi

    log_success "Plugin SEO configurati"
}