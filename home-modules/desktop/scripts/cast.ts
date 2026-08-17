// cast - desktop-level Google Cast sender that drives Chrome's own cast engine.
//
// Chrome's built-in "Cast screen" is the only maintained Linux sender for the
// mirroring protocol Chromecast-class receivers accept (third-party Cast V2
// tools can only fling media URLs), so instead of reimplementing the protocol
// this CLI drives Chrome itself through the DevTools Protocol's Cast domain
// (Cast.startDesktopMirroring / Cast.stopCasting) against a dedicated caster
// instance (cast-caster.service: own profile + --remote-debugging-port, which
// Chrome 136+ requires to differ from the default profile). Same engine as the
// toolbar Cast menu: same receivers, same quality, same latency — without
// walking the Chrome UI.
//
// Usage:
//   cast list [--json]        receivers the caster discovered (mDNS); no
//                             receiver on the LAN is not an error
//   cast start [sink]         mirror a screen; the walker portal picker
//                             chooses WHICH output; sink defaults to the only
//                             receiver, or a walker dmenu pick
//   cast extend [WxH]         wireless extended display: cast-extend on
//                               (headless output) + start; pick the HEADLESS-*
//                               entry in the portal picker
//   cast stop [sink]          stop the current cast (+ disable headless)
//   cast toggle               stop if casting, otherwise extend
//   cast status [--json]      caster health + live session + headless state
//
// Behaviour notes (verified against Chromium source + live on this LAN, 2026-08):
// - Cast.* only works on a PAGE target (/json/list), not the browser endpoint.
// - Sinks are addressed by FRIENDLY NAME ("Living Room TV"), not id, and a
//   sink with a live route carries `session` in Cast.sinksUpdated — that is
//   how status verifies a cast is really still up.
// - Never send Cast.disable: it tears down every route the caster started.
//   stopCasting(sink) is the targeted stop; a later session may stop a cast
//   an earlier one started. Mirroring survives this CLI exiting.
// - On Wayland every desktop-mirror start shows the portal chooser (walker,
//   here) once — no Chrome flag can bypass it. The caster runs with
//   --auto-select-desktop-capture-source so Chrome's own Share dialog is the
//   one prompt that does NOT appear.

const CDP_PORT = Number(Deno.env.get("CAST_CDP_PORT") ?? 9333);
const CDP_HTTP = `http://127.0.0.1:${CDP_PORT}`;
const RUNTIME_DIR =
  Deno.env.get("XDG_RUNTIME_DIR") ?? `/run/user/${typeof Deno.uid === "function" ? Deno.uid() : 1000}`;
const STATE_FILE = `${RUNTIME_DIR}/cast.state`;
const LOCK_FILE = `${RUNTIME_DIR}/cast.lock`;
// Pinned choice for the portal screencast chooser (cast-portal-chooser):
// "headless" for extend, "focused" for mirror — the cast flow picks its
// output itself instead of putting an interactive menu mid-cast.
const PICKER_FILE = `${RUNTIME_DIR}/cast.picker`;
const CAST_EXTEND = `${Deno.env.get("HOME") ?? "/home"}/.local/bin/cast-extend`;

// startDesktopMirroring resolves only after the user satisfies the portal
// picker, so it needs a human-scale timeout; plain calls get a short one.
const CALL_TIMEOUT_MS = 10_000;
const MIRROR_TIMEOUT_MS = 180_000;

type Sink = { name: string; id: string; session?: string };
type CastState = { mode: "mirror" | "extend"; sink: string; startedAt: string };

const sleep = (ms: number) => new Promise<void>((resolve) => setTimeout(resolve, ms));

