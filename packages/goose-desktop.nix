# Goose Desktop - AI Agent Desktop Application
# Electron app packaged as DEB, extracted and wrapped for NixOS
{ lib, stdenv, fetchurl, dpkg, autoPatchelfHook, makeWrapper, wrapGAppsHook3
, alsa-lib, at-spi2-atk, at-spi2-core, atk, cairo, cups, dbus, expat, fontconfig
, freetype, gdk-pixbuf, glib, gtk3, libdrm, libnotify, libxkbcommon, mesa, nspr
, nss, pango, systemd, xorg, libappindicator-gtk3, libGL, gnutar, binutils, zstd }:

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
    wrapGAppsHook3
    binutils  # for ar to extract .deb
    gnutar    # for extracting with --no-same-permissions
    zstd      # for decompressing data.tar.zst
  ];

  buildInputs = runtimeLibs;

  unpackPhase = ''
    runHook preUnpack
    # Extract control and data archives separately to avoid setuid permission issues
    ar x $src
    # Extract data.tar without preserving special permissions (setuid/setgid)
    tar --no-same-permissions --no-same-owner -xf data.tar.* 2>/dev/null || tar -xf data.tar.*
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

    # Copy the application files - handle different possible locations
    if [ -d usr/lib/goose ]; then
      cp -r usr/lib/goose/* $out/opt/goose/
    elif [ -d opt/Goose ]; then
      cp -r opt/Goose/* $out/opt/goose/
    elif [ -d usr/share/goose ]; then
      cp -r usr/share/goose/* $out/opt/goose/
    else
      # Try to find the main executable
      GOOSE_DIR=$(find . -type f \( -name "goose" -o -name "Goose" \) | head -1 | xargs -I {} dirname {})
      if [ -n "$GOOSE_DIR" ] && [ -d "$GOOSE_DIR" ]; then
        cp -r "$GOOSE_DIR"/* $out/opt/goose/
      fi
    fi

    # Make the main binary executable - find it first
    if [ -f "$out/opt/goose/goose" ]; then
      chmod +x $out/opt/goose/goose
      MAIN_BINARY="$out/opt/goose/goose"
    elif [ -f "$out/opt/goose/Goose" ]; then
      chmod +x $out/opt/goose/Goose
      MAIN_BINARY="$out/opt/goose/Goose"
    else
      # List what we have for debugging
      echo "Contents of $out/opt/goose:"
      ls -la $out/opt/goose/ | head -20
      echo "Looking for any executable files..."
      MAIN_BINARY=$(find $out/opt/goose -maxdepth 1 -type f -name "*.bin" -o -type f ! -name "*.*" | head -1)
      if [ -n "$MAIN_BINARY" ]; then
        chmod +x "$MAIN_BINARY"
      else
        echo "ERROR: Could not find main binary in $out/opt/goose"
        exit 1
      fi
    fi

    # Install desktop file if present
    if [ -f usr/share/applications/*.desktop ]; then
      cp usr/share/applications/*.desktop $out/share/applications/
      substituteInPlace $out/share/applications/*.desktop \
        --replace-warn '/opt/Goose/' "$out/opt/goose/" \
        --replace-warn '/usr/lib/goose/' "$out/opt/goose/" \
        --replace-warn '/usr/share/goose/' "$out/opt/goose/"
    fi

    # Install icons if present
    if [ -d usr/share/icons ]; then
      cp -r usr/share/icons/* $out/share/icons/
    fi

    # Create wrapper script
    makeWrapper "$MAIN_BINARY" "$out/bin/goose-desktop" \
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
