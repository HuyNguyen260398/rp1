# Phase 3b — Player, Movement and Collision Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Put a player in the Phase 3a debug zone who moves in eight directions, is stopped by water and trees, cannot leave the zone, is followed by a bounds-limited camera, and sorts correctly against oaks.

**Architecture:** Three node-free modules in `src/systems/` do all the thinking — `Walkability` derives the `FLAG_WALKABLE` bit from content, `CollisionBuilder` merges blocked tiles into rectangles, and `MovementSystem` resolves an AABB against them with wall sliding. Three thin nodes in `src/presentation/` do the rest: `Player` reads input, `EntityRenderer` pools sprites, `FollowCamera` follows. The player owns no position of its own — it lives in an `EntityStore` row, so the renderer, the camera and Phase 5's save all read one source of truth.

**Tech Stack:** Godot 4.7.2 stable (standard build, not Mono), GDScript with static typing throughout, GUT for tests.

**Spec:** `docs/superpowers/specs/2026-09-08-rp1-phase3b-player-movement-design.md`

## Global Constraints

- Godot **4.7.2**, standard build. Invoke it only through `./tools/godot.sh`. Never hardcode a binary path.
- GDScript only. Static typing everywhere: `var x: int = 0`, `func f(a: Vector2i) -> void:`.
- `src/core/` and `src/systems/` **MUST NOT reference Godot nodes.** No `extends Node`, no `get_tree()`, no `Engine.`, no `.tscn`, no `add_child(`, no `get_node(`, no `queue_free(`. These folders extend `RefCounted` only. Enforced by `tools/guard.gd`.
- **Entity positions are in tile units, not pixels.** An entity at `(40.5, 40.5)` stands at the centre of tile `(40, 40)`. Presentation multiplies by `TILE_SIZE` at the boundary and nowhere else.
- Tile size is **32x32**. Character sprites are 32x64. Texture filter is `Nearest`, project-wide; never override per-texture.
- Presentation reads world data and never writes it, except through `EntityStore`'s own API.
- All game content lives in `data/*.json`. Never `match` over content types — look it up in `ContentRegistry`.
- Run tests with `./tools/run_tests.sh` — never call `gut_cmdln.gd` directly. The runner does a mandatory `--import` pass first.
- TDD: write the failing test, watch it fail, implement minimally, watch it pass.
- Commits use conventional prefixes: `feat:`, `test:`, `ci:`, `docs:`, `fix:`.
- Every folder directly under `assets/` needs a `LICENSE.txt`. Record every pack in `assets/CREDITS.md` at import time.
- End every commit message with:
  ```
  Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
  ```

### Ticking checkboxes in this plan

`tools/mark_task_done.py` defaults to a glob that matches only the Phases 0-2 plan. For this plan you **must** pass `--plan` explicitly:

```bash
python3 tools/mark_task_done.py <task-number> --plan docs/superpowers/plans/2026-09-08-rp1-phase3b-player-movement.md
```

Never tick checkboxes by hand.

### A note on `load()` and `ResourceLoader`

`CLAUDE.md` forbids `load()`, `ResourceLoader` and `.tres`/`.res` **for save data**, because a resource file can name a script path and loading one executes code. That rule is about the save system.

Loading a **texture named by a content definition** is a different thing and is required here. `ResourceLoader.exists()` followed by `load()` is correct and expected in `EntityRenderer`, exactly as `src/systems/tileset_builder.gd:49` already does it. Do not route texture loading through `FileAccess`.

### The phase that deletes the placeholders is now 3c, not 3b

Phase 3a's art, licences and docs say the debug swatches are "deleted in Phase 3b". The Phase 3 split moved that to **Phase 3c**. Task 1 corrects those strings. If you see "deleted in Phase 3b" anywhere after Task 1, it is a miss.

---

## File Structure

| File | Responsibility |
|---|---|
| `tools/make_placeholder_art.gd` | Gains two character swatches (modified) |
| `assets/characters/player.png` | 32x64 debug swatch |
| `assets/characters/rabbit.png` | 32x32 debug swatch — fixes a dangling reference |
| `assets/characters/LICENSE.txt` | New folder; the licence gate checks every top-level `assets/` folder |
| `assets/CREDITS.md` | New row, and the 3b/3c correction (modified) |
| `docs/palette.md` | Exemption list gains two files (modified) |
| `src/systems/walkability.gd` | `Walkability`: content -> `FLAG_WALKABLE` |
| `src/systems/collision_builder.gd` | `CollisionBuilder`: `Chunk` -> `Array[Rect2i]`, cached |
| `src/systems/movement_system.gd` | `MovementSystem`: AABB resolution, sliding, facing |
| `src/presentation/entity_renderer.gd` | `EntityRenderer`: entity rows -> pooled `Sprite2D` |
| `src/presentation/player.gd` | `Player`: input, spawning, write-back |
| `src/presentation/camera.gd` | `FollowCamera`: follows an entity, clamped to bounds |
| `src/presentation/zone_renderer.gd` | Y-sort and z-index corrections (modified) |
| `src/presentation/main.gd` | Wire-up (modified) |
| `data/creature/player.json` | Player content definition |
| `project.godot` | `[input]` actions and pixel-snap settings (modified) |
| `tests/test_walkability.gd` | Unit tests |
| `tests/test_collision_builder.gd` | Unit tests |
| `tests/test_movement_system.gd` | Unit tests |
| `tools/smoke.gd` | Movement and entity-render assertions (modified) |
| `.github/workflows/ci.yml` | Export gate gains a player assertion (modified) |

`camera.gd` declares `class_name FollowCamera`, not `Camera` — a bare `Camera` risks colliding with engine-reserved names.

---

## Task 1: Character placeholder art and licences

**Files:**
- Modify: `tools/make_placeholder_art.gd`
- Create: `assets/characters/player.png`, `assets/characters/rabbit.png`, `assets/characters/LICENSE.txt`
- Modify: `assets/CREDITS.md`, `assets/tiles/LICENSE.txt`, `assets/objects/LICENSE.txt`, `docs/palette.md`

**Interfaces:**
- Consumes: nothing
- Produces: `res://assets/characters/player.png` (32x64) and `res://assets/characters/rabbit.png` (32x32), both loadable by `ResourceLoader.exists()`

**Why the rabbit sprite is here.** `data/creature/rabbit.json` already points at `res://assets/characters/rabbit.png` and that directory does not exist. `TilesetBuilder` skips creatures, so nothing has ever tried to load it. `EntityRenderer` in Task 7 is the first thing that will.

- [x] **Step 1: Add the two character swatches to the generator**

In `tools/make_placeholder_art.gd`, extend `SWATCHES` and correct the docstring:

```gdscript
## Generates the Phase 3a and 3b debug swatches.
##
## These are NOT art. They are flat blocks in obviously-synthetic colours,
## sized to match what the content JSON declares, and they are deleted
## wholesale when the real tileset is imported in Phase 3c.
##
## Colours are deliberately off-palette: docs/palette.md fixes the palette
## as Apollo and exempts these files by name, precisely so a throwaway
## swatch never gets mistaken for a considered choice.

const SWATCHES: Array[Dictionary] = [
	{"path": "res://assets/tiles/grass.png", "size": Vector2i(32, 32), "color": Color(0.36, 0.60, 0.34)},
	{"path": "res://assets/tiles/water.png", "size": Vector2i(32, 32), "color": Color(0.25, 0.45, 0.72)},
	{"path": "res://assets/objects/oak_tree.png", "size": Vector2i(32, 48), "color": Color(0.45, 0.32, 0.22)},
	{"path": "res://assets/characters/player.png", "size": Vector2i(32, 64), "color": Color(0.82, 0.36, 0.58)},
	{"path": "res://assets/characters/rabbit.png", "size": Vector2i(32, 32), "color": Color(0.86, 0.81, 0.74)},
]
```

Then make the directory creation cover the new folder:

```gdscript
func _init() -> void:
	DirAccess.make_dir_recursive_absolute("res://assets/objects")
	DirAccess.make_dir_recursive_absolute("res://assets/characters")
```

- [x] **Step 2: Run the generator**

```bash
./tools/godot.sh --headless --path . -s tools/make_placeholder_art.gd
```

Expected: five `wrote res://assets/...` lines, including `player.png (32x64)` and `rabbit.png (32x32)`.

- [x] **Step 3: Import the new PNGs**

```bash
./tools/godot.sh --headless --path . --import
```

Expected: exits 0, and `assets/characters/player.png.import` and `rabbit.png.import` now exist.

- [x] **Step 4: Write the licence file**

Create `assets/characters/LICENSE.txt`:

```
Source: generated by tools/make_placeholder_art.gd
Author: this project
Licence: project-owned placeholder art, no third-party rights

These are flat debug swatches, not artwork. They exist so the entity
renderer has something to draw before real character art is imported in
Phase 3c, at which point they are deleted and this file is replaced with
the real pack's source, author and licence.
```

- [x] **Step 5: Correct the two existing licence files**

In both `assets/tiles/LICENSE.txt` and `assets/objects/LICENSE.txt`, change `imported in Phase 3b` to `imported in Phase 3c`. The phase that deletes them moved when Phase 3 was split.

- [x] **Step 6: Record the pack in CREDITS.md**

In `assets/CREDITS.md`, add a row to the Packs table and correct the note above it:

```markdown
_No third-party packs yet. The entries below are project-generated
placeholders, deleted when the first real tileset is imported in Phase 3c._

| Pack | Author | Source | Licence |
|---|---|---|---|
| Phase 3a debug swatches (tiles) | this project | `tools/make_placeholder_art.gd` | project-owned placeholder |
| Phase 3a debug swatches (objects) | this project | `tools/make_placeholder_art.gd` | project-owned placeholder |
| Phase 3b debug swatches (characters) | this project | `tools/make_placeholder_art.gd` | project-owned placeholder |
```

- [x] **Step 7: Update the palette exemption list**

