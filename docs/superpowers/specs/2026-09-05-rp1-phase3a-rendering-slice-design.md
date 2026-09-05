# RP1 — Phase 3a Design: The Rendering Slice

**Status:** approved
**Date:** 2026-09-05
**Refines:** `docs/superpowers/specs/2026-08-23-rp1-stage0-stage1-design.md` §7 (Presentation)
**Follows:** Phases 0-2 (foundation, data layer, persistence)

---

## 1. Purpose and scope

Phases 0-2 built the world model, the content registry and the save system, and
proved all three headless. Nothing has ever been drawn. This phase draws
something.

**The deliverable, stated as a single sentence:** running the project opens a
window showing a 128x128-tile zone — grass, a water pond, scattered oaks —
painted from real `Zone` chunk data through a `TileSet` built at runtime from
`ContentRegistry`.

Phase 3 in the Stage 1 design bundles rendering, the player, the camera and the
Kenney art import. This document splits off the rendering half as **Phase 3a**
and leaves the rest to **Phase 3b**. The split exists because one architectural
bet underpins everything downstream, and it should be settled before movement,
collision and an art pipeline are stacked on top of it.

### 1.1 In scope

- `TilesetBuilder`: `ContentRegistry` -> `TileSet` + id-to-atlas-coord map
- `ZoneRenderer`: three `TileMapLayer` nodes painted from `Zone` data
- Dirty-chunk repaint path, batched once per frame
- Throwaway placeholder art at the sprite paths the JSON already names
- A CI assertion that the exported build actually paints cells

### 1.2 Out of scope

Player, movement, input, collision, `Camera2D`, Y-sorting, `EntityRenderer`,
chunk streaming, autotiling, the Kenney import, and the real palette. Phase 3b
picks these up. Nothing here should make any of them harder.

### 1.3 Success criteria

This phase succeeds if a new terrain type can be added by writing one JSON file
and one PNG, with no GDScript change, and it appears on screen.

---

## 2. The central bet

The Stage 1 acceptance criterion "adding a new tree type = adding one JSON file
+ one PNG, no code change" is incompatible with a `TileSet` authored in the
Godot editor. An editor-authored `TileSet` is a checked-in resource that must be
hand-edited for every new definition, which is a code change in all but name.

Therefore the `TileSet` is **constructed at runtime** from `ContentRegistry`:
one `TileSetAtlasSource` per definition, holding that definition's texture.

This is the bet, and it had two halves.

**Half one is already settled.** A throwaway probe run against Godot 4.7.2
before this spec was committed confirmed the whole path works as documented:

```
source id      = 0        TileSet.add_source()
source count   = 1
region size    = (32, 48) TileSetAtlasSource.texture_region_size  (oversized OK)
texture_origin = (0, -16) TileData.texture_origin                 (offset OK)
painted cell   = 0        TileMapLayer.set_cell()
used cells     = 1
```

Every API name in section 3.2 is verified, including the two that mattered most
— an atlas region taller than the tile grid, and a negative origin offset. The
implementation is not writing against a guessed API.

**Half two is still open:** textures may not survive export into the PCK,
exactly as `data/*.json` nearly did not — the existing export gate carries a
comment about precisely that failure. Section 8 says how it is caught in CI
rather than in a play session.

---

## 3. Architecture

### 3.1 Where the logic lives

`src/core/` and `src/systems/` must not reference Godot **nodes**. `TileSet`,
`TileSetAtlasSource` and `Texture2D` are `Resource` types, not nodes. A
node-free builder may therefore construct them, stay inside the guard's rules,
and — critically — be unit-tested directly.

That is the whole reason for the split below. The fragile part is the atlas
assembly; putting it inside a `Node2D` would bury the phase's main risk
somewhere GUT cannot reach it cleanly.

```
ContentRegistry ──► TilesetBuilder ──► { TileSet, id → atlas coord }
   (core)            (systems)                    │
                                                  ▼
                     Zone data ──────────► ZoneRenderer ──► 3 TileMapLayers
                       (core)              (presentation)
```

Data flows one way. `ZoneRenderer` reads `Zone`; it never writes to it.

`src/systems/` does not exist yet and is created by this phase. `tools/guard.gd`
already lists it in `GUARDED_ROOTS`, so it is covered from the first file.

### 3.2 `TilesetBuilder` — `src/systems/tileset_builder.gd`

`extends RefCounted`. No nodes, no `get_tree()`, no `.tscn`.

