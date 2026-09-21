#!/usr/bin/env python3
"""What each AI agent session actually wants, judged from its terminal screen.

herdr already reports `agent_status` — working, blocked, done, idle. That enum
answers "is it running", but the question a person with nine sessions and half
their attention is really asking is "does this need me, and can it wait". Those
are different, and the gap between them is where the expensive failures live:

  - `blocked` covers both "may I run npm install?" (one keystroke) and "should I
    drop legacy_token or fix the two cron jobs?" (reload the whole task).
  - `done` covers both "here is your feature" and "I gave up".
  - `working` covers an agent making progress AND one that has run the same
    failing test three times in thirty-four minutes.

So one request carries a battery of questions over the pane's own screen:

  progress       losing ground / circling / grinding / advancing
  understanding  guessing / hunting / diagnosed
  repeating      is it redoing something it already did
  frustration    do its own words admit it has lost the thread
  needs_input    is it missing something only the user can give
  ask_kind       what it is waiting for, as a closed set
  risky          is something irreversible in play
  drifted        has it ANNOUNCED work beyond the task in its title

`ask_kind` and the progress dimensions are deliberately orthogonal: an agent
going in circles wants nothing from you, which is exactly why a status enum
cannot catch it.

Nothing here asks for a prediction. "Will it keep struggling" is a trajectory,
and no single screen contains one — so each observation is appended to a short
per-pane history and the trend is computed in code. One bad observation is
ordinary work; a run of them is the signal.

What a judgement *costs* in attention is derived here in code from `ask_kind`
rather than asked — it is a function of the category, and asking it separately
measured as the least confident answer in the battery. Ask what things are;
compute what they cost.

Verdicts land in a JSON file the shell watches, keyed by pane, cached by the
pane's herdr revision so an unchanged screen is never paid for twice.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shlex
import subprocess
import sys
import time
from pathlib import Path
from typing import Any

from jev_api import JevError, api_key, evaluate

# --------------------------------------------------------------------------
# the questions

QUESTIONS: dict[str, Any] = {
    # ---- is this going anywhere? -----------------------------------------
    # The heart of it. Ordinal, concrete at each level, one dimension. No
    # question here asks for a PREDICTION: jev 1.13 is documented to lose
    # accuracy on multi-step reasoning, so "will they keep struggling" is
    # never asked — it is a trend, computed in code from a series of these.
    "progress": {
        "type": "score",
        "instructions": (
            "Look at the work on this screen in the order it happened. How is it moving?"
        ),
        "criteria": [
            "Losing ground. It is undoing or redoing work that was already finished, "
            "or each step leaves more broken than before.",
            "Circling. It keeps trying variations of one idea and getting the same outcome each time.",
            "Grinding. Some steps land and some do not, but the work is inching forward.",
            "Advancing. Each step builds on the one before it and the work is visibly nearer done.",
        ],
    },
    # Structured levels rather than plain strings, which is the documented
    # remedy for a Score whose probability splits between neighbours. Measured:
    # on a flailing screen this went from 0.44 at 0.35 confidence to 0.01 at
    # 0.98 — the difference between "no idea" and "certainly guessing".
    "understanding": {
        "type": "score",
        "instructions": (
            "How well does this agent appear to understand what is actually wrong, "
            "or what it is actually doing?"
        ),
        "criteria": [
            {
                "what": "Guessing. It changes things without saying why, or its stated "
                        "reason does not match what just happened.",
                "examples": [
                    "tries a different value with no explanation",
                    "says 'let me try' repeatedly",
                    "its explanation contradicts the error text",
                ],
            },
            {
                "what": "Hunting. It has named a theory and is testing it, but has not "
                        "established the cause.",
                "examples": [
                    "reads a file to check an assumption",
                    "adds a print to see a value",
                    "says 'if X then Y, let me check'",
                ],
            },
            {
                "what": "Diagnosed. It has stated what is actually going on and its "
                        "actions follow from that.",
                "examples": [
                    "names the specific cause and cites the evidence",
                    "the fix it makes addresses that named cause",
                ],
            },
        ],
    },
    # Recognition, not counting: jev cannot count reliably, so this asks
    # whether repetition is visible, never how many times.
    "repeating": {
        "type": "noul",
        "instructions": (
            "Does this screen show the agent doing something it already did earlier on "
            "this same screen, and getting the same outcome again?"
        ),
        "criteria": {
            "true": "the same action and the same result appear more than once",
            "false": "each action on the screen is different from the ones before it",
        },
    },
    "frustration": {
        "type": "noul",
        "instructions": (
            "Does the agent's own wording show it has lost the thread - saying it is "
            "confused, that it is not sure why something happens, that it will try "
            "something else, or apologising for going in circles?"
        ),
        "criteria": {
            "true": "its own words admit confusion or repeated failure",
            "false": "it reads as matter-of-fact about what it is doing",
        },
    },
    "needs_input": {
        "type": "noul",
        "instructions": (
            "Is the agent missing something that only the person who started it can "
            "supply - a decision, a credential, a file, an answer to a question it asked?"
        ),
        "criteria": {
            "true": "it cannot get past this by working on its own",
            "false": "everything it needs to continue is available to it",
        },
    },
    # ---- what does it want, and is anything dangerous? --------------------
    # Kept from the first battery: validated, orthogonal to progress, and what
    # the row glyphs are built on. `trouble` was dropped — `progress` at its
    # bottom two levels plus `repeating` says the same thing with more nuance.
    "ask_kind": {
        "type": "choice",
        "instructions": (
            "An AI coding agent is running in this terminal. Looking at what is on its "
            "screen, what is it waiting for from the person who started it?"
        ),
        "criteria": {
            "permission": (
                "it is asking to be allowed to do something it already decided to do — a "
                "yes/no or an approve/deny prompt. Answering costs one keystroke and no thought."
            ),
            "pick_one": (
                "it has laid out options and wants the person to choose between them. "
                "Answering needs a moment but no new context."
            ),
            "judgement": (
                "it has hit a real question about intent, design, or priorities that only "
                "the person can answer, and answering means understanding where the work got to."
            ),
            "blocked_external": (
                "it is waiting on something that is not the person — a build, a download, "
                "a test run, a rate limit, another machine."
            ),
            "finished_done": "it has finished what it was asked and is reporting the result.",
            "finished_incomplete": (
                "it has stopped without finishing — it gave up, hit a wall it cannot pass, "
                "or is asking to be redirected."
            ),
            "nothing": (
                "it is working and wants nothing; whatever is on screen is progress, not a request."
            ),
        },
    },
    "risky": {
        "type": "noul",
        "instructions": (
            "Is this agent about to do, or has it just done, something hard to undo — "
            "force-pushing, deleting files or branches, rewriting history, deploying, "
            "dropping data, changing a remote system?"
        ),
        "criteria": {
            "true": "something irreversible is in play",
            "false": "everything on screen is ordinary local work",
        },
    },
    "drifted": {
        "type": "noul",
        # Asks about what the agent ANNOUNCED, not about whether the screen
        # "looks like" the task. The first spelling false-positived at 0.74 on
        # ordinary mid-task shell output, which never visibly serves a title.
        "instructions": (
            "The title records the task this agent was given. Has the agent ANNOUNCED that "
            "it is now doing something outside that task — taking on a refactor, a cleanup, "
            "or a second piece of work nobody asked for? Ordinary intermediate steps toward "
            "the stated task are not a departure, and neither is shell output that simply "
            "does not mention the task."
        ),
        "criteria": {
            "true": "it has said it is doing additional work beyond what was asked",
            "false": "everything it has announced is in service of the stated task, or it has announced nothing",
        },
    },
}

# ask_kind -> (attention cost, the phrase the row shows)
# Cost is the derived half: 0 leave it alone, 1 a keystroke, 2 a moment,
# 3 you will have to read back.
ASK_KINDS: dict[str, tuple[int, str]] = {
    "permission": (1, "permission"),
    "pick_one": (2, "options"),
    "judgement": (3, "needs a decision"),
    "blocked_external": (0, "waiting on something else"),
    "finished_done": (1, "delivered"),
    "finished_incomplete": (3, "stopped, unfinished"),
    "nothing": (0, ""),
}

# Tiers, lowest first. Alarms outrank requests on purpose: a permission prompt
# announces itself and will still be there in ten minutes, while a looping or
# off-task agent is precisely what selective attention never discovers.
TIER_ALARM = 0
TIER_WANTS = 10
TIER_INFORMATIONAL = 20
TIER_QUIET = 30


# --------------------------------------------------------------------------
# configuration


def env_float(name: str, fallback: float) -> float:
    try:
        return float(os.environ.get(name) or fallback)
    except ValueError:
        return fallback


def env_int(name: str, fallback: int) -> int:
    try:
        return int(os.environ.get(name) or fallback)
    except ValueError:
        return fallback


def store_path() -> Path:
    raw = os.environ.get("AGENT_JUDGE_STORE")
    if raw:
        return Path(raw)
    state = os.environ.get("XDG_STATE_HOME") or f"{Path.home()}/.local/state"
    return Path(state) / "quickshell-runtime-shell/agents/judgements.json"


def herdr_bin() -> str:
    return os.environ.get("AGENT_JUDGE_HERDR_BIN") or "herdr"


def hosts() -> list[dict[str, str]]:
    """Every herdr this machine can see: the local one, plus the remotes.

    Fed from the same `herdrRemoteTargets` the i3pm daemon already aggregates,
    so the set of hosts judged cannot drift from the set of hosts shown.
    """
    local = {"host": os.environ.get("AGENT_JUDGE_LOCAL_HOST") or os.uname().nodename,
             "ssh_target": ""}
    try:
        remote = json.loads(os.environ.get("AGENT_JUDGE_HOSTS") or "[]")
    except json.JSONDecodeError:
        remote = []
    rows = [local]
    for entry in remote:
        target = str(entry.get("ssh_target") or "").strip()
        name = str(entry.get("host") or "").strip()
        if target and name and name.lower() != local["host"].lower():
            rows.append({"host": name, "ssh_target": target})
    return rows


# --------------------------------------------------------------------------
# herdr
#
# A remote herdr is reached by running its own CLI over ssh. That is what the
# i3pm daemon already does to aggregate remote sessions, and with the
# ControlMaster this account already keeps, a remote pane read costs about a
# tenth of a second — far less than the judgement it feeds.


def herdr(host: dict[str, str], *args: str, timeout: float = 20.0) -> str:
    target = host.get("ssh_target") or ""
    if target:
        remote = "herdr " + " ".join(shlex.quote(a) for a in args)
        command = [
            "ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=8",
            target, "--", remote,
        ]
        label = f"{host['host']}: herdr {' '.join(args)}"
    else:
        command = [herdr_bin(), *args]
        label = f"herdr {' '.join(args)}"

    try:
        done = subprocess.run(command, capture_output=True, text=True, timeout=timeout)
    except FileNotFoundError:
        raise JevError(f"{label}: command not found") from None
    except subprocess.TimeoutExpired:
        raise JevError(f"{label}: timed out") from None
    if done.returncode != 0:
        detail = (done.stderr or done.stdout or "").strip().splitlines()
        raise JevError(f"{label}: {detail[-1] if detail else 'failed'}")
    return done.stdout


def agents_on(host: dict[str, str]) -> list[dict[str, Any]]:
    raw = herdr(host, "agent", "list")
    try:
        rows = json.loads(raw)["result"]["agents"] or []
    except (json.JSONDecodeError, KeyError, TypeError):
        raise JevError(f"{host['host']}: could not read the agent list") from None
    for row in rows:
        row["_host"] = host["host"]
        row["_ssh_target"] = host.get("ssh_target") or ""
    return rows


def agents() -> tuple[list[dict[str, Any]], list[str]]:
    """Every agent on every reachable herdr.

    An unreachable host is reported, not fatal: a laptop that is asleep should
    cost the others nothing, and its verdicts stay put rather than being
    cleared as though its sessions had ended.
    """
    rows: list[dict[str, Any]] = []
    unreachable: list[str] = []
    for host in hosts():
        try:
            rows.extend(agents_on(host))
        except JevError as exc:
            unreachable.append(str(exc))
    return rows, unreachable


def verdict_key(agent: dict[str, Any]) -> str:
    # Lowercased to match sessionHostKey() in the shell, which normalises the
    # host before using it as a key.
    return f"{str(agent.get('_host') or '').lower()}:{agent.get('pane_id')}"


def read_pane(agent: dict[str, Any], lines: int) -> str:
    # `visible` is what is actually on screen — the same thing the person would
    # see if they switched to this pane, which is the only honest basis for a
    # judgement presented as "what this agent wants".
    host = {"host": agent.get("_host"), "ssh_target": agent.get("_ssh_target") or ""}
    args = ["pane", "read", str(agent.get("pane_id")), "--source", "visible"]
    if lines > 0:
        args += ["--lines", str(lines)]
    return herdr(host, *args)


# --------------------------------------------------------------------------
# redaction
#
# The screen is the most sensitive surface on the machine, and this is the one
# thing on it that leaves the machine. These patterns are a floor, not a
# guarantee: the real protection is sending fifteen lines instead of a
# scrollback, and keeping the excerpt local for the drill-down.

SECRET_PATTERNS = [
    re.compile(r"\b(sk-|ghp_|gho_|ghs_|github_pat_|xox[baprs]-|AKIA|ASIA)[A-Za-z0-9_\-]{8,}"),
    re.compile(r"\bBearer\s+[A-Za-z0-9._\-]{16,}", re.IGNORECASE),
    re.compile(r"\beyJ[A-Za-z0-9._\-]{20,}"),  # a JWT
    re.compile(r"-----BEGIN[A-Z ]*PRIVATE KEY-----"),
    re.compile(
        r"""((?:password|passwd|secret|token|api[_\-]?key|credential)["'\s:=]+)(\S{6,})""",
        re.IGNORECASE,
    ),
    re.compile(r"\b[A-Za-z0-9+/]{40,}={0,2}\b"),  # a long base64 blob
]


