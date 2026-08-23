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
    extraComponents = [
      "default_config" "met" "esphome" "homekit_controller"
      "apple_tv" "sonos" "samsungtv" "smartthings" "ibeacon" "google_translate"
      "ecobee" "cast" "hunterdouglas_powerview"
      "mcp_server" "google_generative_ai_conversation"
      "bluetooth"
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

    config = {
      # Meta-integration pulling the standard set (frontend, recorder,
      # history, logbook, ssdp, zeroconf, ...).
      default_config = { };

      # HomeKit Bridge: expose HA entities back to Apple Home. The { } default
      # advertises "Home Assistant Bridge" on TCP 21063 with the default domain
      # filter. Pair from the HA UI (Settings -> Devices & Services -> the
      # HomeKit Bridge card shows the setup code/QR).
      homekit = { };

      # Motion push for the Circle View cameras (homekit_controller pairings,
      # 2026-08-20). The cameras themselves cannot be re-exposed to Apple Home
      # (snapshot-only, no stream), so motion lands on the iPhone via the HA
      # companion app's notify target instead; tapping opens the "Cameras"
      # Lovelace dashboard (storage-mode, /cameras). The module cannot emit
      # "!include automations.yaml", so these live here, declaratively.
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
        in
        [
          (motion "living_room" "Living Room")
          (motion "bedroom" "Bedroom")
          (motion "kitchen" "Kitchen")
          (motion "hallway" "Hallway")
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
