# RP1 — Phase 4a Design: Zone Authoring

**Status:** draft
**Date:** 2026-09-11
**Refines:** `docs/superpowers/specs/2026-08-23-rp1-stage0-stage1-design.md` §10 (Phase 4)
**Follows:** Phase 3c (the art pipeline)

---

## 1. Purpose and scope

`src/presentation/main.gd` builds the world in GDScript. Its own comment says
so: *"Phase 4 replaces `_build_debug_zone()` with a zone authored as data."*
Until that happens the project violates its own first content rule — all game
content lives in `data/`, never hardcoded in GDScript — in the single most
visible place it could.

**The deliverable, stated as a single sentence:** the 128x128 home zone is
three PNGs and a JSON file under `data/zone/home/`, the game reads them at
boot, and CI gate 7 makes an unpaintable zone unmergeable.

Phase 4 in the Stage 1 design bundles four loosely related pieces. This spec
takes the first two; `AnimalSystem` and the multi-consumer dirty channel become
**Phase 4b** with their own spec. The split follows the Phase 3a/3b/3c
precedent and keeps each milestone runnable: 4a ends in a real world you can
walk around.

### 1.1 In scope

- `data/zone/home/`: `zone.json` plus `terrain.png`, `object.png`, `height.png`
- `data/schema/zone.json` and its validation test
- `src/core/zone_loader.gd` and `src/core/zone_load_result.gd`
- `tools/check_zone.sh` -> `tools/check_zone.gd`: CI gate 7
- `tools/zone_legend.gd`: a labelled swatch PNG for hand-editing
- Roughly a dozen new tile slices from the committed Slates sheet, with defs
- Deleting `_build_debug_zone()` from `main.gd`

### 1.2 Out of scope

- `AnimalSystem` and the multi-consumer dirty channel — Phase 4b
- Save wiring, New World / Continue — Phase 5
- Autotiling and transition tiles — deferred by Phase 3c, revisited in Phase 6
- Building interiors, a second zone, elevation *rendering*

---

## 2. The central bet

**A zone is a picture of itself.**

The alternative designs were a JSON tile array and a declarative brush script.
Both are more diffable than a PNG and both were rejected for the same reason:
the author cannot see the world while authoring it. A 128x128 zone has 16,384
tiles per layer. No human reads that as text, and the failure mode of a format
humans cannot read is a world nobody ever adjusts.

The bet costs a real thing — `git diff` on `terrain.png` says "binary files
differ" and nothing more. Three mitigations, in order of how much they carry:

1. **CI gate 7 reads the picture.** Every rule a reviewer would want to check
   by eye — full coverage, legend completeness, a walkable spawn — is
   mechanical, so review does not depend on reading the diff.
2. **`tools/zone_legend.gd`** emits a labelled swatch strip, so an editor
   knows which colour is which without consulting the JSON.
3. **The zone is visible in the game**, and `tools/screenshot.gd` already
   exists to capture it.

The second-order payoff is that a house stops being a system. In a brush
format, three houses want a prefab mechanism with stamping and rotation. In a
picture, a house is a rectangle of wall pixels with a door pixel in it.

---

## 3. The data contract

```
data/zone/home/
    zone.json          metadata, legend, entity spawns
    terrain.png        128x128, one pixel = one tile
    object.png         128x128
    height.png         128x128, red channel = the height byte (optional)
```

```json
{
  "id": "home",
  "category": "zone",
  "display_name": "Home Valley",
  "size": [128, 128],
  "biome": "temperate",
  "generation_seed": 0,
  "maps": {
    "terrain": "terrain.png",
    "object": "object.png",
    "height": "height.png"
  },
  "legend": {
    "terrain": {"00ff00": "grass", "0000ff": "water", "ff8000": "dirt"},
    "object": {"000000": null, "008000": "oak_tree", "808080": "rock_small"}
  },
  "player_spawn": [64.5, 64.5],
  "entities": [
    {"type": "rabbit", "at": [40.5, 52.5]}
  ]
}
```

### 3.1 There is no floor map

`floor_id` is Stage 2's player-placed flooring. It is not authorable here, and
that is a deliberate safety property rather than an omission.

`src/systems/walkability.gd:17` carries a warning written for whoever authored
this phase: the composite walkability rule does not consult the `floor` column,
so *"a path or bridge authored as a `floor` over `water` will come out
unwalkable, with no error anywhere to flag it."*

