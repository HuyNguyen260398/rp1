#!/usr/bin/env python3
"""Tick every checkbox in one task of an implementation plan.

Hand-editing checkboxes in a multi-thousand-line plan is error-prone and
easy to do to the wrong task. This does it mechanically.

Usage:
    python3 tools/mark_task_done.py 5
    python3 tools/mark_task_done.py 5 --plan docs/superpowers/plans/other.md
    python3 tools/mark_task_done.py 5 --undo
    python3 tools/mark_task_done.py --section "Definition of done"

Not every checkbox in a plan lives under a '## Task <n>:' heading -- a
plan's Definition of done is a section of its own, and it is the last
thing ticked before a phase closes. --section reaches those by heading
text instead of by task number.
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


def span_from(lines: list[str], mask: list[bool], start: int) -> int:
    """Return the index one past the last line of the section at `start`."""
    for i in range(start + 1, len(lines)):
        if mask[i]:
            return i
    return len(lines)


def find_section_span(lines: list[str], wanted: str) -> tuple[int, int, str]:
    """Return (start, end, title) for the '## <wanted>' section.

    Matched case-insensitively, exactly first, then as a unique substring
    so '--section "definition of done"' and '--section done' both land.
    An ambiguous or absent name lists the headings rather than guessing:
    ticking the wrong section of a plan is the failure this tool exists
    to prevent.
    """
    mask = heading_mask(lines)
    headings = [
        (i, lines[i][3:].strip())
        for i in range(len(lines))
        if mask[i] and not re.match(r"^## Task \d", lines[i])
    ]

    needle = wanted.strip().casefold()
    hits = [h for h in headings if h[1].casefold() == needle]
    if not hits:
        hits = [h for h in headings if needle in h[1].casefold()]
    if not hits:
        known = "\n".join(f"  {t}" for _, t in headings) or "  (none)"
        sys.exit(f"error: no '## {wanted}' heading found. Sections here:\n{known}")
    if len(hits) > 1:
        matched = "\n".join(f"  {t}" for _, t in hits)
        sys.exit(
            f"error: '{wanted}' matches {len(hits)} sections. "
            f"Be more specific:\n{matched}"
        )

    start, title = hits[0]
    return start, span_from(lines, mask, start), title


def find_task_span(lines: list[str], task_no: int) -> tuple[int, int, str]:
    """Return (start, end, title) for the '## Task <n>:' section.

    A qualifier may sit between the number and the colon -- plans write
    '## Task 12 (optional): ...'. The \\b stops Task 1 matching Task 12,
    and [^:] stops the qualifier swallowing a later heading's colon.
    """
    mask = heading_mask(lines)
    header = re.compile(rf"^## Task {task_no}\b[^:]*:\s*(.+?)\s*$")

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

    return start, span_from(lines, mask, start), title


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("task", type=int, nargs="?", help="task number to mark")
    ap.add_argument("--plan", help="path to the plan markdown file")
    ap.add_argument("--undo", action="store_true", help="untick instead of tick")
    ap.add_argument(
        "--section",
        help="heading text to mark instead of a task, e.g. 'Definition of done'",
    )
    args = ap.parse_args()

    if (args.task is None) == (args.section is None):
        ap.error("give either a task number or --section, not both and not neither")

    path = resolve_plan(args.plan)
    with open(path, encoding="utf-8") as f:
        lines = f.read().split("\n")

    if args.section is not None:
        start, end, title = find_section_span(lines, args.section)
        what = f"section '{title}'"
    else:
        start, end, title = find_task_span(lines, args.task)
        what = f"Task {args.task}: {title}"

    src, dst = ("- [ ]", "- [x]") if not args.undo else ("- [x]", "- [ ]")
    changed = 0
    for i in range(start, end):
        if lines[i].startswith(src):
            lines[i] = dst + lines[i][len(src):]
            changed += 1

    if changed == 0:
        print(f"{what}: nothing to change.")
        return 0

    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))

    verb = "Unticked" if args.undo else "Ticked"
    print(f"{verb} {changed} checkbox(es) for {what}")
    print(f"  {path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
