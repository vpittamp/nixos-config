{
  lib,
  stdenv,
  fetchurl,
  makeShellWrapper,
  wrapGAppsHook3,
  alsa-lib,
  at-spi2-atk,
  at-spi2-core,
  atk,
  cairo,
  cups,
  dbus,
  expat,
  gdk-pixbuf,
  glib,
  gtk3,
  libx11,
  libxcomposite,
  libxdamage,
  libxext,
  libxfixes,
  libxrandr,
  libdrm,
  libxcb,
  libxkbcommon,
  libxshmfence,
  libGL,
  libappindicator-gtk3,
  libgbm,
  nspr,
  nss,
  pango,
  systemd,
  udev,
  xdg-utils,
  polkitPolicyOwners ? [ ],
}:

let
  pname = "1password";
  version = "8.12.38";

  sources = {
    x86_64-linux = {
      url = "https://downloads.1password.com/linux/tar/stable/x86_64/1password-${version}.x64.tar.gz";
      hash = "sha256-i5dnJ2rWeVqPG3kwaqgoL315YXx8oIvtp4Rv95obtPI=";
    };
    aarch64-linux = {
      url = "https://downloads.1password.com/linux/tar/stable/aarch64/1password-${version}.arm64.tar.gz";
      hash = "sha256-y4s2Z6D1FwXkCk4eSrg9RAxXMkz6s/O/rLcT5A5jEp0=";
    };
  };

  src = fetchurl (sources.${stdenv.hostPlatform.system} or (throw "Unsupported system: ${stdenv.hostPlatform.system}"));

  policyOwners = lib.concatStringsSep " " (map (user: "unix-user:${user}") polkitPolicyOwners);
in
stdenv.mkDerivation {
  inherit pname version src;

  nativeBuildInputs = [
    makeShellWrapper
    wrapGAppsHook3
  ];
  buildInputs = [ glib ];

  dontConfigure = true;
  dontBuild = true;
  dontPatchELF = true;
  dontWrapGApps = true;

  installPhase =
    let
      rpath =
        lib.makeLibraryPath [
          alsa-lib
          at-spi2-atk
          at-spi2-core
          atk
          cairo
          cups
          dbus
          expat
          gdk-pixbuf
          glib
          gtk3
          libx11
          libxcomposite
          libxdamage
          libxext
          libxfixes
          libxrandr
          libdrm
          libxcb
          libxkbcommon
          libxshmfence
          libGL
          libappindicator-gtk3
          libgbm
          nspr
          nss
          pango
          systemd
        ]
        + ":${lib.getLib stdenv.cc.cc}/lib64";
    in
    ''
      runHook preInstall

      mkdir -p $out/bin $out/share/1password
      cp -a * $out/share/1password

      # Desktop file
      install -Dt $out/share/applications resources/*.desktop
      substituteInPlace $out/share/applications/*.desktop \
        --replace-fail 'Exec=/opt/1Password/1password' 'Exec=1password'

      # Provide 1password.desktop compatibility link if upstream uses com.onepassword.OnePassword.desktop
      if [ -f $out/share/applications/com.onepassword.OnePassword.desktop ] && [ ! -f $out/share/applications/1password.desktop ]; then
        ln -s com.onepassword.OnePassword.desktop $out/share/applications/1password.desktop
      fi
    ''
    + (lib.optionalString (polkitPolicyOwners != [ ]) ''
      # Polkit file
      mkdir -p $out/share/polkit-1/actions
      substitute com.1password.1Password.policy.tpl $out/share/polkit-1/actions/com.1password.1Password.policy --replace-fail "\''${POLICY_OWNERS}" "${policyOwners}"
    '')
    + ''
      # Icons
      cp -a resources/icons $out/share

      interp="$(cat $NIX_CC/nix-support/dynamic-linker)"
      patchelf --set-interpreter $interp $out/share/1password/{1password,1Password-BrowserSupport,1Password-Crash-Handler,1Password-LastPass-Exporter,op-ssh-sign,1password-mcp}
      patchelf --set-rpath ${rpath}:$out/share/1password $out/share/1password/{1password,1Password-BrowserSupport,1Password-Crash-Handler,1Password-LastPass-Exporter,op-ssh-sign,1password-mcp}
      for file in $(find $out -type f -name \*.so\* ); do
        patchelf --set-rpath ${rpath}:$out/share/1password $file
      done

      ln -s $out/share/1password/op-ssh-sign $out/bin/op-ssh-sign
      ln -s $out/share/1password/1password-mcp $out/bin/1password-mcp

      runHook postInstall
    '';

  preFixup = ''
    makeShellWrapper $out/share/1password/1password $out/bin/1password \
      "''${gappsWrapperArgs[@]}" \
      --suffix PATH : ${lib.makeBinPath [ xdg-utils ]} \
      --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath [ udev ]} \
      --add-flags "\''${NIXOS_OZONE_WL:+--ozone-platform-hint=auto}"
  '';

  meta = {
    description = "Multi-platform password manager";
    homepage = "https://1password.com/";
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    license = lib.licenses.unfree;
    platforms = [ "x86_64-linux" "aarch64-linux" ];
    mainProgram = "1password";
  };
}
