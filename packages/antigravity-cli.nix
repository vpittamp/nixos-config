# Google Antigravity CLI (`agy`) — Google's Gemini-CLI successor.
# Version 1.4.5 includes Gemini 4 Argon and updated model catalogs.
{ lib
, stdenvNoCC
, fetchurl
, autoPatchelfHook
, versionCheckHook
}:

let
  version = "1.4.5";
  buildId = "4952523841339392";
  wholeVersion = "${version}-${buildId}";

  throwSystem = throw "Unsupported system: ${stdenvNoCC.hostPlatform.system}";

  sourceData = {
    x86_64-linux = fetchurl {
      url = "https://storage.googleapis.com/antigravity-public/antigravity-cli/${wholeVersion}/linux-x64/cli_linux_x64.tar.gz";
      hash = "sha256-kMwYlLaGJRCGmtTPGm9MBDt658CVutjVw1V4igypNcc=";
    };
    aarch64-linux = fetchurl {
      url = "https://storage.googleapis.com/antigravity-public/antigravity-cli/${wholeVersion}/linux-arm/cli_linux_arm64.tar.gz";
      hash = "sha256-iCa4DEsBPwh3NPJMXq3MOGAOdKGvQRJy1CqEDVLtPuc=";
    };
    aarch64-darwin = fetchurl {
      url = "https://storage.googleapis.com/antigravity-public/antigravity-cli/${wholeVersion}/darwin-arm/cli_mac_arm64.tar.gz";
      hash = "sha256-bWKNfSXfoYjvZ2Vk45cUZnxImbUr6mtWOdZZG8IrhpY=";
    };
  };
in
stdenvNoCC.mkDerivation {
  pname = "antigravity-cli";
  inherit version;

  strictDeps = true;
  __structuredAttrs = true;

  src = sourceData.${stdenvNoCC.hostPlatform.system} or throwSystem;

  sourceRoot = ".";

  nativeBuildInputs = lib.optionals stdenvNoCC.hostPlatform.isElf [ autoPatchelfHook ];

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    install -Dm755 antigravity $out/libexec/antigravity

    mkdir -p $out/bin
    cat > $out/bin/agy <<EOF
#!/bin/sh
has_model=0
for arg in "\$@"; do
  case "\$arg" in
    --model|--model=*)
      has_model=1
      break
      ;;
  esac
done

if [ "\$has_model" -eq 0 ]; then
  case "\''${1:-}" in
    agent|agents|changelog|help|install|mcp|mic-serve|models|plugin|plugins|remote-control|update|version)
      exec "$out/libexec/antigravity" "\$@"
      ;;
    *)
      exec "$out/libexec/antigravity" --model gemini-4-argon "\$@"
      ;;
  esac
else
  exec "$out/libexec/antigravity" "\$@"
fi
EOF
    chmod +x $out/bin/agy

    runHook postInstall
  '';

  nativeInstallCheckInputs = [ versionCheckHook ];
  doInstallCheck = true;

  passthru = {
    inherit wholeVersion;
  };

  meta = with lib; {
    description = "Google's Go-based terminal user interface (TUI) agent client";
    homepage = "https://antigravity.google";
    changelog = "https://antigravity.google/changelog";
    license = licenses.unfree;
    platforms = lib.attrNames sourceData;
    mainProgram = "agy";
    sourceProvenance = with sourceTypes; [ binaryNativeCode ];
  };
}
