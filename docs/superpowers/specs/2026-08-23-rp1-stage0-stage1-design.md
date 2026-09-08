# RP1 — Stage 0 + Stage 1 Design

**Status:** approved
**Date:** 2026-08-23
**Supersedes:** `docs/rp1-game-dev-plan.md` §§3, 6, 7 (the draft plan remains the source for art direction, asset sourcing, and the Stage 2+ roadmap)

**Working title:** RP1
**Engine:** Godot 4.7.2 stable, standard (non-Mono) build, GDScript only
**Targets:** Windows, Linux
**Team:** one developer (DevOps background, first game project) plus coding agents

---

## 1. Purpose and scope

Build the foundation (Stage 0) and one playable, persistent, hand-authored zone (Stage 1).

**The Stage 1 deliverable, stated as a single sentence:** the player walks around a 128x128-tile zone containing trees, rocks, water, paths, three houses and wandering animals; quits; relaunches; and the world, their position, and every animal are exactly as they were left.

### 1.1 In scope

- Node-free world data layer: zones, chunks, tiles, entities
- Versioned, atomic, compressed persistence with string-ID remapping
- JSON content registry with schema validation
- Tile and entity rendering, 8-direction player movement, following camera
- One hand-authored zone, authored as data rather than in the Godot editor
- Animals with deliberately simple wander-and-flee behaviour
- Main menu, pause menu, autosave
- Headless test suite and five CI gates

### 1.2 Out of scope

Building, crafting, combat, inventory, procedural generation, multiple zones, elevation *rendering*, NPC schedules, day/night cycle, weather, dialogue, audio beyond ambient and footsteps, multiplayer, modding UI.

Ideas in these areas go in `IDEAS.md`. Nothing on that list enters the codebase during Stage 1.

### 1.3 Design pillars

Every decision is checked against these three:

1. **The player builds, and the world remembers.** Persistence is the product, not a feature.
2. **Everything is made of pixels, and the player controls them.** Building is placement of pixel-art tiles and objects, not voxel cubes.
3. **The world can always get bigger.** In fiction and in the codebase.

---

## 2. The world model decision

**Copy Elin's hub-and-zone world model, not Minecraft's seamless streaming world.**

A seamless world is one continuous coordinate space with chunks streaming around the player: background-thread generation, chunk lifecycle management, entity handoff across borders, constant frame-time pressure. A zone-based world is a set of finite maps plus a world map; travel is a transition, not a stream.

| | Seamless | Zone-based |
|---|---|---|
| Chunk streaming while playing | Required | Not required |
| Load times | Must be zero | A 1s transition is fine |
| Save granularity | Complex, incremental | Whole zone at once |
| Headless testability | Hard | Easy — a zone is one data structure |
| Time to first playable | Months | Weeks |

Expandability comes from **adding zones**, and from a home zone that grows. Seamless streaming stays possible later because world data is chunked *inside* each zone from day one — the data layer is already chunked even though the loading layer is not.

---

## 3. Architecture

### 3.1 The rule that makes everything else work

**World data is completely separated from world rendering.**

```
+---------------------------------------------+
|  Presentation   TileMapLayer, Sprite2D,     |  <- Godot nodes, no game logic
|                 Camera2D, UI                |
+---------------------------------------------+
|  Simulation     systems that mutate         |  <- plain GDScript, no nodes
|                 world data                  |
+---------------------------------------------+
|  World data     Zone -> Chunk -> Tile       |  <- plain GDScript, no nodes
|                 Zone -> EntityStore         |     (source of truth)
+---------------------------------------------+
|  Persistence    binary chunks, JSON meta    |  <- plain GDScript, no nodes
+---------------------------------------------+
|  Content        JSON definitions            |  <- data, not code
+---------------------------------------------+
```

Dependencies point strictly downward. Presentation reads from world data; world data never reads from presentation.

