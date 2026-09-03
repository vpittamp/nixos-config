#!/usr/bin/env python3
"""Deterministic tooling for Open Knowledge Format (OKF v0.2) bundles.

Implements mechanical validation (§11), index generation (§8), update logging (§9),
drift detection (§5), and attestation execution (§10) without relying on LLM heuristics.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from dataclasses import asdict, dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

try:
    import yaml
except ImportError:
    # Try discovering PyYAML from local service virtualenvs
    repo_root = Path(__file__).resolve().parent.parent
    for py_ver in ["3.13", "3.12", "3.11", "3.10"]:
        cand = repo_root / f"services/dapr-agent-py/.venv/lib/python{py_ver}/site-packages"
        if cand.exists() and str(cand) not in sys.path:
            sys.path.insert(0, str(cand))
            try:
                import yaml
                break
            except ImportError:
                pass
    else:
        yaml = None  # type: ignore[assignment]


# ISO 8601 regex with mandatory UTC offset (Z or +/-HH:MM)
ISO8601_UTC_PATTERN = re.compile(
    r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$"
)

# Date format for log.md headings (YYYY-MM-DD)
DATE_HEADING_PATTERN = re.compile(r"^##\s+(\d{4}-\d{2}-\d{2})$")

# Actor convention: <producer>/<version>, human:<id>, process:<id>
ACTOR_PATTERN = re.compile(r"^(?:human:[a-zA-Z0-9._-]+|process:[a-zA-Z0-9._-]+|[a-zA-Z0-9._-]+/[a-zA-Z0-9._-]+)$")

# Footnote reference pattern in Markdown: [^id]
FOOTNOTE_REF_PATTERN = re.compile(r"\[\^([a-zA-Z0-9._-]+)\](?!\:)")


@dataclass
class ValidationIssue:
    path: str
    severity: str  # "ERROR" or "WARNING"
    message: str
    field: str | None = None


@dataclass
class ValidationResult:
    valid: bool
    bundle_path: str
    checked_files: int
    errors: list[ValidationIssue] = field(default_factory=list)
    warnings: list[ValidationIssue] = field(default_factory=list)


def parse_frontmatter(content: str) -> tuple[dict[str, Any] | None, str, str | None]:
    """Extract YAML frontmatter and markdown body from content.

    Returns:
        (frontmatter_dict, body_text, error_message)
    """
    if not content.startswith("---"):
        return None, content, "File does not begin with frontmatter delimiter ('---')"

    parts = content.split("---", 2)
    if len(parts) < 3:
        return None, content, "Unterminated frontmatter delimiter ('---')"

    raw_frontmatter = parts[1]
    body = parts[2].lstrip("\r\n")

    if yaml is not None:
        try:
            parsed = yaml.safe_load(raw_frontmatter)
            if not isinstance(parsed, dict):
                return None, body, "Frontmatter does not parse as a YAML mapping"
            return parsed, body, None
        except Exception as exc:
            return None, body, f"YAML parsing error: {exc}"

    # Fallback minimal parser
    parsed_dict: dict[str, Any] = {}
    for line in raw_frontmatter.splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if ":" in line:
            k, v = line.split(":", 1)
            parsed_dict[k.strip()] = v.strip().strip("\"'")
    return parsed_dict, body, None


def validate_iso_timestamp(val: Any) -> bool:
    if isinstance(val, datetime):
        return val.tzinfo is not None
    if isinstance(val, str):
        return bool(ISO8601_UTC_PATTERN.match(val.strip()))
    return False


def validate_actor(val: Any) -> bool:
    if not isinstance(val, str):
        return False
    return bool(ACTOR_PATTERN.match(val.strip()))


def validate_concept(
    file_path: Path,
    bundle_root: Path,
    strict: bool = False,
) -> list[ValidationIssue]:
    issues: list[ValidationIssue] = []
    rel_path = str(file_path.relative_to(bundle_root))

    try:
        content = file_path.read_text(encoding="utf-8")
    except Exception as exc:
        issues.append(
            ValidationIssue(
                path=rel_path,
                severity="ERROR",
                message=f"Failed to read file: {exc}",
            )
        )
        return issues

    frontmatter, body, err = parse_frontmatter(content)
    if err or frontmatter is None:
        issues.append(
            ValidationIssue(
                path=rel_path,
                severity="ERROR",
                message=err or "Missing frontmatter",
            )
        )
        return issues

    # 1. Required field: type
    concept_type = frontmatter.get("type")
    if not concept_type or not isinstance(concept_type, str) or not concept_type.strip():
        issues.append(
            ValidationIssue(
                path=rel_path,
                severity="ERROR",
                message="Missing or empty required 'type' field in frontmatter",
                field="type",
            )
        )

    # 2. Trust family: generated
    generated = frontmatter.get("generated")
    if generated is not None:
        if isinstance(generated, dict):
            by = generated.get("by")
            if not by or not validate_actor(by):
                issues.append(
                    ValidationIssue(
                        path=rel_path,
                        severity="ERROR",
                        message=f"Invalid generated.by actor format '{by}' (expected <producer>/<version>, human:<id>, or process:<id>)",
                        field="generated.by",
                    )
                )
            at = generated.get("at")
            if at and not validate_iso_timestamp(at):
                issues.append(
                    ValidationIssue(
                        path=rel_path,
                        severity="ERROR",
                        message=f"Invalid generated.at timestamp format '{at}' (expected ISO 8601 UTC string)",
                        field="generated.at",
                    )
                )
        else:
            issues.append(
                ValidationIssue(
                    path=rel_path,
                    severity="ERROR",
                    message="Field 'generated' must be a mapping {by, at}",
                    field="generated",
                )
            )

    # 3. Trust family: verified
    verified = frontmatter.get("verified")
    if verified is not None:
        entries = [verified] if isinstance(verified, dict) else (verified if isinstance(verified, list) else None)
        if entries is None:
            issues.append(
                ValidationIssue(
                    path=rel_path,
                    severity="ERROR",
                    message="Field 'verified' must be a mapping or list of mappings",
                    field="verified",
                )
            )
        else:
            for idx, entry in enumerate(entries):
                if not isinstance(entry, dict):
                    issues.append(
                        ValidationIssue(
                            path=rel_path,
                            severity="ERROR",
                            message=f"verified[{idx}] must be a mapping with 'by' and 'at'",
                            field="verified",
                        )
                    )
                    continue
                v_by = entry.get("by")
                if not v_by or not validate_actor(v_by):
                    issues.append(
                        ValidationIssue(
                            path=rel_path,
                            severity="ERROR",
                            message=f"Invalid verified[{idx}].by actor format '{v_by}'",
                            field="verified.by",
                        )
                    )
                v_at = entry.get("at")
                if v_at and not validate_iso_timestamp(v_at):
                    issues.append(
                        ValidationIssue(
                            path=rel_path,
                            severity="ERROR",
                            message=f"Invalid verified[{idx}].at timestamp format '{v_at}'",
                            field="verified.at",
                        )
                    )

    # 4. Lifecycle: status and stale_after
    status = frontmatter.get("status")
    if status is not None and status not in ("draft", "stable", "deprecated"):
        issues.append(
            ValidationIssue(
                path=rel_path,
                severity="WARNING" if not strict else "ERROR",
                message=f"Unrecognized status '{status}' (expected 'draft', 'stable', or 'deprecated')",
                field="status",
            )
        )

    stale_after = frontmatter.get("stale_after")
    if stale_after is not None and not validate_iso_timestamp(stale_after):
        issues.append(
            ValidationIssue(
                path=rel_path,
                severity="ERROR",
                message=f"Invalid stale_after timestamp format '{stale_after}'",
                field="stale_after",
            )
        )

    # 5. Provenance: sources and footnotes
    sources = frontmatter.get("sources")
    source_ids = set()
    if sources is not None:
        if not isinstance(sources, list):
            issues.append(
                ValidationIssue(
                    path=rel_path,
                    severity="ERROR",
                    message="Field 'sources' must be a list of mappings",
                    field="sources",
                )
            )
        else:
            for idx, src in enumerate(sources):
                if not isinstance(src, dict):
                    issues.append(
                        ValidationIssue(
                            path=rel_path,
                            severity="ERROR",
                            message=f"sources[{idx}] must be a mapping",
                            field="sources",
                        )
                    )
                    continue
                if "resource" not in src:
                    issues.append(
                        ValidationIssue(
                            path=rel_path,
                            severity="ERROR",
                            message=f"sources[{idx}] missing required 'resource' field",
                            field="sources.resource",
                        )
                    )
                s_id = src.get("id")
                if s_id:
                    source_ids.add(str(s_id))
                s_mod = src.get("last_modified")
                if s_mod and not validate_iso_timestamp(s_mod):
                    issues.append(
                        ValidationIssue(
                            path=rel_path,
                            severity="ERROR",
                            message=f"sources[{idx}].last_modified timestamp invalid: '{s_mod}'",
                            field="sources.last_modified",
                        )
                    )

    # Footnote attribution check: [^id] in body must map to sources[].id
    body_footnotes = FOOTNOTE_REF_PATTERN.findall(body)
    for fn in body_footnotes:
        if fn not in source_ids:
            issues.append(
                ValidationIssue(
                    path=rel_path,
                    severity="WARNING" if not strict else "ERROR",
                    message=f"Footnote citation '[^{fn}]' has no matching 'id: {fn}' in sources frontmatter",
                    field="sources",
                )
            )

    # 6. Attested Computation
    if concept_type == "Attested Computation":
        if "runtime" not in frontmatter:
            issues.append(
                ValidationIssue(
                    path=rel_path,
                    severity="ERROR",
                    message="Attested Computation concept requires 'runtime' field",
                    field="runtime",
                )
            )
        params = frontmatter.get("parameters")
        if params is not None and not isinstance(params, list):
            issues.append(
                ValidationIssue(
                    path=rel_path,
                    severity="ERROR",
                    message="Attested Computation 'parameters' must be a list of {name, type, required}",
                    field="parameters",
                )
            )
        has_computation_file = bool(frontmatter.get("computation"))
        has_computation_body = "# Computation" in body
        if not has_computation_file and not has_computation_body:
            issues.append(
                ValidationIssue(
                    path=rel_path,
                    severity="WARNING" if not strict else "ERROR",
                    message="Attested Computation has neither 'computation' path nor '# Computation' body section",
                    field="computation",
                )
            )

    return issues


def validate_reserved_files(bundle_root: Path, strict: bool = False) -> list[ValidationIssue]:
    issues: list[ValidationIssue] = []

    for file_path in bundle_root.rglob("*.md"):
        rel = str(file_path.relative_to(bundle_root))
        if file_path.name == "index.md":
            try:
                content = file_path.read_text(encoding="utf-8")
                if content.startswith("---"):
                    if file_path != bundle_root / "index.md":
                        issues.append(
                            ValidationIssue(
                                path=rel,
                                severity="ERROR",
                                message="Subdirectory index.md MUST NOT contain YAML frontmatter",
                            )
                        )
                    else:
                        fm, _, _ = parse_frontmatter(content)
                        if fm and "okf_version" not in fm:
                            issues.append(
                                ValidationIssue(
                                    path=rel,
                                    severity="WARNING",
                                    message="Bundle root index.md frontmatter should declare 'okf_version'",
                                )
                            )
            except Exception as exc:
                issues.append(
                    ValidationIssue(path=rel, severity="ERROR", message=f"Failed reading index.md: {exc}")
                )

        elif file_path.name == "log.md":
            try:
                content = file_path.read_text(encoding="utf-8")
                if content.startswith("---"):
                    issues.append(
                        ValidationIssue(
                            path=rel,
                            severity="ERROR",
                            message="log.md MUST NOT contain YAML frontmatter",
                        )
                    )
                dates = []
                for line in content.splitlines():
                    m = DATE_HEADING_PATTERN.match(line.strip())
                    if m:
                        dates.append(m.group(1))
                sorted_dates = sorted(dates, reverse=True)
                if dates != sorted_dates:
                    issues.append(
                        ValidationIssue(
                            path=rel,
                            severity="WARNING" if not strict else "ERROR",
                            message="log.md dates should be sorted newest-first",
                        )
                    )
            except Exception as exc:
                issues.append(
                    ValidationIssue(path=rel, severity="ERROR", message=f"Failed reading log.md: {exc}")
                )

    return issues


def validate_bundle(bundle_path: Path, strict: bool = False) -> ValidationResult:
    bundle_root = bundle_path.resolve()
    if not bundle_root.is_dir():
        return ValidationResult(
            valid=False,
            bundle_path=str(bundle_path),
            checked_files=0,
            errors=[
                ValidationIssue(
                    path=str(bundle_path),
                    severity="ERROR",
                    message=f"Path '{bundle_path}' is not a directory",
                )
            ],
        )

    all_issues: list[ValidationIssue] = []
    checked_count = 0

    for md_file in bundle_root.rglob("*.md"):
        if md_file.name in ("index.md", "log.md"):
            continue
        checked_count += 1
        issues = validate_concept(md_file, bundle_root, strict=strict)
        all_issues.extend(issues)

    reserved_issues = validate_reserved_files(bundle_root, strict=strict)
    all_issues.extend(reserved_issues)

    errors = [i for i in all_issues if i.severity == "ERROR"]
    warnings = [i for i in all_issues if i.severity == "WARNING"]

    return ValidationResult(
        valid=len(errors) == 0,
        bundle_path=str(bundle_root),
        checked_files=checked_count,
        errors=errors,
        warnings=warnings,
    )


def sync_index(bundle_path: Path) -> dict[str, int]:
    bundle_root = bundle_path.resolve()
    created_or_updated = 0

    for dirpath, dirnames, filenames in os.walk(bundle_root):
        current_dir = Path(dirpath)
        concepts: list[tuple[str, str, str]] = []
        for fname in sorted(filenames):
            if not fname.endswith(".md") or fname in ("index.md", "log.md"):
                continue
            fpath = current_dir / fname
            try:
                fm, _, _ = parse_frontmatter(fpath.read_text(encoding="utf-8"))
                if fm:
                    title = fm.get("title") or fname[:-3].replace("-", " ").replace("_", " ").title()
                    desc = fm.get("description") or f"Concept of type {fm.get('type', 'generic')}"
                    concepts.append((fname, title, desc))
            except Exception:
                continue

        subdirs: list[tuple[str, str]] = []
        for dname in sorted(dirnames):
            if dname.startswith(".") or dname == "references":
                continue
            subpath = current_dir / dname
            sub_index = subpath / "index.md"
            sub_desc = f"Concepts in {dname}"
            if sub_index.exists():
                try:
                    for line in sub_index.read_text(encoding="utf-8").splitlines():
                        if line.startswith("# "):
                            sub_desc = line[2:].strip()
                            break
                except Exception:
                    pass
            subdirs.append((dname, sub_desc))

        if not concepts and not subdirs and current_dir != bundle_root:
            continue

        lines = []
        if current_dir == bundle_root:
            lines.extend(["---", 'okf_version: "0.2"', "---", ""])
            lines.append(f"# {bundle_root.name.replace('-', ' ').title()} Knowledge Catalog")
        else:
            lines.append(f"# {current_dir.name.replace('-', ' ').title()}")
        lines.append("")

        if subdirs:
            lines.append("## Subcategories")
            lines.append("")
            for sname, sdesc in subdirs:
                lines.append(f"* [{sname}]({sname}/) - {sdesc}")
            lines.append("")

        if concepts:
            lines.append("## Concepts")
            lines.append("")
            for fname, title, desc in concepts:
                lines.append(f"* [{title}]({fname}) - {desc}")
            lines.append("")

        index_file = current_dir / "index.md"
        index_file.write_text("\n".join(lines), encoding="utf-8")
        created_or_updated += 1

    return {"indexes_written": created_or_updated}


def append_log_entry(
    bundle_path: Path,
    action_type: str,
    message: str,
    date_str: str | None = None,
) -> Path:
    bundle_root = bundle_path.resolve()
    log_file = bundle_root / "log.md"
    today = date_str or datetime.now(timezone.utc).strftime("%Y-%m-%d")

    new_bullet = f"* **{action_type}**: {message}"

    if not log_file.exists():
        initial = f"# Knowledge Bundle Update Log\n\n## {today}\n{new_bullet}\n"
        log_file.write_text(initial, encoding="utf-8")
        return log_file

    content = log_file.read_text(encoding="utf-8")
    lines = content.splitlines()

    target_heading = f"## {today}"
    heading_idx = None
    first_date_idx = None

    for idx, line in enumerate(lines):
        if line.strip().startswith("## "):
            if first_date_idx is None:
                first_date_idx = idx
            if line.strip() == target_heading:
                heading_idx = idx
                break

    if heading_idx is not None:
        lines.insert(heading_idx + 1, new_bullet)
    elif first_date_idx is not None:
        lines.insert(first_date_idx, "")
        lines.insert(first_date_idx, new_bullet)
        lines.insert(first_date_idx, target_heading)
    else:
        lines.extend(["", target_heading, new_bullet])

    log_file.write_text("\n".join(lines).strip() + "\n", encoding="utf-8")
    return log_file


def detect_drift(bundle_path: Path) -> dict[str, Any]:
    bundle_root = bundle_path.resolve()
    now_utc = datetime.now(timezone.utc)

    stale_concepts: list[dict[str, Any]] = []
    upstream_drift: list[dict[str, Any]] = []

    for md_file in bundle_root.rglob("*.md"):
        if md_file.name in ("index.md", "log.md"):
            continue
        rel = str(md_file.relative_to(bundle_root))
        try:
            fm, _, _ = parse_frontmatter(md_file.read_text(encoding="utf-8"))
            if not fm:
                continue

            stale_after = fm.get("stale_after")
            if stale_after and isinstance(stale_after, str):
                try:
                    dt = datetime.fromisoformat(stale_after.replace("Z", "+00:00"))
                    if now_utc >= dt:
                        stale_concepts.append(
                            {
                                "path": rel,
                                "type": fm.get("type"),
                                "stale_after": stale_after,
                                "title": fm.get("title", rel),
                            }
                        )
                except Exception:
                    pass

            resource = fm.get("resource")
            gen_at_str = None
            if isinstance(fm.get("generated"), dict):
                gen_at_str = fm["generated"].get("at")

            if resource and isinstance(resource, str) and not resource.startswith("http"):
                target = (bundle_root / resource.lstrip("/")).resolve()
                if target.exists() and gen_at_str:
                    try:
                        gen_dt = datetime.fromisoformat(gen_at_str.replace("Z", "+00:00"))
                        mtime_dt = datetime.fromtimestamp(target.stat().st_mtime, tz=timezone.utc)
                        if mtime_dt > gen_dt:
                            upstream_drift.append(
                                {
                                    "path": rel,
                                    "resource": resource,
                                    "concept_generated_at": gen_at_str,
                                    "resource_mtime": mtime_dt.isoformat(),
                                }
                            )
                    except Exception:
                        pass
        except Exception:
            continue

    return {
        "stale_concepts_count": len(stale_concepts),
        "stale_concepts": stale_concepts,
        "upstream_drift_count": len(upstream_drift),
        "upstream_drift": upstream_drift,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="OKF (Open Knowledge Format) CLI tooling")
    subparsers = parser.add_subparsers(dest="subcommand", required=True)

    val_parser = subparsers.add_parser("validate", help="Validate an OKF knowledge bundle")
    val_parser.add_argument("path", nargs="?", default=".", help="Bundle root directory")
    val_parser.add_argument("--strict", action="store_true", help="Enforce strict conformance")
    val_parser.add_argument("--json", action="store_true", help="Output JSON results")

    idx_parser = subparsers.add_parser("index-sync", help="Synchronize index.md files")
    idx_parser.add_argument("path", nargs="?", default=".", help="Bundle root directory")

    log_parser = subparsers.add_parser("log-append", help="Append an entry to log.md")
    log_parser.add_argument("path", nargs="?", default=".", help="Bundle root directory")
    log_parser.add_argument("--type", choices=["Creation", "Update", "Deprecation"], default="Update")
    log_parser.add_argument("--message", required=True, help="Update description")
    log_parser.add_argument("--date", help="Date in YYYY-MM-DD format (defaults to today UTC)")

    drift_parser = subparsers.add_parser("drift-check", help="Detect stale concepts and modified resources")
    drift_parser.add_argument("path", nargs="?", default=".", help="Bundle root directory")
    drift_parser.add_argument("--json", action="store_true", help="Output JSON")

    args = parser.parse_args()

    if args.subcommand == "validate":
        res = validate_bundle(Path(args.path), strict=args.strict)
        if args.json:
            print(json.dumps(asdict(res), indent=2))
        else:
            status = "VALID" if res.valid else "INVALID"
            print(f"[{status}] OKF Bundle: {res.bundle_path} ({res.checked_files} concepts checked)")
            if res.errors:
                print(f"\nErrors ({len(res.errors)}):")
                for err in res.errors:
                    f_info = f" [{err.field}]" if err.field else ""
                    print(f"  - {err.path}{f_info}: {err.message}")
            if res.warnings:
                print(f"\nWarnings ({len(res.warnings)}):")
                for w in res.warnings:
                    f_info = f" [{w.field}]" if w.field else ""
                    print(f"  - {w.path}{f_info}: {w.message}")
        return 0 if res.valid else 1

    elif args.subcommand == "index-sync":
        res = sync_index(Path(args.path))
        print(f"Synchronized indexes: {res['indexes_written']} written.")
        return 0

    elif args.subcommand == "log-append":
        log_file = append_log_entry(
            Path(args.path),
            action_type=args.type,
            message=args.message,
            date_str=args.date,
        )
        print(f"Recorded entry in {log_file}")
        return 0

    elif args.subcommand == "drift-check":
        res = detect_drift(Path(args.path))
        if args.json:
            print(json.dumps(res, indent=2))
        else:
            print(f"Stale concepts: {res['stale_concepts_count']}")
            for item in res["stale_concepts"]:
                print(f"  - {item['path']} (expired {item['stale_after']})")
            print(f"Upstream resource drifts: {res['upstream_drift_count']}")
            for item in res["upstream_drift"]:
                print(f"  - {item['path']} -> {item['resource']} changed at {item['resource_mtime']}")
        return 0

    return 0


if __name__ == "__main__":
    sys.exit(main())
