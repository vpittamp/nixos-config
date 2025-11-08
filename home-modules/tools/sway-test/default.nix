{ pkgs, lib, ... }:

# Feature 001: Sway Test Framework - Nix packaging for Deno-based test framework
#
# This derivation compiles the sway-test TypeScript CLI to a self-contained binary
# using Deno's compile feature. The result is a single executable with all
# dependencies bundled, providing a complete test automation framework for Sway
# window manager.

pkgs.stdenv.mkDerivation rec {
  pname = "sway-test";
  version = "1.0.0";

  src = ./.;

  nativeBuildInputs = with pkgs; [
    deno
  ];

  # Deno compile needs network access during build to fetch dependencies
  # We handle this by allowing network access in the build sandbox
  __noChroot = true;

  buildPhase = ''
    # Create output directory
    mkdir -p dist

    # Compile TypeScript to standalone binary
    # --allow-all: sway-test needs full system access for:
    #   - IPC socket communication with Sway compositor
    #   - File I/O for test cases and state capture
    #   - Network access for tree-monitor daemon communication
    #   - Process spawning for test execution
    #   - Environment variable access for configuration
    deno compile \
      --allow-all \
      --output dist/sway-test \
      main.ts

    echo "Built sway-test binary: dist/sway-test"
  '';

  installPhase = ''
    mkdir -p $out/bin
    cp dist/sway-test $out/bin/

    # Set executable permissions
    chmod +x $out/bin/sway-test

    echo "Installed sway-test to $out/bin/sway-test"
  '';

  meta = with lib; {
    description = "Test automation framework for Sway window manager";
    longDescription = ''
      sway-test is a comprehensive testing framework for the Sway window manager,
      providing declarative JSON-based test cases with state validation and
      event correlation. It offers:

      - Declarative JSON test case format with fixtures and assertions
      - IPC-based action execution (workspace switching, window management)
      - State snapshot and comparison with detailed diff output
      - Tree monitor integration for event correlation
      - Interactive REPL debugging for failed tests
      - Multiple output formats: Human-readable, TAP v13, JUnit XML
      - CI/CD support with Docker and headless Sway execution
      - Fixture system for reusable test setups

      Feature 001: Complete test-driven development framework implementation
      with comprehensive documentation and CI/CD integration.
    '';
    homepage = "https://github.com/yourusername/nixos-config";
    license = licenses.mit;
    maintainers = [ ];
    platforms = platforms.linux;
  };
}