In `docs/palette.md`, replace the exemption paragraph so it names all five files. The palette gate lands in Phase 3c and will fail on any off-palette file it was not told to skip:

```markdown
### Exemption: the Phase 3a and 3b debug swatches

`assets/tiles/grass.png`, `assets/tiles/water.png`,
`assets/objects/oak_tree.png`, `assets/characters/player.png` and
`assets/characters/rabbit.png` are deliberately **off-palette**. They are flat
debug swatches generated by `tools/make_placeholder_art.gd`, they exist only so
the renderer has something to draw before real art arrives, and they are
deleted in Phase 3c.
```

Also change the two `| Phase 3b |` status cells in the enforcement table at the top of §1 to `| Phase 3c |` — `tools/quantize.gd` and `tools/check_palette.sh` moved with the split.

- [x] **Step 8: Run the licence gate**

```bash
./tools/check_asset_licences.sh
```

Expected: `Asset licences: OK`

- [x] **Step 9: Commit**

```bash
git add tools/make_placeholder_art.gd assets/ docs/palette.md
git commit -m "$(cat <<'EOF'
feat: add Phase 3b placeholder character art

Adds a 32x64 player swatch and a 32x32 rabbit swatch. The rabbit fixes a
dangling reference: data/creature/rabbit.json has always pointed at
res://assets/characters/rabbit.png, and that directory never existed.
TilesetBuilder skips creatures, so nothing had tried to load it.

Also corrects the phase that deletes these placeholders from 3b to 3c
across the licence files, CREDITS.md and the palette exemption list.
Splitting Phase 3 moved the art pipeline into 3c, and the palette gate
lands there -- it fails on any off-palette file it was not told to skip.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: `Walkability` — deriving the flag from content

**Files:**
- Create: `src/systems/walkability.gd`
- Test: `tests/test_walkability.gd`

**Interfaces:**
- Consumes: `Chunk.get_terrain(Vector2i) -> int`, `Chunk.get_object(Vector2i) -> int`, `Chunk.get_flags(Vector2i) -> int`, `Chunk.set_flags(Vector2i, int)`, `Chunk.FLAG_WALKABLE`, `Chunk.FLAG_BLOCKS_LIGHT`, `ContentRegistry.def_of(int) -> Dictionary`, `ContentRegistry.is_placeholder(int) -> bool`, `ContentRegistry.ID_UNKNOWN`, `Zone.chunk_coords() -> Array[Vector2i]`, `Zone.get_chunk(Vector2i) -> Chunk`
- Produces: `Walkability.recompute_chunk(chunk: Chunk, registry: ContentRegistry) -> int` and `Walkability.recompute_zone(zone: Zone, registry: ContentRegistry) -> int`, both returning the count of tiles whose flag changed

- [x] **Step 1: Write the failing test**

Create `tests/test_walkability.gd`:

```gdscript
extends GutTest

var _r: ContentRegistry
var _grass: int
var _water: int
var _oak: int
var _chunk: Chunk


func before_each() -> void:
	_r = ContentRegistry.new()
	_grass = _r.register({"id": "grass", "category": "terrain", "display_name": "Grass",
		"sprite": "res://none.png", "walkable": true})
	_water = _r.register({"id": "water", "category": "terrain", "display_name": "Water",
		"sprite": "res://none.png", "walkable": false})
	_oak = _r.register({"id": "oak", "category": "object", "display_name": "Oak",
		"sprite": "res://none.png", "blocks_movement": true})
	_chunk = Chunk.new(Vector2i(0, 0))


func test_walkable_terrain_sets_the_flag() -> void:
	_chunk.set_terrain(Vector2i(1, 1), _grass)
	Walkability.recompute_chunk(_chunk, _r)
	assert_true(_chunk.is_walkable(Vector2i(1, 1)))


func test_unwalkable_terrain_clears_the_flag() -> void:
	_chunk.set_terrain(Vector2i(1, 1), _water)
	Walkability.recompute_chunk(_chunk, _r)
	assert_false(_chunk.is_walkable(Vector2i(1, 1)))


func test_a_blocking_object_overrides_walkable_terrain() -> void:
	_chunk.set_terrain(Vector2i(2, 2), _grass)
	_chunk.set_object(Vector2i(2, 2), _oak)
	Walkability.recompute_chunk(_chunk, _r)
	assert_false(_chunk.is_walkable(Vector2i(2, 2)), "grass under an oak is not walkable")


func test_terrain_missing_walkable_defaults_to_walkable() -> void:
	var path: int = _r.register({"id": "path", "category": "terrain",
		"display_name": "Path", "sprite": "res://none.png"})
	_chunk.set_terrain(Vector2i(3, 3), path)
	Walkability.recompute_chunk(_chunk, _r)
	assert_true(_chunk.is_walkable(Vector2i(3, 3)), "optional in the schema, so absent means walkable")


func test_object_missing_blocks_movement_defaults_to_passable() -> void:
	var flower: int = _r.register({"id": "flower", "category": "object",
		"display_name": "Flower", "sprite": "res://none.png"})
	_chunk.set_terrain(Vector2i(4, 4), _grass)
	_chunk.set_object(Vector2i(4, 4), flower)
	Walkability.recompute_chunk(_chunk, _r)
	assert_true(_chunk.is_walkable(Vector2i(4, 4)))


func test_object_id_zero_is_empty_not_unknown() -> void:
	_chunk.set_terrain(Vector2i(5, 5), _grass)
	_chunk.set_object(Vector2i(5, 5), ContentRegistry.ID_UNKNOWN)
	Walkability.recompute_chunk(_chunk, _r)
	assert_true(_chunk.is_walkable(Vector2i(5, 5)), "id 0 means empty cell, not unknown thing")


func test_terrain_id_zero_is_not_floor() -> void:
	Walkability.recompute_chunk(_chunk, _r)
	assert_false(_chunk.is_walkable(Vector2i(6, 6)), "unpainted void is not walkable")


func test_a_placeholder_object_never_blocks() -> void:
	# Stage 1 design 6.4 point 3: an unknown id is non-blocking for movement.
	var ghost: int = _r.register_placeholder("mod:removed_statue")
	_chunk.set_terrain(Vector2i(7, 7), _grass)
	_chunk.set_object(Vector2i(7, 7), ghost)
	Walkability.recompute_chunk(_chunk, _r)
	assert_true(_chunk.is_walkable(Vector2i(7, 7)), "content you cannot see must not wall you in")


func test_blocks_light_survives_a_recompute() -> void:
	_chunk.set_terrain(Vector2i(8, 8), _grass)
	_chunk.set_flags(Vector2i(8, 8), Chunk.FLAG_BLOCKS_LIGHT)
	Walkability.recompute_chunk(_chunk, _r)
	var flags: int = _chunk.get_flags(Vector2i(8, 8))
	assert_true((flags & Chunk.FLAG_BLOCKS_LIGHT) != 0, "the other bit shares this byte")
	assert_true((flags & Chunk.FLAG_WALKABLE) != 0)


func test_recomputing_a_correct_chunk_changes_nothing() -> void:
	_chunk.set_terrain(Vector2i(9, 9), _grass)
	Walkability.recompute_chunk(_chunk, _r)
	assert_eq(Walkability.recompute_chunk(_chunk, _r), 0, "the staleness guard")


func test_recompute_zone_covers_every_chunk() -> void:
	var z: Zone = Zone.new("t", Vector2i(64, 64))
	z.set_terrain(Vector2i(1, 1), _grass)
	z.set_terrain(Vector2i(40, 40), _water)
	Walkability.recompute_zone(z, _r)
	assert_true(z.is_walkable(Vector2i(1, 1)))
	assert_false(z.is_walkable(Vector2i(40, 40)))
```

- [x] **Step 2: Run the test to verify it fails**

```bash
./tools/run_tests.sh
```

Expected: FAIL — GUT reports `Walkability` is not declared.

- [x] **Step 3: Write the implementation**

Create `src/systems/walkability.gd`:

```gdscript
class_name Walkability
extends RefCounted
## Derives the FLAG_WALKABLE bit from content definitions.
##
## The composite rule lives here and nowhere else:
##
##   walkable = terrain.walkable AND NOT object.blocks_movement
##
## Note the two vocabularies. Terrain declares `walkable` and objects declare
## `blocks_movement` -- different names, opposite polarity. That asymmetry is
## already in the content schemas; this is the one place that reconciles it.
##
## Both functions return the number of tiles whose flag CHANGED, which is what
## makes the staleness guard testable: recompute an already-correct chunk and
## expect zero.


static func recompute_chunk(chunk: Chunk, registry: ContentRegistry) -> int:
	var changed: int = 0
	for y: int in range(Coords.CHUNK_SIZE):
		for x: int in range(Coords.CHUNK_SIZE):
			var l: Vector2i = Vector2i(x, y)
			var walkable: bool = _tile_is_walkable(chunk, l, registry)
			var flags: int = chunk.get_flags(l)
			if ((flags & Chunk.FLAG_WALKABLE) != 0) == walkable:
				continue
			# Set or clear one bit. FLAG_BLOCKS_LIGHT shares this byte and
			# must survive untouched.
			if walkable:
				flags |= Chunk.FLAG_WALKABLE
			else:
				flags &= ~Chunk.FLAG_WALKABLE
			chunk.set_flags(l, flags)
			changed += 1
	return changed


static func recompute_zone(zone: Zone, registry: ContentRegistry) -> int:
	var changed: int = 0
	for c: Vector2i in zone.chunk_coords():
		changed += recompute_chunk(zone.get_chunk(c), registry)
	return changed


