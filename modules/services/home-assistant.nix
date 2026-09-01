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
    #                      ONE ecobee account holds both homes' thermostats and the
    #                      integration has no per-thermostat filter, so every host
    #                      running this module imports both devices:
    #                        "Home"     = ecobee4 (home 215, this LAN's thermostat)
    #                        "My ecobee"= Smart Premium (home 114)
    #                      Scoped per home via the HA device registry (2026-08-30):
    #                      the non-local device has disabled_by=user on each host
    #                      (surface-pro3 disables "My ecobee", ryzen disables
    #                      "Home"). That state lives in /var/lib/hass/.storage/
    #                      core.device_registry, NOT here — do not "fix" the
    #                      duplicate by deleting the device; it would be recreated
    #                      on the next start. Re-enable in the HA UI if needed.
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
      "bluetooth" "shell_command" "webhook" "script" "ios" "input_boolean"
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

        # BuildingLink mail-room package sensor (sensor.buildinglink_packages).
        # Config-flow only: username/password are entered once in the UI (or via
        # the config-flow API) and stored in the config entry; the integration
        # exchanges them for an OAuth token against BuildingLink's resident
        # portal. No YAML, no extraComponents entry — config_flow integrations
        # are picked up from customComponents alone.
        buildinglink-component = pkgs.buildHomeAssistantComponent rec {
          owner = "yakattack77";
          domain = "buildinglink";
          version = "0.1.1";
          src = pkgs.fetchFromGitHub {
            owner = "yakattack77";
            repo = "ha-buildinglink";
            rev = "v${version}";
            hash = "sha256-yOk1gUYhaAIP94eR6qCA78/7SEVsR8FhA9Zw2lbrGi0=";
          };
        };

        # Time To Pet client portal (pet-sitting schedule for 215). Source is
        # vendored in ./home-assistant-components/timetopet because Time To Pet
        # has no client-side API: its Zapier/API integrations are business-
        # account only, and there is no client calendar feed. The component
        # logs into the client portal with email/password (config flow, stored
        # in the config entry) and polls the portal's JSON event feed for
        # scheduled/completed visits.
        timetopet-component = pkgs.buildHomeAssistantComponent {
          owner = "pittampalli";
          domain = "timetopet";
          version = "0.1.0";
          src = ./home-assistant-components/timetopet;
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
        buildinglink-component
        timetopet-component
        uber-eats-component
        samsungtv-smart-component
      ];

    config =
      let
        # Args are base64-encoded by the caller (shell_command templates use
        # |base64_encode) so message text containing quotes, apostrophes, or
        # newlines survives both the local shell and the remote ssh shell
        # verbatim — plain single-quoted args used to truncate any SMS with an
        # apostrophe (e.g. "Mom's place").
        broadcastNotification = pkgs.writeShellScriptBin "broadcast-desktop-notification" ''
          TITLE_B64="''${1:-}"
          MESSAGE_B64="''${2:-}"
          APP_B64="''${3:-}"
          SSH_KEY="/var/lib/hass/.ssh/id_ed25519"

          HOSTS=("ryzen" "surface" "thinkpad")

          for host in "''${HOSTS[@]}"; do
            ${pkgs.openssh}/bin/ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=2 -i "$SSH_KEY" "vpittamp@$host" "
              DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus \
              PATH=/run/current-system/sw/bin:/etc/profiles/per-user/vpittamp/bin:\$PATH \
              notify-send -a \"\$(printf %s '$APP_B64' | base64 -d)\" -u normal \"\$(printf %s '$TITLE_B64' | base64 -d)\" \"\$(printf %s '$MESSAGE_B64' | base64 -d)\"
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
    "OK": [(4, 1)],
    "ENTER": [(4, 1)],
    "SELECT": [(4, 1)],
    "DOWN": [(4, 2)],
    "KEY_DOWN": [(4, 2)],
    "HOME": [(4, 3)],
    "KEY_HOME": [(4, 3)],
    "SMARTCAST": [(4, 3)],
    "INFO": [(4, 6)],
    "KEY_INFO": [(4, 6)],
    "LEFT": [(4, 7)],
    "KEY_LEFT": [(4, 7)],
    "UP": [(4, 8)],
    "KEY_UP": [(4, 8)],
    "RIGHT": [(4, 9)],
    "KEY_RIGHT": [(4, 9)],
    "MENU": [(4, 0)],
    "KEY_MENU": [(4, 0)],
    "BACK": [(4, 0)],
    "KEY_RETURN": [(4, 0)],
    "EXIT": [(4, 0)],
    "POWER": [(11, 1)],
    "KEY_POWER": [(11, 1)],
    "POWER_OFF": [(11, 0)],
    "POWER_ON": [(11, 1)],
    "VOLUP": [(5, 0)],
    "KEY_VOLUP": [(5, 0)],
    "VOLDOWN": [(5, 1)],
    "KEY_VOLDOWN": [(5, 1)],
    "MUTE": [(5, 2)],
    "KEY_MUTE": [(5, 2)],
    "PLAY": [(3, 0), (2, 2), (3, 2), (4, 1)],
    "KEY_PLAY": [(3, 0), (2, 2), (3, 2), (4, 1)],
    "PAUSE": [(3, 1), (2, 1)],
    "KEY_PAUSE": [(3, 1), (2, 1)],
    "PLAY_PAUSE": [(3, 2), (4, 1)],
}

