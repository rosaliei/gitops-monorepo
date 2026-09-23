#!/usr/bin/env python3
"""Delivery metrics (DORA-style) computed from Git history and the GitHub API.

In GitOps every deployment is a commit to environments/<env>/, so Git already is the
deployment log:
  - deployment frequency  = commits that changed environments/<env>/ in the window
  - lead time to prod     = release tag (<app>-v<x.y.z>) -> commit that put x.y.z in prod
  - change failure rate   = prod changes that were rollbacks / all prod changes
  - CI success rate       = GitHub Actions runs of ci.yaml on main (needs GH_TOKEN + gh CLI)

Prints Markdown. Never fails the pipeline: missing data is reported as "n/a".
Run locally:  python3 scripts/pipeline_health.py
"""
import json
import os
import re
import statistics
import subprocess
from datetime import datetime, timedelta, timezone

DAYS = 30


def sh(*cmd):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, check=True).stdout.strip()
    except (subprocess.CalledProcessError, FileNotFoundError):
        return ""


def env_commits(env):
    """[(timestamp, subject, sha)] for commits that changed environments/<env>/."""
    out = sh("git", "log", f"--since={DAYS}.days", "--format=%ct|%H|%s", "--", f"environments/{env}")
    rows = []
    for line in filter(None, out.splitlines()):
        ts, sha, subject = line.split("|", 2)
        rows.append((int(ts), subject, sha))
    return rows


def prod_lead_times_hours():
    hours = []
    for ts, _subject, sha in env_commits("prod"):
        diff = sh("git", "show", "--format=", "--unified=0", sha, "--", "environments/prod")
        current_app = None
        for line in diff.splitlines():
            m = re.match(r"^\+\+\+ b/environments/prod/(.+)\.yaml$", line)
            if m:
                current_app = m.group(1)
            m = re.match(r'^\+  tag: "(\d+\.\d+\.\d+)"$', line)
            if m and current_app:
                tag_time = sh("git", "log", "-1", "--format=%ct", f"{current_app}-v{m.group(1)}")
                if tag_time:
                    hours.append((ts - int(tag_time)) / 3600)
    return hours


def ci_stats():
    repo = os.getenv("GITHUB_REPOSITORY") or sh("gh", "repo", "view", "--json", "nameWithOwner", "-q", ".nameWithOwner")
    if not repo:
        return None
    raw = sh("gh", "api", f"repos/{repo}/actions/workflows/ci.yaml/runs?branch=main&per_page=100")
    if not raw:
        return None
    since = datetime.now(timezone.utc) - timedelta(days=DAYS)
    runs = [r for r in json.loads(raw).get("workflow_runs", [])
            if r.get("conclusion") in ("success", "failure")
            and datetime.fromisoformat(r["created_at"].replace("Z", "+00:00")) >= since]
    if not runs:
        return None
    ok = sum(r["conclusion"] == "success" for r in runs)
    minutes = [
        (datetime.fromisoformat(r["updated_at"].replace("Z", "+00:00"))
         - datetime.fromisoformat(r["run_started_at"].replace("Z", "+00:00"))).total_seconds() / 60
        for r in runs if r.get("run_started_at")
    ]
    return len(runs), ok, statistics.median(minutes) if minutes else None


def fmt(value, unit=""):
    return "n/a" if value is None else f"{value:.1f}{unit}"


def main():
    print(f"## Delivery metrics - last {DAYS} days\n")
    print("| metric | value |\n|---|---|")
    for env in ("dev", "qa", "prod"):
        n = len(env_commits(env))
        print(f"| deployments to **{env}** | {n} ({n / DAYS * 7:.1f} / week) |")

    lead = prod_lead_times_hours()
    print(f"| lead time release -> prod (median) | {fmt(statistics.median(lead) if lead else None, ' h')} |")

    prod = env_commits("prod")
    rollbacks = sum("rollback" in subject for _, subject, _ in prod)
    print(f"| change failure rate (rollbacks / prod changes) | "
          f"{fmt(rollbacks / len(prod) * 100 if prod else None, ' %')} ({rollbacks}/{len(prod)}) |")

    stats = ci_stats()
    if stats:
        total, ok, median_min = stats
        print(f"| CI success rate on main | {ok / total * 100:.0f} % ({ok}/{total} runs) |")
        print(f"| CI duration (median) | {fmt(median_min, ' min')} |")
    else:
        print("| CI success rate on main | n/a |")

    print("\nDeployments are Git commits, so this is computed from `git log environments/<env>`.")


if __name__ == "__main__":
    main()
