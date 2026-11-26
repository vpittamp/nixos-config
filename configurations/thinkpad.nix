# Lenovo ThinkPad Configuration
# Intel Core Ultra 7 155U (Meteor Lake) with Intel Arc integrated graphics
# Physical laptop with Sway/Wayland desktop environment
#
# BARE METAL ADVANTAGES over Hetzner VM / M1 / WSL2:
# - Full KVM virtualization with virt-manager
# - Hardware video encoding/decoding (Intel QuickSync)
# - TPM 2.0 for secure boot and encryption
# - Native suspend/hibernate to disk
# - Fingerprint reader support
# - Full PipeWire with low-latency audio
# - Printing and scanning support
#
{ config, lib, pkgs, inputs, ... }:

let
  # Firefox 146+ overlay for native Wayland fractional scaling support
  pkgs-unstable = import inputs.nixpkgs-bleeding {
    system = pkgs.stdenv.hostPlatform.system;
    config.allowUnfree = true;
  };
  # Latest lazygit/lazydocker without bumping the main channel (see flake.nix)
  pkgs-lazygit = import inputs.nixpkgs-lazygit {
    system = pkgs.stdenv.hostPlatform.system;
    config.allowUnfree = true;
  };
  mkMoonlightRyzenDesktop = {
    scriptName,
    logName,
    workspaceName,
    fps,
    bitrate,
    packetSize ? 1024,
    videoCodec ? "H.264",
  }:
    pkgs.writeShellScriptBin scriptName ''
      #!${pkgs.bash}/bin/bash
      set -euo pipefail

      phase() {
        printf '${logName}: %s\n' "$*" >&2
      }

      fail() {
        phase "$1"
        exit 1
      }

      is_live_sway_socket() {
        local candidate="$1"
        [ -n "$candidate" ] || return 1
        [ -S "$candidate" ] || return 1
        SWAYSOCK="$candidate" ${pkgs.sway}/bin/swaymsg -s "$candidate" -t get_version >/dev/null 2>&1
      }

      resolve_sway_socket() {
        local candidate

        candidate="''${SWAYSOCK:-}"
        if is_live_sway_socket "$candidate"; then
          printf '%s\n' "$candidate"
          return 0
        fi

        candidate="$(${pkgs.systemd}/bin/systemctl --user show-environment 2>/dev/null | ${pkgs.gnused}/bin/sed -n 's/^SWAYSOCK=//p' | ${pkgs.coreutils}/bin/head -n1)"
        if is_live_sway_socket "$candidate"; then
          printf '%s\n' "$candidate"
          return 0
        fi

        while IFS= read -r candidate; do
          if is_live_sway_socket "$candidate"; then
            printf '%s\n' "$candidate"
            return 0
          fi
        done < <(${pkgs.findutils}/bin/find /run/user/$(${pkgs.coreutils}/bin/id -u) -maxdepth 1 -name 'sway-ipc.*.sock' | ${pkgs.coreutils}/bin/sort)

        return 1
      }

      socket_path="$(resolve_sway_socket || true)"

      runtime_dir="''${XDG_RUNTIME_DIR:-/run/user/$(${pkgs.coreutils}/bin/id -u)}"
      lock_file="$runtime_dir/moonlight-ryzen-desktop.lock"

      ${pkgs.coreutils}/bin/mkdir -p "$runtime_dir"

      run_moonlight() {
        export SDL_VIDEODRIVER=wayland
        exec ${pkgs.moonlight-qt}/bin/moonlight \
          stream \
          --resolution 1920x1200 \
          --fps ${toString fps} \
          --bitrate ${toString bitrate} \
          --packet-size ${toString packetSize} \
          --video-codec ${videoCodec} \
          --frame-pacing \
          --audio-config stereo \
          --display-mode windowed \
          --no-absolute-mouse \
          --capture-system-keys always \
          ryzen \
          Desktop
      }

      focus_existing_stream() {
        if [ -z "$socket_path" ]; then
          return 1
        fi

        if ! SWAYSOCK="$socket_path" ${pkgs.sway}/bin/swaymsg -t get_tree -r \
          | ${pkgs.jq}/bin/jq -e '
            .. | objects | select((.app_id? // "") == "com.moonlight_stream.Moonlight")
          ' >/dev/null 2>&1; then
          return 1
        fi

        phase "existing Moonlight session detected; focusing current stream"
        SWAYSOCK="$socket_path" ${pkgs.sway}/bin/swaymsg '[app_id="com.moonlight_stream.Moonlight"] focus' >/dev/null 2>&1 || true
        return 0
      }

      cleanup_stale_stream() {
        phase "cleaning up stale Moonlight session"
        while IFS= read -r stale_pid; do
          [ -n "$stale_pid" ] || continue
          ${pkgs.coreutils}/bin/kill "$stale_pid" >/dev/null 2>&1 || true
        done < <(${pkgs.procps}/bin/pgrep -f '${pkgs.moonlight-qt}/bin/moonlight[[:space:]]+stream([[:space:]].*)?[[:space:]]+ryzen[[:space:]]+Desktop([[:space:]]|$)' || true)

        while IFS= read -r stale_pid; do
          [ -n "$stale_pid" ] || continue
          if [ "$stale_pid" != "$$" ]; then
            ${pkgs.coreutils}/bin/kill "$stale_pid" >/dev/null 2>&1 || true
          fi
        done < <(${pkgs.procps}/bin/pgrep -f '/run/current-system/sw/bin/moonlight-ryzen-desktop(-remote)?' || true)

        attempts=0
        while ${pkgs.procps}/bin/pgrep -f '${pkgs.moonlight-qt}/bin/moonlight[[:space:]]+stream([[:space:]].*)?[[:space:]]+ryzen[[:space:]]+Desktop([[:space:]]|$)' >/dev/null 2>&1; do
          if [ "$attempts" -ge 20 ]; then
            fail "stale Moonlight processes would not exit"
          fi
          attempts=$((attempts + 1))
          ${pkgs.coreutils}/bin/sleep 0.25
        done
      }

      acquire_launch_lock() {
        exec 9>"$lock_file"
        if ${pkgs.util-linux}/bin/flock -n 9; then
          return 0
        fi

        focus_existing_stream && exit 0
        cleanup_stale_stream

        exec 9>"$lock_file"
        ${pkgs.util-linux}/bin/flock -n 9 || fail "another Ryzen Desktop launch is already in progress"
      }

      acquire_launch_lock

      if ${pkgs.procps}/bin/pgrep -f '${pkgs.moonlight-qt}/bin/moonlight[[:space:]]+stream([[:space:]].*)?[[:space:]]+ryzen[[:space:]]+Desktop([[:space:]]|$)' >/dev/null 2>&1; then
        focus_existing_stream && exit 0
        cleanup_stale_stream
      fi

      phase "checking ryzen host"
      if ! ${pkgs.openssh}/bin/ssh \
        -o BatchMode=yes \
        -o ConnectTimeout=5 \
        ryzen \
        /run/current-system/sw/bin/sunshine-primary-monitor-ensure; then
        phase "ryzen SSH preflight failed; continuing with direct Moonlight validation"
      fi

      phase "probing desktop stream"
      available_apps="$(${pkgs.coreutils}/bin/timeout 8s ${pkgs.moonlight-qt}/bin/moonlight list ryzen 2>&1 || true)"
      if [ -z "$available_apps" ]; then
        phase "Moonlight list probe produced no response; continuing with direct Desktop stream"
      elif ! printf '%s\n' "$available_apps" | ${pkgs.gnugrep}/bin/grep -Fx "Desktop" >/dev/null 2>&1; then
        printf '%s\n' "$available_apps" >&2
        phase "Moonlight list probe did not include Desktop; continuing with direct Desktop stream"
      fi

      if [ -z "$socket_path" ]; then
        phase "starting stream"
        run_moonlight
      fi

      original_workspace="$(${pkgs.sway}/bin/swaymsg -s "$socket_path" -t get_workspaces -r | ${pkgs.jq}/bin/jq -r '.[] | select(.focused) | .name')"
      moonlight_workspace="${workspaceName}"

      restore_workspace() {
        if [ -n "''${original_workspace:-}" ]; then
          ${pkgs.sway}/bin/swaymsg -s "$socket_path" workspace "$original_workspace" >/dev/null 2>&1 || true
        fi
      }

      trap 'restore_workspace' EXIT INT TERM

      # Keep launch-correlation metadata for the daemon, but drop project/terminal context.
      while IFS= read -r var_name; do
        case "$var_name" in
          I3PM_APP_ID|I3PM_APP_NAME|I3PM_EXPECTED_CLASS|I3PM_SCOPE|I3PM_TARGET_WORKSPACE|I3PM_TERMINAL_ANCHOR_ID)
            ;;
          I3PM_*)
            unset "$var_name"
            ;;
        esac
      done < <(${pkgs.coreutils}/bin/env | ${pkgs.gawk}/bin/awk -F= '/^I3PM_/ { print $1 }')

      phase "starting stream"
      export SDL_VIDEODRIVER=wayland
      ${pkgs.moonlight-qt}/bin/moonlight \
        stream \
        --resolution 1920x1200 \
        --fps ${toString fps} \
        --bitrate ${toString bitrate} \
        --packet-size ${toString packetSize} \
        --video-codec ${videoCodec} \
        --frame-pacing \
        --audio-config stereo \
        --display-mode windowed \
        --no-absolute-mouse \
        --capture-system-keys always \
        ryzen \
        Desktop &
      moonlight_pid=$!

      attempts=0
      until ${pkgs.sway}/bin/swaymsg -s "$socket_path" -t get_tree -r | ${pkgs.jq}/bin/jq -e '
        .. | objects | select((.app_id? // "") == "com.moonlight_stream.Moonlight")
      ' >/dev/null 2>&1; do
        if ! ${pkgs.coreutils}/bin/kill -0 "$moonlight_pid" >/dev/null 2>&1; then
          wait "$moonlight_pid"
          exit $?
        fi
        if [ "$attempts" -ge 40 ]; then
          break
        fi
        attempts=$((attempts + 1))
        ${pkgs.coreutils}/bin/sleep 0.25
      done

      # Move Moonlight to its workspace and remove borders (no forced fullscreen)
      ${pkgs.sway}/bin/swaymsg -s "$socket_path" '[app_id="com.moonlight_stream.Moonlight"] border none' >/dev/null 2>&1 || true
      ${pkgs.sway}/bin/swaymsg -s "$socket_path" '[app_id="com.moonlight_stream.Moonlight"] move container to workspace "'"$moonlight_workspace"'"' >/dev/null 2>&1 || true
      ${pkgs.sway}/bin/swaymsg -s "$socket_path" workspace "$moonlight_workspace" >/dev/null 2>&1 || true
      ${pkgs.sway}/bin/swaymsg -s "$socket_path" '[app_id="com.moonlight_stream.Moonlight"] focus' >/dev/null 2>&1 || true

      wait "$moonlight_pid"
    '';
  rustdeskConnectRyzen = pkgs.writeShellScriptBin "rustdesk-connect-ryzen" ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail

    host_ip="$(${pkgs.tailscale}/bin/tailscale ip -4 ryzen 2>/dev/null | ${pkgs.coreutils}/bin/head -n1)"

    if [ -z "$host_ip" ]; then
      host_ip="$(getent ahostsv4 ryzen | ${pkgs.gawk}/bin/awk 'NR == 1 { print $1 }')"
    fi

    if [ -z "$host_ip" ]; then
      echo "Unable to resolve ryzen to a Tailscale IPv4 address" >&2
      exit 1
    fi

    exec ${pkgs.rustdesk}/bin/rustdesk --connect "$host_ip"
  '';
  moonlightRyzenDesktop = mkMoonlightRyzenDesktop {
    scriptName = "moonlight-ryzen-desktop";
    logName = "moonlight-ryzen-desktop";
    workspaceName = "12: Ryzen Desktop";
    fps = 60;
    bitrate = 10000;
  };
  moonlightRyzenDesktopRemote = mkMoonlightRyzenDesktop {
    scriptName = "moonlight-ryzen-desktop-remote";
    logName = "moonlight-ryzen-desktop-remote";
    workspaceName = "32: Ryzen Desktop Remote";
    fps = 30;
    bitrate = 7000;
  };
  mac80211Xb8Fix =
    let
      kernel = config.boot.kernelPackages.kernel;
      srcDir = pkgs.writeTextDir "mac80211_xb8_fix.c" ''
        #include <linux/module.h>
        #include <linux/kernel.h>
        #include <linux/kmod.h>
        #include <linux/kprobes.h>
        #include <linux/ieee80211.h>
        #include <net/cfg80211.h>

        /*
         * Workaround for Technicolor CGM4981COM (Xfinity XB8) firmware bug:
         * The AP sets all 16 bytes of HT Operation basic_set (EID 61) to 0xff,
         * claiming that 4 spatial streams (MCS 0-76 + reserved bits) are mandatory
         * basic HT rates. Linux 6.x mac80211 ieee80211_verify_sta_ht_mcs_support()
         * rejects HT/VHT/HE when any bit in basic_set is not in the STA's 2x2 rx_mask,
         * logging "required MCSes not supported, disabling HT" and dropping Wi-Fi 6
         * clients down to 20 MHz legacy 802.11a/g (18-54 Mbps).
         */
        struct xb8_elems_parse_params {
          u32 mode;
          const u8 *start;
          size_t len;
        };

        static void sanitize_ies_buf(const u8 *data, size_t len)
        {
          const struct element *elem;
          struct ieee80211_ht_operation *ht_op;
          struct ieee80211_ht_cap *ht_cap;
          struct ieee80211_vht_cap *vht_cap;
          int i;
          bool bogus = false;

          if (!data || !len)
            return;

          elem = cfg80211_find_elem(WLAN_EID_HT_OPERATION, data, len);
          if (elem && elem->datalen >= sizeof(*ht_op)) {
            ht_op = (struct ieee80211_ht_operation *)elem->data;
            for (i = 1; i < IEEE80211_HT_MCS_MASK_LEN; i++) {
              if (ht_op->basic_set[i] != 0) {
                bogus = true;
                break;
              }
            }
            if (bogus) {
              memset(&ht_op->basic_set[1], 0, sizeof(ht_op->basic_set) - 1);
              pr_info_ratelimited("mac80211_xb8_fix: sanitized bogus HT basic_set MCS mask from AP\n");
            }
          }

          elem = cfg80211_find_elem(WLAN_EID_HT_CAPABILITY, data, len);
          if (elem && elem->datalen >= sizeof(*ht_cap)) {
            ht_cap = (struct ieee80211_ht_cap *)elem->data;
            if (ht_cap->mcs.tx_params == 0xff) {
              ht_cap->mcs.tx_params = IEEE80211_HT_MCS_TX_DEFINED;
              memset(&ht_cap->mcs.rx_mask[4], 0, 6);
              ht_cap->mcs.rx_highest = 0;
            }
          }

          elem = cfg80211_find_elem(WLAN_EID_VHT_CAPABILITY, data, len);
          if (elem && elem->datalen >= sizeof(*vht_cap)) {
            u32 cap;
            vht_cap = (struct ieee80211_vht_cap *)elem->data;
            cap = le32_to_cpu(vht_cap->vht_cap_info);
            if ((cap & IEEE80211_VHT_CAP_SU_BEAMFORMER_CAPABLE) &&
                !(cap & IEEE80211_VHT_CAP_BEAMFORMEE_STS_MASK)) {
              cap |= (3U << IEEE80211_VHT_CAP_BEAMFORMEE_STS_SHIFT);
              vht_cap->vht_cap_info = cpu_to_le32(cap);
            }
            /* Restrict STA->AP TX to 1 spatial stream (NSS 1, MCS 0-9) for +3 dB SNR */
            vht_cap->supp_mcs.rx_mcs_map = cpu_to_le16(0xfffe);
          }

          elem = cfg80211_find_ext_elem(WLAN_EID_EXT_HE_CAPABILITY, data, len);
          if (elem && elem->datalen >= 1 + sizeof(struct ieee80211_he_cap_elem) + 4) {
            __le16 *rx_mcs_80 = (__le16 *)(elem->data + 1 + sizeof(struct ieee80211_he_cap_elem));
            /* Restrict STA->AP HE TX to 1 spatial stream (NSS 1, MCS 0-11) for +3 dB SNR */
            *rx_mcs_80 = cpu_to_le16(0xfffe);
          }
        }

        static void sanitize_bss_ies(const struct cfg80211_bss_ies *ies)
        {
          if (ies && ies->len)
            sanitize_ies_buf(ies->data, ies->len);
        }

        static int handler_pre(struct kprobe *p, struct pt_regs *regs)
        {
        #if defined(__x86_64__)
          struct cfg80211_bss *cbss = (struct cfg80211_bss *)regs->dx;

          if (cbss) {
            rcu_read_lock();
            sanitize_bss_ies(rcu_dereference(cbss->ies));
            sanitize_bss_ies(rcu_dereference(cbss->beacon_ies));
            sanitize_bss_ies(rcu_dereference(cbss->proberesp_ies));
            rcu_read_unlock();
          }
        #endif
          return 0;
        }

        static int handler_parse_pre(struct kprobe *p, struct pt_regs *regs)
        {
        #if defined(__x86_64__)
          struct xb8_elems_parse_params *params =
            (struct xb8_elems_parse_params *)regs->di;

          if (params && params->start && params->len > 0 && params->len < 4096)
            sanitize_ies_buf(params->start, params->len);
        #endif
          return 0;
        }

        static struct kprobe kp = {
          .symbol_name = "ieee80211_determine_chan_mode",
          .pre_handler = handler_pre,
        };

        static struct kprobe kp_parse = {
          .symbol_name = "ieee802_11_parse_elems_full",
          .pre_handler = handler_parse_pre,
        };

        static int __init mac80211_xb8_fix_init(void)
        {
          int ret;

          request_module("mac80211");
          ret = register_kprobe(&kp);
          if (ret < 0)
            return ret;
          ret = register_kprobe(&kp_parse);
          if (ret < 0) {
            unregister_kprobe(&kp);
            return ret;
          }
          pr_info("mac80211_xb8_fix: loaded kprobes on %s and %s\n",
                  kp.symbol_name, kp_parse.symbol_name);
          return 0;
        }

        static void __exit mac80211_xb8_fix_exit(void)
        {
          unregister_kprobe(&kp_parse);
          unregister_kprobe(&kp);
          pr_info("mac80211_xb8_fix: unloaded\n");
        }

        module_init(mac80211_xb8_fix_init);
        module_exit(mac80211_xb8_fix_exit);
        MODULE_SOFTDEP("pre: mac80211");
        MODULE_LICENSE("GPL");
        MODULE_DESCRIPTION("Sanitize bogus Xfinity XB8 HT basic_set MCS mask in mac80211");
      '';
    in
    pkgs.stdenv.mkDerivation {
      pname = "mac80211-xb8-fix";
      version = kernel.version;
      dontUnpack = true;
      nativeBuildInputs = kernel.moduleBuildDependencies;
      buildPhase = ''
        cp ${srcDir}/mac80211_xb8_fix.c .
        echo "obj-m += mac80211_xb8_fix.o" > Makefile
        make -C ${kernel.dev}/lib/modules/${kernel.modDirVersion}/build M=$(pwd) modules
      '';
      installPhase = ''
        install -D -m 644 mac80211_xb8_fix.ko $out/lib/modules/${kernel.modDirVersion}/updates/mac80211_xb8_fix.ko
      '';
    };
in
{
  imports = [
    # Base configuration
    ./base.nix

    # Hardware
    ../hardware/thinkpad.nix

    # nixos-hardware modules for Intel laptops
    inputs.nixos-hardware.nixosModules.common-cpu-intel
    inputs.nixos-hardware.nixosModules.common-pc-laptop
    inputs.nixos-hardware.nixosModules.common-pc-laptop-ssd

    # ThinkPad-specific optimizations (TrackPoint, etc.)
    inputs.nixos-hardware.nixosModules.lenovo-thinkpad

    # Desktop environment (Sway - Wayland compositor)
    ../modules/desktop/sway.nix

    # Kernel-level key remapper (Copilot F23→Compose for voxtype)
    ../modules/services/keyd.nix

    # Services
    ../modules/services/development.nix
    ../modules/services/networking.nix
    ../modules/services/onepassword.nix
    # Feature 117: System service removed - now runs as home-manager user service

    # Bare metal optimizations (KVM, Podman, printing, TPM, etc.)
    ../modules/services/bare-metal.nix
    ./thinkpad-lid-policy.nix

    # Browser integrations with 1Password
    ../modules/desktop/firefox-1password.nix

    # Chrome policy for Claude-in-Chrome extension (force-install in all Chrome profiles)
    ../modules/desktop/chrome-claude.nix

    # Chrome policy for Kimi WebBridge extension (force-install in all Chrome profiles)
    ../modules/desktop/chrome-kimi-webbridge.nix

    # Chrome policy for OpenAI ChatGPT extension (force-install in all Chrome profiles)
    ../modules/desktop/chrome-chatgpt.nix

    # Chrome managed bookmarks (one entry per PWA, generated from pwa-sites.nix)
    ../modules/desktop/chrome-bookmarks.nix

    # Chrome sign-in + sync policy (allow user to sign in, sync bookmarks etc.)
    ../modules/desktop/chrome-sync.nix

    # Chrome policy for native Gemini and Generative AI features
    ../modules/desktop/chrome-gemini.nix

    # Chrome policy for Google's Model Context Tool Inspector (WebMCP) extension
    ../modules/desktop/chrome-webmcp.nix

    # Sunshine game streaming (Intel Quick Sync hardware encoding)
    ../modules/desktop/sunshine.nix

    # Cachix Deploy for automated deployments
    ../modules/services/cachix-deploy.nix
  ];

  # Firefox 146+ overlay for native Wayland fractional scaling support
  nixpkgs.overlays = [
    (final: prev: {
      firefox = pkgs-unstable.firefox;
      firefox-unwrapped = pkgs-unstable.firefox-unwrapped;

      # Latest lazygit / lazydocker without bumping the main channel.
      # Wrap them (and k9s) so `infocmp` (ncurses) is always on their PATH —
      # otherwise these gocui/tcell TUIs crash on startup when launched from
      # the systemd/daemon context with a stripped PATH. See
      # packages/with-terminfo.nix. Wrapping in the overlay means every
      # reference (package lists + ${pkgs.x}/bin string interps) gets it.
      lazygit = (import ../packages/with-terminfo.nix { pkgs = prev; }) pkgs-lazygit.lazygit "lazygit";
      lazydocker = (import ../packages/with-terminfo.nix { pkgs = prev; }) pkgs-lazygit.lazydocker "lazydocker";
      k9s = (import ../packages/with-terminfo.nix { pkgs = prev; }) (prev.callPackage ../packages/k9s.nix { k9s = prev.k9s; }) "k9s";
      gh-dash = prev.callPackage ../packages/gh-dash.nix { };
      gh-enhance = prev.callPackage ../packages/gh-enhance.nix { };
      diffnav = prev.callPackage ../packages/diffnav.nix { };

      # NOTE: google-chrome stable comes straight from nixpkgs (149+). Do NOT pin
      # an older version here: Chrome's fallback Cast CRL expires 20 weeks after
      # the browser build date (cast_crl.cc "CRL - Not time-valid"), after which
      # cast device auth fails and the picker shows "No devices found".
      # (A stale 145 pin caused exactly that on 2026-07-29.)

      # Chrome beta/dev channel (for testing features behind newer flags)

      # Chrome 146 beta/dev channel (for testing features behind newer flags)
      google-chrome-beta = prev.callPackage ../packages/google-chrome-beta.nix { };
      google-chrome-unstable = prev.callPackage ../packages/google-chrome-unstable.nix { };
    })
  ];

  # System identification
  networking.hostName = "thinkpad";

  # Enable Sway Wayland compositor
  services.sway.enable = true;

  # ========== BARE METAL FEATURES ==========
  # These are NOT possible on Hetzner VM, M1/Asahi, or WSL2
  services.bare-metal = {
    enable = true;

    # KVM/libvirt removed — unused (no VMs; libvirtd only idle-flapped as failed).
    # Drops libvirtd, virt-manager, and the libvirtd/kvm groups.
    enableVirtualization = false;

    # Podman rootless containers (complement to Docker)
    enablePodman = true;

    # Printing support with CUPS
    # (Hetzner: headless server, WSL2: use Windows printing)
    enablePrinting = true;

    # Fingerprint reader (ThinkPad has built-in fingerprint sensor)
    # Enable after enrolling fingerprint with: fprintd-enroll
    enableFingerprint = true;

    # No gaming on laptop (battery life)
    enableGaming = false;
  };

  # Sunshine host removed on this laptop: it was never paired with any client
  # (no sunshine_state.json after weeks of uptime) yet ran 24/7 with
  # cap_sys_admin + uinput and open tailnet ports. The ThinkPad is a Moonlight
  # *client* of the ryzen Sunshine host (see the Moonlight.conf activation and
  # keybindings above); re-add services.sunshine-streaming here only to stream
  # FROM the laptop.

  # Feature 117: i3 Project Daemon now runs as home-manager user service
  # Daemon lifecycle managed by graphical-session.target (see home-vpittamp.nix)

  # Local observability (grafana-alloy, Feature 129) was REMOVED 2026-07-26 —
  # herdr tracks AI sessions natively and no local producer remained. Hub-side
  # K8s observability (stacks repo) is unaffected.

  # Display manager - greetd for Wayland/Sway login
  services.greetd = {
    enable = true;
    settings = {
      default_session = {
        command = "${pkgs.tuigreet}/bin/tuigreet --time --remember --cmd sway";
        user = "greeter";
      };
    };
  };

  # Swap configured in hardware/thinkpad.nix (uses dedicated partition)

  # ========== HIBERNATION SUPPORT ==========
  # Full suspend-to-disk. Resume from the dedicated swap PARTITION (same device
  # as swapDevices in hardware/thinkpad.nix). It is 34 GiB > 30 GiB RAM, so it
  # can hold a full hibernation image, and needs no resume_offset.
  #
  # resumeDevice MUST be a block device. A file path here (the old
  # "/var/lib/swapfile") makes newer systemd's hibernate-resume generator emit
  # `resume=/var/lib/swapfile` and then wait forever for that non-existent
  # device — "A start job is running for /var/lib/swapfile (… / no limit)" —
  # which hangs boot on 26.11. The stale /var/lib/swapfile file is unused (it is
  # not in swapDevices) and can be deleted to reclaim 16 GiB.
  boot.resumeDevice = "/dev/disk/by-uuid/2d05acef-3fb1-4264-be73-8a71fcaeab1d";

  # Memory management + TCP congestion control for Wi-Fi
  boot.kernel.sysctl = {
    "vm.swappiness" = 10;
    "vm.vfs_cache_pressure" = 50;
    "vm.dirty_background_ratio" = 5;
    "vm.dirty_ratio" = 10;
    # Laptop-optimized writeback (less aggressive)
    "vm.laptop_mode" = 5;
    "net.ipv4.tcp_congestion_control" = lib.mkForce "cubic";
    "net.core.default_qdisc" = lib.mkForce "fq_codel";
    "net.ipv4.tcp_limit_output_bytes" = 262144;
    "net.ipv6.conf.wlp0s20f3.disable_ipv6" = 1;
  };

  # Boot configuration for standard x86_64 UEFI
  boot.loader.systemd-boot.enable = true;
  boot.loader.systemd-boot.configurationLimit = 10;
  boot.loader.efi.canTouchEfiVariables = true;

  # Increase tmpfs size for kernel builds
  boot.tmp.tmpfsSize = "75%";

  # Kernel parameters for Intel Core Ultra (Meteor Lake)
  boot.kernelParams = [
    # Intel graphics tweaks for Meteor Lake
    "i915.enable_psr=0"           # Disable Panel Self Refresh (can cause flickering)
    "i915.enable_fbc=1"           # Enable framebuffer compression
    # Power management
    "intel_pstate=active"         # Use Intel P-state driver
    # Meteor Lake specific
    "i915.force_probe=*"          # Force probe for newer Intel GPUs if needed
  ];

  # Workaround for Xfinity XB8 (Technicolor CGM4981COM) HT Operation basic_set=0xff
  # and VHT Beamformee-STS=0 bugs on 2x2 Intel iwlwifi cards, plus CAM power scheme.
  boot.extraModulePackages = [ mac80211Xb8Fix ];
  boot.kernelModules = [ "mac80211_xb8_fix" ];
  boot.extraModprobeConfig = ''
    options iwlwifi power_save=0 bt_coex_active=0 disable_11ax=1 11n_disable=8 amsdu_size=4
    options iwlmvm power_scheme=1
  '';

  # Feature 117: i3-project-daemon now runs as home-manager user service
  # No systemd dependency needed - user service binds to graphical-session.target
  systemd.services.home-manager-vpittamp = {
    serviceConfig = {
      Restart = "on-failure";
      RestartSec = "2s";
      StartLimitBurst = 3;
      StartLimitIntervalSec = 30;
    };
  };

  # NetworkManager for WiFi (default wpa_supplicant backend).
  # NOTE: Do NOT use wifi.backend = "iwd" here: iwd 3.12 sends an incomplete
  # NL80211_ATTR_HT_CAPABILITY_MASK on connect against the Xfinity XB8 gateway,
  # causing Linux 6.18 mac80211 to log "wlan0: required MCSes not supported,
  # disabling HT" and fall back to legacy 802.11a/g (18-54 Mbps) instead of
  # Wi-Fi 6/6E (802.11ax HE).
  networking.networkmanager = {
    enable = true;
    wifi.powersave = false;
  };

  # Fonts - Nerd Fonts for desktop shell glyph icons
  fonts = {
    packages = let nerdFonts = pkgs."nerd-fonts"; in [
      nerdFonts.jetbrains-mono
      nerdFonts.fira-code
      nerdFonts.ubuntu
      nerdFonts.symbols-only
    ];
    fontconfig.defaultFonts = {
      monospace = [ "JetBrainsMono Nerd Font Mono" ];
      sansSerif = [ "Ubuntu Nerd Font" ];
    };
  };

  # Display configuration
  # ThinkPad display - adjust DPI based on actual panel resolution
  services.xserver = {
    dpi = 120;  # Adjust based on your panel

    serverFlagsSection = ''
      Option "DPI" "120 x 120"
    '';

    videoDrivers = [ "modesetting" ];  # Use modesetting for Intel Arc
  };

  # Display scaling configuration for Wayland
  environment.sessionVariables = {
    # Cursor size for HiDPI
    XCURSOR_SIZE = "24";

    # Java applications scaling
    _JAVA_OPTIONS = "-Dsun.java2d.uiScale=1.0";

    # Electron apps
    ELECTRON_FORCE_IS_PACKAGED = "true";

    # ========== VA-API HARDWARE VIDEO ACCELERATION ==========
    # Intel Arc (Meteor Lake) uses the iHD VA-API driver
    LIBVA_DRIVER_NAME = "iHD";

    # Enable Wayland for Electron apps
    NIXOS_OZONE_WL = "1";
  };

  # Touchpad configuration with natural scrolling (ThinkPad trackpad + TrackPoint)
  services.libinput = {
    enable = true;
    touchpad = {
      naturalScrolling = true;
      tapping = true;
      clickMethod = "clickfinger";
      disableWhileTyping = true;
      scrollMethod = "twofinger";
      accelProfile = "adaptive";
      accelSpeed = "0.0";
    };
  };

  # Platform configuration
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";

  # CPU configuration
  powerManagement.cpuFreqGovernor = lib.mkDefault "powersave";

  # Hardware acceleration
  hardware.graphics.enable = true;

  # Firmware updates
  hardware.enableRedistributableFirmware = true;

  # Enable fwupd for firmware updates (LVFS)
  services.fwupd.enable = true;

  # ========== THUNDERBOLT/USB4 SUPPORT (Feature 115) ==========
  # Enable bolt daemon for Thunderbolt device authorization
  # Allows docking stations and external displays via Thunderbolt
  services.hardware.bolt.enable = true;

  # Fingerprint reader support (Elan 04f3:0c8c MOC Sensor)
  # Enroll fingerprint with: fprintd-enroll
  # Verify with: fprintd-verify
  services.fprintd.enable = true;

  # PAM integration for fingerprint authentication
  # Keep separate from fprintd to avoid login conflicts
  # Reference: https://github.com/NixOS/nixpkgs/issues/171136
  security.pam.services = {
    # Sudo with fingerprint (fingerprint OR password)
    sudo.fprintAuth = true;

    # Screen lock (swaylock)
    swaylock.fprintAuth = true;

    # Polkit for GUI privilege escalation
    polkit-1.fprintAuth = true;

    # Login fingerprint - enable cautiously (can cause issues with some display managers)
    # greetd.fprintAuth = true;
  };

  # pam_fprintd is tried first and its default verify timeout is 30s, so a
  # password unlock/sudo without a finger on the sensor hangs for 30s before
  # the password prompt is even consulted (seen in the lock-screen PAM log:
  # "Place your right index finger..." → "Verification timed out" 30s later).
  # Cap the fingerprint wait at 2s: a successful scan completes in ~1s, and
  # the password path (the lock screen's "Checking…" state) then takes ~2s
  # worst case instead of 30s.
  security.pam.services.swaylock.rules.auth.fprintd.settings.timeout = 2;
  security.pam.services.sudo.rules.auth.fprintd.settings.timeout = 2;
  security.pam.services.polkit-1.rules.auth.fprintd.settings.timeout = 2;

  # Polkit rules for fingerprint and 1Password integration
  security.polkit.extraConfig = lib.mkAfter ''
    // Allow wheel users to enroll fingerprints without password
    polkit.addRule(function(action, subject) {
      if (action.id == "net.reactivated.fprint.device.enroll" &&
          subject.isInGroup("wheel")) {
        return polkit.Result.YES;
      }
    });
  '';

  # Automatic garbage collection
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 7d";
  };

  # 1Password configuration
  services.onepassword = {
    enable = true;
    user = "vpittamp";

    gui.enable = true;

    automation = {
      enable = true;
      tokenReference = "op://Employee/kzfqt6yulhj6glup3w22eupegu/credential";
    };

    passwordManagement = {
      enable = false;
      users.vpittamp = {
        enable = true;
        passwordReference = "op://CLI/NixOS User Password/password";
      };
      updateInterval = "hourly";
    };

    ssh.enable = true;
  };

  # Firefox with 1Password and PWA support
  programs.firefox-1password = {
    enable = true;
  };

  # Cachix Deploy Agent - Auto-deploy on git push
  # Token stored in 1Password, manually bootstrapped on first setup
  services.cachix-deploy = {
    enable = true;
    onePassword = {
      enable = true;
      tokenReference = "op://CLI/Cachix Deploy Agent Thinkpad/token";
    };
  };

  # Fallback password for initial setup
  users.users.vpittamp.initialPassword = lib.mkDefault "nixos";

  # Add user to required groups
  users.users.vpittamp.extraGroups = [ "wheel" "networkmanager" "video" "seat" "input" "onepassword" ];

  # Bluetooth support (common in ThinkPads)
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
    settings = {
      General = {
        Experimental = true;
      };
    };
  };

  # Bluetooth manager GUI
  services.blueman.enable = true;

  # UPower for battery monitoring
  services.upower.enable = true;

  # TLP for better laptop power management
  services.tlp = {
    enable = true;
    settings = {
      CPU_SCALING_GOVERNOR_ON_AC = "performance";
      CPU_SCALING_GOVERNOR_ON_BAT = "powersave";

      CPU_ENERGY_PERF_POLICY_ON_AC = "performance";
      CPU_ENERGY_PERF_POLICY_ON_BAT = "balance_power";

      # Intel CPU specific
      CPU_HWP_DYN_BOOST_ON_AC = 1;
      CPU_HWP_DYN_BOOST_ON_BAT = 0;

      # WiFi power saving
      WIFI_PWR_ON_AC = "off";
      WIFI_PWR_ON_BAT = "on";

      # USB autosuspend
      USB_AUTOSUSPEND = 1;
      # Never autosuspend the portable external monitor's USB chain: its
      # touch controller (SiS 0457:0819) and onboard hub (1a40:0101) brown
      # out on autosuspend, power-cycling the panel every ~6 minutes and
      # blanking HDMI-A-1.
      USB_DENYLIST = "0457:0819 1a40:0101";

      # Runtime PM for PCIe
      RUNTIME_PM_ON_AC = "on";
      RUNTIME_PM_ON_BAT = "auto";

      # Battery charge thresholds (ThinkPad specific - uncomment if supported)
      # START_CHARGE_THRESH_BAT0 = 75;
      # STOP_CHARGE_THRESH_BAT0 = 80;
    };
  };

  # Disable power-profiles-daemon (conflicts with TLP)
  services.power-profiles-daemon.enable = false;

  # Thermald for Intel thermal management
  services.thermald.enable = true;

  # Additional packages for laptop
  environment.systemPackages = with pkgs; [
    # Terminal
    ghostty

    # Voxtype - Push-to-talk speech-to-text (Vulkan, works in tmux/CLI)
    (callPackage ../packages/voxtype.nix { })

    # Brightness control
    brightnessctl

    imagemagick
    librsvg

    # Remote access
    tailscale
    rustdesk
    rustdeskConnectRyzen
    moonlight-qt
    moonlightRyzenDesktop
    moonlightRyzenDesktopRemote
    remmina
    rustdesk-flutter  # Open-source remote desktop

    # 1Password GUI
    _1password-gui

    # Power management utilities
    powertop
    acpi
    tlp               # TLP CLI

    # ThinkPad specific tools
    tpacpi-bat        # ThinkPad ACPI battery control
    thinkfan          # ThinkPad fan control (optional, TLP handles most)

    # Hardware info
    pciutils
    usbutils
    lshw

    # ========== BARE METAL EXCLUSIVE PACKAGES ==========
    # These require physical hardware (not available on Hetzner/M1/WSL)

    # Hardware video acceleration (Intel QuickSync)
    intel-gpu-tools   # Intel GPU debugging (intel_gpu_top)
    libva-utils       # VA-API verification (vainfo)
    vdpauinfo         # VDPAU verification

    # Disk encryption and security
    cryptsetup        # LUKS disk encryption
    yubikey-manager   # YubiKey management (if you have one)

    # Hardware monitoring
    s-tui             # Stress test + monitoring TUI
    stress-ng         # CPU stress testing

    # Laptop-specific power tools
    acpid             # ACPI daemon
    upower            # Power device info

    # USB device management
    udiskie           # Automount USB drives

    # Webcam (if present)
    v4l-utils         # Video4Linux utilities
    cameractrls       # Webcam controls

    # ========== SCREEN RECORDING (Feature 115) ==========
    # Hardware-accelerated screen recording with Intel QuickSync
    obs-studio        # PipeWire/portal screen capture validation and streaming
    wf-recorder       # Wayland screen recorder with VAAPI support
    grim              # Screenshot utility for Wayland
    slurp             # Region selection for screenshots/recording
  ];

  # Firefox configuration with PWA support
  programs.firefox = {
    enable = lib.mkDefault true;
  };

  # Tailscale VPN
  services.tailscale = {
    enable = true;
    useRoutingFeatures = "client";
    # Keep plain SSH over the tailnet so tagged infrastructure devices like
    # ryzen can still reach this user-owned workstation.
    # --accept-routes is set centrally via extraSetFlags in
    # modules/services/networking.nix (extraUpFlags never applied: no authKeyFile).
  };

  # Firewall configuration
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 5900 ];  # SSH and VNC
    allowedUDPPorts = [ 5353 ];     # mDNS for Chrome Chromecast / TV discovery on LAN
    # Phase 4: OTEL remote-session sink (port 4320) retired — cross-host
    # sessions now flow through the K8s session-aggregator at
    # ai-sessions-ryzen.tail286401.ts.net, not host-to-host push.
    checkReversePath = "loose";  # For Tailscale
    # Mobile hotspot TTL/Hop-Limit normalization: when tethered to an iPhone
    # hotspot, the phone decrements outgoing TTL/Hop-Limit by 1 (64 -> 63),
    # which triggers carrier tether throttling (~600 Kbps on Verizon, especially
    # on IPv6 where iOS Router Advertisements force hoplimit=64). Bump only
    # default-TTL/HL (64 -> 65) on Wi-Fi egress so packets leave the phone at 64
    # while preserving TTL/HL=255 required by RFC 4861 IPv6 NDP and RFC 6762 mDNS.
    extraCommands = ''
      iptables -t mangle -C POSTROUTING -o wlan0 -m ttl --ttl-eq 64 -j TTL --ttl-set 65 2>/dev/null \
        || iptables -t mangle -A POSTROUTING -o wlan0 -m ttl --ttl-eq 64 -j TTL --ttl-set 65
      ip6tables -t mangle -C POSTROUTING -o wlan0 -m hl --hl-eq 64 -j HL --hl-set 65 2>/dev/null \
        || ip6tables -t mangle -A POSTROUTING -o wlan0 -m hl --hl-eq 64 -j HL --hl-set 65
    '';
    extraStopCommands = ''
      iptables -t mangle -D POSTROUTING -o wlan0 -m ttl --ttl-eq 64 -j TTL --ttl-set 65 2>/dev/null || true
      ip6tables -t mangle -D POSTROUTING -o wlan0 -m hl --hl-eq 64 -j HL --hl-set 65 2>/dev/null || true
    '';
  };

  # ========== ADVANCED AUDIO (BARE METAL) ==========
  # Full PipeWire with low-latency and Bluetooth codecs
  # (Hetzner: audio streaming only, M1: limited codec support)
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    jack.enable = true;  # For pro audio applications

    # Low-latency audio configuration
    extraConfig.pipewire = {
      "92-low-latency" = {
        "context.properties" = {
          "default.clock.rate" = 48000;
          "default.clock.quantum" = 256;
          "default.clock.min-quantum" = 32;
          "default.clock.max-quantum" = 1024;
        };
      };
    };

    # WirePlumber configuration for better Bluetooth
    wireplumber.extraConfig = {
      "10-bluez" = {
        "monitor.bluez.properties" = {
          "bluez5.enable-sbc-xq" = true;
          "bluez5.enable-msbc" = true;
          "bluez5.enable-hw-volume" = true;
          "bluez5.codecs" = [ "sbc" "sbc_xq" "aac" "ldac" "aptx" "aptx_hd" ];
        };
      };

      # Jabra Evolve2 85 USB dongle - auto-prioritize when connected
      "50-jabra-usb" = {
        "monitor.alsa.rules" = [
          {
            matches = [
              { "device.vendor.id" = "2830"; }  # 0x0b0e = 2830 decimal (GN Audio/Jabra)
            ];
            actions = {
              update-props = {
                "device.description" = "Jabra Evolve2 85";
                "priority.driver" = 2000;
                "priority.session" = 2000;
              };
            };
          }
          {
            matches = [
              { "node.name" = "~alsa_output.usb-0b0e_Jabra*"; }
            ];
            actions = {
              update-props = {
                "node.description" = "Jabra Evolve2 85 Output";
                "priority.driver" = 2000;
                "priority.session" = 2000;
              };
            };
          }
          {
            matches = [
              { "node.name" = "~alsa_input.usb-0b0e_Jabra*"; }
            ];
            actions = {
              update-props = {
                "node.description" = "Jabra Evolve2 85 Mic";
                "priority.driver" = 2000;
                "priority.session" = 2000;
              };
            };
          }
        ];
      };

      # Jabra Evolve2 85 over BLUETOOTH - prioritize its output/input so that,
      # when the headset exposes a mic (HFP mode), it becomes the default source
      # for dictation without any script forcing a profile switch. (Forcing HFP
      # collapses A2DP stereo to mono and leaves the headset stuck/"muted".)
      "55-jabra-bluetooth" = {
        "monitor.bluez.rules" = [
          {
            matches = [
              { "device.name" = "~bluez_card.*Jabra.*"; }
            ];
            actions = {
              update-props = {
                "device.description" = "Jabra Evolve2 85";
                "bluez5.auto-connect" = [ "a2dp_sink" "hfp_hf" ];
              };
            };
          }
          {
            matches = [
              { "node.name" = "~bluez_output.*Jabra.*"; }
            ];
            actions = {
              update-props = {
                "node.description" = "Jabra Evolve2 85 Output";
                "priority.driver" = 2000;
                "priority.session" = 2000;
              };
            };
          }
          {
            matches = [
              { "node.name" = "~bluez_input.*Jabra.*"; }
            ];
            actions = {
              update-props = {
                "node.description" = "Jabra Evolve2 85 Mic";
                "priority.driver" = 2000;
                "priority.session" = 2000;
              };
            };
          }
        ];
      };
    };
  };

  systemd.user.services.thinkpad-audio-defaults = {
    description = "Restore ThinkPad internal speaker when Bluetooth is not active";
    wantedBy = [ "sway-session.target" ];
    partOf = [ "sway-session.target" ];
    after = [ "pipewire.service" "wireplumber.service" "sway-session.target" ];

    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "thinkpad-audio-defaults" ''
        set -euo pipefail

        export XDG_RUNTIME_DIR="/run/user/$(${pkgs.coreutils}/bin/id -u)"
        export PULSE_SERVER="unix:$XDG_RUNTIME_DIR/pulse/native"

        speaker_sink='alsa_output.pci-0000_00_1f.3-platform-skl_hda_dsp_generic.HiFi__Speaker__sink'

        attempts=0
        until ${pkgs.pulseaudio}/bin/pactl info >/dev/null 2>&1; do
          if [ "$attempts" -ge 40 ]; then
            echo "pactl not ready, skipping ThinkPad audio restore" >&2
            exit 0
          fi
          attempts=$((attempts + 1))
          sleep 0.5
        done

        attempts=0
        until ${pkgs.pulseaudio}/bin/pactl list short sinks 2>/dev/null | ${pkgs.gnugrep}/bin/grep -q "$speaker_sink"; do
          if [ "$attempts" -ge 40 ]; then
            echo "ThinkPad speaker sink not ready, skipping audio restore" >&2
            exit 0
          fi
          attempts=$((attempts + 1))
          sleep 0.5
        done

        if ${pkgs.pulseaudio}/bin/pactl list short sinks 2>/dev/null | ${pkgs.gnugrep}/bin/grep -q '^bluez_output\.'; then
          exit 0
        fi

        ${pkgs.pulseaudio}/bin/pactl set-default-sink "$speaker_sink" || true
        ${pkgs.pulseaudio}/bin/pactl set-sink-mute "$speaker_sink" false || true
      '';
    };
  };

  # Enable rtkit for real-time audio scheduling
  security.rtkit.enable = true;

  # ========== USB AUTOMOUNT ==========
  # Automatic mounting of USB drives
  services.udisks2.enable = true;
  services.gvfs.enable = true;  # For GUI file managers

  # ========== LIBRECHAT AI CHAT PLATFORM (DISABLED) ==========
  # Open-source AI chat UI with MongoDB backend
  # Disabled 2026-06-29: the service was crash-looping (Failed to load
  # environment files; systemd restart counter in the hundreds, ~every 10s),
  # matching the ryzen decision (2026-05-28). LLM access is via the hub MLflow
  # AI Gateway now; this also stops the orphaned node + mongodb churn.
  services.librechat = {
    enable = false;
    enableLocalDB = false;

    # Credentials file with secrets (CREDS_KEY, CREDS_IV, JWT_SECRET, JWT_REFRESH_SECRET)
    # Generate with: for v in CREDS_KEY JWT_SECRET JWT_REFRESH_SECRET; do echo "$v=$(openssl rand -hex 32)"; done; echo "CREDS_IV=$(openssl rand -hex 16)"
    credentialsFile = "/etc/librechat/credentials";

    env = {
      HOST = "0.0.0.0";
      ALLOW_REGISTRATION = true;
      # Trust K8s cluster CA for outbound HTTPS to *.cnoe.localtest.me services
      NODE_EXTRA_CA_CERTS = "/etc/ssl/certs/ca-certificates.crt";
    };

    settings = {
      version = "1.0.8";
      cache = true;
    };
  };

  # System state version
  system.stateVersion = "25.11";
}
