#!/usr/bin/env node
'use strict';

const http = require('node:http');
const https = require('node:https');
const crypto = require('node:crypto');
const zlib = require('node:zlib');

function msToNanos(ms) {
  return (Math.max(0, Math.floor(ms)) * 1_000_000).toString();
}

function randomHex(bytes) {
  return crypto.randomBytes(bytes).toString('hex');
}

function getPreview(text, maxLen = 80) {
  if (!text || typeof text !== 'string') return '';
  const clean = text.replace(/[\r\n]+/g, ' ').replace(/\s+/g, ' ').trim();
  if (clean.length <= maxLen) return clean;
  return clean.slice(0, Math.max(0, maxLen - 3)) + '...';
}

function tryParseJson(text) {
  if (!text || typeof text !== 'string') return null;
  const trimmed = text.trim();
  if (!trimmed.startsWith('{') && !trimmed.startsWith('[')) return null;
  try {
    return JSON.parse(trimmed);
  } catch {
    return null;
  }
}

function toSafeString(value) {
  if (value == null) return null;
  if (typeof value === 'string') return value;
  try {
    return JSON.stringify(value);
  } catch {
    return String(value);
  }
}

function parseToolArgs(rawArgs) {
  if (rawArgs == null) return { raw: null, parsed: null };
  if (typeof rawArgs === 'object') return { raw: null, parsed: rawArgs };
  const raw = toSafeString(rawArgs);
  const parsed = raw ? tryParseJson(raw) : null;
  return { raw, parsed };
}

function toolArgsSummary(toolName, parsedArgs, rawArgs) {
  const t = String(toolName || 'tool');
  const a = parsedArgs && typeof parsedArgs === 'object' ? parsedArgs : null;
  const candidates = [
    a && typeof a.command === 'string' ? a.command : null,
    a && typeof a.cmd === 'string' ? a.cmd : null,
    a && typeof a.expression === 'string' ? a.expression : null,
    a && typeof a.path === 'string' ? a.path : null,
    a && typeof a.directory === 'string' ? a.directory : null,
    a && typeof a.dir_path === 'string' ? a.dir_path : null,
    a && typeof a.directory_path === 'string' ? a.directory_path : null,
    a && typeof a.filePath === 'string' ? a.filePath : null,
    a && typeof a.file_path === 'string' ? a.file_path : null,
    a && typeof a.filename === 'string' ? a.filename : null,
    a && typeof a.ref_id === 'string' ? a.ref_id : null,
    a && typeof a.url === 'string' ? a.url : null,
    a && typeof a.q === 'string' ? a.q : null,
    a && typeof a.query === 'string' ? a.query : null,
    a && typeof a.pattern === 'string' ? a.pattern : null,
    a && typeof a.location === 'string' ? a.location : null,
    a && typeof a.ticker === 'string' ? a.ticker : null,
    rawArgs,
  ].filter(Boolean);

  const first = candidates[0];
  if (!first) return null;
  const preview = getPreview(String(first), 80);
  return preview ? `${t} ${preview}` : null;
}