`src/core/` and `src/systems/` extend `RefCounted` only. No `Node`, no `get_tree()`, no `.tscn` preloads, no `Engine.` calls. **This is enforced by a CI test, not by documentation** — agents drift toward node-based solutions because most Godot tutorials are node-based, and a failing test corrects that drift automatically while a document does not.

Three payoffs:

- **Headless testing.** A zone can be built, filled with 50,000 tiles, saved, reloaded and asserted equal in well under a second with no window. This gives agents a real pass/fail signal instead of "looks right in the screenshot."
- **Swappable renderer.** Moving from top-down 2D to Elin-style 2.5D isometric becomes a presentation change plus picking math, not a rewrite.
- **Performance escape hatch.** If GDScript becomes the bottleneck, the data layer ports to GDExtension without touching gameplay.

### 3.2 Module boundaries

| Module | Path | Responsibility | Depends on |
|---|---|---|---|
| `Coords` | `core/coords.gd` | world <-> chunk <-> local conversion | nothing |
| `Chunk` | `core/chunk.gd` | 32x32 tile columns, dirty flag | `Coords` |
| `Zone` | `core/zone.gd` | chunk dictionary, entity store, metadata | `Chunk`, `EntityStore` |
| `EntityStore` | `core/entity_store.gd` | entity columns, free list | nothing |
| `ContentRegistry` | `core/content_registry.gd` | JSON load, string <-> numeric IDs | nothing |
| `SaveManager` | `core/save/save_manager.gd` | orchestrates save/load, atomicity | codecs |
| `ChunkCodec` | `core/save/chunk_codec.gd` | chunk <-> bytes | `Chunk` |
| `EntityCodec` | `core/save/entity_codec.gd` | entity store <-> bytes | `EntityStore` |
| `Migrations` | `core/save/migrations.gd` | version upgrade functions | codecs |
| `MovementSystem` | `systems/movement_system.gd` | collision resolution against flags | `Zone` |
| `AnimalSystem` | `systems/animal_system.gd` | wander and flee | `Zone`, `EntityStore` |
| `ZoneRenderer` | `presentation/zone_renderer.gd` | dirty chunks -> TileMapLayers | `Zone` |
| `EntityRenderer` | `presentation/entity_renderer.gd` | entity rows -> sprites | `EntityStore` |
| `Player` | `presentation/player.gd` | input, CharacterBody2D | `MovementSystem` |

Each module answers: what does it do, how is it used, what does it depend on. Any module whose file grows past roughly 300 lines is doing too much and gets split.

---

## 4. World data model

### 4.1 Chunk storage

32x32 tiles per chunk, five parallel columns, all `PackedByteArray`:

| Column | Width | Bytes | Meaning |
|---|---|---|---|
| `terrain_id` | u16 | 2048 | grass, dirt, stone, water |
| `floor_id` | u16 | 2048 | player-placed flooring (unused in Stage 1) |
| `object_id` | u16 | 2048 | wall, tree, furniture |
| `height` | u8 | 1024 | elevation, Elin-style |
| `flags` | u8 | 1024 | walkable, blocks light, reserved |
| | | **8192** | uncompressed per chunk |

Indexing is `y * 32 + x`. Access is via `encode_u16`/`decode_u16` for the 16-bit columns and direct indexing for the 8-bit ones.

**Rationale for `PackedByteArray` over `PackedInt32Array`:** the draft plan declared `height` and `flags` as `u8` but specified `PackedInt32Array` storage, which would spend 4 bytes on a 1-byte field. Byte arrays cut chunk memory from 20 KB to 8 KB and make serialization a straight buffer concatenation with no width conversion — the in-memory representation *is* the storage format.

**`height` is carried and persisted from day one although Stage 1 renders flat.** Elin's visual identity comes from tile elevation; adding a column to a save format later is painful, and carrying an unused byte costs nothing.

### 4.2 Coordinate conversion

Its own module with its own test file, because floor division on negative coordinates is where off-by-one bugs live.

