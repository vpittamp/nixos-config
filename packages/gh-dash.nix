{ lib
, stdenv
, fetchurl
}:

let
  version = "4.24.1";
  system = stdenv.hostPlatform.system;

  assets = {
    "x86_64-linux" = {
      name = "gh-dash_v${version}_linux-amd64";
      sha256 = "6ce014376489a471bdcabcbe3e5f326aa04ad94000857abb1da38a9ec2c6d473";
    };
    "aarch64-linux" = {
      name = "gh-dash_v${version}_linux-arm64";
      sha256 = "2ca09757771b5d22dd245dd57698c8b4ce63c1b31a7114cd3f92e02bdb892d76";
    };
    "x86_64-darwin" = {
      name = "gh-dash_v${version}_darwin-amd64";
      sha256 = "e4caec1b112f216ca812e92a0f7dbf5713eb6bdf5f302cf6185148b84f09fc40";
    };
    "aarch64-darwin" = {
      name = "gh-dash_v${version}_darwin-arm64";
      sha256 = "c3087bd05b7cd2727cbfeb96701f80544109f4b925ae98836a74129bbde645e9";
    };
  };

  asset = assets.${system} or (throw "Unsupported system for gh-dash: ${system}");
in
stdenv.mkDerivation {
  pname = "gh-dash";
  inherit version;

  src = fetchurl {
    url = "https://github.com/dlvhdr/gh-dash/releases/download/v${version}/${asset.name}";
    inherit (asset) sha256;
  };

  dontUnpack = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 "$src" "$out/bin/gh-dash"
    runHook postInstall
  '';

  meta = with lib; {
    description = "GitHub CLI extension to display pull requests and issues in a terminal dashboard";
    homepage = "https://www.gh-dash.dev";
    changelog = "https://github.com/dlvhdr/gh-dash/releases/tag/v${version}";
    license = licenses.mit;
    platforms = builtins.attrNames assets;
    mainProgram = "gh-dash";
  };
}
