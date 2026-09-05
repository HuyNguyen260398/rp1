# Phase 3a — Rendering Slice Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Paint a 128x128-tile zone on screen from real `Zone` chunk data, through a `TileSet` assembled at runtime from `ContentRegistry`.

**Architecture:** A node-free `TilesetBuilder` in `src/systems/` turns the content registry into a `TileSet` plus a numeric-id-to-source-id map; it is `RefCounted`, so it is unit-tested directly. A thin `ZoneRenderer` `Node2D` in `src/presentation/` owns three `TileMapLayer` children and paints cells from zone data. Data flows one way: presentation reads world data and never writes it.

**Tech Stack:** Godot 4.7.2 stable (standard build, not Mono), GDScript with static typing throughout, GUT for tests.

**Spec:** `docs/superpowers/specs/2026-09-05-rp1-phase3a-rendering-slice-design.md`

## Global Constraints

- Godot **4.7.2**, standard build. Invoke it only through `./tools/godot.sh`. Never hardcode a binary path.
- GDScript only. Static typing everywhere: `var x: int = 0`, `func f(a: Vector2i) -> void:`.
- `src/core/` and `src/systems/` **MUST NOT reference Godot nodes.** No `extends Node`, no `get_tree()`, no `Engine.`, no `.tscn`, no `add_child(`, no `get_node(`, no `queue_free(`. These folders extend `RefCounted` only. Enforced by `tools/guard.gd`.
- `TileSet`, `TileSetAtlasSource`, `TileData` and `Texture2D` are `Resource` types, **not nodes**. `src/systems/` may construct them.
- Use `TileMapLayer`. The `TileMap` node is deprecated.
- Tile size is **32x32**. Character sprites are 32x64. Texture filter is `Nearest`, project-wide (already set via `default_texture_filter=0`); never override per-texture.
- Run tests with `./tools/run_tests.sh` — never call `gut_cmdln.gd` directly.
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
python3 tools/mark_task_done.py <task-number> --plan docs/superpowers/plans/2026-09-05-rp1-phase3a-rendering-slice.md
```

Never tick checkboxes by hand.

### A note on `load()` and `ResourceLoader`

`CLAUDE.md` forbids `load()`, `ResourceLoader` and `.tres`/`.res` **for save data**, because a resource file can name a script path and loading one executes code. That rule is about the save system.

Loading a **texture named by a content definition** is a different thing and is required here. `ResourceLoader.exists()` and `load()` are correct and expected in `TilesetBuilder`. Do not route texture loading through `FileAccess`.

---

## File Structure

| File | Responsibility |
|---|---|
| `tools/make_placeholder_art.gd` | Create the throwaway debug PNGs. Run once; committed for reproducibility. |
| `assets/tiles/grass.png`, `water.png` | 32x32 debug swatches |
| `assets/objects/oak_tree.png` | 32x48 debug swatch — deliberately not square |
| `assets/objects/LICENSE.txt` | New folder needs one; the licence gate checks every top-level `assets/` folder |
| `src/systems/tileset_build_result.gd` | `TilesetBuildResult`: the value type returned by the builder |
| `src/systems/tileset_builder.gd` | `TilesetBuilder`: `ContentRegistry` -> `TileSet` + id map |
| `src/presentation/zone_renderer.gd` | `ZoneRenderer`: three `TileMapLayer`s painted from `Zone` |
| `src/presentation/main.gd` | Debug zone + wire-up (modified) |
| `tests/test_tileset_builder.gd` | Unit tests for the builder |
| `tools/smoke.gd` | Gains render assertions (modified) |
| `.github/workflows/ci.yml` | Export gate gains a painted-cells assertion (modified) |

`TilesetBuildResult` is a separate file rather than an inner class, matching the existing `src/core/save/decode_result.gd` precedent.

---

## Task 1: Placeholder art and licences

The JSON already names three sprite paths that do not exist. Create them as flat debug swatches. They are deliberately ugly — a placeholder that resembles finished art is a placeholder that survives to release.

**Files:**
- Create: `tools/make_placeholder_art.gd`
- Create: `assets/tiles/grass.png`, `assets/tiles/water.png`, `assets/objects/oak_tree.png`
- Create: `assets/objects/LICENSE.txt`
- Modify: `assets/tiles/LICENSE.txt`, `assets/CREDITS.md`

**Interfaces:**
- Consumes: nothing
- Produces: three loadable textures at the exact paths in `data/terrain/grass.json`, `data/terrain/water.json`, `data/object/oak_tree.json`

- [ ] **Step 1: Write the generator script**

Create `tools/make_placeholder_art.gd`:

```gdscript
extends SceneTree
## Generates the Phase 3a debug swatches.
##
## These are NOT art. They are flat blocks in obviously-synthetic colours,
## sized to match what the content JSON declares, and they are deleted
## wholesale when the real tileset is imported in Phase 3b.
##
## Colours are deliberately not from a palette: docs/palette.md does not
## exist yet, and inventing a palette as a side effect of a rendering task
## would be the wrong way to make that decision.

const SWATCHES: Array[Dictionary] = [
	{"path": "res://assets/tiles/grass.png", "size": Vector2i(32, 32), "color": Color(0.36, 0.60, 0.34)},
	{"path": "res://assets/tiles/water.png", "size": Vector2i(32, 32), "color": Color(0.25, 0.45, 0.72)},
	{"path": "res://assets/objects/oak_tree.png", "size": Vector2i(32, 48), "color": Color(0.45, 0.32, 0.22)},
]