```gdscript
const CHUNK_SIZE: int = 32

static func world_to_chunk(w: Vector2i) -> Vector2i:
    return Vector2i(floori(float(w.x) / CHUNK_SIZE), floori(float(w.y) / CHUNK_SIZE))

static func world_to_local(w: Vector2i) -> Vector2i:
    return Vector2i(posmod(w.x, CHUNK_SIZE), posmod(w.y, CHUNK_SIZE))

static func local_index(l: Vector2i) -> int:
    return l.y * CHUNK_SIZE + l.x
```

Tests must cover negative coordinates, exact chunk boundaries, and round-trip identity across a range spanning at least `[-64, 64]` on both axes.

### 4.3 Zone

A zone owns metadata (`id`, `display_name`, `size_tiles`, `biome`, `generation_seed`), a `Dictionary` of chunks keyed by `Vector2i`, and one `EntityStore`. Stage 1 ships exactly one zone, `home`, at 128x128 tiles = 4x4 = 16 chunks.

Tile access on `Zone` is by absolute world coordinate; the zone resolves the chunk, creating it lazily if absent, and marks it dirty on write.

### 4.4 Entity model

Entities are stored per **zone**, not per chunk. An animal crossing a chunk boundary is a position update and nothing else — no handoff, no lifecycle event, no bug class.

`EntityStore` is struct-of-arrays with a free list:

| Column | Type | Meaning |
|---|---|---|
| `id` | `PackedInt32Array` | stable u32, never reused within a save |
| `type_id` | `PackedByteArray` (u16) | resolves through `ContentRegistry` |
| `x`, `y` | `PackedFloat32Array` | sub-tile world position, **in tile units** |
| `facing` | `PackedByteArray` (u8) | 8 directions |
| `flags` | `PackedByteArray` (u8) | active, persisted, reserved |
| `blob_offset` | `PackedInt32Array` | offset into side buffer; **all zero in Stage 1** |

**One position unit is one tile**, not one pixel: an entity at `(40.5, 40.5)` stands at the centre of tile `(40, 40)`. Tile size is a *presentation* constant (§7.1), so measuring persisted positions in pixels would bake it into every save file and make changing it a migration. Presentation multiplies by `TILE_SIZE` at the boundary. (Pinned by Phase 3b; the column predates the decision.)

The `blob` column carries variable-length per-entity state (an NPC's inventory, an animal's hunger memory). It is present in the format and unused in Stage 1, on the same reasoning as `height`.

Deleted entities push their slot onto the free list; `id` values are never reused within a save so that dangling references fail loudly rather than silently aliasing a different entity.

**Why struct-of-arrays rather than objects or nodes:** it mirrors the chunk layer exactly, so there is one serialization pattern rather than two, and it keeps entity state out of the presentation layer. The tempting Week-5 shortcut — a `Node2D` per animal owning its own position — violates the layer rule and would fail the architecture guard test.

---

## 5. Content registry

Every tile, object, item and creature is defined in JSON under `data/`, never in GDScript enums or hardcoded `match` statements.

```json
{
  "id": "oak_tree",
  "category": "object",
  "display_name": "Oak Tree",
  "sprite": "res://assets/objects/oak_tree.png",
  "sprite_rect": [0, 0, 32, 48],
  "y_offset": -16,
  "blocks_movement": true,
  "blocks_light": true,
  "tags": ["natural", "flammable", "tree"]
}
```

`ContentRegistry` loads all JSON at boot, assigns numeric runtime IDs, and exposes lookup by string ID in both directions.

**Each category has a JSON schema, and a test validates every data file against it.** This is what makes bulk agent-generated content safe to accept: without a schema, "add 20 furniture types" produces twenty files with three subtly different shapes, and the divergence is only discovered at runtime.

Three reasons the registry matters more than it looks:

- Adding content becomes a data edit, not a code change — validated by a schema test rather than by review.
- It is mod support nearly for free; scanning a `mods/` folder for additional JSON is most of the work.
- String IDs survive save-format changes, which section 6 depends on entirely.

