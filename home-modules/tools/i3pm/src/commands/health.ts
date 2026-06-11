import { parseArgs } from "@std/cli/parse-args";
import { bold, cyan, dim, green, red, yellow } from "jsr:@std/fmt/colors";
import { DaemonClient } from "../services/daemon-client.ts";
import { getSocketPath } from "../utils/socket.ts";

interface CommandOptions {
  verbose?: boolean;
  debug?: boolean;
}

interface UnitStatus {
  name: string;
  scope: "user" | "system";
  load_state: string;
  active_state: string;
  sub_state: string;
  unit_file_state: string;
  fragment_path: string;
  result: string;
  healthy: boolean;
}

interface PathCheck {
  current_path: string;
  expected_path: string;
  matches: boolean;
}

interface HerdrHealth {
  healthy: boolean;
  issues: string[];
  client_version: string;
  server_version: string;
  protocol: number;
  compatible: boolean;
  server_running: boolean;
  agent_count: number;
  pane_count: number;
  integrations: {
    claude: boolean;
    codex: boolean;
  };
}

interface HerdrRemoteTarget {
  host: string;
  ssh_target: string;
  connection_key: string;
}

interface TailscalePeerHealth {
  checked: boolean;
  peer_found: boolean;
  host: string;
  dns_name: string;
  online: boolean | null;
  expired: boolean | null;
  tailscale_ips: string[];
  issue: string;
}

interface HerdrRemoteHealth extends HerdrHealth {
  host: string;
  ssh_target: string;
  connection_key: string;
  proxy_reachable: boolean;
  proxy_schema_version: string;
  proxy_protocol_version: number;
  tailscale: TailscalePeerHealth | null;
}

interface McpBrowserCandidate {
  pid: number;
  ppid: number;
  age_seconds: number;
  cmdline: string;
}

interface McpBrowserHealth {
  healthy: boolean;
  issues: string[];
  endpoint_url: string;
  managed_browser_service: {
    name: string;
    active: boolean;
    profile_dir: string;
    port: number;
  };
  reaper_timer: {
    name: string;
    active: boolean;
  };
  listener: {
    line: string;
    pid: number | null;
    cmdline: string;
    matches_expected_profile: boolean;
  };
  stale_candidates: McpBrowserCandidate[];
}

interface DashboardHealth {
  healthy: boolean;
  reachable: boolean;
  schema_version: string;
  snapshot_version: number;
  session_generation: number;
  display_generation: number;
  focus_generation: number;
  issues: string[];
  warnings: string[];
}

interface HealthReport {
  timestamp: string;
  overall_status: "ok" | "warn" | "fail";
  core_issues: string[];
  optional_issues: string[];
  core_units: UnitStatus[];
  failed_user_units: string[];
  system_generation: string;
  home_manager_generation: string;
  home_manager_profile_generation: string;
  daemon_socket: {
    path: string;
    exists: boolean;
  };
  quickshell: {
    shell_qml: PathCheck;
    service_unit: PathCheck;
  };
  dashboard: DashboardHealth | null;
  herdr: HerdrHealth | null;
  herdr_remotes: HerdrRemoteHealth[];
  mcp_browser_runtime: McpBrowserHealth | null;
}

const OPTIONAL_USER_UNIT_PREFIXES = ["wayvnc@"];

function showHelp(): void {
  console.log(`i3pm health [--json]

Checks runtime convergence and service health for the local host.

Examples:
  i3pm health
  i3pm health --json`);
}

function expandHome(path: string): string {
  if (!path.startsWith("~/")) {
    return path;
  }
  return `${Deno.env.get("HOME") || ""}/${path.slice(2)}`;
}

async function runCommand(
  args: string[],
  timeoutMs = 0,
): Promise<{ code: number; stdout: string; stderr: string }> {
  const commandOptions: Deno.CommandOptions = {
    args: args.slice(1),
    stdin: "null",
    stdout: "piped",
    stderr: "piped",
  };
  if (timeoutMs > 0) {
    commandOptions.signal = AbortSignal.timeout(timeoutMs);
  }
  const command = new Deno.Command(args[0], {
    ...commandOptions,
  });
  const output = await command.output();
  return {
    code: output.code,
    stdout: new TextDecoder().decode(output.stdout).trim(),
    stderr: new TextDecoder().decode(output.stderr).trim(),
  };
}

async function realPathOrEmpty(path: string): Promise<string> {
  try {
    return await Deno.realPath(expandHome(path));
  } catch {
    return "";
  }
}