static func _tile_is_walkable(chunk: Chunk, l: Vector2i, registry: ContentRegistry) -> bool:
	var terrain: int = chunk.get_terrain(l)
	# Unpainted void is not floor. Content id 0 is ID_UNKNOWN, meaning the
	# cell was never painted -- not that something unknown stands there.
	if terrain == ContentRegistry.ID_UNKNOWN:
		return false
	# A placeholder is content the build cannot see. Stage 1 design 6.4
	# point 3 makes it non-blocking: walking through a gap where a mod used
	# to be beats being walled in by something invisible.
	if not registry.is_placeholder(terrain):
		if not bool(registry.def_of(terrain).get("walkable", true)):
			return false

	var obj: int = chunk.get_object(l)
	if obj == ContentRegistry.ID_UNKNOWN or registry.is_placeholder(obj):
		return true
	return not bool(registry.def_of(obj).get("blocks_movement", false))
```

- [x] **Step 4: Run the tests to verify they pass**

```bash
./tools/run_tests.sh
```

Expected: PASS, eleven new tests.

- [x] **Step 5: Run the architecture guard**

```bash
./tools/godot.sh --headless --path . -s tools/guard.gd
```

Expected: `Architecture guard: clean`

- [x] **Step 6: Commit**

```bash
git add src/systems/walkability.gd tests/test_walkability.gd
git commit -m "$(cat <<'EOF'
feat: derive the walkable flag from content definitions

Reconciles the two vocabularies the content schemas already use: terrain
declares `walkable` and objects declare `blocks_movement`, different names
with opposite polarity. The composite rule lives in exactly one place.

A placeholder never blocks, per Stage 1 design 6.4 point 3. Being walled
in by content you cannot see is a worse failure than walking through a gap
where a mod used to be.

Returns the number of tiles changed so the staleness guard is testable:
recompute an already-correct chunk and expect zero.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: `CollisionBuilder` — flags to rectangles

**Files:**
- Create: `src/systems/collision_builder.gd`
- Test: `tests/test_collision_builder.gd`

**Interfaces:**
- Consumes: `Chunk.is_walkable(Vector2i) -> bool`, `Chunk.coord`, `Coords.CHUNK_SIZE`, `Coords.chunk_origin(Vector2i) -> Vector2i`, `Coords.world_to_chunk(Vector2i) -> Vector2i`, `Zone.get_chunk(Vector2i) -> Chunk`
- Produces: `CollisionBuilder.new()`, `rects_for_chunk(chunk: Chunk) -> Array[Rect2i]`, `solids_for(zone: Zone, chunk_coord: Vector2i) -> Array[Rect2i]`, `solids_near(zone: Zone, area: Rect2) -> Array[Rect2i]`, `invalidate(chunk_coord: Vector2i) -> void`, `clear() -> void`. All rects are in **world tile coordinates**.

- [x] **Step 1: Write the failing test**

Create `tests/test_collision_builder.gd`:

```gdscript
extends GutTest

var _b: CollisionBuilder


func before_each() -> void:
	_b = CollisionBuilder.new()


func _blocked_chunk(coord: Vector2i) -> Chunk:
	# Every tile starts with FLAG_WALKABLE clear, so a fresh chunk is solid.
	return Chunk.new(coord)


func _open_chunk(coord: Vector2i) -> Chunk:
	var c: Chunk = Chunk.new(coord)
	for y: int in range(Coords.CHUNK_SIZE):
		for x: int in range(Coords.CHUNK_SIZE):
			c.set_flags(Vector2i(x, y), Chunk.FLAG_WALKABLE)
	return c


func test_a_fully_open_chunk_has_no_rects() -> void:
	assert_eq(_b.rects_for_chunk(_open_chunk(Vector2i(0, 0))).size(), 0)


func test_a_fully_blocked_chunk_is_one_rect_per_row() -> void:
	var rects: Array[Rect2i] = _b.rects_for_chunk(_blocked_chunk(Vector2i(0, 0)))
	assert_eq(rects.size(), 32, "row-merge yields 32, not 1024 colliders")
	assert_eq(rects[0], Rect2i(0, 0, 32, 1))


func test_a_run_in_the_middle_of_a_row() -> void:
	var c: Chunk = _open_chunk(Vector2i(0, 0))
	for x: int in range(4, 9):
		c.set_flags(Vector2i(x, 3), 0)
	var rects: Array[Rect2i] = _b.rects_for_chunk(c)
	assert_eq(rects.size(), 1)
	assert_eq(rects[0], Rect2i(4, 3, 5, 1))


func test_two_runs_in_one_row_stay_separate() -> void:
	var c: Chunk = _open_chunk(Vector2i(0, 0))
	c.set_flags(Vector2i(2, 0), 0)
	c.set_flags(Vector2i(5, 0), 0)
	var rects: Array[Rect2i] = _b.rects_for_chunk(c)
	assert_eq(rects.size(), 2)
	assert_eq(rects[0], Rect2i(2, 0, 1, 1))
	assert_eq(rects[1], Rect2i(5, 0, 1, 1))


func test_a_run_reaching_the_chunk_edge_is_closed() -> void:
	var c: Chunk = _open_chunk(Vector2i(0, 0))
	c.set_flags(Vector2i(31, 0), 0)
	var rects: Array[Rect2i] = _b.rects_for_chunk(c)
	assert_eq(rects.size(), 1)
	assert_eq(rects[0], Rect2i(31, 0, 1, 1), "the last column must not be dropped")


func test_rects_are_in_world_coordinates() -> void:
	var c: Chunk = _open_chunk(Vector2i(2, 3))
	c.set_flags(Vector2i(1, 1), 0)
	var rects: Array[Rect2i] = _b.rects_for_chunk(c)
	assert_eq(rects[0], Rect2i(65, 97, 1, 1), "chunk 2,3 starts at world tile 64,96")


func test_rects_come_out_row_major() -> void:
	var c: Chunk = _open_chunk(Vector2i(0, 0))
	c.set_flags(Vector2i(0, 5), 0)
	c.set_flags(Vector2i(0, 1), 0)
	var rects: Array[Rect2i] = _b.rects_for_chunk(c)
	assert_eq(rects[0].position.y, 1, "determinism: tests assert on exact output")
	assert_eq(rects[1].position.y, 5)


func test_a_missing_chunk_is_solid() -> void:
	var z: Zone = Zone.new("t", Vector2i(128, 128))
	var rects: Array[Rect2i] = _b.solids_for(z, Vector2i(0, 0))
	assert_eq(rects.size(), 1)
	assert_eq(rects[0], Rect2i(0, 0, 32, 32), "an unloaded region is not somewhere to walk")


func test_solids_near_gathers_every_overlapped_chunk() -> void:
	var z: Zone = Zone.new("t", Vector2i(128, 128))
	for c: Vector2i in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
		z.install_chunk(_open_chunk(c))
	# A 2x2-tile area straddling the corner where all four chunks meet.
	var rects: Array[Rect2i] = _b.solids_near(z, Rect2(Vector2(31.0, 31.0), Vector2(2.0, 2.0)))
	assert_eq(rects.size(), 0, "all four chunks are open")


func test_invalidate_forces_a_rebuild() -> void:
	var z: Zone = Zone.new("t", Vector2i(128, 128))
	z.install_chunk(_open_chunk(Vector2i(0, 0)))
	assert_eq(_b.solids_for(z, Vector2i(0, 0)).size(), 0)

	z.get_chunk(Vector2i(0, 0)).set_flags(Vector2i(3, 3), 0)
	assert_eq(_b.solids_for(z, Vector2i(0, 0)).size(), 0, "still the cached answer")

	_b.invalidate(Vector2i(0, 0))
	assert_eq(_b.solids_for(z, Vector2i(0, 0)).size(), 1, "rebuilt after invalidation")
```

- [x] **Step 2: Run the test to verify it fails**

```bash
./tools/run_tests.sh
```

Expected: FAIL — `CollisionBuilder` is not declared.

- [x] **Step 3: Write the implementation**

Create `src/systems/collision_builder.gd`:

```gdscript
class_name CollisionBuilder
extends RefCounted
## Merges blocked tiles into rectangles.
##
## Per-tile collision shapes are never used: a 32x32 chunk of solid tiles
## would be 1024 of them. Stage 1 merges runs within a row and stops there;
## Stage 2 replaces the body of rects_for_chunk() with greedy meshing behind
## the same signature.
##
## Rects are in WORLD tile coordinates -- the chunk knows its own coords and
## every caller wants world space -- and are emitted in row-major order so
## tests can assert on exact output.
##
## An instance rather than pure statics because it caches. Rebuilding 1024
## tiles per chunk per frame is not affordable.
##
## Invalidation is an EXPLICIT call, not a subscription to the zone's dirty
## flags: ZoneRenderer.refresh_dirty() already consumes and clears those, so
## a second subscriber would race it and whichever ran second would see
## nothing to do. Nothing mutates a zone during play in Phase 3b. Phase 4
## introduces zone mutation and owns the multi-consumer dirty channel.

var _cache: Dictionary = {}  ## Vector2i chunk coord -> Array[Rect2i]


func rects_for_chunk(chunk: Chunk) -> Array[Rect2i]:
	var out: Array[Rect2i] = []
	var origin: Vector2i = Coords.chunk_origin(chunk.coord)
	for y: int in range(Coords.CHUNK_SIZE):
		var run_start: int = -1
		# One column past the edge, so a run reaching the chunk boundary
		# is closed rather than dropped.
		for x: int in range(Coords.CHUNK_SIZE + 1):
			var blocked: bool = (
				x < Coords.CHUNK_SIZE and not chunk.is_walkable(Vector2i(x, y))
			)
			if blocked and run_start == -1:
				run_start = x
			elif not blocked and run_start != -1:
				out.append(Rect2i(origin.x + run_start, origin.y + y, x - run_start, 1))
				run_start = -1
	return out


func solids_for(zone: Zone, chunk_coord: Vector2i) -> Array[Rect2i]:
	if _cache.has(chunk_coord):
		return _cache[chunk_coord]
	var chunk: Chunk = zone.get_chunk(chunk_coord)
	var rects: Array[Rect2i] = []
	if chunk == null:
		# An unloaded region is solid, matching Walkability's rule that an
		# unpainted tile is not floor. The alternative lets a player walk
		# off into a region that has not been generated.
		var o: Vector2i = Coords.chunk_origin(chunk_coord)
		rects.append(Rect2i(o.x, o.y, Coords.CHUNK_SIZE, Coords.CHUNK_SIZE))
	else:
		rects = rects_for_chunk(chunk)
	_cache[chunk_coord] = rects
	return rects


## Every solid rect in the chunks overlapping `area`, which is in tile units.
func solids_near(zone: Zone, area: Rect2) -> Array[Rect2i]:
	var out: Array[Rect2i] = []
	var lo: Vector2i = Coords.world_to_chunk(
		Vector2i(floori(area.position.x), floori(area.position.y))
	)
	var hi: Vector2i = Coords.world_to_chunk(
		Vector2i(ceili(area.end.x), ceili(area.end.y))
	)
	for cy: int in range(lo.y, hi.y + 1):
		for cx: int in range(lo.x, hi.x + 1):
			out.append_array(solids_for(zone, Vector2i(cx, cy)))
	return out


func invalidate(chunk_coord: Vector2i) -> void:
	_cache.erase(chunk_coord)


func clear() -> void:
	_cache.clear()
```

