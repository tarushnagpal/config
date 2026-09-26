#!/usr/bin/env python3

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title AI Usage
# @raycast.mode fullOutput

# Optional parameters:
# @raycast.packageName AI
# @raycast.icon 📊
# @raycast.description Claude Max, Claude Team, Codex limits, and Respan spend

"""Show Claude/Codex subscription limits and Respan gateway spend.

Credentials are read from where the tools already keep them; nothing is stored here:
  - Claude Max:  macOS keychain item "Claude Code-credentials" (fallback ~/.claude/.credentials.json)
  - Claude Team: keychain item for ~/.claude-team (fallback ~/.claude-team/.credentials.json)
  - Codex:       asks the `codex` binary via `codex app-server` (uses its own login)
  - Respan:      $RESPAN_API_KEY, ~/.keys/respan_key.txt, or keychain item "respan-api-key"
"""

import datetime as dt
import glob
import hashlib
import json
import os
import shutil
import subprocess
import sys
import unicodedata
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor

HOME = os.path.expanduser("~")
TIMEOUT = 20

# Raycast runs scripts with a minimal PATH.
EXTRA_PATHS = [
    "/opt/homebrew/bin",
    "/usr/local/bin",
    f"{HOME}/.local/bin",
    *sorted(glob.glob(f"{HOME}/.nvm/versions/node/*/bin"), reverse=True),
]
os.environ["PATH"] = os.pathsep.join([os.environ.get("PATH", ""), *EXTRA_PATHS])


class UsageError(Exception):
    pass


# ---------- helpers ----------

def keychain(service):
    if sys.platform != "darwin":
        return None
    r = subprocess.run(
        ["security", "find-generic-password", "-s", service, "-w"],
        capture_output=True, text=True,
    )
    return r.stdout.strip() or None if r.returncode == 0 else None


def http_json(url, headers, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(
        url, data=data, method="POST" if data is not None else "GET",
        headers={"Content-Type": "application/json", **headers},
    )
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT) as r:
            return json.load(r)
    except urllib.error.HTTPError as e:
        raise UsageError(f"HTTP {e.code}: {e.read()[:160].decode(errors='replace')}")


def bar(left_pct, width=20):
    left_pct = max(0.0, min(100.0, float(left_pct)))
    filled = round(left_pct / 100 * width)
    return "█" * filled + "░" * (width - filled) + f" {left_pct:5.1f}% left"


