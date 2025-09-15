{ config, lib, pkgs, ... }:

{
  programs.chromium = {
    enable = true;
    # Enterprise policies: disable built-in password manager, pin 1Password, and handle certificates
    extraOpts = {
      "PasswordManagerEnabled" = false;
      "ExtensionSettings" = {
        "aeblfdkhhhdcdjpifhhbdiojplfjncoa" = {
          "toolbar_pin" = "force_pinned";
        };
      };
      
      # Certificate policies for local development
      # Allow insecure content from these domains
      "InsecureContentAllowedForUrls" = [
        "https://*.cnoe.localtest.me"
        "https://cnoe.localtest.me"
        "https://localhost"
        "https://127.0.0.1"
      ];
      
      # Allow certificates from these hosts even if they're invalid
      "CertificateTransparencyEnforcementDisabledForUrls" = [
        "*.cnoe.localtest.me"
        "cnoe.localtest.me"
        "localhost"
        "127.0.0.1"
      ];
      
      # Disable HSTS for local development domains
      "HSTSPolicyBypassList" = [
        "*.cnoe.localtest.me"
        "cnoe.localtest.me"
      ];
      
      # Allow running insecure content
      "DefaultInsecureContentSetting" = 2; # 2 = Allow
    };
    # Also set initial preferences to turn off password saving UI on first run
    initialPrefs = {
      "credentials_enable_service" = false;
    };
  };
  
  # System-wide certificate trust
  # This makes NixOS trust additional CA certificates
  security.pki.certificateFiles = [
    # IDPBuilder/Kind cluster certificates will be added here
  ];
}