```gdscript
class_name TilesetBuilder

const TILE_SIZE: Vector2i = Vector2i(32, 32)

## Result of a build: the assembled TileSet plus the mapping a renderer
## needs to turn a numeric content id into a cell to paint.
class BuildResult extends RefCounted:
    var tileset: TileSet
    var source_id_by_numeric: Dictionary   ## int -> int (TileSet source id)
    var errors: PackedStringArray

static func build(registry: ContentRegistry) -> BuildResult
```

For each definition in the registry:

- Read `sprite` from the definition. Load the texture.
- If the texture is missing or fails to load, record an error and **skip that
  definition** — it must not abort the build, and it must not paint a wrong
  tile. A missing sprite yields an empty cell and a recorded error.
- Create a `TileSetAtlasSource` with that texture, `texture_region_size` from
  `sprite_rect` if present, otherwise `TILE_SIZE`.
- Create the single tile at atlas coord `(0, 0)`.
- Apply `y_offset` as the tile's `texture_origin`.
- Record `numeric id -> source id`.

Definitions are processed in ascending numeric id so source ids are
deterministic across runs. Determinism matters: a non-deterministic mapping
would make the renderer's output untestable.

Placeholder definitions (`registry.is_placeholder()`) are skipped and recorded,
not drawn. Content that vanished from the build has no art to draw by
definition, and inventing one would hide the problem.

### 3.3 `ZoneRenderer` — `src/presentation/zone_renderer.gd`

`extends Node2D`. Owns three `TileMapLayer` children, created in `_ready()`:

| Layer | Source column | `y_sort_enabled` |
|---|---|---|
| terrain | `Chunk.terrain_id` | false |
| floor | `Chunk.floor_id` | false |
| object | `Chunk.object_id` | **true** |

Y-sorting is on for the object layer only, per §7 of the Stage 1 design. It has
nothing to sort against until the player exists in Phase 3b, but the layer is
configured correctly now so that phase does not have to revisit it.

```gdscript
func setup(registry: ContentRegistry) -> PackedStringArray  ## builds the TileSet
func render_zone(zone: Zone) -> int                          ## full paint, returns cells painted
func refresh_dirty(zone: Zone) -> int                        ## repaints dirty chunks only
```

`render_zone` walks `zone.chunk_coords()` (already sorted for determinism) and
paints each chunk's cells. `refresh_dirty` walks `zone.dirty_chunk_coords()`,
repaints those, and calls `zone.clear_dirty()`.

`_process` calls `refresh_dirty` once per frame. In this phase nothing marks
chunks dirty, so it is a cheap no-op — but the path exists and is exercised, so
Phase 3b inherits a working incremental repaint rather than building one under
deadline.

**Two sentinels, easily confused.** `ContentRegistry` reserves content id `0`
as `ID_UNKNOWN`, meaning "empty tile, do not paint". `TileMapLayer`
independently uses source id `-1` to mean "no cell here", and its source ids
start at `0` — a *valid* source. So content id `0` and source id `0` are both
meaningful and mean different things.

The rules: skip content id `0` rather than painting it, and test emptiness
against `-1` when reading cells back. Conflating the two would silently paint
whatever definition happens to land on source `0`.

### 3.4 Resolved ambiguity: the `set_cell` rule

§7 of the Stage 1 design states: *"`set_cell` is never called in a bulk loop
over thousands of tiles."* Read strictly this forbids initial population, which
is not achievable — Godot 4 exposes no bulk cell-write API, and a 4x4-chunk zone
is 16,384 cells that have to reach the layer somehow.

**This spec reads the rule as forbidding *per-frame* bulk writes, not one-time
population.** Concretely:

- A full `render_zone` is permitted, once, at load.
- `_process` may only ever repaint chunks marked dirty.
- A full repaint from `_process` is a defect.

If the one-time population proves too slow at 128x128, the fix is to spread it
across frames chunk by chunk, not to abandon `TileMapLayer`.

---

## 4. Placeholder art

The JSON already names sprite paths that do not exist:
`res://assets/tiles/grass.png`, `res://assets/tiles/water.png`,
`res://assets/objects/oak_tree.png`. This phase creates them as flat
single-colour PNGs.

| File | Size | Note |
|---|---|---|
| `assets/tiles/grass.png` | 32x32 | |
| `assets/tiles/water.png` | 32x32 | |
| `assets/objects/oak_tree.png` | 32x48 | matches the declared `sprite_rect` |

The oak is deliberately **not** square. `oak_tree.json` already declares
`"sprite_rect": [0, 0, 32, 48]` and `"y_offset": -16`, so oversized tiles with
an origin offset are a live requirement on day one. A convenient 32x32 stand-in
would let a whole class of alignment bug hide until real art lands.

These are debug swatches, not art. They are flat, obviously synthetic, and
deleted wholesale in Phase 3b. They deliberately do not attempt to look good —
a placeholder that resembles finished art is a placeholder that survives to
release.

