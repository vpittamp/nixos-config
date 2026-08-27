#!/usr/bin/env node
/**
 * kimi-webbridge-mcp-stdio — MCP stdio ⇄ Kimi WebBridge WebSocket proxy.
 *
 * The persistent bridge (`kimi-webbridge mcp` under the kimi-webbridge user
 * service) owns ws://127.0.0.1:10086/ws: the Chrome extension connects there
 * as a WebSocket client, and so do the one-shot CLI calls. A second `mcp`
 * process exits(1) on EADDRINUSE, so an agent cannot register `kimi-webbridge
 * mcp` directly while the service is running.
 *
 * This proxy closes that gap: it speaks MCP over stdio to the agent, and for
 * each tool call plays the bridge's one-shot CLI-client role over a transient
 * WebSocket — send `{type:"tool_call", requestId, payload:{name, args}}`,
 * await the matching `{type:"tool_result", responseToRequestId}`. Result
 * shaping mirrors upstream src/mcp.js (screenshot → image content,
 * save_as_pdf → embedded resource).
 *
 * Tool names/schemas mirror upstream kimi-webbridge 0.1.3 TOOL_DEFINITIONS;
 * the bridge itself validates nothing, so this table is the contract both
 * sides work from. Requires Node ≥ 22 (global WebSocket client).
 */

import { randomUUID } from "node:crypto";

const WS_URL = process.env.KIMI_WEBBRIDGE_WS_URL || "ws://127.0.0.1:10086/ws";
const OPEN_TIMEOUT_MS = 5_000;
const TOOL_DEFAULT_TIMEOUT = 30_000;

const str = (description) => ({ type: "string", description });

