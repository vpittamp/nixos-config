{ pkgs, ... }:

pkgs.stdenv.mkDerivation {
  pname = "cli-ux";
  version = "1.0.0";

  src = ./.;

  buildInputs = [ pkgs.deno ];

  buildPhase = ''
    # Type check the library
    deno check mod.ts

    # Run tests
    deno task test
  '';

  installPhase = ''
    mkdir -p $out/lib/cli-ux
    cp -r * $out/lib/cli-ux/
  '';

  meta = with pkgs.lib; {
    description = "CLI UX enhancement library for Deno";
    license = licenses.mit;
  };
}
