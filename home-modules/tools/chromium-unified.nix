{ config, pkgs, lib, ... }:

let
  # Detect if we're on M1 or Hetzner based on hostname
  isM1 = config.networking.hostName or "" == "nixos-m1";
  scaleFactor = if isM1 then "1.75" else "1.0";
in
{
  # Configure Chromium with extensions
  programs.chromium = {
    enable = lib.mkForce true;  # Override the false setting in chromium.nix
    package = pkgs.chromium;
    extensions = [
      { id = "aeblfdkhhhdcdjpifhhbdiojplfjncoa"; }  # 1Password - Password Manager
      { id = "cjpalhdlnbpafiamejdnhcphjbkeiagm"; }  # uBlock Origin
      { id = "eimadpbcbfnmbkopoojfekhnkhdbieeh"; }  # Dark Reader
      { id = "dbepggeogbaibhgnhhndojpepiihcmeb"; }  # Vimium
      { id = "pkehgijcmpdhfbdbbnkijodmdjhbjlgp"; }  # Privacy Badger
    ];
    commandLineArgs = [
      "--force-device-scale-factor=${scaleFactor}"
      "--high-dpi-support=1"
      "--password-store=basic"
      "--enable-features=VaapiVideoDecoder,PasswordImport"
      "--use-gl=desktop"
      "--enable-gpu-rasterization"
      "--enable-zero-copy"
      "--ozone-platform-hint=auto"
      "--enable-native-messaging"
      "--disable-reading-from-canvas"
      "--disable-background-networking"
      "--lang=en-US"
    ];
  };
  
  # Setup Local State file to pre-configure profiles
  # This creates the "Cluster Dev" profile with certificate bypass policies
  home.file.".config/chromium/Local State" = {
    force = false;  # Don't overwrite if it exists
    text = builtins.toJSON {
      profile = {
        info_cache = {
          "Default" = {
            name = "Personal";
            shortcut_name = "Personal";
            is_using_default_name = false;
            is_using_default_avatar = false;
            avatar_icon = "chrome://theme/IDR_PROFILE_AVATAR_0";
            background_apps = false;
            is_ephemeral = false;
            is_omitted_from_profile_list = false;
            user_name = "";
          };
          "Profile 1" = {
            name = "Cluster Dev";
            shortcut_name = "ClusterDev";
            is_using_default_name = false;
            is_using_default_avatar = false;
            avatar_icon = "chrome://theme/IDR_PROFILE_AVATAR_14";  # Developer avatar
            background_apps = false;
            is_ephemeral = false;
            is_omitted_from_profile_list = false;
            user_name = "";
          };
        };
        last_used = "Default";
        last_active_profiles = [ "Default" ];
      };
      # Language and location settings
      intl = {
        accept_languages = "en-US,en";
        selected_languages = "en-US,en";
      };
      local_state = {
        default_geolocation_setting = 3;  # Allow location requests
      };
    };
  };
  
  # Create preferences for the Default (Personal) profile
  home.file.".config/chromium/Default/Preferences" = {
    force = false;  # Don't overwrite if it exists
    text = builtins.toJSON {
      profile = {
        name = "Personal";
        is_ephemeral = false;
      };
      
      # Extensions configuration - same for both profiles
      extensions = {
        settings = {
          "aeblfdkhhhdcdjpifhhbdiojplfjncoa" = {  # 1Password
            manifest = {
              key = "MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA0Z6y4jKwMRIHdR0W3R67HD9f5S6umqY84cqKqBQKgdmSJUOvmzRg6IkFgfIb+7MsP1qPHZnPOrVnwWGOgZ3rmrc8hfJxQP2PKQssoErgeGy8EUvSuK7klzzUQCMGJJZ5Sw2K0dNqr3Mb9iFiGPW4SUJQ2fzZzcc1j5P7khX5h8rJYvtBBzuykHe2P7J6h4oNjQb4RRp6bhqZmHvKf7Mwxiuf3OxcC5stimaJLkEvvYaGYkGKqvXvOJXbx7mJkLSWQgFJzSxA7jwYHUPFMpgkBbzVjH9rflbB9IYLqR3SmPd3SutuwEGDFaHZklexrqmSHTBX/rAKdPQKEiC0yQjFwQIDAQAB";
            };
            state = 1;  # Enabled
            toolbar_pin = "force_pinned";
          };
          "cjpalhdlnbpafiamejdnhcphjbkeiagm" = { state = 1; };  # uBlock Origin
          "eimadpbcbfnmbkopoojfekhnkhdbieeh" = { state = 1; };  # Dark Reader
          "dbepggeogbaibhgnhhndojpepiihcmeb" = { state = 1; };  # Vimium
          "pkehgijcmpdhfbdbbnkijodmdjhbjlgp" = { state = 1; };  # Privacy Badger
        };
        # Pin 1Password to toolbar
        toolbar = [
          "aeblfdkhhhdcdjpifhhbdiojplfjncoa"  # 1Password
        ];
      };
      
      # Language settings
      intl = {
        accept_languages = "en-US,en";
        selected_languages = "en-US,en";
      };
      spellcheck = {
        dictionaries = [ "en-US" ];
        dictionary = "en-US";
      };
      translate = {
        enabled = true;
        translate_language_blacklist = [];
      };
      
      # Location settings - Boston, MA 02215
      default_geolocation_setting = 3;  # Allow location requests
      geolocation = {
        access_token = "";
      };
      
      # Regional settings
      homepage = "chrome://newtab/";
      homepage_is_newtabpage = true;
      
      # Bookmark bar visible
      bookmark_bar = {
        show_on_all_tabs = true;
      };
    };
  };
  
  # Create preferences for the Cluster Dev profile
  home.file.".config/chromium/Profile 1/Preferences" = {
    force = false;  # Don't overwrite if it exists
    text = builtins.toJSON {
      profile = {
        name = "Cluster Dev";
        is_ephemeral = false;
      };
      
      # Extensions configuration - same as Personal profile
      extensions = {
        settings = {
          "aeblfdkhhhdcdjpifhhbdiojplfjncoa" = {  # 1Password
            manifest = {
              key = "MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA0Z6y4jKwMRIHdR0W3R67HD9f5S6umqY84cqKqBQKgdmSJUOvmzRg6IkFgfIb+7MsP1qPHZnPOrVnwWGOgZ3rmrc8hfJxQP2PKQssoErgeGy8EUvSuK7klzzUQCMGJJZ5Sw2K0dNqr3Mb9iFiGPW4SUJQ2fzZzcc1j5P7khX5h8rJYvtBBzuykHe2P7J6h4oNjQb4RRp6bhqZmHvKf7Mwxiuf3OxcC5stimaJLkEvvYaGYkGKqvXvOJXbx7mJkLSWQgFJzSxA7jwYHUPFMpgkBbzVjH9rflbB9IYLqR3SmPd3SutuwEGDFaHZklexrqmSHTBX/rAKdPQKEiC0yQjFwQIDAQAB";
            };
            state = 1;  # Enabled
            toolbar_pin = "force_pinned";
          };
          "cjpalhdlnbpafiamejdnhcphjbkeiagm" = { state = 1; };  # uBlock Origin
          "eimadpbcbfnmbkopoojfekhnkhdbieeh" = { state = 1; };  # Dark Reader
          "dbepggeogbaibhgnhhndojpepiihcmeb" = { state = 1; };  # Vimium
          "pkehgijcmpdhfbdbbnkijodmdjhbjlgp" = { state = 1; };  # Privacy Badger
        };
        # Pin 1Password to toolbar
        toolbar = [
          "aeblfdkhhhdcdjpifhhbdiojplfjncoa"  # 1Password
        ];
      };
      
      # Language settings
      intl = {
        accept_languages = "en-US,en";
        selected_languages = "en-US,en";
      };
      spellcheck = {
        dictionaries = [ "en-US" ];
        dictionary = "en-US";
      };
      translate = {
        enabled = true;
        translate_language_blacklist = [];
      };
      
      # Location settings - Boston, MA 02215
      default_geolocation_setting = 3;  # Allow location requests
      geolocation = {
        access_token = "";
      };
      
      # Disable annoying features for development
      safebrowsing = {
        enabled = false;
        scout_reporting_enabled = false;
      };
      
      # Set homepage to cluster services
      homepage = "https://argocd.cnoe.localtest.me:8443";
      homepage_is_newtabpage = false;
      session.restore_on_startup = 4;  # Restore last session
      session.startup_urls = [
        "https://argocd.cnoe.localtest.me:8443"
      ];
      
      # Bookmark bar visible
      bookmark_bar = {
        show_on_all_tabs = true;
      };
      
      # Disable password manager (since it's dev profile)
      credentials_enable_service = false;
      credentials_enable_autosignon = false;
      
      # Profile-specific settings for development
      protocol_handler = {
        excluded_schemes = {
          "https://cnoe.localtest.me:8443" = false;
          "https://argocd.cnoe.localtest.me:8443" = false;
          "https://gitea.cnoe.localtest.me:8443" = false;
          "https://backstage.cnoe.localtest.me:8443" = false;
          "https://headlamp.cnoe.localtest.me:8443" = false;
          "https://kargo.cnoe.localtest.me:8443" = false;
        };
      };
    };
  };
  
  # Create bookmarks for the Cluster Dev profile
  home.file.".config/chromium/Profile 1/Bookmarks" = {
    force = false;  # Don't overwrite if it exists
    text = builtins.toJSON {
      version = 1;
      roots = {
        bookmark_bar = {
          name = "Bookmarks bar";
          type = "folder";
          children = [
            {
              name = "🚀 ArgoCD";
              type = "url";
              url = "https://argocd.cnoe.localtest.me:8443";
            }
            {
              name = "📦 Gitea";
              type = "url";
              url = "https://gitea.cnoe.localtest.me:8443";
            }
            {
              name = "🎭 Backstage";
              type = "url";
              url = "https://backstage.cnoe.localtest.me:8443";
            }
            {
              name = "🎯 Headlamp";
              type = "url";
              url = "https://headlamp.cnoe.localtest.me:8443";
            }
            {
              name = "🚢 Kargo";
              type = "url";
              url = "https://kargo.cnoe.localtest.me:8443";
            }
          ];
        };
        other = {
          name = "Other bookmarks";
          type = "folder";
          children = [];
        };
      };
    };
  };
  
  # Per-profile managed policy for the Cluster Dev profile
  # This allows certificate bypass ONLY for Profile 1
  home.file.".config/chromium/Profile 1/Managed Preferences" = {
    force = true;  # Always enforce these policies
    text = builtins.toJSON {
      # Certificate policies for local development - ONLY for this profile
      InsecureContentAllowedForUrls = [
        "https://*.cnoe.localtest.me:8443"
        "https://cnoe.localtest.me:8443"
      ];
      
      CertificateTransparencyEnforcementDisabledForUrls = [
        "*.cnoe.localtest.me"
        "cnoe.localtest.me"
      ];
      
      # Allow invalid certificates for these patterns
      OverrideSecurityRestrictionsOnInsecureOrigin = [
        "https://cnoe.localtest.me:8443"
        "https://argocd.cnoe.localtest.me:8443"
        "https://gitea.cnoe.localtest.me:8443"
        "https://backstage.cnoe.localtest.me:8443"
        "https://headlamp.cnoe.localtest.me:8443"
        "https://kargo.cnoe.localtest.me:8443"
      ];
      
      # Disable HSTS for local development domains
      HSTSPolicyBypassList = [
        "*.cnoe.localtest.me"
        "cnoe.localtest.me"
      ];
    };
  };
  
  # Create a launcher specifically for the dev profile with certificate bypass flags
  home.file.".local/bin/chromium-cluster" = {
    executable = true;
    text = ''
      #!/usr/bin/env bash
      # Launch Chromium directly to Cluster Dev profile with certificate bypass
      # Note: --ignore-certificate-errors will show a warning banner but bypasses all cert checks
      exec chromium \
        --profile-directory="Profile 1" \
        --ignore-certificate-errors \
        --ignore-certificate-errors-spki-list \
        --allow-running-insecure-content \
        --disable-web-security \
        --unsafely-treat-insecure-origin-as-secure="https://cnoe.localtest.me:8443,https://argocd.cnoe.localtest.me:8443,https://gitea.cnoe.localtest.me:8443,https://backstage.cnoe.localtest.me:8443,https://headlamp.cnoe.localtest.me:8443,https://kargo.cnoe.localtest.me:8443" \
        "$@"
    '';
  };
  
  # Native messaging host manifest for 1Password
  # This allows the browser extension to communicate with the desktop app
  home.file.".config/chromium/NativeMessagingHosts/com.1password.1password.json" = {
    text = builtins.toJSON {
      name = "com.1password.1password";
      description = "1Password Native Messaging Host";
      type = "stdio";
      allowed_origins = [
        "chrome-extension://aeblfdkhhhdcdjpifhhbdiojplfjncoa/"
      ];
      # Path to the 1Password browser support binary
      path = "/run/current-system/sw/share/1password/1Password-BrowserSupport";
    };
  };

  # Additional native messaging host for browser support
  home.file.".config/chromium/NativeMessagingHosts/com.1password.browser_support.json" = {
    text = builtins.toJSON {
      name = "com.1password.browser_support";
      description = "1Password Browser Support";
      type = "stdio";
      allowed_origins = [
        "chrome-extension://aeblfdkhhhdcdjpifhhbdiojplfjncoa/"
      ];
      path = "/run/current-system/sw/share/1password/1Password-BrowserSupport";
    };
  };

  # Configure 1Password browser integration settings
  home.file.".config/1Password/settings/browser-support.json" = {
    text = builtins.toJSON {
      "browser.autoFillShortcut" = {
        "enabled" = true;
        "shortcut" = "Ctrl+Shift+L";
      };
      "browser.showSavePrompts" = true;
      "browser.theme" = "system";
      "security.authenticatedUnlock.enabled" = true;
      "security.authenticatedUnlock.method" = "system";  # Use system authentication
      "security.autolock.minutes" = 10;
      "security.clipboardClearAfterSeconds" = 90;
    };
  };
  
  # Shell aliases
  programs.bash.shellAliases = {
    "chrome-cluster" = "~/.local/bin/chromium-cluster";
  };
  
  # Add a note about profile switching
  programs.bash.initExtra = lib.mkAfter ''
    # Chromium profile info
    if [[ $- == *i* ]] && [[ -z "''${CHROMIUM_PROFILE_INFO_SHOWN:-}" ]]; then
      if kubectl cluster-info &>/dev/null 2>&1; then
        echo "💡 Chromium profiles configured:"
        echo "   • Click profile icon (top-right) to switch between:"
        echo "     - Personal (secure browsing)"
        echo "     - Cluster Dev (certificate bypass for *.cnoe.localtest.me)"
        echo "   • Or use: chrome-cluster to launch dev profile directly"
        export CHROMIUM_PROFILE_INFO_SHOWN=1
      fi
    fi
  '';
}