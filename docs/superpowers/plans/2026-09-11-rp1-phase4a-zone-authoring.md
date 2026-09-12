# Phase 4a — Zone Authoring Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The 128x128 home zone becomes three PNGs and a JSON file under
`data/zone/home/` that the game reads at boot, and CI gate 7 makes an
unpaintable zone unmergeable.

**Architecture:** One PNG per tile column (`terrain`, `object`, `height`), one
pixel per tile, with a per-layer colour -> string-id legend in `zone.json`. A
node-free `ZoneLoader` in `src/core/` decodes them into a `Zone`, reporting
errors rather than aborting. `tools/check_zone.gd` runs that same loader as a
CI gate, so the gate and the game cannot disagree about what a valid zone is.

**Tech Stack:** Godot 4.7.2 standard build, GDScript, GUT for tests, bash for
CI gates.

**Spec:** `docs/superpowers/specs/2026-09-11-rp1-phase4a-zone-authoring-design.md`

## Global Constraints

Every task's requirements implicitly include this section.

- Godot **4.7.2 standard build**, never the Mono build. Invoke it only through
  `./tools/godot.sh` — never a hardcoded binary path.
- **GDScript only.** Static typing everywhere: `var x: int = 0`,
  `func f(a: Vector2i) -> void:`.
- `src/core/` and `src/systems/` extend **`RefCounted` or `Object` only**, and
  may not contain the strings `get_tree(`, `Engine.`, `.tscn`, `get_node(`,
  `add_child(` or `queue_free(`. Enforced by `tools/guard.gd`.
- Run tests **only** with `./tools/run_tests.sh`. Never call `gut_cmdln.gd`
  directly: the runner does a mandatory `--import` pass first, and without it
  GUT reports missing `class_name`s and still exits 0.
- **TDD, strictly.** Write the failing test, run it, watch it fail for the
  right reason, implement minimally, watch it pass.
- All game content lives in `data/*.json`. Never hardcode content in GDScript,
  and never `match` over content types.
- Presentation reads world data; world data never reads presentation.
- Error output is capped at **8** distinct problems per file, matching
  `MAX_REPORTED` in `tools/check_palette.gd`.
- Tile size is 32x32. The palette is fixed (`docs/palette.md`); imported art is
  re-quantized onto it by `tools/quantize.gd`, never used as authored.
- Every folder under `assets/` has a `LICENSE.txt`. **Never add a CC-NC asset.**
- Commit prefixes: `feat:`, `test:`, `ci:`, `docs:`, `fix:`.
- **Each task produces two commits:** the code, then a `docs:` commit ticking
  that task's checkboxes. Tick them with
  `python3 tools/mark_task_done.py <N> --plan docs/superpowers/plans/2026-09-11-rp1-phase4a-zone-authoring.md`
  — never by hand.

---

## File structure

**Created**

| Path | Responsibility |
|---|---|
| `data/schema/zone.json` | The zone document contract, enforced by `SchemaValidator` |
| `data/zone/home/zone.json` | Metadata, per-layer legend, entity spawns |
| `data/zone/home/terrain.png` | One pixel per tile, the terrain column |
| `data/zone/home/object.png` | One pixel per tile, the object column |
| `data/zone/home/height.png` | Red channel is the height byte |
| `data/zone/home/*.png.import` | `importer="keep"`, so Godot ships the bytes verbatim |
| `src/core/zone_load_result.gd` | `zone`, `player_spawn`, `errors` |
| `src/core/zone_loader.gd` | Directory -> `Zone`. The only file that knows the format |
| `tools/seed_zone.gd` | One-shot authoring tool. **Deleted in Task 10** |
| `tools/zone_legend.gd` | Emits a labelled swatch PNG for hand-editing |
| `tools/check_zone.sh` / `tools/check_zone.gd` | CI gate 7 |
| `tests/test_zone_schema.gd` | The document contract |
| `tests/test_zone_loader.gd` | Decoding, errors, walkability, dirty flags |
| `tests/test_zone_home.gd` | The real shipped zone |
| `tests/test_zone_import_mode.gd` | The maps are still `importer="keep"` |
| `tests/test_zone_load_budget.gd` | 128x128 loads in under a second |
| `data/terrain/dirt.json` + 10 `data/object/*.json` | The new content defs |

**Modified**

| Path | Change |
|---|---|
| `export_presets.cfg` | `include_filter` widened so the maps reach the pack |
| `tools/import_manifest.json` | One slice entry per new tile |
| `src/presentation/main.gd` | `_build_debug_zone()` deleted; loads the authored zone |
| `.github/workflows/ci.yml` | Gate 7 added after the Palette step |
| `assets/CREDITS.md` | Slice count refreshed (no new pack, no licence change) |

`ZoneLoader` is the only file that knows the on-disk format. `check_zone.gd`
calls it rather than re-reading PNGs, so a rule can never drift between the
gate and the game.

---

## Task order and why

Task 2 comes second on purpose. The spec's §5 names the export filter as the
one thing taken on documentation rather than evidence, and everything shipped
depends on it. It is verified against a real exported pack before any code
depends on it, while backing out is still cheap.

Tasks 3-7 build the loader against generated fixtures, so none of them wait on
art. Task 8 boots the game into the authored zone while it is still 8x8 — the
zone grows to its real size in Task 10, by which point nothing structural is
left to discover.

---

## Task 1: The zone document schema and a minimal authored zone

**Files:**
- Create: `data/schema/zone.json`
- Create: `tools/seed_zone.gd`
- Create: `data/zone/home/zone.json`, `terrain.png`, `object.png`, `height.png`
- Test: `tests/test_zone_schema.gd`

**Interfaces:**
- Consumes: `SchemaValidator.validate(def: Dictionary, schema: Dictionary) -> PackedStringArray` (existing)
- Produces: the on-disk contract every later task reads. Legend colours fixed
  here and used unchanged throughout: terrain `00ff00` grass, `0000ff` water,
  `ff8000` dirt; object `000000` null (empty), `008000` oak_tree.

This task ships a **real but tiny** zone: 8x8, one pond tile, one oak. It grows
to 128x128 in Task 10. Everything structural is exercised at a size a human can
check by counting.

- [x] **Step 1: Write the failing test**

Create `tests/test_zone_schema.gd`:

```gdscript
extends GutTest
## data/schema/zone.json is the contract for an authored zone document.
##
## SchemaValidator enforces four rules -- required fields, field types,
## unknown fields, and a category match -- and this asserts all four apply
## here, so a typo in zone.json is an error rather than a setting that
## silently does nothing.

const SCHEMA_PATH: String = "res://data/schema/zone.json"
const ZONE_PATH: String = "res://data/zone/home/zone.json"

var _schema: Dictionary


func _read(path: String) -> Dictionary:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	assert_not_null(f, "%s must exist" % path)
	if f == null:
		return {}
	var text: String = f.get_as_text()
	f.close()
	var parser: JSON = JSON.new()
	assert_eq(parser.parse(text), OK, "%s must be valid JSON" % path)
	return parser.data as Dictionary


func before_each() -> void:
	_schema = _read(SCHEMA_PATH)


func _valid_doc() -> Dictionary:
	return {
		"id": "t",
		"category": "zone",
		"display_name": "T",
		"size": [8, 8],
		"maps": {"terrain": "terrain.png"},
		"legend": {"terrain": {"00ff00": "grass"}},
		"player_spawn": [4.5, 4.5],
	}


func test_the_shipped_zone_validates() -> void:
	assert_eq(SchemaValidator.validate(_read(ZONE_PATH), _schema), PackedStringArray(),
		"data/zone/home/zone.json must satisfy its own schema")


func test_a_minimal_document_validates() -> void:
	assert_eq(SchemaValidator.validate(_valid_doc(), _schema), PackedStringArray())


func test_each_required_field_is_required() -> void:
	for field: String in ["id", "category", "display_name", "size", "maps",
			"legend", "player_spawn"]:
		var doc: Dictionary = _valid_doc()
		doc.erase(field)
		assert_gt(SchemaValidator.validate(doc, _schema).size(), 0,
			"removing '%s' must be an error" % field)


func test_an_unknown_field_is_rejected() -> void:
	var doc: Dictionary = _valid_doc()
	doc["spawn_point"] = [1, 1]
	assert_gt(SchemaValidator.validate(doc, _schema).size(), 0,
		"a typo'd key must be an error, not a setting that does nothing")


func test_the_wrong_category_is_rejected() -> void:
	var doc: Dictionary = _valid_doc()
	doc["category"] = "terrain"
	assert_gt(SchemaValidator.validate(doc, _schema).size(), 0)


func test_the_optional_fields_are_accepted() -> void:
	var doc: Dictionary = _valid_doc()
	doc["biome"] = "temperate"
	doc["generation_seed"] = 0
	doc["entities"] = [{"type": "rabbit", "at": [2.5, 2.5]}]
	assert_eq(SchemaValidator.validate(doc, _schema), PackedStringArray())
```

- [x] **Step 2: Run the test and watch it fail**

Run: `./tools/run_tests.sh`

Expected: FAIL. `data/schema/zone.json` does not exist, so `_read` asserts on a
null `FileAccess` and every test that needs the schema fails.

- [x] **Step 3: Write the schema**

Create `data/schema/zone.json`:

```json
{
  "category": "zone",
  "required": {
    "id": "String", "category": "String", "display_name": "String",
    "size": "Array", "maps": "Dictionary", "legend": "Dictionary",
    "player_spawn": "Array"
  },
  "optional": {
    "biome": "String", "generation_seed": "int", "entities": "Array"
  }
}
```

- [x] **Step 4: Write the seeding tool**

Create `tools/seed_zone.gd`. This is a **one-shot authoring tool**, deleted in
Task 10 once its final output is committed — the same treatment
`tools/make_placeholder_art.gd` got in Phase 3c. The PNGs it writes are the
source of truth from the moment they land; nothing ever reads this file at
runtime.

```gdscript
extends SceneTree
## Writes the first draft of data/zone/home/. Build-time only, never shipped.
##
##   ./tools/godot.sh --headless --path . -s tools/seed_zone.gd
##
## DELETED at the end of Phase 4a. Its output is the source of truth: once
## the PNGs are committed, edit them in a pixel editor, not by editing this.

const OUT_DIR: String = "res://data/zone/home"

const GRASS: Color = Color8(0, 255, 0)
const WATER: Color = Color8(0, 0, 255)
const EMPTY: Color = Color8(0, 0, 0)
const OAK: Color = Color8(0, 128, 0)

const SIZE: Vector2i = Vector2i(8, 8)


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)

	var terrain: Image = _filled(GRASS)
	terrain.set_pixel(5, 5, WATER)
	terrain.set_pixel(6, 5, WATER)
	terrain.set_pixel(5, 6, WATER)
	terrain.set_pixel(6, 6, WATER)

	var object: Image = _filled(EMPTY)
	object.set_pixel(2, 2, OAK)

	# Stage 1 renders flat. The column is carried and persisted from day one
	# because adding one to a save format later is painful.
	var height: Image = _filled(EMPTY)

	var failures: int = 0
	failures += _save(terrain, "terrain.png")
	failures += _save(object, "object.png")
	failures += _save(height, "height.png")

	if failures > 0:
		printerr("seed_zone: %d file(s) failed to write" % failures)
		quit(1)
		return
	print("seed_zone: wrote a %dx%d zone to %s" % [SIZE.x, SIZE.y, OUT_DIR])
	quit(0)


func _filled(c: Color) -> Image:
	var img: Image = Image.create_empty(SIZE.x, SIZE.y, false, Image.FORMAT_RGBA8)
	img.fill(c)
	return img


func _save(img: Image, file_name: String) -> int:
	var err: int = img.save_png(OUT_DIR.path_join(file_name))
	if err != OK:
		printerr("seed_zone: cannot write %s (error %d)" % [file_name, err])
		return 1
	return 0
```

- [x] **Step 5: Run the seeding tool**

Run: `./tools/godot.sh --headless --path . -s tools/seed_zone.gd`

Expected: `seed_zone: wrote a 8x8 zone to res://data/zone/home`, and three PNGs
exist under `data/zone/home/`.

- [x] **Step 6: Write the zone document**

Create `data/zone/home/zone.json`:

```json
{
  "id": "home",
  "category": "zone",
  "display_name": "Home Valley",
  "size": [8, 8],
  "biome": "temperate",
  "generation_seed": 0,
  "maps": {
    "terrain": "terrain.png",
    "object": "object.png",
    "height": "height.png"
  },
  "legend": {
    "terrain": {"00ff00": "grass", "0000ff": "water"},
    "object": {"000000": null, "008000": "oak_tree"}
  },
  "player_spawn": [1.5, 1.5],
  "entities": []
}
```

- [x] **Step 7: Run the tests and watch them pass**

Run: `./tools/run_tests.sh`

Expected: PASS, with one more script than before and six new tests.

- [x] **Step 8: Commit**