// sway helpers (cast-extend, headlessOutput) need SWAYSOCK; a desktop
// context always has it, a foreign ssh shell does not — find the socket.
if (!Deno.env.get("SWAYSOCK")) {
  try {
    // NB: no isFile filter — the sway IPC socket is a unix socket, which
    // DirEntry does not classify as a file. Newest mtime wins: a crashed
    // session leaves its socket behind and only the live one answers.
    const swaysock = [...Deno.readDirSync(RUNTIME_DIR)]
      .filter((e) => e.name.startsWith("sway-ipc."))
      .map((e) => `${RUNTIME_DIR}/${e.name}`)
      .sort((a, b) =>
        (Deno.statSync(b).mtime?.getTime() ?? 0) - (Deno.statSync(a).mtime?.getTime() ?? 0)
      )[0];
    if (swaysock) Deno.env.set("SWAYSOCK", swaysock);
  } catch {
    // no runtime dir readable — desktop contexts have SWAYSOCK anyway
  }
}

function fail(message: string): never {
  console.error(`cast: ${message}`);
  Deno.exit(1);
}

// ---------------------------------------------------------------------------
// Caster lifecycle + CDP transport
// ---------------------------------------------------------------------------

async function casterUp(timeoutMs = 800): Promise<boolean> {
  try {
    const res = await fetch(`${CDP_HTTP}/json/version`, {
      signal: AbortSignal.timeout(timeoutMs),
    });
    return res.ok;
  } catch {
    return false;
  }
}

async function ensureCaster(): Promise<void> {
  if (await casterUp()) return;
  const start = new Deno.Command("systemctl", {
    args: ["--user", "start", "cast-caster"],
    stdin: "null",
    stdout: "null",
    stderr: "inherit",
  });
  await start.output();
  for (let i = 0; i < 40; i++) {
    if (await casterUp(500)) return;
    await sleep(500);
  }
  // Throw (not fail/exit): callers on the start path have rollback — a hard
  // exit here would skip it and strand the headless output + lock.
  throw new Error(
    `caster Chrome is not responding on 127.0.0.1:${CDP_PORT} (see journalctl --user -u cast-caster)`,
  );
}

class Cdp {
  readonly sinks: Sink[] = [];
  #ws: WebSocket;
  #nextId = 1;
  #pending = new Map<number, { resolve: (v: unknown) => void; reject: (e: Error) => void }>();
  #firstSinks: Promise<void>;

  constructor(ws: WebSocket) {
    this.#ws = ws;
    this.#firstSinks = new Promise((resolve) => {
      ws.addEventListener("message", (ev) => this.#onMessage(String(ev.data), resolve));
    });
  }

  #onMessage(raw: string, sinksArrived: () => void): void {
    let msg: Record<string, unknown>;
    try {
      msg = JSON.parse(raw);
    } catch {
      return;
    }
    const id = msg.id as number | undefined;
    if (typeof id === "number" && this.#pending.has(id)) {
      const pending = this.#pending.get(id)!;
      this.#pending.delete(id);
      if (msg.error) {
        pending.reject(new Error(String((msg.error as { message?: string }).message ?? JSON.stringify(msg.error))));
      } else {
        pending.resolve(msg.result ?? {});
      }
      return;
    }
    if (msg.method === "Cast.sinksUpdated") {
      const sinks = (msg.params as { sinks?: Sink[] } | undefined)?.sinks ?? [];
      this.sinks.length = 0;
      this.sinks.push(...sinks);
      sinksArrived();
    }
  }

  send(method: string, params?: Record<string, unknown>, timeoutMs = CALL_TIMEOUT_MS): Promise<unknown> {
    const id = this.#nextId++;
    const promise = new Promise<unknown>((resolve, reject) => {
      const timer = setTimeout(() => {
        if (this.#pending.delete(id)) reject(new Error(`${method}: timed out`));
      }, timeoutMs);
      Deno.unrefTimer(timer); // an armed timer must never keep the process alive
      this.#pending.set(id, {
        resolve: (value) => {
          clearTimeout(timer);
          resolve(value);
        },
        reject: (err) => {
          clearTimeout(timer);
          reject(err);
        },
      });
    });
    this.#ws.send(JSON.stringify({ id, method, ...(params ? { params } : {}) }));
    return promise;
  }

  // Waits for the first sinksUpdated (fires immediately on Cast.enable) and
  // lets mDNS settle: while the list is empty, up to settleMs; once non-empty,
  // one extra short window so trickle-discovered receivers land before the
  // caller counts them (a partial first event would otherwise make a
  // multi-receiver LAN look like a single-receiver one and skip the picker).
  async waitForSinks(settleMs: number): Promise<void> {
    await Promise.race([this.#firstSinks, sleep(CALL_TIMEOUT_MS).then(() => {
      throw new Error("caster sent no Cast.sinksUpdated event");
    })]);
    const deadline = Date.now() + settleMs;
    while (this.sinks.length === 0 && Date.now() < deadline) {
      await sleep(250);
    }
    if (this.sinks.length > 0) {
      await sleep(1_500);
    }
  }

  close(): void {
    try {
      this.#ws.close();
    } catch {
      // already closed
    }
  }
}