function parseSystemctlShow(payload: string): Record<string, string> {
  const result: Record<string, string> = {};
  for (const line of payload.split("\n")) {
    const trimmed = line.trim();
    if (!trimmed) {
      continue;
    }
    const idx = trimmed.indexOf("=");
    if (idx <= 0) {
      continue;
    }
    result[trimmed.slice(0, idx)] = trimmed.slice(idx + 1);
  }
  return result;
}

function asRecord(value: unknown): Record<string, unknown> {
  return value && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : {};
}

function asArray(value: unknown): unknown[] {
  return Array.isArray(value) ? value : [];
}

function herdrStatusRoot(payload: Record<string, unknown>): Record<string, unknown> {
  if (
    Object.keys(asRecord(payload.client)).length > 0 ||
    Object.keys(asRecord(payload.server)).length > 0
  ) {
    return payload;
  }
  return asRecord(payload.result);
}

async function loadUnitStatus(name: string, scope: "user" | "system"): Promise<UnitStatus> {
  const args = scope === "user"
    ? [
      "systemctl",
      "--user",
      "show",
      name,
      "--property=LoadState,ActiveState,SubState,UnitFileState,FragmentPath,Result",
    ]
    : [
      "systemctl",
      "show",
      name,
      "--property=LoadState,ActiveState,SubState,UnitFileState,FragmentPath,Result",
    ];
  const result = await runCommand(args);
  const fields = parseSystemctlShow(result.stdout);
  const activeState = String(fields.ActiveState || "");
  return {
    name,
    scope,
    load_state: String(fields.LoadState || ""),
    active_state: activeState,
    sub_state: String(fields.SubState || ""),
    unit_file_state: String(fields.UnitFileState || ""),
    fragment_path: String(fields.FragmentPath || ""),
    result: String(fields.Result || ""),
    healthy: activeState === "active",
  };
}

async function loadFailedUserUnits(): Promise<string[]> {
  const result = await runCommand([
    "systemctl",
    "--user",
    "list-units",
    "--type=service",
    "--state=failed",
    "--plain",
    "--no-legend",
    "--no-pager",
  ]);
  if (!result.stdout) {
    return [];
  }
  return result.stdout
    .split("\n")
    .map((line) => line.trim())
    .filter((line) => line.length > 0)
    .map((line) => line.split(/\s+/, 1)[0]);
}

function normalizeConnectionKey(value: string): string {
  const raw = String(value || "").trim().toLowerCase();
  if (!raw) {
    return "unknown";
  }
  return raw.replace(/[^a-z0-9@._:-]+/g, "-");
}

function parseSshTarget(value: string): { user: string; host: string; port: number } {
  let raw = String(value || "").trim();
  if (raw.startsWith("ssh://")) {
    raw = raw.slice("ssh://".length);
  }
  let user = "";
  let hostPort = raw;
  if (raw.includes("@")) {
    const parts = raw.split("@");
    user = parts.shift() || "";
    hostPort = parts.join("@");
  }
  let host = hostPort;
  let port = 22;
  const colonIndex = hostPort.lastIndexOf(":");
  if (colonIndex > 0) {
    const maybePort = hostPort.slice(colonIndex + 1);
    if (/^[0-9]+$/.test(maybePort)) {
      host = hostPort.slice(0, colonIndex);
      port = Number(maybePort) || 22;
    }
  }
  return { user: user.trim(), host: host.trim(), port };
}

function connectionKeyForTarget(sshTarget: string, explicit: string): string {
  if (String(explicit || "").trim()) {
    return normalizeConnectionKey(explicit);
  }
  const parsed = parseSshTarget(sshTarget);
  if (!parsed.host) {
    return "unknown";
  }
  const user = parsed.user || Deno.env.get("USER") || "vpittamp";
  return normalizeConnectionKey(`${user}@${parsed.host}:${parsed.port || 22}`);
}

function boolOrNull(value: unknown): boolean | null {
  return typeof value === "boolean" ? value : null;
}

function peerAliases(peer: Record<string, unknown>): string[] {
  const aliases = [
    String(peer.HostName || "").trim().toLowerCase(),
    String(peer.DNSName || "").trim().toLowerCase().replace(/\.$/, ""),
    ...asArray(peer.TailscaleIPs).map((ip) => String(ip || "").trim().toLowerCase()),
  ];
  return aliases.filter((alias) => alias.length > 0);
}