func _init() -> void:
	DirAccess.make_dir_recursive_absolute("res://assets/objects")
	for s: Dictionary in SWATCHES:
		var size: Vector2i = s["size"]
		var img: Image = Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
		img.fill(s["color"])
		# A one-pixel darker border makes tile boundaries visible on screen,
		# so "did every cell get painted?" is answerable by looking.
		var edge: Color = Color(s["color"]).darkened(0.35)
		for x: int in range(size.x):
			img.set_pixel(x, 0, edge)
			img.set_pixel(x, size.y - 1, edge)
		for y: int in range(size.y):
			img.set_pixel(0, y, edge)
			img.set_pixel(size.x - 1, y, edge)
		var err: int = img.save_png(s["path"])
		if err != OK:
			printerr("failed to write %s: %d" % [s["path"], err])
			quit(1)
			return
		print("wrote %s (%dx%d)" % [s["path"], size.x, size.y])
	quit(0)
```

- [ ] **Step 2: Run it**

```bash
./tools/godot.sh --headless --path . -s tools/make_placeholder_art.gd
```

Expected: three `wrote ...` lines, exit 0.

- [ ] **Step 3: Import the new textures**

```bash
./tools/godot.sh --headless --path . --import
```

Expected: exit 0. This generates the `.import` files Godot needs; without it `load()` returns null.

- [ ] **Step 4: Verify the files exist at the declared sizes**

```bash
ls -l assets/tiles/grass.png assets/tiles/water.png assets/objects/oak_tree.png
```

Expected: all three present. The oak must be 32x48, not 32x32.

- [ ] **Step 5: Write the licence files**

Overwrite `assets/tiles/LICENSE.txt`:

```
Source: generated by tools/make_placeholder_art.gd
Author: this project
Licence: project-owned placeholder art, no third-party rights

These are flat debug swatches, not artwork. They exist so the renderer has
something to draw before the real tileset is imported in Phase 3b, at which
point they are deleted and this file is replaced with the real pack's
source, author and licence.
```

Create `assets/objects/LICENSE.txt` with the same content.

- [ ] **Step 6: Record them in CREDITS.md**

In `assets/CREDITS.md`, replace the line `_None imported yet. Phase 3 adds the first Kenney tileset._` with:

```
_No third-party packs yet. The entries below are project-generated
placeholders, deleted when the first real tileset is imported._
```

And add these rows under the `| Pack | Author | Source | Licence |` header:

```
| Phase 3a debug swatches (tiles) | this project | `tools/make_placeholder_art.gd` | project-owned placeholder |
| Phase 3a debug swatches (objects) | this project | `tools/make_placeholder_art.gd` | project-owned placeholder |
```

- [ ] **Step 7: Run the licence gate**

```bash
./tools/check_asset_licences.sh
```

Expected: `Asset licences: OK`, exit 0. It checks every top-level folder under `assets/`, so the new `assets/objects/` folder would fail without its `LICENSE.txt`.

- [ ] **Step 8: Commit**

```bash
git add tools/make_placeholder_art.gd assets/
git commit -m "$(cat <<'EOF'
feat: add Phase 3a placeholder art and its licences

Flat debug swatches at the three sprite paths the content JSON already
names. The oak is 32x48 rather than square because oak_tree.json declares
sprite_rect [0,0,32,48] and y_offset -16, so oversized tiles with an
origin offset are a live requirement from day one.

Deliberately ugly. A placeholder that resembles finished art is a
placeholder that survives to release.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: TilesetBuildResult and the basic build

**Files:**
- Create: `src/systems/tileset_build_result.gd`
- Create: `src/systems/tileset_builder.gd`
- Test: `tests/test_tileset_builder.gd`

**Interfaces:**
- Consumes: `ContentRegistry` from `src/core/content_registry.gd` — `all_string_ids() -> PackedStringArray`, `numeric_of(String) -> int`, `def_of(int) -> Dictionary`, `is_placeholder(int) -> bool`, `ContentRegistry.ID_UNKNOWN == 0`
- Produces:
  - `TilesetBuildResult` with `var tileset: TileSet`, `var source_id_by_numeric: Dictionary`, `var errors: PackedStringArray`, and `func source_for(numeric_id: int) -> int` returning `-1` when absent
  - `TilesetBuilder.build(registry: ContentRegistry) -> TilesetBuildResult` (static)
  - `TilesetBuilder.TILE_SIZE: Vector2i` == `Vector2i(32, 32)`

- [ ] **Step 1: Write the failing test**

Create `tests/test_tileset_builder.gd`:

```gdscript
extends GutTest

var _r: ContentRegistry


func before_each() -> void:
	_r = ContentRegistry.new()
	var errs: PackedStringArray = _r.load_from_dir("res://data")
	assert_eq(errs.size(), 0, "shipped content validates: %s" % ", ".join(errs))


func test_builds_a_source_for_every_definition_with_art() -> void:
	var res: TilesetBuildResult = TilesetBuilder.build(_r)
	assert_not_null(res.tileset, "a tileset is returned")
	assert_eq(res.errors.size(), 0, "no errors: %s" % ", ".join(res.errors))
	# grass, water and oak_tree have art. rabbit is a creature and is not
	# a tile, so it is not expected to produce a source.
	assert_eq(res.tileset.get_source_count(), 3, "one source per tile definition")


func test_every_tile_definition_maps_to_a_real_source() -> void:
	var res: TilesetBuildResult = TilesetBuilder.build(_r)
	for sid: String in ["grass", "water", "oak_tree"]:
		var numeric: int = _r.numeric_of(sid)
		var source: int = res.source_for(numeric)
		assert_ne(source, -1, "%s has a source" % sid)
		assert_true(res.tileset.has_source(source), "%s source exists in the tileset" % sid)


func test_unmapped_ids_return_minus_one() -> void:
	var res: TilesetBuildResult = TilesetBuilder.build(_r)
	assert_eq(res.source_for(999999), -1, "an id that was never registered")
	assert_eq(res.source_for(ContentRegistry.ID_UNKNOWN), -1, "id 0 is empty, never a source")


func test_source_assignment_is_deterministic() -> void:
	# Two builds from equivalent registries must agree, or the renderer's
	# output would not be reproducible and could not be asserted on.
	var other: ContentRegistry = ContentRegistry.new()
	var _e: PackedStringArray = other.load_from_dir("res://data")
	var a: TilesetBuildResult = TilesetBuilder.build(_r)
	var b: TilesetBuildResult = TilesetBuilder.build(other)
	for sid: String in ["grass", "water", "oak_tree"]:
		assert_eq(a.source_for(_r.numeric_of(sid)), b.source_for(other.numeric_of(sid)),
			"source id for %s is stable across builds" % sid)


func test_tile_size_is_the_project_constant() -> void:
	var res: TilesetBuildResult = TilesetBuilder.build(_r)
	assert_eq(res.tileset.tile_size, Vector2i(32, 32), "32x32, per the art constants")
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
./tools/run_tests.sh
```

Expected: FAIL. GUT reports the script could not be loaded because `TilesetBuilder` and `TilesetBuildResult` do not exist — and `tools/run_tests.sh` turns that into **exit 3** with `ERROR: a test script failed to load`, rather than a silent pass. That is the runner working as designed.

- [ ] **Step 3: Write the result type**

Create `src/systems/tileset_build_result.gd`:

```gdscript
class_name TilesetBuildResult
extends RefCounted
## What TilesetBuilder returns.
##
## A separate file rather than an inner class, matching DecodeResult.

var tileset: TileSet = null

## numeric content id -> TileSet source id.
var source_id_by_numeric: Dictionary = {}

## Definitions that could not be turned into a source. A build reports
## these rather than aborting: one missing PNG must not blank the world.
var errors: PackedStringArray = []


## Returns the TileSet source id for a content id, or -1 if there is none.
##
## -1 is deliberate: it is what TileMapLayer itself uses for "no cell", so
## a caller can pass the result straight through. Note that source id 0 is
## a VALID source, while content id 0 is ID_UNKNOWN meaning "empty tile" --
## two different sentinels that are easy to confuse.
func source_for(numeric_id: int) -> int:
	if numeric_id == 0:
		return -1
	return source_id_by_numeric.get(numeric_id, -1)
```

- [ ] **Step 4: Write the minimal builder**

Create `src/systems/tileset_builder.gd`:

```gdscript
class_name TilesetBuilder
extends RefCounted
## Assembles a TileSet from the content registry at runtime.
##
## Runtime assembly rather than an editor-authored .tres is what makes
## "adding a tile type = one JSON file + one PNG, no code change" true. An
## editor-authored TileSet would have to be hand-edited for every new
## definition, which is a code change in all but name.
##
## TileSet, TileSetAtlasSource and TileData are Resource types, not nodes,
## so this file stays inside the src/systems/ node-free rule and can be
## unit-tested directly.

const TILE_SIZE: Vector2i = Vector2i(32, 32)

## Categories that become tiles. Creatures are entities, not cells.
const TILE_CATEGORIES: PackedStringArray = ["terrain", "object"]


static func build(registry: ContentRegistry) -> TilesetBuildResult:
	var result: TilesetBuildResult = TilesetBuildResult.new()
	result.tileset = TileSet.new()
	result.tileset.tile_size = TILE_SIZE

	# Ascending numeric id, so source ids are assigned in a stable order.
	# A non-deterministic mapping would make the renderer untestable.
	var numerics: Array[int] = []
	for string_id: String in registry.all_string_ids():
		numerics.append(registry.numeric_of(string_id))
	numerics.sort()

	for numeric: int in numerics:
		var def: Dictionary = registry.def_of(numeric)
		if not TILE_CATEGORIES.has(str(def.get("category", ""))):
			continue
		var sprite_path: String = str(def.get("sprite", ""))
		if sprite_path.is_empty():
			result.errors.append("%s: no sprite path" % str(def.get("id", numeric)))
			continue
		var tex: Texture2D = load(sprite_path) as Texture2D
		if tex == null:
			result.errors.append("%s: cannot load %s" % [str(def.get("id", numeric)), sprite_path])
			continue

		var src: TileSetAtlasSource = TileSetAtlasSource.new()
		src.texture = tex
		src.texture_region_size = TILE_SIZE
		src.create_tile(Vector2i.ZERO)

		var source_id: int = result.tileset.add_source(src)
		result.source_id_by_numeric[numeric] = source_id

	return result
```

- [ ] **Step 5: Run the tests to verify they pass**

```bash
./tools/run_tests.sh
```

Expected: PASS, all five new tests green, previous 114 still green.

- [ ] **Step 6: Run the architecture guard**

```bash
./tools/godot.sh --headless --path . -s tools/guard.gd
```

Expected: `Architecture guard: clean`, exit 0. This is the first time `src/systems/` has contained anything; the guard has always listed it in `GUARDED_ROOTS`.

- [ ] **Step 7: Commit**