async function connect(wsUrl: string): Promise<Cdp> {
  const ws = new WebSocket(wsUrl);
  await new Promise<void>((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error("websocket connect timed out")), 3_000);
    ws.addEventListener("open", () => {
      clearTimeout(timer);
      resolve();
    }, { once: true });
    ws.addEventListener("error", () => {
      clearTimeout(timer);
      reject(new Error("websocket error"));
    }, { once: true });
  });
  return new Cdp(ws);
}

// Cast.* needs a PAGE session. Which page matters: policy-force-installed
// extensions (the Claude Code OAuth helper) open tabs whose sessions can be
// wedged, and a wedged session answers nothing — not even browser-domain
// pings. So always talk to a dedicated about:blank tab: reuse the one a
// previous run left behind (it parents the live mirroring route), verify it
// with a liveness ping, and otherwise make a fresh one via /json/new.
async function openSession(): Promise<Cdp> {
  await ensureCaster();
  try {
    const res = await fetch(`${CDP_HTTP}/json/list`, { signal: AbortSignal.timeout(2_000) });
    const targets = (await res.json()) as Array<{ type: string; url: string; webSocketDebuggerUrl?: string }>;
    const ours = targets.find((t) => t.type === "page" && t.url === "about:blank" && t.webSocketDebuggerUrl);
    if (ours) {
      let cdp: Cdp | undefined;
      try {
        cdp = await connect(ours.webSocketDebuggerUrl!);
        await cdp.send("Target.getTargets", undefined, 2_000); // liveness ping
        return cdp;
      } catch {
        // Wedged: close the socket — an abandoned open WebSocket pins the
        // Deno event loop open forever, hanging every caller of this CLI.
        cdp?.close();
      }
    }
  } catch {
    // /json/list failed entirely — try /json/new directly
  }
  const res = await fetch(`${CDP_HTTP}/json/new?about:blank`, {
    method: "PUT",
    signal: AbortSignal.timeout(3_000),
  });
  if (!res.ok) throw new Error(`/json/new: HTTP ${res.status}`);
  const target = await res.json() as { webSocketDebuggerUrl?: string };
  if (!target.webSocketDebuggerUrl) throw new Error("/json/new returned no webSocketDebuggerUrl");
  return connect(target.webSocketDebuggerUrl);
}

async function withCdp<T>(fn: (cdp: Cdp) => Promise<T>): Promise<T> {
  const cdp = await openSession();
  try {
    return await fn(cdp);
  } finally {
    cdp.close();
  }
}

async function discoverSinks(settleMs = 8_000): Promise<Sink[]> {
  return withCdp(async (cdp) => {
    await cdp.send("Cast.enable");
    await cdp.waitForSinks(settleMs);
    return [...cdp.sinks];
  });
}

// ---------------------------------------------------------------------------
// Local helpers: state, lock, cast-extend, sway outputs, walker dmenu
// ---------------------------------------------------------------------------

