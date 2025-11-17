# Goose Desktop - AI Agent Desktop Application
# Electron app packaged as DEB, extracted and wrapped for NixOS
{ lib, stdenv, fetchurl, dpkg, autoPatchelfHook, makeWrapper, wrapGAppsHook
, alsa-lib, at-spi2-atk, at-spi2-core, atk, cairo, cups, dbus, expat, fontconfig
, freetype, gdk-pixbuf, glib, gtk3, libdrm, libnotify, libxkbcommon, mesa, nspr
, nss, pango, systemd, xorg, libappindicator-gtk3, libGL }:

let
  version = "1.14.0";

  src = fetchurl {
    url = "https://github.com/block/goose/releases/download/v${version}/goose_${version}_amd64.deb";
    sha256 = "01nc4yxwarx8wnqpga1wml1wqagg8dya9c935s2x4bqvrhl8gz5v";
  };

  runtimeLibs = [
    alsa-lib
    at-spi2-atk
    at-spi2-core
    atk
    cairo
    cups
    dbus
    expat
    fontconfig
    freetype
    gdk-pixbuf
    glib
    gtk3
    libdrm
    libnotify
    libxkbcommon
    mesa
    nspr
    nss
    pango
    systemd
    xorg.libX11
    xorg.libXcomposite
    xorg.libXcursor
    xorg.libXdamage
    xorg.libXext
    xorg.libXfixes
    xorg.libXi
    xorg.libXrandr
    xorg.libXrender
    xorg.libXScrnSaver
    xorg.libXtst
    xorg.libxcb
    xorg.libxshmfence
    libappindicator-gtk3
    libGL
  ];
in
stdenv.mkDerivation {
  pname = "goose-desktop";
  inherit version src;

  nativeBuildInputs = [
    dpkg
    autoPatchelfHook
    makeWrapper
    wrapGAppsHook
  ];

  buildInputs = runtimeLibs;

  unpackPhase = ''
    runHook preUnpack
    dpkg-deb -x $src .
    runHook postUnpack
  '';

  dontBuild = true;
  dontConfigure = true;
  dontWrapGApps = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/opt/goose
    mkdir -p $out/bin
    mkdir -p $out/share/applications
    mkdir -p $out/share/icons/hicolor

    # Copy the application files
    cp -r opt/Goose/* $out/opt/goose/ || cp -r usr/lib/goose/* $out/opt/goose/ || cp -r usr/share/goose/* $out/opt/goose/ || true

    # If the app is in a different location, try to find it
    if [ ! -f "$out/opt/goose/goose" ] && [ ! -f "$out/opt/goose/Goose" ]; then
      # Try to find the main executable
      find . -type f -name "goose" -o -name "Goose" | head -1 | xargs -I {} cp -r "$(dirname {})"/* $out/opt/goose/
    fi

    # Make the main binary executable
    chmod +x $out/opt/goose/goose 2>/dev/null || chmod +x $out/opt/goose/Goose 2>/dev/null || true

    # Install desktop file if present
    if [ -f usr/share/applications/*.desktop ]; then
      cp usr/share/applications/*.desktop $out/share/applications/
      substituteInPlace $out/share/applications/*.desktop \
        --replace '/opt/Goose/' "$out/opt/goose/" \
        --replace '/usr/lib/goose/' "$out/opt/goose/" \
        --replace '/usr/share/goose/' "$out/opt/goose/"
    fi

    # Install icons if present
    if [ -d usr/share/icons ]; then
      cp -r usr/share/icons/* $out/share/icons/
    fi

    # Create wrapper script
    makeWrapper "$out/opt/goose/goose" "$out/bin/goose-desktop" \
      --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath runtimeLibs}" \
      --add-flags "--no-sandbox" \
      "''${gappsWrapperArgs[@]}" \
      2>/dev/null || \
    makeWrapper "$out/opt/goose/Goose" "$out/bin/goose-desktop" \
      --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath runtimeLibs}" \
      --add-flags "--no-sandbox" \
      "''${gappsWrapperArgs[@]}"

    runHook postInstall
  '';

  meta = with lib; {
    description = "Goose Desktop - Open-source AI agent with desktop interface";
    homepage = "https://github.com/block/goose";
    license = licenses.asl20;
    maintainers = [ ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "goose-desktop";
  };
}