**Palette:** `CLAUDE.md` requires colours to come from `docs/palette.md`, but
that file has never been created; the rule currently points at nothing. Rather
than invent a palette as a side effect of a rendering task, this phase uses
obviously-synthetic debug colours and leaves the palette to Phase 3b, where it
is chosen deliberately alongside the Kenney import. **Creating
`docs/palette.md` is a prerequisite for any non-placeholder art.**

**Licensing:** `assets/tiles/LICENSE.txt` is updated and `assets/objects/`
gains one, both naming these as project-generated placeholders. A row is added
to `assets/CREDITS.md` at the same time, per the import-time rule.

---

## 5. Testing

Following the project's TDD rule: failing test, watch it fail, implement, watch
it pass.

### 5.1 `tests/test_tileset_builder.gd`

`TilesetBuilder` is node-free, so it is tested directly:

- A registry of N loadable definitions yields N sources.
- `source_id_by_numeric` maps every registered id, and maps none that were
  not registered.
- Source ids are deterministic across two builds from the same registry.
- A definition whose `sprite` does not resolve is skipped, recorded in
  `errors`, and does not abort the build or shift the ids of other entries.
- `sprite_rect` produces the declared region size; its absence defaults to
  32x32.
- `y_offset` reaches the tile's `texture_origin`.
- A placeholder definition is skipped and recorded.

The missing-texture case is not hypothetical — `grass.png` is referenced and
absent in the tree as of this writing, so the test is written before the art.

### 5.2 `ZoneRenderer`

Presentation is outside the per-file test mandate that covers `core/` and
`systems/`. It is covered instead by extending `tools/smoke.gd`, which already
runs headless in CI: build a small zone, render it, assert the painted cell
count matches the number of non-zero tiles, mark a chunk dirty, and assert
`refresh_dirty` repaints exactly that chunk.

This is deliberate. A `TileMapLayer` assertion in GUT proves little that the
smoke test does not, and the smoke test additionally proves the thing works
under the headless conditions CI actually runs.

---

## 6. Debug zone

`main.gd` replaces its print stub with a generated zone: grass everywhere, a
water disc, and an oak on a fixed lattice. Deterministic, so "did it render
correctly?" is answerable by looking.

This is scaffolding, not content, and sits behind a clearly named
`_build_debug_zone()` marked for deletion in Phase 4 when zones are authored as
data. It is the one place this phase knowingly bends the "content lives in
JSON" rule, and it bends it for a fixture rather than for content.

---

## 7. Acceptance criteria

- [ ] Running the project shows a 128x128 zone: grass, a water pond, oaks
- [ ] The oak renders 32x48, offset so its base sits on its tile
- [ ] Adding a terrain JSON + PNG puts it on screen with no GDScript change
- [ ] `./tools/run_tests.sh` green, including the new builder tests
- [ ] `tools/guard.gd` green — `src/systems/` stays node-free
- [ ] `tools/smoke.gd` green, including the new render assertions
- [ ] The exported build paints a non-zero cell count (section 8)
- [ ] A missing sprite logs an error and leaves an empty cell, without crashing

---

## 8. CI

The export job already runs the built game and greps for
`RP1 booted with N content definitions`, because a build that exports cleanly
can still ship without its data. Runtime-built tilesets have exactly that
failure mode, one layer further on: textures may not reach the PCK.

`main.gd` therefore also prints `RP1 rendered N cells`, and the export gate
asserts N is non-zero. The bet in section 2 is then verified by CI on every
push, in an exported build, rather than by remembering to look at a window.

No new CI gate is added. The existing export gate learns one more assertion.

---

## 9. Risks

| Risk | Mitigation |
|---|---|
| ~~Runtime `TileSet` assembly misbehaves in 4.7.2~~ | **Retired** before implementation by the probe in section 2. |
| Textures do not survive export | The section 8 assertion, in CI, in an exported build. |
| 16,384 `set_cell` calls too slow at load | Measured in the smoke test. Fix is chunk-by-chunk population across frames, not a different node. |
| Oversized-tile alignment is subtly wrong | Oak is 32x48 from day one rather than a square stand-in. |
| Debug swatches outlive the phase | Flat and deliberately ugly; deletion is a Phase 3b task. |

---

## 10. What Phase 3b inherits

A working data-to-screen path with a tested atlas builder, a configured
Y-sorted object layer, an incremental repaint path, and a CI assertion that all
of it survives export. Phase 3b adds the player, the camera, collision from the
walkable flags, the Kenney import, and `docs/palette.md` — onto a foundation
whose main uncertainty has already been settled.