function readState(): CastState | null {
  try {
    const state = JSON.parse(Deno.readTextFileSync(STATE_FILE)) as CastState;
    return state?.sink ? state : null;
  } catch {
    return null;
  }
}

function saveState(state: CastState): void {
  Deno.writeTextFileSync(STATE_FILE, JSON.stringify(state));
}

function clearState(): void {
  try {
    Deno.removeSync(STATE_FILE);
  } catch {
    // already gone
  }
}

function processAlive(pid: number): boolean {
  try {
    return new Deno.Command("kill", {
      args: ["-0", String(pid)],
      stdin: "null",
      stdout: "null",
      stderr: "null",
    }).outputSync().success;
  } catch {
    return false;
  }
}

// startDesktopMirroring only resolves after the human satisfies the portal
// picker (minutes, potentially), and the state file is written only afterwards
// — so a second start during that window looks like "not casting" and its
// failure rollback would disable the headless output under the first run's
// live cast. The lock closes that window; it is stolen if the holder is dead.
function acquireStartLock(): void {
  for (let attempt = 0; attempt < 2; attempt++) {
    try {
      Deno.writeTextFileSync(LOCK_FILE, String(Deno.pid), { createNew: true });
      return;
    } catch (err) {
      if (!(err instanceof Deno.errors.AlreadyExists)) throw err;
      let holder = 0;
      try {
        holder = Number(Deno.readTextFileSync(LOCK_FILE));
      } catch {
        // unreadable — treat as dead
      }
      if (Number.isInteger(holder) && holder > 0 && processAlive(holder)) {
        fail(`another cast start is already in progress (pid ${holder})`);
      }
      try {
        Deno.removeSync(LOCK_FILE);
      } catch {
        // raced someone else stealing it — loop once more
      }
    }
  }
  fail("could not acquire the cast start lock");
}

async function run(
  cmd: string,
  args: string[],
  options: { quiet?: boolean } = {},
): Promise<void> {
  try {
    const child = new Deno.Command(cmd, {
      args,
      stdin: "null",
      stdout: options.quiet ? "piped" : "inherit",
      stderr: "inherit",
    }).spawn();
    const { success } = await child.output();
    if (!success) throw new Error(`${cmd} ${args.join(" ")} failed`);
  } catch (err) {
    if (err instanceof Deno.errors.NotFound) {
      throw new Error(`${cmd} not found on PATH`);
    }
    throw err;
  }
}

type Headless = { output: string; width: number; height: number };

async function headlessOutput(): Promise<Headless | null> {
  try {
    const out = await new Deno.Command("swaymsg", {
      args: ["-t", "get_outputs"],
      stdin: "null",
      stdout: "piped",
      stderr: "null",
    }).output();
    const outputs = JSON.parse(new TextDecoder().decode(out.stdout)) as Array<Record<string, unknown>>;
    const live = outputs.find(
      (o) => String(o.name).startsWith("HEADLESS-") && o.active === true,
    );
    if (!live) return null;
    const mode = live.current_mode as { width?: number; height?: number } | undefined;
    return {
      output: String(live.name),
      width: mode?.width ?? 0,
      height: mode?.height ?? 0,
    };
  } catch {
    return null;
  }
}

// Receiver picker when several are on the LAN — walker dmenu, the same
// surface the portal chooser uses, so cast feels like one interaction style.
async function pickSink(sinks: Sink[], sinkArg?: string): Promise<string> {
  if (sinkArg) return sinkArg;
  if (sinks.length === 0) {
    throw new Error("no Chromecast receivers found — is the TV on and on this network? (cast list)");
  }
  if (sinks.length === 1) return sinks[0].name;

  const input = sinks.map((s) => s.name).join("\n") + "\n";
  let choice: string;
  try {
    const child = new Deno.Command("walker", {
      args: ["--dmenu", "-p", "Cast to:"],
      stdin: "piped",
      stdout: "piped",
      stderr: "inherit",
    }).spawn();
    const writer = child.stdin.getWriter();
    await writer.write(new TextEncoder().encode(input));
    writer.releaseLock();
    await child.stdin.close();
    const { stdout, success } = await child.output();
    choice = new TextDecoder().decode(stdout).trim();
    if (!success && !choice) throw new Error("no receiver selected");
  } catch (err) {
    if (err instanceof Deno.errors.NotFound) {
      throw new Error("several receivers found but walker is not on PATH to pick one — pass the sink name");
    }
    throw err;
  }
  return choice;
}