---

## 6. Persistence

### 6.1 Layout

```
user://saves/<world_id>/
    meta.json          save_version, created, playtime, seed
    id_map.json        string_id -> numeric_id for THIS save
    player.json        position, facing, current zone
    zones/
        home/
            zone_meta.json
            chunks/
                0_0.chunk
                0_1.chunk
            entities.dat
```

**Metadata is JSON; bulk data is binary.** Metadata is small, cold, and worth being able to inspect with `cat`; chunk and entity data are large and hot. Debuggability where it is free, density where it matters.

### 6.2 Chunk file format

```
offset  field               size   encoding
0       magic "RP1C"        4 B    plaintext
4       format_version u32  4 B    plaintext
8       chunk_x i32         4 B    plaintext
12      chunk_y i32         4 B    plaintext
16      payload_size u32    4 B    plaintext  (uncompressed byte count)
20      compression u8      1 B    plaintext  (0 = none, 1 = ZSTD)
21      reserved            3 B    plaintext
24      payload             ...    ZSTD-compressed
```

Payload is the five columns concatenated in the order given in section 4.1, totalling 8192 bytes uncompressed.

**The header is outside the compressed stream.** This is the critical correction to the draft plan, which specified both a 4-byte version header and `FileAccess.open_compressed()`. Those requirements contradict each other: `open_compressed` compresses the entire file, so the version header would only be readable after already decompressing with an assumed format. Writing with plain `FileAccess` and compressing only the payload via `PackedByteArray.compress()` keeps the version readable before parsing, and the plaintext `payload_size` supplies the argument `PackedByteArray.decompress()` requires.

Entity files use the same pattern with magic `RP1E`, a `count` field, and the entity columns as payload.

### 6.3 Rules

1. **Version every file.** Magic plus `format_version` in every binary header, `save_version` in `meta.json`. The migration function skeleton is written in Stage 0 even though it does nothing. Retrofitting versioning onto an unversioned format is the kind of problem that kills hobby projects.

2. **Persist string IDs, not runtime integers.** `id_map.json` records the string-to-numeric mapping used when the save was written. On load, a translation table is built from old numeric to new numeric and applied to every tile column. Without this, inserting one new tile type corrupts every existing world. This is the single highest-value rule in this document.

3. **Never use `load()`, `ResourceLoader`, or `.tres`/`.res` for save data.** Godot resource files can name script paths, so loading one executes code; a save file from a friend or a cloud sync becomes an arbitrary code execution vector. Use `FileAccess` with explicit typed reads and writes.

4. **`get_var()` must always pass `false`.** The deserialization guard is on the **read** side — `get_var(allow_objects = true)` is what instantiates objects. The draft plan placed this rule on `store_var()`, which does not close the vector. Preferred practice in the chunk path is no `get_var` at all, only explicit typed reads.

5. **Atomic writes, always.** Write to `<name>.tmp`, `flush()`, `close()`, then `DirAccess.rename_absolute()`. A crash or power loss mid-save must never leave a half-written world.

6. **Dirty flags.** Each chunk carries `dirty: bool`. Autosave walks loaded chunks and writes only dirty ones.

7. **Compression.** ZSTD on the payload. Measured at 89x on synthetic repetitive data; expect 10-20x on real mixed content.

8. **Autosave triggers:** zone transition, every 5 minutes, and on quit. The previous autosave is retained as `.bak`, one rotation. **Focus-loss autosave is deliberately excluded** — it fires constantly during development and adds nothing the 5-minute timer does not already cover.

9. **Generated-versus-modified separation** is not needed in Stage 1 (the zone is hand-authored), but the chunk format reserves header space so a flag can be added when procedural zones arrive in Stage 4.

### 6.4 Unknown ID policy

When a save's `id_map.json` names a string the current registry does not have — content removed, mod uninstalled, save from a newer build — the loader:

1. allocates a placeholder runtime ID that **retains the original string**,
2. renders it as a visibly wrong magenta tile with the string in its tooltip,
3. treats it as non-blocking for movement,
4. writes the **original string** back on the next save.

Saves therefore remain lossless across content removal, and the failure is loud rather than silent. This behaviour is covered by a test.

### 6.5 Steam Cloud

Point Steam Cloud at `user://saves/` when the Steamworks app exists. Configuration only, no code. Stage 6.

---

## 7. Presentation

`ZoneRenderer` owns three `TileMapLayer` nodes — terrain, floor, object. It rebuilds only chunks marked dirty, batching all changes and applying them once per frame in `_process`. `set_cell` is never called in a bulk loop over thousands of tiles, and `set_cell_terrain_connect` is never used for bulk fills; autotile connections for bulk operations are computed in the data layer.

`y_sort_enabled` is on for the object layer only, never for terrain.

`EntityRenderer` maintains a pool of `Sprite2D` nodes that read positions from `EntityStore` each frame and own no state of their own.

`Player` is a thin `Node2D` owning input and no position of its own: it reads the input actions, asks `MovementSystem` to resolve the move, and writes the result back to its `EntityStore` row. Movement is 8-direction, Y-sorted against objects. `Camera2D` follows with pixel snapping and zone-bounds limits.

**Corrected by Phase 3b.** This section previously specified a `CharacterBody2D`, which contradicted §3.2's `MovementSystem` ("collision resolution against flags") — `move_and_slide()` *is* collision resolution, and `src/systems/` may not touch a node. Resolved in §3.2's favour so that acceptance criterion #1 is a headless test rather than a play-session. See `docs/superpowers/specs/2026-09-08-rp1-phase3b-player-movement-design.md` §2.

**Collision** in Stage 1 is generated as merged rectangles per chunk from the walkable flags, via the interface `Chunk -> Array[Rect2i]`. Rects are in **world tile coordinates** and the builder is a **cached instance**, not a pure static, because rebuilding 1024 tiles per chunk per frame is not affordable. Stage 1 may use a naive row-merge implementation; Stage 2 replaces it with greedy meshing behind the same interface. Per-tile collision shapes are never used — a 32x32 chunk of solid tiles would be 1024 colliders.

The `FLAG_WALKABLE` bit those rects read is derived from content by `systems/walkability.gd` as `terrain.walkable AND NOT object.blocks_movement`, recomputed when a zone is built, loaded, or mutated. Invalidation is an explicit call rather than a subscription to the zone's dirty flags, which `ZoneRenderer` already consumes and clears.

### 7.1 Art constants

Fixed once, recorded in `CLAUDE.md`, never revisited.

| Constant | Value |
|---|---|
| Tile size | 32x32 |
| Character size | 32x64 (2 tiles tall) |
| Palette | one fixed Lospec palette, recorded in `docs/palette.md` |
| Outline style | one style, enforced |
| Texture filter | `Nearest`, project-wide |
| Window | 1280x720, `canvas_items` stretch, integer scaling |

---

## 8. Testing and CI

### 8.1 Approach

Test-driven throughout. Weeks 2 and 3 are pure data and persistence work with no visuals, so every line is headless-testable and there is no excuse for a test-after workflow. This is also the best possible period to calibrate how the developer works with coding agents.

Every file in `core/` and `systems/` has a matching test file in `tests/`.

Framework: GUT 9.7.1.

### 8.2 CI gates

All gates run on `ubuntu-latest` with the Godot 4.7.2 Linux headless binary.

| # | Gate | Fails when |
|---|---|---|
| 1 | GUT suite | any test fails |
| 2 | Architecture guard | `core/` or `systems/` extends a non-allowlisted base class, or references a banned identifier |
| 3 | Smoke test | booting headless and running 300 frames produces any error |
| 4 | Asset licence check | a folder under `assets/` lacks `LICENSE.txt` |
| 5 | Export | Windows or Linux export fails |