- [x] **Step 4: Run the tests to verify they pass**

```bash
./tools/run_tests.sh
```

Expected: PASS, ten new tests.

- [x] **Step 5: Run the architecture guard**

```bash
./tools/godot.sh --headless --path . -s tools/guard.gd
```

Expected: `Architecture guard: clean`

- [x] **Step 6: Commit**

```bash
git add src/systems/collision_builder.gd tests/test_collision_builder.gd
git commit -m "$(cat <<'EOF'
feat: merge blocked tiles into collision rectangles

Row-merge per chunk: a fully solid chunk becomes 32 rects rather than 1024
colliders. Stage 2 swaps in greedy meshing behind the same signature.

Rects are in world tile coordinates and row-major, so tests assert on
exact output rather than on a set.

Invalidation is explicit rather than a subscription to the zone's dirty
flags. ZoneRenderer.refresh_dirty() already consumes and clears those, so
a second subscriber would race it. Nothing mutates a zone during play yet;
Phase 4 owns the multi-consumer dirty channel.

An unloaded chunk reads as solid, matching the rule that an unpainted tile
is not floor.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: `MovementSystem` — resolution, sliding and bounds

**Files:**
- Create: `src/systems/movement_system.gd`
- Test: `tests/test_movement_system.gd`

**Interfaces:**
- Consumes: nothing beyond Godot's `Rect2` / `Rect2i`
- Produces: `MovementSystem.body_rect(pos: Vector2, body: Vector2) -> Rect2`, `MovementSystem.clamp_to_bounds(pos: Vector2, body: Vector2, bounds: Rect2) -> Vector2`, `MovementSystem.move(pos: Vector2, velocity: Vector2, delta: float, body: Vector2, solids: Array[Rect2i], bounds: Rect2) -> Vector2`. Every argument is in tile units. Task 5 adds `facing_from` to the same file.

**The anchor.** `pos` is the **feet point**: the bottom-centre of the body box. So a body of `(0.625, 0.5)` at `(4.0, 3.0)` spans x from `3.6875` to `4.3125` and y from `2.5` to `3.0`.

- [x] **Step 1: Write the failing test**

Create `tests/test_movement_system.gd`:

```gdscript
extends GutTest

const BODY: Vector2 = Vector2(0.625, 0.5)
const BOUNDS: Rect2 = Rect2(Vector2.ZERO, Vector2(32.0, 32.0))
const TICK: float = 1.0 / 60.0

var _none: Array[Rect2i] = []


func test_body_is_anchored_at_the_feet() -> void:
	var r: Rect2 = MovementSystem.body_rect(Vector2(4.0, 3.0), BODY)
	assert_almost_eq(r.position.x, 3.6875, 0.0001)
	assert_almost_eq(r.position.y, 2.5, 0.0001)
	assert_almost_eq(r.end.y, 3.0, 0.0001, "pos.y is the bottom edge")


func test_unobstructed_movement_advances() -> void:
	var p: Vector2 = MovementSystem.move(
		Vector2(4.0, 4.0), Vector2(4.5, 0.0), TICK, BODY, _none, BOUNDS)
	assert_almost_eq(p.x, 4.075, 0.0001)
	assert_almost_eq(p.y, 4.0, 0.0001)


func test_a_wall_stops_movement_head_on() -> void:
	var solids: Array[Rect2i] = [Rect2i(6, 3, 1, 2)]
	var p: Vector2 = Vector2(4.0, 4.0)
	for i: int in range(200):
		p = MovementSystem.move(p, Vector2(4.5, 0.0), TICK, BODY, solids, BOUNDS)
	assert_almost_eq(p.x, 5.6875, 0.0001, "stops with the body edge against tile 6")


func test_walking_diagonally_into_a_wall_slides_along_it() -> void:
	# A vertical wall at x = 6. Moving north-east should keep the northward
	# component even though the eastward one is blocked.
	var solids: Array[Rect2i] = [Rect2i(6, 0, 1, 32)]
	var p: Vector2 = Vector2(5.5, 10.0)
	for i: int in range(60):
		p = MovementSystem.move(p, Vector2(4.5, -4.5), TICK, BODY, solids, BOUNDS)
	assert_almost_eq(p.x, 5.6875, 0.0001, "blocked eastward")
	assert_lt(p.y, 6.5, "but still moved north")


func test_an_inside_corner_stops_both_axes() -> void:
	var solids: Array[Rect2i] = [Rect2i(6, 0, 1, 32), Rect2i(0, 2, 32, 1)]
	var p: Vector2 = Vector2(5.5, 4.0)
	for i: int in range(120):
		p = MovementSystem.move(p, Vector2(4.5, -4.5), TICK, BODY, solids, BOUNDS)
	assert_almost_eq(p.x, 5.6875, 0.0001)
	assert_almost_eq(p.y, 3.5, 0.0001, "feet stop below the horizontal wall")


func test_bounds_clamp_west_and_north() -> void:
	var p: Vector2 = Vector2(1.0, 1.0)
	for i: int in range(200):
		p = MovementSystem.move(p, Vector2(-4.5, -4.5), TICK, BODY, _none, BOUNDS)
	assert_almost_eq(p.x, 0.3125, 0.0001)
	assert_almost_eq(p.y, 0.5, 0.0001, "the feet point is a body height below the top edge")


func test_bounds_clamp_east_and_south() -> void:
	var p: Vector2 = Vector2(30.0, 30.0)
	for i: int in range(200):
		p = MovementSystem.move(p, Vector2(4.5, 4.5), TICK, BODY, _none, BOUNDS)
	assert_almost_eq(p.x, 31.6875, 0.0001)
	assert_almost_eq(p.y, 32.0, 0.0001)
```

- [x] **Step 2: Run the test to verify it fails**

```bash
./tools/run_tests.sh
```

Expected: FAIL — `MovementSystem` is not declared.

- [x] **Step 3: Write the implementation**

Create `src/systems/movement_system.gd`:

```gdscript
class_name MovementSystem
extends RefCounted
## Resolves a desired move against solid rectangles.
##
## Pure: same inputs, same output, no engine state, no physics tick, no
## display server. That is the whole point -- Stage 1 acceptance criterion
## #1 ("walk from any corner to any other with no collision bugs") is a test
## that runs in CI rather than a play-session somebody performs.
##
## Every argument is in TILE UNITS. `body` is the collision box size in
## tiles, anchored bottom-centre on `pos`: the position IS the feet point,
## which also makes it the Y-sort key with no offset arithmetic.
##
## Resolution is axis-separated, not swept: move on X and push out along X,
## then move on Y and push out along Y. Wall sliding falls out of that for
## free, and it avoids the edge cases a true swept AABB brings for no
## behavioural gain at these speeds.


## The body box in world tile space. `pos` is its bottom-centre.
static func body_rect(pos: Vector2, body: Vector2) -> Rect2:
	return Rect2(pos.x - body.x * 0.5, pos.y - body.y, body.x, body.y)


static func clamp_to_bounds(pos: Vector2, body: Vector2, bounds: Rect2) -> Vector2:
	var half: float = body.x * 0.5
	return Vector2(
		clampf(pos.x, bounds.position.x + half, bounds.end.x - half),
		clampf(pos.y, bounds.position.y + body.y, bounds.end.y)
	)


static func move(
	pos: Vector2,
	velocity: Vector2,
	delta: float,
	body: Vector2,
	solids: Array[Rect2i],
	bounds: Rect2
) -> Vector2:
	var p: Vector2 = pos
	var step: Vector2 = velocity * delta
	p = _slide_axis(p, body, Vector2(step.x, 0.0), solids)
	p = _slide_axis(p, body, Vector2(0.0, step.y), solids)
	return clamp_to_bounds(p, body, bounds)


## Moves along one axis and pushes out of anything it lands inside.
## `step` has exactly one non-zero component.
static func _slide_axis(
	pos: Vector2, body: Vector2, step: Vector2, solids: Array[Rect2i]
) -> Vector2:
	if step.is_zero_approx():
		return pos
	var moved: Vector2 = pos + step
	var r: Rect2 = body_rect(moved, body)
	for s: Rect2i in solids:
		var sr: Rect2 = Rect2(float(s.position.x), float(s.position.y),
			float(s.size.x), float(s.size.y))
		# Rect2.intersects() is exclusive, so a body resting exactly against
		# a wall does not count as overlapping it.
		if not r.intersects(sr):
			continue
		if step.x > 0.0:
			moved.x = sr.position.x - body.x * 0.5
		elif step.x < 0.0:
			moved.x = sr.end.x + body.x * 0.5
		elif step.y > 0.0:
			moved.y = sr.position.y
		else:
			moved.y = sr.end.y + body.y
		r = body_rect(moved, body)
	return moved