// ---------------------------------------------------------------------------
// Liveness of the recorded session
// ---------------------------------------------------------------------------

// A sink with a live route carries `session` in Cast.sinksUpdated. Returns
// false when the sink is definitively not casting, true when it is, and null
// when it could not be determined (caller then trusts the state file).
async function sessionLive(sink: string): Promise<boolean | null> {
  try {
    return await withCdp(async (cdp) => {
      await cdp.send("Cast.enable");
      await cdp.waitForSinks(3_000);
      const found = cdp.sinks.find((s) => s.name === sink);
      return found ? found.session != null && found.session !== "" : false;
    });
  } catch {
    return null;
  }
}

async function isCasting(): Promise<boolean> {
  const state = readState();
  if (!state) return false;
  if (!(await casterUp())) return false; // the cast died with the caster
  const live = await sessionLive(state.sink);
  if (live === false) {
    // Route is gone (stopped from the TV side, receiver powered off, caster
    // crashed and restarted into a fresh session-less state).
    clearState();
    return false;
  }
  return true; // verified, or undeterminable — trust the state file
}

// ---------------------------------------------------------------------------
// Commands
// ---------------------------------------------------------------------------

async function cmdList(format: "plain" | "json"): Promise<void> {
  const sinks = await discoverSinks();
  if (format === "json") {
    console.log(JSON.stringify(sinks, null, 2));
  } else {
    if (sinks.length === 0) console.error("cast: no receivers discovered (is the TV on?)");
    for (const sink of sinks) console.log(sink.name);
  }
}

async function cmdStart(mode: "mirror" | "extend", sinkArg?: string, sizeArg?: string): Promise<void> {
  acquireStartLock();
  let resolvedSink: string | undefined;
  if (mode === "extend") {
    // Quiet: cast-extend's own instructions describe the manual Chrome flow
    // this command is replacing.
    await run(CAST_EXTEND, ["on", ...(sizeArg ? [sizeArg] : [])], { quiet: true });
  }
  try {
    const sinks = await discoverSinks();
    const sink = await pickSink(sinks, sinkArg);
    resolvedSink = sink;

    // The portal chooser (cast-portal-chooser) reads this while Chrome's
    // picker chain runs: extend captures the headless TV output, mirror the
    // currently focused screen. No interactive portal menu appears.
    Deno.writeTextFileSync(PICKER_FILE, mode === "extend" ? "headless" : "focused");
    console.error(
      `cast: ${mode === "extend" ? "extending" : "mirroring"} to ${sink} — ${mode === "extend" ? "the TV output" : "the focused screen"} is picked automatically`,
    );

    await withCdp(async (cdp) => {
      await cdp.send("Cast.enable");
      // Resolves once the portal session is up (the pinned choice makes it
      // non-interactive); a portal failure comes back as an error.
      await cdp.send("Cast.startDesktopMirroring", { sinkName: sink }, MIRROR_TIMEOUT_MS);
    });
    saveState({ mode, sink, startedAt: new Date().toISOString() });
  } catch (err) {
    if (mode === "extend") {
      // Don't leave an invisible headless output behind a failed start.
      await run(CAST_EXTEND, ["off"], { quiet: true }).catch(() => {});
    }
    throw err;
  } finally {
    try {
      Deno.removeSync(PICKER_FILE);
    } catch {
      // already gone
    }
    try {
      Deno.removeSync(LOCK_FILE);
    } catch {
      // already gone
    }
  }
  console.log(mode === "extend"
    ? `Extending to ${resolvedSink}. Move windows over with: cast-extend send`
    : `Mirroring to ${resolvedSink}.`);
}