```bash
git add data/schema/zone.json data/zone/home tools/seed_zone.gd tests/test_zone_schema.gd
git commit -m "$(cat <<'EOF'
feat: add the zone document schema and a minimal authored zone

The format Phase 4a exists to introduce: one PNG per tile column plus a
per-layer colour legend. Eight by eight for now, with one pond and one
oak, so everything structural is exercised at a size a human can check by
counting. Task 10 grows it to 128x128 and deletes the seeding tool.

Reusing SchemaValidator brings two of its rules along: zone.json carries
a "category" like every content file, and an undeclared key is an error
rather than a setting that silently does nothing.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

- [x] **Step 9: Tick this task**

```bash
python3 tools/mark_task_done.py 1 --plan docs/superpowers/plans/2026-09-11-rp1-phase4a-zone-authoring.md
git add docs/superpowers/plans/2026-09-11-rp1-phase4a-zone-authoring.md
git commit -m "docs: tick Phase 4a task 1"
```

---

## Task 2: Ship the maps in the exported build

**Files:**
- Create: `data/zone/home/terrain.png.import`, `object.png.import`, `height.png.import`
- Modify: `export_presets.cfg:10` and `:36` (`include_filter`, both presets)
- Test: `tests/test_zone_import_mode.gd`

**Interfaces:**
- Consumes: the three PNGs from Task 1
- Produces: nothing in code. The guarantee that `res://data/zone/home/*.png`
  is readable byte-for-byte inside an exported pack, which every later task
  assumes.

**Why this is second.** Godot imports a `.png` as a `CompressedTexture2D`, and
`export_presets.cfg` currently includes only `*.json`. Left alone, the zone
would load perfectly in the editor and the *shipped* build would boot to an
empty world. `assets/tiles/grass.png.import` also shows
`process/fix_alpha_border=true`, which rewrites the RGB of transparent pixels —
harmless for a sprite, fatal for a colour-keyed index map.

The spec flags the exact glob syntax an export filter accepts for a path
pattern as the one claim taken on documentation rather than evidence. This task
settles it against a real pack.

- [x] **Step 1: Write the failing test**

Create `tests/test_zone_import_mode.gd`:

```gdscript
extends GutTest
## The zone maps are data, not textures.
##
## Godot would otherwise import them as CompressedTexture2D, and
## fix_alpha_border would rewrite the RGB of transparent pixels. Opening
## the project in the editor is exactly the kind of ordinary act that
## reverts an import mode, so this asserts it every run -- the same guard
## tests/test_import_manifest.gd applies to art.

const MAPS: PackedStringArray = [
	"res://data/zone/home/terrain.png",
	"res://data/zone/home/object.png",
	"res://data/zone/home/height.png",
]


func _import_text(png_path: String) -> String:
	var path: String = png_path + ".import"
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	assert_not_null(f, "%s must exist" % path)
	if f == null:
		return ""
	var text: String = f.get_as_text()
	f.close()
	return text


func test_every_map_is_kept_rather_than_imported() -> void:
	for png: String in MAPS:
		assert_string_contains(_import_text(png), 'importer="keep"',
			"%s must not be imported as a texture" % png)


func test_no_map_is_imported_as_a_texture() -> void:
	for png: String in MAPS:
		assert_false(_import_text(png).contains('importer="texture"'),
			"%s was re-imported as a texture; re-apply importer=\"keep\"" % png)
```

- [x] **Step 2: Run the test and watch it fail**

Run: `./tools/run_tests.sh`

Expected: FAIL. No `.import` files exist yet for the maps (Godot has not been
asked to import `data/` at all), so `assert_not_null` fails three times.

- [x] **Step 3: Write the keep-mode import files**

Create all three, identical except for the path. `data/zone/home/terrain.png.import`:

```
[remap]

importer="keep"
```

Repeat verbatim for `data/zone/home/object.png.import` and
`data/zone/home/height.png.import`. A `keep` remap needs no `type`, `uid`,
`path`, `[deps]` or `[params]` section — the engine copies the file and records
nothing to rebuild.

- [x] **Step 4: Run an import pass and confirm the mode survives it**

```bash
./tools/godot.sh --headless --path . --import
grep -c 'importer="keep"' data/zone/home/*.png.import
```

Expected: `1` for each of the three files. If any now says `importer="texture"`,
the engine has overwritten the file — re-apply Step 3 and re-run; it sticks on
the second pass because the `.import` file then predates the source scan.

- [x] **Step 5: Run the test and watch it pass**

Run: `./tools/run_tests.sh`

Expected: PASS.

- [x] **Step 6: Widen the export filter**

`export_presets.cfg` has two presets (Linux and Windows) and **both** must
change. Edit line 10 and line 36:

```diff
-include_filter="*.json"
+include_filter="*.json,data/zone/*"
```

No space after the comma: the filter is split on commas and the pattern is
matched against the resource path, so a leading space would make the second
pattern ` data/zone/*` and match nothing.

- [x] **Step 7: Prove the bytes reach the pack**

```bash
./tools/godot.sh --headless --path . --export-pack "Linux" /tmp/rp1_probe.pck
grep -ac "data/zone/home/terrain.png" /tmp/rp1_probe.pck
```

Expected: `1` or more. A `.pck` stores its file paths as plain strings, so a
grep is a sufficient and dependency-free check that the raw PNG was packed
rather than replaced by a `.ctex`.

Also confirm the imported-texture form is **absent**:

```bash
grep -ac "terrain.png-.*\.ctex" /tmp/rp1_probe.pck || echo "no ctex, correct"
```

- [x] **Step 8: If the path pattern did not match, apply the fallback**

Only if Step 7 found nothing. Rename the three maps to
`terrain.zonemap.png`, `object.zonemap.png`, `height.zonemap.png` (renaming
their `.import` files to match), update the `maps` block in
`data/zone/home/zone.json`, update `MAPS` in `tests/test_zone_import_mode.gd`,
update `SIZE`-adjacent filenames in `tools/seed_zone.gd`, and set
`include_filter="*.json,*.zonemap.png"` — a plain suffix wildcard, which the
filter unambiguously supports. Re-run Step 7.

Record which form worked in the commit message. Later tasks refer to the maps
by the names in `zone.json`, so nothing else changes.

- [x] **Step 9: Clean up and commit**

```bash
rm -f /tmp/rp1_probe.pck
git add data/zone/home export_presets.cfg tests/test_zone_import_mode.gd
git commit -m "$(cat <<'EOF'
feat: ship the zone maps as bytes, not textures

A colour-keyed PNG is data. Godot cannot tell, and would have imported
these as CompressedTexture2D with fix_alpha_border rewriting the RGB of
transparent pixels -- then left them out of the pack entirely, since
include_filter was "*.json". The editor would have looked perfect and the
shipped build would have booted to an empty world.

importer="keep" on each map, both export presets widened, and verified
against a real --export-pack rather than against the documentation. A
test asserts the import mode every run, because opening the project in
the editor is exactly what reverts it.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

- [x] **Step 10: Tick this task**

```bash
python3 tools/mark_task_done.py 2 --plan docs/superpowers/plans/2026-09-11-rp1-phase4a-zone-authoring.md
git add docs/superpowers/plans/2026-09-11-rp1-phase4a-zone-authoring.md
git commit -m "docs: tick Phase 4a task 2"
```

---

## Task 3: `ZoneLoadResult` and the terrain layer, with its error paths

**Files:**
- Create: `src/core/zone_load_result.gd`, `src/core/zone_loader.gd`
- Test: `tests/test_zone_loader.gd`

**Interfaces:**
- Consumes: `Zone`, `Chunk`, `Coords`, `ContentRegistry`, `SchemaValidator`
- Produces:
  - `ZoneLoadResult` with `var zone: Zone = null`,
    `var player_spawn: Vector2 = Vector2.ZERO`,
    `var errors: PackedStringArray = []`
  - `ZoneLoader.load_zone(dir: String, registry: ContentRegistry) -> ZoneLoadResult`
  - `ZoneLoader.MAX_REPORTED: int = 8`

Fixtures are generated into `user://` rather than committed: a 4x4 zone written
by the test is readable *in* the test, which a committed PNG is not.

- [x] **Step 1: Write the failing test**

Create `tests/test_zone_loader.gd`:

```gdscript
extends GutTest
## ZoneLoader turns an authored directory into a Zone.
##
## Every fixture is written into user:// by the test itself, so the
## expected result is visible beside the input rather than hidden in a
## committed binary.

const GRASS: Color = Color8(0, 255, 0)
const WATER: Color = Color8(0, 0, 255)
const OAK: Color = Color8(0, 128, 0)
const EMPTY: Color = Color8(0, 0, 0)

var _dir: String
var _registry: ContentRegistry


func before_each() -> void:
	_dir = "user://zone_fixture_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(_dir)
	_registry = ContentRegistry.new()
	_registry.register({"id": "grass", "category": "terrain",
		"display_name": "Grass", "sprite": "res://none.png", "walkable": true})
	_registry.register({"id": "water", "category": "terrain",
		"display_name": "Water", "sprite": "res://none.png", "walkable": false})
	_registry.register({"id": "oak_tree", "category": "object",
		"display_name": "Oak", "sprite": "res://none.png", "blocks_movement": true})
	_registry.register({"id": "rabbit", "category": "creature",
		"display_name": "Rabbit", "sprite": "res://none.png"})


func after_each() -> void:
	# user:// persists between runs; fixtures would otherwise accumulate.
	var d: DirAccess = DirAccess.open(_dir)
	if d != null:
		for f: String in d.get_files():
			d.remove(f)
	DirAccess.remove_absolute(_dir)


## Writes a map whose every pixel is `fill`, then overrides the pixels in
## `overrides` (Vector2i -> Color).
func _write_map(file_name: String, size: Vector2i, fill: Color,
		overrides: Dictionary = {}) -> void:
	var img: Image = Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
	img.fill(fill)
	for p: Vector2i in overrides:
		img.set_pixelv(p, overrides[p])
	img.save_png(_dir.path_join(file_name))


func _write_doc(doc: Dictionary) -> void:
	var f: FileAccess = FileAccess.open(_dir.path_join("zone.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(doc))
	f.close()


## The smallest document the schema accepts, with a terrain map only.
func _doc(size: Vector2i = Vector2i(4, 4)) -> Dictionary:
	return {
		"id": "fixture",
		"category": "zone",
		"display_name": "Fixture",
		"size": [size.x, size.y],
		"maps": {"terrain": "terrain.png"},
		"legend": {"terrain": {"00ff00": "grass", "0000ff": "water"}},
		"player_spawn": [1.5, 1.5],
	}


func test_terrain_pixels_become_tiles() -> void:
	_write_doc(_doc())
	_write_map("terrain.png", Vector2i(4, 4), GRASS, {Vector2i(2, 1): WATER})

	var r: ZoneLoadResult = ZoneLoader.load_zone(_dir, _registry)

	assert_eq(r.errors, PackedStringArray(), "a clean fixture reports nothing")
	assert_not_null(r.zone)
	assert_eq(r.zone.get_terrain(Vector2i(0, 0)), _registry.numeric_of("grass"))
	assert_eq(r.zone.get_terrain(Vector2i(2, 1)), _registry.numeric_of("water"),
		"the pixel at (2,1) is the tile at (2,1) -- x across, y down")
	assert_eq(r.zone.get_terrain(Vector2i(1, 2)), _registry.numeric_of("grass"),
		"and (1,2) is a different tile, so the axes are not transposed")


func test_metadata_comes_from_the_document() -> void:
	var doc: Dictionary = _doc()
	doc["biome"] = "alpine"
	doc["generation_seed"] = 7
	_write_doc(doc)
	_write_map("terrain.png", Vector2i(4, 4), GRASS)

	var r: ZoneLoadResult = ZoneLoader.load_zone(_dir, _registry)

	assert_eq(r.zone.id, "fixture")
	assert_eq(r.zone.display_name, "Fixture")
	assert_eq(r.zone.size_tiles, Vector2i(4, 4))
	assert_eq(r.zone.biome, "alpine")
	assert_eq(r.zone.generation_seed, 7)


func test_player_spawn_is_returned_in_tile_units() -> void:
	_write_doc(_doc())
	_write_map("terrain.png", Vector2i(4, 4), GRASS)

	var r: ZoneLoadResult = ZoneLoader.load_zone(_dir, _registry)

	assert_eq(r.player_spawn, Vector2(1.5, 1.5),
		"tile units, not pixels: the centre of tile (1,1)")


func test_a_missing_directory_reports_an_error_and_no_zone() -> void:
	var r: ZoneLoadResult = ZoneLoader.load_zone("user://no_such_zone", _registry)

	assert_null(r.zone, "there is no half-usable zone to hand back")
	assert_gt(r.errors.size(), 0, "and it must say so rather than fail silently")


func test_malformed_json_reports_an_error_and_no_zone() -> void:
	var f: FileAccess = FileAccess.open(_dir.path_join("zone.json"), FileAccess.WRITE)
	f.store_string("{ not json")
	f.close()

	var r: ZoneLoadResult = ZoneLoader.load_zone(_dir, _registry)

	assert_null(r.zone)
	assert_gt(r.errors.size(), 0)


func test_a_schema_violation_reports_an_error_and_no_zone() -> void:
	var doc: Dictionary = _doc()
	doc.erase("player_spawn")
	_write_doc(doc)
	_write_map("terrain.png", Vector2i(4, 4), GRASS)

	var r: ZoneLoadResult = ZoneLoader.load_zone(_dir, _registry)

	assert_null(r.zone, "an unschematic document is not loaded at all")
	assert_gt(r.errors.size(), 0)


func test_an_unknown_colour_is_an_error_and_leaves_the_tile_unpainted() -> void:
	_write_doc(_doc())
	_write_map("terrain.png", Vector2i(4, 4), GRASS, {Vector2i(3, 3): Color8(1, 2, 3)})

	var r: ZoneLoadResult = ZoneLoader.load_zone(_dir, _registry)

	assert_not_null(r.zone, "one bad pixel must not cost the whole zone")
	assert_eq(r.zone.get_terrain(Vector2i(3, 3)), ContentRegistry.ID_UNKNOWN)
	assert_eq(r.zone.get_terrain(Vector2i(0, 0)), _registry.numeric_of("grass"),
		"and the rest of the map still loaded")
	assert_gt(r.errors.size(), 0)
	assert_string_contains(r.errors[0], "010203",
		"the error names the colour, since that is what the author must find")


func test_unknown_colour_errors_are_capped() -> void:
	_write_doc(_doc(Vector2i(16, 16)))
	# Every pixel a different unknown colour: 256 distinct problems.
	var overrides: Dictionary = {}
	for y: int in range(16):
		for x: int in range(16):
			overrides[Vector2i(x, y)] = Color8(200, x * 4, y * 4)
	_write_map("terrain.png", Vector2i(16, 16), GRASS, overrides)

	var r: ZoneLoadResult = ZoneLoader.load_zone(_dir, _registry)

	assert_lt(r.errors.size(), ZoneLoader.MAX_REPORTED + 3,
		"a wrong colour mode must not produce one error per pixel")
	assert_string_contains(r.errors[r.errors.size() - 1], "more colour(s)",
		"the tail says how many were suppressed")


func test_a_map_of_the_wrong_size_is_skipped_and_reported() -> void:
	_write_doc(_doc(Vector2i(4, 4)))
	_write_map("terrain.png", Vector2i(8, 8), GRASS)

	var r: ZoneLoadResult = ZoneLoader.load_zone(_dir, _registry)

	assert_not_null(r.zone, "the zone still exists, just unpainted")
	assert_eq(r.zone.get_terrain(Vector2i(0, 0)), ContentRegistry.ID_UNKNOWN)
	assert_gt(r.errors.size(), 0)
	assert_string_contains(r.errors[0], "8x8")


func test_a_partly_transparent_pixel_is_reported() -> void:
	_write_doc(_doc())
	_write_map("terrain.png", Vector2i(4, 4), GRASS,
		{Vector2i(1, 1): Color8(0, 255, 0, 128)})

	var r: ZoneLoadResult = ZoneLoader.load_zone(_dir, _registry)

	assert_gt(r.errors.size(), 0, "a map is an index, not art; alpha is meaningless")
	assert_eq(r.zone.get_terrain(Vector2i(1, 1)), ContentRegistry.ID_UNKNOWN)


func test_a_missing_map_file_is_reported_without_losing_the_zone() -> void:
	_write_doc(_doc())
	# No terrain.png written at all.

	var r: ZoneLoadResult = ZoneLoader.load_zone(_dir, _registry)

	assert_not_null(r.zone, "the document parsed, so there is a zone to hand back")
	assert_gt(r.errors.size(), 0)


func test_a_legend_id_this_build_lacks_becomes_a_placeholder() -> void:
	var doc: Dictionary = _doc()
	doc["legend"]["terrain"]["ff00ff"] = "moon_rock"
	_write_doc(doc)
	_write_map("terrain.png", Vector2i(4, 4), GRASS,
		{Vector2i(2, 2): Color8(255, 0, 255)})

	var r: ZoneLoadResult = ZoneLoader.load_zone(_dir, _registry)

	var id: int = r.zone.get_terrain(Vector2i(2, 2))
	assert_ne(id, ContentRegistry.ID_UNKNOWN, "the tile is painted, not dropped")
	assert_true(_registry.is_placeholder(id), "with a placeholder that keeps the string")
	assert_eq(_registry.string_of(id), "moon_rock",
		"so a resave round-trips the original id -- Stage 1 design 6.4")
	# Walkability arrives in Task 6; that a placeholder is non-blocking is
	# asserted there, against a zone whose flags have actually been derived.
	assert_gt(r.errors.size(), 0, "and the build says what it could not find")


func test_a_malformed_legend_key_is_reported() -> void:
	var doc: Dictionary = _doc()
	doc["legend"]["terrain"]["#00ff00"] = "grass"
	_write_doc(doc)
	_write_map("terrain.png", Vector2i(4, 4), GRASS)

	var r: ZoneLoadResult = ZoneLoader.load_zone(_dir, _registry)

	assert_gt(r.errors.size(), 0, "six hex digits, no leading hash")
```

