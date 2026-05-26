# Dapr CLI — pinned to match the Dapr runtime version installed in PittampalliOrg/stacks (main)
#
# Dapr runtime version in stacks/main: 1.17.7 (see
#   packages/components/profiles/local-core-ryzen/manifests/dapr-runtime/*.yaml,
#   `app.kubernetes.io/version: 1.17.7`).
#
# Per Dapr's compatibility convention the CLI minor must match the runtime minor.
# Nixpkgs currently pins dapr-cli to 1.16.4 (one minor behind), so we build a
# 1.17.x release here. v1.17.1 would be the newest patch but its go.mod requires
# Go 1.26.0 — nixpkgs only ships 1.26rc2, so we pin to v1.17.0 (needs Go 1.24.13,
# satisfied by the default 1.25.x toolchain).
{ buildGoModule, fetchFromGitHub, installShellFiles, lib }:

buildGoModule rec {
  pname = "dapr-cli";
  version = "1.17.0";

  src = fetchFromGitHub {
    owner = "dapr";
    repo = "cli";
    rev = "v${version}";
    hash = "sha256-3nD6IVXUjLXpTz4OTNEEmsu7cDmMepLwguqI9nRQmxA=";
  };

  vendorHash = "sha256-o8lEcTTIASvhpRJveo0UciGhwSu+5z9+jQcII9+D5Z8=";

  proxyVendor = true;

  nativeBuildInputs = [ installShellFiles ];

  subPackages = [ "." ];

  preCheck = ''
    export HOME=$(mktemp -d)
  '';

  ldflags = [
    "-X main.version=${version}"
    "-X main.apiVersion=1.0"
    "-X github.com/dapr/cli/pkg/standalone.gitcommit=${src.rev}"
    "-X github.com/dapr/cli/pkg/standalone.gitversion=${version}"
  ];

  postInstall = ''
    mv $out/bin/cli $out/bin/dapr

    installShellCompletion --cmd dapr \
      --bash <($out/bin/dapr completion bash) \
      --zsh <($out/bin/dapr completion zsh)
  '';

  meta = {
    description = "CLI for managing Dapr, the distributed application runtime";
    homepage = "https://dapr.io";
    license = lib.licenses.asl20;
    mainProgram = "dapr";
  };
}