```

- [x] **Step 4: Run the tests to verify they pass**

```bash
./tools/run_tests.sh
```

Expected: PASS, seven new tests.

- [x] **Step 5: Run the architecture guard**

```bash
./tools/godot.sh --headless --path . -s tools/guard.gd
```

Expected: `Architecture guard: clean`

- [x] **Step 6: Commit**

```bash
git add src/systems/movement_system.gd tests/test_movement_system.gd
git commit -m "$(cat <<'EOF'
feat: resolve movement against solid rects without Godot physics

Axis-separated AABB resolution: move on X and push out along X, then the
same on Y. Wall sliding falls out for free.

Pure functions with no engine state, so Stage 1 acceptance criterion #1 --
walk from any corner to any other with no collision bugs -- is a headless
test rather than a play-session. That is the reason the Stage 1 design's
CharacterBody2D was corrected away in the Phase 3b spec.

Position is the feet point, the bottom-centre of the body box, which also
makes it the Y-sort key with no offset arithmetic.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: Substepping and facing

**Files:**
- Modify: `src/systems/movement_system.gd`
- Test: `tests/test_movement_system.gd`

**Interfaces:**
- Consumes: everything from Task 4
- Produces: `MovementSystem.facing_from(velocity: Vector2, current: int) -> int` and the constants `FACING_S = 0`, `FACING_SE = 1`, `FACING_E = 2`, `FACING_NE = 3`, `FACING_N = 4`, `FACING_NW = 5`, `FACING_W = 6`, `FACING_SW = 7`. `move()` keeps its Task 4 signature.

**Why substepping.** At 4.5 tiles/sec on a 60 Hz tick a step is 0.075 tiles against a body 0.5 tiles deep — a margin of about 6.7x. A frame spike erases it. Note that a body landing *inside* a wall is still pushed out correctly; tunnelling needs the body to clear the far side entirely, which at this body width takes a step over 1.125 tiles — a hitch of about half a second. Substepping makes correctness depend on the body size, which we control, rather than the frame rate, which we do not.

- [x] **Step 1: Write the failing tests**

Append to `tests/test_movement_system.gd`:

```gdscript
func test_a_frame_spike_does_not_tunnel_through_a_wall() -> void:
	# A half-second hitch steps 2.25 tiles. Landing INSIDE a wall is still
	# resolved correctly, so a smaller spike proves nothing -- this one
	# clears the far side of the wall entirely, which is real tunnelling.
	var solids: Array[Rect2i] = [Rect2i(6, 0, 1, 32)]
	var p: Vector2 = MovementSystem.move(
		Vector2(5.5, 10.0), Vector2(4.5, 0.0), 0.5, BODY, solids, BOUNDS)
	assert_almost_eq(p.x, 5.6875, 0.0001, "stopped by the wall, not teleported past it")


func test_substepping_does_not_change_an_unobstructed_move() -> void:
	var p: Vector2 = MovementSystem.move(
		Vector2(4.0, 4.0), Vector2(4.5, 0.0), 0.25, BODY, _none, BOUNDS)
	assert_almost_eq(p.x, 5.125, 0.0001, "4.0 + 4.5 * 0.25")


func test_facing_covers_all_eight_octants() -> void:
	assert_eq(MovementSystem.facing_from(Vector2(0, 1), 0), MovementSystem.FACING_S)
	assert_eq(MovementSystem.facing_from(Vector2(1, 1), 0), MovementSystem.FACING_SE)
	assert_eq(MovementSystem.facing_from(Vector2(1, 0), 0), MovementSystem.FACING_E)
	assert_eq(MovementSystem.facing_from(Vector2(1, -1), 0), MovementSystem.FACING_NE)
	assert_eq(MovementSystem.facing_from(Vector2(0, -1), 0), MovementSystem.FACING_N)
	assert_eq(MovementSystem.facing_from(Vector2(-1, -1), 0), MovementSystem.FACING_NW)
	assert_eq(MovementSystem.facing_from(Vector2(-1, 0), 0), MovementSystem.FACING_W)
	assert_eq(MovementSystem.facing_from(Vector2(-1, 1), 0), MovementSystem.FACING_SW)


func test_facing_is_held_when_velocity_is_zero() -> void:
	# Releasing every key must not snap the character back to a default,
	# or persisting `facing` in Phase 5 means nothing.
	assert_eq(
		MovementSystem.facing_from(Vector2.ZERO, MovementSystem.FACING_W),
		MovementSystem.FACING_W
	)
```

- [x] **Step 2: Run the tests to verify they fail**

```bash
./tools/run_tests.sh
```

Expected: FAIL — `facing_from` is not defined, and the spike test lands at roughly `x = 7.75`, clean past the wall.

- [x] **Step 3: Add the constants and facing**

At the top of `src/systems/movement_system.gd`, below the docstring:

```gdscript
## Eight octants. Screen space has y pointing down, so "south" is +y.
const FACING_S: int = 0
const FACING_SE: int = 1
const FACING_E: int = 2
const FACING_NE: int = 3
const FACING_N: int = 4
const FACING_NW: int = 5
const FACING_W: int = 6
const FACING_SW: int = 7
```

And add the function:

```gdscript
## Takes the current facing so that releasing every key holds the last
## direction rather than snapping to a default -- which is what makes
## persisting `facing` in Phase 5 mean anything.
static func facing_from(velocity: Vector2, current: int) -> int:
	if velocity.is_zero_approx():
		return current
	# atan2 gives +PI/2 for south and 0 for east; the octant index runs the
	# other way, starting at south, so subtract from PI/2 and wrap.
	var octant: int = roundi((PI * 0.5 - atan2(velocity.y, velocity.x)) / (PI * 0.25))
	return posmod(octant, 8)
```

- [x] **Step 4: Add substepping to `move()`**

Replace the body of `move()` in `src/systems/movement_system.gd`:

```gdscript
static func move(
	pos: Vector2,
	velocity: Vector2,
	delta: float,
	body: Vector2,
	solids: Array[Rect2i],
	bounds: Rect2
) -> Vector2:
	var total: Vector2 = velocity * delta
	# No single step may exceed half the body's smaller dimension, or a
	# frame spike walks straight through a one-tile wall.
	var cap: float = minf(body.x, body.y) * 0.5
	var steps: int = 1
	if cap > 0.0 and total.length() > cap:
		steps = ceili(total.length() / cap)
	var step: Vector2 = total / float(steps)

	var p: Vector2 = pos
	for i: int in range(steps):
		p = _slide_axis(p, body, Vector2(step.x, 0.0), solids)
		p = _slide_axis(p, body, Vector2(0.0, step.y), solids)
		p = clamp_to_bounds(p, body, bounds)
	return p
```

- [x] **Step 5: Run the tests to verify they pass**

```bash
./tools/run_tests.sh
```

Expected: PASS, eleven tests in this file — the seven from Task 4 still green.

- [x] **Step 6: Commit**

```bash
git add src/systems/movement_system.gd tests/test_movement_system.gd
git commit -m "$(cat <<'EOF'
feat: substep movement and derive eight-way facing

A quarter-second frame spike steps 1.125 tiles at walking speed, clean
through a one-tile wall. Substepping caps a single step at half the body's
smaller dimension, so correctness depends on the body size we control
rather than the frame rate we do not.

facing_from takes the current value so releasing every key holds the last
direction instead of snapping to a default. Without that, persisting
`facing` in Phase 5 would mean nothing.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: The player content definition, input map and `Player` node

**Files:**
- Create: `data/creature/player.json`, `src/presentation/player.gd`
- Modify: `project.godot`

**Interfaces:**
- Consumes: `MovementSystem.move`, `MovementSystem.facing_from`, `CollisionBuilder.solids_near`, `Zone.is_walkable(Vector2i) -> bool`, `Zone.in_bounds(Vector2i) -> bool`, `Zone.size_tiles`, `Zone.entities`, `EntityStore.spawn(int, Vector2) -> int`, `EntityStore.get_position/set_position/get_facing/set_facing`, `ContentRegistry.numeric_of(String) -> int`
- Produces: `Player.spawn(zone: Zone, registry: ContentRegistry, near: Vector2i) -> int`, `Player.find_spawn_tile(zone: Zone, near: Vector2i) -> Vector2i` (static), and the members `entity_id: int`, `speed: float`, `body: Vector2`

`player.json` reuses the existing **`creature`** category. A new category would need a new schema plus a schema validation test per `CLAUDE.md`, and buys nothing here — `wander_radius` and `flees_player` are optional and simply absent.

- [x] **Step 1: Write the content definition**

Create `data/creature/player.json`:

```json
{"id": "player", "category": "creature", "display_name": "Player",
 "sprite": "res://assets/characters/player.png", "tags": ["player"]}
```

- [x] **Step 2: Verify the registry picks it up**

```bash
./tools/godot.sh --headless --path . --import
./tools/godot.sh --headless --path . --quit-after 60
```

Expected: `RP1 booted with 5 content definitions` (was 4).

- [x] **Step 3: Add the input actions**

Append to `project.godot`. There is no `[input]` section today — create it above `[rendering]`:

```
[input]