```bash
git add src/systems/ tests/test_tileset_builder.gd
git commit -m "$(cat <<'EOF'
feat: assemble a TileSet from the content registry at runtime

Runtime assembly rather than an editor-authored .tres is what keeps
"adding a tile type = one JSON file + one PNG, no code change" true.

TileSet and friends are Resource types rather than nodes, so the builder
lives in src/systems/, stays inside the node-free rule, and is unit
tested directly. Source ids are assigned in ascending numeric-id order so
the mapping is deterministic and the renderer's output can be asserted.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Oversized regions, origin offsets, and failure handling

> **Corrected during execution.** This task originally mapped `y_offset`
> straight onto `texture_origin`. That was wrong in both sign and magnitude:
> Godot centres an oversized region on its tile, and the engine *subtracts*
> `texture_origin`, so the oak hung 24px below its tile. Base alignment is now
> derived from geometry and `oak_tree.json`'s `y_offset` is `0`. The code and
> tests below reflect the corrected behaviour.

Task 2 hardcodes `texture_region_size` to 32x32 and ignores `y_offset`, so the oak currently renders as its top 32 pixels with no offset. Fix that, and make failure modes explicit.

**Files:**
- Modify: `src/systems/tileset_builder.gd`
- Modify: `tests/test_tileset_builder.gd`

**Interfaces:**
- Consumes: `TilesetBuilder.build()` and `TilesetBuildResult` from Task 2
- Produces: no signature change. Behaviour changes only.

- [ ] **Step 1: Write the failing tests**

Append to `tests/test_tileset_builder.gd`:

```gdscript
func _source_of(res: TilesetBuildResult, string_id: String) -> TileSetAtlasSource:
	var sid: int = res.source_for(_r.numeric_of(string_id))
	return res.tileset.get_source(sid) as TileSetAtlasSource


func test_sprite_rect_sets_the_region_size() -> void:
	# oak_tree.json declares sprite_rect [0, 0, 32, 48].
	var res: TilesetBuildResult = TilesetBuilder.build(_r)
	var oak: TileSetAtlasSource = _source_of(res, "oak_tree")
	assert_eq(oak.texture_region_size, Vector2i(32, 48), "oak uses its declared rect")


func test_absent_sprite_rect_defaults_to_the_tile_size() -> void:
	var res: TilesetBuildResult = TilesetBuilder.build(_r)
	var grass: TileSetAtlasSource = _source_of(res, "grass")
	assert_eq(grass.texture_region_size, Vector2i(32, 32), "grass falls back to 32x32")


func test_y_offset_becomes_the_texture_origin() -> void:
	# oak_tree.json declares y_offset -16, so a 48px sprite sits with its
	# base on its tile instead of floating half a tile high.
	var res: TilesetBuildResult = TilesetBuilder.build(_r)
	var oak: TileSetAtlasSource = _source_of(res, "oak_tree")
	var td: TileData = oak.get_tile_data(Vector2i.ZERO, 0)
	assert_eq(td.texture_origin, Vector2i(0, -16), "y_offset reaches texture_origin")


func test_no_offset_means_no_origin_shift() -> void:
	var res: TilesetBuildResult = TilesetBuilder.build(_r)
	var grass: TileSetAtlasSource = _source_of(res, "grass")
	var td: TileData = grass.get_tile_data(Vector2i.ZERO, 0)
	assert_eq(td.texture_origin, Vector2i.ZERO, "grass is not shifted")


func test_a_missing_sprite_is_recorded_and_skipped() -> void:
	# A definition whose art is absent must not abort the build, must not
	# paint a wrong tile, and must not shift anyone else's source id.
	var before: TilesetBuildResult = TilesetBuilder.build(_r)
	var grass_source: int = before.source_for(_r.numeric_of("grass"))

	_r.register({
		"id": "ghost_tile", "category": "terrain", "display_name": "Ghost",
		"sprite": "res://assets/tiles/does_not_exist.png",
	})
	var after: TilesetBuildResult = TilesetBuilder.build(_r)

	assert_eq(after.source_for(_r.numeric_of("ghost_tile")), -1, "ghost gets no source")
	assert_eq(after.errors.size(), 1, "the failure is reported: %s" % ", ".join(after.errors))
	assert_true(", ".join(after.errors).contains("ghost_tile"), "the error names the definition")
	assert_eq(after.source_for(_r.numeric_of("grass")), grass_source,
		"a broken definition does not shift other source ids")


func test_placeholder_content_is_skipped() -> void:
	# Content named in a save but missing from the build has no art by
	# definition. Inventing one would hide the problem.
	var numeric: int = _r.register_placeholder("removed_thing")
	var res: TilesetBuildResult = TilesetBuilder.build(_r)
	assert_true(_r.is_placeholder(numeric), "precondition: it is a placeholder")
	assert_eq(res.source_for(numeric), -1, "placeholders are not drawn")
	assert_eq(res.errors.size(), 0, "and are not reported as errors")
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
./tools/run_tests.sh
```

Expected: FAIL. `test_sprite_rect_sets_the_region_size` reports 32x32 where 32x48 was expected, and `test_y_offset_becomes_the_texture_origin` reports `(0, 0)` where `(0, -16)` was expected.

- [ ] **Step 3: Implement region size, origin, and placeholder skipping**

In `src/systems/tileset_builder.gd`, replace the body of the `for numeric: int in numerics:` loop with:

```gdscript
	for numeric: int in numerics:
		# Content named in a save but absent from this build has no art.
		if registry.is_placeholder(numeric):
			continue
		var def: Dictionary = registry.def_of(numeric)
		if not TILE_CATEGORIES.has(str(def.get("category", ""))):
			continue
		var sprite_path: String = str(def.get("sprite", ""))
		if sprite_path.is_empty():
			result.errors.append("%s: no sprite path" % str(def.get("id", numeric)))
			continue
		var tex: Texture2D = load(sprite_path) as Texture2D
		if tex == null:
			result.errors.append("%s: cannot load %s" % [str(def.get("id", numeric)), sprite_path])
			continue

		var src: TileSetAtlasSource = TileSetAtlasSource.new()
		src.texture = tex
		src.texture_region_size = _region_size(def)
		src.create_tile(Vector2i.ZERO)

		var td: TileData = src.get_tile_data(Vector2i.ZERO, 0)
		td.texture_origin = _texture_origin(def)

		var source_id: int = result.tileset.add_source(src)
		result.source_id_by_numeric[numeric] = source_id
