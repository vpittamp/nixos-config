{ config, pkgs, lib, osConfig ? null, ... }:

let
  hostName =
    if osConfig != null && osConfig ? networking && osConfig.networking ? hostName
    then osConfig.networking.hostName
    else null;
  isRyzen = hostName == "ryzen";
  gatewayName = "ryzen-internal";
  gatewayEndpoint = "https://openshell-ryzen.tail286401.ts.net:8080";
  gatewayPort = 8080;
  gatewayMetadata = builtins.toJSON {
    name = gatewayName;
    gateway_endpoint = gatewayEndpoint;
    is_remote = false;
    gateway_port = gatewayPort;
    auth_mode = "mtls";
  };
  openshellConfigRoot = "${config.home.homeDirectory}/.config/openshell";
  ryzenGatewaySync = pkgs.writeShellScriptBin "openshell-ryzen-sync" ''
    set -euo pipefail

    strict=0
    if [ "''${1:-}" = "--strict" ]; then
      strict=1
      shift
    fi

    if [ "$#" -ne 0 ]; then
      echo "Usage: openshell-ryzen-sync [--strict]" >&2
      exit 1
    fi

    fail() {
      echo "openshell-ryzen-sync: $*" >&2
      if [ "$strict" -eq 1 ]; then
        exit 1
      fi
      exit 0
    }

    kubectl_cmd=(${pkgs.kubectl}/bin/kubectl --context kind-ryzen)
    config_root="${openshellConfigRoot}"
    gateway_dir="$config_root/gateways/${gatewayName}"
    mtls_dir="$gateway_dir/mtls"
    temp_dir="$(${pkgs.coreutils}/bin/mktemp -d)"

    cleanup() {
      ${pkgs.coreutils}/bin/rm -rf "$temp_dir"
    }
    trap cleanup EXIT

    if ! "''${kubectl_cmd[@]}" get namespace openshell >/dev/null 2>&1; then
      fail "kind-ryzen context or openshell namespace is unavailable"
    fi

    if ! "''${kubectl_cmd[@]}" get secret -n openshell openshell-client-tls >/dev/null 2>&1; then
      fail "openshell-client-tls secret not found in namespace openshell"
    fi

    if ! "''${kubectl_cmd[@]}" get secret -n openshell openshell-server-client-ca >/dev/null 2>&1; then
      fail "openshell-server-client-ca secret not found in namespace openshell"
    fi

    ${pkgs.coreutils}/bin/mkdir -p "$mtls_dir"
    ${pkgs.coreutils}/bin/chmod 700 "$config_root" "$config_root/gateways" "$gateway_dir" "$mtls_dir"

    "''${kubectl_cmd[@]}" get secret -n openshell openshell-client-tls -o jsonpath='{.data.tls\.crt}' \
      | ${pkgs.coreutils}/bin/base64 --decode > "$temp_dir/tls.crt" \
      || fail "failed to decode openshell client certificate"
    "''${kubectl_cmd[@]}" get secret -n openshell openshell-client-tls -o jsonpath='{.data.tls\.key}' \
      | ${pkgs.coreutils}/bin/base64 --decode > "$temp_dir/tls.key" \
      || fail "failed to decode openshell client key"
    "''${kubectl_cmd[@]}" get secret -n openshell openshell-server-client-ca -o jsonpath='{.data.tls\.crt}' \
      | ${pkgs.coreutils}/bin/base64 --decode > "$temp_dir/ca.crt" \
      || fail "failed to decode openshell client CA"

    ${pkgs.coreutils}/bin/install -m 0644 "$temp_dir/tls.crt" "$mtls_dir/tls.crt"
    ${pkgs.coreutils}/bin/install -m 0600 "$temp_dir/tls.key" "$mtls_dir/tls.key"
    ${pkgs.coreutils}/bin/install -m 0644 "$temp_dir/ca.crt" "$mtls_dir/ca.crt"
  '';

  # NVIDIA OpenShell - sandboxed runtime for autonomous AI agents
  # https://github.com/NVIDIA/OpenShell
  # Latest release: v0.0.16
  # Requires Docker running for sandbox operations
  openshellPkg = pkgs.python3Packages.buildPythonPackage rec {
    pname = "openshell";
    version = "0.0.16";
    format = "wheel";

    src = pkgs.fetchurl {
      url = "https://files.pythonhosted.org/packages/16/7c/7c37b65dd7945d88aaf1311fa94713292a5070ad48c33892ec72a50d3d6c/openshell-${version}-py3-none-manylinux_2_39_x86_64.whl";
      hash = "sha256-kv+FmC48z5Hg8FgbmHw2raj001DfPNxGZ5qrH62EUxc=";
    };

    nativeBuildInputs = [
      pkgs.autoPatchelfHook
    ];

    buildInputs = [
      pkgs.stdenv.cc.cc.lib
    ];

    dependencies = with pkgs.python3Packages; [
      cloudpickle
      grpcio
      protobuf
    ];

    doCheck = false;

    meta = {
      description = "NVIDIA OpenShell - sandboxed runtime for autonomous AI agents";
      homepage = "https://github.com/NVIDIA/OpenShell";
      license = lib.licenses.asl20;
      platforms = [ "x86_64-linux" ];
      mainProgram = "openshell";
    };
  };
in
lib.mkMerge [
  {
    home.packages = [ openshellPkg ];
  }
  (lib.mkIf isRyzen {
    home.packages = [ ryzenGatewaySync ];

    home.sessionVariables.OPENSHELL_GATEWAY = gatewayName;

    xdg.configFile."openshell/active_gateway".text = "${gatewayName}\n";
    xdg.configFile."openshell/gateways/${gatewayName}/metadata.json".text = gatewayMetadata;

    home.activation.openshellRyzenGateway = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      $DRY_RUN_CMD ${ryzenGatewaySync}/bin/openshell-ryzen-sync
    '';
  })
]