def redact(text: str) -> str:
    for pattern in SECRET_PATTERNS:
        if pattern.groups >= 2:
            text = pattern.sub(lambda m: m.group(1) + "<redacted>", text)
        else:
            text = pattern.sub("<redacted>", text)
    return text


# The spinner rows and box-drawing filler a TUI paints carry no information.
# jev is documented to be distracted by irrelevant state, and these lines are
# pure noise — stripping them takes about a fifth off the payload.
DECORATION = re.compile(r"^[\s\u2800-\u28ff\u2500-\u257f\u2580-\u259f·∙…]*$")
ANSI = re.compile(r"\x1b\[[0-9;]*[A-Za-z]")


def excerpt(agent: dict[str, Any], lines: int) -> str:
    """The agent's own recent work, decoration removed.

    More of it is better, which is the opposite of what the "excess context"
    warning first suggested: measured across real panes, progress confidence
    climbed from 0.13 to 0.59 and 0.74 to 0.92 as the window widened from ten
    lines to the full viewport. The warning is about *irrelevant* state; an
    agent's own recent steps are the most relevant state there is.
    """
    raw = read_pane(agent, lines)
    kept = []
    for line in raw.splitlines():
        bare = ANSI.sub("", line).rstrip()
        if not bare.strip() or DECORATION.match(bare):
            continue
        kept.append(bare)
    if lines > 0:
        kept = kept[-lines:]
    return redact("\n".join(kept))