function targetAliases(target: HerdrRemoteTarget): string[] {
  const parsed = parseSshTarget(target.ssh_target);
  return [
    target.host,
    target.ssh_target,
    parsed.host,
    parsed.host.split(".", 1)[0] || "",
  ]
    .map((alias) => String(alias || "").trim().toLowerCase().replace(/\.$/, ""))
    .filter((alias) => alias.length > 0);
}

async function loadTailscalePeerHealth(
  targets: HerdrRemoteTarget[],
): Promise<Map<string, TailscalePeerHealth | null>> {
  const result = new Map<string, TailscalePeerHealth | null>();
  for (const target of targets) {
    result.set(target.connection_key, null);
  }
  if (targets.length === 0) {
    return result;
  }

  let status: { code: number; stdout: string; stderr: string };
  try {
    status = await runCommand(["tailscale", "status", "--json"], 1500);
  } catch {
    return result;
  }
  if (status.code !== 0 || !status.stdout) {
    return result;
  }

  let payload: Record<string, unknown>;
  try {
    payload = JSON.parse(status.stdout) as Record<string, unknown>;
  } catch {
    return result;
  }

  const peers = Object.values(asRecord(payload.Peer))
    .map(asRecord)
    .filter((peer) => Object.keys(peer).length > 0);
  for (const target of targets) {
    const aliases = targetAliases(target);
    const peer = peers.find((candidate) => {
      const candidateAliases = peerAliases(candidate);
      return aliases.some((alias) =>
        candidateAliases.includes(alias) ||
        candidateAliases.some((candidateAlias) => candidateAlias.startsWith(`${alias}.`))
      );
    });
    if (!peer) {
      result.set(target.connection_key, {
        checked: true,
        peer_found: false,
        host: "",
        dns_name: "",
        online: null,
        expired: null,
        tailscale_ips: [],
        issue: "",
      });
      continue;
    }
    const expired = boolOrNull(peer.Expired ?? peer.expired);
    const online = boolOrNull(peer.Online ?? peer.online);
    result.set(target.connection_key, {
      checked: true,
      peer_found: true,
      host: String(peer.HostName || ""),
      dns_name: String(peer.DNSName || ""),
      online,
      expired,
      tailscale_ips: asArray(peer.TailscaleIPs).map((ip) => String(ip || "")).filter((ip) =>
        ip.length > 0
      ),
      issue: expired === true ? "Tailscale peer node key is expired" : "",
    });
  }

  return result;
}

