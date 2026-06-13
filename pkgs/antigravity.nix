{ stdenv
, lib
, fetchurl
, autoPatchelfHook
, wrapGAppsHook3
, makeDesktopItem
, copyDesktopItems
, atk
, at-spi2-atk
, at-spi2-core
, alsa-lib
, cairo
, cups
, curl
, dbus
, expat
, fontconfig
, freetype
, gdk-pixbuf
, glib
, gtk3
, libdrm
, libnotify
, libpulseaudio
, libsecret
, libuuid
, libxkbcommon
, libxkbfile
, libxshmfence
, mesa
, nspr
, nss
, pango
, systemd
, xdg-utils
, xorg
, firefox
, libglvnd
, vulkan-loader
, zlib
}:

# Antigravity IDE (the VS Code-based IDE, successor to the legacy 1.x .deb).
#
# As of Antigravity 2.x, Google stopped shipping the IDE as a Debian package via
# the us-central1-apt.pkg.dev apt repo (that channel froze at 1.23.2) and now
# distributes it as a plain Linux tarball from the edgedl CDN. The release tag
# below (2.0.4-...) is the public download version; the bundled product.json
# still reports the upstream VS Code base version (1.107.0).
#
# To bump: open https://antigravity.google/download, grab the "Antigravity IDE →
# Linux → Download for x64" link (a storage URL under
# edgedl.me.gvt1.com/.../antigravity/stable/<version>/linux-x64/Antigravity IDE.tar.gz),
# then update `version` and run `nix store prefetch-file --json <url>` for the hash.
stdenv.mkDerivation (finalAttrs: {
  pname = "antigravity";
  version = "2.0.4-6381998290370560";

  src = fetchurl {
    # The space in "Antigravity IDE.tar.gz" must stay percent-encoded in the URL.
    url = "https://edgedl.me.gvt1.com/edgedl/release2/j0qc3/antigravity/stable/${finalAttrs.version}/linux-x64/Antigravity%20IDE.tar.gz";
    hash = "sha256-ZjN9RfJHLOXonzlOd67HSQmqG+C7M8n3MpmpX0WOZ3A=";
  };

  nativeBuildInputs = [ autoPatchelfHook wrapGAppsHook3 copyDesktopItems ];

  buildInputs = [
    atk at-spi2-atk at-spi2-core alsa-lib cairo cups curl dbus expat fontconfig
    freetype gdk-pixbuf glib gtk3 libdrm libglvnd libnotify libpulseaudio
    libsecret libuuid libxkbcommon libxkbfile libxshmfence mesa
    nspr nss pango systemd vulkan-loader xdg-utils zlib
    xorg.libX11 xorg.libxcb xorg.libXcomposite xorg.libXcursor
    xorg.libXdamage xorg.libXext xorg.libXfixes xorg.libXi xorg.libXrandr
    xorg.libXrender
    xorg.libXtst xorg.libXScrnSaver
  ];

  # The bundled microsoft-authentication extension ships libmsalruntime.so which
  # links libsoup-3.0/libwebkit2gtk-4.1. That extension is irrelevant for a Google
  # IDE and pulling webkitgtk into the closure isn't worth it, so skip patching it.
  autoPatchelfIgnoreMissingDeps = [
    "libsoup-3.0.so.0"
    "libwebkit2gtk-4.1.so.0"
  ];

  dontConfigure = true;
  dontBuild = true;

  # The tarball unpacks into a single "Antigravity IDE/" directory.
  unpackPhase = ''
    runHook preUnpack
    mkdir source
    tar -xzf $src --strip-components=1 -C source
    runHook postUnpack
  '';

  desktopItems = [
    (makeDesktopItem {
      name = "antigravity-ide";
      desktopName = "Antigravity IDE";
      exec = "antigravity-ide %U";
      icon = "antigravity-ide";
      categories = [ "Development" "IDE" ];
      mimeTypes = [ "x-scheme-handler/antigravity-ide" ];
      startupWMClass = "Antigravity IDE";
    })
    (makeDesktopItem {
      name = "antigravity-ide-url-handler";
      desktopName = "Antigravity IDE - URL Handler";
      exec = "antigravity-ide %U";
      icon = "antigravity-ide";
      noDisplay = true;
      mimeTypes = [ "x-scheme-handler/antigravity-ide" ];
      startupWMClass = "Antigravity IDE";
    })
  ];

  installPhase = ''
    runHook preInstall

    install -dm755 $out/opt/antigravity-ide
    cp -r source/. $out/opt/antigravity-ide/

    install -dm755 $out/bin
    cat > $out/bin/antigravity-ide <<EOF
    #!${stdenv.shell}
    # Use Firefox for OAuth — it handles the custom URL scheme more reliably than Chromium.
    export BROWSER=${firefox}/bin/firefox
    exec "$out/opt/antigravity-ide/antigravity-ide" --no-sandbox "\$@"
    EOF
    chmod +x $out/bin/antigravity-ide

    install -Dm644 source/resources/app/resources/linux/code.png \
      $out/share/icons/hicolor/512x512/apps/antigravity-ide.png

    runHook postInstall
  '';

  meta = {
    description = "Google Antigravity IDE";
    homepage = "https://antigravity.google";
    license = lib.licenses.unfree;
    platforms = [ "x86_64-linux" ];
    mainProgram = "antigravity-ide";
  };
})
