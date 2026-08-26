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
    #   vizio            - Vizio SmartCast TVs (pyvizio)
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
      "apple_tv" "sonos" "samsungtv" "vizio" "smartthings" "ibeacon" "google_translate"
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

        samsungtv-smart-component = pkgs.buildHomeAssistantComponent rec {
          owner = "ollo69";
          domain = "samsungtv_smart";
          version = "0.14.5";
          src = pkgs.fetchFromGitHub {
            owner = "ollo69";
            repo = "ha-samsungtv-smart";
            rev = "v${version}";
            hash = "sha256-J3+HD/jMJDIBSiVJnHvjOJ3yswck+DV3XpPqIoR5/sU=";
          };
          dependencies = with py; [
            websocket-client
            wakeonlan
            aiofiles
            casttube
          ];
        };
      in
      [
        ember-mug-component
        uber-eats-component
        samsungtv-smart-component
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

        vizioRemote = pkgs.writeShellScriptBin "vizio-remote" ''
          exec ${pkgs.python3}/bin/python3 - "$@" << 'EOF'
import sys, urllib.request, json, ssl

ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE

AUTH = "Zpm670i03k"
HOST = "192.168.1.195:7345"

KEYMAP = {
    "OK": (4, 1),
    "ENTER": (4, 1),
    "SELECT": (4, 1),
    "DOWN": (4, 2),
    "KEY_DOWN": (4, 2),
    "HOME": (4, 3),
    "KEY_HOME": (4, 3),
    "SMARTCAST": (4, 3),
    "INFO": (4, 6),
    "KEY_INFO": (4, 6),
    "LEFT": (4, 7),
    "KEY_LEFT": (4, 7),
    "UP": (4, 8),
    "KEY_UP": (4, 8),
    "RIGHT": (4, 9),
    "KEY_RIGHT": (4, 9),
    "MENU": (4, 0),
    "KEY_MENU": (4, 0),
    "BACK": (4, 0),
    "KEY_RETURN": (4, 0),
    "EXIT": (4, 0),
    "POWER": (11, 1),
    "KEY_POWER": (11, 1),
    "POWER_OFF": (11, 0),
    "POWER_ON": (11, 1),
    "VOLUP": (5, 0),
    "KEY_VOLUP": (5, 0),
    "VOLDOWN": (5, 1),
    "KEY_VOLDOWN": (5, 1),
    "MUTE": (5, 2),
    "KEY_MUTE": (5, 2),
    "PLAY": (2, 2),
    "KEY_PLAY": (2, 2),
    "PAUSE": (2, 1),
    "KEY_PAUSE": (2, 1),
}

if len(sys.argv) < 2:
    print("usage: vizio-remote <key|input|power> [value]")
    sys.exit(1)

action = sys.argv[1].lower()

if action in ("key", "send_key"):
    key = sys.argv[2].upper() if len(sys.argv) > 2 else "OK"
    if key in KEYMAP:
        codeset, code = KEYMAP[key]
        payload = {"KEYLIST": [{"CODESET": codeset, "CODE": code, "ACTION": "KEYPRESS"}]}
        req = urllib.request.Request(
            f"https://{HOST}/key_command/",
            data=json.dumps(payload).encode(),
            headers={"AUTH": AUTH, "Content-Type": "application/json"},
            method="PUT"
        )
        with urllib.request.urlopen(req, context=ctx, timeout=5) as resp:
            pass

elif action in ("input", "set_input", "source"):
    val = sys.argv[2].upper() if len(sys.argv) > 2 else "SMARTCAST"
    if val in ("CAST", "SMARTCAST"):
        val = "SMARTCAST"
    elif "HDMI1" in val or "HDMI-1" in val or val == "1":
        val = "HDMI-1"
    elif "HDMI2" in val or "HDMI-2" in val or val == "2":
        val = "HDMI-2"
    elif "HDMI3" in val or "HDMI-3" in val or "CHROMECAST" in val or val == "3":
        val = "HDMI-3"
    elif "HDMI4" in val or "HDMI-4" in val or "APPLE TV" in val or val == "4":
        val = "HDMI-4"
    elif "COMP" in val:
        val = "COMP"
    payload = {
        "HASHVAL": 2023834057,
        "REQUEST": "MODIFY",
        "VALUE": val
    }
    req = urllib.request.Request(
        f"https://{HOST}/menu_native/dynamic/tv_settings/devices/current_input",
        data=json.dumps(payload).encode(),
        headers={"AUTH": AUTH, "Content-Type": "application/json"},
        method="PUT"
    )
    with urllib.request.urlopen(req, context=ctx, timeout=5) as resp:
        pass

elif action in ("power", "power_mode"):
    mode = sys.argv[2].lower() if len(sys.argv) > 2 else "toggle"
    if mode == "toggle":
        codeset, code = (11, 1)
    elif mode in ("on", "1"):
        codeset, code = (11, 1)
    else:
        codeset, code = (11, 0)
    payload = {"KEYLIST": [{"CODESET": codeset, "CODE": code, "ACTION": "KEYPRESS"}]}
    req = urllib.request.Request(
        f"https://{HOST}/key_command/",
        data=json.dumps(payload).encode(),
        headers={"AUTH": AUTH, "Content-Type": "application/json"},
        method="PUT"
    )
    with urllib.request.urlopen(req, context=ctx, timeout=5) as resp:
        pass
EOF
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
          vizio_send_key = ''
            ${vizioRemote}/bin/vizio-remote key "{{ command }}"
          '';
          vizio_set_input = ''
            ${vizioRemote}/bin/vizio-remote input "{{ input }}"
          '';
          vizio_power = ''
            ${vizioRemote}/bin/vizio-remote power "{{ mode }}"
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

          vizio_send_key = {
            alias = "Vizio TV — Send Remote Key";
            description = "Send remote control keypress (UP, DOWN, LEFT, RIGHT, OK, BACK, HOME, MENU, INFO, VOLUP, VOLDOWN, MUTE, POWER, PLAY, PAUSE) to the Vizio TV in 215";
            icon = "mdi:remote";
            fields = {
              command = {
                description = "Remote key to send";
                example = "OK";
                required = true;
                selector.select.options = [
                  "OK"
                  "UP"
                  "DOWN"
                  "LEFT"
                  "RIGHT"
                  "BACK"
                  "HOME"
                  "MENU"
                  "INFO"
                  "VOLUP"
                  "VOLDOWN"
                  "MUTE"
                  "POWER"
                  "PLAY"
                  "PAUSE"
                ];
              };
            };
            sequence = [{
              action = "shell_command.vizio_send_key";
              data = {
                command = "{{ command }}";
              };
            }];
            mode = "queued";
          };

          vizio_set_input = {
            alias = "Vizio TV — Switch Input";
            description = "Switch active input on the Vizio TV in 215 (HDMI-1, HDMI-2, HDMI-3/Chromecast, HDMI-4/Apple TV, SMARTCAST, COMP)";
            icon = "mdi:video-input-hdmi";
            fields = {
              input = {
                description = "Input name to switch to";
                example = "HDMI-1";
                required = true;
                selector.select.options = [
                  "SMARTCAST"
                  "HDMI-1"
                  "HDMI-2"
                  "HDMI-3"
                  "HDMI-4"
                  "COMP"
                ];
              };
            };
            sequence = [{
              action = "shell_command.vizio_set_input";
              data = {
                input = "{{ input }}";
              };
            }];
            mode = "single";
          };

          vizio_power = {
            alias = "Vizio TV — Power Control";
            description = "Power toggle, turn on, or turn off the Vizio TV in 215";
            icon = "mdi:power";
            fields = {
              mode = {
                description = "Power mode (toggle, on, off)";
                example = "toggle";
                required = false;
                selector.select.options = [
                  "toggle"
                  "on"
                  "off"
                ];
              };
            };
            sequence = [{
              action = "shell_command.vizio_power";
              data = {
                mode = "{{ mode if mode is defined and mode else 'toggle' }}";
              };
            }];
            mode = "single";
          };

          tv_launch_app = {
            alias = "TV — Launch App";
            description = "Launch an application (YouTube, Netflix, Prime Video, Disney+, Plex, Spotify, Apple TV, Browser) on the TV";
            icon = "mdi:youtube-tv";
            fields = {
              app = {
                description = "Name of the app to launch";
                example = "YouTube";
                required = true;
                selector.select.options = [
                  "YouTube"
                  "Netflix"
                  "Prime Video"
                  "Disney+"
                  "Plex"
                  "Spotify"
                  "Apple TV"
                  "Internet"
                ];
              };
              entity_id = {
                description = "Target TV media player entity (optional)";
                example = "media_player.65_crystal_uhd_un65du7200fxza";
                required = false;
                selector.entity.domain = "media_player";
              };
            };
            sequence = [{
              action = "media_player.select_source";
              target = {
                entity_id = "{% if entity_id is defined and entity_id %}{{ entity_id }}{% elif states('media_player.65_crystal_uhd_un65du7200fxza') not in ['unknown', 'unavailable'] %}{% if states('media_player.65_crystal_uhd_un65du7200fxza') != '' %}media_player.65_crystal_uhd_un65du7200fxza{% else %}media_player.55_crystal_uhd_un55du7200fxza{% endif %}{% else %}media_player.55_crystal_uhd_un55du7200fxza{% endif %}";
              };
              data = {
                source = "{{ app }}";
              };
            }];
            mode = "single";
          };

          tv_send_key = {
            alias = "TV — Send Remote Key";
            description = "Send a remote control navigation key (e.g. KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_ENTER, KEY_RETURN, KEY_HOME, KEY_MENU, KEY_PLAY, KEY_PAUSE, KEY_VOLUP, KEY_VOLDOWN, KEY_MUTE, KEY_HDMI1, KEY_HDMI2) to the TV";
            icon = "mdi:remote";
            fields = {
              command = {
                description = "Key command or list of key commands";
                example = "KEY_UP";
                required = true;
                selector.text = { };
              };
              entity_id = {
                description = "Target TV remote entity (optional)";
                example = "remote.65_crystal_uhd_un65du7200fxza";
                required = false;
                selector.entity.domain = "remote";
              };
            };
            sequence = [{
              action = "remote.send_command";
              target = {
                entity_id = "{% if entity_id is defined and entity_id %}{{ entity_id }}{% elif states('remote.65_crystal_uhd_un65du7200fxza') not in ['unknown', 'unavailable'] %}{% if states('remote.65_crystal_uhd_un65du7200fxza') != '' %}remote.65_crystal_uhd_un65du7200fxza{% else %}remote.55_crystal_uhd_un55du7200fxza{% endif %}{% else %}remote.55_crystal_uhd_un55du7200fxza{% endif %}";
              };
              data = {
                command = "{{ command }}";
              };
            }];
            mode = "single";
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
