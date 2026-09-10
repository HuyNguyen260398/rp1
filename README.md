# RP1

A pixel-art open-world sandbox game built in [Godot 4](https://godotengine.org). The player builds, and the world remembers.

> [!NOTE]
> **Pre-alpha.** There is no game yet. The repository currently holds the design spec and the implementation plan for the foundation and first playable slice. Nothing here is runnable.

## What it is

RP1 borrows its world model from [Elin](https://store.steampowered.com/app/2135150/Elin/) rather than Minecraft: a world map of discrete, bounded zones you enter and leave, instead of one seamless streaming coordinate space. That single decision removes chunk streaming, background generation, and entity handoff across borders from the problem — while still allowing the world to grow indefinitely, by adding zones and by letting the home zone expand.

Three design pillars gate every decision:

1. **The player builds, and the world remembers.** Persistence is the product, not a feature.
2. **Everything is made of pixels, and the player controls them.** Building is placement of pixel-art tiles and objects, not voxel cubes.
3. **The world can always get bigger.** In fiction, and in the codebase.

## Architecture

The load-bearing rule is that world **data** is completely separated from world **rendering**. `src/core/` and `src/systems/` extend `RefCounted` only and never touch a Godot node — enforced by a CI gate, not by discipline.

```
Presentation    TileMapLayer, Sprite2D, Camera2D    <- Godot nodes, no game logic
Simulation      systems that mutate world data      <- plain GDScript, no nodes
World data      Zone -> Chunk -> Tile               <- source of truth
                Zone -> EntityStore
Persistence     binary chunks, JSON metadata
Content         JSON definitions                    <- data, not code
```

This buys three things that matter more than they look:

- **Headless testing.** A zone can be built, filled with 50,000 tiles, saved, reloaded and asserted equal in under a second with no window — so automated agents get a real pass/fail signal instead of "looks right in the screenshot".
- **A swappable renderer.** Moving from top-down 2D to Elin-style 2.5D becomes a presentation change, not a rewrite. Tile elevation is stored from day one even though nothing renders it yet.
- **A performance escape hatch.** If GDScript becomes the bottleneck, the data layer ports to GDExtension without touching gameplay.

## Getting started

### Prerequisites

- **Godot 4.7.2**, [standard build](https://godotengine.org/download) — *not* the .NET/Mono build, which hangs in headless mode without a .NET runtime and breaks every CI gate.
- Git, and a Bash shell.

Install to `~/Applications/Godot.app` on macOS, or set `GODOT_BIN` to your binary:

```bash
export GODOT_BIN=/path/to/godot
./tools/godot.sh --version    # expect 4.7.2.stable.official, with no ".mono"
```

### Running the tests

```bash
./tools/run_tests.sh
```

> [!IMPORTANT]
> Always go through `tools/run_tests.sh` rather than calling `gut_cmdln.gd` directly. The runner performs a mandatory `--import` pass first; without it GUT reports missing class names **and exits 0**, so a broken suite reports success.

### The other gates

```bash
./tools/godot.sh --headless --path . -s tools/guard.gd   # no Godot nodes in core/ or systems/
./tools/godot.sh --headless --path . -s tools/smoke.gd   # boot + data layer round-trip
./tools/check_asset_licences.sh                          # every assets/ folder declares a licence
```

## Project layout

```
data/          content definitions as JSON — the expandability layer
  schema/      one schema per category, validated in CI
src/
  core/        world data and persistence — NO Godot nodes
  systems/     simulation — NO Godot nodes
  presentation/ Godot nodes live here and only here
  ui/
scenes/
assets/        CREDITS.md plus a LICENSE.txt per folder
tests/         GUT tests, run headless in CI
tools/         godot.sh, run_tests.sh, guard.gd, smoke.gd, screenshot.gd
docs/
  superpowers/specs/   design specs
  superpowers/plans/   implementation plans
```

## Adding content

Adding a new tree type should be **one JSON file and one PNG, with no code change**. That is the acceptance test for whether the architecture worked.

```json
{
  "id": "oak_tree",
  "category": "object",
  "display_name": "Oak Tree",
  "sprite": "res://assets/objects/oak_tree.png",
  "sprite_rect": [0, 0, 32, 48],
  "y_offset": -16,
  "blocks_movement": true,
  "tags": ["natural", "flammable", "tree"]
}
```

Drop it in `data/object/`, and `ContentRegistry` picks it up at boot. A schema test validates every field, so typos like `block_movement` fail CI instead of silently producing a walkable tree.

## Roadmap

| Stage | Scope | State |
|---|---|---|
| 0 | Foundation: project, CI, test harness, architecture gate | Planned |
| 1 | Playable slice: one persistent 128×128 zone, movement, animals | Planned |
| 2 | Building: build mode, inventory, resource economy, undo/redo | Roadmap |
| 3 | Elevation and 2.5D presentation | Roadmap |
| 4 | Multiple zones, world map, procedural generation | Roadmap |
| 5 | Simulation depth: residents, farming, seasons | Roadmap |
| 6 | Release: Steam, controller support, Early Access | Roadmap |

Stage 1 is a complete deliverable in its own right. Stages 2–6 are a multi-year commitment.

## Documentation

| Document | Purpose |
|---|---|
| [Stage 0 + 1 design spec](docs/superpowers/specs/2026-08-23-rp1-stage0-stage1-design.md) | Architecture, data model, save format, acceptance criteria |
| [Phase 0–2 implementation plan](docs/superpowers/plans/2026-08-23-rp1-phase0-2-foundation-data-persistence.md) | Task-by-task TDD plan for the foundation |
| [CLAUDE.md](CLAUDE.md) | Conventions for humans and coding agents |
| [IDEAS.md](IDEAS.md) | Where scope creep waits its turn |