# Durations are text to jev and ordered quantities to us, so they are parsed
# here and handed over already extracted rather than reasoned about.
DURATION_HM = re.compile(r"\((\d+)h\s*(\d+)m")
DURATION_MS = re.compile(r"\((\d+)m\s*(\d+)s")


def elapsed_minutes(screen: str) -> int:
    best = 0
    for hours, minutes in DURATION_HM.findall(screen):
        best = max(best, int(hours) * 60 + int(minutes))
    for minutes, _seconds in DURATION_MS.findall(screen):
        best = max(best, int(minutes))
    return best


PROMPT_MARKERS = ("❯", "proceed?", "[y/n]", "(y/n)", "1. Yes", "Do you want")


def evidence_line(screen: str) -> str:
    """The line a person would point at. A heuristic, and labelled as one.

    Prompt markers first, because for the category that matters most —
    permission — there is an unambiguous right answer on the screen. Otherwise
    the last non-empty line, which is where an agent's request always ends up.
    """
    rows = [row for row in screen.splitlines() if row.strip()]
    for row in reversed(rows):
        stripped = row.strip()
        # A bare "❯" is the cursor, not the question. Require the marker line
        # to carry some text of its own before preferring it over the tail.
        if len(stripped) > 8 and any(marker in stripped for marker in PROMPT_MARKERS):
            return stripped[:160]
    return rows[-1].strip()[:160] if rows else ""