**Gate 2 detail.** The guard is an allowlist of permitted base classes (`RefCounted`, `Object`) plus a banned-identifier scan for `extends Node`, `extends Node2D`, `get_tree`, `Engine.`, and `.tscn`. The draft plan's `grep "extends Node"` would have passed `extends Node2D` — the guard must be positive (allowlist) rather than negative (blocklist of one string).

Each gate is verified by deliberately breaking it once and confirming CI goes red.

### 8.3 Screenshot tooling

`tools/screenshot.gd` runs the game headless and writes a PNG. This is the only channel through which text-based agents receive visual feedback, and it closes the loop on the one thing they cannot otherwise see. It is the easiest Stage 0 task to skip and must not be skipped.

---

## 9. Repository layout

```
rp1/
  CLAUDE.md              agent rules; the highest-leverage file
  AGENTS.md              pointer file directing Codex to CLAUDE.md (not a symlink: Windows)
  README.md
  LICENSE.md             proprietary, all rights reserved
  IDEAS.md               where scope creep goes to wait
  project.godot
  export_presets.cfg
  data/
    schema/              JSON schema per category
    terrain/ objects/ items/ creatures/
  src/
    core/                NO Godot nodes
      coords.gd chunk.gd zone.gd entity_store.gd content_registry.gd
      save/              save_manager.gd chunk_codec.gd entity_codec.gd migrations.gd
    systems/             NO Godot nodes
      movement_system.gd animal_system.gd
    presentation/        Godot nodes live here and only here
      zone_renderer.gd entity_renderer.gd player.gd camera.gd
    ui/
  scenes/
  assets/
    CREDITS.md
    tiles/ objects/ characters/ ui/
  tests/                 GUT tests, headless in CI
  tools/                 screenshot.gd, guard.gd, validators
  docs/
    palette.md
    superpowers/specs/
```

---

## 10. Delivery phases

**Naming:** *Stages* are roadmap units (Stage 1 is the playable slice); *Phases* are the delivery steps inside them. Phase 0 delivers Stage 0; Phases 1-6 together deliver Stage 1.

Phases are **ordered milestones, not calendar weeks.** The sequence is what carries the risk; the dates will slip and that is expected for a first game project. Estimates assume part-time solo work with heavy agent assistance.

### Phase 0 — Foundation

No gameplay. Build the machine that builds the game.

| # | Task | Done when |
|---|---|---|
| 0.1 | Godot 4.7.2 standard build, project created, git initialised | first commit exists |
| 0.2 | Project settings: `Nearest`, `canvas_items`, integer scaling, 1280x720 | test sprite is crisp at 2x and 3x |
| 0.3 | `CLAUDE.md` and `AGENTS.md` written | agents follow conventions unprompted |
| 0.4 | GUT installed, one trivial test passing headless | exits 0 |
| 0.5 | CI runs all five gates on push | green check on a PR |
| 0.6 | Smoke test | breaking something turns CI red |
| 0.7 | Architecture guard | adding `extends Node2D` to a core file turns CI red |
| 0.8 | `tools/screenshot.gd` | produces a PNG from a headless run |

### Phase 1 — Data layer

Pure GDScript, no visuals, fully headless.

- `Coords` with negative-coordinate tests
- `Chunk` with the five byte columns
- `Zone` holding chunks and an `EntityStore`
- `EntityStore` with free list
- `ContentRegistry` loading and validating JSON
- Tests: cross-boundary tile access, negative coordinates, registry rejects malformed files, entity add/remove/ID stability

### Phase 2 — Persistence

Still headless. Save and load are built **before** rendering; reversing this order is how projects end up retrofitting persistence into a system that resists it.

- `ChunkCodec` and `EntityCodec` with plaintext headers and ZSTD payloads
- `id_map.json` write, read and remap
- Atomic write via temp plus rename
- Migration skeleton
- Tests: round-trip 50,000 random tiles byte-identical; load a fixture written at an older version; truncated file fails gracefully; adding a new tile type leaves old saves loadable; unknown string ID follows section 6.4

