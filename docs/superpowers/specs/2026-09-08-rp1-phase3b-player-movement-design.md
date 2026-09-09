# RP1 — Phase 3b Design: Player, Movement and Collision

**Status:** approved
**Date:** 2026-09-08
**Refines:** `docs/superpowers/specs/2026-08-23-rp1-stage0-stage1-design.md` §7 (Presentation)
**Follows:** Phase 3a (the rendering slice)

---

## 1. Purpose and scope

Phase 3a drew a zone. Nothing moves in it. This phase puts a player in that zone
and lets them walk around it without walking through things.

**The deliverable, stated as a single sentence:** running the project shows the
128x128 debug zone with a character who moves in eight directions under WASD or
the arrow keys, is stopped by water and trees, cannot leave the zone, is followed
by a bounds-limited camera, and sorts correctly in front of and behind oaks.

### 1.1 In scope

- `Walkability`: content definitions -> the `FLAG_WALKABLE` bit
- `CollisionBuilder`: `Chunk` -> `Array[Rect2i]` of blocked runs, cached
- `MovementSystem`: node-free AABB resolution with wall sliding
- `Player`: input, spawning, and writing the resolved position back to world data
- `EntityRenderer`: `EntityStore` rows -> a pool of `Sprite2D`
- `FollowCamera`: follows an entity, snapped to pixels, clamped to zone bounds
- Placeholder character art, the `[input]` action map, and the Y-sorted node tree

### 1.2 Out of scope

The Kenney import, `tools/quantize.gd` and the palette CI gate are **Phase 3c**.
`AnimalSystem` and the data-authored zone are **Phase 4**. Wiring the player into
save and load is **Phase 5** — this phase makes that free, but does not prove it.

Also out: interaction and harvesting (`oak_tree.json` already declares
`harvestable` and nothing reads it), footsteps, audio, UI, menus, autotiling,
chunk streaming, and elevation.

### 1.3 Success criteria

This phase succeeds if walking from any corner of the zone to any other is
possible, is blocked by exactly the tiles the content says are blocking, and is
verified by a headless test rather than by playing.

---

## 2. The central bet

Phase 3a bet that a `TileSet` assembled at runtime from JSON beats one authored
in the editor. This phase bets something narrower: **collision resolution belongs
in the node-free layer, not in Godot's physics engine.**

The Stage 1 design contradicts itself here. §3.2 lists `MovementSystem` in
`src/systems/` with the job "collision resolution against flags". §7 says the
player is a `CharacterBody2D`. Both cannot be true: `CharacterBody2D.move_and_slide()`
*is* collision resolution, and `src/systems/` may not touch a node.

We resolve it in §3.2's favour, and the reason is Stage 1 acceptance criterion #1:

> Walk from any corner of the zone to any other with no collision bugs

Under `move_and_slide()` that sentence is a play-session someone performs and
declares passed. Under a pure function it is a test that runs in CI on every push.
Every other guarantee this project makes — byte-identical round-trips, migration
fixtures, the architecture guard — is mechanical. Collision should be too.

The cost is real and accepted: we write wall-sliding ourselves, and we give up
Godot's physics for any future feature that would have wanted it. For axis-aligned
tile collision that is a small amount of well-understood code, and Stage 2's
building mode has no more need of a physics engine than Stage 1 does.

---

## 3. Architecture

### 3.1 Where the logic lives

| File | Layer | Purpose |
|---|---|---|
| `src/systems/walkability.gd` | node-free | `(chunk, registry)` -> recompute `FLAG_WALKABLE` |
| `src/systems/collision_builder.gd` | node-free | `chunk` -> `Array[Rect2i]`, cached per chunk |
| `src/systems/movement_system.gd` | node-free | `(pos, velocity, delta, ...)` -> resolved position |
| `src/presentation/player.gd` | node | input -> `MovementSystem` -> the entity row |
| `src/presentation/entity_renderer.gd` | node | entity rows -> pooled `Sprite2D` |
| `src/presentation/camera.gd` | node | `Camera2D` following an entity id |

`player.gd` owns **no position of its own**. It reads input, asks `MovementSystem`
for a resolved position, and writes it into the `EntityStore` row. The renderer,
the camera and Phase 5's save all read that same row. One source of truth, and the
layer rule holds: presentation reads world data and writes only through the store's
own API.

