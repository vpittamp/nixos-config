{ stdenv
, lib
, fetchurl
, autoPatchelfHook
, wrapGAppsHook3
, dpkg
, atk
, at-spi2-atk
, at-spi2-core
, alsa-lib
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

stdenv.mkDerivation (finalAttrs: {
  pname = "antigravity";
  version = "1.0.0-1763520963";

  src = fetchurl {
    url = "https://us-central1-apt.pkg.dev/projects/antigravity-auto-updater-dev/pool/antigravity-debian/antigravity_${finalAttrs.version}_amd64_f88cc2d0044913f2fc8df191bca18df7.deb";
    sha256 = "0fkxlqycvmnw2wlbpz29f7rci79b6mg6dzb0xcivgd1pgylp64h1";
  };

  nativeBuildInputs = [ dpkg autoPatchelfHook wrapGAppsHook3 ];

  buildInputs = [
    atk at-spi2-atk at-spi2-core alsa-lib cups curl dbus expat fontconfig
    freetype gdk-pixbuf glib gtk3 libdrm libglvnd libnotify libpulseaudio
    libsecret libuuid libxkbcommon libxkbfile libxshmfence mesa
    nspr nss pango systemd vulkan-loader xdg-utils zlib
    xorg.libX11 xorg.libxcb xorg.libXcomposite xorg.libXcursor
    xorg.libXdamage xorg.libXext xorg.libXfixes xorg.libXi xorg.libXrandr
    xorg.libXrender
    xorg.libXtst xorg.libXScrnSaver
  ];

  dontConfigure = true;
  dontBuild = true;

  unpackPhase = ''
    runHook preUnpack
    mkdir source
    dpkg-deb -x $src source
    runHook postUnpack
  '';

  installPhase = ''
    runHook preInstall

    install -dm755 $out/opt
    cp -r source/usr/share/antigravity $out/opt/

    install -dm755 $out/bin
    cat > $out/bin/antigravity <<'EOF'
#!${stdenv.shell}
export BROWSER=${firefox}/bin/firefox
exec $out/opt/antigravity/bin/antigravity --no-sandbox "$@"
EOF
    chmod +x $out/bin/antigravity

    install -Dm644 source/usr/share/pixmaps/antigravity.png \
      $out/share/pixmaps/antigravity.png

    install -dm755 $out/share/icons/hicolor/512x512/apps
    cp source/usr/share/antigravity/resources/app/resources/linux/code.png \
      $out/share/icons/hicolor/512x512/apps/antigravity.png

    install -Dm644 source/usr/share/applications/antigravity.desktop \
      $out/share/applications/antigravity.desktop
    substituteInPlace $out/share/applications/antigravity.desktop \
      --replace /usr/share/antigravity/antigravity antigravity

    install -Dm644 source/usr/share/applications/antigravity-url-handler.desktop \
      $out/share/applications/antigravity-url-handler.desktop
    substituteInPlace $out/share/applications/antigravity-url-handler.desktop \
      --replace /usr/share/antigravity/antigravity antigravity

    runHook postInstall
  '';

  meta = {
    description = "Google Antigravity IDE";
    homepage = "https://antigravity.google";
    license = lib.licenses.unfree;
    platforms = [ "x86_64-linux" ];
  };
})