### Phase 3 — Rendering and movement

First visuals. Split into three slices; the split is recorded here because the
phase boundaries below moved with it.

**Phase 3a — the rendering slice** *(done)*

- `ZoneRenderer` with three `TileMapLayer`s and dirty-chunk batching
- `TilesetBuilder`: a `TileSet` assembled at runtime from `ContentRegistry`
- Placeholder art and the debug zone

**Phase 3b — player, movement and collision**

- `Player` as a thin `Node2D`, 8-direction, Y-sorted, position held in `EntityStore`
- `Walkability`, `CollisionBuilder` and node-free `MovementSystem`
- `Camera2D` with pixel snapping and bounds
- `EntityRenderer` pooling `Sprite2D` over entity rows

**Phase 3c — the art pipeline**

- Kenney tileset imported, `CREDITS.md` extended
- `tools/quantize.gd` and `tools/check_palette.sh` as CI gate 6
- Every placeholder swatch from 3a and 3b deleted

### Phase 4 — World content

- Hand-author the 128x128 zone **as data** (JSON plus PNG heightmap the game reads), not in the Godot editor, so world data stays in the layer agents can manipulate
- Trees, rocks, water, paths, three houses (exterior only)
- `AnimalSystem`: wander within a radius, flee the player. Deliberately dumb — this validates the entity pipeline, not AI.
- A multi-consumer dirty channel, so the collision cache and `ZoneRenderer` can both react to zone mutation

*(Collision from walkable flags and `EntityRenderer` moved earlier, into Phase 3b.)*

### Phase 5 — Game loop closure

- Main menu: New World / Continue / Quit
- Save on quit, load on continue, autosave every 5 minutes
- Player position and facing persisted
- Animals persisted with positions
- Pause menu

### Phase 6 — Polish and validation

- Ambient audio, footsteps, basic UI frame
- Play for 30 minutes across several sessions; fix what actually annoys
- Export Windows and Linux via CI
- **Test on a machine that has never had Godot installed** — exported builds break in ways the editor never shows

---

## 11. Acceptance criteria

- [ ] Walk from any corner of the zone to any other with no collision bugs
- [ ] Quit and relaunch: world, player position and facing, and all animal positions restored
- [ ] A 128x128 zone's chunk payloads round-trip **byte-identical** through save and load
      (compare decompressed payloads, not raw file bytes -- compression need not be deterministic)
- [ ] A full zone save completes in under 100 ms
- [ ] A save written against an older `format_version` still loads, via a committed fixture
- [ ] An unknown string ID loads as a placeholder and survives a resave with its original string intact
- [ ] Zone loads in under 1 second
- [ ] 60 FPS with all 16 chunks loaded
- [ ] All five CI gates green
- [ ] Exported build runs on a clean machine
- [ ] **Adding a new tree type is one JSON file plus one PNG, with no code change**

The last criterion is the real test of whether the architecture worked.

Note: the draft plan's "save file under 5 MB" criterion was removed. Sixteen ZSTD-compressed chunks total tens of kilobytes, so the criterion passes without conveying information; the byte-identical round-trip and 100 ms budget replace it with something that can actually fail.

---

## 12. Risks