move_up={
"deadzone": 0.2,
"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":87,"key_label":0,"unicode":0,"location":0,"echo":false,"script":null)
, Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":4194320,"key_label":0,"unicode":0,"location":0,"echo":false,"script":null)
]
}
move_down={
"deadzone": 0.2,
"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":83,"key_label":0,"unicode":0,"location":0,"echo":false,"script":null)
, Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":4194322,"key_label":0,"unicode":0,"location":0,"echo":false,"script":null)
]
}
move_left={
"deadzone": 0.2,
"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":65,"key_label":0,"unicode":0,"location":0,"echo":false,"script":null)
, Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":4194319,"key_label":0,"unicode":0,"location":0,"echo":false,"script":null)
]
}
move_right={
"deadzone": 0.2,
"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":68,"key_label":0,"unicode":0,"location":0,"echo":false,"script":null)
, Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":4194321,"key_label":0,"unicode":0,"location":0,"echo":false,"script":null)
]
}
```

Physical keycodes: `87/83/65/68` are W/S/A/D, and `4194320/4194322/4194319/4194321` are the up/down/left/right arrows. Physical rather than logical, so the layout works on AZERTY.

- [x] **Step 4: Verify the actions registered**

```bash
./tools/godot.sh --headless --path . --quit-after 60
```

Expected: exits 0 with no `input` parse errors. If Godot rewrites the section on exit, that is normal and fine.

- [x] **Step 5: Write the Player node**

Create `src/presentation/player.gd`:

```gdscript
class_name Player
extends Node
## Input and spawning. Owns no position of its own.
##
## The player's position lives in an EntityStore row, so the renderer, the
## camera and Phase 5's save all read one source of truth -- and persisting
## the player needs no code beyond the entity codec that already exists.
##
## This node reads input, asks MovementSystem to resolve the move, and
## writes the result back. It does not draw anything: EntityRenderer draws
## the player through the same pool as every other entity.

## How far the spawn search will look before giving up.
const SPAWN_SEARCH_RADIUS: int = 64

## Tiles per second. The figure the substepping bound in MovementSystem is
## calculated against.
@export var speed: float = 4.5

## Collision box in tiles, anchored bottom-centre on the position. The
## sprite is 32x64; a body that size could not walk between two trees the
## character visually fits between.
@export var body: Vector2 = Vector2(0.625, 0.5)

var zone: Zone = null
var entity_id: int = EntityStore.INVALID_ID

var _collision: CollisionBuilder = null


func spawn(p_zone: Zone, registry: ContentRegistry, near: Vector2i) -> int:
	zone = p_zone
	_collision = CollisionBuilder.new()
	var tile: Vector2i = find_spawn_tile(p_zone, near)
	# Centre of the tile: +0.5 on both axes.
	entity_id = p_zone.entities.spawn(
		registry.numeric_of("player"), Vector2(tile) + Vector2(0.5, 0.5)
	)
	return entity_id


## Rings outward from `near` until a walkable tile turns up.
##
## A hardcoded spawn is what Phase 4's authored zone breaks silently: the
## character appears inside a tree, cannot move, and nothing logs an error.
static func find_spawn_tile(p_zone: Zone, near: Vector2i) -> Vector2i:
	if p_zone.in_bounds(near) and p_zone.is_walkable(near):
		return near
	for r: int in range(1, SPAWN_SEARCH_RADIUS + 1):
		for dy: int in range(-r, r + 1):
			for dx: int in range(-r, r + 1):
				# Only the ring's edge; the interior was covered by a
				# smaller radius already.
				if absi(dx) != r and absi(dy) != r:
					continue
				var t: Vector2i = near + Vector2i(dx, dy)
				if p_zone.in_bounds(t) and p_zone.is_walkable(t):
					return t
	push_error("player: no walkable spawn within %d tiles of %s" % [SPAWN_SEARCH_RADIUS, near])
	return near


func _physics_process(delta: float) -> void:
	if zone == null or not zone.entities.has(entity_id):
		return

	var dir: Vector2 = Vector2(
		Input.get_axis("move_left", "move_right"),
		Input.get_axis("move_up", "move_down")
	)
	# Normalize only past unit length, so a diagonal carries no speed bonus
	# while analogue input keeps its magnitude.
	if dir.length_squared() > 1.0:
		dir = dir.normalized()
	var velocity: Vector2 = dir * speed

	var pos: Vector2 = zone.entities.get_position(entity_id)
	# Two tiles of slack around the body covers a frame's travel plus the
	# body itself, so the gathered rects always include anything reachable.
	var area: Rect2 = Rect2(pos - Vector2(2.0, 2.0), Vector2(4.0, 4.0))
	var solids: Array[Rect2i] = _collision.solids_near(zone, area)
	var bounds: Rect2 = Rect2(Vector2.ZERO, Vector2(zone.size_tiles))

	var moved: Vector2 = MovementSystem.move(pos, velocity, delta, body, solids, bounds)
	zone.entities.set_position(entity_id, moved)
	zone.entities.set_facing(
		entity_id, MovementSystem.facing_from(velocity, zone.entities.get_facing(entity_id))
	)
```

- [x] **Step 6: Run the tests and the guard**

```bash
./tools/run_tests.sh
./tools/godot.sh --headless --path . -s tools/guard.gd
```

Expected: tests still pass; `Architecture guard: clean` — `player.gd` lives in `presentation/`, so `extends Node` is fine there.

- [x] **Step 7: Commit**

```bash
git add data/creature/player.json project.godot src/presentation/player.gd
git commit -m "$(cat <<'EOF'
feat: add the player entity, input map and spawn search

The player is an ordinary EntityStore row rather than a node with its own
position. The renderer, the camera and Phase 5's save then all read one
source of truth, and persisting the player needs no code beyond the entity
codec that already exists.

Reuses the creature category: a new one would need a schema and a schema
validation test for no benefit.

Input actions bind WASD and the arrow keys by physical keycode, so the
layout survives AZERTY. There was no [input] section at all before.

The spawn search rings outward rather than trusting a fixed point. Zone
centre is clear in today's debug zone, but a hardcoded spawn is what Phase
4's authored zone breaks silently -- the character appears inside a tree
and nothing logs an error.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: `EntityRenderer`

**Files:**
- Create: `src/presentation/entity_renderer.gd`

**Interfaces:**
- Consumes: `EntityStore.ids() -> PackedInt32Array`, `EntityStore.get_type_id(int) -> int`, `EntityStore.get_position(int) -> Vector2`, `ContentRegistry.def_of(int) -> Dictionary`, `ContentRegistry.string_of(int) -> String`
- Produces: `EntityRenderer.setup(registry: ContentRegistry) -> void`, `entities: EntityStore` (assignable), `refresh() -> int` returning the number of sprites drawn, `visible_count() -> int`

Tested through `tools/smoke.gd` in Task 10 rather than a GUT file, matching how Phase 3a covered `ZoneRenderer`. `CLAUDE.md` requires a matching test for `core/` and `systems/`; presentation is covered by the smoke gate.

- [x] **Step 1: Write the implementation**

Create `src/presentation/entity_renderer.gd`:

```gdscript
class_name EntityRenderer
extends Node2D
## Draws EntityStore rows as a pool of Sprite2D nodes.
##
## Presentation reads world data and never writes it. Nothing here may
## mutate the store it is handed.
##
## y_sort_enabled is set on this node so its sprites flatten into the
## parent's sort and interleave with the object layer's tiles. Without it
## the whole renderer sorts as a single item and every entity draws in
## front of every tree.

const TILE_SIZE: int = 32

var entities: EntityStore = null

var _registry: ContentRegistry = null
var _pool: Array[Sprite2D] = []
## Numeric type id -> Texture2D, or null for one that could not be loaded.
## Failures are cached too, so a missing PNG logs once rather than sixty
## times a second.
var _textures: Dictionary = {}


func _ready() -> void:
	y_sort_enabled = true


func setup(registry: ContentRegistry) -> void:
	_registry = registry
	y_sort_enabled = true


func _process(_delta: float) -> void:
	refresh()


## Repaints every row. Returns the number of sprites actually drawn.
func refresh() -> int:
	if entities == null or _registry == null:
		return 0
	var ids: PackedInt32Array = entities.ids()
	var shown: int = 0
	for i: int in range(ids.size()):
		var texture: Texture2D = _texture_for(entities.get_type_id(ids[i]))
		if texture == null:
			continue
		var sprite: Sprite2D = _sprite_at(shown)
		sprite.texture = texture
		# Bottom-centre anchoring: the texture's bottom edge lands on the
		# entity position, which is the feet point. Derived from geometry,
		# so a 32x64 player and a 32x32 rabbit both stand correctly with no
		# content field and no per-type tuning -- the principle commit
		# ad8956c established for the tileset builder.
		sprite.offset = Vector2(0.0, -float(texture.get_height()) * 0.5)
		sprite.position = entities.get_position(ids[i]) * float(TILE_SIZE)
		sprite.visible = true
		shown += 1
	# Surplus sprites are hidden, not freed: entity counts churn and
	# allocating nodes per frame is what pooling exists to avoid.
	for i: int in range(shown, _pool.size()):
		_pool[i].visible = false
	return shown


func visible_count() -> int:
	var n: int = 0
	for s: Sprite2D in _pool:
		if s.visible:
			n += 1
	return n


func _sprite_at(index: int) -> Sprite2D:
	while _pool.size() <= index:
		var s: Sprite2D = Sprite2D.new()
		s.centered = true
		s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(s)
		_pool.append(s)
	return _pool[index]


func _texture_for(type_id: int) -> Texture2D:
	if _textures.has(type_id):
		return _textures[type_id]
	var path: String = str(_registry.def_of(type_id).get("sprite", ""))
	var texture: Texture2D = null
	# Checked before load() rather than testing the result for null:
	# load() on a missing path pushes an engine-level error. Same guard as
	# tileset_builder.gd:49.
	if path.is_empty() or not ResourceLoader.exists(path):
		push_error("entity sprite: cannot load '%s' for %s"
			% [path, _registry.string_of(type_id)])
	else:
		texture = load(path) as Texture2D
	_textures[type_id] = texture
	return texture
```

- [x] **Step 2: Run the tests and the guard**

```bash
./tools/run_tests.sh
./tools/godot.sh --headless --path . -s tools/guard.gd
```

Expected: tests still pass; `Architecture guard: clean`.

- [x] **Step 3: Commit**