# --------------------------------------------------------------------------
# judging


# Composite scoring: each ordinal is normalised by (levels - 1), weighted, and
# summed in code. jev judges; arithmetic never goes in a prompt. Weights live
# here so priorities can be retuned without touching a single question.
#
# `understanding` carries the least weight of the three on purpose: it is the
# dimension that most often splits between neighbouring levels, so it informs
# the score without being able to dominate it.
WEIGHTS = {"progress": 0.55, "understanding": 0.20, "not_repeating": 0.25}


def health_of(answers: dict[str, Any]) -> float:
    progress = float(answers["progress"]["score"]) / 3.0
    understanding = float(answers["understanding"]["score"]) / 2.0
    not_repeating = 1.0 - float(answers["repeating"]["noul"])
    value = (
        WEIGHTS["progress"] * progress
        + WEIGHTS["understanding"] * understanding
        + WEIGHTS["not_repeating"] * not_repeating
    )
    return round(max(0.0, min(1.0, value)), 3)


def trend_of(series: list[float]) -> float:
    """Rising, flat or falling across the recent past.

    Two-and-two rather than a regression, because jev's test-retest spread on
    an unchanged screen measures under 0.01: movement of this size is the
    screen changing, not the judge wobbling, so a short window suffices and
    multi-sampling would buy nothing.
    """
    if len(series) < 3:
        return 0.0
    recent = series[-2:]
    before = series[-4:-2] or series[:-2]
    return round(sum(recent) / len(recent) - sum(before) / len(before), 3)


def condition_of(series: list[float], working: bool, floor: float, streak_needed: int) -> tuple[str, int]:
    """ok / watch / struggling, and how long it has been low.

    One bad observation is ordinary work — every session has a failing test.
    It takes a run of them to mean something, which is the whole reason the
    history exists: the thing being detected is a trajectory, and no single
    screen contains one.
    """
    if not series or not working:
        return "unknown" if not series else "ok", 0
    streak = 0
    for value in reversed(series):
        if value < floor:
            streak += 1
        else:
            break
    now = series[-1]
    slope = trend_of(series)
    if streak >= streak_needed and now < floor:
        return "struggling", streak
    if now < floor or (slope <= -0.10 and now < 0.70):
        return "watch", streak
    return "ok", streak


