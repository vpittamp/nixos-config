# Kimi WebBridge

Last updated: 2026-07-18

## Purpose

Kimi WebBridge (Moonshot AI) lets local AI agents drive the user's real
Chrome browser: navigate pages, read page structure, click, fill forms, take
screenshots, and evaluate JavaScript — using the browser's existing login
sessions.

## Components

1. Chrome extension
   - Chrome Web Store ID: `fldmhceldgbpfpkbgopacenieobmligc`
   - Auto-connects as a WebSocket client to `ws://127.0.0.1:10086/ws`.
   - No native messaging and no user configuration.
   - Force-installed into all Chrome profiles via managed policy
     (`modules/desktop/chrome-kimi-webbridge.nix`, merged into the single
     ExtensionSettings policy file written by `modules/services/onepassword.nix`).
2. Node daemon (npm package `kimi-webbridge`)
   - Nix-packaged in `packages/kimi-webbridge.nix`.
   - `kimi-webbridge mcp` runs a WebSocket server on `127.0.0.1:10086/ws`
     (accepts the extension connection plus transient CLI client connections)
     and an MCP server on stdio.
   - `kimi-webbridge <action> '<json-args>'` is a one-shot WebSocket client:
     it forwards the tool call to the extension and prints the `tool_result`.

## Local Architecture

- One persistent bridge per host:
  - systemd user service `kimi-webbridge.service`
    (`home-modules/ai-assistants/kimi-webbridge.nix`)
  - runs `tail -f /dev/null | kimi-webbridge mcp` so the stdio MCP transport
    never sees EOF; the useful part is the WebSocket bridge on
    `127.0.0.1:10086/ws`
  - bound to the Sway session (`sway-session.target`)
- The Chrome extension is force-installed by Chrome managed policy and
  auto-connects to the bridge.
- Agents do NOT register a per-agent MCP server for WebBridge. A second
  `kimi-webbridge mcp` process exits on EADDRINUSE (port 10086 is single
  listener), so all agents drive the browser through the one-shot CLI mode
  against the already-running bridge.

## CLI Usage (agent-facing)

```bash
# Open a page in the current tab
kimi-webbridge navigate '{"url":"https://example.com"}'

# Read the page's accessibility/DOM snapshot
kimi-webbridge snapshot '{}'

# Capture a screenshot of the current tab
kimi-webbridge screenshot '{}'

# List open tabs
kimi-webbridge list_tabs '{}'
```

Other actions include `click`, `fill`, and `evaluate`. Each command connects
to `ws://127.0.0.1:10086/ws`, relays the call to the extension, prints the
JSON result, and exits.

## Security

- The Nix package patches upstream `src/mcp.js` so the WebSocket server binds
  `127.0.0.1` only (upstream binds `0.0.0.0`). The patch uses
  `substituteInPlace --replace-fail`, so an upstream change to that line
  fails the build loudly instead of silently widening the bind.
- The bridge drives the user's MAIN Chrome profile with its real login
  sessions. Agents can act on authenticated pages (email, GitHub, internal
  dashboards, etc.). Treat every WebBridge action as an authenticated browser
  action and gate its use accordingly.

## Troubleshooting

```bash
# Service state and logs
systemctl --user status kimi-webbridge.service
journalctl --user -u kimi-webbridge.service -f

# Smoke test: should return a JSON tab list once Chrome + extension are up
kimi-webbridge list_tabs '{}'
```

- If `list_tabs` returns a connection error, the bridge service is not
  running (or Chrome/extension has not connected yet).
- Check the extension is installed and enabled in `chrome://extensions`
  (policy-installed extensions cannot be removed; they show as
  "Installed by your organization").
- The extension connects to exactly one bridge; restarting
  `kimi-webbridge.service` while Chrome is open is safe — the extension
  reconnects.

## References

- Extension policy: `modules/desktop/chrome-kimi-webbridge.nix`
- User service: `home-modules/ai-assistants/kimi-webbridge.nix`
- Package: `packages/kimi-webbridge.nix`
- Extension: Chrome Web Store ID `fldmhceldgbpfpkbgopacenieobmligc`