function herdrRemoteTargetsFile(): string {
  const configured = String(Deno.env.get("I3PM_HERDR_REMOTE_TARGETS_FILE") || "").trim();
  if (configured) {
    return configured.replace(/^~\//, `${Deno.env.get("HOME") || ""}/`);
  }
  return `${Deno.env.get("HOME") || ""}/.config/i3/herdr-remote-targets.json`;
}

async function loadHerdrRemoteTargets(): Promise<HerdrRemoteTarget[]> {
  let rawTargets: unknown = [];
  const envPayload = String(Deno.env.get("I3PM_HERDR_REMOTE_TARGETS") || "").trim();
  if (envPayload) {
    try {
      const parsed = JSON.parse(envPayload);
      if (Array.isArray(parsed)) {
        rawTargets = parsed;
      }
    } catch {
      rawTargets = [];
    }
  } else {
    try {
      const parsed = JSON.parse(await Deno.readTextFile(herdrRemoteTargetsFile()));
      if (Array.isArray(parsed)) {
        rawTargets = parsed;
      }
    } catch {
      rawTargets = [];
    }
  }

  const seen = new Set<string>();
  const targets: HerdrRemoteTarget[] = [];
  for (const item of Array.isArray(rawTargets) ? rawTargets : []) {
    if (!item || typeof item !== "object") {
      continue;
    }
    const record = item as Record<string, unknown>;
    const hostRaw = String(record.host || "").trim().toLowerCase();
    const sshTarget = String(record.ssh_target || record.sshTarget || hostRaw).trim();
    if (!sshTarget) {
      continue;
    }
    const parsedTarget = parseSshTarget(sshTarget);
    const host = hostRaw || parsedTarget.host.toLowerCase();
    const connectionKey = connectionKeyForTarget(
      sshTarget,
      String(record.connection_key || record.connectionKey || ""),
    );
    const dedupeKey = connectionKey !== "unknown" ? connectionKey : sshTarget.toLowerCase();
    if (seen.has(dedupeKey)) {
      continue;
    }
    seen.add(dedupeKey);
    targets.push({
      host: host || sshTarget.toLowerCase(),
      ssh_target: sshTarget,
      connection_key: connectionKey,
    });
  }
  return targets;
}

async function collectHerdrHealth(
  runHerdr: (args: string[]) => Promise<{ code: number; stdout: string; stderr: string }>,
): Promise<HerdrHealth> {
  const status = await runHerdr(["status", "--json"]);
  if (status.code !== 0 || !status.stdout) {
    return {
      healthy: false,
      issues: [status.stderr || status.stdout || "herdr status failed"],
      client_version: "",
      server_version: "",
      protocol: 0,
      compatible: false,
      server_running: false,
      agent_count: 0,
      pane_count: 0,
      integrations: { claude: false, codex: false },
    };
  }

  let statusPayload: Record<string, unknown>;
  try {
    statusPayload = JSON.parse(status.stdout) as Record<string, unknown>;
  } catch {
    return {
      healthy: false,
      issues: ["herdr status returned invalid JSON"],
      client_version: "",
      server_version: "",
      protocol: 0,
      compatible: false,
      server_running: false,
      agent_count: 0,
      pane_count: 0,
      integrations: { claude: false, codex: false },
    };
  }

  const statusRoot = herdrStatusRoot(statusPayload);
  const client = asRecord(statusRoot.client);
  const server = asRecord(statusRoot.server);
  const agentList = await runHerdr(["agent", "list"]);
  const paneList = await runHerdr(["pane", "list"]);
  const integrationStatus = await runHerdr(["integration", "status"]);
  const issues: string[] = [];

  const serverRunning = server.running === true;
  const compatible = server.compatible === true;
  if (!serverRunning) {
    issues.push("Herdr server is not running");
  }
  if (!compatible) {
    issues.push("Herdr client/server protocol is not compatible");
  }

  let agentCount = 0;
  if (agentList.code !== 0 || !agentList.stdout) {
    issues.push("herdr agent list failed");
  } else {
    try {
      const payload = JSON.parse(agentList.stdout);
      agentCount = Array.isArray(payload?.result?.agents) ? payload.result.agents.length : 0;
    } catch {
      issues.push("herdr agent list returned invalid JSON");
    }
  }

  let paneCount = 0;
  if (paneList.code !== 0 || !paneList.stdout) {
    issues.push("herdr pane list failed");
  } else {
    try {
      const payload = JSON.parse(paneList.stdout);
      paneCount = Array.isArray(payload?.result?.panes) ? payload.result.panes.length : 0;
    } catch {
      issues.push("herdr pane list returned invalid JSON");
    }
  }

  if (integrationStatus.code !== 0) {
    issues.push("herdr integration status failed");
  }
  const integrationOutput = integrationStatus.stdout || integrationStatus.stderr || "";
  const integrations = {
    claude: /^claude:\s+(installed|current)\b/m.test(integrationOutput),
    codex: /^codex:\s+(installed|current)\b/m.test(integrationOutput),
  };
  if (!integrations.claude) {
    issues.push("Herdr Claude integration is not installed");
  }
  if (!integrations.codex) {
    issues.push("Herdr Codex integration is not installed");
  }

  return {
    healthy: issues.length === 0,
    issues,
    client_version: String(client.version || ""),
    server_version: String(server.version || ""),
    protocol: Number(client.protocol || server.protocol || 0),
    compatible,
    server_running: serverRunning,
    agent_count: agentCount,
    pane_count: paneCount,
    integrations,
  };
}

async function loadHerdrHealth(): Promise<HerdrHealth | null> {
  const runHerdr = async (
    args: string[],
  ): Promise<{ code: number; stdout: string; stderr: string }> => {
    try {
      return await runCommand(["herdr", ...args], 2500);
    } catch (error) {
      return {
        code: 1,
        stdout: "",
        stderr: error instanceof Error ? error.message : String(error),
      };
    }
  };
  return await collectHerdrHealth(runHerdr);
}

async function loadHerdrRemoteHealth(): Promise<HerdrRemoteHealth[]> {
  const targets = await loadHerdrRemoteTargets();
  const tailscaleHealth = await loadTailscalePeerHealth(targets);
  const results = await Promise.all(targets.map(async (target): Promise<HerdrRemoteHealth> => {
    const tailscale = tailscaleHealth.get(target.connection_key) ?? null;
    let proxyResult: { code: number; stdout: string; stderr: string };
    try {
      proxyResult = await runCommand([
        "ssh",
        "-o",
        "BatchMode=yes",
        "-o",
        "ConnectTimeout=1",
        "-o",
        "ConnectionAttempts=1",
        "-o",
        "ServerAliveInterval=1",
        "-o",
        "ServerAliveCountMax=1",
        target.ssh_target,
        "i3pm",
        "herdr-proxy",
        "snapshot",
        "--json",
      ], 3000);
    } catch (error) {
      proxyResult = {
        code: 1,
        stdout: "",
        stderr: error instanceof Error ? error.message : String(error),
      };
    }

    const base = {
      host: target.host,
      ssh_target: target.ssh_target,
      connection_key: target.connection_key,
      proxy_reachable: false,
      proxy_schema_version: "",
      proxy_protocol_version: 0,
      tailscale,
    };
    if (proxyResult.code !== 0 || !proxyResult.stdout) {
      const issues = [
        `Herdr proxy unreachable: ${proxyResult.stderr || proxyResult.stdout || "no output"}`,
      ];
      if (tailscale?.issue) {
        issues.unshift(tailscale.issue);
      }
      return {
        ...base,
        healthy: false,
        issues,
        client_version: "",
        server_version: "",
        protocol: 0,
        compatible: false,
        server_running: false,
        agent_count: 0,
        pane_count: 0,
        integrations: { claude: false, codex: false },
      };
    }

    let snapshot: Record<string, unknown>;
    try {
      snapshot = JSON.parse(proxyResult.stdout) as Record<string, unknown>;
    } catch {
      return {
        ...base,
        proxy_reachable: true,
        healthy: false,
        issues: ["Herdr proxy returned invalid JSON"],
        client_version: "",
        server_version: "",
        protocol: 0,
        compatible: false,
        server_running: false,
        agent_count: 0,
        pane_count: 0,
        integrations: { claude: false, codex: false },
      };
    }

    const proxySchemaVersion = String(snapshot.schema_version || "");
    const proxyProtocolVersion = Number(snapshot.protocol_version || 0);
    const statusRoot = herdrStatusRoot(asRecord(snapshot.status));
    const client = asRecord(statusRoot.client);
    const server = asRecord(statusRoot.server);
    const issues: string[] = [];
    if (proxySchemaVersion !== "i3pm.herdr_proxy.v1") {
      issues.push(`Herdr proxy schema mismatch: ${proxySchemaVersion || "missing"}`);
    }
    if (proxyProtocolVersion !== 1) {
      issues.push(`Herdr proxy protocol mismatch: ${proxyProtocolVersion || "missing"}`);
    }
    if (tailscale?.issue) {
      issues.push(tailscale.issue);
    }
    const serverRunning = server.running === true;
    const compatible = server.compatible === true;
    if (!serverRunning) {
      issues.push("Remote Herdr server is not running");
    }
    if (!compatible) {
      issues.push("Remote Herdr client/server protocol is not compatible");
    }

    const health: HerdrHealth = {
      healthy: issues.length === 0,
      issues,
      client_version: String(client.version || ""),
      server_version: String(server.version || ""),
      protocol: Number(client.protocol || server.protocol || 0),
      compatible,
      server_running: serverRunning,
      agent_count: asArray(snapshot.agents).length,
      pane_count: asArray(snapshot.panes).length,
      integrations: { claude: false, codex: false },
    };
    return {
      ...health,
      ...base,
      proxy_reachable: true,
      proxy_schema_version: proxySchemaVersion,
      proxy_protocol_version: proxyProtocolVersion,
      tailscale,
    };
  }));
  return results;
}

async function loadMcpBrowserHealth(): Promise<McpBrowserHealth | null> {
  const result = await runCommand(["mcp-browser-lifecycle", "health"]);
  if (result.code !== 0 || !result.stdout) {
    return null;
  }
  try {
    return JSON.parse(result.stdout) as McpBrowserHealth;
  } catch {
    return null;
  }
}

async function loadHomeManagerGenerationFromService(): Promise<string> {
  const result = await runCommand([
    "systemctl",
    "show",
    "home-manager-vpittamp.service",
    "-p",
    "ExecStart",
    "--no-pager",
  ]);
  if (!result.stdout) {
    return "";
  }
  const match = result.stdout.match(/\/nix\/store\/[^ ;]+-home-manager-generation/);
  return match ? match[0] : "";
}

function makePathCheck(currentPath: string, expectedPath: string): PathCheck {
  return {
    current_path: currentPath,
    expected_path: expectedPath,
    matches: !!(currentPath && expectedPath && currentPath === expectedPath),
  };
}

function statusColor(status: HealthReport["overall_status"]): (text: string) => string {
  if (status === "ok") {
    return green;
  }
  if (status === "warn") {
    return yellow;
  }
  return red;
}

function formatUnitStatus(unit: UnitStatus): string {
  const state = unit.healthy
    ? green(unit.active_state || "active")
    : red(unit.active_state || "unknown");
  return `${unit.name} ${state} ${dim(`${unit.sub_state || "unknown"} / ${unit.result || "n/a"}`)}`;
}

async function loadDashboardHealth(): Promise<DashboardHealth | null> {
  const client = new DaemonClient();
  try {
    const result = await client.request<{
      success?: boolean;
      schema_version?: string;
      snapshot_version?: number;
      session_generation?: number;
      display_generation?: number;
      focus_generation?: number;
      issues?: unknown[];
      warnings?: unknown[];
    }>("dashboard.validate", {});
    const issues = Array.isArray(result.issues)
      ? result.issues.map((issue) => String(issue)).filter(Boolean)
      : [];
    const warnings = Array.isArray(result.warnings)
      ? result.warnings.map((warning) => String(warning)).filter(Boolean)
      : [];
    const schemaVersion = String(result.schema_version || "");
    if (schemaVersion !== "i3pm.dashboard.v2") {
      issues.push(`schema_version:${schemaVersion || "missing"}`);
    }
    return {
      healthy: result.success === true && issues.length === 0,
      reachable: true,
      schema_version: schemaVersion,
      snapshot_version: Number(result.snapshot_version || 0),
      session_generation: Number(result.session_generation || 0),
      display_generation: Number(result.display_generation || 0),
      focus_generation: Number(result.focus_generation || 0),
      issues,
      warnings,
    };
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    return {
      healthy: false,
      reachable: false,
      schema_version: "",
      snapshot_version: 0,
      session_generation: 0,
      display_generation: 0,
      focus_generation: 0,
      issues: [message || "dashboard.validate failed"],
      warnings: [],
    };
  } finally {
    client.disconnect();
  }
}

async function collectHealthReport(): Promise<HealthReport> {
  const coreUnits = await Promise.all([
    loadUnitStatus("i3-project-daemon.service", "user"),
    loadUnitStatus("quickshell-runtime-shell.service", "user"),
    loadUnitStatus("mcp-chrome-devtools-browser.service", "user"),
    loadUnitStatus("mcp-browser-orphan-reaper.timer", "user"),
    loadUnitStatus("home-manager-vpittamp.service", "system"),
  ]);

  const failedUserUnits = await loadFailedUserUnits();
  const optionalIssues = failedUserUnits
    .filter((unit) => OPTIONAL_USER_UNIT_PREFIXES.some((prefix) => unit.startsWith(prefix)))
    .map((unit) => `${unit} is failed`);
  const coreFailedUserUnits = failedUserUnits.filter((unit) =>
    !OPTIONAL_USER_UNIT_PREFIXES.some((prefix) => unit.startsWith(prefix))
  );

  const systemGeneration = await realPathOrEmpty("/run/current-system");
  const homeManagerGeneration = await loadHomeManagerGenerationFromService();
  const homeManagerProfileGeneration = await realPathOrEmpty(
    "~/.local/state/nix/profiles/home-manager",
  );
  const currentShellQml = await realPathOrEmpty("~/.config/quickshell/i3pm-shell/shell.qml");
  const expectedShellQml = await realPathOrEmpty(
    `${homeManagerGeneration}/home-files/.config/quickshell/i3pm-shell/shell.qml`,
  );
  const currentShellService = await realPathOrEmpty(
    "~/.config/systemd/user/quickshell-runtime-shell.service",
  );
  const expectedShellService = await realPathOrEmpty(
    `${homeManagerGeneration}/home-files/.config/systemd/user/quickshell-runtime-shell.service`,
  );
  const shellQmlCheck = makePathCheck(currentShellQml, expectedShellQml);
  const shellServiceCheck = makePathCheck(currentShellService, expectedShellService);
  const daemonSocketPath = getSocketPath();
  const daemonSocketExists = await Deno.stat(daemonSocketPath).then(() => true).catch(() => false);
  const dashboard = daemonSocketExists ? await loadDashboardHealth() : null;
  const herdr = await loadHerdrHealth();
  const herdrRemotes = await loadHerdrRemoteHealth();
  const mcpBrowserRuntime = await loadMcpBrowserHealth();

  const coreIssues: string[] = [];
  for (const unit of coreUnits) {
    if (!unit.healthy) {
      coreIssues.push(
        `${unit.name} is ${unit.active_state || "unknown"}/${unit.sub_state || "unknown"}`,
      );
    }
  }
  for (const unit of coreFailedUserUnits) {
    coreIssues.push(`${unit} is failed`);
  }
  if (!daemonSocketExists) {
    coreIssues.push(`daemon socket missing at ${daemonSocketPath}`);
  }
  if (!dashboard) {
    coreIssues.push("dashboard health unavailable");
  } else if (!dashboard.healthy) {
    coreIssues.push(...dashboard.issues.map((issue) => `dashboard: ${issue}`));
  }
  if (currentShellQml && expectedShellQml && !shellQmlCheck.matches) {
    coreIssues.push("quickshell QML path does not match current Home Manager generation");
  }
  if (currentShellService && expectedShellService && !shellServiceCheck.matches) {
    coreIssues.push("quickshell systemd unit does not match current Home Manager generation");
  }
  if (!herdr) {
    coreIssues.push("Herdr health unavailable");
  } else if (!herdr.healthy) {
    coreIssues.push(...herdr.issues.map((issue) => `Herdr: ${issue}`));
  }
  for (const remote of herdrRemotes) {
    if (!remote.healthy) {
      const label = remote.host || remote.ssh_target || remote.connection_key || "remote";
      optionalIssues.push(
        ...remote.issues.map((issue) => `Herdr ${label}: ${issue}`),
      );
    }
  }
  if (!mcpBrowserRuntime) {
    coreIssues.push("mcp browser health helper unavailable");
  } else if (!mcpBrowserRuntime.healthy) {
    coreIssues.push(...mcpBrowserRuntime.issues.map((issue) => `mcp browsers: ${issue}`));
  }

  const overallStatus: HealthReport["overall_status"] = coreIssues.length > 0
    ? "fail"
    : optionalIssues.length > 0
    ? "warn"
    : "ok";

  return {
    timestamp: new Date().toISOString(),
    overall_status: overallStatus,
    core_issues: coreIssues,
    optional_issues: optionalIssues,
    core_units: coreUnits,
    failed_user_units: failedUserUnits,
    system_generation: systemGeneration,
    home_manager_generation: homeManagerGeneration,
    home_manager_profile_generation: homeManagerProfileGeneration,
    daemon_socket: {
      path: daemonSocketPath,
      exists: daemonSocketExists,
    },
    quickshell: {
      shell_qml: shellQmlCheck,
      service_unit: shellServiceCheck,
    },
    dashboard,
    herdr,
    herdr_remotes: herdrRemotes,
    mcp_browser_runtime: mcpBrowserRuntime,
  };
}

function printReport(report: HealthReport): void {
  const color = statusColor(report.overall_status);
  console.log(`${bold("Health")} ${color(report.overall_status.toUpperCase())}`);
  console.log(`${dim(report.timestamp)}`);
  console.log("");

  console.log(bold("Core Services"));
  for (const unit of report.core_units) {
    console.log(`  ${formatUnitStatus(unit)}`);
  }
  console.log(
    `  daemon socket ${report.daemon_socket.exists ? green("present") : red("missing")} ${
      dim(report.daemon_socket.path)
    }`,
  );
  console.log("");

  console.log(bold("Convergence"));
  console.log(`  system ${cyan(report.system_generation || "(missing)")}`);
  console.log(`  home-manager ${cyan(report.home_manager_generation || "(missing)")}`);
  console.log(`  hm profile ${dim(report.home_manager_profile_generation || "(missing)")}`);
  console.log(
    `  quickshell qml ${report.quickshell.shell_qml.matches ? green("matched") : red("mismatch")} ${
      dim(report.quickshell.shell_qml.current_path || "(missing)")
    }`,
  );
  console.log(
    `  quickshell unit ${
      report.quickshell.service_unit.matches ? green("matched") : red("mismatch")
    } ${dim(report.quickshell.service_unit.current_path || "(missing)")}`,
  );
  if (report.dashboard) {
    console.log(
      `  dashboard ${report.dashboard.healthy ? green("matched") : red("invalid")} ${
        dim(
          `${
            report.dashboard.schema_version || "missing"
          } snapshot ${report.dashboard.snapshot_version} focus ${report.dashboard.focus_generation}`,
        )
      }`,
    );
    if (report.dashboard.warnings.length > 0) {
      console.log(`    warnings ${yellow(report.dashboard.warnings.join(", "))}`);
    }
  } else {
    console.log(`  dashboard ${red("unavailable")}`);
  }
  console.log("");

  if (report.herdr) {
    console.log(bold("Herdr"));
    console.log(
      `  server ${report.herdr.server_running ? green("running") : red("down")} ${
        dim(
          `${report.herdr.server_version || "unknown"} protocol ${
            report.herdr.protocol || "unknown"
          }`,
        )
      }`,
    );
    console.log(
      `  protocol ${report.herdr.compatible ? green("compatible") : red("mismatch")} ${
        dim(`client ${report.herdr.client_version || "unknown"}`)
      }`,
    );
    console.log(
      `  agents ${cyan(String(report.herdr.agent_count))} panes ${
        cyan(String(report.herdr.pane_count))
      }`,
    );
    console.log(
      `  integrations claude=${
        report.herdr.integrations.claude ? green("installed") : red("missing")
      } codex=${report.herdr.integrations.codex ? green("installed") : red("missing")}`,
    );
    console.log("");
  }

  if (report.herdr_remotes.length > 0) {
    console.log(bold("Herdr Remotes"));
    for (const remote of report.herdr_remotes) {
      const label = remote.host || remote.ssh_target || remote.connection_key || "remote";
      console.log(
        `  ${label} ${remote.healthy ? green("healthy") : yellow("warning")} ${
          dim(
            `${remote.connection_key || remote.ssh_target} proxy ${
              remote.proxy_reachable ? "reachable" : "down"
            } ${remote.proxy_schema_version || "missing-schema"} protocol ${
              remote.proxy_protocol_version || "unknown"
            } agents ${remote.agent_count} panes ${remote.pane_count}`,
          )
        }`,
      );
      if (remote.tailscale?.checked && remote.tailscale.peer_found) {
        const expired = remote.tailscale.expired === true ? red("expired") : green("valid");
        const online = remote.tailscale.online === false ? yellow("offline") : green("online");
        console.log(
          `    ${dim("tailscale")} ${online} ${expired} ${
            dim(
              remote.tailscale.dns_name || remote.tailscale.host ||
                remote.tailscale.tailscale_ips[0] || "",
            )
          }`,
        );
      }
      for (const issue of remote.issues) {
        console.log(`    ${yellow(issue)}`);
      }
    }
    console.log("");
  }

  if (report.mcp_browser_runtime) {
    const runtime = report.mcp_browser_runtime;
    console.log(bold("MCP Browsers"));
    console.log(
      `  browser service ${
        runtime.managed_browser_service.active ? green("active") : red("inactive")
      } ${dim(runtime.managed_browser_service.name)}`,
    );
    console.log(
      `  reaper timer ${runtime.reaper_timer.active ? green("active") : red("inactive")} ${
        dim(runtime.reaper_timer.name)
      }`,
    );
    console.log(
      `  endpoint ${
        runtime.listener.pid && runtime.listener.matches_expected_profile
          ? green("matched")
          : red("drift")
      } ${dim(runtime.endpoint_url)}`,
    );
    if (runtime.listener.pid) {
      console.log(
        `  listener pid ${runtime.listener.pid} ${dim(runtime.listener.cmdline || "(unknown)")}`,
      );
    }
    if (runtime.stale_candidates.length > 0) {
      console.log(`  stale processes ${red(String(runtime.stale_candidates.length))}`);
      for (const candidate of runtime.stale_candidates.slice(0, 5)) {
        console.log(
          `    ${candidate.pid} ${dim(`${candidate.age_seconds}s`)} ${
            dim(candidate.cmdline || "(unknown)")
          }`,
        );
      }
    } else {
      console.log(`  stale processes ${green("0")}`);
    }
    console.log("");
  }

  if (report.core_issues.length > 0) {
    console.log(red(bold("Core Issues")));
    for (const issue of report.core_issues) {
      console.log(`  ${red("•")} ${issue}`);
    }
    console.log("");
  }

  if (report.optional_issues.length > 0) {
    console.log(yellow(bold("Optional Issues")));
    for (const issue of report.optional_issues) {
      console.log(`  ${yellow("•")} ${issue}`);
    }
  }
}

export async function healthCommand(args: string[], _flags: CommandOptions): Promise<number> {
  const parsed = parseArgs(args, {
    boolean: ["help", "json"],
    alias: { h: "help" },
  });

  if (parsed.help) {
    showHelp();
    return 0;
  }

  const report = await collectHealthReport();
  if (parsed.json) {
    console.log(JSON.stringify(report, null, 2));
  } else {
    printReport(report);
  }

  if (report.overall_status === "fail") {
    return 1;
  }
  if (report.overall_status === "warn") {
    return 2;
  }
  return 0;
}
