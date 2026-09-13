# NetworkManager profile hygiene.
#
# networking.networkmanager.ensureProfiles writes to
# /run/NetworkManager/system-connections and never touches /etc, so declaring a
# profile does not remove the stateful one it was meant to replace. Both
# directories are connection directories and NetworkManager dedupes by UUID, not
# by filename, so a leftover /etc profile with a different UUID loads as a
# *second* connection with the same name. That is not hypothetical: on the
# surface, the declared 'Linksys 416' (c520f3e2...) sat inert for weeks while
# NetworkManager actually used the stateful 9e721534... from /etc.
#
# Leftovers are not merely untidy. On 2026-09-12 a stale 'XFSETUP-37B4' profile
# -- an Xfinity gateway setup SSID saved on surface-pro3's install day -- took
# the house's Home Assistant hub off the network for 18h43m: a WAN blip dropped
# the association, NetworkManager fell through to that dead profile, failed it
# six times, declared the activation failed, and never tried anything again.
#
# So: keep an explicit allowlist and delete the rest. `keep` is the set of
# profile names that may remain in /etc -- the declaratively-managed ones plus,
# on a portable machine, the roaming networks that are legitimately stateful
# (you add a hotel's Wi-Fi in the field, not in a commit).
#
# The guard is the part that matters. Deleting the profile a host is currently
# reachable through, when its declared replacement is unusable, strands the
# machine -- which is the exact failure this module exists to prevent. So any
# profile that is also declared is removed only once the generated file is on
# disk with a real substituted PSK; if the environmentFiles secret is missing or
# a variable did not expand, the stateful file stays and the host stays up.
{ config, lib, pkgs, ... }:

let
  cfg = config.services.nmProfileHygiene;
  etcDir = "/etc/NetworkManager/system-connections";
  runDir = "/run/NetworkManager/system-connections";
in
{
  options.services.nmProfileHygiene = {
    enable = lib.mkEnableOption "pruning of undeclared NetworkManager profiles";

    keep = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "Linksys 416" "iPhone (2)" ];
      description = ''
        Profile names (the filename without .nmconnection) allowed to remain in
        ${etcDir}. Everything else there is deleted. A name that is also
        declared via ensureProfiles is still removed from /etc once the
        generated copy is valid, since the generated one supersedes it.
      '';
    };

    declared = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = lib.attrNames config.networking.networkmanager.ensureProfiles.profiles;
      defaultText = lib.literalExpression "attrNames config.networking.networkmanager.ensureProfiles.profiles";
      description = ''
        Profiles managed by ensureProfiles. The stateful /etc copy of each is
        removed once the generated file exists with a substituted PSK. Defaults
        to whatever is declared, which is almost always what you want.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.nm-prune-foreign-profiles = {
      description = "Remove undeclared NetworkManager profiles";
      wantedBy = [ "multi-user.target" ];
      # Strictly after ensure-profiles, which is itself after NetworkManager.
      # Ordering this before NetworkManager as well would close a cycle
      # (NM -> ensure-profiles -> prune -> NM) that systemd would break by
      # silently dropping one edge. Running late is safe as long as the
      # declared profiles carry a higher autoconnect-priority than the strays,
      # so they win the boot-time autoconnect even while strays still exist.
      after = lib.optional (cfg.declared != [ ]) "NetworkManager-ensure-profiles.service";
      requires = lib.optional (cfg.declared != [ ]) "NetworkManager-ensure-profiles.service";
      path = [ pkgs.networkmanager ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        etc=${lib.escapeShellArg etcDir}
        run=${lib.escapeShellArg runDir}
        [ -d "$etc" ] || exit 0
        shopt -s nullglob

        keep=(${lib.concatMapStringsSep " " lib.escapeShellArg cfg.keep})
        declared=(${lib.concatMapStringsSep " " lib.escapeShellArg cfg.declared})

        # Every variable in these helpers is `local`. Without that, the psk check
        # below assigned to `f` -- the same name as the loop variable it is
        # called from -- and the loop then deleted the freshly generated /run
        # profile instead of the superseded /etc one, on a host whose network
        # depends on it. Caught on the surface on 2026-09-13.
        in_list() {
          local needle="$1" item
          shift
          for item in "$@"; do
            [ "$item" = "$needle" ] && return 0
          done
          return 1
        }

        # A generated profile is usable only if its psk actually expanded. An
        # empty value, or one still starting with '$', means the environment
        # file did not do its job.
        declared_valid() {
          local gen psk
          gen="$run/$1.nmconnection"
          [ -r "$gen" ] || return 1
          if ! grep -q '^psk=' "$gen"; then
            # No PSK at all is fine -- an open or non-wifi profile.
            return 0
          fi
          psk=$(grep -m1 '^psk=' "$gen" | cut -d= -f2-)
          case "$psk" in
            ""|'$'*) return 1 ;;
            *) return 0 ;;
          esac
        }

        pruned=0
        for f in "$etc"/*.nmconnection; do
          name=$(basename "$f" .nmconnection)

          if in_list "$name" ''${declared[@]+"''${declared[@]}"}; then
            if declared_valid "$name"; then
              echo "declared '$name' is valid; removing superseded $f"
              rm -f "$f"
              pruned=1
            else
              echo "WARNING: declared '$name' is missing or has an unsubstituted PSK."
              echo "WARNING: keeping $f so this host stays reachable. Check ensureProfiles.environmentFiles."
            fi
            continue
          fi

          if in_list "$name" ''${keep[@]+"''${keep[@]}"}; then
            continue
          fi

          echo "pruning undeclared NetworkManager profile: $name"
          rm -f "$f"
          pruned=1
        done

        # NetworkManager is already running by now, so make it forget what we
        # just deleted rather than leaving it live in memory until a restart.
        if [ "$pruned" -eq 1 ]; then
          nmcli connection reload || true
        fi
      '';
    };
  };
}