One frame:

```
_physics_process(delta)
  player.gd    input actions -> direction, normalized, x speed
               -> MovementSystem.move(row.pos, vel, delta, body, solids, bounds)
               -> entities.set_position(id, resolved)
               -> entities.set_facing(id, MovementSystem.facing_from(vel, facing))

_process(delta)
  zone_renderer     repaints dirty chunks (Phase 3a, unchanged)
  entity_renderer   every row -> sprite.position = pos * TILE_SIZE
  camera            global_position = player row position * TILE_SIZE
```

### 3.2 Entity positions are in tile units

`EntityStore.x` and `y` are `PackedFloat32Array`, documented as "sub-tile world
position". The design never says of what. This phase pins it: **one unit is one
tile.** The player at `(40.5, 40.5)` stands at the centre of tile `(40, 40)`.

The alternative — pixels — bakes a presentation constant into persisted world
data. Tile size is 32, and §7.1 files that under *Presentation* art constants. If
positions were pixels, changing tile size would rewrite every save file, and the
data layer would know how big a tile is on screen. In tile units it does not, and
`EntityRenderer` and `Camera2D` multiply by `TILE_SIZE` at the boundary, which is
precisely where presentation is supposed to read from world data.

It costs some awkwardness at the edges: the player's body is `0.625 x 0.5` tiles
rather than `20 x 16` pixels, and speed reads as `4.5` tiles/sec rather than `144`
px/sec. In exchange the movement tests read in the same units as the collision
data they run against.

### 3.3 `Walkability` — `src/systems/walkability.gd`

```gdscript
## Derives the FLAG_WALKABLE bit from content definitions.
##
## The composite rule lives here and nowhere else:
##   walkable = terrain.walkable AND NOT object.blocks_movement
##
## Note the two vocabularies. Terrain declares `walkable` and objects declare
## `blocks_movement` -- different names, opposite polarity. That asymmetry is
## in the content schemas already; this is the one place that reconciles it.
static func recompute_chunk(chunk: Chunk, registry: ContentRegistry) -> int
static func recompute_zone(zone: Zone, registry: ContentRegistry) -> int
```

Both return the number of tiles whose flag changed, which is what makes the
staleness test possible: recompute a zone that is already correct and assert zero.

The bit is set or cleared **without disturbing the rest of the byte** —
`blocks_light` shares it and is reserved for Stage 3.

| Case | Result | Reason |
|---|---|---|
| terrain def omits `walkable` | walkable | Optional in the schema; impassable ground should be deliberate |
| object def omits `blocks_movement` | does not block | Same reasoning, inverted polarity |
| object id is `0` (`ID_UNKNOWN`) | does not block | `0` means "empty cell", not "unknown thing" |
| id is a load-time placeholder | **does not block** | Stage 1 design §6.4 point 3, verbatim |
| terrain id is `0` | not walkable | Unpainted void is not floor |

The placeholder row is not a judgement call — §6.4 already decided it. A player
walled in by content they cannot see is a worse failure than one who walks through
a gap where a mod used to be.

### 3.4 `CollisionBuilder` — `src/systems/collision_builder.gd`

```gdscript
## Merges blocked tiles into rectangles. Per-tile shapes are never used:
## a 32x32 chunk of solid tiles would be 1024 of them.
##
## Stage 1 merges runs within a row and stops there. Stage 2 replaces the
## body of this function with greedy meshing behind the same signature.
##
## Rects are in WORLD tile coordinates -- the chunk knows its own coords, and
## every caller wants world space -- and are emitted in row-major order so
## tests can assert on exact output.
func rects_for_chunk(chunk: Chunk) -> Array[Rect2i]
func solids_near(zone: Zone, area: Rect2) -> Array[Rect2i]  ## area in tile units
func invalidate(chunk_coord: Vector2i) -> void
```

An instance rather than pure statics, because it caches: rebuilding 1024 tiles
per chunk at 60 Hz is not affordable, and the cache is per-zone state that has to
live somewhere. `RefCounted`, so the guard is satisfied and the cache is directly
testable.

**A deliberate non-decision.** `ZoneRenderer.refresh_dirty()` *consumes and clears*
the zone's dirty flags. A collision cache keyed off the same flags would race it —
whichever consumer ran second would see nothing to do. So invalidation here is an
explicit call, not a subscription. Nothing mutates the debug zone during play, so
this costs nothing in 3b. Phase 4 introduces zone mutation and owns the decision
about a proper multi-consumer dirty channel. Recorded rather than discovered.

