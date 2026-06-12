{ lib
, stdenv
, fetchurl
, bash
, gh
}:

let
  version = "0.6.1";
  system = stdenv.hostPlatform.system;

  assets = {
    "x86_64-linux" = {
      name = "gh-enhance_v${version}_linux-amd64";
      sha256 = "01c91de1c9378e775ddeac809b956a3be08b2e7986383ee03f56e89cbad15aa5";
    };
    "aarch64-linux" = {
      name = "gh-enhance_v${version}_linux-arm64";
      sha256 = "a168d87eb82d6217d4351d4928835318a6ecd2f3a35230b7e1f0a29dae702521";
    };
    "x86_64-darwin" = {
      name = "gh-enhance_v${version}_darwin-amd64";
      sha256 = "bdec6d651d24a25fcca9842f309ff9b89bcbc001c0d5859a5e97f8d0013452e1";
    };
    "aarch64-darwin" = {
      name = "gh-enhance_v${version}_darwin-arm64";
      sha256 = "c9b6ea8949c567d96ee5684a899fd2c88efea6bbe09228f4b960e7dc4164301d";
    };
  };

  asset = assets.${system} or (throw "Unsupported system for gh-enhance: ${system}");
in
stdenv.mkDerivation {
  pname = "gh-enhance";
  inherit version;

  src = fetchurl {
    url = "https://github.com/dlvhdr/gh-enhance/releases/download/v${version}/${asset.name}";
    inherit (asset) sha256;
  };

  dontUnpack = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 "$src" "$out/libexec/gh-enhance-real"
    mkdir -p "$out/bin"
    cat > "$out/bin/gh-enhance" <<EOF
#!${bash}/bin/bash
set -euo pipefail

real="$out/libexec/gh-enhance-real"
repo_arg=""
needs_target=1
skip_next=""

for arg in "\$@"; do
  if [ -n "\$skip_next" ]; then
    if [ "\$skip_next" = "repo" ]; then
      repo_arg="\$arg"
    fi
    skip_next=""
    continue
  fi

  case "\$arg" in
    -h|--help|-v|--version|completion|help)
      needs_target=0
      break
      ;;
    -R|--repo)
      skip_next="repo"
      ;;
    --repo=*)
      repo_arg="\''${arg#--repo=}"
      ;;
    --debug|--flat)
      ;;
    --run)
      needs_target=0
      break
      ;;
    --*)
      ;;
    -*)
      ;;
    *)
      needs_target=0
      break
      ;;
  esac
done

if [ "\$needs_target" = 1 ]; then
  gh_args=(pr view --json url -q .url)
  if [ -n "\$repo_arg" ]; then
    gh_args+=(-R "\$repo_arg")
  fi
  if pr_url="\$(${lib.getExe gh} "\''${gh_args[@]}" 2>/dev/null)" && [ -n "\$pr_url" ]; then
    exec "\$real" "\$pr_url" "\$@"
  fi
fi

exec "\$real" "\$@"
EOF
    chmod +x "$out/bin/gh-enhance"
    runHook postInstall
  '';

  meta = with lib; {
    description = "GitHub CLI extension terminal UI for GitHub Actions";
    homepage = "https://www.gh-dash.dev/enhance";
    changelog = "https://github.com/dlvhdr/gh-enhance/releases/tag/v${version}";
    license = licenses.mit;
    platforms = builtins.attrNames assets;
    mainProgram = "gh-enhance";
  };
}
