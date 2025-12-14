# Development shells for the flake
# Enter with: nix develop
{ inputs, ... }:

{
  perSystem = { system, pkgs, ... }: {
    devShells.default = pkgs.mkShell {
      name = "nixos-dev";
      buildInputs = with pkgs; [
        # Nix tools
        nixpkgs-fmt
        nixfmt-classic
        statix
        deadnix

        # Development tools
        git
        vim
        tmux

        # Container tools
        docker
        docker-compose
        kubectl
      ];

      shellHook = ''
        echo "NixOS Development Shell"
        echo "Available configurations:"
        echo "  - hetzner: Hetzner Cloud with Sway (x86_64)"
        echo "  - thinkpad: Lenovo ThinkPad (x86_64)"
        echo "  - ryzen: AMD Ryzen Desktop (x86_64)"
        echo ""
        echo "Build with: nixos-rebuild switch --flake .#<config>"
        echo "Check flake: nix flake check"
        echo "Apply Home Manager profile: home-manager switch --flake .#darwin"
      '';
    };
  };
}