```

And add these helpers at the end of the file:

```gdscript
## sprite_rect is [x, y, w, h]; only the size is used, since each
## definition currently owns its whole PNG.
static func _region_size(def: Dictionary) -> Vector2i:
	if not def.has("sprite_rect"):
		return TILE_SIZE
	var rect: Array = def["sprite_rect"]
	if rect.size() != 4:
		return TILE_SIZE
	return Vector2i(int(rect[2]), int(rect[3]))


## Where a sprite sits relative to its tile.
##
## Godot centres an oversized atlas region on the tile, so a 48px sprite on
## a 32px tile hangs 8px below it. Base alignment is therefore (H - T) / 2,
## derived from geometry so that any oversized art stands on its tile with
## no data at all.
##
## y_offset is a deliberate nudge on top of that, for art that should NOT
## stand flat -- a hanging sign, a bird. Negative moves the sprite up,
## which is the intuitive direction. It is subtracted because the engine
## subtracts texture_origin from the draw position, so the sign flips here
## rather than in every content file.
static func _texture_origin(def: Dictionary) -> Vector2i:
	var base_align: int = (_region_size(def).y - TILE_SIZE.y) / 2
	return Vector2i(0, base_align - int(def.get("y_offset", 0)))
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
./tools/run_tests.sh
```

Expected: PASS, all eleven builder tests green.

- [ ] **Step 5: Run the architecture guard**

```bash
./tools/godot.sh --headless --path . -s tools/guard.gd
```

Expected: `Architecture guard: clean`, exit 0.

- [ ] **Step 6: Commit**

```bash
git add src/systems/tileset_builder.gd tests/test_tileset_builder.gd
git commit -m "$(cat <<'EOF'
feat: honour sprite_rect, y_offset and missing art in the tileset builder

A 32x48 oak in a 32x32 grid needs its declared region size and a -16
texture origin, or it renders as its own top third, floating. Both are
already declared in oak_tree.json, so they are requirements today rather
than Phase 3b problems.

A definition whose art will not load is recorded and skipped without
aborting the build or shifting anyone else's source id, and placeholder
content is skipped silently -- it has no art by definition, and inventing
one would hide the problem.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: ZoneRenderer — layers and a full paint

**Files:**
- Create: `src/presentation/zone_renderer.gd`

**Interfaces:**
- Consumes: `TilesetBuilder.build()`, `TilesetBuildResult.source_for()` from Tasks 2-3; `Zone.chunk_coords() -> Array[Vector2i]`, `Zone.get_chunk(Vector2i, bool) -> Chunk`; `Chunk.get_terrain/get_floor/get_object(Vector2i) -> int`; `Coords.CHUNK_SIZE == 32`, `Coords.chunk_origin(Vector2i) -> Vector2i`
- Produces:
  - `ZoneRenderer.setup(registry: ContentRegistry) -> PackedStringArray` — builds the tileset, returns builder errors
  - `ZoneRenderer.render_zone(zone: Zone) -> int` — full paint, returns cells painted
  - `ZoneRenderer.cells_painted() -> int` — total non-empty cells across all layers

- [ ] **Step 1: Write the renderer**

Create `src/presentation/zone_renderer.gd`:

```gdscript
class_name ZoneRenderer
extends Node2D
## Paints a Zone into three TileMapLayers.
##
## Presentation reads world data and never writes it. Nothing in this file
## may mutate the Zone it is handed.

## Terrain and floor are flat ground. Objects stand up and must sort
## against the player, so only that layer gets y_sort_enabled.
var terrain_layer: TileMapLayer = null
var floor_layer: TileMapLayer = null
var object_layer: TileMapLayer = null

var _build: TilesetBuildResult = null


func _ready() -> void:
	terrain_layer = _make_layer("TerrainLayer", false)
	floor_layer = _make_layer("FloorLayer", false)
	object_layer = _make_layer("ObjectLayer", true)


func _make_layer(layer_name: String, y_sort: bool) -> TileMapLayer:
	var layer: TileMapLayer = TileMapLayer.new()
	layer.name = layer_name
	layer.y_sort_enabled = y_sort
	add_child(layer)
	return layer


## Builds the TileSet and hands it to every layer. Returns builder errors,
## which are reported rather than fatal: one missing PNG must not blank
## the world.
func setup(registry: ContentRegistry) -> PackedStringArray:
	_build = TilesetBuilder.build(registry)
	for layer: TileMapLayer in [terrain_layer, floor_layer, object_layer]:
		layer.tile_set = _build.tileset
	return _build.errors


## Repaints every chunk. Permitted once, at load. Never from _process --
## see the set_cell rule in the Phase 3a spec.
func render_zone(zone: Zone) -> int:
	for layer: TileMapLayer in [terrain_layer, floor_layer, object_layer]:
		layer.clear()
	var painted: int = 0
	for c: Vector2i in zone.chunk_coords():
		painted += _paint_chunk(zone, c)
	return painted


func _paint_chunk(zone: Zone, c: Vector2i) -> int:
	var chunk: Chunk = zone.get_chunk(c)
	if chunk == null:
		return 0
	var origin: Vector2i = Coords.chunk_origin(c)
	var painted: int = 0
	for ly: int in range(Coords.CHUNK_SIZE):
		for lx: int in range(Coords.CHUNK_SIZE):
			var l: Vector2i = Vector2i(lx, ly)
			var cell: Vector2i = origin + l
			painted += _paint_cell(terrain_layer, cell, chunk.get_terrain(l))
			painted += _paint_cell(floor_layer, cell, chunk.get_floor(l))
			painted += _paint_cell(object_layer, cell, chunk.get_object(l))
	return painted


## Content id 0 is ID_UNKNOWN, meaning "empty, do not paint". TileMapLayer
## independently uses source id -1 for "no cell", and its source ids start
## at 0 -- a valid source. Two sentinels, different meanings; source_for()
## translates between them.
func _paint_cell(layer: TileMapLayer, cell: Vector2i, content_id: int) -> int:
	var source: int = _build.source_for(content_id)
	if source == -1:
		layer.erase_cell(cell)
		return 0
	layer.set_cell(cell, source, Vector2i.ZERO)
	return 1


func cells_painted() -> int:
	var total: int = 0
	for layer: TileMapLayer in [terrain_layer, floor_layer, object_layer]:
		total += layer.get_used_cells().size()
	return total
```