- [x] **Step 2: Run the test and watch it fail**

Run: `./tools/run_tests.sh`

Expected: FAIL — the suite will not even load, reporting an unknown identifier
`ZoneLoader`. `run_tests.sh` exits 3 on that ("a test script failed to load"),
which is the intended behaviour, not a problem with the runner.

- [x] **Step 3: Write `ZoneLoadResult`**

Create `src/core/zone_load_result.gd`:

```gdscript
class_name ZoneLoadResult
extends RefCounted
## What ZoneLoader returns.
##
## A separate file rather than an inner class, matching DecodeResult and
## TilesetBuildResult.
##
## `zone` is null only when the document itself could not be read or did
## not satisfy the schema. Every other problem is an entry in `errors`
## beside a zone that is still usable: one unreadable map must not blank
## the world, exactly as one missing PNG must not (TilesetBuildResult).

var zone: Zone = null

## Tile units, matching EntityStore: the centre of tile (1,1) is (1.5, 1.5).
var player_spawn: Vector2 = Vector2.ZERO

var errors: PackedStringArray = []
```

- [x] **Step 4: Write `ZoneLoader` with the terrain layer only**

Create `src/core/zone_loader.gd`:

```gdscript
class_name ZoneLoader
extends RefCounted
## Turns an authored zone directory into a Zone.
##
## The format is one PNG per tile column, one pixel per tile, with a
## per-layer colour -> string-id legend in zone.json. This is the only
## file that knows that; tools/check_zone.gd calls it rather than reading
## the PNGs itself, so a rule cannot drift between the gate and the game.
##
## Note what is NOT read here. There is no floor map: floor is Stage 2's
## player-placed layer, and Walkability deliberately does not consult it,
## so a path authored as floor over water would come out unwalkable with
## nothing to flag it. Omitting the map makes that inexpressible. And
## `flags` is derived by Walkability, never authored -- setting flags from
## terrain alone is what once left oaks standing on walkable tiles.

const SCHEMA_PATH: String = "res://data/schema/zone.json"

## Distinct problems reported per map before truncating, matching
## MAX_REPORTED in tools/check_palette.gd. A PNG saved in the wrong colour
## mode yields one error per pixel, and a 16,384-line CI log is the same
## as no CI log.
const MAX_REPORTED: int = 8


static func load_zone(dir: String, registry: ContentRegistry) -> ZoneLoadResult:
	var result: ZoneLoadResult = ZoneLoadResult.new()

	var doc: Dictionary = _read_json(dir.path_join("zone.json"), result.errors)
	if doc.is_empty():
		return result
	var schema: Dictionary = _read_json(SCHEMA_PATH, result.errors)
	if schema.is_empty():
		return result
	var problems: PackedStringArray = SchemaValidator.validate(doc, schema)
	if not problems.is_empty():
		result.errors.append_array(problems)
		return result

	var size: Vector2i = Vector2i(int(doc["size"][0]), int(doc["size"][1]))
	var zone: Zone = Zone.new(str(doc["id"]), size)
	zone.display_name = str(doc["display_name"])
	zone.biome = str(doc.get("biome", "temperate"))
	zone.generation_seed = int(doc.get("generation_seed", 0))

	var spawn: Array = doc["player_spawn"]
	result.player_spawn = Vector2(float(spawn[0]), float(spawn[1]))

	var maps: Dictionary = doc["maps"]
	if maps.has("terrain"):
		var lookup: Dictionary = _resolve_legend("terrain", doc, registry, result.errors)
		var img: Image = _decode_map(
			dir.path_join(str(maps["terrain"])), size, result.errors)
		if img != null:
			_paint(zone, img, size, lookup, zone.set_terrain, "terrain", result.errors)

	result.zone = zone
	return result


## Mirrors ContentRegistry._read_json: the instance JSON API rather than the
## static helper, which pushes an engine-level error on malformed input.
static func _read_json(path: String, errors: PackedStringArray) -> Dictionary:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		errors.append("%s: cannot open" % path)
		return {}
	var text: String = f.get_as_text()
	f.close()
	var parser: JSON = JSON.new()
	var err: int = parser.parse(text)
	if err != OK:
		errors.append("%s: malformed JSON at line %d: %s"
			% [path, parser.get_error_line(), parser.get_error_message()])
		return {}
	if not (parser.data is Dictionary):
		errors.append("%s: top level must be an object" % path)
		return {}
	return parser.data as Dictionary


## Colour key -> numeric content id, for one layer.
##
## An id this build does not have becomes a placeholder plus an error. That
## is the Stage 1 design 6.4 policy, and it matters here: Walkability treats
## a placeholder as non-blocking, so missing content leaves a walkable gap
## rather than an impassable hole in the middle of the world.
static func _resolve_legend(layer: String, doc: Dictionary,
		registry: ContentRegistry, errors: PackedStringArray) -> Dictionary:
	var out: Dictionary = {}
	var legend: Dictionary = doc["legend"].get(layer, {})
	for hex: String in legend:
		if hex.length() != 6 or not hex.is_valid_hex_number(false):
			errors.append("legend %s: '%s' is not a six-digit RRGGBB hex colour"
				% [layer, hex])
			continue
		var key: int = hex.hex_to_int()
		var value: Variant = legend[hex]
		if value == null:
			out[key] = ContentRegistry.ID_UNKNOWN
			continue
		var string_id: String = str(value)
		if registry.has_string(string_id):
			out[key] = registry.numeric_of(string_id)
		else:
			out[key] = registry.register_placeholder(string_id)
			errors.append("legend %s: '%s' is not in this build; using a placeholder"
				% [layer, string_id])
	return out


## Reads the committed bytes, never the engine's imported copy.
##
## Image.load_from_file would also work at build time, but this runs inside
## the shipped game, where there is no file on disk to read -- only the
## bytes in the pack. FileAccess plus load_png_from_buffer works in both.
static func _decode_map(path: String, expect: Vector2i,
		errors: PackedStringArray) -> Image:
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		errors.append("%s: cannot be read" % path)
		return null
	var img: Image = Image.new()
	var err: int = img.load_png_from_buffer(bytes)
	if err != OK:
		errors.append("%s: is not a readable PNG (error %d)" % [path, err])
		return null
	if img.get_size() != expect:
		errors.append("%s: is %dx%d but the zone is %dx%d"
			% [path, img.get_width(), img.get_height(), expect.x, expect.y])
		return null
	img.convert(Image.FORMAT_RGBA8)
	return img


## Walks raw RGBA bytes rather than calling get_pixel().
##
## get_pixel returns a float Color, and a float round-trip through sRGB is
## exactly how a legend key silently stops matching the pixel it was
## written for. Integer bytes compare exactly.
static func _paint(zone: Zone, img: Image, size: Vector2i, lookup: Dictionary,
		setter: Callable, layer: String, errors: PackedStringArray) -> void:
	var data: PackedByteArray = img.get_data()
	var unknown: Dictionary = {}
	var partial_alpha: int = 0

	for y: int in range(size.y):
		for x: int in range(size.x):
			var i: int = (y * size.x + x) * 4
			if data[i + 3] != 255:
				partial_alpha += 1
				continue
			var key: int = (data[i] << 16) | (data[i + 1] << 8) | data[i + 2]
			if not lookup.has(key):
				unknown[key] = unknown.get(key, 0) + 1
				continue
			setter.call(Vector2i(x, y), int(lookup[key]))

	_report_unknown(layer, unknown, errors)
	if partial_alpha > 0:
		errors.append("%s: %d pixel(s) are not fully opaque; a map is an index, not art"
			% [layer, partial_alpha])


static func _report_unknown(layer: String, unknown: Dictionary,
		errors: PackedStringArray) -> void:
	if unknown.is_empty():
		return
	var keys: Array = unknown.keys()
	keys.sort()
	var shown: int = mini(keys.size(), MAX_REPORTED)
	for n: int in range(shown):
		var key: int = keys[n]
		errors.append("%s: #%06x has no legend entry (%d tile(s))"
			% [layer, key, unknown[key]])
	if keys.size() > shown:
		errors.append("%s: ... and %d more colour(s) with no legend entry"
			% [layer, keys.size() - shown])
```

- [x] **Step 5: Run the test and watch it pass**

Run: `./tools/run_tests.sh`

Expected: PASS, thirteen new tests in one new script.

- [x] **Step 6: Confirm the architecture guard is still clean**

Run: `./tools/godot.sh --headless --path . -s tools/guard.gd`

Expected: `Architecture guard: clean`. `Image`, `FileAccess`, `JSON` and
`Callable` are none of them nodes, and none appear in the banned list.

- [x] **Step 7: Commit**

```bash
git add src/core/zone_loader.gd src/core/zone_load_result.gd tests/test_zone_loader.gd
git commit -m "$(cat <<'EOF'
feat: read an authored zone's terrain layer

ZoneLoader is the only file that knows the on-disk format, so the CI gate
can call it instead of re-reading the PNGs and drifting away from what the
game actually does.

Two choices worth keeping: raw RGBA bytes rather than get_pixel(), because
a float round-trip through sRGB is how a legend key silently stops
matching; and FileAccess plus load_png_from_buffer rather than
Image.load_from_file, because this runs inside the shipped game where
there is no file on disk, only bytes in the pack.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

- [x] **Step 8: Tick this task**

```bash
python3 tools/mark_task_done.py 3 --plan docs/superpowers/plans/2026-09-11-rp1-phase4a-zone-authoring.md
git add docs/superpowers/plans/2026-09-11-rp1-phase4a-zone-authoring.md
git commit -m "docs: tick Phase 4a task 3"
```

---

## Task 4: The object and height layers

**Files:**
- Modify: `src/core/zone_loader.gd`
- Test: `tests/test_zone_loader.gd`

**Interfaces:**
- Consumes: `ZoneLoader.load_zone` from Task 3
- Produces: no signature change. `maps` may now name `object` and `height`;
  both are optional, and `height` has no legend — its red channel *is* the
  value.

- [ ] **Step 1: Write the failing tests**

Append to `tests/test_zone_loader.gd`:

```gdscript
## The full three-layer document, as data/zone/home/zone.json is shaped.
func _full_doc(size: Vector2i = Vector2i(4, 4)) -> Dictionary:
	var doc: Dictionary = _doc(size)
	doc["maps"] = {
		"terrain": "terrain.png", "object": "object.png", "height": "height.png"
	}
	doc["legend"]["object"] = {"000000": null, "008000": "oak_tree"}
	return doc


