#!/usr/bin/env python3
"""Format `zig build bench -- --output=json` output as a markdown PR comment.

Consumed by `.github/workflows/perf-pr-comment.yml`: the bench's JSON
mismatch document is piped in, this script emits the markdown body that
`gh pr comment` puts on the PR.

Reads JSON from stdin (no file argument) and writes markdown to stdout. Exit
status is always 0; an upstream bench failure manifests as either a non-JSON
input (the workflow's bash layer guards against that) or a `status=match`
document with no fixtures (which renders as a short "no changes" body).

Schema expected on stdin (see `emitJsonDiff` in tools/bench/main.zig):

    {
      "status": "mismatch" | "match",
      "summary": {"changed": N, "added": N, "removed": N},
      "fixtures": [
        {
          "name": str,
          "topology_changed": bool,
          "changes": [
            {"counter": str, "from": int, "to": int,
             "delta": int, "pct_change": float}, ...
          ]
        }, ...
      ]
    }
"""

from __future__ import annotations

import json
import sys
from typing import Any


def fmt_int(n: int) -> str:
    """Format an integer with thousands separators (e.g. 4619560 -> 4,619,560)."""
    return f"{n:,}"


def fmt_pct(p: float) -> str:
    """Sign-prefixed percentage to one decimal, e.g. -96.56 -> -96.6%."""
    sign = "+" if p >= 0 else "-"
    return f"{sign}{abs(p):.1f}%"


TOP_MOVERS_N = 5
TOP_MOVERS_THRESHOLD = 7  # Skip the section when the full table is already short.


def _name_cell(fixture: dict[str, Any]) -> str:
    """Fixture name cell, with the topology-changed marker folded in.

    Carved out so the top-movers and full-table renderers share the same
    "where do we put the marker" decision and stay in sync if it changes.
    """
    name = fixture.get("name", "?")
    return f"{name} *(topology changed)*" if fixture.get("topology_changed", False) else name


def _row(fixture: dict[str, Any], change: dict[str, Any]) -> str:
    """Render a single per-counter row of the markdown table."""
    counter = change.get("counter", "?")
    before = fmt_int(change.get("from", 0))
    after = fmt_int(change.get("to", 0))
    delta = fmt_int(change.get("delta", 0))
    pct = fmt_pct(float(change.get("pct_change", 0.0)))
    return f"| {_name_cell(fixture)} | `{counter}` | {before} | {after} | {delta} | {pct} |"


def render(doc: dict[str, Any]) -> str:
    """Build the markdown comment body from the bench's JSON document."""
    status = doc.get("status", "match")
    summary = doc.get("summary", {})
    fixtures = doc.get("fixtures", [])

    if status == "match":
        return "No asserted-counter changes vs the base branch's golden.\n"

    changed = summary.get("changed", 0)
    added = summary.get("added", 0)
    removed = summary.get("removed", 0)

    lines: list[str] = []
    parts = [f"**{changed} fixture(s) changed**"]
    if added:
        parts.append(f"{added} added")
    if removed:
        parts.append(f"{removed} removed")
    lines.append(", ".join(parts))
    lines.append("")

    # Flatten (fixture, change) tuples for the by-impact view. Sort by
    # absolute percentage change so the biggest movers float to the top
    # regardless of sign, since a +96% regression deserves the same eyeballs as
    # a -96% improvement.
    all_changes: list[tuple[dict[str, Any], dict[str, Any]]] = []
    for fixture in fixtures:
        for change in fixture.get("changes", []):
            all_changes.append((fixture, change))
    all_changes.sort(
        key=lambda fc: abs(float(fc[1].get("pct_change", 0.0))),
        reverse=True,
    )

    # Only render the top-movers section when the full table is large enough
    # that scanning for the headlines isn't trivial. Below the threshold the
    # full table IS the at-a-glance view; the extra heading would just be
    # noise that pushes everything down.
    if len(all_changes) > TOP_MOVERS_THRESHOLD:
        lines.append(f"### Top movers (by |Δ%|)")
        lines.append("")
        lines.append("| Fixture | Counter | Before | After | Δ | Δ % |")
        lines.append("|---|---|---:|---:|---:|---:|")
        for fixture, change in all_changes[:TOP_MOVERS_N]:
            lines.append(_row(fixture, change))
        lines.append("")
        lines.append("### All changes")
        lines.append("")

    # Full per-fixture table in manifest order (matches the engine golden's
    # row order, so a reviewer can cross-reference the diff if they want).
    lines.append("| Fixture | Counter | Before | After | Δ | Δ % |")
    lines.append("|---|---|---:|---:|---:|---:|")
    for fixture in fixtures:
        for change in fixture.get("changes", []):
            lines.append(_row(fixture, change))

    lines.append("")
    return "\n".join(lines)


def main() -> int:
    raw = sys.stdin.read()
    if not raw.strip():
        print("_(bench produced no JSON output; see workflow logs for the actual error.)_")
        return 0
    try:
        doc = json.loads(raw)
    except json.JSONDecodeError as e:
        print(f"_(could not parse bench JSON: {e}; see workflow logs.)_")
        return 0
    sys.stdout.write(render(doc))
    return 0


if __name__ == "__main__":
    sys.exit(main())
