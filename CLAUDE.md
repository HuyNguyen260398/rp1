# RP1 — project conventions

Pixel-art open-world sandbox in Godot 4. These rules exist because agents
default to patterns from tutorials, and most Godot tutorials are node-heavy or
written for Godot 3. Correct that once here rather than every session.

**Read before changing architecture:** `docs/superpowers/specs/2026-08-23-rp1-stage0-stage1-design.md`

## Engine

- Godot **4.7.2**, standard build. **Not the Mono build** — it hangs headless
  without a .NET runtime and breaks every CI gate.
- Invoke Godot only through `./tools/godot.sh`. Never hardcode a binary path.
- GDScript only. No C#.
- Use `TileMapLayer`. The `TileMap` node is deprecated.
- Static typing everywhere: `var x: int = 0`, `func f(a: Vector2i) -> void:`.
- Use `@export` for inspector values. Never hardcode `res://` paths in logic.

## Architecture

- `src/core/` and `src/systems/` **MUST NOT reference Godot nodes.**
  No `extends Node`, no `get_tree()`, no `Engine.`, no `.tscn`. These folders
  extend `RefCounted` only. Enforced by `tools/guard.gd` in CI.
- Presentation reads from world data. World data never reads from presentation.
- All game content lives in `data/*.json`. Never hardcode content in GDScript.
  Never write `match` over content types — look it up in `ContentRegistry`.
- Tile data is five parallel `PackedByteArray` columns per 32×32 chunk, not
  an array of tile objects.
- Entities belong to a **zone**, not a chunk. Crossing a chunk boundary is a
  position update and nothing else.

## Persistence

- Never use `load()`, `ResourceLoader`, or `.tres`/`.res` for save data.
  Resource files can name script paths, so loading one executes code.
- **`get_var()` always passes `false`.** The deserialization guard is on the
  read side; `store_var(..., false)` does not close the vector.
- Every binary file starts with a 4-byte magic and a `u32` format version,
  both **plaintext, outside any compressed region** — the version must be
  readable before a parse strategy is chosen. Never `FileAccess.open_compressed()`.
- All writes are atomic: temp file, `flush()`, `close()`, then rename.
- Saves persist **string ids**, never runtime numeric ids. Numeric ids shift
  whenever content is added.
- Content named in a save but missing from the build becomes a **placeholder
  that retains its original string** — never silently zeroed.
- Any change to a save format requires a migration function and a test that
  loads a committed fixture from the previous version.

## Testing

- TDD. Write the failing test, watch it fail, implement minimally, watch it pass.
- Every file in `core/` and `systems/` has a matching test in `tests/`.
- Run tests with `./tools/run_tests.sh` — never call `gut_cmdln.gd` directly.
  The runner does a mandatory `--import` pass first; without it GUT reports
  missing class_names **and exits 0**, so a broken suite looks green.
- New content types require a schema validation test.

## Commits

- Conventional prefixes: `feat:`, `test:`, `ci:`, `docs:`, `fix:`.
- When working through an implementation plan, each task produces two commits:
  the code, then a `docs:` commit ticking that task's checkboxes in the plan.
- Tick plan checkboxes with `python3 tools/mark_task_done.py <task-number>`,
  never by hand — the plan files are long and it is easy to mark the wrong task.

## Art

- Tile size is 32×32. Character sprites are 32×64.
- Texture filter is `Nearest`, project-wide. Never override per-texture.
- Palette is fixed — see `docs/palette.md`. Do not introduce new colours.

## Assets

- Every folder under `assets/` has a `LICENSE.txt` naming source, author, licence.
- Record every pack in `assets/CREDITS.md` at import time, not later.
- **Never add a CC-NC asset** — it excludes a Steam release. Flag CC-BY-SA
  before use; its share-alike clause is risky for commercial art.

## Scope

Stage 1 scope is fixed. Out of scope: building, crafting, combat, inventory,
procedural generation, multiple zones, elevation *rendering*, NPC schedules,
day/night. Good ideas go in `IDEAS.md`, not into the code.