func test_object_pixels_become_objects() -> void:
	_write_doc(_full_doc())
	_write_map("terrain.png", Vector2i(4, 4), GRASS)
	_write_map("object.png", Vector2i(4, 4), EMPTY, {Vector2i(1, 3): OAK})
	_write_map("height.png", Vector2i(4, 4), EMPTY)

	var r: ZoneLoadResult = ZoneLoader.load_zone(_dir, _registry)

	assert_eq(r.errors, PackedStringArray())
	assert_eq(r.zone.get_object(Vector2i(1, 3)), _registry.numeric_of("oak_tree"))


func test_a_null_legend_entry_leaves_the_tile_empty() -> void:
	_write_doc(_full_doc())
	_write_map("terrain.png", Vector2i(4, 4), GRASS)
	_write_map("object.png", Vector2i(4, 4), EMPTY)
	_write_map("height.png", Vector2i(4, 4), EMPTY)

	var r: ZoneLoadResult = ZoneLoader.load_zone(_dir, _registry)

	assert_eq(r.errors, PackedStringArray(),
		"black is declared as null, so it is empty rather than unknown")
	assert_eq(r.zone.get_object(Vector2i(0, 0)), ContentRegistry.ID_UNKNOWN)


func test_the_same_colour_may_mean_different_things_per_layer() -> void:
	# 008000 is oak_tree in the object legend. Give it a terrain meaning too
	# and check the layers do not consult each other's legend.
	var doc: Dictionary = _full_doc()
	doc["legend"]["terrain"]["008000"] = "water"
	_write_doc(doc)
	_write_map("terrain.png", Vector2i(4, 4), GRASS, {Vector2i(0, 1): OAK})
	_write_map("object.png", Vector2i(4, 4), EMPTY, {Vector2i(2, 2): OAK})
	_write_map("height.png", Vector2i(4, 4), EMPTY)

	var r: ZoneLoadResult = ZoneLoader.load_zone(_dir, _registry)

	assert_eq(r.errors, PackedStringArray())
	assert_eq(r.zone.get_terrain(Vector2i(0, 1)), _registry.numeric_of("water"))
	assert_eq(r.zone.get_object(Vector2i(2, 2)), _registry.numeric_of("oak_tree"))


func test_height_comes_from_the_red_channel_with_no_legend() -> void:
	_write_doc(_full_doc())
	_write_map("terrain.png", Vector2i(4, 4), GRASS)
	_write_map("object.png", Vector2i(4, 4), EMPTY)
	_write_map("height.png", Vector2i(4, 4), EMPTY, {
		Vector2i(1, 1): Color8(3, 0, 0),
		Vector2i(2, 1): Color8(255, 99, 99),
	})

	var r: ZoneLoadResult = ZoneLoader.load_zone(_dir, _registry)

	assert_eq(r.errors, PackedStringArray(), "height needs no legend entries")
	assert_eq(r.zone.get_height(Vector2i(1, 1)), 3)
	assert_eq(r.zone.get_height(Vector2i(2, 1)), 255,
		"only red is read; green and blue are ignored")
	assert_eq(r.zone.get_height(Vector2i(0, 0)), 0)


func test_a_missing_height_map_is_not_an_error() -> void:
	var doc: Dictionary = _full_doc()
	doc["maps"].erase("height")
	_write_doc(doc)
	_write_map("terrain.png", Vector2i(4, 4), GRASS)
	_write_map("object.png", Vector2i(4, 4), EMPTY)

	var r: ZoneLoadResult = ZoneLoader.load_zone(_dir, _registry)

	assert_eq(r.errors, PackedStringArray(), "height is optional; Stage 1 renders flat")
	assert_eq(r.zone.get_height(Vector2i(2, 2)), 0)
```

- [ ] **Step 2: Run the tests and watch them fail**

Run: `./tools/run_tests.sh`

Expected: FAIL. `get_object` and `get_height` return 0 for every tile, because
`load_zone` still reads only the terrain map.

- [ ] **Step 3: Generalise the layer loop**

In `src/core/zone_loader.gd`, replace the single `if maps.has("terrain")` block
in `load_zone` with:

```gdscript
	var maps: Dictionary = doc["maps"]
	var setters: Dictionary = {
		"terrain": zone.set_terrain,
		"object": zone.set_object,
		"height": zone.set_height,
	}
	# Fixed order so errors read the same way every run.
	for layer: String in ["terrain", "object", "height"]:
		if not maps.has(layer):
			continue
		var img: Image = _decode_map(
			dir.path_join(str(maps[layer])), size, result.errors)
		if img == null:
			continue
		if layer == "height":
			_paint_height(zone, img, size)
			continue
		var lookup: Dictionary = _resolve_legend(layer, doc, registry, result.errors)
		_paint(zone, img, size, lookup, setters[layer], layer, result.errors)
```

and add, beside `_paint`:

```gdscript
## Height has no legend: the red byte IS the value, so there is nothing to
## look up and nothing that can be "unknown". Green and blue are ignored,
## which keeps the map viewable as a greyscale image in any editor.
static func _paint_height(zone: Zone, img: Image, size: Vector2i) -> void:
	var data: PackedByteArray = img.get_data()
	for y: int in range(size.y):
		for x: int in range(size.x):
			zone.set_height(Vector2i(x, y), data[(y * size.x + x) * 4])
```

- [ ] **Step 4: Run the tests and watch them pass**

Run: `./tools/run_tests.sh`

Expected: PASS, five more tests, and every Task 3 test still green.

- [ ] **Step 5: Commit**

```bash
git add src/core/zone_loader.gd tests/test_zone_loader.gd
git commit -m "$(cat <<'EOF'
feat: read the object and height layers

Legends are per-layer, so a colour may mean water in terrain.png and an
oak in object.png -- worth a test, because sharing one legend across
layers is the obvious simplification and it would quietly halve how many
colours an author can use.

Height has no legend at all: the red byte is the value. Stage 1 renders
flat, but the column is carried from day one because adding one to a save
format later is painful.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

- [ ] **Step 6: Tick this task**

```bash
python3 tools/mark_task_done.py 4 --plan docs/superpowers/plans/2026-09-11-rp1-phase4a-zone-authoring.md
git add docs/superpowers/plans/2026-09-11-rp1-phase4a-zone-authoring.md
git commit -m "docs: tick Phase 4a task 4"
```

---

## Task 5: Entity spawns

**Files:**
- Modify: `src/core/zone_loader.gd`
- Test: `tests/test_zone_loader.gd`

**Interfaces:**
- Consumes: `EntityStore.spawn(type_id: int, pos: Vector2, entity_flags: int = FLAG_ACTIVE | FLAG_PERSISTED) -> int`
- Produces: entities present in `result.zone.entities` after a load. Phase 4b's
  `AnimalSystem` reads them from there and needs no authoring surface of its own.

- [ ] **Step 1: Write the failing tests**

Append to `tests/test_zone_loader.gd`:

```gdscript
func test_entities_are_spawned_at_tile_unit_positions() -> void:
	var doc: Dictionary = _full_doc()
	doc["entities"] = [
		{"type": "rabbit", "at": [2.5, 3.5]},
		{"type": "rabbit", "at": [0.5, 0.5]},
	]
	_write_doc(doc)
	_write_map("terrain.png", Vector2i(4, 4), GRASS)
	_write_map("object.png", Vector2i(4, 4), EMPTY)
	_write_map("height.png", Vector2i(4, 4), EMPTY)

	var r: ZoneLoadResult = ZoneLoader.load_zone(_dir, _registry)

	assert_eq(r.errors, PackedStringArray())
	assert_eq(r.zone.entities.count(), 2)
	var ids: PackedInt32Array = r.zone.entities.ids()
	assert_eq(r.zone.entities.get_position(ids[0]), Vector2(2.5, 3.5),
		"tile units, not pixels -- one unit is one tile")
	assert_eq(r.zone.entities.get_type_id(ids[0]), _registry.numeric_of("rabbit"))


func test_an_absent_entities_list_is_not_an_error() -> void:
	var doc: Dictionary = _full_doc()
	doc.erase("entities")
	_write_doc(doc)
	_write_map("terrain.png", Vector2i(4, 4), GRASS)
	_write_map("object.png", Vector2i(4, 4), EMPTY)
	_write_map("height.png", Vector2i(4, 4), EMPTY)

	var r: ZoneLoadResult = ZoneLoader.load_zone(_dir, _registry)

	assert_eq(r.errors, PackedStringArray())
	assert_eq(r.zone.entities.count(), 0)


func test_an_entity_type_this_build_lacks_becomes_a_placeholder() -> void:
	var doc: Dictionary = _full_doc()
	doc["entities"] = [{"type": "wyvern", "at": [1.5, 1.5]}]
	_write_doc(doc)
	_write_map("terrain.png", Vector2i(4, 4), GRASS)
	_write_map("object.png", Vector2i(4, 4), EMPTY)
	_write_map("height.png", Vector2i(4, 4), EMPTY)

	var r: ZoneLoadResult = ZoneLoader.load_zone(_dir, _registry)

	assert_eq(r.zone.entities.count(), 1, "the row survives so a resave keeps it")
	assert_true(_registry.is_placeholder(
		r.zone.entities.get_type_id(r.zone.entities.ids()[0])))
	assert_gt(r.errors.size(), 0)


func test_a_malformed_entity_entry_is_reported_and_skipped() -> void:
	var doc: Dictionary = _full_doc()
	doc["entities"] = [
		{"type": "rabbit"},
		{"at": [1.5, 1.5]},
		{"type": "rabbit", "at": [2.5, 2.5]},
	]
	_write_doc(doc)
	_write_map("terrain.png", Vector2i(4, 4), GRASS)
	_write_map("object.png", Vector2i(4, 4), EMPTY)
	_write_map("height.png", Vector2i(4, 4), EMPTY)

	var r: ZoneLoadResult = ZoneLoader.load_zone(_dir, _registry)

	assert_eq(r.zone.entities.count(), 1, "only the well-formed entry spawns")
	assert_eq(r.errors.size(), 2, "and each bad entry is named")
```

- [ ] **Step 2: Run the tests and watch them fail**

Run: `./tools/run_tests.sh`

Expected: FAIL — `entities.count()` is 0; nothing spawns anything yet.

- [ ] **Step 3: Spawn the list**

In `src/core/zone_loader.gd`, add a call just before `result.zone = zone`:

```gdscript
	_spawn_entities(zone, doc.get("entities", []), registry, result.errors)
```

and the function:

```gdscript
## Entity positions are in tile units, matching EntityStore: (40.5, 52.5)
## stands at the centre of tile (40, 52). Tile size is a presentation
## constant, so measuring these in pixels would bake it into every save.
static func _spawn_entities(zone: Zone, entries: Array,
		registry: ContentRegistry, errors: PackedStringArray) -> void:
	for n: int in range(entries.size()):
		var entry: Variant = entries[n]
		if not (entry is Dictionary) or not entry.has("type") or not entry.has("at"):
			errors.append("entities[%d]: needs both 'type' and 'at'" % n)
			continue
		var at: Variant = entry["at"]
		if not (at is Array) or at.size() != 2:
			errors.append("entities[%d]: 'at' must be [x, y] in tile units" % n)
			continue
		var string_id: String = str(entry["type"])
		var type_id: int = registry.numeric_of(string_id)
		if type_id == ContentRegistry.ID_UNKNOWN:
			type_id = registry.register_placeholder(string_id)
			errors.append("entities[%d]: '%s' is not in this build; using a placeholder"
				% [n, string_id])
		zone.entities.spawn(type_id, Vector2(float(at[0]), float(at[1])))
```

- [ ] **Step 4: Run the tests and watch them pass**

Run: `./tools/run_tests.sh`

Expected: PASS, four more tests.

- [ ] **Step 5: Commit**

```bash
git add src/core/zone_loader.gd tests/test_zone_loader.gd
git commit -m "$(cat <<'EOF'
feat: spawn an authored zone's entities

Positions are in tile units, matching EntityStore, because tile size is a
presentation constant and measuring these in pixels would bake it into
every save file.

A creature the build lacks still spawns, as a placeholder holding its
original string. Dropping the row would silently delete an animal from
someone's world the first time a content pack went missing.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

- [ ] **Step 6: Tick this task**

```bash
python3 tools/mark_task_done.py 5 --plan docs/superpowers/plans/2026-09-11-rp1-phase4a-zone-authoring.md
git add docs/superpowers/plans/2026-09-11-rp1-phase4a-zone-authoring.md
git commit -m "docs: tick Phase 4a task 5"
```

---

## Task 6: Derived flags and a clean dirty slate

**Files:**
- Modify: `src/core/zone_loader.gd`
- Test: `tests/test_zone_loader.gd`

**Interfaces:**
- Consumes: `Walkability.recompute_zone(zone: Zone, registry: ContentRegistry) -> int`
- Produces: a loaded zone whose `FLAG_WALKABLE` bits are correct and whose
  `dirty_chunk_coords()` is empty.

**The ordering is the whole task, and it is not obvious.** `recompute_zone`
dirties every chunk as it writes flags. `main.gd:91` records why that matters:
the first paint is a full `render_zone()`, not a dirty-driven repaint, so those
flags are not pending work for anyone. Clearing before the recompute would
leave every chunk falsely dirty on the first frame.

- [ ] **Step 1: Write the failing tests**

Append to `tests/test_zone_loader.gd`:

```gdscript
func _four_by_four_with_an_oak() -> ZoneLoadResult:
	_write_doc(_full_doc())
	_write_map("terrain.png", Vector2i(4, 4), GRASS, {Vector2i(3, 0): WATER})
	_write_map("object.png", Vector2i(4, 4), EMPTY, {Vector2i(1, 1): OAK})
	_write_map("height.png", Vector2i(4, 4), EMPTY)
	return ZoneLoader.load_zone(_dir, _registry)


