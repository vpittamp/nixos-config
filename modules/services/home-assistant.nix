# Home Assistant Core (services.home-assistant) for surface-pro3.
#
# Added 2026-08-08. The version is whatever the pinned nixpkgs carries —
# 2026.6.1 at the current lock (2026-06-10 nixos-unstable). Upstream latest is
# 2026.8.x, but nixpkgs packaged it only after this lock's date; tracking
# monthly upstream releases means a full nixpkgs input bump, i.e. a whole-
# system rebuild — better done on the normal channel-bump cadence (with CI
# pushing to pittampalli.cachix.org) than ad-hoc on a 2-core / 3.7 GiB host.
#
# Integrations referenced in `config` below are auto-detected by the module's
# useComponent logic, so adding e.g. a `mqtt = { };` block here is enough — do
# NOT also list it in extraComponents. extraComponents below therefore only
# repeats the module defaults (the onboarding set) plus integrations that have
# no configuration.yaml schema and so can only be declared there:
# homekit_controller (Apple HomeKit Device — imports HomeKit accessories INTO
# HA; discovered/UI-paired only). The `homekit = { };` config block covers the
# other direction (HomeKit Bridge — exposes HA entities back to Apple Home).
{ config, lib, pkgs, ... }:

{
  services.home-assistant = {
    enable = true;

    # Opens TCP 8123 (frontend). modules/services/networking.nix does not trust
    # tailscale0, so this is what makes the UI reachable over both the LAN and
    # the tailnet — and this host is administered entirely over tailscale.
    openFirewall = true;

    # Opens per-integration ports per the module's table. For `homekit` that is
    # TCP 21063 (bridge pairing/HAP) + UDP 5353 (mDNS, which homekit_controller
    # discovery also relies on).
    openFirewallForComponents = true;

    # Module defaults (onboarding set) + homekit_controller, which has no
    # configuration.yaml schema — it is discovered and paired from the UI, so
    # this is the only way to get its dependencies packaged.
    #
    # The remaining entries were seen failing to load their config flows in the
    # journal (ModuleNotFoundError) when discovery probed them on this LAN;
    # packaged here so their discovered devices become configurable in the UI:
    #   apple_tv         - Apple TV (pyatv)
    #   sonos            - Sonos speakers (soco)
    #   samsungtv        - Samsung TVs (getmac)
    #   ibeacon          - iBeacon trackers (ibeacon_ble)
    #   google_translate - default_config's built-in TTS entry (gtts)
    #   ecobee           - Ecobee thermostat, per docs/HOMEKIT_DEVICES.md (pyecobee)
    #   cast             - Google/Chromecast devices (pychromecast)
    #   hunterdouglas_powerview - Kirsch Automation Hub (rebadged Hunter Douglas
    #                      PowerView gen2 firmware at 192.168.1.127) driving the
    #                      motorized shades; config-flow only (aiopvapi)
    #   openai_conversation - the Assist conversation agent for both homes,
    #                      running gpt-5.6-luna. Replaced
    #                      google_generative_ai_conversation, which was dropped
    #                      rather than left packaged: on a 2-core/3.7 GiB host
    #                      an unused integration is still resident dependencies.
    #                      Config-flow only; the API key lives in 1Password at
    #                      op://hub-eso/OPENAI-API-KEY and is entered in the UI.
    #   lutron_caseta    - Lutron Caseta Smart Bridge driving the in-wall
    #                      dimmers/switches and any Pico remotes. Config-flow
    #                      only (pylutron-caseta); pairing is a physical button
    #                      press on the bridge, which exchanges a client cert
    #                      stored in HA -- so the bridge needs a *stable* IP or
    #                      the entry breaks the way the PowerView one did.
    extraComponents = [
      "default_config" "met" "esphome" "homekit_controller"
      "apple_tv" "sonos" "samsungtv" "smartthings" "ibeacon" "google_translate"
      "ecobee" "cast" "hunterdouglas_powerview" "lutron_caseta"
      "mcp_server" "openai_conversation"
      "bluetooth" "shell_command" "webhook" "script" "ios"
    ];

    customComponents =
      let
        py = config.services.home-assistant.package.python3Packages;
        python-ember-mug = py.buildPythonPackage rec {
          pname = "python-ember-mug";
          version = "1.4.0b2";
          pyproject = true;
          src = py.fetchPypi {
            pname = "python_ember_mug";
            inherit version;
            hash = "sha256-Wamfs0drzm7qYY1GDwLFnH4J4SRUUsn+JzN+LYJNQZs=";
          };
          nativeBuildInputs = with py; [
            hatchling
            pythonRelaxDepsHook
          ];
          pythonRelaxDeps = [ "bleak" ];
          propagatedBuildInputs = with py; [
            bleak
            bleak-retry-connector
          ];
          pythonImportsCheck = [ "ember_mug" ];
          doCheck = false;
        };

        ember-mug-component = pkgs.buildHomeAssistantComponent rec {
          owner = "sopelj";
          domain = "ember_mug";
          version = "1.5.0";
          src = pkgs.fetchFromGitHub {
            owner = "sopelj";
            repo = "hass_ember_mug";
            rev = version;
            hash = "sha256-mLQ9rtGqO5plIZOlEJ4RlHmaMHy46Mr+l3USDB3SlNw=";
          };
          dependencies = [
            python-ember-mug
          ];
        };

        uber-eats-component = pkgs.buildHomeAssistantComponent rec {
          owner = "zodyking";
          domain = "uber_eats";
          version = "1.4.7";
          src = pkgs.fetchFromGitHub {
            owner = "zodyking";
            repo = "uber-eats-order-tracker";
            rev = "5153ae091bc31e3989121fe27987cd81a9d32e11";
            hash = "sha256-VqgoVYMdMf8M201JPC4fj60sQ9ie8tMnIL1OTrtzDMs=";
          };
        };
      in
      [
        ember-mug-component
        uber-eats-component
      ];

    config =
      let
        broadcastNotification = pkgs.writeShellScriptBin "broadcast-desktop-notification" ''
          TITLE="''${1:-Text Message}"
          MESSAGE="''${2:-New message received}"
          APP="''${3:-Messages}"
          SSH_KEY="/var/lib/hass/.ssh/id_ed25519"

          HOSTS=("ryzen" "surface" "thinkpad")

          for host in "''${HOSTS[@]}"; do
            ${pkgs.openssh}/bin/ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=2 -i "$SSH_KEY" "vpittamp@$host" "
              DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus \
              PATH=/run/current-system/sw/bin:/etc/profiles/per-user/vpittamp/bin:\$PATH \
              notify-send -a '$APP' -u normal '$TITLE' '$MESSAGE'
            " >/dev/null 2>&1 &
          done
        '';
      in
      {
        # Meta-integration pulling the standard set (frontend, recorder,
        # history, logbook, ssdp, zeroconf, ...).
        default_config = { };

        # HomeKit Bridge: expose HA entities back to Apple Home. The { } default
        # advertises "Home Assistant Bridge" on TCP 21063 with the default domain
        # filter. Pair from the HA UI (Settings -> Devices & Services -> the
        # HomeKit Bridge card shows the setup code/QR).
        homekit = { };

        shell_command = {
          broadcast_desktop_notification = ''
            ${broadcastNotification}/bin/broadcast-desktop-notification "{{ title }}" "{{ message }}" "{{ app_name }}"
          '';
        };

        script = {
          notify_nixos_sms = {
            alias = "Notify NixOS Workstations (SMS)";
            description = "Send iOS text message notification with metadata to all connected NixOS Tailscale workstations";
            icon = "mdi:message-text";
            fields = {
              sender = {
                description = "Name of the sender (e.g. Mom, John Doe)";
                example = "Mom";
                required = true;
                selector.text = { };
              };
              message = {
                description = "Body content of the received text message";
                example = "Dinner at 7pm tonight!";
                required = true;
                selector.text = { };
              };
              phone_number = {
                description = "Sender phone number or Apple ID email";
                example = "+15551234567";
                required = false;
                selector.text = { };
              };
              date = {
                description = "Timestamp or date received";
                example = "10:52 AM";
                required = false;
                selector.text = { };
              };
              group = {
                description = "Group name or thread participants";
                example = "Family";
                required = false;
                selector.text = { };
              };
              subject = {
                description = "Subject line if present";
                example = "Photos";
                required = false;
                selector.text = { };
              };
            };
            sequence = [{
              action = "shell_command.broadcast_desktop_notification";
              data = {
                title = "💬 {{ sender }}{% if phone_number is defined and phone_number and phone_number != sender %} ({{ phone_number }}){% endif %}";
                message = "{% if subject is defined and subject %}📌 {{ subject }}\n{% endif %}{{ message }}{% if group is defined and group %}\n👥 {{ group }}{% endif %}\n🕒 {{ date if date is defined and date else now().strftime('%I:%M %p') }} · 📱 iPhone";
                app_name = "Messages";
              };
            }];
            mode = "queued";
          };
        };

        ios = {
          actions = [
            {
              name = "sms_received";
              label = {
                text = "Notify NixOS (SMS)";
                color = "#FFFFFF";
              };
              icon = {
                icon = "message.fill";
                color = "#34C759";
              };
              show_in_carplay = false;
              show_in_watch = true;
            }
          ];
        };

        # Motion push for the Circle View cameras and iOS SMS desktop notification
        automation =
          let
            motion = room: entity: {
              id = "motion-${room}";
              alias = "Motion — ${entity}";
              description = "Push to iPhone when the ${entity} camera sees motion";
              triggers = [{
                platform = "state";
                entity_id = "binary_sensor.${room}_motion";
                to = "on";
              }];
              conditions = [ ];
              actions = [{
                # mobile_app's own notify service (notify.send_message on the
                # entity rejects the nested push "data" extras).
                action = "notify.mobile_app_iphone_2";
                data = {
                  title = "${entity} — motion";
                  message = "Motion detected by the ${entity} camera.";
                  data.url = "/cameras";
                };
              }];
              mode = "single";
            };

            iosSmsNotification = {
              id = "ios-sms-received-notification";
              alias = "iOS SMS Received — Desktop Notification";
              description = "Broadcast text message with metadata from iOS Shortcut to Tailscale NixOS workstations";
              triggers = [
                {
                  platform = "webhook";
                  webhook_id = "ios_sms_received";
                  allowed_methods = [ "POST" ];
                  local_only = false;
                }
                {
                  platform = "event";
                  event_type = "ios_sms_received";
                }
                {
                  platform = "event";
                  event_type = "ios.action_fired";
                  event_data = {
                    actionName = "sms_received";
                  };
                }
              ];
              conditions = [ ];
              actions = [{
                action = "shell_command.broadcast_desktop_notification";
                data = {
                  title = "{% set s = trigger.json.sender if (trigger.platform == 'webhook' and trigger.json is defined and trigger.json.sender is defined) else (trigger.event.data.sender if (trigger.event is defined and trigger.event.data is defined and trigger.event.data.sender is defined) else 'Text Message') %}{% set p = trigger.json.phone_number if (trigger.platform == 'webhook' and trigger.json is defined and trigger.json.phone_number is defined) else (trigger.event.data.phone_number if (trigger.event is defined and trigger.event.data is defined and trigger.event.data.phone_number is defined) else '') %}💬 {{ s }}{% if p and p != s %} ({{ p }}){% endif %}";
                  message = "{% set m = trigger.json.message if (trigger.platform == 'webhook' and trigger.json is defined and trigger.json.message is defined) else (trigger.event.data.message if (trigger.event is defined and trigger.event.data is defined and trigger.event.data.message is defined) else (trigger.event.data.actionData if (trigger.event is defined and trigger.event.data is defined and trigger.event.data.actionData is defined) else 'New message received')) %}{% set d = trigger.json.date if (trigger.platform == 'webhook' and trigger.json is defined and trigger.json.date is defined) else (trigger.event.data.date if (trigger.event is defined and trigger.event.data is defined and trigger.event.data.date is defined) else now().strftime('%I:%M %p')) %}{% set g = trigger.json.group if (trigger.platform == 'webhook' and trigger.json is defined and trigger.json.group is defined) else (trigger.event.data.group if (trigger.event is defined and trigger.event.data is defined and trigger.event.data.group is defined) else '') %}{% set sub = trigger.json.subject if (trigger.platform == 'webhook' and trigger.json is defined and trigger.json.subject is defined) else (trigger.event.data.subject if (trigger.event is defined and trigger.event.data is defined and trigger.event.data.subject is defined) else '') %}{% if sub %}📌 {{ sub }}\n{% endif %}{{ m }}{% if g %}\n👥 {{ g }}{% endif %}\n🕒 {{ d }} · 📱 iPhone";
                  app_name = "Messages";
                };
              }];
              mode = "queued";
            };
          in
          [
            (motion "living_room" "Living Room")
            (motion "bedroom" "Bedroom")
            (motion "kitchen" "Kitchen")
            (motion "hallway" "Hallway")
            iosSmsNotification
          ];

      # Core settings. Location/units are left for the onboarding UI to ask.
      homeassistant = {
        name = "Surface Pro 3";
        time_zone = config.time.timeZone; # America/New_York (base.nix)
        # Companion-app routing: the app switches on reachability, and
        # notification tap-throughs resolve away from home via the tailnet
        # (surface-pro3 = 100.106.239.88). Never port-forward 8123 instead.
        internal_url = "http://192.168.1.161:8123";
        external_url = "http://100.106.239.88:8123";
      };
    };
  };
}