```bash
git add src/presentation/entity_renderer.gd
git commit -m "$(cat <<'EOF'
feat: draw entity rows through a pooled sprite renderer

One load() per content type for the life of the run, guarded by
ResourceLoader.exists() as the tileset builder does. Failures are cached
too, so a missing PNG logs once instead of sixty times a second.

The sprite anchor is derived from texture geometry rather than authored:
offset.y = -h/2 puts the texture's bottom edge on the entity position,
which is the feet point. A 32x64 player and a 32x32 rabbit both stand
correctly with no content field, the same principle as ad8956c.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 8: The camera and the Y-sorted node tree

**Files:**
- Create: `src/presentation/camera.gd`
- Modify: `src/presentation/zone_renderer.gd`, `project.godot`

**Interfaces:**
- Consumes: `Zone.size_tiles`, `Zone.entities`, `EntityStore.has(int) -> bool`, `EntityStore.get_position(int) -> Vector2`
- Produces: `FollowCamera.setup(zone: Zone) -> void`, `target_id: int` (assignable), `follow_zoom: float`

**The Y-sort change is the risky part of this task.** Godot sorts the direct children of a y-sorted node. Phase 3a set `y_sort_enabled` on `ObjectLayer` only, which sorts tiles among themselves but not against anything outside the renderer. Nested y-sorted nodes flatten into the parent's sort, so `ZoneRenderer` itself must be y-sorted too — otherwise its whole subtree sorts as a single item at `y = 0` and every entity draws in front of every tree.

- [x] **Step 1: Make `ZoneRenderer` participate in the parent's sort**

In `src/presentation/zone_renderer.gd`, replace `_ensure_layers()`:

```gdscript
func _ensure_layers() -> void:
	if terrain_layer != null:
		return
	# Nested Y-sorted nodes flatten into the parent's sort, which is what
	# lets object tiles interleave with entity sprites. Without this the
	# whole renderer sorts as one item at y = 0 and the player draws in
	# front of every tree regardless of where they stand.
	y_sort_enabled = true
	terrain_layer = _make_layer("TerrainLayer", false)
	floor_layer = _make_layer("FloorLayer", false)
	object_layer = _make_layer("ObjectLayer", true)
	# Ground never sorts. Without an explicit z_index these layers sit at
	# y = 0 in the flattened sort and stay behind everything only by a
	# tie-break on tree order, which is not a thing to depend on.
	terrain_layer.z_index = -1
	floor_layer.z_index = -1
```

- [x] **Step 2: Write the camera**

Create `src/presentation/camera.gd`:

```gdscript
class_name FollowCamera
extends Camera2D
## Follows an entity, clamped to the zone's bounds.
##
## Named FollowCamera rather than Camera: a bare `Camera` risks colliding
## with engine-reserved names.

const TILE_SIZE: int = 32

## 1280x720 at 2x shows 20 x 11.25 tiles, which frames a 128x128 zone as a
## place you move through rather than a map you survey.
@export var follow_zoom: float = 2.0

var target_id: int = EntityStore.INVALID_ID

var _entities: EntityStore = null


func setup(zone: Zone) -> void:
	_entities = zone.entities
	zoom = Vector2(follow_zoom, follow_zoom)
	# Smoothing plus pixel snapping produces sub-pixel jitter, and crisp
	# beats smooth at this resolution.
	position_smoothing_enabled = false
	limit_left = 0
	limit_top = 0
	limit_right = zone.size_tiles.x * TILE_SIZE
	limit_bottom = zone.size_tiles.y * TILE_SIZE


func _process(_delta: float) -> void:
	if _entities == null or not _entities.has(target_id):
		return
	global_position = _entities.get_position(target_id) * float(TILE_SIZE)
```

- [x] **Step 3: Add the pixel-snap project settings**

In `project.godot`, extend the existing `[rendering]` section:

```
[rendering]

textures/canvas_textures/default_texture_filter=0
renderer/rendering_method="gl_compatibility"
renderer/rendering_method.mobile="gl_compatibility"
2d/snap/snap_2d_transforms_to_pixel=true
2d/snap/snap_2d_vertices_to_pixel=true
```

- [x] **Step 4: Run the tests, the guard and the smoke gate**

```bash
./tools/run_tests.sh
./tools/godot.sh --headless --path . -s tools/guard.gd
./tools/godot.sh --headless --path . -s tools/smoke.gd
```

Expected: all three green. The smoke test exercises `ZoneRenderer`, so this confirms the y-sort change did not break painting.

- [x] **Step 5: Commit**

```bash
git add src/presentation/camera.gd src/presentation/zone_renderer.gd project.godot
git commit -m "$(cat <<'EOF'
feat: add a bounds-limited follow camera and fix the Y-sort tree

ZoneRenderer now sets y_sort_enabled on itself. Phase 3a set it on the
object layer with the comment "must sort against the player", but that was
aspirational: Godot sorts the direct children of a y-sorted node, so an
unsorted ZoneRenderer would have put its entire subtree at y = 0 and drawn
every entity in front of every tree. Nested y-sorted nodes flatten into
the parent's sort; this makes that true.

Terrain and floor get an explicit z_index rather than relying on a
tie-break on tree order.

Camera smoothing is off: combined with pixel snapping it produces
sub-pixel jitter, and crisp beats smooth at this resolution.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 9: Wire it together

**Files:**
- Modify: `src/presentation/main.gd`

**Interfaces:**
- Consumes: everything from Tasks 2-8
- Produces: a running game. Prints `RP1 player spawned at (x, y)`, which Task 10's CI gate greps for.

- [ ] **Step 1: Rewrite `_ready()`**

In `src/presentation/main.gd`, replace `_ready()`:

```gdscript
func _ready() -> void:
	# Nested Y-sorted nodes flatten into this one's sort, so the object
	# layer's tiles and the entity sprites interleave by their y position.
	y_sort_enabled = true

	var registry: ContentRegistry = ContentRegistry.new()
	var errs: PackedStringArray = registry.load_from_dir("res://data")
	if not errs.is_empty():
		push_error("content failed to load: %s" % ", ".join(errs))
	print("RP1 booted with %d content definitions" % registry.all_string_ids().size())

	_renderer = ZoneRenderer.new()
	_renderer.name = "ZoneRenderer"
	add_child(_renderer)

	var art_errs: PackedStringArray = _renderer.setup(registry)
	for e: String in art_errs:
		push_error("tileset: %s" % e)

	var zone: Zone = _build_debug_zone(registry)
	var painted: int = _renderer.render_zone(zone)
	_renderer.zone = zone

	# The export gate asserts this count is non-zero. A build can export
	# cleanly and still ship without its textures, exactly as it nearly
	# shipped without data/*.json.
	print("RP1 rendered %d cells" % painted)

	_entity_renderer = EntityRenderer.new()
	_entity_renderer.name = "EntityRenderer"
	add_child(_entity_renderer)
	_entity_renderer.setup(registry)
	_entity_renderer.entities = zone.entities

	_player = Player.new()
	_player.name = "Player"
	add_child(_player)
	var pid: int = _player.spawn(zone, registry, zone.size_tiles / 2)
	print("RP1 player spawned at %s" % zone.entities.get_position(pid))

	_camera = FollowCamera.new()
	_camera.name = "FollowCamera"
	add_child(_camera)
	_camera.setup(zone)
	_camera.target_id = pid
	_camera.make_current()
```

- [ ] **Step 2: Add the new members**

Alongside the existing `var _renderer: ZoneRenderer = null`:

```gdscript
var _entity_renderer: EntityRenderer = null
var _player: Player = null
var _camera: FollowCamera = null
```

- [ ] **Step 3: Derive the walkable flags in the debug zone**

In `_build_debug_zone()`, the generator currently sets `FLAG_WALKABLE` from terrain alone, which leaves the oaks standing on walkable tiles. Delete that hand-set flag and let `Walkability` derive it. Replace the loop body's flag line and add a recompute before `clear_dirty()`:

```gdscript
	for y: int in range(ZONE_SIZE.y):
		for x: int in range(ZONE_SIZE.x):
			var w: Vector2i = Vector2i(x, y)
			var in_pond: bool = Vector2(w - POND_CENTRE).length() <= float(POND_RADIUS)
			zone.set_terrain(w, water if in_pond else grass)
			# A lattice, skipping the pond, so the result is easy to eyeball.
			if not in_pond and x % TREE_SPACING == 0 and y % TREE_SPACING == 0:
				zone.set_object(w, oak)

	# Flags are derived from content, never hand-set. Setting them here
	# from terrain alone is what left the oaks standing on walkable tiles.
	Walkability.recompute_zone(zone, registry)

	# The renderer has just painted everything; the flags this generator
	# set are not pending work for it. recompute_zone() dirties chunks as
	# it writes, so this must stay AFTER it.
	zone.clear_dirty()
	return zone
```

- [ ] **Step 4: Run it**

```bash
./tools/godot.sh --headless --path . --quit-after 120
```

Expected, in order:

```
RP1 booted with 5 content definitions
RP1 rendered <N> cells
RP1 player spawned at (64.5, 64.5)
```

- [ ] **Step 5: Play it**

```bash
./tools/godot.sh --path .
```

Walk with WASD and the arrow keys. Confirm by eye: eight directions work, diagonals are not faster, the pond and the oaks stop you, the zone edges stop you, and the camera stops at all four bounds instead of showing black.

- [ ] **Step 6: Run every gate**

```bash
./tools/run_tests.sh
./tools/godot.sh --headless --path . -s tools/guard.gd
./tools/godot.sh --headless --path . -s tools/smoke.gd
./tools/check_asset_licences.sh
```

Expected: all four green.

- [ ] **Step 7: Commit**