def judge(agent: dict[str, Any], lines: int, previous: dict[str, Any] | None) -> dict[str, Any]:
    pane_id = str(agent.get("pane_id") or "")
    row_key = verdict_key(agent)
    screen = excerpt(agent, lines)
    if not screen.strip():
        raise JevError(f"{row_key}: nothing on screen to judge")

    title = str(agent.get("terminal_title_stripped") or agent.get("terminal_title") or "")
    status = str(agent.get("agent_status") or "").lower()
    working = status in ("working", "busy")
    minutes = elapsed_minutes(screen)

    state = {
        "terminal_title": title,
        "agent": agent.get("agent"),
        "herdr_agent_status": agent.get("agent_status"),
        "cwd": agent.get("cwd"),
        "host": agent.get("_host"),
        # Parsed here, never reasoned about: jev treats durations as text and
        # cannot compare them, so the number is given already extracted.
        "minutes_on_this_task": minutes,
        "screen": screen,
    }

    response = evaluate(json.dumps(state), QUESTIONS)
    answers = response.get("answers") or {}
    for key in QUESTIONS:
        if key not in answers:
            raise JevError(f"{row_key}: TypeSafe did not answer {key}")

    ask = answers["ask_kind"]
    kind = ask["choice"]
    ask_confidence = float(ask.get("confidence", 0.0))
    flags = {name: float(answers[name]["noul"]) for name in ("risky", "drifted")}

    alarm = env_float("AGENT_JUDGE_ALARM_THRESHOLD", 0.7)
    show = env_float("AGENT_JUDGE_SHOW_THRESHOLD", 0.45)
    floor = env_float("AGENT_JUDGE_STRUGGLE_FLOOR", 0.45)
    streak_needed = env_int("AGENT_JUDGE_STRUGGLE_STREAK", 2)

    health = health_of(answers)
    history = list((previous or {}).get("history") or [])
    history.append({
        "at": int(time.time()),
        "health": health,
        "progress": round(float(answers["progress"]["score"]), 2),
        "understanding": round(float(answers["understanding"]["score"]), 2),
        "repeating": round(float(answers["repeating"]["noul"]), 2),
        "frustration": round(float(answers["frustration"]["noul"]), 2),
        "minutes": minutes,
        "working": working,
    })
    history = history[-env_int("AGENT_JUDGE_HISTORY", 24):]
    # Only observations taken while the agent was actually working describe a
    # trajectory. An idle session has no work in flight to judge, and letting
    # its scores into the series would dilute the very thing being measured.
    series = [row["health"] for row in history if row.get("working")]
    condition, streak = condition_of(series, working, floor, streak_needed)

    raised = {name: value for name, value in flags.items() if value >= alarm}
    if condition == "struggling":
        raised["struggling"] = 1.0
    cost, phrase = ASK_KINDS.get(kind, (0, ""))

    verdict = {
        "key": row_key,
        "pane_id": pane_id,
        "host": str(agent.get("_host") or "").lower(),
        "revision": agent.get("revision"),
        "agent": agent.get("agent"),
        "agent_status": agent.get("agent_status"),
        "terminal_title": title,
        "cwd": agent.get("cwd"),
        "workspace_id": agent.get("workspace_id"),
        "judged_at": int(time.time()),
        "ask_kind": kind,
        "ask_confidence": ask_confidence,
        "ask_distribution": ask.get("probabilities", {}),
        "risky": flags["risky"],
        "drifted": flags["drifted"],
        "needs_input": float(answers["needs_input"]["noul"]),
        # ---- how it is going ----
        "progress": float(answers["progress"]["score"]),
        "progress_confidence": float(answers["progress"].get("confidence", 0.0)),
        "understanding": float(answers["understanding"]["score"]),
        "understanding_confidence": float(answers["understanding"].get("confidence", 0.0)),
        "repeating": float(answers["repeating"]["noul"]),
        "frustration": float(answers["frustration"]["noul"]),
        "health": health,
        "trend": trend_of(series),
        "condition": condition,
        "low_streak": streak,
        "observations": len(series),
        "minutes": minutes,
        "history": history,
        # ---- presentation ----
        "alarms": sorted(raised, key=lambda name: -raised[name]),
        "cost": cost,
        "progress_label": progress_label(float(answers["progress"]["score"])),
        "lede": (
            lede(kind, phrase, raised, condition, minutes)
            or (working_lede(float(answers["progress"]["score"]), condition, minutes, raised)
                if working else "")
        ),
        # A working session with a health reading always shows: the reading is
        # the point, and it is most informative exactly when the agent wants
        # nothing from you.
        "display": ask_confidence >= show or bool(raised) or (working and len(series) > 0),
        "confidence": ask_confidence,
        "attention": attention(kind, cost, raised),
        "excerpt": screen,
        "evidence": evidence_line(screen),
        "trace": {
            "model": response.get("model"),
            "latencyMs": response.get("latencyMs"),
            "usage": response.get("usage", {}),
            "questions": len(QUESTIONS),
            "alarmThreshold": alarm,
            "showThreshold": show,
            "struggleFloor": floor,
            "struggleStreak": streak_needed,
        },
    }
    return verdict


# Where a working agent sits on the progress scale, as a word. Derived here so
# the row, the tooltip and the CLI cannot disagree about where a boundary is.
def progress_label(value: float) -> str:
    if value < 0.75:
        return "losing ground"
    if value < 1.75:
        return "circling"
    if value < 2.5:
        return "grinding"
    return "advancing"


def humanise(minutes: int) -> str:
    if minutes <= 0:
        return ""
    if minutes < 90:
        return f"{minutes}m"
    return f"{minutes // 60}h{minutes % 60:02d}m"


def lede(kind: str, phrase: str, raised: dict[str, float], condition: str, minutes: int) -> str:
    """The short phrase the row shows.

    Trouble speaks first, because it is the part that would otherwise go
    unnoticed: a permission prompt announces itself and will still be there in
    ten minutes, while a session quietly going in circles never will.
    """
    words = []
    if "struggling" in raised:
        words.append("struggling" + (f" · {minutes}m" if minutes else ""))
    elif condition == "watch":
        words.append("slowing")
    if "risky" in raised:
        words.append("irreversible step")
    if "drifted" in raised:
        words.append("off-task")
    if phrase:
        words.append(phrase)
    return " · ".join(words)