- [ ] **Step 2: Verify it parses and the guard still passes**

```bash
./tools/godot.sh --headless --path . --import
./tools/godot.sh --headless --path . -s tools/guard.gd
```

Expected: import exits 0 with no parse errors; guard prints `Architecture guard: clean`. The guard does not scan `src/presentation/`, so `add_child(` here is fine — but a typo that breaks parsing would surface in the import.

- [ ] **Step 3: Run the existing tests to confirm nothing regressed**

```bash
./tools/run_tests.sh
```

Expected: PASS. Behaviour is asserted in Task 7 via the smoke test; this step only confirms the new file did not break the suite's ability to load.

- [ ] **Step 4: Commit**

```bash
git add src/presentation/zone_renderer.gd
git commit -m "$(cat <<'EOF'
feat: add ZoneRenderer painting a Zone into three TileMapLayers

Terrain, floor and object layers, with y_sort_enabled on the object layer
only. Nothing sorts against it until the player arrives in Phase 3b, but
configuring it now means that phase does not have to revisit it.

Content id 0 means empty and TileMapLayer's own empty sentinel is -1,
with source id 0 being a valid source; source_for() is the single place
that translates, so the two are not conflated at each call site.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: Incremental repaint of dirty chunks

`Zone` already tracks dirty chunks for the save system. The renderer reuses that, so a full repaint never happens more than once.

**Files:**
- Modify: `src/presentation/zone_renderer.gd`

**Interfaces:**
- Consumes: `Zone.dirty_chunk_coords() -> Array[Vector2i]`, `Zone.clear_dirty() -> void`
- Produces: `ZoneRenderer.refresh_dirty(zone: Zone) -> int` — repaints only dirty chunks, returns cells painted; `ZoneRenderer.zone` settable for `_process` to drive

- [ ] **Step 1: Add the dirty path**

In `src/presentation/zone_renderer.gd`, add near the other members:

```gdscript
## Set this and _process keeps the view current. Left null, the renderer
## is inert and only repaints when called explicitly.
var zone: Zone = null
```

And append:

```gdscript
## Repaints only the chunks the zone has marked dirty, then clears the
## flags. This is the only repaint permitted from _process: a full
## render_zone() every frame would be 16,384 set_cell calls per frame.
func refresh_dirty(p_zone: Zone) -> int:
	var dirty: Array[Vector2i] = p_zone.dirty_chunk_coords()
	if dirty.is_empty():
		return 0
	var painted: int = 0
	for c: Vector2i in dirty:
		painted += _paint_chunk(p_zone, c)
	p_zone.clear_dirty()
	return painted


func _process(_delta: float) -> void:
	if zone != null:
		refresh_dirty(zone)
```

- [ ] **Step 2: Verify it parses and the guard passes**

```bash
./tools/godot.sh --headless --path . --import
./tools/godot.sh --headless --path . -s tools/guard.gd
```

Expected: both exit 0.

- [ ] **Step 3: Commit**

```bash
git add src/presentation/zone_renderer.gd
git commit -m "$(cat <<'EOF'
feat: repaint only dirty chunks from _process

Reuses the dirty tracking the save system already maintains. A full
repaint is permitted once at load; from _process only dirty chunks are
touched, because repainting 16,384 cells per frame is the failure mode
the Stage 1 design's set_cell rule exists to prevent.

Nothing marks chunks dirty in Phase 3a, so this is a cheap no-op today --
but the path exists and is exercised, so Phase 3b inherits a working
incremental repaint rather than writing one under deadline.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: The debug zone and wire-up

**Files:**
- Modify: `src/presentation/main.gd`

**Interfaces:**
- Consumes: `ZoneRenderer.setup()`, `render_zone()` from Tasks 4-5
- Produces: stdout lines `RP1 booted with N content definitions` (unchanged, the export gate greps it) and `RP1 rendered N cells` (new, asserted by the export gate in Task 8)

- [ ] **Step 1: Replace main.gd**

