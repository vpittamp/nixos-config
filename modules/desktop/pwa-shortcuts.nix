# Declarative PWA Desktop Shortcuts Module
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.pwa-shortcuts;

  # Generate deterministic IDs for PWAs
  googleId = "01D12288367E14F3D20D5C3274";
  youtubeId = "019DB7F7C8868D4C4FA0121E19";
  kargoId = "01738C30F3A05DAB2C1BC16C0A";
  argoCDId = "01CBD2EC47D2F8D8CF86034280";
  backstageId = "0199D501A20B94AE3BB038B6BC";
  giteaId = "01FEA664E5984E1A3E85E944F6";
  headlampId = "0167D0420CC8C9DFCD3751D068";

  # Create desktop file for PWA
  mkPWADesktop = { name, id, icon, categories }: pkgs.writeTextDir "share/applications/FFPWA-${id}.desktop" ''
    [Desktop Entry]
    Type=Application
    Version=1.4
    Name=${name}
    Comment=${name} PWA
    Categories=${categories}
    Icon=${icon}
    Exec=${pkgs.firefoxpwa}/bin/firefoxpwa site launch ${id} --protocol %u
    Terminal=false
    StartupNotify=true
    StartupWMClass=FFPWA-${id}
    MimeType=
    Actions=
    Keywords=
  '';

  # Google PWA desktop file
  googleDesktop = mkPWADesktop {
    name = "Google";
    id = googleId;
    icon = "${pkgs.runCommand "google-icon" {} ''
      mkdir -p $out/share/icons/hicolor/512x512/apps
      cp ${/etc/nixos/assets/icons/pwas/google-ai.png} $out/share/icons/hicolor/512x512/apps/FFPWA-${googleId}.png
    ''}/share/icons/hicolor/512x512/apps/FFPWA-${googleId}.png";
    categories = "Network;WebBrowser;";
  };

  # YouTube PWA desktop file
  youtubeDesktop = mkPWADesktop {
    name = "YouTube";
    id = youtubeId;
    icon = "${pkgs.runCommand "youtube-icon" {} ''
      mkdir -p $out/share/icons/hicolor/512x512/apps
      cp ${/etc/nixos/assets/icons/pwas/youtube.png} $out/share/icons/hicolor/512x512/apps/FFPWA-${youtubeId}.png
    ''}/share/icons/hicolor/512x512/apps/FFPWA-${youtubeId}.png";
    categories = "AudioVideo;Video;";
  };

  # Kargo PWA desktop file
  kargoDesktop = mkPWADesktop {
    name = "Kargo";
    id = kargoId;
    icon = "${pkgs.runCommand "kargo-icon" {} ''
      mkdir -p $out/share/icons/hicolor/512x512/apps
      cp ${/etc/nixos/assets/icons/pwas/Kargo.png} $out/share/icons/hicolor/512x512/apps/FFPWA-${kargoId}.png
    ''}/share/icons/hicolor/512x512/apps/FFPWA-${kargoId}.png";
    categories = "Development;";
  };

  # ArgoCD PWA desktop file
  argoCDDesktop = mkPWADesktop {
    name = "ArgoCD";
    id = argoCDId;
    icon = "${pkgs.runCommand "argocd-icon" {} ''
      mkdir -p $out/share/icons/hicolor/512x512/apps
      cp ${/etc/nixos/assets/icons/pwas/ArgoCD.png} $out/share/icons/hicolor/512x512/apps/FFPWA-${argoCDId}.png
    ''}/share/icons/hicolor/512x512/apps/FFPWA-${argoCDId}.png";
    categories = "Development;";
  };

  # Backstage PWA desktop file
  backstageDesktop = mkPWADesktop {
    name = "Backstage";
    id = backstageId;
    icon = "${pkgs.runCommand "backstage-icon" {} ''
      mkdir -p $out/share/icons/hicolor/512x512/apps
      cp ${/etc/nixos/assets/icons/pwas/Backstage.png} $out/share/icons/hicolor/512x512/apps/FFPWA-${backstageId}.png
    ''}/share/icons/hicolor/512x512/apps/FFPWA-${backstageId}.png";
    categories = "Development;";
  };

  # Gitea PWA desktop file
  giteaDesktop = mkPWADesktop {
    name = "Gitea";
    id = giteaId;
    icon = "${pkgs.runCommand "gitea-icon" {} ''
      mkdir -p $out/share/icons/hicolor/512x512/apps
      cp ${/etc/nixos/assets/icons/pwas/Gitea.png} $out/share/icons/hicolor/512x512/apps/FFPWA-${giteaId}.png
    ''}/share/icons/hicolor/512x512/apps/FFPWA-${giteaId}.png";
    categories = "Development;";
  };

  # Headlamp PWA desktop file
  headlampDesktop = mkPWADesktop {
    name = "Headlamp";
    id = headlampId;
    icon = "${pkgs.runCommand "headlamp-icon" {} ''
      mkdir -p $out/share/icons/hicolor/512x512/apps
      cp ${/etc/nixos/assets/icons/pwas/Headlamp.png} $out/share/icons/hicolor/512x512/apps/FFPWA-${headlampId}.png
    ''}/share/icons/hicolor/512x512/apps/FFPWA-${headlampId}.png";
    categories = "Development;System;";
  };

in {
  options.services.pwa-shortcuts = {
    enable = mkEnableOption "PWA desktop shortcuts";
  };

  config = mkIf cfg.enable {
    # Install PWA desktop files system-wide
    environment.systemPackages = [
      googleDesktop
      youtubeDesktop
      kargoDesktop
      argoCDDesktop
      backstageDesktop
      giteaDesktop
      headlampDesktop
    ];

    # Also install the icons system-wide
    environment.pathsToLink = [
      "/share/applications"
      "/share/icons"
    ];
  };
}