def working_lede(progress: float, condition: str, minutes: int, raised: dict[str, float]) -> str:
    """What a working agent that wants nothing should say.

    This is the common case and it was the blind spot: the row was keyed
    entirely off what the agent WANTS, so an agent that wants nothing showed
    nothing — even with fourteen observations of how it was going behind it.
    """
    if raised or condition == "struggling":
        return ""
    elapsed = humanise(minutes)
    label = progress_label(progress)
    if condition == "watch":
        label = "slowing · " + label
    return f"{label} · {elapsed}" if elapsed else label


def attention(kind: str, cost: int, raised: dict[str, float]) -> int:
    """The order a person should walk the list in.

    Used by `agent-judge show`, not by the panel — the panel's order is fixed,
    because a row that moves while you are reaching for it is worse than a row
    in an unhelpful place. Here nothing can move under you.
    """
    if raised:
        order = 0 if "risky" in raised else (1 if "struggling" in raised else 2)
        return TIER_ALARM + order
    if kind in ("permission", "pick_one", "judgement", "finished_incomplete"):
        return TIER_WANTS + cost
    if kind == "finished_done":
        return TIER_INFORMATIONAL
    return TIER_QUIET


# --------------------------------------------------------------------------
# the store


def load_store() -> dict[str, Any]:
    try:
        data = json.loads(store_path().read_text())
    except (OSError, json.JSONDecodeError):
        return {"version": 1, "updated_at": 0, "verdicts": {}}
    if not isinstance(data, dict) or not isinstance(data.get("verdicts"), dict):
        return {"version": 1, "updated_at": 0, "verdicts": {}}
    # Verdicts written before verdicts were keyed by host carry no `key` and
    # cannot be matched to a session any more. Drop them rather than leaving
    # rows the UI can never resolve and the sweep can never clean up.
    data["verdicts"] = {
        k: v for k, v in data["verdicts"].items()
        if isinstance(v, dict) and v.get("key") and v.get("host")
    }
    return data


def save_store(store: dict[str, Any]) -> None:
    path = store_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    store["updated_at"] = int(time.time())
    # Atomic: the shell file-watches this and must never read a half-written
    # object.
    temporary = path.with_suffix(".tmp")
    temporary.write_text(json.dumps(store, indent=1))
    os.replace(temporary, path)


def stale(verdict: dict[str, Any], agent: dict[str, Any], recheck: int) -> bool:
    """Should a cached verdict be paid for again?

    A changed revision or a changed herdr status is new evidence. Beyond that,
    only a long-running `working` agent is re-judged, and that is the whole
    mechanism by which looping is ever caught — nothing else about a spinning
    agent changes.
    """
    if verdict.get("revision") != agent.get("revision"):
        return True
    if verdict.get("agent_status") != agent.get("agent_status"):
        return True
    if str(agent.get("agent_status") or "").lower() in ("working", "busy"):
        return (time.time() - float(verdict.get("judged_at") or 0)) > recheck
    return False


def sweep(force: bool = False, only: str | None = None) -> dict[str, Any]:
    store = load_store()
    verdicts = store["verdicts"]
    live, unreachable = agents()
    lines = env_int("AGENT_JUDGE_LINES", 15)
    recheck = env_int("AGENT_JUDGE_RECHECK_SECONDS", 120)

    seen = set()
    judged = 0
    failed = list(unreachable)
    for agent in live:
        key = verdict_key(agent)
        if not agent.get("pane_id") or (only and key != only):
            continue
        seen.add(key)
        cached = verdicts.get(key)
        if cached and not force and not stale(cached, agent, recheck):
            continue
        try:
            verdicts[key] = judge(agent, lines, cached)
            judged += 1
        except JevError as exc:
            failed.append(str(exc))

    # A pane that is gone takes its verdict with it; a stale row is worse than
    # no row when the thing it describes no longer exists. Verdicts belonging
    # to a host that simply could not be reached are kept: an asleep laptop has
    # not ended its sessions, and clearing them would claim it had.
    if not only:
        reached = {row["host"] for row in hosts()} - {
            str(problem).split(":", 1)[0] for problem in unreachable
        }
        for key in [k for k in verdicts if k not in seen]:
            if str(verdicts[key].get("host") or "") in reached:
                verdicts.pop(key, None)

    save_store(store)
    return {
        "judged": judged,
        "agents": len(live),
        "failed": failed,
        "unreachable": unreachable,
        "store": store,
    }


# --------------------------------------------------------------------------
# commands


# Nine agents across three hosts can change state a great deal, and every
# change is a paid request. The cap is a guardrail rather than a budget: it
# stops a rebuild storm or a chatty agent from running away, and a judgement
# skipped by it is retried on the next tick.
_spent: list[float] = []


def spend() -> bool:
    ceiling = env_int("AGENT_JUDGE_MAX_PER_HOUR", 600)
    if ceiling <= 0:
        return True
    now = time.time()
    while _spent and now - _spent[0] > 3600:
        _spent.pop(0)
    if len(_spent) >= ceiling:
        return False
    _spent.append(now)
    return True


