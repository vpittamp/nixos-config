# talosctl pinned to v1.13.x, ahead of nixpkgs (which lags at 1.12.x as of
# Jan 2026). Needed to drive Talos OS upgrade + Kubernetes 1.36 upgrade on
# the ryzen talos-docker cluster — pruning support, K8s 1.36 awareness, and
# the v1.13 installer image are talosctl 1.13+ only.
#
# Pattern mirrors packages/idpbuilder.nix (binary fetched from upstream
# GitHub releases, ELF interpreter patched via autoPatchelfHook). Replace
# this file once nixpkgs ships talosctl >= 1.13 — at that point delete and
# point user/packages.nix back at `pkgs.talosctl`.
{ lib
, stdenv
, fetchurl
, autoPatchelfHook
}:

let
  upstreamVersion = "1.13.2";
  system = stdenv.hostPlatform.system;

  assets = {
    "x86_64-linux" = {
      url = "https://github.com/siderolabs/talos/releases/download/v${upstreamVersion}/talosctl-linux-amd64";
      sha256 = "sha256-huIcQ0MAq3HCfoZEVwsURjyM54/CcoU2kd6QavjRwbs=";
    };
    "aarch64-linux" = {
      url = "https://github.com/siderolabs/talos/releases/download/v${upstreamVersion}/talosctl-linux-arm64";
      # NOTE: hash needs verification for aarch64; placeholder until the host
      # actually needs it. ryzen is x86_64.
      sha256 = lib.fakeSha256;
    };
  };

  asset = assets.${system} or (throw "Unsupported system for talosctl-1-13: ${system}");
in
stdenv.mkDerivation {
  pname = "talosctl";
  version = upstreamVersion;

  src = fetchurl asset;

  dontUnpack = true;
  dontBuild = true;

  nativeBuildInputs = [ autoPatchelfHook ];

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    install -m755 "$src" $out/bin/talosctl
    runHook postInstall
  '';

  meta = with lib; {
    description = "CLI for Talos Linux Kubernetes OS (pinned to v${upstreamVersion} ahead of nixpkgs)";
    homepage = "https://www.talos.dev";
    license = licenses.mpl20;
    platforms = [ "x86_64-linux" "aarch64-linux" ];
    mainProgram = "talosctl";
  };
}
