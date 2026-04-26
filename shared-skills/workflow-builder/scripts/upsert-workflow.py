#!/usr/bin/env python3
"""
Upsert a workflow into workflow-builder.

Usage:
    upsert-workflow.py <file.json> [--bff-url URL] [--api-key KEY] [--project-id PID]
    upsert-workflow.py <file.json> --psql                        # direct DB upsert via kubectl exec

Input file shape (matches what the BFF expects, plus the spec column):
    {
      "name": "...",                       # required
      "engineType": "dapr",                # optional, defaults to "dapr"
      "spec": { ...SW 1.0 doc... },        # optional but strongly recommended
      "nodes": [ ... ],                    # required if spec present (keep aligned)
      "edges": [ ... ]                     # required if spec present
    }

Two phases (BFF mode):
    1. POST /api/workflows  with name + nodes + edges + engineType (the BFF stamps userId + projectId)
    2. PUT  /api/workflows/{id}  with spec (POST does NOT write the spec column)

Authentication:
    --api-key, or env WORKFLOW_BUILDER_API_KEY (Bearer "wfb_..."), or env WORKFLOW_BUILDER_COOKIE
    (raw cookie header, e.g. "session=...").

psql fallback (--psql):
    Runs `kubectl -n workflow-builder exec deploy/postgresql -- psql ...`. Requires
    --project-id (NOT NULL since migration 0040). Optionally --user-id; defaults to a
    placeholder which you should update. This path skips connection-ref sync.

Exit codes: 0 = success, 1 = validation/auth error, 2 = transport error.
"""

import argparse
import json
import os
import subprocess
import sys
import uuid
from typing import Any
from urllib import error as urllib_error
from urllib import request as urllib_request


def fail(msg: str, code: int = 1) -> "None":
    print(f"error: {msg}", file=sys.stderr)
    sys.exit(code)


def http_json(method: str, url: str, body: dict | None, headers: dict[str, str]) -> dict:
    data = None
    if body is not None:
        data = json.dumps(body).encode("utf-8")
        headers = {**headers, "Content-Type": "application/json"}
    req = urllib_request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib_request.urlopen(req, timeout=30) as resp:
            raw = resp.read()
            return json.loads(raw) if raw else {}
    except urllib_error.HTTPError as e:
        body_text = e.read().decode("utf-8", errors="replace")
        fail(f"{method} {url} -> HTTP {e.code}: {body_text}", code=2)
    except urllib_error.URLError as e:
        fail(f"{method} {url} -> {e.reason}", code=2)


def auth_headers(api_key: str | None, cookie: str | None) -> dict[str, str]:
    if api_key:
        return {"Authorization": f"Bearer {api_key}"}
    if cookie:
        return {"Cookie": cookie}
    fail(
        "no auth: pass --api-key, set WORKFLOW_BUILDER_API_KEY, or set WORKFLOW_BUILDER_COOKIE",
        code=1,
    )


def upsert_via_bff(payload: dict, args: argparse.Namespace) -> None:
    headers = auth_headers(args.api_key, args.cookie)
    base = args.bff_url.rstrip("/")

    spec = payload.get("spec")
    post_body = {
        "name": payload["name"],
        "engineType": payload.get("engineType", "dapr"),
        "nodes": payload.get("nodes", []),
        "edges": payload.get("edges", []),
    }
    workflow = http_json("POST", f"{base}/api/workflows", post_body, headers)
    wf_id = workflow.get("id")
    if not wf_id:
        fail(f"POST /api/workflows returned no id: {workflow}", code=2)

    if spec is not None:
        put_body = {
            "name": payload["name"],
            "nodes": payload.get("nodes", []),
            "edges": payload.get("edges", []),
            "spec": spec,
        }
        http_json("PUT", f"{base}/api/workflows/{wf_id}", put_body, headers)

    canvas_url = f"{base}/workflows/{wf_id}"
    print(json.dumps({"id": wf_id, "canvasUrl": canvas_url, "specWritten": spec is not None}, indent=2))


