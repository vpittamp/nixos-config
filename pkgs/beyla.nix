{ lib, buildGoModule, fetchFromGitHub }:

buildGoModule rec {
  pname = "beyla";
  version = "1.9.0";

  src = fetchFromGitHub {
    owner = "grafana";
    repo = "beyla";
    rev = "v${version}";
    hash = "sha256-Hb57DeIhuVLCcQMyXbRusBkyEFJiLs+6FVfRzKtx+G8=";
  };

  vendorHash = null;

  subPackages = [ "cmd/beyla" ];

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
