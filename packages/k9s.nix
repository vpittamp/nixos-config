# k9s pinned to v0.51.0 ahead of nixpkgs (which ships 0.50.18).
#
# Wrapped with with-terminfo in configurations/*.nix so `infocmp` (ncurses) is
# always available on PATH when launched from systemd/daemon context.
{ k9s, fetchFromGitHub }:

k9s.overrideAttrs (old: rec {
  version = "0.51.0";
  src = fetchFromGitHub {
    owner = "derailed";
    repo = "k9s";
    tag = "v${version}";
    hash = "sha256-70Rfu1BVd/QnwWXRRpwIeZ2UJNWIGixpdiOHo4v7adA=";
  };
  vendorHash = "sha256-PkYDJK2oGl+siCG9p4R8shC0e5BhGFdJsc+ksL9J5zw=";
})
