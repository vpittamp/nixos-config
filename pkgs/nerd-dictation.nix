{ stdenv, fetchFromGitHub, makeWrapper, python3, lib }:

stdenv.mkDerivation {
  pname = "nerd-dictation";
  version = "2025-01-14";

  src = fetchFromGitHub {
    owner = "ideasman42";
    repo = "nerd-dictation";
    rev = "03ce043a6d569a5bb9a715be6a8e45d8ba0930fd";
    hash = "sha256-M/05SUAe2Fq5I40xuWZ/lTn1+mNLr4Or6o0yKfylVk8=";
  };

  nativeBuildInputs = [ makeWrapper ];

  dontBuild = true;

  installPhase = ''
    mkdir -p $out/bin
    cp nerd-dictation $out/bin/nerd-dictation
    chmod +x $out/bin/nerd-dictation

    wrapProgram $out/bin/nerd-dictation \
      --prefix PYTHONPATH : "${python3.withPackages (ps: with ps; [ sounddevice ])}/lib/python${python3.version}/site-packages" \
      --prefix LD_LIBRARY_PATH : "${stdenv.cc.cc.lib}/lib"
  '';

  meta = {
    description = "Offline speech-to-text for desktop Linux";
    homepage = "https://github.com/ideasman42/nerd-dictation";
    license = lib.licenses.gpl3;
  };
}
