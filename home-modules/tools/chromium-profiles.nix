{ config, pkgs, lib, ... }:

let
  # Detect if we're on M1 or Hetzner based on hostname
  isM1 = config.networking.hostName or "" == "nixos-m1";
  scaleFactor = if isM1 then "1.75" else "1.0";
  
  # Create wrapper scripts for different Chromium profiles
  chromium-default = pkgs.writeShellScriptBin "chromium-default" ''
    exec ${pkgs.chromium}/bin/chromium \
      --force-device-scale-factor=${scaleFactor} \
      --high-dpi-support=1 \
      --password-store=basic \
      --enable-features=VaapiVideoDecoder,PasswordImport \
      --use-gl=desktop \
      --enable-gpu-rasterization \
      --enable-zero-copy \
      --ozone-platform-hint=auto \
      --enable-native-messaging \
      "$@"
  '';
  
  chromium-dev = pkgs.writeShellScriptBin "chromium-dev" ''
    # Development profile for cluster/IDPBuilder with certificate bypass
    exec ${pkgs.chromium}/bin/chromium \
      --force-device-scale-factor=${scaleFactor} \
      --high-dpi-support=1 \
      --password-store=basic \
      --enable-features=VaapiVideoDecoder \
      --use-gl=desktop \
      --enable-gpu-rasterization \
      --enable-zero-copy \
      --ozone-platform-hint=auto \
      --user-data-dir="$HOME/.config/chromium-dev-profile" \
      --profile-directory="Development" \
      --ignore-certificate-errors \
      --ignore-urlfetcher-cert-requests \
      --allow-running-insecure-content \
      --unsafely-treat-insecure-origin-as-secure=https://cnoe.localtest.me:8443,https://argocd.cnoe.localtest.me:8443,https://gitea.cnoe.localtest.me:8443,https://backstage.cnoe.localtest.me:8443,https://headlamp.cnoe.localtest.me:8443,https://kargo.cnoe.localtest.me:8443 \
      --no-default-browser-check \
      "$@"
  '';
  
  # Profile manager to switch between profiles
  chromium-profile-manager = pkgs.writeShellScriptBin "chromium-profiles" ''
    echo "Chromium Profile Manager"
    echo "========================"
    echo ""
    echo "Available profiles:"
    echo "  1. Default (Secure) - Regular browsing with full security"
    echo "  2. Development - Local cluster development (certificate bypass)"
    echo ""
    echo "Usage:"
    echo "  chromium          - Launch default secure profile"
    echo "  chromium-dev      - Launch development profile"
    echo "  chromium-profiles - Show this help"
    echo ""
    echo "Current profiles in ~/.config/chromium*:"
    ls -la ~/.config/ | grep chromium || echo "  No profiles found yet"
  '';
in
{
  # Install the profile-specific launchers
  home.packages = [
    chromium-dev
    chromium-profile-manager
  ];
  
  # Create desktop entries for both profiles
  xdg.desktopEntries = {
    "chromium-default" = {
      name = "Chromium (Secure)";
      comment = "Default Chromium with full security";
      icon = "chromium";
      exec = "${chromium-default}/bin/chromium-default %U";
      categories = [ "Network" "WebBrowser" ];
      mimeType = [
        "text/html"
        "x-scheme-handler/http"
        "x-scheme-handler/https"
      ];
    };
    
    "chromium-dev" = {
      name = "Chromium (Dev - Cluster)";
      comment = "Chromium for local cluster development with certificate bypass";
      icon = "chromium";
      exec = "${chromium-dev}/bin/chromium-dev %U";
      categories = [ "Network" "WebBrowser" "Development" ];
      actions = {
        "new-window" = {
          name = "New Window";
          exec = "${chromium-dev}/bin/chromium-dev --new-window %U";
        };
        "new-private-window" = {
          name = "New Incognito Window";
          exec = "${chromium-dev}/bin/chromium-dev --incognito %U";
        };
      };
    };
  };
  
  # Shell aliases for quick access
  programs.bash.shellAliases = {
    "chrome-dev" = "chromium-dev";
    "chrome-secure" = "chromium";
    "chrome-profiles" = "chromium-profiles";
  };
  
  # Initial preferences for the development profile
  home.file.".config/chromium-dev-profile/Default/Preferences" = {
    force = true;
    text = builtins.toJSON {
      browser = {
        show_home_button = true;
        check_default_browser = false;
        custom_chrome_frame = false;
      };
      
      # Disable annoying features for development
      safebrowsing = {
        enabled = false;
        scout_reporting_enabled = false;
      };
      
      # Set homepage to cluster services
      homepage = "https://argocd.cnoe.localtest.me:8443";
      homepage_is_newtabpage = false;
      
      # Bookmark bar visible
      bookmark_bar = {
        show_on_all_tabs = true;
      };
      
      # Disable password manager (since it's dev profile)
      credentials_enable_service = false;
      credentials_enable_autosignon = false;
      
      # Profile settings
      profile = {
        name = "Cluster Development";
        avatar_icon = "chrome://theme/IDR_PROFILE_AVATAR_26";
        managed_user_id = "";
        is_ephemeral = false;
      };
      
      # Suppress certificate errors silently
      ssl = {
        error_override_allowed = true;
      };
    };
  };
  
  # Create bookmarks for development profile
  home.file.".config/chromium-dev-profile/Default/Bookmarks" = {
    force = true;
    text = builtins.toJSON {
      version = 1;
      roots = {
        bookmark_bar = {
          name = "Bookmarks bar";
          type = "folder";
          children = [
            {
              name = "ArgoCD";
              type = "url";
              url = "https://argocd.cnoe.localtest.me:8443";
            }
            {
              name = "Gitea";
              type = "url";
              url = "https://gitea.cnoe.localtest.me:8443";
            }
            {
              name = "Backstage";
              type = "url";
              url = "https://backstage.cnoe.localtest.me:8443";
            }
            {
              name = "Headlamp";
              type = "url";
              url = "https://headlamp.cnoe.localtest.me:8443";
            }
            {
              name = "Kargo";
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
        synced = {
          name = "Mobile bookmarks";
          type = "folder";
          children = [];
        };
      };
    };
  };
  
  # Add notification about profiles on shell startup
  programs.bash.initExtra = lib.mkAfter ''
    # Chromium profile helper - show hint once when cluster is detected
    if [[ $- == *i* ]] && [[ -z "''${CHROMIUM_PROFILE_HINT_SHOWN:-}" ]]; then
      if kubectl cluster-info &>/dev/null 2>&1; then
        echo "💡 Tip: Use 'chromium-dev' or 'clb' for cluster development browser"
        export CHROMIUM_PROFILE_HINT_SHOWN=1
      fi
    fi
  '';
}