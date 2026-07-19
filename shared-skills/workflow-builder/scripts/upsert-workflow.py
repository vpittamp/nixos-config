#!/usr/bin/env python3
"""Create or update a workflow through Workflow Builder's BFF application API.

The input is a full workflow JSON object. `engineType` defaults to
`dynamic-script`. When `id` is present, the helper updates that scoped workflow
with PUT; otherwise it creates one with POST. POST accepts `spec` directly.

Authentication is a Workflow Builder access JWT or login cookie. Workspace
`wfb_...` API keys belong to Workflow MCP and do not authenticate these BFF
routes. There is intentionally no direct-Postgres fallback.
"""

import argparse
import json
import os
import sys
from urllib import error as urllib_error
from urllib import request as urllib_request


def fail(msg: str, code: int = 1) -> "None":
    print(f"error: {msg}", file=sys.stderr)
    sys.exit(code)


def http_json(
    method: str,
    url: str,
    body: dict | None,
    headers: dict[str, str],
) -> dict:
    request_headers = {**headers, "Content-Type": "application/json"}
    req = urllib_request.Request(
        url,
        data=json.dumps(body).encode("utf-8") if body is not None else None,
        headers=request_headers,
        method=method,
    )
    try:
        with urllib_request.urlopen(req, timeout=30) as resp:
            raw = resp.read()
            return json.loads(raw) if raw else {}
    except urllib_error.HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")
        fail(f"{method} {url} -> HTTP {exc.code}: {detail}", code=2)
    except urllib_error.URLError as exc:
        fail(f"{method} {url} -> {exc.reason}", code=2)


def auth_headers(access_token: str | None, cookie: str | None) -> dict[str, str]:
    if access_token:
        if access_token.startswith("wfb_"):
            fail("wfb_ workspace keys authenticate Workflow MCP, not BFF workflow routes")
        return {"Authorization": f"Bearer {access_token}"}
    if cookie:
        return {"Cookie": cookie}
    fail(
        "no BFF login auth: pass --access-token, set WORKFLOW_BUILDER_ACCESS_TOKEN, "
        "or set WORKFLOW_BUILDER_COOKIE",
    )


def save_via_api(payload: dict, args: argparse.Namespace) -> None:
    headers = auth_headers(args.access_token, args.cookie)
    base = args.bff_url.rstrip("/")
    workflow_id = payload.get("id")

    if workflow_id:
        existing = http_json("GET", f"{base}/api/workflows/{workflow_id}", None, headers)
        if existing.get("engineType") != "dynamic-script":
            fail(
                "refusing to PUT a dynamic-script spec into a non-dynamic workflow; "
                "use the application's explicit conversion flow",
                code=2,
            )
        body = {"name": payload["name"], "spec": payload["spec"]}
        if "nodes" in payload:
            body["nodes"] = payload["nodes"]
        if "edges" in payload:
            body["edges"] = payload["edges"]
        method = "PUT"
        url = f"{base}/api/workflows/{workflow_id}"
    else:
        body = {
            "name": payload["name"],
            "engineType": payload.get("engineType", "dynamic-script"),
            "nodes": payload.get("nodes", []),
            "edges": payload.get("edges", []),
            "spec": payload["spec"],
        }
        method = "POST"
        url = f"{base}/api/workflows"

    workflow = http_json(method, url, body, headers)
    saved_id = workflow.get("id") or workflow_id
    if not saved_id:
        fail(f"{method} returned no workflow id: {workflow}", code=2)

    print(
        json.dumps(
            {
                "id": saved_id,
                "operation": "updated" if workflow_id else "created",
                "canvasUrlHint": (
                    f"{base}/workspaces/<workspace-slug>/workflows/{saved_id}"
                ),
            },
            indent=2,
        )
    )


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Create or update a workflow through Workflow Builder's BFF",
    )
    parser.add_argument("file", help="Full workflow JSON definition")
    parser.add_argument(
        "--bff-url",
        default=os.getenv(
            "WORKFLOW_BUILDER_URL",
            "https://workflow-builder-dev.tail286401.ts.net",
        ),
    )
    parser.add_argument(
        "--access-token",
        default=os.getenv("WORKFLOW_BUILDER_ACCESS_TOKEN"),
        help="Workflow Builder access JWT (not a wfb_ Workflow MCP key)",
    )
    parser.add_argument(
        "--cookie",
        default=os.getenv("WORKFLOW_BUILDER_COOKIE"),
        help="Raw login Cookie header",
    )
    args = parser.parse_args()

    try:
        with open(args.file, encoding="utf-8") as handle:
            payload = json.load(handle)
    except FileNotFoundError:
        fail(f"file not found: {args.file}")
    except json.JSONDecodeError as exc:
        fail(f"invalid JSON in {args.file}: {exc}")

    if not isinstance(payload, dict) or not payload.get("name"):
        fail("payload must be a JSON object with a non-empty name")
    if not isinstance(payload.get("spec"), dict):
        fail("payload must include a spec object")

    save_via_api(payload, args)


if __name__ == "__main__":
    main()