def upsert_via_psql(payload: dict, args: argparse.Namespace) -> None:
    if not args.project_id:
        fail("--project-id is required with --psql (workflows.project_id is NOT NULL since migration 0040)", code=1)
    user_id = args.user_id or "REPLACE_WITH_REAL_USER_ID"
    wf_id = payload.get("id") or f"wf_{uuid.uuid4().hex[:24]}"

    sql = """
    INSERT INTO workflows (id, name, nodes, edges, engine_type, user_id, project_id, spec)
    VALUES ($wf_id$, $name$, $nodes$::jsonb, $edges$::jsonb, $engine$, $user_id$, $project_id$, $spec$::jsonb)
    ON CONFLICT (id) DO UPDATE SET
      name       = EXCLUDED.name,
      nodes      = EXCLUDED.nodes,
      edges      = EXCLUDED.edges,
      engine_type = EXCLUDED.engine_type,
      project_id = EXCLUDED.project_id,
      spec       = EXCLUDED.spec,
      updated_at = now()
    RETURNING id;
    """
    placeholders = {
        "wf_id": wf_id,
        "name": payload["name"],
        "nodes": json.dumps(payload.get("nodes", [])),
        "edges": json.dumps(payload.get("edges", [])),
        "engine": payload.get("engineType", "dapr"),
        "user_id": user_id,
        "project_id": args.project_id,
        "spec": json.dumps(payload.get("spec", {})),
    }
    rendered = sql
    for key, value in placeholders.items():
        rendered = rendered.replace(f"${key}$", value.replace("'", "''"))

    cmd = [
        "kubectl", "-n", "workflow-builder", "exec", "deploy/postgresql", "--",
        "psql", "-U", "postgres", "-d", "workflow_builder", "-v", "ON_ERROR_STOP=1",
        "-c", rendered,
    ]
    try:
        out = subprocess.run(cmd, capture_output=True, text=True, check=True, timeout=60)
    except subprocess.CalledProcessError as e:
        fail(f"psql failed: {e.stderr.strip()}", code=2)
    except FileNotFoundError:
        fail("kubectl not found on PATH", code=1)

    print(json.dumps({"id": wf_id, "psqlOutput": out.stdout.strip()}, indent=2))


def main() -> None:
    parser = argparse.ArgumentParser(description="Upsert a workflow into workflow-builder")
    parser.add_argument("file", help="Workflow JSON file (see header for shape)")
    parser.add_argument("--bff-url", default=os.getenv("WORKFLOW_BUILDER_URL", "http://workflow-builder.cnoe.localtest.me:3000"))
    parser.add_argument("--api-key", default=os.getenv("WORKFLOW_BUILDER_API_KEY"))
    parser.add_argument("--cookie", default=os.getenv("WORKFLOW_BUILDER_COOKIE"))
    parser.add_argument("--psql", action="store_true", help="Bypass BFF and INSERT/UPSERT directly via kubectl exec psql")
    parser.add_argument("--project-id", default=os.getenv("WORKFLOW_BUILDER_PROJECT_ID"), help="Required with --psql")
    parser.add_argument("--user-id", default=os.getenv("WORKFLOW_BUILDER_USER_ID"), help="Optional with --psql")
    args = parser.parse_args()

    try:
        with open(args.file) as fh:
            payload = json.load(fh)
    except FileNotFoundError:
        fail(f"file not found: {args.file}")
    except json.JSONDecodeError as e:
        fail(f"invalid JSON in {args.file}: {e}")

    if not isinstance(payload, dict) or not payload.get("name"):
        fail("payload must be a JSON object with a non-empty 'name'")

    if args.psql:
        upsert_via_psql(payload, args)
    else:
        upsert_via_bff(payload, args)


if __name__ == "__main__":
    main()