def until(when):
    if when is None:
        return ""
    if isinstance(when, (int, float)):
        when = dt.datetime.fromtimestamp(when, dt.timezone.utc)
    else:
        when = dt.datetime.fromisoformat(when.replace("Z", "+00:00"))
    secs = int((when - dt.datetime.now(dt.timezone.utc)).total_seconds())
    if secs <= 0:
        return "  resets now"
    d, rem = divmod(secs, 86400)
    h, m = divmod(rem // 60, 60)
    span = f"{d}d {h}h" if d else f"{h}h {m}m"
    return f"  resets in {span} ({when.astimezone().strftime('%a %H:%M')})"


def row(label, used_pct, resets=None, detail=""):
    """One limit line; takes the *used* percent but draws what's left."""
    return f"  {label:<14}{bar(100 - float(used_pct))}{detail}{until(resets)}"


# ---------- Claude ----------

CLAUDE_WINDOWS = [
    ("five_hour", "Session (5h)"),
    ("seven_day", "Weekly"),
    ("seven_day_opus", "Weekly Opus"),
    ("seven_day_sonnet", "Weekly Sonnet"),
]


CLAUDE_TEAM_DIR = f"{HOME}/.claude-team"


def claude_keychain_service(config_dir):
    """Match Claude Code: default item, or Claude Code-credentials-<sha256(dir)[:8]>."""
    if config_dir is None:
        return "Claude Code-credentials"
    normalized = unicodedata.normalize("NFC", os.path.abspath(os.path.expanduser(config_dir)))
    suffix = hashlib.sha256(normalized.encode()).hexdigest()[:8]
    return f"Claude Code-credentials-{suffix}"


def claude_credentials_path(config_dir):
    if config_dir is None:
        return f"{HOME}/.claude/.credentials.json"
    return os.path.join(os.path.abspath(os.path.expanduser(config_dir)), ".credentials.json")


def claude_org_name(config_dir):
    path = f"{HOME}/.claude.json" if config_dir is None else os.path.join(
        os.path.abspath(os.path.expanduser(config_dir)), ".claude.json"
    )
    try:
        account = json.load(open(path)).get("oauthAccount") or {}
    except (OSError, json.JSONDecodeError):
        return None
    name = account.get("organizationName")
    return name or None


def claude_title(subscription, org):
    if subscription == "max":
        return "Claude Max"
    if subscription == "team":
        return f"Claude Team ({org})" if org else "Claude Team"
    return f"Claude ({subscription})" if subscription else "Claude"


def claude_account(config_dir, login_hint):
    raw = keychain(claude_keychain_service(config_dir))
    path = claude_credentials_path(config_dir)
    if raw is None:
        if not os.path.exists(path):
            raise UsageError(f"no Claude login ({login_hint})")
        raw = open(path).read()
    oauth = json.loads(raw).get("claudeAiOauth") or {}
    token = oauth.get("accessToken")
    if not token:
        raise UsageError(f"no OAuth token in Claude credentials ({login_hint})")
    # Don't refresh the token ourselves: rotating it could sign Claude Code out.
    if oauth.get("expiresAt") and oauth["expiresAt"] / 1000 < dt.datetime.now().timestamp():
        raise UsageError(f"Claude token expired; {login_hint}")

    d = http_json(
        "https://api.anthropic.com/api/oauth/usage",
        {"Authorization": f"Bearer {token}", "anthropic-beta": "oauth-2025-04-20"},
    )
    lines = []
    for key, label in CLAUDE_WINDOWS:
        w = d.get(key)
        if w and w.get("utilization") is not None:
            lines.append(row(label, w["utilization"], w.get("resets_at")))
    extra = d.get("extra_usage") or {}
    if extra.get("is_enabled"):
        used, limit = extra.get("used_credits"), extra.get("monthly_limit")
        if extra.get("utilization") is not None:
            lines.append(row("Extra usage", extra["utilization"]))
        if used is not None:
            lines.append(f"  {'':<14}{used} / {limit} {extra.get('currency') or ''}".rstrip())
    return claude_title(oauth.get("subscriptionType"), claude_org_name(config_dir)), lines or ["  no usage windows reported"]


def claude_max():
    return claude_account(None, "run `claude` and log in")


def claude_team():
    return claude_account(
        CLAUDE_TEAM_DIR,
        "run `CLAUDE_CONFIG_DIR=~/.claude-team claude auth login`",
    )


# ---------- Codex ----------

def codex_window_label(w, name=None):
    mins = w.get("windowDurationMins")
    if name:  # extra per-model limits get a compact "<name> 5h" label
        span = f"{mins // 60}h" if mins and mins % 1440 else f"{(mins or 0) // 1440}d"
        return f"{name[:9]} {span}"
    if mins == 300:
        return "Session (5h)"
    if mins == 10080:
        return "Weekly"
    if mins:
        return f"{mins // 60}h window" if mins % 1440 else f"{mins // 1440}d window"
    return "Window"


def codex_snapshot_lines(snap, name=None):
    lines = []
    for key in ("primary", "secondary"):
        w = snap.get(key)
        if w:
            lines.append(row(codex_window_label(w, name), w["usedPercent"], w.get("resetsAt")))
    return lines


def codex():
    binary = shutil.which("codex")
    if not binary:
        raise UsageError("`codex` not found on PATH")
    proc = subprocess.Popen(
        [binary, "app-server"], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL, text=True,
    )
    try:
        for msg in (
            {"id": 1, "method": "initialize", "params": {"clientInfo": {"name": "raycast-ai-usage", "version": "1"}}},
            {"method": "initialized", "params": {}},
            {"id": 2, "method": "account/rateLimits/read", "params": {}},
        ):
            proc.stdin.write(json.dumps(msg) + "\n")
        proc.stdin.flush()
        deadline = dt.datetime.now() + dt.timedelta(seconds=TIMEOUT)
        while dt.datetime.now() < deadline:
            line = proc.stdout.readline()
            if not line:
                break
            msg = json.loads(line)
            if msg.get("id") == 2:
                break
        else:
            raise UsageError("timed out waiting for codex")
    finally:
        proc.kill()
    if not line:
        raise UsageError("codex app-server exited without answering")
    if "error" in msg:
        raise UsageError(msg["error"].get("message", "unknown error"))
    return codex_format(msg["result"])


def codex_format(res):
    snap = res.get("rateLimits") or {}
    lines = codex_snapshot_lines(snap)
    for limit_id, other in (res.get("rateLimitsByLimitId") or {}).items():
        if other and limit_id != snap.get("limitId"):
            lines += codex_snapshot_lines(other, name=other.get("limitName") or limit_id)
    credits = snap.get("credits") or {}
    if credits.get("unlimited"):
        lines.append("  Credits       unlimited")
    elif credits.get("hasCredits") and credits.get("balance") is not None:
        lines.append(f"  Credits       {credits['balance']}")
    plan = snap.get("planType")
    return (f"Codex ({plan})" if plan else "Codex"), lines or ["  no rate limits reported"]


# ---------- Respan ----------

def respan_key():
    key = os.environ.get("RESPAN_API_KEY")
    if not key and os.path.exists(f"{HOME}/.keys/respan_key.txt"):
        key = open(f"{HOME}/.keys/respan_key.txt").read()
    key = (key or keychain("respan-api-key") or "").strip()
    if not key:
        raise UsageError("no Respan key (set RESPAN_API_KEY, ~/.keys/respan_key.txt, or keychain 'respan-api-key')")
    return key


RESPAN_PERIODS = {"minute": 60, "hour": 3600, "day": 86400, "week": 604800, "month": 2678400}
RESPAN_PERIOD_LABELS = {"hour": "Hourly limit", "day": "Daily limit", "week": "Weekly limit", "month": "Monthly limit"}


def respan_hard_rule(policy):
    return next(
        (r for r in policy.get("rules") or [] if r.get("severity") == "hard" and r.get("is_active") is not False),
        None,
    )


def respan_policy_applies(p, key_hash, now):
    # Same selection rules as the pi respan-usage extension.
    def parse(ts):
        return dt.datetime.fromisoformat(ts.replace("Z", "+00:00"))

    return (
        p.get("scope") == "api_key_id"
        and str(p.get("scope_value", "")).endswith(f".sha512$${key_hash}")
        and not p.get("compose")
        and p.get("metric") == "cost"
        and p.get("is_active") is True
        and p.get("algorithm") in (None, "balance_fixed_window")
        and (p.get("effective_at") is None or parse(p["effective_at"]) <= now)
        and (p.get("expires_at") is None or parse(p["expires_at"]) > now)
    )


def respan_limits(key, key_hash):
    """Cost limit policies on this key, most relevant (hard, shortest period) first."""
    now = dt.datetime.now(dt.timezone.utc)
    url, policies = "https://api.respan.ai/api/limit-policies/", []
    for _ in range(20):  # pagination guard
        page = http_json(url, {"Authorization": f"Bearer {key}"})
        policies += [p for p in page.get("results") or [] if respan_policy_applies(p, key_hash, now)]
        url = page.get("next")
        if not url:
            break
    policies.sort(key=lambda p: (respan_hard_rule(p) is None, RESPAN_PERIODS.get(p.get("period"), float("inf"))))

    lines = []
    for p in policies:
        rule = respan_hard_rule(p)
        counter = ((rule or {}).get("trigger") or {}).get("counter") or {}
        limit = counter.get("value") if rule else p.get("threshold_value")
        state = p.get("current_state") or {}
        spent = state.get("current_value")
        if not limit or spent is None:
            continue
        label = RESPAN_PERIOD_LABELS.get(p.get("period"), f"{p.get('period')} limit")
        detail = f"  ${max(0.0, limit - spent):.2f} of ${limit:g}"
        lines.append(row(label, spent / limit * 100, state.get("interval_end"), detail))
    return lines


def respan():
    key = respan_key()
    key_hash = hashlib.sha512(key.encode()).hexdigest()
    # Logs are org-wide; Respan identifies a key as "<prefix>.sha512$$<sha512(key)>".
    key_id = f"{key.split('.')[0]}.sha512$${key_hash}"
    now = dt.datetime.now().astimezone()
    today = now.replace(hour=0, minute=0, second=0, microsecond=0)
    ranges = [("Today", today), ("This month", today.replace(day=1))]
    end = (now + dt.timedelta(minutes=1)).astimezone(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    def summary(start):
        start = start.astimezone(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        return http_json(
            f"https://api.respan.ai/api/request-logs/summary?start_time={start}&end_time={end}",
            {"Authorization": f"Bearer {key}"},
            {"filters": {"organization_key_id": {"operator": "", "value": [key_id]}}},
        )

    lines = respan_limits(key, key_hash)
    if lines:
        ranges = ranges[1:]  # the limit already covers today's spend
    for label, start in ranges:
        s = summary(start)
        tokens = (s.get("total_tokens") or 0) / 1e6
        lines.append(
            f"  {label:<14}${s.get('total_cost') or 0:>9.2f}   "
            f"{s.get('number_of_requests') or 0:>6} req   {tokens:>8.1f}M tok"
        )
    return "Respan (your key)", lines


# ---------- main ----------

def main():
    sections = [claude_max, claude_team, codex, respan]
    with ThreadPoolExecutor(len(sections)) as pool:
        futures = [pool.submit(fn) for fn in sections]
    for fn, fut in zip(sections, futures):
        try:
            title, lines = fut.result()
        except Exception as e:  # show every section even if one source fails
            title, lines = fn.__name__.capitalize(), [f"  ⚠ {e}"]
        print(title)
        print("\n".join(lines))
        print()
    print(f"updated {dt.datetime.now().strftime('%H:%M:%S')}")


if __name__ == "__main__":
    main()
