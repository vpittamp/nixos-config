{ lib
, stdenv
, fetchurl
, autoPatchelfHook
}:

let
  version = "0.72.1";
  system = stdenv.hostPlatform.system;

  # Release assets are bare platform-named binaries (no archive).
  # See: https://github.com/github/gh-aw/releases
  assets = {
    "x86_64-linux" = {
      name = "linux-amd64";
      sha256 = "bd882f12e4d6bfbd0dc012c5923452f63602cfaed440026ff2be364bc8abbaf7";
    };
    "aarch64-linux" = {
      name = "linux-arm64";
      sha256 = "d644174e11214b466dd3d6d300de255dd5689f74c315b823ea66782999f300a8";
    };
    "x86_64-darwin" = {
      name = "darwin-amd64";
      sha256 = "d588c82d532619747699f1bd69eb6a4fbf29e488b866b2cc01d062ebdd0b76a2";
    };
    "aarch64-darwin" = {
      name = "darwin-arm64";
      sha256 = "75808e32c8726312ff5b369bedc8316fc0cc80f64c7d339d9f37363fe96dc370";
    };
  };

  asset = assets.${system} or (throw "Unsupported system for gh-aw: ${system}");
in
stdenv.mkDerivation {
  pname = "gh-aw";
  inherit version;

  src = fetchurl {
    url = "https://github.com/github/gh-aw/releases/download/v${version}/${asset.name}";
    inherit (asset) sha256;
  };

  # The "source" is a single binary, not an archive.
  dontUnpack = true;

  nativeBuildInputs = lib.optionals stdenv.isLinux [ autoPatchelfHook ];

  installPhase = ''
    runHook preInstall
    install -Dm755 "$src" "$out/bin/gh-aw"
    runHook postInstall
  '';

  meta = with lib; {
    description = "GitHub CLI extension to author and run agentic workflows in GitHub Actions";
    longDescription = ''
      Installs the gh-aw binary into $PATH. The gh CLI automatically resolves
      `gh aw <subcmd>` to a `gh-aw` binary on $PATH, so no `gh extension install`
      step is required.
    '';
    homepage = "https://github.com/github/gh-aw";
    license = licenses.mit;
    platforms = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
    mainProgram = "gh-aw";
  };
}
