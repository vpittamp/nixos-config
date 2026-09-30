# Google Antigravity CLI (`agy`) — Google's Gemini-CLI successor.
# Version 1.2.14 includes Gemini 3.5 Flash/Pro and updated model catalogs.
{ lib
, stdenvNoCC
, fetchurl
, autoPatchelfHook
, versionCheckHook
}:

let
  version = "1.2.14";
  buildId = "4571742832820224";
  wholeVersion = "${version}-${buildId}";

  throwSystem = throw "Unsupported system: ${stdenvNoCC.hostPlatform.system}";

  sourceData = {
    x86_64-linux = fetchurl {
      url = "https://storage.googleapis.com/antigravity-public/antigravity-cli/${wholeVersion}/linux-x64/cli_linux_x64.tar.gz";
      hash = "sha256-aM9NIhy2LgKJJFQ509N/WZvcjgxOHj2uA/MmRjoMJtw=";
    };
    aarch64-linux = fetchurl {
      url = "https://storage.googleapis.com/antigravity-public/antigravity-cli/${wholeVersion}/linux-arm/cli_linux_arm64.tar.gz";
      hash = "sha256-O0DDuqskW0OkEAfB22TfUfXxYrYFn8xKRQRzHyaJ0wE=";
    };
    aarch64-darwin = fetchurl {
      url = "https://storage.googleapis.com/antigravity-public/antigravity-cli/${wholeVersion}/darwin-arm/cli_mac_arm64.tar.gz";
      hash = "sha256-Ro7cxFS2uxwyHY1CWRoWrOTRodYopPHOla0jbJ7kzBk=";
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

    install -Dm755 antigravity $out/bin/agy

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
