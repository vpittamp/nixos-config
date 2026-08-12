# Assets Package: Copy static assets to Nix store for portable builds
# Feature 106: Make NixOS Config Portable
#
# This module creates a derivation that copies the assets directory to the Nix store.
# Assets are then referenced using store paths, ensuring builds work from any directory.
#
# Usage in other modules:
#   { assetsPackage, ... }:
#   {
#     icon = "${assetsPackage}/icons/my-icon.svg";
#   }
{ pkgs }:

pkgs.runCommand "nixos-config-assets"
{
  nativeBuildInputs = [ pkgs.librsvg pkgs.coreutils pkgs.gnugrep ];
} ''
  mkdir -p $out/icons
  cp -r ${../assets/icons}/* $out/icons/
  chmod -R u+w $out/icons

  # Flatten SVGs that Qt cannot draw.
  #
  # Qt's SVG renderer implements SVG 1.2 Tiny, which has no <mask> and no
  # <filter>. It does not error on them — it silently draws nothing, so the icon
  # simply comes out blank wherever Quickshell shows it. gemini.svg is one of
  # these: it rasterises correctly with librsvg but renders empty in the bar,
  # which only became obvious once the workspace pills stopped drawing their
  # number and the icon was all that was left.
  #
  # Rather than track down every offender by eye, rasterise any such file and
  # re-wrap the bitmap in a Tiny-compatible <image> element under the *same*
  # filename, so every existing reference keeps working untouched.
  for f in $out/icons/*.svg; do
    [ -e "$f" ] || continue
    if grep -qE '<(mask|filter)[ >]' "$f"; then
      rsvg-convert -w 128 -h 128 -o "$f.png" "$f"
      b64="$(base64 -w0 "$f.png")"
      # printf rather than a heredoc: this sits inside an indented Nix string,
      # where a heredoc terminator has to reach column 0 to close.
      printf '%s%s%s\n' \
        '<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="128" height="128" viewBox="0 0 128 128"><image width="128" height="128" xlink:href="data:image/png;base64,' \
        "$b64" \
        '"/></svg>' > "$f"
      rm -f "$f.png"
      echo "assets: flattened Qt-incompatible SVG $(basename "$f")"
    fi
  done
''