Omitting the floor map makes that mistake inexpressible. Paths are authored as
**terrain** — a `dirt` tile — which is walkable by its own content definition
and needs no special case anywhere.

### 3.2 The legend

Per-layer, so the same colour may mean `grass` in `terrain.png` and an oak in
`object.png`. Keys are lowercase six-digit hex, `RRGGBB`. A value of `null`
means "leave this tile unpainted" (`ContentRegistry.ID_UNKNOWN`), which is what
most of the object layer is.

**A colour present in a map with no legend entry is an error, never a silently
dropped tile.** This is the failure mode a colour-keyed format is most prone
to: an anti-aliased brush, a wrong colour mode on save, a JPEG round-trip.

**Legend colours are identifiers, not art.** They live under `data/`, and
`tools/check_palette.sh` walks only `assets/`, so they fall outside the palette
gate by construction rather than by exemption — the spec records this so a
future reader does not "fix" it. Choose garish, maximally distinguishable
colours precisely so nobody mistakes a map for a picture.

### 3.3 Heights, flags and entities

`height.png` uses the red channel as the height byte, 0-255. Stage 1 renders
flat; the column is carried and persisted from day one per the Stage 1 design
§4.1. The file is optional — absent means every height is zero.

The `flags` column is **not authorable**. Flags are derived from content by
`Walkability`, never hand-set. `main.gd:87` records what happens otherwise:
setting flags from terrain alone "is what left the oaks standing on walkable
tiles."

Entity positions are in **tile units**, matching the Stage 1 design §4.4, so
the centre of tile `(40, 52)` is `[40.5, 52.5]`. `player_spawn` is returned to
the caller rather than spawned by the loader, so the player continues to enter
the world through `Player.spawn()` exactly as it does today.

### 3.4 Schema

`data/schema/zone.json`, validated by the existing `SchemaValidator`. A zone is
**not** a `ContentRegistry` category: the registry assigns numeric ids to
content, and a zone is a document that *references* content by string id.
`CATEGORIES` is unchanged.

Reusing `SchemaValidator` imposes two of its rules on the document. It
compares `def["category"]` against the schema's, so `zone.json` carries
`"category": "zone"` like every content file. And it rejects unknown fields
outright, so every key above is declared in the schema — a typo'd key is an
error rather than a setting that silently does nothing.

---

## 4. Loading

`src/core/zone_loader.gd` — `class_name ZoneLoader extends RefCounted`.

It belongs in `core/` with the rest of the data layer. Checked against
`tools/guard.gd`: the allowlist is `RefCounted` and `Object`, the banned
identifiers are `get_tree(`, `Engine.`, `.tscn`, `get_node(`, `add_child(` and
`queue_free(`. `Image` and `FileAccess` are neither nodes nor banned. No
`load()` and no `ResourceLoader`, consistent with the persistence rule.

```gdscript
static func load_zone(dir: String, registry: ContentRegistry) -> ZoneLoadResult
```

`ZoneLoadResult` is its own file, matching `TilesetBuildResult` and
`DecodeResult`, and carries `zone`, `player_spawn` and `errors`.

**Errors are reported, never fatal.** This is the doctrine
`tileset_build_result.gd:12` already states for art: one bad tile must not
blank the world. A zone that half-loads and reports five errors is strictly
better than a black screen, and CI gate 7 is what stops the half-loaded zone
from ever being committed.

### 4.1 The pipeline

1. Read and schema-validate `zone.json`.
2. Resolve each legend string id through the registry. An id this build lacks
   becomes `register_placeholder()` plus an error, reusing the Stage 1 design
   §6.4 policy. This matters more than it looks: `walkability.gd:56` makes
   placeholders non-blocking, so missing content leaves a **walkable gap**
   rather than an impassable hole in the middle of the world.
3. Decode each map: `FileAccess.get_file_as_bytes()` ->
   `Image.load_png_from_buffer()` -> `convert(FORMAT_RGBA8)` -> walk
   `get_data()` in four-byte strides.
4. Write through `zone.set_terrain` / `set_object` / `set_height`.
5. Spawn the entity list into `zone.entities`.
6. `Walkability.recompute_zone(zone, registry)`.
7. `zone.clear_dirty()`.

