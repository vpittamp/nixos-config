# PWA Site Definitions - Single Source of Truth
# This file contains all PWA metadata with ULID identifiers for cross-machine portability
{ lib }:

{
  # List of PWA sites with static ULID identifiers
  pwaSites = [
    # YouTube
    {
      name = "YouTube";
      url = "https://www.youtube.com";
      domain = "youtube.com";
      icon = "file:///etc/nixos/assets/pwa-icons/youtube.png";
      description = "YouTube Video Platform";
      categories = "AudioVideo;Video;";
      keywords = "video;streaming;youtube;";
      scope = "https://www.youtube.com/";
      ulid = "01HQ1Z9J8G7X2K5MNBVWXYZ013";  # Generated 2024-03-15
    }

    # Google AI (Gemini)
    {
      name = "Google AI";
      url = "https://gemini.google.com/app";
      domain = "gemini.google.com";
      icon = "file:///etc/nixos/assets/pwa-icons/google-ai.png";
      description = "Google Gemini AI Assistant";
      categories = "Network;Development;";
      keywords = "ai;gemini;google;assistant;";
      scope = "https://gemini.google.com/";
      ulid = "01HQ1Z9J8G7X2K5MNBVWXYZ014";  # Generated 2024-03-15
    }

    # Claude (Anthropic AI)
    {
      name = "Claude";
      url = "https://claude.ai/chats";
      domain = "claude.ai";
      icon = "file:///etc/nixos/assets/pwa-icons/claude.png";
      description = "Claude AI Assistant by Anthropic";
      categories = "Network;Development;";
      keywords = "ai;claude;anthropic;assistant;";
      scope = "https://claude.ai/";
      ulid = "01JCYF8Z2M7R4N6QW9XKPHVTB5";  # Generated 2025-11-02
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
    }

    # Figma
    {
      name = "Figma";
      url = "https://www.figma.com";
      domain = "figma.com";
      icon = "file:///etc/nixos/assets/pwa-icons/figma.png";
      description = "Figma Design Tool";
      categories = "Graphics;Design;";
      keywords = "figma;design;ui;ux;prototyping;";
      scope = "https://www.figma.com/";
      ulid = "01JCYFAC7T2Y9A1BN4RTVXYA3G";  # Generated 2025-11-02
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
}