func test_walkability_is_derived_not_authored() -> void:
	var r: ZoneLoadResult = _four_by_four_with_an_oak()

	assert_true(r.zone.is_walkable(Vector2i(0, 0)), "plain grass")
	assert_false(r.zone.is_walkable(Vector2i(1, 1)), "grass under an oak")
	assert_false(r.zone.is_walkable(Vector2i(3, 0)), "water")


func test_an_unpainted_tile_is_not_walkable() -> void:
	# A 4x4 zone occupies one 32x32 chunk, so tile (10,10) is inside the
	# chunk but outside the authored area: never painted, and therefore
	# void rather than floor.
	var r: ZoneLoadResult = _four_by_four_with_an_oak()

	assert_false(r.zone.is_walkable(Vector2i(10, 10)))


func test_the_zone_comes_back_with_no_dirty_chunks() -> void:
	var r: ZoneLoadResult = _four_by_four_with_an_oak()

	assert_eq(r.zone.dirty_chunk_coords(), [] as Array[Vector2i],
		"the first paint is a full render_zone(), so nothing is pending")
```

- [ ] **Step 2: Run the tests and watch them fail**

Run: `./tools/run_tests.sh`

Expected: FAIL on all three. No flags are ever set, so `is_walkable` is false
everywhere (including the grass), and every painted chunk is still dirty.

- [ ] **Step 3: Recompute, then clear**

In `src/core/zone_loader.gd`, immediately before `result.zone = zone`:

```gdscript
	# Flags are derived from content, never authored: there is no flags map
	# and there must never be one. Setting flags from terrain alone is what
	# once left oaks standing on walkable tiles.
	Walkability.recompute_zone(zone, registry)

	# AFTER the recompute, not before. recompute_zone dirties every chunk it
	# writes to, and the caller's first paint is a full render_zone() rather
	# than a dirty-driven repaint, so none of that is pending work. Clearing
	# first would leave every chunk falsely dirty on frame one.
	zone.clear_dirty()

	result.zone = zone
```

- [ ] **Step 4: Run the tests and watch them pass**

Run: `./tools/run_tests.sh`

Expected: PASS, three more tests.

- [ ] **Step 5: Commit**

```bash
git add src/core/zone_loader.gd tests/test_zone_loader.gd
git commit -m "$(cat <<'EOF'
feat: derive walkability and hand back a clean zone

There is no flags map in the format and there must never be one: flags
come from content through Walkability. The alternative is how oaks once
ended up standing on walkable tiles.

The order matters and is easy to get backwards. recompute_zone dirties
every chunk as it writes, and the caller's first paint is a full
render_zone(), so the flags must be cleared after the recompute rather
than before -- otherwise all sixteen chunks are falsely dirty on frame
one and get repainted for nothing.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

- [ ] **Step 6: Tick this task**

```bash
python3 tools/mark_task_done.py 6 --plan docs/superpowers/plans/2026-09-11-rp1-phase4a-zone-authoring.md
git add docs/superpowers/plans/2026-09-11-rp1-phase4a-zone-authoring.md
git commit -m "docs: tick Phase 4a task 6"
```

---

## Task 7: The shipped zone loads clean, and within budget

**Files:**
- Create: `tests/test_zone_home.gd`, `tests/test_zone_load_budget.gd`

**Interfaces:**
- Consumes: `ZoneLoader.load_zone`, `ContentRegistry.load_from_dir(root: String) -> PackedStringArray`
- Produces: nothing. These are tests only and add no production API; Task 12's
  CI gate calls `ZoneLoader.load_zone` itself and re-derives the same
  assertions there.

Until now every test has run against a fixture. These two run against the real
`data/zone/home/` and against the real size budget, so an authoring mistake
fails locally under `run_tests.sh` rather than only in CI.

- [ ] **Step 1: Write the failing tests**

Create `tests/test_zone_home.gd`:

```gdscript
extends GutTest
## The zone that actually ships.
##
## Every other loader test uses a generated fixture. This one loads
## data/zone/home/ exactly as the game does, so editing a PNG badly fails
## here rather than at boot.

var _registry: ContentRegistry
var _result: ZoneLoadResult


func before_all() -> void:
	_registry = ContentRegistry.new()
	var errs: PackedStringArray = _registry.load_from_dir("res://data")
	assert_eq(errs, PackedStringArray(), "content must load before a zone can")
	_result = ZoneLoader.load_zone("res://data/zone/home", _registry)


func test_the_home_zone_loads_without_errors() -> void:
	assert_eq(_result.errors, PackedStringArray())
	assert_not_null(_result.zone)


func test_every_terrain_tile_is_painted() -> void:
	# An unpainted terrain tile is ID_UNKNOWN, which Walkability treats as
	# void rather than floor -- a hole in the world. The loader survives
	# one; the shipped zone must not contain one.
	var zone: Zone = _result.zone
	var holes: int = 0
	var first: Vector2i = Vector2i(-1, -1)
	for y: int in range(zone.size_tiles.y):
		for x: int in range(zone.size_tiles.x):
			if zone.get_terrain(Vector2i(x, y)) == ContentRegistry.ID_UNKNOWN:
				holes += 1
				if first.x < 0:
					first = Vector2i(x, y)
	assert_eq(holes, 0, "%d unpainted terrain tile(s), first at %s" % [holes, first])


func test_the_player_spawn_is_in_bounds_and_walkable() -> void:
	var zone: Zone = _result.zone
	var tile: Vector2i = Vector2i(
		floori(_result.player_spawn.x), floori(_result.player_spawn.y))
	assert_true(zone.in_bounds(tile), "spawn %s is outside the zone" % tile)
	assert_true(zone.is_walkable(tile),
		"spawn %s is blocked; the player would start inside something" % tile)
```

Create `tests/test_zone_load_budget.gd`:

```gdscript
extends GutTest
## The Stage 1 acceptance criterion "zone loads in under 1 second", made
## mechanical rather than assumed.
##
## Runs against a generated 128x128 zone rather than the shipped one, so
## the budget still means something while data/zone/home/ is smaller than
## its final size.

const SIZE: Vector2i = Vector2i(128, 128)
const BUDGET_MS: int = 1000

var _dir: String
var _registry: ContentRegistry


func before_all() -> void:
	_dir = "user://zone_budget_fixture"
	DirAccess.make_dir_recursive_absolute(_dir)
	_registry = ContentRegistry.new()
	_registry.register({"id": "grass", "category": "terrain",
		"display_name": "Grass", "sprite": "res://none.png", "walkable": true})
	_registry.register({"id": "oak_tree", "category": "object",
		"display_name": "Oak", "sprite": "res://none.png", "blocks_movement": true})

	var doc: Dictionary = {
		"id": "budget", "category": "zone", "display_name": "Budget",
		"size": [SIZE.x, SIZE.y],
		"maps": {"terrain": "terrain.png", "object": "object.png",
			"height": "height.png"},
		"legend": {
			"terrain": {"00ff00": "grass"},
			"object": {"000000": null, "008000": "oak_tree"},
		},
		"player_spawn": [64.5, 64.5],
	}
	var f: FileAccess = FileAccess.open(_dir.path_join("zone.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(doc))
	f.close()

	_fill("terrain.png", Color8(0, 255, 0))
	# A tree every eleventh tile: enough object work to be representative.
	var objects: Image = Image.create_empty(SIZE.x, SIZE.y, false, Image.FORMAT_RGBA8)
	objects.fill(Color8(0, 0, 0))
	for y: int in range(0, SIZE.y, 11):
		for x: int in range(0, SIZE.x, 11):
			objects.set_pixel(x, y, Color8(0, 128, 0))
	objects.save_png(_dir.path_join("object.png"))
	_fill("height.png", Color8(0, 0, 0))


func after_all() -> void:
	var d: DirAccess = DirAccess.open(_dir)
	if d != null:
		for f: String in d.get_files():
			d.remove(f)
	DirAccess.remove_absolute(_dir)


func _fill(file_name: String, c: Color) -> void:
	var img: Image = Image.create_empty(SIZE.x, SIZE.y, false, Image.FORMAT_RGBA8)
	img.fill(c)
	img.save_png(_dir.path_join(file_name))


func test_a_full_size_zone_loads_within_the_budget() -> void:
	var start: int = Time.get_ticks_msec()
	var r: ZoneLoadResult = ZoneLoader.load_zone(_dir, _registry)
	var elapsed: int = Time.get_ticks_msec() - start

	assert_eq(r.errors, PackedStringArray())
	assert_eq(r.zone.size_tiles, SIZE)
	assert_lt(elapsed, BUDGET_MS,
		"a 128x128 zone took %d ms; the Stage 1 budget is %d ms" % [elapsed, BUDGET_MS])
```

- [ ] **Step 2: Run the tests and watch them fail for the right reason**

Run: `./tools/run_tests.sh`

Expected: FAIL. Both scripts are new, so `run_tests.sh` first fails its script
count check — that is the runner working, not a problem. The substantive
failure to look for is in `test_zone_home.gd`: `data/zone/home/zone.json`
declares `oak_tree` in its legend, and `ContentRegistry` loads the real `data/`,
so this should pass immediately **if** Task 1's zone is consistent. If it does
not, the fault is in the committed zone and that is exactly what this test is
for.

If `test_zone_home.gd` passes on the first run, that is the expected outcome
here — it is a regression guard, not a red-to-green step. Do not weaken it to
manufacture a failure.

- [ ] **Step 3: Fix whatever the tests caught**

If `test_every_terrain_tile_is_painted` fails, the 8x8 `terrain.png` has a gap:
re-run `tools/seed_zone.gd`. If the spawn test fails, `player_spawn` in
`data/zone/home/zone.json` sits on the oak at (2,2) or in the pond — move it to
a clear tile such as `[1.5, 1.5]`.

- [ ] **Step 4: Run the tests and watch them pass**

Run: `./tools/run_tests.sh`

Expected: PASS, two new scripts and four new tests.

- [ ] **Step 5: Commit**

```bash
git add tests/test_zone_home.gd tests/test_zone_load_budget.gd
git commit -m "$(cat <<'EOF'
test: guard the shipped zone and the load budget

Every other loader test runs on a generated fixture, which proves the
loader and nothing about the world we actually ship. This loads
data/zone/home/ the way the game does, so a bad pixel fails under
run_tests.sh rather than at boot.

The budget test generates its own 128x128 zone rather than using the
shipped one, so "loads in under a second" keeps meaning something while
data/zone/home/ is still smaller than its final size.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

- [ ] **Step 6: Tick this task**

```bash
python3 tools/mark_task_done.py 7 --plan docs/superpowers/plans/2026-09-11-rp1-phase4a-zone-authoring.md
git add docs/superpowers/plans/2026-09-11-rp1-phase4a-zone-authoring.md
git commit -m "docs: tick Phase 4a task 7"
```

---

## Task 8: Boot the game into the authored zone

**Files:**
- Modify: `src/presentation/main.gd`

**Interfaces:**
- Consumes: `ZoneLoader.load_zone`, `ZoneLoadResult.player_spawn`,
  `Player.spawn(p_zone: Zone, registry: ContentRegistry, collision: CollisionBuilder, near: Vector2i) -> int`
- Produces: nothing new. This deletes code.

`Player.spawn` takes `near` as a `Vector2i` and rings outward from it until it
finds a walkable tile. `player_spawn` is a tile-unit float pair, so `main.gd`
floors it. **The ring search stays exactly where it is** — its own comment says
it exists because "a hardcoded spawn is what Phase 4's authored zone breaks
silently", and this is that phase. `tests/test_player_spawn.gd` covers the
static function and does not change.

- [ ] **Step 1: Delete the debug zone generator**

In `src/presentation/main.gd`, delete:
- the constants `ZONE_SIZE`, `POND_CENTRE`, `POND_RADIUS`, `TREE_SPACING`
- the whole `_build_debug_zone()` function, including its `## TEMPORARY` comment

- [ ] **Step 2: Declare the zone directory as an exported value**

Replace the deleted constants with:

```gdscript
## Exported rather than hardcoded: a res:// path in logic is the thing the
## content rules exist to prevent. Phase 5's New World flow sets this.
@export var zone_dir: String = "res://data/zone/home"
```

- [ ] **Step 3: Load the zone instead of building one**

In `_ready()`, replace `var zone: Zone = _build_debug_zone(registry)` with:

```gdscript
	var load_result: ZoneLoadResult = ZoneLoader.load_zone(zone_dir, registry)
	for e: String in load_result.errors:
		push_error("zone: %s" % e)
	if load_result.zone == null:
		# There is no sensible fallback world. CI gate 7 exists so this
		# state never reaches a build; if it happens anyway, say so loudly
		# rather than rendering an empty screen with no explanation.
		push_error("zone failed to load from %s; nothing to render" % zone_dir)
		return
	var zone: Zone = load_result.zone
```