if len(sys.argv) < 2:
    print("usage: vizio-remote <key|input|power> [value]")
    sys.exit(1)

action = sys.argv[1].lower()

if action in ("key", "send_key"):
    key = sys.argv[2].upper() if len(sys.argv) > 2 else "OK"
    if key in KEYMAP:
        codes = KEYMAP[key]
        if isinstance(codes, tuple):
            codes = [codes]
        payload = {"KEYLIST": [{"CODESET": cs, "CODE": cd, "ACTION": "KEYPRESS"} for (cs, cd) in codes]}
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

        # Helper toggles for Lovelace camera dashboard overlay
        input_boolean = {
          camera_activity = {
            name = "Camera Activity & Controls";
            icon = "mdi:motion-sensor";
          };
        };

        # The uber_eats custom integration keeps all per-order detail in
        # *attributes* (its sensor states are just the order count), which means
        # no state transitions in History and no clean automation triggers.
        # These template entities promote the live order's attributes into real
        # states. They are TRIGGER-based on purpose: state-based template
        # entities do not reliably re-render on attribute-only writes from this
        # integration's coordinator (verified 2026-08-30 — the entities stayed
        # 'unknown' until homeassistant.update_entity). A bare state trigger
        # fires on every write, attribute-only included.
        # Entity IDs of the source sensors derive from the config-entry
        # title ("Vinod Pittampalli") — update them here if the entry is ever
        # re-added under a different name.
        template =
          let
            src = suffix: "sensor.vinod_pittampalli_uber_eats_${suffix}";
          in
          [{
            trigger = [
              {
                platform = "homeassistant";
                event = "start";
              }
              {
                platform = "state";
                entity_id = [
                  (src "order_stage")
                  (src "order_status")
                  (src "restaurant_name")
                  (src "driver_name")
                  (src "driver_eta")
                  (src "driver_ett")
                ];
              }
            ];
            sensor = [
              {
                name = "Uber Eats Order Stage";
                unique_id = "uber_eats_order_stage";
                icon = "mdi:food";
                state = "{{ state_attr('${src "order_stage"}', 'order1_order_stage') or 'none' }}";
              }
              {
                name = "Uber Eats Order Status";
                unique_id = "uber_eats_order_status";
                icon = "mdi:text-long";
                state = "{{ state_attr('${src "order_status"}', 'order1_order_status') or 'none' }}";
              }
              {
                name = "Uber Eats Restaurant";
                unique_id = "uber_eats_restaurant";
                icon = "mdi:storefront";
                state = "{{ state_attr('${src "restaurant_name"}', 'order1_restaurant_name') or 'none' }}";
              }
              {
                name = "Uber Eats Driver";
                unique_id = "uber_eats_driver";
                icon = "mdi:account";
                state = "{{ state_attr('${src "driver_name"}', 'order1_driver_name') or 'none' }}";
              }
              {
                name = "Uber Eats ETA";
                unique_id = "uber_eats_eta";
                icon = "mdi:clock-outline";
                state = "{{ state_attr('${src "driver_eta"}', 'order1_eta') or 'none' }}";
              }
              {
                name = "Uber Eats Minutes Remaining";
                unique_id = "uber_eats_minutes_remaining";
                icon = "mdi:timer-outline";
                unit_of_measurement = "min";
                device_class = "duration";
                state_class = "measurement";
                state = "{{ state_attr('${src "driver_ett"}', 'order1_minutes_remaining') }}";
                availability = "{{ state_attr('${src "driver_ett"}', 'order1_minutes_remaining') | float(none) is not none }}";
              }
            ];
          }];

        shell_command = {
          # base64_encode every field: the rendered command line must not break
          # on quotes/apostrophes/newlines in message text.
          broadcast_desktop_notification = ''
            ${broadcastNotification}/bin/broadcast-desktop-notification "{{ title | base64_encode }}" "{{ message | base64_encode }}" "{{ app_name | default('Messages') | base64_encode }}"
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

          # Launch an app on the Samsung TVs via the samsungtv_smart
          # integration's `app` play_media type. This used to be
          # media_player.select_source against the core `samsungtv` entities,
          # but on these 2024 DU7200-series TVs the core integration exposes
          # only TV/HDMI as sources (Samsung removed the installed-apps API),
          # so every app name failed with "does not support source <app>".
          # samsungtv_smart instead launches via the TV's app-control
          # websocket channel (ms.application.start), verified working on the
          # 65" at 114 on 2026-08-31. App names map to real numeric app ids:
          # Internet/YouTube/Netflix ids verified on the UN65DU7200FXZA
          # (org.tizen.browser is only a launch alias there); the remaining
          # ids are the standard community values for this TV family and are
          # unverified on these specific sets.
          tv_launch_app = {
            alias = "TV — Launch App";
            description = "Launch an application (YouTube, Netflix, Prime Video, Disney+, Plex, Spotify, Apple TV, Internet browser) on the TV";
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
                description = "Target TV media player entity (optional; defaults to the 65\" at 114, then the 55\" at 215)";
                example = "media_player.living_room_65_crystal_uhd_smart";
                required = false;
                selector.entity.domain = "media_player";
              };
            };
            sequence = [{
              action = "media_player.play_media";
              target = {
                entity_id = "{% if entity_id is defined and entity_id %}{{ entity_id }}{% elif states('media_player.living_room_65_crystal_uhd_smart') not in ['unknown', 'unavailable'] %}media_player.living_room_65_crystal_uhd_smart{% else %}media_player.bedroom_55_crystal_uhd_smart{% endif %}";
              };
              data = {
                media_content_type = "app";
                media_content_id = "{{ {'YouTube': '111299001912', 'Netflix': '3201907018807', 'Internet': '3202010022079', 'Prime Video': '3201910019365', 'Disney+': '3201901017640', 'Plex': '3201512006963', 'Spotify': '3201606009684', 'Apple TV': '3201807016597'}[app] }}";
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

          # NOTE: there is intentionally no `open_url` script. The `browser`
          # play_media type (launch org.tizen.browser with a URL payload) is
          # dead on the 2024 DU7200-series firmware in both homes — Samsung
          # removed/crippled the websocket app API it relied on; the call
          # returns success but the TV silently does nothing, even after a
          # true cold boot (verified on the 65" at 114 and the 55" at 215,
          # 2026-08-31/09-01). For app launching use script.tv_launch_app
          # (app play_media via ms.application.start); for a fixed dashboard
          # URL set it as the Internet app's homepage on the TV. Do not
          # re-add an open_url script unless a sideloaded helper app provides
          # a working launch channel.
          #
          # send_text types into whatever input field has focus on the TV
          # (search boxes, login forms), via samsungtv_smart's `send_text`
          # play_media type.
          # Targets media_player.bedroom_55_crystal_uhd_smart — the
          # samsungtv_smart config entry "55 Crystal UHD Smart" (set up
          # 2026-08-31 via config flow against 192.168.1.72; the entity id
          # comes from the TV's own SmartThings device name, not the entry
          # title).
          # Exposed to MCP clients as a tool via the mcp_server integration's
          # LLM API (script fields become tool parameters).
          samsung_tv_send_text = {
            alias = "Samsung TV — Send Text";
            description = "Type text into the focused input field on the 55\" Samsung TV in 215 (e.g. a browser search or login field)";
            icon = "mdi:keyboard";
            fields = {
              text = {
                description = "Text to type into the focused field";
                example = "nasa live stream";
                required = true;
                selector.text = { };
              };
            };
            sequence = [{
              action = "media_player.play_media";
              target.entity_id = "media_player.bedroom_55_crystal_uhd_smart";
              data = {
                media_content_type = "send_text";
                media_content_id = "{{ text }}";
              };
            }];
            mode = "single";
          };

          # 65" TV in the 114 home (ryzen instance). Targets
          # media_player.living_room_65_crystal_uhd_smart — the samsungtv_smart
          # config entry "65 Crystal UHD Smart" (set up 2026-08-31 via config
          # flow against 10.0.0.159). This script exists on both instances
          # (shared module) but only works on the ryzen/114 one; on surface-pro3
          # the target entity does not exist and a call will fail.
          samsung_tv_65_send_text = {
            alias = "Samsung TV 65 — Send Text";
            description = "Type text into the focused input field on the 65\" Samsung TV in 114 (e.g. a browser search or login field)";
            icon = "mdi:keyboard";
            fields = {
              text = {
                description = "Text to type into the focused field";
                example = "nasa live stream";
                required = true;
                selector.text = { };
              };
            };
            sequence = [{
              action = "media_player.play_media";
              target.entity_id = "media_player.living_room_65_crystal_uhd_smart";
              data = {
                media_content_type = "send_text";
                media_content_id = "{{ text }}";
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
            # Stable, privacy-bounded event contract consumed by Workflow
            # Builder's Home Assistant trigger adapter. Home Assistant adds the
            # event envelope (context and time_fired); event_data stays focused
            # on fields agents can safely route on. Do not add SMS bodies or
            # other free-form personal content here.
            homeActivity = data: {
              event = "home_215_activity";
              event_data = {
                schema_version = 1;
                home_id = "215";
              } // data;
            };

            motion = room: entity: {
              id = "motion-${room}";
              alias = "Motion — ${entity}";
              description = "Publish activity and push to iPhone when the ${entity} camera sees motion";
              triggers = [{
                platform = "state";
                entity_id = "binary_sensor.${room}_motion";
                to = "on";
              }];
              conditions = [ ];
              actions = [
                (homeActivity {
                  kind = "camera_motion";
                  entity_id = "binary_sensor.${room}_motion";
                  area = room;
                  state = "on";
                })
                {
                  # mobile_app's own notify service (notify.send_message on the
                  # entity rejects the nested push "data" extras).
                  action = "notify.mobile_app_iphone_2";
                  data = {
                    title = "${entity} — motion";
                    message = "Motion detected by the ${entity} camera.";
                    data.url = "/cameras";
                  };
                }
              ];
              mode = "single";
            };

            # Presence notifications from the iPhone's companion-app location
            # (device_tracker.iphone_2 -> person.vinod). The from/to guards
            # skip 'unavailable'/'unknown' transitions so an HA restart or a
            # brief tracker dropout doesn't fire a false arrive/leave.
            vinodArrivesHome = {
              id = "vinod-arrives-home";
              alias = "Presence — Vinod arrives home";
              description = "Publish activity and notify the desktop when Vinod's iPhone enters the Home zone";
              triggers = [{
                platform = "state";
                entity_id = "person.vinod";
                to = "home";
              }];
              conditions = [{
                condition = "template";
                value_template = "{{ trigger.from_state.state not in ['unavailable', 'unknown'] }}";
              }];
              actions = [
                (homeActivity {
                  kind = "presence_arrived";
                  entity_id = "person.vinod";
                  person = "vinod";
                  state = "home";
                })
                {
                  action = "shell_command.broadcast_desktop_notification";
                  data = {
                    title = "🏠 Vinod arrived home";
                    message = "Detected by iPhone location at {{ now().strftime('%I:%M %p') }}.";
                    app_name = "Home Assistant";
                  };
                }
              ];
              mode = "single";
            };

            vinodLeavesHome = {
              id = "vinod-leaves-home";
              alias = "Presence — Vinod leaves home";
              description = "Publish activity and notify the desktop when Vinod's iPhone exits the Home zone";
              triggers = [{
                platform = "state";
                entity_id = "person.vinod";
                from = "home";
              }];
              conditions = [{
                condition = "template";
                value_template = "{{ trigger.to_state.state not in ['unavailable', 'unknown'] }}";
              }];
              actions = [
                (homeActivity {
                  kind = "presence_departed";
                  entity_id = "person.vinod";
                  person = "vinod";
                  state = "away";
                })
                {
                  action = "shell_command.broadcast_desktop_notification";
                  data = {
                    title = "🚗 Vinod left home";
                    message = "Detected by iPhone location at {{ now().strftime('%I:%M %p') }}.";
                    app_name = "Home Assistant";
                  };
                }
              ];
              mode = "single";
            };

            # Uber Eats desktop notifications. Deliberately sparse — four per
            # order max: placed, picked up, arriving, complete. "en route",
            # status-text churn, ETA drift, and the per-minute countdown are
            # intentionally not notified. All trigger on the template sensors
            # (see the `template` block above), so trigger.to_state is always
            # the freshly rendered value.
            uberNotify = { suffix, alias, description, to, message, activityKind, activityData ? { }, conditions ? [ ] }:
              let
                baseTrigger = {
                  platform = "state";
                  entity_id = "sensor.uber_eats_order_stage";
                };
              in
              {
                id = "uber-eats-${suffix}";
                alias = "Uber Eats — ${alias}";
                inherit description conditions;
                triggers = [ (baseTrigger // to) ];
                actions = [
                  (homeActivity ({
                    kind = activityKind;
                    entity_id = "sensor.uber_eats_order_stage";
                    provider = "uber_eats";
                    stage = "{{ trigger.to_state.state }}";
                  } // activityData))
                  {
                    action = "shell_command.broadcast_desktop_notification";
                    data = {
                      title = "🛵 ${alias}";
                      inherit message;
                      app_name = "Uber Eats";
                    };
                  }
                ];
                mode = "single";
              };

            uberOrderPlaced = uberNotify {
              suffix = "order-placed";
              alias = "Order placed";
              description = "Desktop notification when a new Uber Eats order is detected";
              activityKind = "delivery_order_placed";
              activityData.restaurant = "{{ states('sensor.uber_eats_restaurant') }}";
              to = { }; # any transition, gated by the condition below
              conditions = [{
                condition = "template";
                # Only on a genuine "no order -> live stage" transition. The
                # trigger-based template sensors briefly render 'unknown' on HA
                # startup before the first coordinator poll; without the
                # to_state guard that restore fires a spurious "Order placed".
                value_template = "{{ trigger.from_state.state in ['none', 'unavailable', 'unknown'] and trigger.to_state.state not in ['none', 'unavailable', 'unknown'] }}";
              }];
              message = "{{ states('sensor.uber_eats_restaurant') }} is preparing your order.";
            };

            uberOrderPickedUp = uberNotify {
              suffix = "order-picked-up";
              alias = "On the way";
              description = "Desktop notification when the driver picks up the order";
              activityKind = "delivery_order_picked_up";
              activityData = {
                restaurant = "{{ states('sensor.uber_eats_restaurant') }}";
                eta = "{{ states('sensor.uber_eats_eta') }}";
              };
              to = { to = "picked up"; };
              message = "{% set eta = states('sensor.uber_eats_eta') %}{{ states('sensor.uber_eats_restaurant') }} order picked up{% if eta not in ['none', 'unavailable', 'unknown', 'No ETT Available'] %} — ETA {{ eta }}{% endif %}.";
            };

            uberOrderArriving = uberNotify {
              suffix = "order-arriving";
              alias = "Arriving now";
              description = "Desktop notification when the driver is at the door";
              activityKind = "delivery_order_arriving";
              activityData.minutes_remaining = "{{ states('sensor.uber_eats_minutes_remaining') }}";
              to = { to = "arriving"; };
              message = "{% set mins = states('sensor.uber_eats_minutes_remaining') %}Your order is arriving{% if mins | float(none) is not none %} — about {{ mins }} min out{% endif %}. Head to the door.";
            };

            uberOrderComplete = {
              id = "uber-eats-order-complete";
              alias = "Uber Eats — Order complete";
              description = "Desktop notification when the active order clears (delivered or canceled)";
              triggers = [{
                platform = "state";
                entity_id = "binary_sensor.vinod_pittampalli_uber_eats_active_order";
                to = "off";
                from = "on";
              }];
              conditions = [ ];
              actions = [
                (homeActivity {
                  kind = "delivery_order_complete";
                  entity_id = "binary_sensor.vinod_pittampalli_uber_eats_active_order";
                  provider = "uber_eats";
                  state = "complete";
                })
                {
                  action = "shell_command.broadcast_desktop_notification";
                  data = {
                    title = "✅ Uber Eats — order complete";
                    message = "Delivered or canceled — if you did not get your food, check the Uber Eats app.";
                    app_name = "Uber Eats";
                  };
                }
              ];
              mode = "single";
            };

            buildingLinkPackageReceived = {
              id = "buildinglink-package-received";
              alias = "BuildingLink — Package received";
              description = "Publish activity when BuildingLink reports an increase in held packages";
              triggers = [{
                platform = "state";
                entity_id = "sensor.buildinglink_packages";
              }];
              conditions = [{
                condition = "template";
                value_template = "{{ trigger.from_state is not none and trigger.to_state is not none and trigger.from_state.state | int(-1) >= 0 and trigger.to_state.state | int(-1) > trigger.from_state.state | int(-1) }}";
              }];
              actions = [
                (homeActivity {
                  kind = "package_received";
                  entity_id = "sensor.buildinglink_packages";
                  provider = "buildinglink";
                  package_count = "{{ trigger.to_state.state | int }}";
                  package_delta = "{{ (trigger.to_state.state | int) - (trigger.from_state.state | int) }}";
                })
              ];
              mode = "queued";
            };

            timeToPetVisitStarted = {
              id = "time-to-pet-visit-started";
              alias = "Time To Pet — Visit started";
              description = "Publish activity when a Time To Pet visit starts";
              triggers = [{
                platform = "state";
                entity_id = "binary_sensor.time_to_pet_visit_in_progress";
                from = "off";
                to = "on";
              }];
              conditions = [ ];
              actions = [
                (homeActivity {
                  kind = "pet_visit_started";
                  entity_id = "binary_sensor.time_to_pet_visit_in_progress";
                  provider = "time_to_pet";
                  state = "in_progress";
                })
              ];
              mode = "single";
            };

            timeToPetVisitCompleted = {
              id = "time-to-pet-visit-completed";
              alias = "Time To Pet — Visit completed";
              description = "Publish activity when a Time To Pet visit completes";
              triggers = [{
                platform = "state";
                entity_id = "binary_sensor.time_to_pet_visit_in_progress";
                from = "on";
                to = "off";
              }];
              conditions = [ ];
              actions = [
                (homeActivity {
                  kind = "pet_visit_completed";
                  entity_id = "binary_sensor.time_to_pet_visit_in_progress";
                  provider = "time_to_pet";
                  state = "complete";
                })
              ];
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
                  # Normalize the payload first: Shortcuts can deliver this as a
                  # webhook JSON body (trigger.json), a webhook FORM post
                  # (trigger.data — Get Contents of URL with a Form body, which
                  # is what silently dropped the message text before), query
                  # params (trigger.query), or an event (trigger.event.data,
                  # with actionData for ios.action_fired). Field names are read
                  # with case/spelling fallbacks.
                  title = "{% set p = trigger.json if (trigger.platform == 'webhook' and trigger.json is mapping and trigger.json) else (trigger.data if (trigger.platform == 'webhook' and trigger.data) else (trigger.query if (trigger.platform == 'webhook' and trigger.query) else (trigger.event.data if (trigger.platform == 'event' and trigger.event.data is defined) else {}))) %}{% set s = p.sender | default(p.Sender) | default('Text Message') %}{% set ph = p.phone_number | default(p.phone) | default('') %}💬 {{ s }}{% if ph and ph != s %} ({{ ph }}){% endif %}";
                  message = "{% set p = trigger.json if (trigger.platform == 'webhook' and trigger.json is mapping and trigger.json) else (trigger.data if (trigger.platform == 'webhook' and trigger.data) else (trigger.query if (trigger.platform == 'webhook' and trigger.query) else (trigger.event.data if (trigger.platform == 'event' and trigger.event.data is defined) else {}))) %}{% set m = p.message | default(p.Message) | default(p.text) | default(p.body) | default(p.actionData) | default('New message received', true) | string %}{% set d = p.date | default(now().strftime('%I:%M %p')) %}{% set g = p.group | default('') %}{% set sub = p.subject | default('') %}{% if sub %}📌 {{ sub }}\n{% endif %}{{ m }}{% if g %}\n👥 {{ g }}{% endif %}\n🕒 {{ d }} · 📱 iPhone";
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
            vinodArrivesHome
            vinodLeavesHome
            uberOrderPlaced
            uberOrderPickedUp
            uberOrderArriving
            uberOrderComplete
            buildingLinkPackageReceived
            timeToPetVisitStarted
            timeToPetVisitCompleted
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
