# PWA Site Definitions - Single Source of Truth
# This file contains all PWA metadata with ULID identifiers for cross-machine portability
{ lib }:

{
  # List of PWA sites with static ULID identifiers
  # App Registry Fields:
  #   - app_scope: "scoped" (project-specific) or "global" (shared across projects)
  #   - preferred_workspace: workspace number (50-70 for PWAs to avoid conflicts with standard apps on 1-9)
  pwaSites = [
    # YouTube
    {
      name = "YouTube";
      url = "https://www.youtube.com";
      domain = "youtube.com";
      icon = "file:///etc/nixos/assets/pwa-icons/youtube.png";
      description = "YouTube video platform";
      categories = "AudioVideo;Video;";
      keywords = "video;streaming;youtube;";
      scope = "https://www.youtube.com/";
      ulid = "01K666N2V6BQMDSBMX3AY74TY7";  # FFPWA ID
      # App registry metadata
      app_scope = "scoped";
      preferred_workspace = 50;
    }

    # Google AI (AI Mode Search)
    {
      name = "Google AI";
      url = "https://google.com/ai";
      domain = "google.com";
      icon = "file:///etc/nixos/assets/pwa-icons/google.png";
      description = "Google AI Mode - Advanced AI search with Gemini 2.5";
      categories = "Network;Development;";
      keywords = "ai;gemini;google;search;assistant;";
      scope = "https://google.com/";
      ulid = "01K665SPD8EPMP3JTW02JM1M0Z";  # FFPWA ID
      # App registry metadata
      app_scope = "scoped";
      preferred_workspace = 51;
    }

    # Claude (Anthropic AI)
    {
      name = "Claude";
      url = "https://claude.ai/code";
      domain = "claude.ai";
      icon = "file:///etc/nixos/assets/pwa-icons/claude.png";
      description = "Claude AI Assistant by Anthropic";
      categories = "Network;Development;";
      keywords = "ai;claude;anthropic;assistant;";
      scope = "https://claude.ai/";
      ulid = "01JCYF8Z2M7R4N6QW9XKPHVTB5";  # Generated 2025-11-02
      # App registry metadata
      app_scope = "scoped";
      preferred_workspace = 52;
    }

    # ChatGPT
    {
      name = "ChatGPT";
      url = "https://chatgpt.com";
      domain = "chatgpt.com";
      icon = "file:///etc/nixos/assets/pwa-icons/chatgpt.png";
      description = "ChatGPT AI assistant";
      categories = "Network;Development;";
      keywords = "ai;chatgpt;openai;assistant;";
      scope = "https://chatgpt.com/";
      ulid = "01K772ZBM45JD68HXYNM193CVW";  # FFPWA ID
      # App registry metadata
      app_scope = "scoped";
      preferred_workspace = 65;
    }

    # GitHub
    {
      name = "GitHub";
      url = "https://github.com";
      domain = "github.com";
      icon = "file:///etc/nixos/assets/pwa-icons/github.png";
      description = "GitHub Code Hosting Platform";
      categories = "Development;Network;";
      keywords = "git;github;code;development;";
      scope = "https://github.com/";
      ulid = "01JCYF9A3P8T5W7XH0KMQRNZC6";  # Generated 2025-11-02
      # App registry metadata
      app_scope = "scoped";
      preferred_workspace = 53;
    }

    # GitHub Codespaces
    {
      name = "GitHub Codespaces";
      url = "https://github.dev";
      domain = "github.dev";
      icon = "file:///etc/nixos/assets/pwa-icons/github-codespaces.png";
      description = "GitHub cloud development environment";
      categories = "Development;Network;";
      keywords = "github;codespaces;cloud;ide;development;";
      scope = "https://github.dev/";
      ulid = "01K772Z7AY5J36Q3NXHH9RYGC0";  # FFPWA ID
      # App registry metadata
      app_scope = "global";
      preferred_workspace = 66;
    }

    # Gmail
    {
      name = "Gmail";
      url = "https://mail.google.com";
      domain = "mail.google.com";
      icon = "file:///etc/nixos/assets/pwa-icons/gmail.png";
      description = "Google Gmail Email Client";
      categories = "Network;Email;";
      keywords = "email;gmail;google;mail;";
      scope = "https://mail.google.com/";
      ulid = "01JCYF9K4Q9V6X8YJ1MNSPT0D7";  # Generated 2025-11-02
      # App registry metadata
      app_scope = "global";
      preferred_workspace = 54;
    }

    # Google Calendar
    {
      name = "Google Calendar";
      url = "https://calendar.google.com";
      domain = "calendar.google.com";
      icon = "file:///etc/nixos/assets/pwa-icons/calendar.png";
      description = "Google Calendar";
      categories = "Office;Calendar;";
      keywords = "calendar;google;schedule;events;";
      scope = "https://calendar.google.com/";
      ulid = "01JCYF9T5R0W7Y9ZK2PQTVX1E8";  # Generated 2025-11-02
      # App registry metadata
      app_scope = "global";
      preferred_workspace = 55;
    }

    # Notion
    {
      name = "Notion";
      url = "https://www.notion.so";
      domain = "notion.so";
      icon = "file:///etc/nixos/assets/pwa-icons/notion.png";
      description = "Notion Workspace";
      categories = "Office;ProjectManagement;";
      keywords = "notion;notes;wiki;workspace;";
      scope = "https://www.notion.so/";
      ulid = "01JCYFA36S1X8Z0AM3QSWZ2F9A";  # Generated 2025-11-02
      # App registry metadata
      app_scope = "scoped";
      preferred_workspace = 56;
    }

    # Figma
    {
      name = "Figma";
      url = "https://www.figma.com";
      domain = "figma.com";
      icon = "file:///etc/nixos/assets/pwa-icons/figma.png";
      description = "Figma Design Tool";
      categories = "Graphics;";  # Design is not a standard category
      keywords = "figma;design;ui;ux;prototyping;";
      scope = "https://www.figma.com/";
      ulid = "01JCYFAC7T2Y9A1BN4RTVXYA3G";  # Generated 2025-11-02
      # App registry metadata
      app_scope = "scoped";
      preferred_workspace = 57;
    }

    # Linear
    {
      name = "Linear";
      url = "https://linear.app";
      domain = "linear.app";
      icon = "file:///etc/nixos/assets/pwa-icons/linear.png";
      description = "Linear Issue Tracker";
      categories = "Development;ProjectManagement;";
      keywords = "linear;issues;tracker;project;";
      scope = "https://linear.app/";
      ulid = "01JCYFAM8V3Z0B2CP5SVWYZB4H";  # Generated 2025-11-02
      # App registry metadata
      app_scope = "scoped";
      preferred_workspace = 58;
    }

    # Slack
    {
      name = "Slack";
      url = "https://app.slack.com";
      domain = "slack.com";
      icon = "file:///etc/nixos/assets/pwa-icons/slack.png";
      description = "Slack Team Communication";
      categories = "Network;InstantMessaging;";
      keywords = "slack;chat;team;communication;";
      scope = "https://app.slack.com/";
      ulid = "01JCYFAV9W4A1C3DQ6TWXZ0C5K";  # Generated 2025-11-02
      # App registry metadata
      app_scope = "global";
      preferred_workspace = 59;
    }

    # WhatsApp Web
    {
      name = "WhatsApp";
      url = "https://web.whatsapp.com";
      domain = "web.whatsapp.com";
      icon = "file:///etc/nixos/assets/pwa-icons/whatsapp.png";
      description = "WhatsApp Messaging";
      categories = "Network;InstantMessaging;";
      keywords = "whatsapp;messaging;chat;";
      scope = "https://web.whatsapp.com/";
      ulid = "01JCYFB5AX5B2D4ER7VXYA1D6M";  # Generated 2025-11-02
      # App registry metadata
      app_scope = "global";
      preferred_workspace = 60;
    }

    # Spotify
    {
      name = "Spotify";
      url = "https://open.spotify.com";
      domain = "open.spotify.com";
      icon = "file:///etc/nixos/assets/pwa-icons/spotify.png";
      description = "Spotify Music Streaming";
      categories = "AudioVideo;Audio;Music;";
      keywords = "spotify;music;streaming;audio;";
      scope = "https://open.spotify.com/";
      ulid = "01JCYFBFBY6C3E5FS8WYZB2E7N";  # Generated 2025-11-02
      # App registry metadata
      app_scope = "scoped";
      preferred_workspace = 61;
    }

    # Netflix
    {
      name = "Netflix";
      url = "https://www.netflix.com";
      domain = "netflix.com";
      icon = "file:///etc/nixos/assets/pwa-icons/netflix.png";
      description = "Netflix Streaming";
      categories = "AudioVideo;Video;";
      keywords = "netflix;streaming;video;movies;shows;";
      scope = "https://www.netflix.com/";
      ulid = "01JCYFBPCZ7D4F6GT9XZA0C3F8";  # Generated 2025-11-02
      # App registry metadata
      app_scope = "scoped";
      preferred_workspace = 62;
    }

    # Discord
    {
      name = "Discord";
      url = "https://discord.com/app";
      domain = "discord.com";
      icon = "file:///etc/nixos/assets/pwa-icons/discord.png";
      description = "Discord Chat Platform";
      categories = "Network;InstantMessaging;";
      keywords = "discord;chat;voice;gaming;";
      scope = "https://discord.com/";
      ulid = "01JCYFBZD08E5G7HV0AZB1D4G9";  # Generated 2025-11-02
      # App registry metadata
      app_scope = "global";
      preferred_workspace = 63;
    }

    # Excalidraw
    {
      name = "Excalidraw";
      url = "https://excalidraw.com";
      domain = "excalidraw.com";
      icon = "file:///etc/nixos/assets/pwa-icons/excalidraw.png";
      description = "Excalidraw Whiteboard";
      categories = "Graphics;";
      keywords = "excalidraw;whiteboard;drawing;diagrams;";
      scope = "https://excalidraw.com/";
      ulid = "01JCYFC9E19F6H8JW1BZC2E5H0";  # Generated 2025-11-02
      # App registry metadata
      app_scope = "scoped";
      preferred_workspace = 64;
    }
  ];

  # ULID validation function
  # ULID format: 26 characters from alphabet [0-9A-HJKMNP-TV-Z] (excludes I, L, O, U)
  validateULID = ulid:
    let
      len = builtins.stringLength ulid;
      # Check if string contains only valid ULID characters
      isValidChars = builtins.match "[0-9A-HJKMNP-TV-Z]*" ulid != null;
    in
    len == 26 && isValidChars;

  # Helper to check for duplicate ULIDs
  checkDuplicateULIDs = pwas:
    let
      ulids = builtins.map (pwa: pwa.ulid) pwas;
      uniqueULIDs = lib.lists.unique ulids;
    in
    if builtins.length ulids != builtins.length uniqueULIDs
    then throw "Duplicate ULIDs detected in pwa-sites.nix"
    else true;

  # Additional trusted domains for Firefox policies
  # These are domains that need clipboard/tracking exception but aren't PWAs
  additionalTrustedDomains = [
    # GitHub ecosystem
    "github.dev"
    "codespaces.githubusercontent.com"

    # AI tools (not all are PWAs)
    "chatgpt.com"

    # Authentication
    "my.1password.com"
    "1password.com"
  ];

  # Helper functions to extract domain patterns for Firefox policies
  helpers = {
    # Extract unique base domains from PWA sites
    # Returns list like: ["google.com", "youtube.com", "github.com", ...]
    getBaseDomains = sites: lib.unique (builtins.map (site: site.domain) sites);

    # Generate Firefox policy exception patterns
    # Returns list like: ["https://google.com", "https://*.google.com", ...]
    getDomainPatterns = sites: additionalDomains:
      let
        pwaDomains = lib.unique (builtins.map (site: site.domain) sites);
        allDomains = lib.unique (pwaDomains ++ additionalDomains);

        # Generate both exact and wildcard patterns for each domain
        generatePatterns = domain:
          if lib.hasPrefix "localhost" domain || lib.hasPrefix "127.0.0.1" domain
          then [ "http://${domain}" ]  # localhost uses HTTP
          else [
            "https://${domain}"
            "https://*.${domain}"
          ];
      in
        lib.flatten (builtins.map generatePatterns allDomains);
  };
}
