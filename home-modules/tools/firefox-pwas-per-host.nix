# Per-Host PWA Configuration Module
# This allows different PWA setups for different machines
{ config, lib, pkgs, ... }:

with lib;

let
  hostname = config.networking.hostName or "unknown";
  
  # Define PWA sets per hostname
  # These IDs are from 'firefoxpwa profile list' on each machine
  pwasByHost = {
    # M1 Mac PWAs (current installation)
    "nixos-m1" = {
      google = {
        name = "Google";
        url = "https://www.google.com";
        id = "01D12288367E14F3D20D5C3274";
        icon = "https://www.google.com/favicon.ico";
      };
      youtube = {
        name = "YouTube";
        url = "https://www.youtube.com";
        id = "019DB7F7C8868D4C4FA0121E19";
        icon = "https://www.youtube.com/favicon.ico";
      };
      gitea = {
        name = "Gitea";
        url = "https://gitea.cnoe.localtest.me:8443";
        id = "01FEA664E5984E1A3E85E944F6";
        icon = "https://raw.githubusercontent.com/go-gitea/gitea/main/assets/logo.png";
      };
      backstage = {
        name = "Backstage";
        url = "https://backstage.cnoe.localtest.me:8443";
        id = "0199D501A20B94AE3BB038B6BC";
        icon = "https://backstage.io/img/logo-gradient-on-dark.svg";
      };
      kargo = {
        name = "Kargo";
        url = "https://kargo.cnoe.localtest.me:8443";
        id = "01738C30F3A05DAB2C1BC16C0A";
        icon = "https://raw.githubusercontent.com/akuity/kargo/main/ui/public/kargo-icon.png";
      };
      argocd = {
        name = "ArgoCD";
        url = "https://argocd.cnoe.localtest.me:8443";
        id = "01CBD2EC47D2F8D8CF86034280";
        icon = "https://raw.githubusercontent.com/argoproj/argo-cd/master/docs/assets/logo.png";
      };
      headlamp = {
        name = "Headlamp";
        url = "https://headlamp.cnoe.localtest.me:8443";
        id = "0167D0420CC8C9DFCD3751D068";
        icon = "https://backstage.io/logo_assets/png/Icon_Teal.png";
      };
    };
    
    # Hetzner PWAs (will need to be updated with actual IDs from that machine)
    "nixos-hetzner" = {
      # These are placeholder IDs - need to run 'firefoxpwa profile list' on Hetzner
      # and update with actual IDs
      youtube = {
        name = "YouTube";
        url = "https://www.youtube.com";
        id = "PLACEHOLDER_YOUTUBE";  # Update from Hetzner
        icon = "https://www.youtube.com/favicon.ico";
      };
      github = {
        name = "GitHub";
        url = "https://github.com";
        id = "PLACEHOLDER_GITHUB";  # Update from Hetzner
        icon = "https://github.githubassets.com/favicons/favicon-dark.png";
      };
      # Add more PWAs as installed on Hetzner
    };
    
    # Default empty set for unknown hosts
    "unknown" = {};
  };
  
  # Get PWAs for current host
  currentPwas = pwasByHost.${hostname} or {};

in {
  # Only create desktop files if we have PWAs defined for this host
  home.file = lib.mkIf (currentPwas != {}) (
    lib.mkMerge (lib.mapAttrsToList (name: pwa: {
      ".local/share/applications/FFPWA-${pwa.id}.desktop" = {
        text = ''
          [Desktop Entry]
          Type=Application
          Version=1.4
          Name=${pwa.name}
          Comment=Firefox Progressive Web App
          Icon=FFPWA-${pwa.id}
          Exec=${pkgs.firefoxpwa}/bin/firefoxpwa site launch ${pwa.id} --protocol %u
          Terminal=false
          StartupNotify=true
          StartupWMClass=FFPWA-${pwa.id}
          Categories=Network;
          MimeType=x-scheme-handler/https;x-scheme-handler/http;
        '';
      };
    }) currentPwas)
  );

  # Ensure firefoxpwa is available
  home.packages = [ pkgs.firefoxpwa ];
}