### 3.5 `MovementSystem` — `src/systems/movement_system.gd`

```gdscript
## Resolves a desired move against solid rectangles. Pure: same inputs,
## same output, no engine state, no physics tick, no display server.
##
## Every argument is in tile units, matching §3.2: `body` is the collision
## box size in tiles anchored bottom-centre on `pos` (see the anchor note
## below), and `bounds` is the zone rect in tiles. `solids` comes from
## CollisionBuilder already in world tile coordinates.
static func move(pos: Vector2, velocity: Vector2, delta: float,
                 body: Vector2, solids: Array[Rect2i], bounds: Rect2) -> Vector2

## Eight octants, 0 = south, counter-clockwise. Takes the current facing so
## that releasing every key holds the last direction rather than snapping to
## a default -- which is what makes persisting `facing` in Phase 5 mean
## anything.
static func facing_from(velocity: Vector2, current: int) -> int
```

**Axis-separated, not swept.** Move on X and push out of any overlap along X;
then move on Y and push out along Y. This is the standard approach for
axis-aligned tile collision and it produces wall-sliding as a side effect —
walking diagonally into a wall slides you along it. A true swept AABB is more
code and more edge cases for no behavioural gain at these speeds.

**Tunnelling is bounded by construction.** At 4.5 tiles/sec on a 60 Hz tick a step
is 0.075 tiles against a body whose smaller dimension is 0.5 tiles — a margin of
about 6.7x. A frame spike erases it. Note the precise failure: a body that lands
*inside* a wall is still pushed out correctly, so tunnelling requires clearing the
far side entirely, which at this body width takes a step over 1.125 tiles — a hitch
of roughly half a second. So `move()` **substeps**, splitting the move so no single
step exceeds half the body's smaller dimension (0.25 tiles). Correctness then depends on the body size, which we
control, rather than on the frame rate, which we do not.

**Position is the feet point**, the bottom-centre of a `0.625 x 0.5` tile box
(20 x 16 px). The sprite is 32 x 64; a body that size could not walk between two
trees the character visually fits between. Anchoring at the feet also makes the
Y-sort key the position's `y` with no offset arithmetic anywhere.

**Zone edges** come in through `bounds`, which clamps the body inside the zone
rect. Cheaper and far more obvious than synthesising four perimeter wall rects.

### 3.6 `Player` — `src/presentation/player.gd`