**Raw bytes, not `get_pixel()`.** `Image.get_pixel()` returns a float `Color`,
and a float round-trip through sRGB is exactly how a legend key stops matching
the pixel it was written for. Integer bytes compare exactly.

**Steps 6 and 7 are ordered, and the order is not obvious.** `main.gd:91`
documents why: `recompute_zone` dirties every chunk as it writes flags, and the
initial paint is a full `render_zone()` rather than a dirty-driven repaint, so
those flags are not pending work for the renderer. Clearing before the
recompute would leave 16 chunks falsely dirty on the first frame.

### 4.2 Error handling

Each of these is an error that does not stop the load:

| Condition | Result |
|---|---|
| Map dimensions differ from `size` | that map is skipped, others still load |
| Any pixel with alpha < 255 | reported once per map |
| Colour with no legend entry | tile left unpainted |
| Legend id absent from the registry | placeholder registered, tile painted with it |
| `height.png` missing | no error; heights are zero |
| Malformed or unschematic `zone.json` | errors returned, `zone` is null |
| Every map unreadable or absent | errors returned, `zone` is null |

A null `zone` is the one outcome a caller must branch on. `main.gd` reports the
errors through `push_error` and renders nothing — there is no sensible fallback
world, and gate 7 exists so this state never reaches a build.

**Error output is capped at eight distinct problems per map**, then a count. A
PNG saved in the wrong colour mode produces 16,384 unknown colours, and a
16,384-line CI log is the same as no CI log.

### 4.3 Cost

Roughly 49,000 pixel reads and 32,000 `set_*` calls per load, each of which
resolves a chunk through a `Dictionary`. The Stage 1 budget is one second and
this should land far under it, but the budget is an acceptance criterion, so
§8 makes it a test rather than an assumption. If it ever becomes a problem the
fix is to write chunk columns directly instead of going tile by tile; do not do
that pre-emptively.

---

## 5. Surviving the editor and the export

A colour-keyed PNG under `data/` is not art, but Godot cannot tell.

Left alone, the engine imports `data/zone/home/terrain.png` as a
`CompressedTexture2D`. Worse, `export_presets.cfg:10` sets
`include_filter="*.json"`, so **the source PNG never enters the export pack**:
the game would run perfectly in the editor and boot to an empty world as a
shipped build. `assets/tiles/grass.png.import` also shows
`process/fix_alpha_border=true`, which rewrites the RGB of transparent pixels —
harmless for a sprite, fatal for an index map.

**The fix:** commit a `.import` file per map with `importer="keep"`, and widen
the filter to `include_filter="*.json,data/zone/*"`. Godot then leaves the
bytes alone and ships them verbatim, and `load_png_from_buffer` reads identical
bytes in the editor and in the pack.

The exact glob syntax an export filter accepts for a path pattern is the one
thing here taken on documentation rather than on evidence. The plan verifies it
against a real `--export-pack` before anything else depends on it, and falls
back to a `*.zonemap.png` suffix — an unambiguous plain wildcard — if a path
pattern turns out not to match.

Opening the project in the Godot editor is exactly the kind of ordinary act
that reverts an import mode, so gate 7 asserts the three `.import` files still
say `keep`. This mirrors the guard `tests/test_import_manifest.gd` already
applies to art.

The alternative was a bake step compiling PNGs to binary at build time, in the
style of the 3c art pipeline. It is more machinery and a second source of
truth, and it does not buy enough to justify either.

Note that the export gate **already** catches this class of failure: it greps
the packed build for `RP1 rendered <N> cells`, and a zone that failed to load
renders zero. The requirement here is mostly to not weaken that assertion.

---

## 6. CI gate 7

`tools/check_zone.sh` -> `tools/check_zone.gd`, added to
`.github/workflows/ci.yml` after the Palette step. The shell wrapper matches
`check_palette.sh`: bash cannot read PNGs.

**The gate runs the real `ZoneLoader` and fails if `errors` is non-empty.** It
does not reimplement the checks. This is the reasoning Phase 3c gave for
`palette_report.gd` reusing `PaletteMap` — a tool and the pipeline it checks
must not be able to disagree.

On top of the loader's errors it adds four authoring-only rules that the loader
deliberately tolerates at runtime:

