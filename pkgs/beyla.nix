{ lib, buildGoModule, fetchFromGitHub }:

buildGoModule rec {
  pname = "beyla";
  version = "1.9.0";

  src = fetchFromGitHub {
    owner = "grafana";
    repo = "beyla";
    rev = "v${version}";
    hash = "sha256-RndvT7Xz6X5zL9X8n5v5m5p5q5r5s5t5u5v5w5x5y5z="; # Placeholder, will need update
  };

  vendorHash = null; # Usually needed for Go modules

  ldflags = [
    "-s" "-w"
    "-X github.com/grafana/beyla/pkg/build.Version=${version}"
  ];

  doCheck = false; # eBPF tests usually require privileges

  meta = with lib; {
    description = "eBPF-based auto-instrumentation for OpenTelemetry and Prometheus";
    homepage = "https://github.com/grafana/beyla";
    license = licenses.asl20;
    maintainers = with maintainers; [ ];
    mainProgram = "beyla";
  };
}