def cmd_once(args: argparse.Namespace) -> int:
    result = sweep(force=args.force, only=args.pane)
    for problem in result["failed"]:
        print(f"agent-judge: {problem}", file=sys.stderr)
    if args.json:
        print(json.dumps(result["store"]))
    else:
        print(f"{result['judged']} judged of {result['agents']} agents")
        render(result["store"])
    return 1 if result["failed"] and not result["judged"] else 0


def cmd_watch(args: argparse.Namespace) -> int:
    """Poll herdr and judge what changed.

    Polling rather than subscribing because herdr's revision counter is the
    thing that tells us a screen is worth re-reading, and it is cheap to read.
    The debounce matters more than the interval: a burst of output bumps the
    revision many times, and each bump is otherwise a paid request.
    """
    interval = env_float("AGENT_JUDGE_INTERVAL", 3.0)
    debounce = env_float("AGENT_JUDGE_DEBOUNCE", 2.5)
    settled: dict[str, tuple[Any, float]] = {}
    complained = False

    while True:
        live, unreachable = agents()
        if unreachable and not complained:
            for problem in unreachable:
                print(f"agent-judge: {problem}", file=sys.stderr)
            complained = True
        elif not unreachable:
            complained = False
        if not live:
            time.sleep(max(interval, 5.0))
            continue

        now = time.time()
        store = load_store()
        recheck = env_int("AGENT_JUDGE_RECHECK_SECONDS", 120)
        ready = []
        for agent in live:
            if not agent.get("pane_id"):
                continue
            key = verdict_key(agent)
            revision = agent.get("revision")
            previous = settled.get(key)
            if not previous or previous[0] != revision:
                settled[key] = (revision, now)
                continue
            cached = store["verdicts"].get(key)
            if cached and not stale(cached, agent, recheck):
                continue
            if now - previous[1] >= debounce:
                ready.append(key)

        for key in ready:
            if not spend():
                break
            try:
                sweep(only=key)
            except JevError as exc:
                print(f"agent-judge: {exc}", file=sys.stderr)

        alive = {verdict_key(a) for a in live}
        for key in [k for k in settled if k not in alive]:
            settled.pop(key, None)

        time.sleep(interval)


def render(store: dict[str, Any]) -> None:
    rows = sorted(store["verdicts"].values(),
                  key=lambda v: (v.get("attention", 99), v.get("key") or v.get("pane_id")))
    if not rows:
        print("  no verdicts")
        return
    print(f"\n  {'host':<12}{'cond':<12}{'health':>7}{'trend':>7}{'obs':>5}  "
          f"{'prog':>5}{'rep':>5}{'frus':>5}  {'ask':<18}  title")
    for v in rows:
        print(
            f"  {str(v.get('host') or '?')[:11]:<12}{str(v.get('condition') or '?'):<12}"
            f"{v.get('health', 0):>7.2f}{v.get('trend', 0):>+7.2f}{v.get('observations', 0):>5}  "
            f"{v.get('progress', 0):>5.2f}{v.get('repeating', 0):>5.2f}{v.get('frustration', 0):>5.2f}  "
            f"{v['ask_kind'][:17]:<18}  {v['terminal_title'][:30]}"
        )
        if v.get("lede"):
            print(f"  {'':<12}-> {v['lede']}   [{v.get('key')}]")


def cmd_show(args: argparse.Namespace) -> int:
    store = load_store()
    if args.json:
        print(json.dumps(store))
        return 0
    age = int(time.time()) - int(store.get("updated_at") or 0)
    print(f"{len(store['verdicts'])} verdicts, written {age}s ago, {store_path()}")
    render(store)
    return 0


