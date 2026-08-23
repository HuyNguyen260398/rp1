#!/usr/bin/env python3
"""Tick every checkbox in one task of an implementation plan.

Hand-editing checkboxes in a multi-thousand-line plan is error-prone and
easy to do to the wrong task. This does it mechanically.

Usage:
    python3 tools/mark_task_done.py 5
    python3 tools/mark_task_done.py 5 --plan docs/superpowers/plans/other.md
    python3 tools/mark_task_done.py 5 --undo
"""
from __future__ import annotations

import argparse
import glob
import re
import sys

DEFAULT_PLAN_GLOB = "docs/superpowers/plans/*-rp1-phase0-2-*.md"


def resolve_plan(explicit: str | None) -> str:
    if explicit:
        return explicit
    matches = sorted(glob.glob(DEFAULT_PLAN_GLOB))
    if len(matches) != 1:
        sys.exit(
            f"error: expected exactly one plan matching {DEFAULT_PLAN_GLOB}, "
            f"found {len(matches)}. Pass --plan explicitly."
        )
    return matches[0]


def heading_mask(lines: list[str]) -> list[bool]:
    """True for lines that are real Markdown headings.

    Lines inside fenced code blocks never count. This matters because
    GDScript doc comments also start with '##', so a line like
    '## A 32x32 block of tiles' inside a code fence would otherwise be
    mistaken for the next section heading.
    """
    mask = [False] * len(lines)
    fence: str | None = None
    for i, line in enumerate(lines):
        stripped = line.lstrip()
        if fence is None:
            m = re.match(r"^(`{3,}|~{3,})", stripped)
            if m:
                fence = m.group(1)[0] * len(m.group(1))
                continue
        else:
            # A closing fence is at least as long as the opening one.
            m = re.match(rf"^{re.escape(fence[0])}{{{len(fence)},}}\s*$", stripped)
            if m:
                fence = None
            continue
        mask[i] = line.startswith("## ")
    return mask


def find_task_span(lines: list[str], task_no: int) -> tuple[int, int, str]:
    """Return (start, end, title) for the '## Task <n>:' section."""
    mask = heading_mask(lines)
    header = re.compile(rf"^## Task {task_no}:\s*(.+?)\s*$")

    start = None
    title = ""
    for i, line in enumerate(lines):
        if not mask[i]:
            continue
        m = header.match(line)
        if m:
            start = i
            title = m.group(1)
            break
    if start is None:
        sys.exit(f"error: no '## Task {task_no}:' heading found")

    end = len(lines)
    for i in range(start + 1, len(lines)):
        if mask[i]:
            end = i
            break
    return start, end, title


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("task", type=int, help="task number to mark")
    ap.add_argument("--plan", help="path to the plan markdown file")
    ap.add_argument("--undo", action="store_true", help="untick instead of tick")
    args = ap.parse_args()

    path = resolve_plan(args.plan)
    with open(path, encoding="utf-8") as f:
        lines = f.read().split("\n")

    start, end, title = find_task_span(lines, args.task)

    src, dst = ("- [ ]", "- [x]") if not args.undo else ("- [x]", "- [ ]")
    changed = 0
    for i in range(start, end):
        if lines[i].startswith(src):
            lines[i] = dst + lines[i][len(src):]
            changed += 1

    if changed == 0:
        print(f"Task {args.task} ({title}): nothing to change.")
        return 0

    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))

    verb = "Unticked" if args.undo else "Ticked"
    print(f"{verb} {changed} checkbox(es) for Task {args.task}: {title}")
    print(f"  {path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