const TOOL_DEFINITIONS = [
    // ── Navigation ──────────────────────────────────
    {
        name: "navigate",
        description:
            "Open a web page. Navigates the current tab or opens a new one. Use for logging in, searching, or visiting any URL.",
        inputSchema: {
            type: "object",
            properties: {
                url: str("Full URL to open, including protocol (e.g. https://example.com)"),
                newTab: { type: "boolean", description: "Open in a new tab (default false: navigate the current tab)" },
                group_title: str("Optional tab-group name, for organising tabs"),
            },
            required: ["url"],
        },
        timeout: 40_000,
    },
    {
        name: "find_tab",
        description:
            "Find an already-open tab matching a URL and switch to it. Errors when nothing matches; use navigate instead then.",
        inputSchema: {
            type: "object",
            properties: {
                url: str("URL keyword to search for (supports * wildcard)"),
            },
            required: ["url"],
        },
    },
    {
        name: "close_tab",
        description: "Close the current tab.",
        inputSchema: { type: "object", properties: {} },
    },
    {
        name: "list_tabs",
        description: "List all open tabs with URL, title and group info.",
        inputSchema: { type: "object", properties: {} },
    },

    // ── Page content extraction ─────────────────────
    {
        name: "evaluate",
        description:
            "Run JavaScript in the page and get the return value. For extracting data, checking page state, or calling page functions.",
        inputSchema: {
            type: "object",
            properties: {
                code: str("JavaScript code to execute"),
            },
            required: ["code"],
        },
        timeout: 15_000,
    },
    {
        name: "snapshot",
        description:
            "Accessibility-tree snapshot of the current page: every interactive element with role, name, value and hierarchy. The core tool for understanding page content and structure.",
        inputSchema: { type: "object", properties: {} },
        timeout: 15_000,
    },
    {
        name: "network",
        description:
            "Network capture. cmd=start begins capture, stop ends it, list shows captured requests (optional URL filter), detail returns one response body by requestId.",
        inputSchema: {
            type: "object",
            properties: {
                cmd: { type: "string", description: "Operation: start / stop / list / detail", enum: ["start", "stop", "list", "detail"] },
                filter: str("(list only) filter by URL keyword"),
                requestId: str("(detail only) request ID whose body to fetch"),
            },
            required: ["cmd"],
        },
        timeout: 20_000,
    },

    // ── Interaction ─────────────────────────────────
    {
        name: "snapshot_click",
        description:
            "Click a page element by accessibility ref (e.g. @e1, @e2). Take a snapshot first to get refs. Suits buttons, links and other interactive elements.",
        inputSchema: {
            type: "object",
            properties: {
                ref: str("snapshot @e reference (e.g. @e1, @e12)"),
            },
            required: ["ref"],
        },
    },
    {
        name: "click",
        description:
            "Click a page element by CSS selector. When several elements match, only the first is clicked.",
        inputSchema: {
            type: "object",
            properties: {
                selector: str("CSS selector (e.g. #submit-btn, .login-button, button[type='submit'])"),
            },
            required: ["selector"],
        },
    },
    {
        name: "mouse_click",
        description:
            "Simulate a physical mouse click — lower level than click, firing the full mousedown → mouseup sequence. For precise coordinates or unusual elements.",
        inputSchema: {
            type: "object",
            properties: {
                selector: str("CSS selector or @e ref"),
            },
            required: ["selector"],
        },
    },
    {
        name: "fill",
        description:
            "Fill a form field. Supports input, textarea and contentEditable elements; fires input/change events like a real user.",
        inputSchema: {
            type: "object",
            properties: {
                selector: str("CSS selector or @e ref of the field to fill"),
                value: str("Value to enter"),
            },
            required: ["selector", "value"],
        },
    },
    {
        name: "send_keys",
        description:
            "Send keyboard keys. Supports modifier combos (Mod+A, Mod+C) and named keys (Enter, Tab, Escape, ArrowDown). Separate a sequence with spaces.",
        inputSchema: {
            type: "object",
            properties: {
                keys: str("Key sequence, e.g. 'Enter', 'Mod+A', 'Control+C', 'Escape Tab Enter'"),
                repeat: { type: "number", description: "Repeat count (1-100, default 1)" },
            },
            required: ["keys"],
        },
    },
    {
        name: "key_type",
        description: "Type text directly into the page via CDP Input.insertText — for entering content into fields.",
        inputSchema: {
            type: "object",
            properties: {
                text: str("Text to type"),
            },
            required: ["text"],
        },
    },

    // ── Page capture ────────────────────────────────
    {
        name: "screenshot",
        description: "Screenshot the current page — full page or a single element. Returns base64 image data.",
        inputSchema: {
            type: "object",
            properties: {
                format: { type: "string", description: "Image format: png or jpeg (default png)", enum: ["png", "jpeg"] },
                quality: { type: "number", description: "jpeg quality (1-100, default 80; only with format=jpeg)" },
                selector: str("Optional CSS selector or @e ref of the element to capture"),
            },
        },
        timeout: 20_000,
    },
    {
        name: "save_as_pdf",
        description: "Save the current page as PDF. Configurable paper size, scale, background printing.",
        inputSchema: {
            type: "object",
            properties: {
                paper_format: { type: "string", description: "Paper format: letter / legal / a4 / a3 / tabloid (default letter)", enum: ["letter", "legal", "a4", "a3", "tabloid"] },
                scale: { type: "number", description: "Scale 0.1-2.0 (default 1.0)" },
                print_background: { type: "boolean", description: "Print backgrounds (default true)" },
                landscape: { type: "boolean", description: "Landscape orientation (default false)" },
                file_name: str("Suggested file name (informational)"),
            },
        },
        timeout: 30_000,
    },

    // ── Files ───────────────────────────────────────
    {
        name: "upload",
        description: "Upload local files into a page <input type=\"file\"> element.",
        inputSchema: {
            type: "object",
            properties: {
                selector: str("CSS selector of the file input element"),
                files: { type: "array", items: { type: "string" }, description: "Absolute paths of local files to upload" },
            },
            required: ["selector", "files"],
        },
    },
];

const toolDef = (name) => TOOL_DEFINITIONS.find((t) => t.name === name);

// ─── WebSocket bridge client ────────────────────────────

function openWebSocket(url, timeoutMs) {
    return new Promise((resolve, reject) => {
        let ws;
        try {
            ws = new WebSocket(url);
        } catch (err) {
            reject(new Error(`cannot open WebSocket: ${err.message}`));
            return;
        }
        const timer = setTimeout(() => {
            try { ws.close(); } catch { /* already gone */ }
            reject(new Error(`timed out connecting to ${url} — is the kimi-webbridge user service running?`));
        }, timeoutMs);
        ws.addEventListener("open", () => {
            clearTimeout(timer);
            resolve(ws);
        }, { once: true });
        ws.addEventListener("error", (ev) => {
            clearTimeout(timer);
            const detail = ev?.message || ev?.error?.message || "connection refused";
            reject(new Error(`bridge unreachable at ${url} (${detail})`));
        }, { once: true });
    });
}