def cmd_explain(args: argparse.Namespace) -> int:
    store = load_store()
    verdict = store["verdicts"].get(args.pane)
    if verdict is None:
        # Accept a bare pane id when it is unambiguous: the host:pane key is
        # exact, but nobody wants to type it when only one host has that pane.
        matches = [v for v in store["verdicts"].values() if v.get("pane_id") == args.pane]
        if len(matches) == 1:
            verdict = matches[0]
        elif len(matches) > 1:
            print("agent-judge: that pane id exists on several hosts; use host:pane —",
                  ", ".join(v["key"] for v in matches), file=sys.stderr)
            return 1
    if verdict is None:
        print(f"agent-judge: no verdict for {args.pane}", file=sys.stderr)
        return 1
    trace = verdict.get("trace") or {}
    print(f"\npane      {verdict.get('key') or verdict['pane_id']}  rev {verdict.get('revision')}  "
          f"({int(time.time()) - int(verdict.get('judged_at') or 0)}s ago)")
    print(f"title     {verdict['terminal_title']}")
    print(f"herdr     {verdict.get('agent_status')}")
    print(f"verdict   {verdict['lede'] or verdict['ask_kind']}   "
          f"attention {verdict.get('attention')}   cost {verdict.get('cost')}")
    print(f"cost      {(trace.get('usage') or {}).get('input_tokens','?')} in / "
          f"{(trace.get('usage') or {}).get('output_tokens','?')} out, "
          f"{trace.get('latencyMs','?')} ms, {trace.get('model')}")

    print("\nwhat it wants:")
    ranked = sorted((verdict.get("ask_distribution") or {}).items(), key=lambda kv: -kv[1])
    for option, probability in ranked[:5]:
        mark = "->" if option == verdict["ask_kind"] else "  "
        bar = "█" * int(round(probability * 20)) + "·" * (20 - int(round(probability * 20)))
        print(f"  {mark} {bar} {probability:.2f}  {option}")

    print(f"\nhow it is going:   {verdict.get('condition')}   health {verdict.get('health',0):.2f}"
          f"   trend {verdict.get('trend',0):+.2f}   over {verdict.get('observations',0)} observations"
          f"   ({verdict.get('minutes',0)}m on task)")
    for name, span in (("progress", 3), ("understanding", 2)):
        value = float(verdict.get(name, 0))
        filled = int(round((value / span) * 20))
        conf = verdict.get(f"{name}_confidence", 0)
        print(f"     {'█' * filled}{'·' * (20 - filled)} {value:.2f}/{span} ({conf:.2f})  {name}")

    series = [row for row in (verdict.get("history") or []) if row.get("working")]
    if len(series) > 1:
        print("\nhealth over time (oldest first):")
        marks = " ▁▂▃▄▅▆▇█"
        spark = "".join(marks[max(0, min(8, int(round(row["health"] * 8))))] for row in series)
        print(f"     {spark}   " + "  ".join(f"{row['health']:.2f}" for row in series[-8:]))

    print("\nflags:")
    for name in ("repeating", "frustration", "needs_input", "risky", "drifted"):
        value = verdict[name]
        bar = "█" * int(round(value * 20)) + "·" * (20 - int(round(value * 20)))
        mark = "!!" if name in (verdict.get("alarms") or []) else "  "
        print(f"  {mark} {bar} {value:.2f}  {name}")

    print(f"\nthe line it was pointed at:\n  {verdict.get('evidence','')}")
    print("\nthe screen it judged (redacted, as sent):")
    for row in (verdict.get("excerpt") or "").splitlines():
        print(f"  | {row}")
    return 0


def cmd_doctor(_: argparse.Namespace) -> int:
    print(f"store        {store_path()}")
    print(f"herdr        {herdr_bin()}")
    print("hosts        " + ", ".join(
        f"{h['host']}{'' if not h['ssh_target'] else ' via ssh ' + h['ssh_target']}"
        for h in hosts()))

    live, unreachable = agents()
    by_host: dict[str, int] = {}
    for agent in live:
        by_host[str(agent.get("_host"))] = by_host.get(str(agent.get("_host")), 0) + 1
    print(f"agents       {len(live)} — " + ", ".join(f"{h}:{n}" for h, n in sorted(by_host.items())))
    for problem in unreachable:
        print(f"             unreachable: {problem}")

    # One pane read per host, because a remote read is the part most likely to
    # be broken and the part a local-only check would never exercise.
    for host_name in sorted(by_host):
        first = next(a for a in live if str(a.get("_host")) == host_name)
        started = time.time()
        try:
            screen = excerpt(first, env_int("AGENT_JUDGE_LINES", 15))
            print(f"pane read    {host_name}: ok, {len(screen)} bytes, "
                  f"{round((time.time() - started) * 1000)} ms")
        except JevError as exc:
            print(f"pane read    {host_name}: FAILED: {exc}")
            return 1
    try:
        key = api_key()
        print(f"api key      ok ({len(key)} chars, …{key[-4:]})")
    except JevError as exc:
        print(f"api key      FAILED: {exc}")
        return 1
    print(f"thresholds   alarm {env_float('AGENT_JUDGE_ALARM_THRESHOLD',0.7)} "
          f"show {env_float('AGENT_JUDGE_SHOW_THRESHOLD',0.45)}  "
          f"lines {env_int('AGENT_JUDGE_LINES',15)}  "
          f"recheck {env_int('AGENT_JUDGE_RECHECK_SECONDS',120)}s  "
          f"cap {env_int('AGENT_JUDGE_MAX_PER_HOUR',120)}/h")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="agent-judge",
        description="Judge what each AI agent session wants, from its own screen.",
    )
    sub = parser.add_subparsers(dest="command", required=True)

    node = sub.add_parser("once", help="judge every agent whose screen has changed")
    node.add_argument("--force", action="store_true", help="re-judge even a cached pane")
    node.add_argument("--pane", help="only this host:pane key")
    node.add_argument("--json", action="store_true")
    node.set_defaults(func=cmd_once)

    node = sub.add_parser("watch", help="judge continuously as agents change")
    node.set_defaults(func=cmd_watch)

    node = sub.add_parser("show", help="print the current verdicts")
    node.add_argument("--json", action="store_true")
    node.set_defaults(func=cmd_show)

    node = sub.add_parser("explain", help="every probability behind one pane's verdict")
    node.add_argument("pane", help="host:pane key, or a pane id if it is unambiguous")
    node.set_defaults(func=cmd_explain)

    sub.add_parser("doctor", help="check herdr, pane reads, and the key").set_defaults(
        func=cmd_doctor
    )

    args = parser.parse_args(argv)
    try:
        return args.func(args)
    except JevError as exc:
        print(f"agent-judge: {exc}", file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        return 0


if __name__ == "__main__":
    sys.exit(main())