function escapeRegex(s) {
  return String(s || '').replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function getToolSpanName(toolName, rawArgs) {
  const { raw, parsed } = parseToolArgs(rawArgs);
  const summary = toolArgsSummary(toolName, parsed, raw);
  if (!summary) return `Tool: ${toolName}`;
  const detail = summary.replace(new RegExp(`^${escapeRegex(toolName)}\\s*`, 'i'), '');
  return detail ? `Tool: ${toolName} (${detail})` : `Tool: ${toolName}`;
}

function parseShellCommandOutput(output) {
  if (!output || typeof output !== 'string') return { exitCode: null, wallTimeMs: null };
  const exitMatch = output.match(/Exit\\s+code:\\s*(\\d+)/i);
  const wallMatch = output.match(/Wall\\s+time:\\s*(\\d+(?:\\.\\d+)?)\\s*seconds?/i);
  const exitCode = exitMatch ? Number.parseInt(exitMatch[1], 10) : null;
  const wallTimeMs = wallMatch ? Math.round(Number.parseFloat(wallMatch[1]) * 1000) : null;
  return {
    exitCode: Number.isFinite(exitCode) ? exitCode : null,
    wallTimeMs: Number.isFinite(wallTimeMs) ? wallTimeMs : null,
  };
}

function anyValueToJs(value) {
  if (!value || typeof value !== 'object') return null;
  if (Object.prototype.hasOwnProperty.call(value, 'stringValue')) return value.stringValue;
  if (Object.prototype.hasOwnProperty.call(value, 'intValue')) {
    const raw = value.intValue;
    if (typeof raw === 'number' && Number.isFinite(raw)) return raw;
    const n = Number.parseInt(String(raw), 10);
    return Number.isFinite(n) ? n : null;
  }
  if (Object.prototype.hasOwnProperty.call(value, 'doubleValue')) return Number(value.doubleValue);
  if (Object.prototype.hasOwnProperty.call(value, 'boolValue')) return Boolean(value.boolValue);
  if (Object.prototype.hasOwnProperty.call(value, 'arrayValue')) {
    const vs = value.arrayValue && Array.isArray(value.arrayValue.values) ? value.arrayValue.values : [];
    return vs.map(anyValueToJs);
  }
  if (Object.prototype.hasOwnProperty.call(value, 'kvlistValue')) {
    const out = {};
    const vs = value.kvlistValue && Array.isArray(value.kvlistValue.values) ? value.kvlistValue.values : [];
    for (const kv of vs) {
      if (!kv || typeof kv.key !== 'string') continue;
      out[kv.key] = anyValueToJs(kv.value);
    }
    return out;
  }
  if (Object.prototype.hasOwnProperty.call(value, 'bytesValue')) return value.bytesValue;
  return null;
}

function attrFind(attributes, key) {
  if (!Array.isArray(attributes)) return null;
  return attributes.find((a) => a && a.key === key) || null;
}

function attrGet(attributes, key) {
  const a = attrFind(attributes, key);
  return a ? anyValueToJs(a.value) : null;
}

function attrGetString(attributes, key) {
  const a = attrFind(attributes, key);
  if (!a || !a.value) return null;
  if (Object.prototype.hasOwnProperty.call(a.value, 'stringValue')) return a.value.stringValue;
  if (Object.prototype.hasOwnProperty.call(a.value, 'intValue')) return String(a.value.intValue);
  return null;
}

function attrGetInt(attributes, key) {
  const a = attrFind(attributes, key);
  if (!a || !a.value) return null;
  if (Object.prototype.hasOwnProperty.call(a.value, 'intValue')) {
    const v = a.value.intValue;
    return typeof v === 'number' ? v : Number.parseInt(v, 10);
  }
  if (Object.prototype.hasOwnProperty.call(a.value, 'stringValue')) {
    return Number.parseInt(a.value.stringValue, 10) || null;
  }
  return null;
}

function attrUpsert(attributes, key, value) {
  if (!Array.isArray(attributes)) return;
  const existing = attrFind(attributes, key);
  if (existing) {
    existing.value = value;
    return;
  }
  attributes.push({ key, value });
}

function parseIsoToMs(iso) {
  if (!iso || typeof iso !== 'string') return null;
  const ms = Date.parse(iso);
  return Number.isFinite(ms) ? ms : null;
}

function parseDurationMs(value) {
  if (value == null) return null;
  if (typeof value === 'number' && Number.isFinite(value)) return Math.max(0, Math.floor(value));
  if (typeof value === 'string') {
    const n = Number.parseInt(value, 10);
    return Number.isFinite(n) ? Math.max(0, n) : null;
  }
  return null;
}

function readRequestBody(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    req.on('data', (c) => chunks.push(c));
    req.on('end', () => resolve(Buffer.concat(chunks)));
    req.on('error', reject);
  });
}

function maybeGunzip(buf) {
  if (!Buffer.isBuffer(buf) || buf.length < 2) return buf;
  if (buf[0] === 0x1f && buf[1] === 0x8b) {
    try {
      return zlib.gunzipSync(buf);
    } catch {
      return buf;
    }
  }
  return buf;
}

function httpPostJson(urlStr, obj, { timeoutMs = 2000 } = {}) {
  try {
    const data = Buffer.from(JSON.stringify(obj));
    const u = new URL(urlStr);
    const mod = u.protocol === 'https:' ? https : http;
    const req = mod.request(
      {
        hostname: u.hostname,
        port: u.port || (u.protocol === 'https:' ? 443 : 80),
        path: u.pathname + (u.search || ''),
        method: 'POST',
        agent: false,
        headers: {
          'Content-Type': 'application/json',
          'Content-Length': data.length,
        },
      },
      (res) => res.resume()
    );
    req.on('error', () => {});
    req.setTimeout(timeoutMs, () => req.destroy());
    req.end(data);
  } catch {
    // best-effort
  }
}

function jsonOk(res, body = '{}') {
  res.statusCode = 200;
  res.setHeader('Content-Type', 'application/json');
  res.end(body);
}

module.exports = {
  anyValueToJs,
  attrFind,
  attrGet,
  attrGetInt,
  attrGetString,
  attrUpsert,
  escapeRegex,
  getPreview,
  getToolSpanName,
  httpPostJson,
  jsonOk,
  maybeGunzip,
  msToNanos,
  parseDurationMs,
  parseIsoToMs,
  parseShellCommandOutput,
  parseToolArgs,
  randomHex,
  readRequestBody,
  toSafeString,
  toolArgsSummary,
  tryParseJson,
};