| Risk | Severity | Mitigation |
|---|---|---|
| Scope creep into "make Elin" | Very high | Stage 1 scope is fixed. Everything else goes in `IDEAS.md`. |
| Motivation loss around month 3 | High | The real killer of solo projects. Ship Stage 1 publicly and free on itch.io; external feedback is fuel. |
| Building systems forever, never a game | High | Every phase ends in something runnable. A phase with no runnable output is mis-scoped. |
| Save format churn breaking worlds | High | String IDs, versioning and migration tests from Phase 2. Non-negotiable. |
| Agent code drifting from architecture | Medium | CI gates as enforcement, not documentation. Tests correct drift; docs do not. |
| Godot 4.7.2 is five days old | Medium | Accepted knowingly. Engine bugs may lack public answers. Upgrading is cheap now and expensive after content exists; 4.6.3 is the fallback if a blocker appears. |
| Art incoherence from mixed packs | Medium | One palette, one tile size, one outline style. Kenney only to begin with. |
| GDScript performance at scale | Medium | The data/render split makes the fix a contained GDExtension port. Do not optimise before Stage 2. |
| Phase estimates slip | Medium | Phases are ordered milestones, not dates. Sequence is the thing that matters. |

---

## 13. Corrections to the draft plan

Recorded so the reasoning is not lost.

| # | Change | Reason |
|---|---|---|
| 1 | `get_var(false)` on read, not `store_var(..., false)` on write | The write-side rule does not close the code-execution vector |
| 2 | Plaintext header plus compressed payload, not `open_compressed()` | Version must be readable before the parse strategy is chosen |
| 3 | `PackedByteArray` for all five columns | Matches declared widths; 8 KB rather than 20 KB per chunk |
| 4 | Entity layer designed (`EntityStore`) | Was scheduled in Weeks 5-6 with no design behind it |
| 5 | Unknown-string-ID policy plus test | Behaviour was undefined on content removal |
| 6 | Guard test is an allowlist plus banned identifiers | `grep "extends Node"` misses `extends Node2D` |
| 7 | JSON schema per content category | Makes bulk agent-generated content safe to accept |
| 8 | Metadata JSON, bulk data binary | Debuggability where it costs nothing |
| 9 | Focus-loss autosave dropped | Fires constantly in development, no benefit over the timer |
| 10 | Acceptance criteria revised | The 5 MB criterion could not meaningfully fail |
| 11 | Godot pinned to 4.7.2 standard build | The Mono build hangs in headless mode without a .NET runtime, breaking every CI gate |
| 12 | Steam Deck reclassified as Stage 6 work | Not free; needs controller support, 1280x800, and text legibility |

Endorsed unchanged from the draft: the Elin zone model, the data/render split, string-ID save mapping, chunked data inside bounded zones, the JSON content registry, 32x32 tiles, CI as the enforcement mechanism, and the data-before-persistence-before-rendering ordering.

---

## 14. Roadmap beyond Stage 1

Ordering, not deadlines. Each stage gets its own spec and plan when it is reached.

- **Stage 2 — Building (2-3 months).** Build mode with tile cursor; place and remove terrain, floors, walls, objects. Inventory and a resource economy. Greedy-meshed chunk colliders. Undo/redo — essential for a building game and far easier to add now than later. Blueprint save/load.
- **Stage 3 — Elevation and 2.5D (1-2 months).** Activate `height`. Terraforming, height-aware depth sorting, cliff and slope autotiling, elevation-aware picking, roof fade when indoors. This is the stage that makes it look like Elin.
- **Stage 4 — Zones and expansion (2 months).** World map, multiple zones, transitions, per-zone persistence, one procedural zone type (where seed-plus-diff saving earns its keep). Home zone growth.
- **Stage 5 — Simulation depth (3+ months).** Pick one or two: NPC residents with needs and schedules, farming and livestock, day/night and seasons, crafting stations, visitors and trade. Add one at a time, each fully working.
- **Stage 6 — Release (2-3 months).** GodotSteam, achievements, Steam Cloud. Steam page live **early** — wishlists accumulate over months. Controller support and Steam Deck verification. Settings, key rebinding, localisation scaffolding. Demo for Next Fest, then Early Access.

**A realistic note.** Elin followed Elona, which its developer worked on for roughly 17 years. Cassette Beasts was a funded team. Stage 1 is achievable by one person part-time. Stages 2-6 are a multi-year commitment. Both are fine — but know which one is being signed up for at each decision point, and treat Stage 1 as a complete deliverable in its own right.