and update the header comment at the top of the file, which still says the
zone is "scaffolding, not content":

```gdscript
extends Node2D
## Entry point: load the authored zone and draw it.
##
## The world is data. Everything drawn here comes from data/zone/home/ and
## data/*.json; this file contains no content and no layout.
```

- [ ] **Step 4: Spawn the player at the authored point**

Replace `zone.size_tiles / 2` in the `_player.spawn(...)` call:

```gdscript
	var spawn_near: Vector2i = Vector2i(
		floori(load_result.player_spawn.x), floori(load_result.player_spawn.y))
	var pid: int = _player.spawn(zone, registry, _collision, spawn_near)
```

- [ ] **Step 5: Run the whole gate set**

```bash
./tools/run_tests.sh
./tools/godot.sh --headless --path . -s tools/guard.gd
./tools/godot.sh --headless --path . -s tools/smoke.gd
```

Expected: all three green, with **no test file modified**. `smoke.gd` builds its
own zones and never touched `_build_debug_zone`, so it is unaffected.

- [ ] **Step 6: Look at it**

```bash
./tools/godot.sh --headless --path . -s tools/screenshot.gd
```

Expected: a PNG showing an 8x8 patch of grass with one oak and a 2x2 pond, the
player standing on it. Small, and correct. Open the file and check.

- [ ] **Step 7: Commit**

```bash
git add src/presentation/main.gd
git commit -m "$(cat <<'EOF'
feat: boot into the authored zone

_build_debug_zone() is gone. It was the one place the project knowingly
broke its own first content rule, and its own comment scheduled its
deletion for this phase.

The spawn point now comes from zone.json. Player.spawn's ring search
stays exactly as it is: its comment says it exists because "a hardcoded
spawn is what Phase 4's authored zone breaks silently", and an authored
spawn is precisely when a ring search starts earning its keep.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

- [ ] **Step 8: Tick this task**

```bash
python3 tools/mark_task_done.py 8 --plan docs/superpowers/plans/2026-09-11-rp1-phase4a-zone-authoring.md
git add docs/superpowers/plans/2026-09-11-rp1-phase4a-zone-authoring.md
git commit -m "docs: tick Phase 4a task 8"
```

---

## Task 9: The tiles the zone is made of

**Files:**
- Modify: `tools/import_manifest.json`
- Create: `data/terrain/dirt.json` and ten files under `data/object/`
- Modify: `assets/CREDITS.md`

**Interfaces:**
- Consumes: `tools/quantize.gd` (reads `tools/import_manifest.json`)
- Produces: string ids usable in a legend — `dirt`, `pine_tree`, `rock_small`,
  `rock_large`, `bush`, `wall_stone`, `wall_wood`, `roof_red`, `roof_grey`,
  `door`, `window`.

**No new asset pack.** Every slice comes from the already-committed
`assets/_source/slates-outdoor/sheet.png` (1792x736, so 56x23 tiles of 32px).
Slates is CC-BY 4.0, already credited, and `assets/tiles/LICENSE.txt` already
describes exactly this derivation — so this task touches no licence surface.

- [ ] **Step 1: Find the rects by eye**

The sheet's tile contents are not recorded anywhere, so the rects have to be
read off the image. Do not guess them.

```bash
open assets/_source/slates-outdoor/sheet.png
```

Tile `(col, row)` occupies rect `[col * 32, row * 32, 32, 32]`. Note the column
and row of each tile wanted, and convert. The three existing entries in
`tools/import_manifest.json` are worked examples: `grass` is `[32, 64, 32, 32]`,
which is tile `(1, 2)`.

If a candidate is ambiguous at full-sheet zoom, zoom in the image viewer. Do
not add tooling for this: the rects are written down once and then live in the
manifest forever.

Record each choice as `tile (col, row) -> name` in a scratch note before
converting to rects, so Step 2 is transcription rather than arithmetic done
twice.

- [ ] **Step 2: Add the slices to the manifest**

Add to the `slices` array in `tools/import_manifest.json`, substituting the
rects found in Step 1. `source` is relative to `assets/_source/`; `out` is
relative to the project root:

```json
    {"source": "slates-outdoor/sheet.png", "rect": [COL*32, ROW*32, 32, 32],
     "out": "assets/tiles/dirt.png"},

    {"source": "slates-outdoor/sheet.png", "rect": [COL*32, ROW*32, 32, 32],
     "out": "assets/objects/pine_tree.png"},

    {"source": "slates-outdoor/sheet.png", "rect": [COL*32, ROW*32, 32, 32],
     "out": "assets/objects/rock_small.png"},

    {"source": "slates-outdoor/sheet.png", "rect": [COL*32, ROW*32, 32, 32],
     "out": "assets/objects/rock_large.png"},

    {"source": "slates-outdoor/sheet.png", "rect": [COL*32, ROW*32, 32, 32],
     "out": "assets/objects/bush.png"},

    {"source": "slates-outdoor/sheet.png", "rect": [COL*32, ROW*32, 32, 32],
     "out": "assets/objects/wall_stone.png"},

    {"source": "slates-outdoor/sheet.png", "rect": [COL*32, ROW*32, 32, 32],
     "out": "assets/objects/wall_wood.png"},

    {"source": "slates-outdoor/sheet.png", "rect": [COL*32, ROW*32, 32, 32],
     "out": "assets/objects/roof_red.png"},

    {"source": "slates-outdoor/sheet.png", "rect": [COL*32, ROW*32, 32, 32],
     "out": "assets/objects/roof_grey.png"},

    {"source": "slates-outdoor/sheet.png", "rect": [COL*32, ROW*32, 32, 32],
     "out": "assets/objects/door.png"},

    {"source": "slates-outdoor/sheet.png", "rect": [COL*32, ROW*32, 32, 32],
     "out": "assets/objects/window.png"}
```

Write literal numbers, not `COL*32` — JSON has no arithmetic.

- [ ] **Step 3: Run the pipeline and look at the output**

```bash
./tools/godot.sh --headless --path . -s tools/quantize.gd
./tools/check_palette.sh
```

Expected: `quantize: wrote 16 asset(s) from 2 source sheet(s)` and
`Palette: OK (16 file(s))`. Open the new PNGs. A slice one tile off looks like
half a roof and half the sky, and the palette gate cannot tell the difference.

If the mapping report flags a colour that crossed a ramp, pin it in
`tools/palette_overrides.json` and re-run — do not hand-edit a PNG.

- [ ] **Step 4: Write the content definitions**

Create `data/terrain/dirt.json`:

```json
{"id": "dirt", "category": "terrain", "display_name": "Dirt Path",
 "sprite": "res://assets/tiles/dirt.png", "walkable": true,
 "tags": ["natural", "path"]}
```

Create the ten object definitions. Trees, rocks and every house part block
movement; the bush does not. **The door blocks movement too** — there are no
interiors in Stage 1, so a house is solid decoration.

`data/object/pine_tree.json`:

```json
{"id": "pine_tree", "category": "object", "display_name": "Pine Tree",
 "sprite": "res://assets/objects/pine_tree.png", "sprite_rect": [0, 0, 32, 32],
 "y_offset": 0, "blocks_movement": true, "blocks_light": true,
 "harvestable": {"item": "wood", "amount": [2, 4]},
 "tags": ["natural", "flammable", "tree"]}
```

`data/object/rock_small.json`:

```json
{"id": "rock_small", "category": "object", "display_name": "Small Rock",
 "sprite": "res://assets/objects/rock_small.png", "sprite_rect": [0, 0, 32, 32],
 "y_offset": 0, "blocks_movement": true, "blocks_light": false,
 "harvestable": {"item": "stone", "amount": [1, 2]}, "tags": ["natural", "rock"]}
```

`data/object/rock_large.json`: as `rock_small`, with `"id": "rock_large"`,
`"display_name": "Large Rock"`, its own sprite path, `"blocks_light": true`,
and `"amount": [3, 5]`.

`data/object/bush.json`:

```json
{"id": "bush", "category": "object", "display_name": "Bush",
 "sprite": "res://assets/objects/bush.png", "sprite_rect": [0, 0, 32, 32],
 "y_offset": 0, "blocks_movement": false, "blocks_light": false,
 "tags": ["natural", "flammable"]}
```

`data/object/wall_stone.json`:

```json
{"id": "wall_stone", "category": "object", "display_name": "Stone Wall",
 "sprite": "res://assets/objects/wall_stone.png", "sprite_rect": [0, 0, 32, 32],
 "y_offset": 0, "blocks_movement": true, "blocks_light": true,
 "tags": ["built", "wall"]}
```

`data/object/wall_wood.json`, `roof_red.json`, `roof_grey.json`, `door.json`
and `window.json`: the same shape as `wall_stone.json`, each with its own `id`,
`display_name` and `sprite`, all with `"blocks_movement": true` and
`"blocks_light": true`. Tags: `["built", "wall"]` for `wall_wood`,
`["built", "roof"]` for both roofs, `["built", "door"]` for `door`, and
`["built", "window"]` for `window`.

- [ ] **Step 5: Verify the content loads and the gates stay green**

```bash
./tools/run_tests.sh
./tools/godot.sh --headless --path . -s tools/smoke.gd
./tools/check_asset_licences.sh
./tools/check_palette.sh
```

Expected: all green. `smoke.gd` prints the content count, which should have
risen by eleven. No test file changes: these are new *instances* of existing
categories, not new categories, so the existing schemas already cover them and
`test_content_registry.gd` validates them automatically.

- [ ] **Step 6: Refresh the credits**

`assets/CREDITS.md` names both packs already and needs no new row. If it states
a file or slice count anywhere, update the number. Confirm the licence table is
untouched — nothing in this task adds a pack.

- [ ] **Step 7: Commit**

```bash
git add tools/import_manifest.json assets data/terrain data/object
git commit -m "$(cat <<'EOF'
feat: add the tiles the home zone is made of

Eleven slices from the Slates sheet already committed in 3c: dirt, four
natural objects, and six house parts. No new pack, so no new licence
surface -- which is what doing the art pipeline first bought us.

Houses are exterior-only and every part blocks movement, the door
included. Stage 1 has no interiors, so a house is solid decoration.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

- [ ] **Step 8: Tick this task**

```bash
python3 tools/mark_task_done.py 9 --plan docs/superpowers/plans/2026-09-11-rp1-phase4a-zone-authoring.md
git add docs/superpowers/plans/2026-09-11-rp1-phase4a-zone-authoring.md
git commit -m "docs: tick Phase 4a task 9"
```

---

## Task 10: Seed the real 128x128 home zone

**Files:**
- Modify: `tools/seed_zone.gd`, then **delete it**
- Modify: `data/zone/home/zone.json`, `terrain.png`, `object.png`, `height.png`

**Interfaces:**
- Consumes: the string ids from Task 9
- Produces: the world. From this commit on, the PNGs are the source of truth
  and are edited in a pixel editor, not by re-running anything.

- [ ] **Step 1: Grow the seeding tool**

Replace the body of `tools/seed_zone.gd` with the full layout. It stays a
one-shot tool and is deleted at Step 6.