```bash
git add src/presentation/main.gd
git commit -m "$(cat <<'EOF'
feat: spawn a player into the debug zone and follow it

Wires the entity renderer, player and camera into main, and turns on
y_sort_enabled so the object layer and the entity sprites share one sort.

Also stops hand-setting FLAG_WALKABLE in the debug zone generator. It set
the flag from terrain alone, which left every oak standing on a walkable
tile -- the trees have never blocked anything. Walkability derives it from
content instead, which is the whole point of having the rule in one place.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 10: Smoke assertions and the export gate

**Files:**
- Modify: `tools/smoke.gd`, `.github/workflows/ci.yml`

**Interfaces:**
- Consumes: `Walkability`, `CollisionBuilder`, `MovementSystem`, `EntityRenderer`
- Produces: a smoke run that fails if movement stops working headless

- [ ] **Step 1: Add the movement block to the smoke test**

In `tools/smoke.gd`, insert before the `renderer.queue_free()` line:

```gdscript
	# --- movement --------------------------------------------------------
	# A purpose-built fixture: an 8x8 patch of grass with one oak in it.
	# The zone above is scattered tiles and is not walkable enough to test
	# against.
	var mzone: Zone = Zone.new("move", Vector2i(32, 32))
	var oak: int = registry.numeric_of("oak_tree")
	_check(oak != ContentRegistry.ID_UNKNOWN, "oak_tree is registered")
	for y: int in range(8):
		for x: int in range(8):
			mzone.set_terrain(Vector2i(x, y), grass)
	mzone.set_object(Vector2i(4, 2), oak)

	_check(Walkability.recompute_zone(mzone, registry) > 0, "walkability set some flags")
	_check(mzone.is_walkable(Vector2i(2, 2)), "plain grass is walkable")
	_check(not mzone.is_walkable(Vector2i(4, 2)), "grass under an oak is not walkable")

	var collision: CollisionBuilder = CollisionBuilder.new()
	var solids: Array[Rect2i] = collision.solids_near(
		mzone, Rect2(Vector2.ZERO, Vector2(8.0, 8.0)))
	_check(not solids.is_empty(), "collision builder produced rects")

	var body: Vector2 = Vector2(0.625, 0.5)
	var bounds: Rect2 = Rect2(Vector2.ZERO, Vector2(mzone.size_tiles))
	var tick: float = 1.0 / 60.0

	# Row 2 has the oak at x = 4. Walking east must stop short of it.
	var blocked: Vector2 = Vector2(2.5, 2.5)
	for i: int in range(120):
		blocked = MovementSystem.move(blocked, Vector2(4.5, 0.0), tick, body, solids, bounds)
	_check(blocked.x < 4.0, "walking east into the oak stopped at %.3f" % blocked.x)

	# Row 5 is clear, so the same walk must actually get somewhere.
	var open: Vector2 = Vector2(2.5, 5.5)
	for i: int in range(120):
		open = MovementSystem.move(open, Vector2(4.5, 0.0), tick, body, solids, bounds)
	_check(open.x > 5.0, "walking east across open grass reached only %.3f" % open.x)

	# --- entity rendering ------------------------------------------------
	var entity_renderer: EntityRenderer = EntityRenderer.new()
	root.add_child(entity_renderer)
	entity_renderer.setup(registry)
	entity_renderer.entities = mzone.entities
	var player_type: int = registry.numeric_of("player")
	_check(player_type != ContentRegistry.ID_UNKNOWN, "player is registered")
	mzone.entities.spawn(player_type, Vector2(2.5, 2.5))
	_check(entity_renderer.refresh() == 1, "entity renderer drew the player")
	_check(entity_renderer.visible_count() == 1, "exactly one sprite is visible")
	entity_renderer.queue_free()
```

- [ ] **Step 2: Run the smoke test**

```bash
./tools/godot.sh --headless --path . -s tools/smoke.gd
```

Expected: `Smoke test: OK (300 iterations)`

- [ ] **Step 3: Prove each new assertion can fail**

Phase 3a mutated all seven of its new checks in turn and watched each fail with its own message. Do the same for all ten added above. One at a time: break it, run the smoke test, confirm it fails with *that* message, restore it.

Suggested mutations:

| Assertion | Mutation |
|---|---|
| `oak_tree is registered` | look up `"oak_treee"` |
| `player is registered` | look up `"playerr"` |
| `walkability set some flags` | skip the `recompute_zone` call |
| `plain grass is walkable` | place the oak at `(2, 2)` |
| `grass under an oak is not walkable` | place the oak at `(9, 9)`, outside the patch |
| `collision builder produced rects` | gather from an all-open zone |
| `walking east into the oak stopped` | pass `_none` as `solids` |
| `walking east across open grass` | start at `(2.5, 2.5)`, the blocked row |
| `entity renderer drew the player` | do not spawn the entity |
| `exactly one sprite is visible` | spawn a second entity |

Restore the file completely afterwards and re-run to confirm it is green again.

- [ ] **Step 4: Add the player assertion to the export gate**

In `.github/workflows/ci.yml`, extend the "Verify the exported build loads its content and renders" step with a third check after the rendered-cells one:

```yaml
          echo "$OUT" | grep -qE "RP1 player spawned at" \
            || { echo "Exported build spawned no player: data/creature/player.json is not" >&2
                 echo "reaching the PCK, or the spawn search failed against the exported zone." >&2
                 exit 1; }
```

The comment above the step already explains why this gate exists: an export can succeed while the PCK silently omits `data/`. A player that fails to spawn fails in exactly that way, so it belongs in the same place.

- [ ] **Step 5: Commit**

```bash
git add tools/smoke.gd .github/workflows/ci.yml
git commit -m "$(cat <<'EOF'
test: assert movement and entity rendering in the smoke gate

Builds an 8x8 grass patch with one oak and walks into it headless: east
along the blocked row must stop short of the tree, east along a clear row
must actually get somewhere. This is the mechanical form of Stage 1
acceptance criterion #1, which is why collision resolution was kept out of
Godot's physics.

Every new assertion was mutated in turn and seen to fail with its own
message before being trusted.

The export gate also now asserts the player spawned. An export can succeed
while the PCK silently omits data/, and a missing player.json fails in
exactly that way.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 11: Verify Y-sorting by screenshot

**Files:**
- No source changes expected. If the check fails, modify `src/presentation/main.gd` and `src/presentation/zone_renderer.gd` per the fallback below.

**Interfaces:**
- Consumes: `tools/screenshot.gd`
- Produces: visual confirmation of the one guarantee this phase cannot assert headless

Draw order is a rendering outcome, not node state, so no test can cover it. This task is a deliberate manual gate.

- [ ] **Step 1: Capture the player standing above an oak**

Temporarily spawn the player one tile north of the oak at `(66, 66)` — the lattice places trees every 11 tiles, so `(66, 66)` holds one. In `main.gd`, change the spawn call to:

```gdscript
	var pid: int = _player.spawn(zone, registry, Vector2i(66, 65))
```

Then capture:

```bash
./tools/godot.sh --path . -s tools/screenshot.gd -- --out=/tmp/ysort_above.png
```

- [ ] **Step 2: Capture the player standing below the same oak**

```gdscript
	var pid: int = _player.spawn(zone, registry, Vector2i(66, 67))
```

```bash
./tools/godot.sh --path . -s tools/screenshot.gd -- --out=/tmp/ysort_below.png
```

- [ ] **Step 3: Compare them**

Open both. Expected:

- `ysort_above.png` — the player is **behind** the tree; the trunk overlaps the character
- `ysort_below.png` — the player is **in front of** the tree; the character overlaps the trunk

If the player is in front in both, the nested y-sort did not flatten. **Fallback:** restructure so `ObjectLayer` and `EntityRenderer` are children of one dedicated y-sorted `Node2D`, with `TerrainLayer` and `FloorLayer` outside it and drawn first. That requires `ZoneRenderer` to expose its object layer for reparenting, and the spec records it as the accepted fallback.

- [ ] **Step 4: Restore the spawn point**

```gdscript
	var pid: int = _player.spawn(zone, registry, zone.size_tiles / 2)
```

Confirm nothing else changed:

```bash
git diff --stat
```

Expected: empty, unless the fallback was needed.

- [ ] **Step 5: Run every gate one final time**

```bash
./tools/run_tests.sh
./tools/godot.sh --headless --path . -s tools/guard.gd
./tools/godot.sh --headless --path . -s tools/smoke.gd
./tools/check_asset_licences.sh
```

Expected: all four green.

- [ ] **Step 6: Commit only if the fallback was needed**

If Step 3 passed, there is nothing to commit — record the result in the definition of done below instead. If the fallback was needed:

```bash
git add src/presentation/
git commit -m "$(cat <<'EOF'
fix: sort entities against object tiles via a dedicated sorted parent

Nested Y-sort flattening did not behave as expected in 4.7.2, so the
object layer and the entity renderer now share one dedicated Y-sorted
parent, with terrain and floor outside it. This is the fallback the Phase
3b spec section 4 recorded.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

## Definition of done for Phase 3b

- [ ] WASD and the arrow keys move the player in eight directions, diagonals normalized
- [ ] The player cannot enter the pond or a tree tile, and slides along an edge rather than sticking
- [ ] The player cannot leave the zone at any of the four edges
- [ ] The camera follows and clamps at all four bounds without jitter
- [ ] Screenshot: the player renders behind an oak from above, in front from below
- [ ] `EntityRenderer` draws the player, and `rabbit.png` resolves
- [ ] `./tools/run_tests.sh` green, including **32** new tests across three files (11 walkability, 10 collision, 11 movement)
- [ ] `tools/guard.gd` green — `walkability`, `collision_builder` and `movement_system` are node-free
- [ ] `tools/smoke.gd` green with ten new assertions, **each one seen to fail**
- [ ] The exported build loads content, renders, and spawns the player
- [ ] `docs/palette.md` exemptions and `assets/CREDITS.md` updated, and no "deleted in Phase 3b" strings remain
- [ ] No new file over roughly 300 lines

### Verifying the collision criterion by hand

The headless tests are the real gate, but walking it once catches what a test cannot — feel:

```bash
./tools/godot.sh --path .
```

Walk into the pond from all four directions. Walk diagonally into a tree and confirm you slide past rather than stick. Walk to each of the four zone edges. Walk the full diagonal of the zone, corner to corner.

**Not done in this phase, by design:** the Kenney import, `tools/quantize.gd`, the palette gate, `AnimalSystem`, the data-authored zone, and save/load wiring for the player. Those are Phase 3c, Phase 4 and Phase 5.