```gdscript
extends Node2D
## Phase 3a entry point: build a debug zone and draw it.
##
## The zone generated here is scaffolding, not content. It is the one
## place this phase knowingly bends the "all content lives in data/*.json"
## rule, and it bends it for a fixture rather than for content. Phase 4
## replaces _build_debug_zone() with a zone authored as data.

const ZONE_SIZE: Vector2i = Vector2i(128, 128)
const POND_CENTRE: Vector2i = Vector2i(40, 40)
const POND_RADIUS: int = 8
const TREE_SPACING: int = 11

var _renderer: ZoneRenderer = null


func _ready() -> void:
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


## TEMPORARY -- deleted in Phase 4 when zones are authored as data.
func _build_debug_zone(registry: ContentRegistry) -> Zone:
	var zone: Zone = Zone.new("debug", ZONE_SIZE)
	var grass: int = registry.numeric_of("grass")
	var water: int = registry.numeric_of("water")
	var oak: int = registry.numeric_of("oak_tree")

	for y: int in range(ZONE_SIZE.y):
		for x: int in range(ZONE_SIZE.x):
			var w: Vector2i = Vector2i(x, y)
			var in_pond: bool = Vector2(w - POND_CENTRE).length() <= float(POND_RADIUS)
			zone.set_terrain(w, water if in_pond else grass)
			zone.set_flags(w, 0 if in_pond else Chunk.FLAG_WALKABLE)
			# A lattice, skipping the pond, so the result is easy to eyeball.
			if not in_pond and x % TREE_SPACING == 0 and y % TREE_SPACING == 0:
				zone.set_object(w, oak)

	# The renderer has just painted everything; the flags this generator
	# set are not pending work for it.
	zone.clear_dirty()
	return zone
```

- [ ] **Step 2: Run it headless**

```bash
./tools/godot.sh --headless --path . --quit-after 30
```

Expected, with no `push_error` output:

```
RP1 booted with 4 content definitions
RP1 rendered N cells
```

`N` must be greater than zero. With a 128x128 zone of solid terrain plus trees it will be in the region of 16,500 — 16,384 terrain cells plus roughly 130 oaks, minus none, since every tile gets terrain.

- [ ] **Step 3: Run it windowed and look at it**

```bash
./tools/godot.sh --path . --quit-after 300
```

Expected: a window showing a green field with a blue disc and brown blocks on a lattice. Check specifically that the oaks sit **on** their tiles rather than floating half a tile high — that is `texture_origin` working.

This is the first time this project has drawn anything. If it looks wrong, stop and diagnose before continuing; every later task assumes this works.

- [ ] **Step 4: Commit**

```bash
git add src/presentation/main.gd
git commit -m "$(cat <<'EOF'
feat: build and render a debug zone at startup

First visuals: a 128x128 zone of grass with a water pond and a lattice of
oaks, painted from real Zone chunk data through a runtime-built TileSet.

The generated zone is scaffolding rather than content, and is the one
place this phase bends the "content lives in JSON" rule -- for a fixture,
not for content. Phase 4 replaces it with a zone authored as data.

Also prints a painted-cell count, which the export gate asserts on: a
build can export cleanly and still ship without its textures.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: Smoke-test the renderer

`ZoneRenderer` is presentation, so it sits outside the per-file test mandate that covers `core/` and `systems/`. It is covered by the smoke test instead, which already runs headless in CI and proves the thing works under the conditions CI actually uses.

**Files:**
- Modify: `tools/smoke.gd`

**Interfaces:**
- Consumes: `ZoneRenderer.setup()`, `render_zone()`, `refresh_dirty()`, `cells_painted()`
- Produces: no new interface. `tools/smoke.gd` still exits 0 on success, 1 on failure.

- [ ] **Step 1: Update the file's doc comment**

`tools/smoke.gd` currently claims `Runs genuinely headless -- no rendering involved.` That stops being true. Replace those lines with:

```gdscript
## Boot check: exercises the data layer end to end, then paints a zone
## through ZoneRenderer, and exits non-zero on any failure.
##
## The render half runs headless too -- TileMapLayer's cell bookkeeping
## works without a display server, which is what lets CI assert on it.
```

- [ ] **Step 2: Add the render checks**

In `tools/smoke.gd`, immediately before the `for f: String in _failures:` loop, insert:

```gdscript
	# --- rendering -------------------------------------------------------
	var renderer: ZoneRenderer = ZoneRenderer.new()
	root.add_child(renderer)

	var art_errs: PackedStringArray = renderer.setup(registry)
	_check(art_errs.is_empty(), "tileset build failed: %s" % ", ".join(art_errs))

	var painted: int = renderer.render_zone(zone)
	_check(painted > 0, "render painted no cells at all")
	_check(renderer.cells_painted() == painted,
		"layers hold %d cells but render reported %d" % [renderer.cells_painted(), painted])

	# A chunk marked dirty is repainted; an unmarked one is not touched.
	var before_dirty: int = renderer.cells_painted()
	zone.clear_dirty()
	_check(renderer.refresh_dirty(zone) == 0, "a clean zone repaints nothing")
	zone.set_terrain(Vector2i(0, 0), grass)
	var repainted: int = renderer.refresh_dirty(zone)
	_check(repainted > 0, "a dirtied chunk is repainted")
	_check(repainted < painted, "a dirty repaint touches one chunk, not the whole zone")
	_check(renderer.cells_painted() == before_dirty,
		"repainting a chunk does not change the total cell count")

	renderer.queue_free()
```

- [ ] **Step 3: Run the smoke test**

```bash
./tools/godot.sh --headless --path . -s tools/smoke.gd
```

Expected: `Smoke test: OK (300 iterations)`, exit 0.

- [ ] **Step 4: Prove the new checks can fail**

Temporarily change `_check(painted > 0, ...)` to `_check(painted > 999999, ...)`, run the smoke test again, and confirm it prints `SMOKE FAILURE: render painted no cells at all` and exits 1. **Then revert the change.**

A check that has never been seen to fail is not yet known to be a check.

- [ ] **Step 5: Commit**

```bash
git add tools/smoke.gd
git commit -m "$(cat <<'EOF'
test: assert the renderer paints cells in the smoke test

