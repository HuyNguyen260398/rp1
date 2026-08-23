# Agent instructions

This project's conventions live in **[CLAUDE.md](CLAUDE.md)**. Read that file
first and follow it exactly; it applies to every agent, not only Claude.

Not a symlink, because this repo targets Windows as well as Linux and macOS.
When you change one file, mirror anything agent-relevant into the other.

Quick reference:

- Godot 4.7.2 standard build, invoked via `./tools/godot.sh`. GDScript only.
- `src/core/` and `src/systems/` are node-free (`RefCounted` only), enforced by CI.
- Content is JSON in `data/`, never hardcoded in GDScript.
- Run tests with `./tools/run_tests.sh`.
- Spec: `docs/superpowers/specs/2026-08-23-rp1-stage0-stage1-design.md`
- Current plan: `docs/superpowers/plans/2026-08-23-rp1-phase0-2-foundation-data-persistence.md`