async function cmdStop(sinkArg?: string): Promise<void> {
  const state = readState();
  const sink = sinkArg ?? state?.sink;
  let stopped = false;

  if (sink && await casterUp()) {
    try {
      await withCdp(async (cdp) => {
        // Cast.enable first: without it the handler has no sink list and
        // every stopCasting answers "Sink not found" — leaving a live cast
        // running while the caller believes it stopped.
        await cdp.send("Cast.enable");
        await cdp.waitForSinks(3_000);
        await cdp.send("Cast.stopCasting", { sinkName: sink });
      });
      stopped = true;
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      // No live route on that sink (already stopped from the TV side, or the
      // caster restarted and took the session with it) — nothing to stop.
      if (!/route|not found|no active/i.test(message)) throw err;
    }
  }

  // Headless output goes away on every stop (it exists only to feed a cast):
  // a mirror-mode state or a lost state file must not strand it.
  await run(CAST_EXTEND, ["off"], { quiet: true }).catch(() => {});
  clearState();
  console.log(
    stopped ? `Stopped casting to ${sink}.` : `No active cast${sink ? ` on ${sink}` : ""}.`,
  );
}

async function cmdStatus(asJson: boolean): Promise<void> {
  const casting = await isCasting();
  const state = readState();
  const headless = await headlessOutput();

  let detail: string;
  if (casting && state!.mode === "extend" && headless) {
    detail = `Extending to ${state!.sink} (${headless.output} ${headless.width}x${headless.height})`;
  } else if (casting) {
    detail = state!.mode === "extend"
      ? `Extending to ${state!.sink} (headless output not detected)`
      : `Mirroring to ${state!.sink}`;
  } else if (headless) {
    detail = `Cast output ${headless.output} live, no stream — start with: cast extend`;
  } else if (await casterUp()) {
    detail = "Caster ready — no cast (cast extend | cast start)";
  } else {
    detail = "Caster down — starts on demand (journalctl --user -u cast-caster)";
  }

  const payload = {
    active: casting,
    mode: casting ? state!.mode : null,
    sink: casting ? state!.sink : null,
    caster_up: await casterUp(),
    output: headless?.output ?? "",
    width: headless?.width ?? 0,
    height: headless?.height ?? 0,
    detail,
  };
  console.log(asJson ? JSON.stringify(payload) : detail);
}

async function main(): Promise<void> {
  const args = Deno.args.filter((a) => a !== "--json");
  const asJson = Deno.args.includes("--json");
  const [command, ...rest] = args;

  try {
    switch (command) {
      case "list":
        await cmdList(asJson ? "json" : "plain");
        break;
      case "start":
        await cmdStart("mirror", rest[0]);
        break;
      case "extend":
        await cmdStart("extend", rest.find((a) => !/^\d+x\d+$/.test(a)), rest.find((a) => /^\d+x\d+$/.test(a)));
        break;
      case "stop":
        await cmdStop(rest[0]);
        break;
      case "toggle":
        if (await isCasting()) await cmdStop();
        else await cmdStart("extend");
        break;
      case "status":
        await cmdStatus(asJson);
        break;
      default:
        console.error(`usage: cast {list [--json] | start [sink] | extend [WxH] | stop [sink] | toggle | status [--json]}`);
        Deno.exit(command ? 1 : 0);
    }
  } catch (err) {
    fail(err instanceof Error ? err.message : String(err));
  }
}

await main();
// Explicit exit: cast.ts is done when main() is done. An abandoned WebSocket
// or a stray armed timer must never pin this process open — sway exec, the
// QuickShell chip action, and elephant's menu actions all wait on its exit.
Deno.exit(0);