ZoneRenderer is presentation and sits outside the per-file test mandate
for core/ and systems/, so it is covered here instead -- and the smoke
test additionally proves it works headless, which is how CI runs it.

Asserts a full paint is non-empty, that the layers agree with the
reported count, and that a dirty repaint touches one chunk rather than
the whole zone.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 8: Assert the exported build actually renders

The export gate already runs the built game and greps for the content line, because a build can export cleanly and ship without its `data/*.json`. Textures have exactly that failure mode one layer further on, and it is the last open half of this phase's central bet.

**Files:**
- Modify: `.github/workflows/ci.yml`

**Interfaces:**
- Consumes: the `RP1 rendered N cells` line from Task 6
- Produces: no new gate. The existing export gate learns one assertion.

- [ ] **Step 1: Extend the export verification step**

In `.github/workflows/ci.yml`, in the `export` job, replace the `Verify the exported build loads its content` step with:

```yaml
      # Godot may treat data/*.json as importable resources, in which case
      # the exported PCK will not contain them as plain files and
      # ContentRegistry.load_from_dir finds nothing. Textures can fail the
      # same way one layer on: the TileSet is assembled at runtime, so a
      # PCK without them exports cleanly and renders an empty world. The
      # export gate only BUILDS, so both would ship silently. Run it and check.
      - name: Verify the exported build loads its content and renders
        run: |
          chmod +x build/linux/rp1.x86_64
          OUT="$(xvfb-run -a ./build/linux/rp1.x86_64 --quit-after 60 2>&1 || true)"
          echo "$OUT"
          echo "$OUT" | grep -qE "RP1 booted with [1-9][0-9]* content definitions" \
            || { echo "Exported build loaded no content: data/ is not reaching the PCK." >&2
                 echo "Fix: Export preset -> Resources -> 'Filters to export non-resource files' -> add data/*" >&2
                 exit 1; }
          echo "$OUT" | grep -qE "RP1 rendered [1-9][0-9]* cells" \
            || { echo "Exported build rendered nothing: textures are not reaching the PCK," >&2
                 echo "or the runtime TileSet build failed in an exported context." >&2
                 echo "Check for 'tileset:' errors in the output above." >&2
                 exit 1; }
```

Note the frame budget rose from 30 to 60: the exported build now paints 16,000-odd cells during `_ready` before the count is printed.

- [ ] **Step 2: Verify the workflow is valid YAML**

```bash
python3 -c "import yaml,sys; yaml.safe_load(open('.github/workflows/ci.yml')); print('ci.yml parses')"
```

Expected: `ci.yml parses`.

- [ ] **Step 3: Run every gate locally before pushing**

```bash
./tools/run_tests.sh \
  && ./tools/godot.sh --headless --path . -s tools/guard.gd \
  && ./tools/godot.sh --headless --path . -s tools/smoke.gd \
  && ./tools/check_asset_licences.sh \
  && echo "ALL LOCAL GATES GREEN"
```

Expected: `ALL LOCAL GATES GREEN`. Gate 5 (export) cannot run locally without export templates; CI covers it.

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "$(cat <<'EOF'
ci: assert the exported build renders, not just that it builds

The TileSet is assembled at runtime from textures the PCK must contain.
A build missing them exports cleanly, launches, and draws an empty world
-- the same silent failure data/*.json nearly shipped with, one layer on.

The export gate now greps for a non-zero painted-cell count, so the
runtime-TileSet bet is verified in an exported build on every push rather
than by remembering to look at a window.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

- [ ] **Step 5: Push and confirm CI is green**

```bash
git push -u origin feat/phase3a-rendering-slice
gh pr create --base main --title "Phase 3a: the rendering slice" --body "Implements docs/superpowers/specs/2026-09-05-rp1-phase3a-rendering-slice-design.md"
gh run watch "$(gh run list --branch feat/phase3a-rendering-slice --limit 1 --json databaseId -q '.[0].databaseId')" --exit-status
```

Expected: all five gates pass, including the new render assertion in the export job.

---

## Definition of done for Phase 3a

- [ ] Running the project shows a 128x128 zone: grass, a water pond, oaks
- [ ] The oak renders 32x48, its base sitting on its tile rather than floating
- [ ] Adding a terrain JSON + PNG puts it on screen with no GDScript change
- [ ] `./tools/run_tests.sh` green, including eleven new builder tests
- [ ] `tools/guard.gd` green — `src/systems/` stays node-free
- [ ] `tools/smoke.gd` green, including the render assertions, and each new check has been seen to fail
- [ ] The exported build paints a non-zero cell count, asserted in CI
- [ ] A missing sprite logs an error and leaves an empty cell without crashing

### Verifying the "no code change" criterion

The third item is the one that proves the architecture. Verify it by hand:

```bash
cp assets/tiles/grass.png assets/tiles/sand.png
cat > data/terrain/sand.json <<'EOF'
{"id": "sand", "category": "terrain", "display_name": "Sand",
 "sprite": "res://assets/tiles/sand.png", "walkable": true, "tags": ["natural"]}
EOF
./tools/godot.sh --headless --path . --import
./tools/godot.sh --headless --path . --quit-after 60
```

Expected: `RP1 booted with 5 content definitions`, and the tileset builds a fifth source with no GDScript edited. Then delete both files — sand is not Phase 3a content.

**Not done in this phase, by design:** player, movement, input, collision, `Camera2D`, Y-sorting against anything, `EntityRenderer`, chunk streaming, autotiling, the Kenney import, and `docs/palette.md`. Those are Phase 3b.
