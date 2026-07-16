# Flake checks — run with: nix flake check
#
# The previous placeholder PWA "tests" always passed and verified nothing. These
# checks build the two maintained host system closures, so `nix flake check`
# (and CI) fails the moment either configuration stops evaluating/building —
# which is the regression that repeatedly slipped through before.
{ self, ... }:
{
  perSystem = { system, lib, ... }: {
    checks = lib.optionalAttrs (system == "x86_64-linux") {
      thinkpad-system = self.nixosConfigurations.thinkpad.config.system.build.toplevel;
      ryzen-system = self.nixosConfigurations.ryzen.config.system.build.toplevel;
    };
  };
}
