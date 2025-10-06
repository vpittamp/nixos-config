{ lib, config, ... }:

# PWA (Progressive Web App) Definitions
# This module defines which PWAs exist and which activities they belong to.
# The actual PWA IDs are dynamically discovered at activation time.

rec {
  # PWA to Activity mappings
  # Each PWA definition specifies which activity it should open in
  pwas = {
    googleai = {
      name = "Google AI";
      activity = null;  # null = all activities
      url = "https://www.google.com/search?udm=50";
    };

    youtube = {
      name = "YouTube";
      activity = null;  # null = all activities
      url = "https://www.youtube.com";
    };

    gitea = {
      name = "Gitea";
      activity = "stacks";
      url = "https://gitea.cnoe.localtest.me:8443";
    };

    backstage = {
      name = "Backstage";
      activity = "stacks";
      url = "https://cnoe.localtest.me:8443";
    };

    kargo = {
      name = "Kargo";
      activity = "stacks";
      url = "https://kargo.cnoe.localtest.me:8443";
    };

    argocd = {
      name = "ArgoCD";
      activity = "stacks";
      url = "https://argocd.cnoe.localtest.me:8443";
    };

    headlamp = {
      name = "Headlamp";
      activity = "stacks";
      url = "https://headlamp.cnoe.localtest.me:8443";
    };

    homeassistant = {
      name = "Home Assistant";
      activity = null;
      url = "http://localhost:8123";
    };

    ubereats = {
      name = "Uber Eats";
      activity = null;  # Default activity
      url = "https://www.ubereats.com";
    };
  };

  # Helper: Get PWA names as a list
  pwaNames = lib.attrNames pwas;

  # Helper: Get all PWAs for a specific activity
  pwasForActivity = activityName:
    lib.filterAttrs (name: pwa: pwa.activity == activityName) pwas;
}