Reads the four input actions into a direction vector, normalizes it so diagonals
carry no speed bonus, multiplies by `@export var speed: float = 4.5` (tiles per
second — the figure §3.5's tunnelling bound is calculated against), and hands the
result to `MovementSystem`. It holds the entity id, not a position.

Movement runs in `_physics_process`, not `_process`: a fixed timestep keeps the
substepping bound meaningful and keeps behaviour identical between a 60 Hz and a
144 Hz machine.

**Spawning searches.** The player asks for a spawn tile and walks outward in rings
until it finds a walkable one. Zone centre `(64.5, 64.5)` happens to be clear in
today's debug zone, but a hardcoded spawn is exactly what Phase 4's authored zone
breaks silently — the character appears inside a tree and cannot move, with no
error anywhere. The search is roughly fifteen lines.

### 3.7 `EntityRenderer` — `src/presentation/entity_renderer.gd`

A `Sprite2D` pool reused by index, hidden rather than freed when the entity count
drops. Each `_process`: walk `entities.ids()`, ensure a sprite, set its texture,
set `position = pos * TILE_SIZE`.

**Textures are cached by numeric type id.** One `load()` per type for the life of
the run, guarded by `ResourceLoader.exists()` first — the pattern
`tileset_builder.gd:49` established, and for the same reason: `load()` on a missing
path pushes an engine-level error rather than returning null. **Failures are cached
too**, so a missing PNG logs once instead of sixty times a second.

**The anchor is derived from geometry, not authored.** With `centred = true` and
`offset.y = -h / 2`, the texture's bottom edge lands on the entity position — the
feet. A 32x64 player and a 32x32 rabbit both stand correctly with no content field
and no per-type tuning. This is the principle commit `ad8956c` established when it
replaced a hand-authored `y_offset` with geometry in the tileset builder.

### 3.8 `FollowCamera` — `src/presentation/camera.gd`

Named `FollowCamera` rather than `Camera`: a bare `Camera` risks colliding with
engine-reserved names.

`Camera2D` following an entity id. `zoom` is an `@export` defaulting to `2.0`:
1280x720 at 2x shows 20 x 11.25 tiles, which frames a 128x128 zone as a place you
move through rather than a map you survey. Limits run from `(0, 0)` to
`zone.size_tiles * TILE_SIZE`.

Position smoothing is **off** for Stage 1. Combined with pixel snapping it
produces sub-pixel jitter, and crisp beats smooth at this resolution. Two project
settings go in alongside: `snap_2d_transforms_to_pixel` and
`snap_2d_vertices_to_pixel`.

---

## 4. Y-sorting

This is the one part of the phase that cannot be asserted headless, and the one
most likely to be quietly wrong.

Godot sorts the **direct children** of a y-sorted node. Phase 3a set
`y_sort_enabled` on `ObjectLayer` with the comment "must sort against the player",
but as the tree stands that comment is aspirational: if `EntityRenderer` were a
plain sibling of `ZoneRenderer`, the whole `ZoneRenderer` subtree would sort as a
*single item* at its own `y = 0`, and every entity would draw in front of every
object tile. The player would never pass behind a tree.

Nested y-sorted nodes flatten into the parent's sort, so all of the following
must hold:

```
Main                y_sort_enabled = true      <- new in 3b
  ZoneRenderer      y_sort_enabled = true      <- new in 3b (3a left it false)
    TerrainLayer    y_sort off, z_index = -1
    FloorLayer      y_sort off, z_index = -1
    ObjectLayer     y_sort_enabled = true      <- 3a already set this
  EntityRenderer    y_sort_enabled = true      <- new in 3b
    Sprite2D pool
```

The explicit `z_index = -1` on terrain and floor is belt-and-braces. Without it
those layers sort as single items at `y = 0` and stay behind everything only by a
tie-break on tree order, which is not a thing to depend on.

Draw order is a rendering outcome, not node state, so the definition of done
carries a **screenshot check** via the existing `tools/screenshot.gd` (§8.3): the
player standing one tile above an oak renders behind it, one tile below renders in
front. If 4.7.2 does not flatten as expected, the fallback is a dedicated sorted
parent holding `ObjectLayer` and `EntityRenderer` together, with terrain and floor
outside it.

---

## 5. Content and assets

`data/creature/player.json` reuses the existing **`creature`** category rather than
introducing a `character` one. A new category needs a new schema and a schema
validation test per `CLAUDE.md`, and buys nothing this phase; `wander_radius` and
`flees_player` are optional and simply absent.

Two placeholder sprites are generated by `tools/make_placeholder_art.gd`:
`player.png` at 32x64 and `rabbit.png` at 32x32.

**The rabbit sprite fixes a live bug.** `data/creature/rabbit.json` points at
`res://assets/characters/rabbit.png` and that directory does not exist.
`TilesetBuilder` skips creatures — "creatures are entities, not cells" — so nothing
has ever tried to load it. `EntityRenderer` is the first thing that will.

`assets/characters/LICENSE.txt` and rows in `assets/CREDITS.md` are written at
import time, per the standing rule.

Both files are off-palette debug swatches, so **`docs/palette.md`'s exemption list
is updated in the same commit.** It currently names exactly three files by path.
That list has to stay accurate or the palette gate in Phase 3c goes red on files it
was never told to skip.

`project.godot` gains an `[input]` section — `move_up`, `move_down`, `move_left`,
`move_right`, each bound to both WASD and the arrow keys. There is no `[input]`
section today.

---

## 6. Testing

`tests/test_walkability.gd`
: every row of the §3.3 table, plus a case asserting `blocks_light` survives a
  recompute, plus the staleness case — recompute an already-correct zone and
  assert zero tiles changed.

`tests/test_collision_builder.gd`
: empty chunk -> no rects; fully blocked chunk -> exactly 32; a row broken into
  runs -> correct rects; world-coordinate offset applied for a non-origin chunk;
  row-major determinism; `invalidate()` forces a rebuild.

`tests/test_movement_system.gd`
: free movement; head-on block; diagonal slide along a wall; an inside corner;
  substepping a spike-sized delta (the tunnelling guard); the bounds clamp at all
  four edges; `facing_from` across all eight octants; facing held on zero velocity.

All three run headless with no physics tick and no display server, which is the
entire point of §2.

`tools/smoke.gd` gains: spawn the player, step toward a tree and assert the
position stops; step toward open grass and assert it advances; assert
`EntityRenderer` produced at least one visible sprite. **Each new assertion is
mutated and seen to fail before it is trusted**, as all seven of 3a's were.

---

## 7. Acceptance criteria

- [ ] WASD and the arrow keys move the player in eight directions, diagonals normalized
- [ ] The player cannot enter the pond or a tree tile, and slides along an edge rather than sticking
- [ ] The player cannot leave the zone at any of the four edges
- [ ] The camera follows and clamps at all four bounds without jitter
- [ ] Screenshot: the player renders behind an oak from above, in front from below
- [ ] `EntityRenderer` draws the player, and `rabbit.png` resolves
- [ ] `./tools/run_tests.sh` green, including the three new test files
- [ ] `tools/guard.gd` green — all three new `systems/` files node-free
- [ ] `tools/smoke.gd` green with the new assertions, each seen to fail
- [ ] The exported build loads content, renders, and spawns the player
- [ ] `docs/palette.md` exemptions and `assets/CREDITS.md` updated at import time
- [ ] No new file over roughly 300 lines (§3.2)

---

## 8. CI

No new gates. Gate 1 picks up three test files, gate 2 guards three new
`systems/` files, gate 3 gains the movement assertions, gate 4 sees a new
`assets/characters/LICENSE.txt`, and gate 5's exported-build check gains a line
asserting the player spawned.

Gate 5 is worth restating. It exists because the export can succeed while the PCK
silently omits `data/` or the textures — a build that runs and shows nothing. A
player that fails to spawn in an exported build fails the same way, so it is
asserted in the same place.

---

## 9. Risks

| Risk | Mitigation |
|---|---|
| Y-sort flattening misbehaves in 4.7.2 | Screenshot check in the DoD. Fallback: a dedicated sorted parent holding `ObjectLayer` and `EntityRenderer`, terrain and floor outside |
| Axis-separated resolution feels sticky on corners | Body size is tunable; an inside corner is in the test list. Feel is judged by playing, not asserted |
| The collision cache goes stale once zones mutate | Explicit `invalidate()` in 3b; Phase 4 owns the multi-consumer dirty channel, recorded in §3.4 rather than left to be discovered |
| Player-as-entity strains when inventory arrives | Accepted. Stage 2 revisits; the row stays the position source either way |
| Placeholder character art survives to release | Flat and deliberately ugly, listed in `docs/palette.md`'s exemptions, deleted in 3c |

---

## 10. Corrections to the Stage 1 design

`CLAUDE.md` requires reading the Stage 1 design before changing architecture, so
it cannot be left saying things this phase decided against. Three edits land in
the same commit as this spec.

| § | Said | Now says |
|---|---|---|
| §7 | "`Player` is a `CharacterBody2D`" | A thin `Node`; resolution runs in node-free `MovementSystem`. `Node` rather than `Node2D` because `Player` draws nothing and owns no transform of its own. |
| §7 | `Chunk -> Array[Rect2i]` | Same signature; rects in world tile coords, builder is a cached instance |
| §10 | Phase 3 = renderer + player + camera + Kenney; Phase 4 = collision + `EntityRenderer` | 3a = renderer; 3b = player, camera, collision, `EntityRenderer`; 3c = Kenney + palette tooling; Phase 4 = authored zone + `AnimalSystem` |

One addition rather than a correction: **§4.4 gains a sentence pinning `x` and `y`
to tile units.** It says "sub-tile world position" and never says of what.

§3.2 called this right all along — it listed `MovementSystem` as "collision
resolution against flags" while §7 said `CharacterBody2D`. The contradiction is
resolved in §3.2's favour.

---

## 11. What Phase 3c inherits

A zone that can be walked around, with collision derived from content rather than
authored, and movement covered by tests that run without a display server. Phase
3c replaces the debug swatches with the Kenney tileset, adds `tools/quantize.gd`
and the palette gate, and deletes every placeholder this phase and 3a generated —
including the two character sprites, whose exemption entries are already written
down waiting for it.