```gdscript
extends SceneTree
## Writes the first draft of data/zone/home/. Build-time only, never shipped,
## and DELETED once its output is committed.
##
##   ./tools/godot.sh --headless --path . -s tools/seed_zone.gd
##
## The PNGs are the source of truth from the moment they land. To change the
## world after that, edit the pixels -- do not edit this and re-run.

const OUT_DIR: String = "res://data/zone/home"
const SIZE: Vector2i = Vector2i(128, 128)
const SEED: int = 20260911

# Terrain legend colours.
const GRASS: Color = Color8(0, 255, 0)
const WATER: Color = Color8(0, 0, 255)
const DIRT: Color = Color8(255, 128, 0)

# Object legend colours.
const EMPTY: Color = Color8(0, 0, 0)
const OAK: Color = Color8(0, 128, 0)
const PINE: Color = Color8(0, 200, 80)
const ROCK_SMALL: Color = Color8(128, 128, 128)
const ROCK_LARGE: Color = Color8(90, 90, 90)
const BUSH: Color = Color8(150, 220, 60)
const WALL_STONE: Color = Color8(200, 200, 180)
const WALL_WOOD: Color = Color8(160, 110, 60)
const ROOF_RED: Color = Color8(220, 60, 60)
const ROOF_GREY: Color = Color8(120, 120, 140)
const DOOR: Color = Color8(90, 60, 30)
const WINDOW: Color = Color8(120, 200, 255)

const POND_CENTRE: Vector2i = Vector2i(40, 40)
const POND_RADIUS: int = 8
const ROAD_Y: int = 64
const ROAD_X: int = 64

var _terrain: Image
var _object: Image


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	_terrain = _filled(GRASS)
	_object = _filled(EMPTY)

	_paint_pond()
	_paint_roads()
	_paint_house(Vector2i(20, 20), WALL_STONE, ROOF_RED)
	_paint_house(Vector2i(86, 28), WALL_WOOD, ROOF_GREY)
	_paint_house(Vector2i(30, 92), WALL_STONE, ROOF_GREY)
	_scatter()

	var height: Image = _filled(EMPTY)

	var failures: int = 0
	failures += _save(_terrain, "terrain.png")
	failures += _save(_object, "object.png")
	failures += _save(height, "height.png")
	if failures > 0:
		printerr("seed_zone: %d file(s) failed to write" % failures)
		quit(1)
		return
	print("seed_zone: wrote a %dx%d zone to %s" % [SIZE.x, SIZE.y, OUT_DIR])
	quit(0)


func _filled(c: Color) -> Image:
	var img: Image = Image.create_empty(SIZE.x, SIZE.y, false, Image.FORMAT_RGBA8)
	img.fill(c)
	return img


func _paint_pond() -> void:
	for y: int in range(SIZE.y):
		for x: int in range(SIZE.x):
			if Vector2(Vector2i(x, y) - POND_CENTRE).length() <= float(POND_RADIUS):
				_terrain.set_pixel(x, y, WATER)


func _paint_roads() -> void:
	for x: int in range(8, SIZE.x - 8):
		_terrain.set_pixel(x, ROAD_Y, DIRT)
		_terrain.set_pixel(x, ROAD_Y + 1, DIRT)
	for y: int in range(16, SIZE.y - 16):
		_terrain.set_pixel(ROAD_X, y, DIRT)
		_terrain.set_pixel(ROAD_X + 1, y, DIRT)


## A seven-wide, five-tall exterior: two roof rows, two wall rows, and a
## front wall with a door and two windows. Solid throughout -- Stage 1 has
## no interiors, so a house is decoration you cannot walk through.
func _paint_house(origin: Vector2i, wall: Color, roof: Color) -> void:
	for dy: int in range(5):
		for dx: int in range(7):
			var p: Vector2i = origin + Vector2i(dx, dy)
			if not _in_bounds(p):
				continue
			# Clear terrain under a building: no house on a pond.
			_terrain.set_pixel(p.x, p.y, GRASS)
			_object.set_pixel(p.x, p.y, roof if dy < 2 else wall)
	var front: int = origin.y + 4
	if _in_bounds(Vector2i(origin.x + 3, front)):
		_object.set_pixel(origin.x + 3, front, DOOR)
	for dx: int in [1, 5]:
		if _in_bounds(Vector2i(origin.x + dx, front)):
			_object.set_pixel(origin.x + dx, front, WINDOW)


## Trees, rocks and bushes, seeded so re-running produces the same world.
## Nothing is placed on water, on a road, or on a building.
func _scatter() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = SEED
	var picks: Array[Color] = [OAK, OAK, OAK, PINE, PINE, BUSH, ROCK_SMALL, ROCK_LARGE]
	var placed: int = 0
	var attempts: int = 0
	while placed < 900 and attempts < 20000:
		attempts += 1
		var p: Vector2i = Vector2i(rng.randi_range(0, SIZE.x - 1), rng.randi_range(0, SIZE.y - 1))
		if not _is_clear(p):
			continue
		_object.set_pixel(p.x, p.y, picks[rng.randi_range(0, picks.size() - 1)])
		placed += 1
	print("seed_zone: scattered %d object(s) in %d attempt(s)" % [placed, attempts])


func _is_clear(p: Vector2i) -> bool:
	if _terrain.get_pixel(p.x, p.y) != GRASS:
		return false
	if _object.get_pixel(p.x, p.y) != EMPTY:
		return false
	# Keep a one-tile margin around the spawn so the player never wakes up
	# boxed in, and leave the roads walkable.
	return Vector2(p - Vector2i(ROAD_X, ROAD_Y)).length() > 3.0


func _in_bounds(p: Vector2i) -> bool:
	return p.x >= 0 and p.y >= 0 and p.x < SIZE.x and p.y < SIZE.y


func _save(img: Image, file_name: String) -> int:
	var err: int = img.save_png(OUT_DIR.path_join(file_name))
	if err != OK:
		printerr("seed_zone: cannot write %s (error %d)" % [file_name, err])
		return 1
	return 0
```

- [ ] **Step 2: Run it**

```bash
./tools/godot.sh --headless --path . -s tools/seed_zone.gd
```

Expected: `seed_zone: wrote a 128x128 zone to res://data/zone/home`, preceded
by the scatter count.

- [ ] **Step 3: Update the zone document**

Rewrite `data/zone/home/zone.json`. Every colour the seeding tool writes needs
a legend entry, or Task 3's unknown-colour rule fires:

```json
{
  "id": "home",
  "category": "zone",
  "display_name": "Home Valley",
  "size": [128, 128],
  "biome": "temperate",
  "generation_seed": 20260911,
  "maps": {
    "terrain": "terrain.png",
    "object": "object.png",
    "height": "height.png"
  },
  "legend": {
    "terrain": {
      "00ff00": "grass",
      "0000ff": "water",
      "ff8000": "dirt"
    },
    "object": {
      "000000": null,
      "008000": "oak_tree",
      "00c850": "pine_tree",
      "808080": "rock_small",
      "5a5a5a": "rock_large",
      "96dc3c": "bush",
      "c8c8b4": "wall_stone",
      "a06e3c": "wall_wood",
      "dc3c3c": "roof_red",
      "78788c": "roof_grey",
      "5a3c1e": "door",
      "78c8ff": "window"
    }
  },
  "player_spawn": [64.5, 60.5],
  "entities": [
    {"type": "rabbit", "at": [30.5, 70.5]},
    {"type": "rabbit", "at": [34.5, 74.5]},
    {"type": "rabbit", "at": [72.5, 44.5]},
    {"type": "rabbit", "at": [78.5, 48.5]},
    {"type": "rabbit", "at": [96.5, 80.5]},
    {"type": "rabbit", "at": [100.5, 86.5]},
    {"type": "rabbit", "at": [50.5, 104.5]},
    {"type": "rabbit", "at": [56.5, 108.5]}
  ]
}
```

The hex values must match `Color8` triples in the tool exactly: `Color8(0, 200,
80)` is `00c850`, `Color8(150, 220, 60)` is `96dc3c`. Getting one wrong is
caught by `test_zone_home.gd`, not by eye.

- [ ] **Step 4: Verify the real zone**

```bash
./tools/run_tests.sh
```

Expected: PASS, including `test_zone_home.gd`'s three assertions against the
real 128x128 world — zero errors, no unpainted terrain tile, and a walkable
spawn. If an entity landed in a pond that is fine; only the *player* spawn is
checked, and animals wander out.

- [ ] **Step 5: Look at it**

```bash
./tools/godot.sh --headless --path . -s tools/screenshot.gd
```

Open the PNG. The camera starts at the spawn, which sits on the crossroads, so
expect dirt underfoot and grass with scattered trees around. Walk the build if
you have a keyboard; otherwise move `player_spawn` temporarily to look at a
house and the pond, then put it back.

- [ ] **Step 6: Delete the seeding tool**

```bash
git rm tools/seed_zone.gd
grep -rn "seed_zone" --exclude-dir=.git . || echo "no references remain"
```

Expected: no references outside this plan and the spec. The tool's job is done;
its output is committed, and keeping it invites someone to re-run it and
silently discard hand edits — exactly the trap `make_placeholder_art.gd` was
deleted to avoid in Phase 3c.

- [ ] **Step 7: Commit**

```bash
git add data/zone/home
git commit -m "$(cat <<'EOF'
feat: author the home zone

A 128x128 valley: a pond, crossroads, three houses, scattered woodland,
and eight rabbits. Seeded programmatically once, then committed -- from
here the PNGs are the source of truth and the way to change the world is
to edit pixels.

tools/seed_zone.gd is deleted with this commit. Keeping it would invite
someone to re-run it and silently discard hand edits, which is the trap
make_placeholder_art.gd was deleted to avoid in 3c.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

- [ ] **Step 8: Tick this task**

```bash
python3 tools/mark_task_done.py 10 --plan docs/superpowers/plans/2026-09-11-rp1-phase4a-zone-authoring.md
git add docs/superpowers/plans/2026-09-11-rp1-phase4a-zone-authoring.md
git commit -m "docs: tick Phase 4a task 10"
```

---

## Task 11: The legend swatch

**Files:**
- Create: `tools/zone_legend.gd`

**Interfaces:**
- Consumes: `data/zone/home/zone.json`
- Produces: `build/zone_legend.png`, a build artefact, not a committed one.

Editing a zone by hand means knowing which garish colour is which tile. A
labelled swatch strip is the difference between a format a human can edit and
one only an agent can.

- [ ] **Step 1: Write the tool**

Create `tools/zone_legend.gd`:

```gdscript
extends SceneTree
## Emits a labelled swatch image for hand-editing a zone's maps.
##
##   ./tools/godot.sh --headless --path . -s tools/zone_legend.gd
##
## Output is build/zone_legend.png, which is a build artefact and is not
## committed. Open it beside the map in a pixel editor and pick colours
## from it, so a tile id never has to be typed from memory.

const ZONE_DOC: String = "res://data/zone/home/zone.json"
const OUT: String = "res://build/zone_legend.png"

const SWATCH: int = 24
const LABEL_WIDTH: int = 160
const ROW_HEIGHT: int = 28


func _init() -> void:
	var f: FileAccess = FileAccess.open(ZONE_DOC, FileAccess.READ)
	if f == null:
		printerr("zone_legend: cannot open %s" % ZONE_DOC)
		quit(1)
		return
	var parser: JSON = JSON.new()
	var err: int = parser.parse(f.get_as_text())
	f.close()
	if err != OK:
		printerr("zone_legend: %s is not valid JSON" % ZONE_DOC)
		quit(1)
		return

	var legend: Dictionary = (parser.data as Dictionary).get("legend", {})
	var rows: Array = []
	for layer: String in legend:
		var entries: Dictionary = legend[layer]
		var hexes: Array = entries.keys()
		hexes.sort()
		for hex: String in hexes:
			var name: Variant = entries[hex]
			rows.append([layer, hex, "(empty)" if name == null else str(name)])

	if rows.is_empty():
		printerr("zone_legend: no legend entries found")
		quit(1)
		return

	var img: Image = Image.create_empty(
		LABEL_WIDTH + SWATCH + 8, rows.size() * ROW_HEIGHT, false, Image.FORMAT_RGBA8)
	img.fill(Color8(24, 24, 24))
	for n: int in range(rows.size()):
		var hex: String = rows[n][1]
		var c: Color = Color.from_string("#" + hex, Color.MAGENTA)
		img.fill_rect(Rect2i(4, n * ROW_HEIGHT + 2, SWATCH, SWATCH), c)

	DirAccess.make_dir_recursive_absolute("res://build")
	var save_err: int = img.save_png(OUT)
	if save_err != OK:
		printerr("zone_legend: cannot write %s (error %d)" % [OUT, save_err])
		quit(1)
		return

	# The image carries the colours; the console carries the names. Drawing
	# text into an Image needs a font and a viewport, which is a lot of
	# machinery for a build-time crib sheet.
	print("zone_legend: %d entries -> %s" % [rows.size(), OUT])
	for n: int in range(rows.size()):
		print("  row %2d  %-8s #%s  %s" % [n, rows[n][0], rows[n][1], rows[n][2]])
	quit(0)
```

- [ ] **Step 2: Run it and check the output**

```bash
./tools/godot.sh --headless --path . -s tools/zone_legend.gd
```

Expected: fifteen rows printed — three terrain and twelve object — and
`build/zone_legend.png` written. Open it: one swatch per row, in the order
printed.

- [ ] **Step 3: Confirm the artefact is not committed**

```bash
git status --short build/ 2>/dev/null
grep -n "^build" .gitignore || echo "build/ is NOT ignored -- add it"
```

If `build/` is not in `.gitignore`, add a `build/` line. The export gate already
writes there, so this is likely already handled.

- [ ] **Step 4: Commit**

```bash
git add tools/zone_legend.gd .gitignore
git commit -m "$(cat <<'EOF'
feat: emit a legend swatch for hand-editing a zone

A colour-keyed format is only editable by hand if you can see which
colour means what. This writes a swatch strip to build/ and prints the
names beside it, so a tile id never has to be typed from memory.

Swatches in the image, names on the console: drawing text into an Image
needs a font and a viewport, which is a lot of machinery for a
build-time crib sheet.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

- [ ] **Step 5: Tick this task**

```bash
python3 tools/mark_task_done.py 11 --plan docs/superpowers/plans/2026-09-11-rp1-phase4a-zone-authoring.md
git add docs/superpowers/plans/2026-09-11-rp1-phase4a-zone-authoring.md
git commit -m "docs: tick Phase 4a task 11"
```

---

## Task 12: CI gate 7

**Files:**
- Create: `tools/check_zone.sh`, `tools/check_zone.gd`
- Modify: `.github/workflows/ci.yml`

**Interfaces:**
- Consumes: `ZoneLoader.load_zone`, `ContentRegistry.load_from_dir`
- Produces: a seventh CI gate. Exit 0 clean, 1 on a rule failure, 2 if content
  itself will not load.

**The gate runs the real loader and fails if `errors` is non-empty.** It does
not reimplement the checks. This is the reasoning Phase 3c gave for
`palette_report.gd` reusing `PaletteMap`: a tool and the pipeline it checks must
not be able to disagree. On top of the loader's errors it adds the rules the
loader deliberately tolerates at runtime but an author must never commit.

- [ ] **Step 1: Write the shell wrapper**

Create `tools/check_zone.sh`, matching `check_palette.sh`:

```bash
#!/usr/bin/env bash
# The zone gate. Bash cannot read PNGs, so the work is in tools/check_zone.gd.
set -euo pipefail
cd "$(dirname "$0")/.."

[[ -d data/zone ]] || { echo "No data/zone/ yet; nothing to check."; exit 0; }

exec ./tools/godot.sh --headless --path . -s tools/check_zone.gd
```

Then: `chmod +x tools/check_zone.sh`

- [ ] **Step 2: Write the gate**

Create `tools/check_zone.gd`:

```gdscript
extends SceneTree
## The zone gate: every authored zone under data/zone/ loads clean and is
## fit to play.
##
## This calls ZoneLoader rather than reading the PNGs itself. A gate with
## its own copy of the format is a gate that eventually disagrees with the
## game, and the disagreement always surfaces as a bug nobody can
## reproduce -- the same reasoning that has palette_report.gd reuse
## PaletteMap.
##
## The loader is deliberately forgiving at runtime: an unreadable map costs
## one layer, not the world. This is where that forgiveness stops.

const ZONE_ROOT: String = "res://data/zone"
const MAPS: PackedStringArray = ["terrain.png", "object.png", "height.png"]
const MAX_REPORTED: int = 8

var _failures: int = 0


func _init() -> void:
	var registry: ContentRegistry = ContentRegistry.new()
	var content_errors: PackedStringArray = registry.load_from_dir("res://data")
	if not content_errors.is_empty():
		for e: String in content_errors:
			printerr("content: %s" % e)
		printerr("Zone gate: content does not load, so no zone can be checked.")
		quit(2)
		return

	var dirs: PackedStringArray = DirAccess.get_directories_at(ZONE_ROOT)
	if dirs.is_empty():
		print("Zone gate: no zones under %s" % ZONE_ROOT)
		quit(0)
		return
	dirs.sort()

	for name: String in dirs:
		_check_zone(ZONE_ROOT.path_join(name), registry)

	if _failures > 0:
		printerr("")
		printerr("Zone gate: %d problem(s)." % _failures)
		printerr("A zone is data/zone/<id>/zone.json plus one PNG per tile column.")
		printerr("Colours are declared in the legend; every colour used must be")
		printerr("declared, every terrain tile must be painted, and the spawn must")
		printerr("be somewhere the player can stand. To see which colour is which:")
		printerr("  ./tools/godot.sh --headless --path . -s tools/zone_legend.gd")
		quit(1)
		return
	print("Zone gate: OK (%d zone(s))" % dirs.size())
	quit(0)


func _fail(message: String) -> void:
	printerr(message)
	_failures += 1


func _check_zone(dir: String, registry: ContentRegistry) -> void:
	var result: ZoneLoadResult = ZoneLoader.load_zone(dir, registry)

	# Rule: whatever the loader reports at runtime is a build failure here.
	# This covers unknown colours, malformed legend keys, wrong map sizes,
	# partial alpha, and any legend id or entity type the build cannot
	# resolve -- all of which the loader turns into placeholders and carries
	# on with, which is right in a shipped game and wrong in a commit.
	for e: String in result.errors:
		_fail("%s: %s" % [dir, e])

	if result.zone == null:
		_fail("%s: did not load at all" % dir)
		return

	_check_fully_painted(dir, result.zone)
	_check_spawn(dir, result)
	_check_import_modes(dir)
	_report_unused_legend(dir, result.zone, registry)


## An unpainted terrain tile is ID_UNKNOWN, which Walkability treats as void
## rather than floor: a hole in the world the player cannot cross and
## nothing logs.
func _check_fully_painted(dir: String, zone: Zone) -> void:
	var holes: int = 0
	for y: int in range(zone.size_tiles.y):
		for x: int in range(zone.size_tiles.x):
			if zone.get_terrain(Vector2i(x, y)) != ContentRegistry.ID_UNKNOWN:
				continue
			holes += 1
			if holes <= MAX_REPORTED:
				_fail("%s: terrain tile (%d,%d) is unpainted" % [dir, x, y])
	if holes > MAX_REPORTED:
		printerr("%s: ... and %d more unpainted terrain tile(s)"
			% [dir, holes - MAX_REPORTED])


func _check_spawn(dir: String, result: ZoneLoadResult) -> void:
	var zone: Zone = result.zone
	var tile: Vector2i = Vector2i(
		floori(result.player_spawn.x), floori(result.player_spawn.y))
	if not zone.in_bounds(tile):
		_fail("%s: player_spawn %s is outside the zone" % [dir, tile])
		return
	if not zone.is_walkable(tile):
		_fail("%s: player_spawn %s is blocked; the player would start inside something"
			% [dir, tile])


## Opening the project in the editor is exactly the kind of ordinary act
## that reverts an import mode, and the consequence -- maps missing from the
## export pack -- shows up only in a shipped build.
func _check_import_modes(dir: String) -> void:
	for map_name: String in MAPS:
		var path: String = dir.path_join(map_name + ".import")
		if not FileAccess.file_exists(path):
			_fail("%s: missing; the map would be imported as a texture" % path)
			continue
		var f: FileAccess = FileAccess.open(path, FileAccess.READ)
		if f == null:
			_fail("%s: cannot open" % path)
			continue
		var text: String = f.get_as_text()
		f.close()
		if not text.contains('importer="keep"'):
			_fail('%s: must say importer="keep"; re-apply it and re-import' % path)


## Reported, never failed: an author adds a colour before painting with it,
## and failing on that would make the format annoying to work in for no
## safety gain.
func _report_unused_legend(dir: String, zone: Zone, registry: ContentRegistry) -> void:
	# Compare by string id. Numeric ids are assigned per registry instance
	# and mean nothing outside it.
	var used: Dictionary = {}
	for y: int in range(zone.size_tiles.y):
		for x: int in range(zone.size_tiles.x):
			var w: Vector2i = Vector2i(x, y)
			used[registry.string_of(zone.get_terrain(w))] = true
			used[registry.string_of(zone.get_object(w))] = true

	var parser: JSON = JSON.new()
	var f: FileAccess = FileAccess.open(dir.path_join("zone.json"), FileAccess.READ)
	if f == null:
		return
	var err: int = parser.parse(f.get_as_text())
	f.close()
	if err != OK:
		return

	var legend: Dictionary = (parser.data as Dictionary).get("legend", {})
	for layer: String in legend:
		for hex: String in legend[layer]:
			var value: Variant = legend[layer][hex]
			if value == null:
				continue
			if not used.has(str(value)):
				print("%s: note: legend %s #%s (%s) is declared but unused"
					% [dir, layer, hex, str(value)])
```

- [ ] **Step 3: Run the gate and expect it to pass**

```bash
./tools/check_zone.sh
```

Expected: `Zone gate: OK (1 zone(s))`.

- [ ] **Step 4: See every rule fail**

A gate nobody has watched fail is a gate nobody knows works. Break each rule,
confirm the message, and restore. **Restore after each one** — do not batch
them.

```bash
# Rule 1 -- an unpainted terrain tile.
#   Set one terrain pixel to a colour with no legend entry, run the gate.
#   Expect BOTH an unknown-colour error and an unpainted-tile error.
#   Restore with: git checkout data/zone/home/terrain.png

# Rule 2 -- a blocked spawn.
#   Edit data/zone/home/zone.json: set "player_spawn" to a tile holding a
#   house wall, e.g. [21.5, 22.5]. Run the gate.
#   Expect: player_spawn (21,22) is blocked.
#   Restore with: git checkout data/zone/home/zone.json

# Rule 3 -- a legend id this build does not have.
#   Edit zone.json: change "008000": "oak_tree" to "008000": "oak_treee".
#   Expect: 'oak_treee' is not in this build; using a placeholder.
#   Restore with: git checkout data/zone/home/zone.json

# Rule 4 -- a reverted import mode.
#   Edit data/zone/home/terrain.png.import: importer="keep" -> "texture".
#   Expect: must say importer="keep".
#   Restore with: git checkout data/zone/home/terrain.png.import
```

Confirm `git status` is clean before moving on.

- [ ] **Step 5: Add the gate to CI**

In `.github/workflows/ci.yml`, immediately after the `Palette` step:

```yaml
      - name: Zone
        run: ./tools/check_zone.sh
```

- [ ] **Step 6: Run every gate**

```bash
./tools/run_tests.sh
./tools/godot.sh --headless --path . -s tools/guard.gd
./tools/godot.sh --headless --path . -s tools/smoke.gd
./tools/check_asset_licences.sh
./tools/check_palette.sh
./tools/check_zone.sh
```

Expected: six green.

- [ ] **Step 7: Commit**

```bash
git add tools/check_zone.sh tools/check_zone.gd .github/workflows/ci.yml
git commit -m "$(cat <<'EOF'
ci: add the zone gate

Zone authoring introduces a class of mistake nothing else catches: a hole
in the terrain, a spawn inside a wall, a colour nobody declared, an
import mode the editor quietly reverted. None of them break a test and
all of them ruin the world.

The gate calls ZoneLoader rather than reading the PNGs itself. A gate
with its own copy of the format eventually disagrees with the game, and
that disagreement always surfaces as a bug nobody can reproduce.

All four rules were watched failing before being trusted.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

- [ ] **Step 8: Tick this task**

```bash
python3 tools/mark_task_done.py 12 --plan docs/superpowers/plans/2026-09-11-rp1-phase4a-zone-authoring.md
git add docs/superpowers/plans/2026-09-11-rp1-phase4a-zone-authoring.md
git commit -m "docs: tick Phase 4a task 12"
```

---

## Task 13: Close the phase

**Files:**
- Modify: `docs/superpowers/specs/2026-08-23-rp1-stage0-stage1-design.md` (§10)
- Modify: `README.md` if it describes the world as generated

- [ ] **Step 1: Record the phase split where Phase 3's split is recorded**

The Stage 1 design already records Phase 3's split inline, with the note "the
split is recorded here because the phase boundaries below moved with it". Do the
same for Phase 4. Replace the `### Phase 4 — World content` body with:

```markdown
### Phase 4 — World content

Split into two slices, recorded here because the boundaries below moved
with it.

**Phase 4a — zone authoring** *(done)*

- The 128x128 zone authored **as data**: one PNG per tile column plus a
  JSON legend under `data/zone/home/`, read at boot by `ZoneLoader`
- Trees, rocks, water, paths, three houses (exterior only)
- CI gate 7 (`tools/check_zone.sh`) and the legend swatch tool

**Phase 4b — living world**

- `AnimalSystem`: wander within a radius, flee the player. Deliberately
  dumb — this validates the entity pipeline, not AI.
- A multi-consumer dirty channel, so the collision cache and
  `ZoneRenderer` can both react to zone mutation

*(Collision from walkable flags and `EntityRenderer` moved earlier, into
Phase 3b.)*
```

- [ ] **Step 2: Verify the whole definition of done**

Work through the spec's §9 acceptance criteria one at a time and record the
result of each in the commit message. Specifically:

```bash
# Every gate.
./tools/run_tests.sh
./tools/godot.sh --headless --path . -s tools/guard.gd
./tools/godot.sh --headless --path . -s tools/smoke.gd
./tools/check_asset_licences.sh
./tools/check_palette.sh
./tools/check_zone.sh

# No pre-existing test was modified. Expect only new test files.
git diff --stat main...HEAD -- tests/

# _build_debug_zone is gone.
grep -rn "_build_debug_zone\|POND_CENTRE\|TREE_SPACING" src/ || echo "gone"

# The exported build still renders, which is what proves the maps
# reached the pack.
./tools/godot.sh --headless --path . --export-pack "Linux" /tmp/rp1_done.pck
./tools/godot.sh --headless --main-pack /tmp/rp1_done.pck 2>&1 | grep "RP1 rendered"
rm -f /tmp/rp1_done.pck
```

Expected on the last one: `RP1 rendered <N> cells` with N in the tens of
thousands — a zone that failed to load renders zero, so a non-zero count is the
proof that the PNGs are in the pack and readable.

- [ ] **Step 3: Prove the sharpest acceptance criterion**

Change one pixel and confirm one tile changes, with no code and no re-export:

```bash
# Open data/zone/home/object.png, erase one tree pixel to 000000, save.
./tools/check_zone.sh
./tools/godot.sh --headless --path . -s tools/screenshot.gd
# Confirm the tree is gone from the screenshot, then:
git checkout data/zone/home/object.png
```

- [ ] **Step 4: Commit**

```bash
git add docs README.md
git commit -m "$(cat <<'EOF'
docs: settle the Phase 4a definition of done

Records the 4a/4b split in the Stage 1 design where Phase 3's split is
already recorded, and closes out the acceptance criteria.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

- [ ] **Step 5: Tick this task**

```bash
python3 tools/mark_task_done.py 13 --plan docs/superpowers/plans/2026-09-11-rp1-phase4a-zone-authoring.md
git add docs/superpowers/plans/2026-09-11-rp1-phase4a-zone-authoring.md
git commit -m "docs: tick Phase 4a task 13"
```

---

## Definition of done for Phase 4a

- [ ] `data/zone/home/` holds `zone.json` and three PNGs, and
      `_build_debug_zone()` and its constants are gone from `main.gd`
- [ ] The game boots into the authored zone and the player can walk it
- [ ] `./tools/check_zone.sh` green, and **each of its four rules seen to fail**
- [ ] `./tools/run_tests.sh` green, with **every pre-existing test file
      unmodified**
- [ ] `tools/guard.gd`, `tools/smoke.gd`, `check_asset_licences.sh` and
      `check_palette.sh` still green
- [ ] The exported build prints a non-zero `RP1 rendered <N> cells`, proving the
      maps reached the pack
- [ ] A 128x128 zone loads in under one second (`test_zone_load_budget.gd`)
- [ ] Editing one pixel changes one tile, with no code change
- [ ] `tools/seed_zone.gd` is deleted and no non-historical file mentions it
- [ ] Three houses, a pond, roads, rocks and trees are visible in a screenshot
- [ ] The Stage 1 design §10 records the 4a/4b split

**Not done in this phase, by design:** `AnimalSystem` and the multi-consumer
dirty channel (Phase 4b), save wiring and New World / Continue (Phase 5),
autotiling and transition tiles (deferred by 3c, revisited in Phase 6),
building interiors, and any second zone.
