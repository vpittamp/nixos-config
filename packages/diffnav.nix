{ lib
, stdenv
, fetchurl
, makeBinaryWrapper
, delta
}:

let
  version = "0.11.0";
  system = stdenv.hostPlatform.system;

  assets = {
    "x86_64-linux" = {
      name = "diffnav_Linux_x86_64.tar.gz";
      sha256 = "35b0c3afb84f14b7e0aed411fbb9fd352b67a90885448f94a38829ebf74275e4";
    };
    "aarch64-linux" = {
      name = "diffnav_Linux_arm64.tar.gz";
      sha256 = "902b88c34d3e0c26c2f2f0cef2f3550d4f12b8e8e72323f36a86b668a009b0d8";
    };
    "x86_64-darwin" = {
      name = "diffnav_Darwin_x86_64.tar.gz";
      sha256 = "33a3911292dcf013953e3678aaa85fbc4aab50af5946002c8ff25e84c1b75cc2";
    };
    "aarch64-darwin" = {
      name = "diffnav_Darwin_arm64.tar.gz";
      sha256 = "a4cbb3222708fc5662877d3b0a01f5b7625363f6e83c498cb746bf6b3058588e";
    };
  };

  asset = assets.${system} or (throw "Unsupported system for diffnav: ${system}");
in
stdenv.mkDerivation {
  pname = "diffnav";
  inherit version;

  src = fetchurl {
    url = "https://github.com/dlvhdr/diffnav/releases/download/v${version}/${asset.name}";
    inherit (asset) sha256;
  };

  nativeBuildInputs = [ makeBinaryWrapper ];

  unpackPhase = ''
    runHook preUnpack
    mkdir source
    tar -xzf "$src" -C source
    cd source
    runHook postUnpack
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 diffnav "$out/bin/diffnav"
    wrapProgram "$out/bin/diffnav" \
      --prefix PATH : ${lib.makeBinPath [ delta ]}
    ln -s diffnav "$out/bin/gh-diffnav"
    runHook postInstall
  '';

  meta = with lib; {
    description = "Git diff pager based on delta with a GitHub-style file tree";
    homepage = "https://github.com/dlvhdr/diffnav";
    changelog = "https://github.com/dlvhdr/diffnav/releases/tag/v${version}";
    license = licenses.mit;
    platforms = builtins.attrNames assets;
    mainProgram = "diffnav";
  };
}
