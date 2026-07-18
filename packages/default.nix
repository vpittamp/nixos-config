# Package outputs
# Built with: nix build .#<package>
#
# The container/KubeVirt/Hetzner/Incus VM image builders were removed in 2026-07
# along with their (unmaintained / eval-broken) target configurations. The two
# maintained machines are nixosConfigurations.{thinkpad,ryzen}; `default` points
# at the ThinkPad system closure so `nix build` and `nix flake check` verify a
# real artifact.
{ inputs, self, ... }:
{
  perSystem = { system, pkgs, ... }: {
    packages = {
      # Default build target: the ThinkPad system closure.
      default = self.nixosConfigurations.thinkpad.config.system.build.toplevel;

      idpbuilder = pkgs.callPackage ./idpbuilder.nix {
        idpbuilderSrc = inputs.idpbuilder-src;
      };

      # GitHub Agentic Workflows — gh CLI extension
      gh-aw = pkgs.callPackage ./gh-aw.nix { };
      gh-dash = pkgs.callPackage ./gh-dash.nix { };
      gh-enhance = pkgs.callPackage ./gh-enhance.nix { };
      diffnav = pkgs.callPackage ./diffnav.nix { };

      # Kimi WebBridge — browser control CLI/MCP bridge for Chrome
      kimi-webbridge = pkgs.callPackage ./kimi-webbridge.nix { };

      # Cachix Deploy specification
      # Build with: nix build .#deploy
      # Used by GitHub Actions to trigger deployments to agents
      deploy =
        let
          cachix-deploy-lib = inputs.cachix-deploy-flake.lib pkgs;
        in
        cachix-deploy-lib.spec {
          agents = {
            thinkpad = self.nixosConfigurations.thinkpad.config.system.build.toplevel;
            ryzen = self.nixosConfigurations.ryzen.config.system.build.toplevel;
          };
        };
    };
  };
}