1. **The terrain map is fully painted.** An unpainted terrain tile is
   `ID_UNKNOWN`, which `walkability.gd:52` treats as void rather than floor —
   a hole in the world. The loader must survive one; an author must not ship
   one.
2. **`player_spawn` is in bounds and walkable** after `Walkability` has run.
3. **Every legend id and every entity `type` resolves** in the registry. At
   runtime these degrade to placeholders; in CI they are a typo.
4. **The three `.import` files still say `importer="keep"`.**

Two colours mapping to the same content id is fine. A repeated colour *key* is
not detectable: Godot's JSON parser keeps the last occurrence silently, and no
gate can see what the parser discarded. It is also harmless, which is why this
spec accepts it rather than inventing a pre-parse scan. Legend entries never
used by any pixel are **reported but do not fail** — an author adds a colour
before painting with it.

Following the Phase 3c precedent, every rule must be **seen to fail** before it
is trusted. The implementation plan makes that an explicit step per rule.

---

## 7. Content and art

Eleven named slices from `assets/_source/slates-outdoor/sheet.png` (1792x736,
so 56x23 tiles to choose from), plus whatever the zone turns out to want:

| Category | Additions |
|---|---|
| terrain | `dirt` |
| object | `pine_tree`, `rock_small`, `rock_large`, `bush` |
| object (houses) | `wall_stone`, `wall_wood`, `roof_red`, `roof_grey`, `door`, `window` |

Each is a rect entry in `tools/import_manifest.json` plus a JSON def under
`data/terrain/` or `data/object/`; `tools/quantize.gd` regenerates the PNGs
onto the Apollo palette. Objects taller than one tile use the `y_offset`
mechanism `TilesetBuilder` already supports.

**No new asset pack, so no new licence work.** Slates is already CC-BY 4.0,
already credited in `assets/CREDITS.md`, and `assets/tiles/LICENSE.txt` already
describes exactly this derivation. Nothing in this phase touches the licence
surface, which is the point of having done 3c first.

Houses are exterior-only and painted straight into `object.png`: a rectangle of
wall pixels, a door pixel, roof pixels above. Every house tile blocks movement,
including the door — there are no interiors in Stage 1.

Water and path meet grass at a hard 90-degree edge. Autotiling was deferred by
Phase 3c by design and stays deferred; if the result annoys in play, Phase 6 is
where "fix what actually annoys" lives.

### 7.1 An honest note on the sharpest acceptance criterion

The Stage 1 design ends with *"adding a new tree type is one JSON file plus one
PNG, with no code change"* and calls it the real test of whether the
architecture worked. Phase 4a is its first genuine exercise, adding a dozen
tile types without touching `src/`.

The answer comes out as **one JSON file plus one manifest slice**. The PNG is
generated by `quantize.gd` rather than dropped in by hand. The criterion's
spirit holds exactly; its letter predates the 3c art pipeline. Recorded here
rather than quietly claimed as a pass.

---

## 8. Testing

TDD throughout: failing test, watch it fail, implement minimally, watch it
pass. Small fixtures are generated into `user://` at test time rather than
committed as binaries — a 4x4 zone written by the test is readable in the test,
which a committed PNG is not.

**`tests/test_zone_loader.gd`**

- a 4x4 fixture lands terrain, object and height on the correct tiles
- unknown colour: an error, the tile unpainted, the rest of the zone intact
- dimension mismatch on one map: that map skipped, the others still loaded
- a pixel with alpha < 255: an error
- `height.png` absent: every height zero, no error
- legend id absent from the registry: placeholder registered, error reported,
  and the tile comes out **walkable** per §6.4
- entity spawns land in `EntityStore` at tile-unit positions
- error output is capped when every pixel is unknown
- walkability is recomputed: a tile carrying an oak is not walkable
- `dirty_chunk_coords()` is empty on return
- malformed JSON and schema violations return errors and never crash

**`tests/test_zone_schema.gd`** — `data/schema/zone.json` accepts the shipped
`zone.json` and rejects each missing required key. This satisfies the standing
rule that a new content type requires a schema validation test.

**`tests/test_zone_home.gd`** — loads the real shipped `data/zone/home/` and
asserts zero errors, full terrain coverage, and a walkable spawn. This is the
test that fails when someone edits a PNG badly, and it fails locally under
`run_tests.sh` rather than only in CI. It calls the same rule functions
`check_zone.gd` calls, for the same reason the gate reuses `ZoneLoader`: one
implementation, so the two cannot drift apart.

