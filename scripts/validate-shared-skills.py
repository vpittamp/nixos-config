#!/usr/bin/env python3
"""Validate the repository-owned shared skill inventory without extra packages."""

from __future__ import annotations

import ast
import json
import re
import sys
from pathlib import Path
from urllib.parse import unquote


REPO_ROOT = Path(__file__).resolve().parents[1]
SKILLS_ROOT = REPO_ROOT / "shared-skills"
NAME_RE = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
FRONTMATTER_RE = re.compile(r"^([A-Za-z0-9_-]+):\s*(.+)$")
INTERFACE_RE = re.compile(
    r"^  (display_name|short_description|default_prompt):\s*(.+)$"
)
LINK_RE = re.compile(r"!?\[[^\]]*\]\(([^)]+)\)")
FORBIDDEN_AUXILIARY_FILES = {
    "CHANGELOG.md",
    "INSTALLATION_GUIDE.md",
    "QUICK_REFERENCE.md",
    "README.md",
}


class ValidationError(Exception):
    pass


def fail(path: Path, message: str) -> None:
    raise ValidationError(f"{path.relative_to(REPO_ROOT)}: {message}")


def scalar(path: Path, raw: str) -> str:
    raw = raw.strip()
    if not raw:
        fail(path, "empty scalar")
    if raw.startswith('"'):
        try:
            value = json.loads(raw)
        except json.JSONDecodeError as exc:
            fail(path, f"invalid quoted scalar: {exc}")
        if not isinstance(value, str):
            fail(path, "expected a string scalar")
        return value
    if raw.startswith("'"):
        try:
            value = ast.literal_eval(raw)
        except (SyntaxError, ValueError) as exc:
            fail(path, f"invalid quoted scalar: {exc}")
        if not isinstance(value, str):
            fail(path, "expected a string scalar")
        return value
    return raw


def parse_frontmatter(path: Path) -> tuple[dict[str, str], list[str]]:
    lines = path.read_text(encoding="utf-8").splitlines()
    if not lines or lines[0] != "---":
        fail(path, "SKILL.md must start with YAML frontmatter")
    try:
        end = lines.index("---", 1)
    except ValueError:
        fail(path, "frontmatter has no closing delimiter")

    values: dict[str, str] = {}
    for line_number, line in enumerate(lines[1:end], start=2):
        if not line.strip():
            continue
        match = FRONTMATTER_RE.fullmatch(line)
        if not match:
            fail(path, f"unsupported frontmatter at line {line_number}")
        key, raw = match.groups()
        if key in values:
            fail(path, f"duplicate frontmatter key {key}")
        values[key] = scalar(path, raw)
    return values, lines


def validate_openai_yaml(skill_dir: Path, skill_name: str) -> None:
    path = skill_dir / "agents" / "openai.yaml"
    if not path.is_file():
        fail(path, "missing agents/openai.yaml")

    lines = path.read_text(encoding="utf-8").splitlines()
    if not lines or lines[0] != "interface:":
        fail(path, "must begin with interface:")

    values: dict[str, str] = {}
    for line_number, line in enumerate(lines[1:], start=2):
        match = INTERFACE_RE.fullmatch(line)
        if not match:
            fail(path, f"unsupported metadata at line {line_number}")
        key, raw = match.groups()
        if key in values:
            fail(path, f"duplicate interface key {key}")
        values[key] = scalar(path, raw)

    required = {"display_name", "short_description", "default_prompt"}
    missing = required - values.keys()
    if missing:
        fail(path, f"missing interface keys: {', '.join(sorted(missing))}")
    short_length = len(values["short_description"])
    if not 25 <= short_length <= 64:
        fail(path, "short_description must contain 25-64 characters")
    if f"${skill_name}" not in values["default_prompt"]:
        fail(path, f"default_prompt must mention ${skill_name}")


def validate_links(path: Path) -> None:
    text = path.read_text(encoding="utf-8")
    for raw_target in LINK_RE.findall(text):
        target = raw_target.strip().split(maxsplit=1)[0].strip("<>")
        if not target or target.startswith(("#", "/", "mailto:")):
            continue
        if re.match(r"^[A-Za-z][A-Za-z0-9+.-]*://", target):
            continue
        relative = unquote(target.split("#", 1)[0])
        if relative and not (path.parent / relative).exists():
            fail(path, f"broken relative link: {target}")


def validate_skill(skill_dir: Path) -> int:
    skill_path = skill_dir / "SKILL.md"
    if not skill_path.is_file():
        fail(skill_path, "every shared-skills directory must be a skill")

    values, lines = parse_frontmatter(skill_path)
    if set(values) != {"name", "description"}:
        fail(skill_path, "frontmatter must contain only name and description")
    name = values["name"]
    if name != skill_dir.name:
        fail(skill_path, f"name {name!r} does not match directory {skill_dir.name!r}")
    if len(name) > 64 or not NAME_RE.fullmatch(name):
        fail(skill_path, "name must be <=64 lowercase letters, digits, and hyphens")
    if not values["description"].strip():
        fail(skill_path, "description is empty")
    if len(values["description"]) > 1024:
        fail(skill_path, "description exceeds 1024 characters")
    if len(lines) > 500:
        fail(skill_path, "entry point exceeds the 500-line limit")

    validate_openai_yaml(skill_dir, name)

    for forbidden in FORBIDDEN_AUXILIARY_FILES:
        path = skill_dir / forbidden
        if path.exists():
            fail(path, "move essential content into SKILL.md or a focused resource")

    for path in skill_dir.rglob("*"):
        if not path.is_file():
            continue
        if path.suffix == ".md":
            validate_links(path)
        elif path.suffix == ".json":
            try:
                json.loads(path.read_text(encoding="utf-8"))
            except json.JSONDecodeError as exc:
                fail(path, f"invalid JSON: {exc}")
        elif path.suffix == ".py":
            try:
                ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
            except SyntaxError as exc:
                fail(path, f"invalid Python: {exc}")
    return len(lines)


def main() -> int:
    if not SKILLS_ROOT.is_dir():
        print(f"missing {SKILLS_ROOT}", file=sys.stderr)
        return 1

    skill_dirs = sorted(
        path
        for path in SKILLS_ROOT.iterdir()
        if path.is_dir() and not path.name.startswith(".")
    )
    try:
        total_lines = sum(validate_skill(path) for path in skill_dirs)
    except ValidationError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1

    print(f"validated {len(skill_dirs)} shared skills ({total_lines} SKILL.md lines)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