async function bridgeCall(name, args, timeoutMs) {
    const ws = await openWebSocket(WS_URL, OPEN_TIMEOUT_MS);
    try {
        return await new Promise((resolve, reject) => {
            const requestId = randomUUID();
            const timer = setTimeout(() => {
                cleanup();
                reject(new Error(`tool "${name}" timed out after ${timeoutMs}ms — page may be stuck or unresponsive`));
            }, timeoutMs);

            const onMessage = (ev) => {
                let msg;
                try {
                    msg = JSON.parse(typeof ev.data === "string" ? ev.data : Buffer.from(ev.data).toString("utf8"));
                } catch {
                    return; // not JSON — not ours
                }
                if (msg?.type !== "tool_result" || msg.responseToRequestId !== requestId) return;
                cleanup();
                if (msg.payload?.error) reject(new Error(String(msg.payload.error)));
                else resolve(msg.payload?.data ?? {});
            };
            const onClose = () => {
                cleanup();
                reject(new Error("bridge closed the connection before replying"));
            };
            function cleanup() {
                clearTimeout(timer);
                ws.removeEventListener("message", onMessage);
                ws.removeEventListener("close", onClose);
            }

            ws.addEventListener("message", onMessage);
            ws.addEventListener("close", onClose);
            ws.send(JSON.stringify({ type: "tool_call", requestId, payload: { name, args: args ?? {} } }));
        });
    } finally {
        try { ws.close(); } catch { /* already gone */ }
    }
}

// ─── Result shaping (mirrors upstream src/mcp.js) ───────

function shapeResult(name, data) {
    if (name === "screenshot" && data.data) {
        const mimeType = data.format === "jpeg" ? "image/jpeg" : "image/png";
        const size = (data.dataLength / 1024).toFixed(1);
        return {
            content: [
                { type: "text", text: `Screenshot complete (${size}KB, ${mimeType})` },
                { type: "image", data: data.data, mimeType },
            ],
        };
    }
    if (name === "save_as_pdf" && data.data) {
        const size = (data.dataLength / 1024).toFixed(1);
        return {
            content: [
                {
                    type: "resource",
                    resource: {
                        uri: `data:application/pdf;base64,${data.data}`,
                        mimeType: "application/pdf",
                        text: `PDF generated (${size}KB)${data.pageTitle ? ` — ${data.pageTitle}` : ""}`,
                    },
                },
            ],
        };
    }
    return { content: [{ type: "text", text: JSON.stringify(data, null, 2) }] };
}

async function callTool(name, args) {
    const def = toolDef(name);
    if (!def) {
        return { content: [{ type: "text", text: `Unknown tool: "${name}"` }], isError: true };
    }
    try {
        const timeout = def.timeout ?? TOOL_DEFAULT_TIMEOUT;
        const data = await bridgeCall(name, args, timeout);
        return shapeResult(name, data);
    } catch (err) {
        return { content: [{ type: "text", text: err.message }], isError: true };
    }
}

// ─── MCP stdio plumbing ─────────────────────────────────

const write = (msg) => process.stdout.write(JSON.stringify(msg) + "\n");
const reply = (id, result) => write({ jsonrpc: "2.0", id, result });
const replyError = (id, code, message) => write({ jsonrpc: "2.0", id, error: { code, message } });

async function handleMessage(msg) {
    const { id, method, params } = msg;

    if (method === undefined) return; // malformed; ignore
    if (id === undefined || id === null) return; // notification — nothing to answer

    switch (method) {
        case "initialize":
            reply(id, {
                protocolVersion: params?.protocolVersion ?? "2025-06-18",
                capabilities: { tools: {} },
                serverInfo: { name: "kimi-webbridge", version: "0.1.3" },
            });
            return;
        case "ping":
            reply(id, {});
            return;
        case "tools/list":
            reply(id, {
                tools: TOOL_DEFINITIONS.map(({ name, description, inputSchema }) => ({
                    name, description, inputSchema,
                })),
            });
            return;
        case "tools/call": {
            const { name, arguments: args } = params ?? {};
            if (typeof name !== "string") {
                replyError(id, -32602, "params.name is required");
                return;
            }
            reply(id, await callTool(name, args));
            return;
        }
        default:
            replyError(id, -32601, `Method not found: ${method}`);
    }
}

let buffer = "";
process.stdin.setEncoding("utf8");
process.stdin.on("data", (chunk) => {
    buffer += chunk;
    let newline;
    while ((newline = buffer.indexOf("\n")) >= 0) {
        const line = buffer.slice(0, newline).trim();
        buffer = buffer.slice(newline + 1);
        if (!line) continue;
        let msg;
        try {
            msg = JSON.parse(line);
        } catch (err) {
            console.error(`[mcp-stdio] dropping unparseable message: ${err.message}`);
            continue;
        }
        handleMessage(msg).catch((err) => {
            console.error(`[mcp-stdio] handler error: ${err.message}`);
            if (msg?.id !== undefined && msg?.id !== null) {
                replyError(msg.id, -32603, `Internal error: ${err.message}`);
            }
        });
    }
});
process.stdin.on("end", () => process.exit(0));
process.on("SIGINT", () => process.exit(0));
process.on("SIGTERM", () => process.exit(0));

console.error(`[mcp-stdio] kimi-webbridge MCP stdio proxy → ${WS_URL}`);