**`tests/test_zone_load_budget.gd`** — a generated 128x128 zone loads in under
one second, making the Stage 1 acceptance criterion mechanical.

**`tests/test_zone_import_mode.gd`** — the three `.import` files say
`importer="keep"`.

Every existing suite must stay green **and unmodified**. `main.gd` is the only
presentation file that changes and has no test of its own;
`tests/test_player_spawn.gd` covers `Player.find_spawn_tile`, which is static
and unaffected by where the spawn point comes from. `player_spawn` is a
tile-unit float pair, so `main.gd` floors it to the `Vector2i` that
`Player.spawn()` takes as `near` — and the ring search stays exactly where it
is, as the guard its own comment says it was written to be.

---

## 9. Acceptance criteria

- [ ] `data/zone/home/` holds `zone.json` and three PNGs; `_build_debug_zone()`
      and its constants are gone from `main.gd`
- [ ] The game boots into the authored zone and the player can walk it
- [ ] `./tools/check_zone.sh` is green, and **each of its rules has been seen
      to fail**
- [ ] `./tools/run_tests.sh` green, with the new suites passing and every
      pre-existing suite unmodified
- [ ] `tools/guard.gd`, `tools/smoke.gd`, `check_asset_licences.sh` and
      `check_palette.sh` still green
- [ ] The **exported** build renders a non-zero cell count, proving the zone
      PNGs reached the pack
- [ ] A 128x128 zone loads in under one second
- [ ] Editing one pixel in `terrain.png` changes one tile in the game, with no
      code change and no re-export of anything
- [ ] Three houses, a pond, paths, rocks and trees are visible in a screenshot

---

## 10. Risks

| Risk | Severity | Mitigation |
|---|---|---|
| PNG changes are invisible in review | High | Gate 7 checks mechanically what a reviewer would check by eye; `zone_legend.gd` and a screenshot cover the rest |
| The editor silently re-imports the maps | High | `importer="keep"` asserted by gate 7 and a test; the export gate catches the consequence independently |
| Seeded layout reads as programmer art | Medium | The PNGs are the source of truth from the moment they are committed; hand-editing needs no tooling and no code |
| Hard tile edges look unfinished | Medium | Accepted knowingly. Autotiling is a Phase 6 decision made with the zone in front of us |
| Legend drift between JSON and pixels | Medium | Unknown colours are errors, not dropped tiles; gate 7 fails the build |
| Scope creep into prefabs or a zone editor | Medium | Out of scope by §1.2. A picture needs no prefab system, which is why this format was chosen |

---

## 11. Corrections to the Stage 1 design

| # | Change | Reason |
|---|---|---|
| 1 | Phase 4 splits into 4a (authoring, zone, art) and 4b (`AnimalSystem`, dirty channel) | Four loosely related pieces in one milestone; the 3a/3b/3c split is the precedent |
| 2 | The authoring format is one PNG per column plus a JSON legend, and there is **no floor map** | §10 said "JSON plus PNG heightmap" without pinning the rest. Omitting floor makes `walkability.gd:17`'s trap inexpressible |
| 3 | CI gains a seventh gate | Zone authoring introduces a new class of committable mistake |
| 4 | The "one JSON plus one PNG" criterion reads "one JSON plus one manifest slice" | 3c made art a generated artefact; recorded in §7.1 rather than silently passed |

---

## 12. What Phase 4b inherits

- **The dirty channel is still unbuilt.** `collision_builder.gd:17` explains
  why invalidation is an explicit call today: `ZoneRenderer.refresh_dirty()`
  consumes and clears the zone's dirty flags, so a second subscriber would race
  it and whichever ran second would see nothing to do. Nothing mutates a zone
  during play in 4a either — the loader runs once, at boot, before the first
  frame. 4b introduces the first runtime mutation and owns the fix.
- **Entity spawns are already authored.** `zone.json`'s `entities` list is
  where 4b's rabbits come from; `AnimalSystem` needs no new authoring surface.
- **`wander_radius` and `flees_player` already exist** in
  `data/creature/rabbit.json` and its schema, unused until 4b.
