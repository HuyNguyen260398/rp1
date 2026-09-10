# RP1 Phase 3c — Art Pipeline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the five debug swatches with real, Apollo-quantized art produced by a reproducible tool, and make an off-palette pixel unmergeable in CI.

**Architecture:** Third-party art enters the repo twice — once as downloaded under `assets/_source/` (committed, `.gdignore`'d, never in the PCK), and once as `assets/**.png` derived from it by `tools/quantize.gd`. All colour logic lives in a node-free `PaletteMap` that maps the *distinct colour set* in OKLab with a committed override table. The tool slices sheets into per-tile PNGs so every content definition still owns its whole PNG and no rendering code changes.

**Tech Stack:** Godot 4.7.2 (standard build), GDScript with static typing, GUT for tests, bash for CI gate entry points.

**Spec:** `docs/superpowers/specs/2026-09-10-rp1-phase3c-art-pipeline-design.md`

## Global Constraints

Copied verbatim from `CLAUDE.md` and the spec. Every task's requirements implicitly include these.

- Godot **4.7.2**, standard build. **Not the Mono build.** Invoke Godot only through `./tools/godot.sh`.
- GDScript only. Static typing everywhere: `var x: int = 0`, `func f(a: Vector2i) -> void:`.
- `src/core/` and `src/systems/` **MUST NOT reference Godot nodes.** This phase adds nothing to either — all new code lives in `tools/` and `tests/`, which `tools/guard.gd` does not scan.
- Tile size is 32×32. **Character sprites are 32×64** — unchanged by this phase, see spec §3.2.
- Texture filter is `Nearest`, project-wide. Never override per-texture.
- Palette is fixed: Apollo, 46 colours, `docs/palette.md`. Do not introduce new colours.
- Every folder under `assets/` has a `LICENSE.txt` naming source, author, licence. Record every pack in `assets/CREDITS.md` **at import time, not later**.
- **Never add a CC-NC asset.** CC-BY-SA must be flagged before use.
- **No Elin art, sprite, tile or asset may be copied into this project** (`docs/palette.md` §7). Reference screenshots live in `docs/reference/`, which is git-ignored.
- TDD: write the failing test, watch it fail, implement minimally, watch it pass.
- Run tests with `./tools/run_tests.sh` — never call `gut_cmdln.gd` directly.
- Conventional commit prefixes: `feat:`, `test:`, `ci:`, `docs:`, `fix:`.
- Each plan task produces two commits: the code, then a `docs:` commit ticking that task's checkboxes. **`tools/mark_task_done.py` defaults to a glob matching only the Phases 0–2 plan**, so `--plan` is mandatory here — a bare invocation silently ticks the wrong file:
  ```bash
  python3 tools/mark_task_done.py <task-number> --plan docs/superpowers/plans/2026-09-10-rp1-phase3c-art-pipeline.md
  ```
- Commit messages end with:
  ```
  Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
  ```

**Baseline before starting:** 163 tests passing across 18 scripts. All four gates green.

**Already done, before this plan starts:** spec §8's reference-image bullet is complete as of commit `e5ecf22` — `docs/reference/` exists with a `.gitignore` rule, a `.gdignore`, and a README, and the two stray PNGs are out of the repository root. No task below repeats it.

**A numbering note.** The spec and `docs/palette.md` §1 both call the palette check "CI gate 6". CI currently has gates 1–4 in the `verify` job and gate 5 (export) in the `export` job, and the palette check belongs in `verify` — so it becomes **gate 5** and export renumbers to 6. Execution order wins over the label that was written before the gate existed; Task 10 corrects `palette.md` to match.

---

## File structure

**Created:**

| Path | Responsibility |
|---|---|
| `assets/_source/.gdignore` | Stops Godot importing source art, so it never reaches the PCK |
| `assets/_source/buch-outdoor/sheet.png` | Terrain and object source, as downloaded |
| `assets/_source/buch-outdoor/LICENSE.txt` | CC0, Buch, source URL |
| `assets/_source/bukket-characters/*.bmp` | Character source, as downloaded |
| `assets/_source/bukket-characters/LICENSE.txt` | CC-BY 3.0, Bukket Games, source URL, attribution text |
| `tools/palette/apollo.json` | The 46 colours as data, grouped by ramp |
| `tools/palette_map.gd` | **All** colour logic: OKLab nearest, overrides, image quantization. Node-free, `RefCounted`, unit-tested |
| `tools/import_manifest.json` | Which rect of which source becomes which asset |
| `tools/palette_overrides.json` | Source colour → chosen Apollo step, with a reason |
| `tools/quantize.gd` | `SceneTree` driver: read manifest, crop, call `PaletteMap`, write PNG, print report |
| `tools/check_palette.gd` | The gate's pixel walk |
| `tools/check_palette.sh` | CI gate 6 entry point |
| `tests/test_palette.gd` | `apollo.json` ↔ `docs/palette.md` agreement |
| `tests/test_palette_map.gd` | OKLab nearest, overrides, alpha, determinism |
| `tests/test_import_manifest.gd` | Manifest ↔ content JSON agreement |

**Modified:** `assets/tiles/*.png`, `assets/objects/*.png`, `assets/characters/*.png` (regenerated), `assets/*/LICENSE.txt`, `assets/CREDITS.md`, `docs/palette.md`, `data/object/oak_tree.json` (only if the tree is not 32×48), `.github/workflows/ci.yml`, `docs/rp1-game-dev-plan.md`, `docs/superpowers/specs/2026-08-23-rp1-stage0-stage1-design.md`.

**Deleted:** `tools/make_placeholder_art.gd`, `tools/make_placeholder_art.gd.uid`.

---

## Task 1: Acquire and inspect the sources

The one task that cannot be fully scripted: it ends with rectangles that were chosen by looking. Everything downstream consumes those numbers, so they get written down here.

**Files:**
- Create: `assets/_source/.gdignore`, `assets/_source/buch-outdoor/{sheet.png,LICENSE.txt}`, `assets/_source/bukket-characters/{*.bmp,LICENSE.txt}`
- Create (throwaway): `/tmp/inspect.gd`

**Interfaces:**
- Produces: the rect list consumed by Task 7's `tools/import_manifest.json`. Record it in the Task 7 step, not in your head.

- [x] **Step 1: Create the source tree and stop Godot importing it**

```bash
mkdir -p assets/_source/buch-outdoor assets/_source/bukket-characters
touch assets/_source/.gdignore
```

`.gdignore` is an empty marker file. Godot skips the whole directory, so nothing here is imported or reaches the exported PCK. `Image.load_from_file()` still reads these files at build time — verified on 4.7.2; `ResourceLoader.exists()` on the same path correctly returns `false`.

- [x] **Step 2: Download both packs**

Open each page, download, and place the files:

- <https://opengameart.org/content/outdoor-32x32-tileset> → `assets/_source/buch-outdoor/sheet.png`
- <https://opengameart.org/content/top-down-rpg-character-sprites> → `assets/_source/bukket-characters/` (three `.bmp` templates: child, male, woman)

If a direct link is available, `curl -sSLo <dest> <url>` works. If OpenGameArt requires a browser, download manually and move the files. Do not proceed with placeholder files — every rect chosen below depends on the real sheets.

- [x] **Step 3: Write the licence files**

`assets/_source/buch-outdoor/LICENSE.txt`:

```
Outdoor 32x32 tileset
Author:  Buch
Source:  https://opengameart.org/content/outdoor-32x32-tileset
Licence: CC0 1.0 (public domain dedication)

No attribution is legally required. Buch requests credit as "Buch" with a
link to their OpenGameArt profile, and assets/CREDITS.md carries it.
```

`assets/_source/bukket-characters/LICENSE.txt`:

```
Top-Down RPG Character Sprites
Author:  Bukket Games (bukketgames)
Source:  https://opengameart.org/content/top-down-rpg-character-sprites
Licence: CC-BY 3.0

ATTRIBUTION IS A LICENCE CONDITION, NOT A COURTESY. It must remain in
assets/CREDITS.md and in any distributed build's credits. Do not remove it
while "tidying up" -- unlike every other asset in this project so far,
removing this one is a licence violation.
```

- [x] **Step 4: Inspect the sheets**

Write `/tmp/inspect.gd`:

```gdscript
extends SceneTree
## Throwaway. Prints what the source sheets contain so rects can be chosen.

const SOURCES: PackedStringArray = [
	"res://assets/_source/buch-outdoor/sheet.png",
	"res://assets/_source/bukket-characters/template_w.bmp",
]


func _init() -> void:
	for path: String in SOURCES:
		var img: Image = Image.load_from_file(path)
		if img == null:
			printerr("could not read %s" % path)
			continue
		var seen: Dictionary = {}
		for y: int in range(img.get_height()):
			for x: int in range(img.get_width()):
				seen[img.get_pixel(x, y).to_html(false)] = true
		print("%s  %dx%d  tiles=%dx%d  distinct colours=%d" % [
			path, img.get_width(), img.get_height(),
			img.get_width() / 32, img.get_height() / 32, seen.size()])
		# A grid overlay makes rects choosable by eye at 1:1.
		var grid: Image = img.duplicate()
		for y: int in range(grid.get_height()):
			for x: int in range(grid.get_width()):
				if x % 32 == 0 or y % 32 == 0:
					grid.set_pixel(x, y, Color(1, 0, 1, 1))
		var out: String = "/tmp/%s-grid.png" % path.get_file().get_basename()
		grid.save_png(out)
		print("  grid overlay -> %s" % out)
	quit(0)
```

Run it:

```bash
./tools/godot.sh --headless --path . -s /tmp/inspect.gd
```

- [x] **Step 5: Choose the rects by looking at the grid overlays**

Open each `/tmp/*-grid.png`. Write down, on paper or in the commit message, the `[x, y, w, h]` for:

| Asset | Needs |
|---|---|
| `grass` | a 32×32 plain grass tile |
| `water` | a 32×32 plain water tile |
| `oak_tree` | a tree. **Record its real height** — the pack's description says "stumps", so a full tree may not exist |
| `player` | one 32×64 front-facing standing frame |
| `rabbit` | a 32×64 frame; any non-player template, since nothing spawns a rabbit until Phase 4 |

**Decision point — if there is no usable tree.** Do not improvise and do not defer. Pick one and record why in the commit message:
1. Use a different Buch sheet from the same author (best: keeps one style, still CC0).
2. Source one CC0 tree from OpenGameArt and add a third `assets/_source/` folder with its own `LICENSE.txt`.
3. Use a large rock or stump as the blocking object and rename the content definition — a bigger change, since `data/object/oak_tree.json` and its string id are referenced in saves and tests.

- [x] **Step 6: Verify the source tree is invisible to the engine**

```bash
./tools/godot.sh --headless --path . --import 2>&1 | grep -i "_source" && echo "FAIL: source art was imported" || echo "OK: source art not imported"
ls assets/_source/buch-outdoor/*.import 2>/dev/null && echo "FAIL: .import files generated" || echo "OK: no .import files"
```

Expected: both `OK`.

- [x] **Step 7: Commit**

```bash
git add assets/_source/
git commit -m "$(cat <<'EOF'
feat: commit the Buch and Bukket art sources

Import is a transform, not a copy: third-party art enters the repo as
downloaded and is re-derived into assets/ by tools/quantize.gd. The
palette is still provisional (docs/palette.md section 2), so a palette
change has to be a re-run rather than a re-download of URLs that may be
dead by then.

A .gdignore keeps the whole tree out of the import pass and the PCK.
Image.load_from_file still reads it at build time; ResourceLoader cannot
see it at all, which is exactly the split we want.

Rects chosen from the grid overlays:
  grass     [x, y, 32, 32]
  water     [x, y, 32, 32]
  oak_tree  [x, y, 32, H]
  player    [x, y, 32, 64]
  rabbit    [x, y, 32, 64]

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

Replace the placeholder rects with the real numbers before committing.

- [x] **Step 8: Tick this task**

```bash
python3 tools/mark_task_done.py 1 --plan docs/superpowers/plans/2026-09-10-rp1-phase3c-art-pipeline.md
git add docs/superpowers/plans/2026-09-10-rp1-phase3c-art-pipeline.md
git commit -m "docs: tick Phase 3c task 1"
```

---

## Task 2: The palette as data, with a drift test

`docs/palette.md` §3 is currently the only copy of the 46 colours, and it is prose. Two tools need them. Two copies of a colour list drift, so the second copy arrives with a test that pins it to the first.

**Files:**
- Create: `tools/palette/apollo.json`, `tests/test_palette.gd`

**Interfaces:**
- Produces: `tools/palette/apollo.json` with shape `{name, author, source, outline, ramps: {<ramp>: [<hex>, ...]}}`. Hex values are lowercase, six digits, **no leading `#`**. Consumed by Task 3.

- [x] **Step 1: Write the failing test**

Create `tests/test_palette.gd`:

```gdscript
extends GutTest
## Pins tools/palette/apollo.json to docs/palette.md.
##
## The palette existed as prose first. A second machine-readable copy is
## only safe if something fails when the two disagree -- otherwise the
## next colour change lands in one of them and nobody notices for a month.

const JSON_PATH: String = "res://tools/palette/apollo.json"
const DOC_PATH: String = "res://docs/palette.md"

var _ramps: Dictionary = {}


func before_each() -> void:
	var f: FileAccess = FileAccess.open(JSON_PATH, FileAccess.READ)
	assert_not_null(f, "apollo.json is readable")
	if f == null:
		return
	var parser: JSON = JSON.new()
	# JSON.new().parse() rather than JSON.parse_string(): the static helper
	# pushes an engine-level error on bad input, which is log noise and
	# fails the tests that deliberately feed it one. Same reasoning as
	# ContentRegistry.
	var err: int = parser.parse(f.get_as_text())
	f.close()
	assert_eq(err, OK, "apollo.json parses")
	_ramps = parser.data.get("ramps", {}) if err == OK else {}


func _all_colours() -> Array[String]:
	var out: Array[String] = []
	for ramp: String in _ramps:
		for hexs: String in _ramps[ramp]:
			out.append(hexs)
	return out


func test_the_palette_has_forty_six_unique_colours() -> void:
	var all: Array[String] = _all_colours()
	assert_eq(all.size(), 46, "Apollo is 46 colours")
	var unique: Dictionary = {}
	for h: String in all:
		unique[h] = true
	assert_eq(unique.size(), 46, "no colour appears twice")


func test_every_colour_is_lowercase_six_digit_hex_without_a_hash() -> void:
	var re: RegEx = RegEx.create_from_string("^[0-9a-f]{6}$")
	for h: String in _all_colours():
		assert_not_null(re.search(h), "%s is bare lowercase hex" % h)


func test_the_json_and_the_documentation_agree() -> void:
	# docs/palette.md contains exactly the 46 palette colours and no other
	# hex codes -- sections 3 and 4 both draw from the same set. So set
	# equality is the assertion, not subset.
	var f: FileAccess = FileAccess.open(DOC_PATH, FileAccess.READ)
	assert_not_null(f, "docs/palette.md is readable")
	if f == null:
		return
	var doc: String = f.get_as_text()
	f.close()

	var in_doc: Dictionary = {}
	var re: RegEx = RegEx.create_from_string("#([0-9a-fA-F]{6})\\b")
	for m: RegExMatch in re.search_all(doc):
		in_doc[m.get_string(1).to_lower()] = true

	var in_json: Dictionary = {}
	for h: String in _all_colours():
		in_json[h] = true

	var missing_from_doc: Array = []
	for h: String in in_json:
		if not in_doc.has(h):
			missing_from_doc.append(h)
	var missing_from_json: Array = []
	for h: String in in_doc:
		if not in_json.has(h):
			missing_from_json.append(h)

	missing_from_doc.sort()
	missing_from_json.sort()
	assert_eq(missing_from_doc, [], "colours in apollo.json but not in palette.md")
	assert_eq(missing_from_json, [], "colours in palette.md but not in apollo.json")


func test_the_outline_colour_is_in_the_palette() -> void:
	var f: FileAccess = FileAccess.open(JSON_PATH, FileAccess.READ)
	var parser: JSON = JSON.new()
	var _e: int = parser.parse(f.get_as_text())
	f.close()
	var outline: String = str(parser.data.get("outline", ""))
	# palette.md section 4 fixes the outline as the darkest blue, not the
	# darkest neutral: a blue-black outline keeps outdoor art from reading
	# as sooty.
	assert_eq(outline, "172038", "outline is the darkest blue")
	assert_true(_all_colours().has(outline), "the outline is a palette colour")
```

- [x] **Step 2: Run it and watch it fail**

```bash
./tools/run_tests.sh 2>&1 | tail -20
```

Expected: FAIL — `apollo.json is readable` fails because the file does not exist.

- [x] **Step 3: Write the palette file**

Create `tools/palette/apollo.json`. Values are transcribed from `docs/palette.md` §3, in ramp order, dark to light:

```json
{
  "name": "Apollo",
  "author": "AdamCYounis",
  "source": "https://lospec.com/palette-list/apollo",
  "outline": "172038",
  "ramps": {
    "blue":    ["172038", "253a5e", "3c5e8b", "4f8fba", "73bed3", "a4dddb"],
    "green":   ["19332d", "25562e", "468232", "75a743", "a8ca58", "d0da91"],
    "tan":     ["4d2b32", "7a4841", "ad7757", "c09473", "d7b594", "e7d5b3"],
    "gold":    ["341c27", "602c2c", "884b2b", "be772b", "de9e41", "e8c170"],
    "red":     ["241527", "411d31", "752438", "a53030", "cf573c", "da863e"],
    "purple":  ["1e1d39", "402751", "7a367b", "a23e8c", "c65197", "df84a5"],
    "neutral": ["090a14", "10141f", "151d28", "202e37", "394a50", "577277",
                "819796", "a8b5b2", "c7cfcc", "ebede9"]
  }
}
```

It lives in `tools/`, not `data/`. `data/` is game content loaded by `ContentRegistry`; the palette is a build-time constraint the running game never reads. (`ContentRegistry.CATEGORIES` is an allowlist, so `data/palette/` would be silently ignored — safe, but wrong.)

- [x] **Step 4: Run it and watch it pass**

```bash
./tools/run_tests.sh 2>&1 | tail -20
```

Expected: PASS. Totals: **19 scripts, 167 tests**.

- [x] **Step 5: Commit**

```bash
git add tools/palette/apollo.json tests/test_palette.gd
git commit -m "$(cat <<'EOF'
feat: add the Apollo palette as data, pinned to the documentation

docs/palette.md section 3 was the only copy of the 46 colours and it is
prose. Two build-time tools need them, and two copies of a colour list
drift, so the machine-readable copy arrives with a test asserting set
equality against the markdown.

Lives in tools/ rather than data/: data/ is game content loaded by
ContentRegistry, and the palette is a constraint the running game never
reads.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

- [x] **Step 6: Tick this task**

```bash
python3 tools/mark_task_done.py 2 --plan docs/superpowers/plans/2026-09-10-rp1-phase3c-art-pipeline.md
git add docs/superpowers/plans/2026-09-10-rp1-phase3c-art-pipeline.md
git commit -m "docs: tick Phase 3c task 2"
```

---

## Task 3: `PaletteMap` — nearest colour in OKLab

**Files:**
- Create: `tools/palette_map.gd`, `tests/test_palette_map.gd`

**Interfaces:**
- Consumes: `tools/palette/apollo.json` from Task 2.
- Produces:
  - `class_name PaletteMap extends RefCounted`
  - `const ALPHA_THRESHOLD: int = 128`
  - `func load_palette(path: String) -> PackedStringArray` — returns errors, empty on success
  - `func nearest(c: Color) -> Color`
  - `func ramp_of(c: Color) -> String` — ramp name of the *nearest* palette colour
  - `func size() -> int`
  - `func has_colour(c: Color) -> bool` — exact membership, used by the gate in Task 8

- [x] **Step 1: Write the failing test**

Create `tests/test_palette_map.gd`. Every expected value below was computed against the Apollo values and verified — do not adjust them to match an implementation.

```gdscript
extends GutTest

const PALETTE: String = "res://tools/palette/apollo.json"

var _m: PaletteMap


func before_each() -> void:
	_m = PaletteMap.new()
	var errs: PackedStringArray = _m.load_palette(PALETTE)
	assert_eq(errs.size(), 0, "palette loads: %s" % ", ".join(errs))


func test_it_loads_forty_six_colours() -> void:
	assert_eq(_m.size(), 46, "the whole palette is loaded")


func test_a_palette_colour_maps_to_itself() -> void:
	# Idempotence. Quantizing already-quantized art must be a no-op, or
	# re-running the pipeline would drift the assets a little every time.
	for hexs: String in ["7a4841", "75a743", "4f8fba", "172038", "ebede9"]:
		var c: Color = Color(hexs)
		assert_eq(_m.nearest(c).to_html(false), hexs, "#%s maps to itself" % hexs)


func test_known_colours_map_to_the_expected_step() -> void:
	# Verified against the Apollo values in OKLab.
	var cases: Dictionary = {
		"ff0000": "cf573c",  # pure red -> the Red ramp's light step
		"000000": "090a14",  # pure black -> the darkest neutral
		"ffffff": "ebede9",  # pure white -> the lightest neutral
		"808080": "819796",  # mid grey -> a cool grey-green, never pure grey
		"33462a": "25562e",  # an Elin meadow green -> the Green ramp
		"c0ffc0": "d0da91",  # pale mint -> the lightest green
	}
	for src: String in cases:
		assert_eq(_m.nearest(Color(src)).to_html(false), cases[src],
			"#%s maps to #%s" % [src, cases[src]])


func test_it_reports_the_ramp() -> void:
	assert_eq(_m.ramp_of(Color("33462a")), "green", "meadow green is in the Green ramp")
	assert_eq(_m.ramp_of(Color("808080")), "neutral", "grey is in the Neutral ramp")
	assert_eq(_m.ramp_of(Color("ff0000")), "red", "red is in the Red ramp")


func test_exact_membership_is_not_nearest() -> void:
	# The gate needs "is this pixel literally on the palette", which is a
	# different question from "what is closest". A near-miss must fail.
	assert_true(_m.has_colour(Color("75a743")), "an exact palette colour")
	assert_false(_m.has_colour(Color("75a744")), "one digit off is not on the palette")


func test_mapping_is_deterministic() -> void:
	# Two instances must agree, or committed assets would depend on
	# dictionary iteration order and the pipeline would not be reproducible.
	var other: PaletteMap = PaletteMap.new()
	var _e: PackedStringArray = other.load_palette(PALETTE)
	for hexs: String in ["33462a", "808080", "c0ffc0", "2b2b2b", "ff00ff"]:
		assert_eq(_m.nearest(Color(hexs)).to_html(false),
			other.nearest(Color(hexs)).to_html(false),
			"#%s maps identically across instances" % hexs)


func test_a_missing_palette_file_reports_an_error_rather_than_crashing() -> void:
	var m: PaletteMap = PaletteMap.new()
	var errs: PackedStringArray = m.load_palette("res://tools/palette/nope.json")
	assert_gt(errs.size(), 0, "a missing file is an error, not a crash")
	assert_eq(m.size(), 0, "nothing was loaded")
```

- [x] **Step 2: Run it and watch it fail**

```bash
./tools/run_tests.sh 2>&1 | tail -20
```

Expected: FAIL — `PaletteMap` is not a known class.

- [x] **Step 3: Write the implementation**

Create `tools/palette_map.gd`:

```gdscript
class_name PaletteMap
extends RefCounted
## Maps arbitrary colours onto the fixed Apollo palette.
##
## Build-time only. Nothing in the running game loads this -- it exists so
## that imported art can be re-derived onto the palette by a tool rather
## than by hand, which is what makes docs/palette.md a constraint instead
## of a style guide.
##
## Distance is Euclidean in OKLab, not RGB. RGB distance picks visibly
## wrong shades in dark greens and blues, which are precisely the ramps
## this game spends most of its pixels in -- an Elin meadow screenshot
## measured 85% Green.

## Alpha at or above this becomes opaque; below becomes fully transparent.
## Under project-wide Nearest filtering, partial alpha has no meaning.
const ALPHA_THRESHOLD: int = 128

var _colours: PackedColorArray = PackedColorArray()
var _labs: Array[Vector3] = []
var _ramp_by_index: PackedStringArray = PackedStringArray()
var _exact: Dictionary = {}    ## hex string -> true
var _memo: Dictionary = {}     ## hex string -> Color


func size() -> int:
	return _colours.size()


func load_palette(path: String) -> PackedStringArray:
	var errs: PackedStringArray = PackedStringArray()
	if not FileAccess.file_exists(path):
		errs.append("palette not found: %s" % path)
		return errs
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		errs.append("cannot open palette: %s" % path)
		return errs
	var text: String = f.get_as_text()
	f.close()

	var parser: JSON = JSON.new()
	if parser.parse(text) != OK:
		errs.append("palette is not valid JSON: %s at line %d" % [
			parser.get_error_message(), parser.get_error_line()])
		return errs
	var data: Variant = parser.data
	if typeof(data) != TYPE_DICTIONARY or not data.has("ramps"):
		errs.append("palette has no 'ramps' object")
		return errs

	# Ramp names sorted, so index assignment is stable regardless of how the
	# JSON parser orders keys. Two runs must produce identical output.
	var ramp_names: Array = data["ramps"].keys()
	ramp_names.sort()
	for ramp: String in ramp_names:
		for hexs: String in data["ramps"][ramp]:
			var c: Color = Color(hexs)
			_colours.append(c)
			_labs.append(_to_oklab(c))
			_ramp_by_index.append(ramp)
			_exact[c.to_html(false)] = true
	if _colours.is_empty():
		errs.append("palette contains no colours")
	return errs


## Exact membership. Distinct from nearest(): the gate asks whether a pixel
## is literally on the palette, not what it would round to.
func has_colour(c: Color) -> bool:
	return _exact.has(c.to_html(false))


func nearest(c: Color) -> Color:
	var key: String = c.to_html(false)
	if _memo.has(key):
		return _memo[key]
	var out: Color = _colours[_nearest_index(c)]
	_memo[key] = out
	return out


func ramp_of(c: Color) -> String:
	return _ramp_by_index[_nearest_index(c)]


func _nearest_index(c: Color) -> int:
	var target: Vector3 = _to_oklab(c)
	var best: int = 0
	var best_d: float = INF
	for i: int in range(_labs.size()):
		# Squared distance: monotonic in distance, and skips a sqrt per
		# comparison across 46 colours per distinct source colour.
		var d: float = (_labs[i] - target).length_squared()
		if d < best_d:
			best_d = d
			best = i
	return best


## sRGB -> OKLab. Björn Ottosson's matrices, unchanged.
##
## OKLab is perceptually uniform, so Euclidean distance in it corresponds
## to perceived difference. The cube roots are safe: linear components are
## never negative for a valid colour.
static func _to_oklab(c: Color) -> Vector3:
	var lin: Color = c.srgb_to_linear()
	var l: float = 0.4122214708 * lin.r + 0.5363325363 * lin.g + 0.0514459929 * lin.b
	var m: float = 0.2119034982 * lin.r + 0.6806995451 * lin.g + 0.1073969566 * lin.b
	var s: float = 0.0883024619 * lin.r + 0.2817188376 * lin.g + 0.6299787005 * lin.b
	var l_: float = pow(l, 1.0 / 3.0)
	var m_: float = pow(m, 1.0 / 3.0)
	var s_: float = pow(s, 1.0 / 3.0)
	return Vector3(
		0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_,
		1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_,
		0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_)
```

- [x] **Step 4: Run it and watch it pass**

```bash
./tools/run_tests.sh 2>&1 | tail -20
```

Expected: PASS. Totals: **20 scripts, 174 tests**.

- [x] **Step 5: Confirm the architecture guard still passes**

```bash
./tools/godot.sh --headless --path . -s tools/guard.gd
```

Expected: `Architecture guard: clean`. `tools/` is not a guarded root, but run it — a new `class_name` is exactly the kind of change that surprises a guard.

- [x] **Step 6: Commit**

```bash
git add tools/palette_map.gd tests/test_palette_map.gd
git commit -m "$(cat <<'EOF'
feat: map arbitrary colours onto Apollo in OKLab

Distance is Euclidean in OKLab rather than RGB. RGB distance picks
visibly wrong shades in dark greens and blues, which is where this game
spends its pixels -- a measured Elin meadow was 85% Green ramp.

nearest() is memoised by hex and has_colour() is exact membership: the
gate asks whether a pixel is literally on the palette, which is a
different question from what it would round to.

Ramp names are sorted at load so colour indices do not depend on JSON key
order. Committed art must not depend on dictionary iteration.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

- [x] **Step 7: Tick this task**

```bash
python3 tools/mark_task_done.py 3 --plan docs/superpowers/plans/2026-09-10-rp1-phase3c-art-pipeline.md
git add docs/superpowers/plans/2026-09-10-rp1-phase3c-art-pipeline.md
git commit -m "docs: tick Phase 3c task 3"
```

---

## Task 4: `PaletteMap` — the override table

`docs/palette.md` pulls two ways. §5 says pick the nearest step; §3 says "shade within a ramp; do not mix ramps to make a shade — that is what produces mud." Nearest-colour obeys §5 and can violate §3: a brown trunk's shadow may land in Neutral because that is where the nearest colour is.

The fix is a human escape hatch rather than a cleverer algorithm — a ramp-aware heuristic breaks on any multi-coloured sprite, and a tree is a brown trunk plus a green canopy.

**Files:**
- Modify: `tools/palette_map.gd`, `tests/test_palette_map.gd`
- Create: `tools/palette_overrides.json`

**Interfaces:**
- Produces: `func load_overrides(path: String) -> PackedStringArray`. Overrides take precedence over `nearest()`. File shape: `{"overrides": [{"from": "<hex>", "to": "<hex>", "why": "<reason>"}]}`.

- [x] **Step 1: Write the failing test**

Append to `tests/test_palette_map.gd`:

```gdscript
func test_an_override_beats_the_nearest_colour() -> void:
	# 33462a's nearest is 25562e (asserted above). An override must win.
	var path: String = "user://test_overrides.json"
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	f.store_string('{"overrides": [{"from": "33462a", "to": "19332d", "why": "test"}]}')
	f.close()

	var errs: PackedStringArray = _m.load_overrides(path)
	assert_eq(errs.size(), 0, "overrides load: %s" % ", ".join(errs))
	assert_eq(_m.nearest(Color("33462a")).to_html(false), "19332d",
		"the override wins over the nearest colour")
	assert_eq(_m.nearest(Color("808080")).to_html(false), "819796",
		"an unlisted colour is unaffected")


func test_an_override_to_a_non_palette_colour_is_rejected() -> void:
	# An override is a choice between palette steps, never a way to smuggle
	# a forty-seventh colour past the gate.
	var path: String = "user://bad_overrides.json"
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	f.store_string('{"overrides": [{"from": "33462a", "to": "ff00ff", "why": "test"}]}')
	f.close()

	var errs: PackedStringArray = _m.load_overrides(path)
	assert_gt(errs.size(), 0, "an off-palette target is an error")
	assert_eq(_m.nearest(Color("33462a")).to_html(false), "25562e",
		"the rejected override did not take effect")


func test_an_override_must_explain_itself() -> void:
	var path: String = "user://why_overrides.json"
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	f.store_string('{"overrides": [{"from": "33462a", "to": "19332d"}]}')
	f.close()

	var errs: PackedStringArray = _m.load_overrides(path)
	assert_gt(errs.size(), 0, "an override without a reason is an error")


func test_a_missing_override_file_is_not_an_error() -> void:
	# Overrides are optional. A pipeline with none is the healthy case.
	var m: PaletteMap = PaletteMap.new()
	var _e: PackedStringArray = m.load_palette(PALETTE)
	var errs: PackedStringArray = m.load_overrides("res://tools/nope.json")
	assert_eq(errs.size(), 0, "absent overrides are fine")
```

- [x] **Step 2: Run it and watch it fail**

```bash
./tools/run_tests.sh 2>&1 | tail -20
```

Expected: FAIL — `load_overrides` is not a method.

- [x] **Step 3: Implement overrides**

In `tools/palette_map.gd`, add the field beside `_memo`:

```gdscript
var _overrides: Dictionary = {}  ## source hex -> Color
```

Add the loader:

```gdscript
## Pins specific source colours to a chosen palette step.
##
## Nearest-colour honours palette.md section 5 and can violate section 3 by
## mixing ramps within one sprite, which is what produces mud. Rather than
## a ramp-aware heuristic -- which breaks on any multi-coloured sprite, and
## a tree is a trunk plus a canopy -- the mapping stays simple and a human
## pins the exceptions. Each one is a reviewable line with its reason
## attached, and survives re-quantization; hand-editing the output PNG
## instead would hide the decision in a binary and lose it on the next run.
##
## A missing file is not an error. Having no overrides is the healthy case.
func load_overrides(path: String) -> PackedStringArray:
	var errs: PackedStringArray = PackedStringArray()
	if not FileAccess.file_exists(path):
		return errs
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		errs.append("cannot open overrides: %s" % path)
		return errs
	var text: String = f.get_as_text()
	f.close()

	var parser: JSON = JSON.new()
	if parser.parse(text) != OK:
		errs.append("overrides are not valid JSON: %s at line %d" % [
			parser.get_error_message(), parser.get_error_line()])
		return errs
	var entries: Variant = parser.data.get("overrides", []) if typeof(parser.data) == TYPE_DICTIONARY else []

	for e: Variant in entries:
		if typeof(e) != TYPE_DICTIONARY:
			errs.append("override is not an object: %s" % str(e))
			continue
		var src: String = str(e.get("from", "")).to_lower()
		var dst: String = str(e.get("to", "")).to_lower()
		if src.is_empty() or dst.is_empty():
			errs.append("override needs 'from' and 'to': %s" % str(e))
			continue
		# The reason is required. An override with no explanation is
		# indistinguishable from a mistake six months later.
		if str(e.get("why", "")).strip_edges().is_empty():
			errs.append("override %s -> %s has no 'why'" % [src, dst])
			continue
		# An override chooses between palette steps. It is never a way to
		# smuggle a forty-seventh colour past the gate.
		if not _exact.has(dst):
			errs.append("override target #%s is not a palette colour" % dst)
			continue
		_overrides[src] = Color(dst)

	# Overrides change what nearest() returns, so anything already memoised
	# is stale.
	_memo.clear()
	return errs
```

Change `nearest()` to consult overrides first:

```gdscript
func nearest(c: Color) -> Color:
	var key: String = c.to_html(false)
	if _overrides.has(key):
		return _overrides[key]
	if _memo.has(key):
		return _memo[key]
	var out: Color = _colours[_nearest_index(c)]
	_memo[key] = out
	return out
```

- [x] **Step 4: Run it and watch it pass**

```bash
./tools/run_tests.sh 2>&1 | tail -20
```

Expected: PASS. Totals: **20 scripts, 178 tests**.

- [x] **Step 5: Create the (empty) override table**

`tools/palette_overrides.json`:

```json
{
  "_comment": "Source colour -> chosen Apollo step, for cases where nearest-colour crosses a ramp and produces mud. See docs/palette.md section 3. Every entry needs a 'why'; the loader rejects it otherwise. Populated in Task 9 from the mapping report, if the art needs it.",
  "overrides": []
}
```

Starting empty is deliberate. Overrides are added in Task 9 in response to a mapping report showing a real problem, never pre-emptively.

- [x] **Step 6: Commit**

```bash
git add tools/palette_map.gd tools/palette_overrides.json tests/test_palette_map.gd
git commit -m "$(cat <<'EOF'
feat: let a human pin a colour that nearest-match gets wrong

palette.md section 5 says pick the nearest step; section 3 says do not mix
ramps, because that produces mud. Nearest-colour can satisfy the first and
violate the second. A ramp-aware heuristic would break on any
multi-coloured sprite -- a tree is a trunk plus a canopy -- so the mapping
stays simple and exceptions are pinned by hand.

Three things are rejected: an override to a non-palette colour, which
would smuggle a 47th colour past the gate; one with no reason, which is
indistinguishable from a mistake later; and malformed entries. A missing
file is not an error, since having no overrides is the healthy case.

The table ships empty. Entries get added from a mapping report that shows
a real problem, not pre-emptively.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

- [x] **Step 7: Tick this task**

```bash
python3 tools/mark_task_done.py 4 --plan docs/superpowers/plans/2026-09-10-rp1-phase3c-art-pipeline.md
git add docs/superpowers/plans/2026-09-10-rp1-phase3c-art-pipeline.md
git commit -m "docs: tick Phase 3c task 4"
```

---

## Task 5: `PaletteMap` — quantize a whole image

**Files:**
- Modify: `tools/palette_map.gd`, `tests/test_palette_map.gd`

**Interfaces:**
- Produces:
  - `func quantize_image(img: Image) -> Image` — returns a new `FORMAT_RGBA8` image
  - `func last_report() -> Array[Dictionary]` — `[{from, to, ramp, count}]`, sorted by `count` descending

- [x] **Step 1: Write the failing test**

Append to `tests/test_palette_map.gd`:

```gdscript
func _solid(size: Vector2i, c: Color) -> Image:
	var img: Image = Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	img.fill(c)
	return img


func test_it_quantizes_every_pixel_onto_the_palette() -> void:
	var img: Image = _solid(Vector2i(4, 4), Color("33462a"))
	var out: Image = _m.quantize_image(img)
	assert_eq(out.get_size(), Vector2i(4, 4), "size is preserved")
	for y: int in range(4):
		for x: int in range(4):
			assert_eq(out.get_pixel(x, y).to_html(false), "25562e",
				"pixel %d,%d is on the palette" % [x, y])


func test_the_source_image_is_not_modified() -> void:
	var img: Image = _solid(Vector2i(2, 2), Color("33462a"))
	var _out: Image = _m.quantize_image(img)
	assert_eq(img.get_pixel(0, 0).to_html(false), "33462a",
		"quantize_image returns a new image and leaves its input alone")


func test_alpha_is_binarized() -> void:
	var img: Image = Image.create(4, 1, false, Image.FORMAT_RGBA8)
	img.set_pixel(0, 0, Color("33462a", 0.0))    # fully transparent
	img.set_pixel(1, 0, Color("33462a", 0.4))    # below the threshold
	img.set_pixel(2, 0, Color("33462a", 0.6))    # at or above it
	img.set_pixel(3, 0, Color("33462a", 1.0))    # fully opaque
	var out: Image = _m.quantize_image(img)
	assert_eq(out.get_pixel(0, 0).a8, 0, "transparent stays transparent")
	assert_eq(out.get_pixel(1, 0).a8, 0, "below threshold becomes transparent")
	assert_eq(out.get_pixel(2, 0).a8, 255, "at threshold becomes opaque")
	assert_eq(out.get_pixel(3, 0).a8, 255, "opaque stays opaque")


func test_transparent_pixels_are_not_colour_mapped() -> void:
	# A fully transparent pixel is invisible, so mapping its RGB would spend
	# a report entry on a colour nobody can see.
	var img: Image = Image.create(1, 1, false, Image.FORMAT_RGBA8)
	img.set_pixel(0, 0, Color("ff00ff", 0.0))
	var out: Image = _m.quantize_image(img)
	assert_eq(out.get_pixel(0, 0).a8, 0, "still transparent")
	assert_eq(_m.last_report().size(), 0, "no report entry for an invisible pixel")


func test_quantizing_is_idempotent() -> void:
	# Re-running the pipeline must not drift the committed assets.
	var img: Image = _solid(Vector2i(3, 3), Color("33462a"))
	var once: Image = _m.quantize_image(img)
	var twice: Image = _m.quantize_image(once)
	assert_eq(once.get_data(), twice.get_data(), "quantizing twice changes nothing")


func test_the_report_counts_pixels_per_source_colour() -> void:
	var img: Image = Image.create(3, 1, false, Image.FORMAT_RGBA8)
	img.set_pixel(0, 0, Color("33462a"))
	img.set_pixel(1, 0, Color("33462a"))
	img.set_pixel(2, 0, Color("808080"))
	var _out: Image = _m.quantize_image(img)
	var report: Array[Dictionary] = _m.last_report()
	assert_eq(report.size(), 2, "one entry per distinct source colour")
	# Sorted by count descending, so the biggest offender reads first.
	assert_eq(report[0]["from"], "33462a", "most common source colour first")
	assert_eq(report[0]["count"], 2, "counted twice")
	assert_eq(report[0]["to"], "25562e", "mapped target")
	assert_eq(report[0]["ramp"], "green", "target ramp")
	assert_eq(report[1]["from"], "808080", "the rarer colour second")
	assert_eq(report[1]["count"], 1, "counted once")
```

- [x] **Step 2: Run it and watch it fail**

```bash
./tools/run_tests.sh 2>&1 | tail -20
```

Expected: FAIL — `quantize_image` is not a method.

- [x] **Step 3: Implement it**

Add to `tools/palette_map.gd`:

```gdscript
var _report: Dictionary = {}  ## source hex -> count, for the last quantize
```

```gdscript
## Maps every visible pixel onto the palette and binarizes alpha.
##
## Colours are mapped through nearest(), which is memoised by hex, so the
## work is proportional to the number of DISTINCT colours rather than to
## the pixel count -- pixel art is flat, and a sheet has a few dozen
## colours against hundreds of thousands of pixels. It also guarantees
## that identical source colours map identically, so a flat region can
## never come out speckled.
##
## Returns a new image; the input is untouched.
func quantize_image(img: Image) -> Image:
	_report.clear()
	var w: int = img.get_width()
	var h: int = img.get_height()
	var out: Image = Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y: int in range(h):
		for x: int in range(w):
			var src: Color = img.get_pixel(x, y)
			# Under project-wide Nearest filtering partial alpha has no
			# meaning, and "alpha is 0 or 255, never between" is an
			# invariant the palette gate can actually check.
			if src.a8 < ALPHA_THRESHOLD:
				out.set_pixel(x, y, Color(0.0, 0.0, 0.0, 0.0))
				continue
			var opaque: Color = Color(src.r, src.g, src.b, 1.0)
			var key: String = opaque.to_html(false)
			_report[key] = int(_report.get(key, 0)) + 1
			out.set_pixel(x, y, nearest(opaque))
	return out


## What the last quantize_image() call did, biggest source colour first.
## This is how a mapping that crosses a ramp gets noticed -- see
## load_overrides().
func last_report() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for src: String in _report:
		var c: Color = Color(src)
		rows.append({
			"from": src,
			"to": nearest(c).to_html(false),
			"ramp": ramp_of(c),
			"count": _report[src],
		})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		# Count descending, then hex ascending so ties are deterministic
		# and two runs produce identical reports.
		if a["count"] != b["count"]:
			return a["count"] > b["count"]
		return a["from"] < b["from"])
	return rows
```

Note `ramp_of()` is called on the *source* colour, and returns the ramp of its nearest palette colour — which is the target's ramp, since `nearest()` and `ramp_of()` agree by construction. When an override is active, `ramp_of()` still reports the *unoverridden* nearest ramp; that is deliberate, because the report exists to show what the algorithm did.

- [x] **Step 4: Run it and watch it pass**

```bash
./tools/run_tests.sh 2>&1 | tail -20
```

Expected: PASS. Totals: **20 scripts, 184 tests**.

- [x] **Step 5: Commit**

```bash
git add tools/palette_map.gd tests/test_palette_map.gd
git commit -m "$(cat <<'EOF'
feat: quantize a whole image and report what it did

Maps through the memoised nearest(), so cost tracks the number of
distinct colours rather than the pixel count -- a sheet has a few dozen
colours and hundreds of thousands of pixels. More importantly it
guarantees identical source colours map identically, so a flat region can
never come out speckled.

Alpha is binarized at 128. Under project-wide Nearest filtering partial
alpha means nothing, and "0 or 255, never between" is an invariant the
gate can check. Transparent pixels are left uncoloured and kept out of the
report: mapping a pixel nobody can see would waste a line in it.

Quantizing is idempotent, so re-running the pipeline cannot drift the
committed assets.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

- [x] **Step 6: Tick this task**

```bash
python3 tools/mark_task_done.py 5 --plan docs/superpowers/plans/2026-09-10-rp1-phase3c-art-pipeline.md
git add docs/superpowers/plans/2026-09-10-rp1-phase3c-art-pipeline.md
git commit -m "docs: tick Phase 3c task 5"
```

---

## Task 6: The manifest and its consistency test

The manifest is the committed record of what came from where. It has one dangerous seam: a rect can be resized without updating the content JSON that declares the sprite's size, which renders a sprite wrong and nothing else would catch it.

**Files:**
- Create: `tools/import_manifest.json`, `tests/test_import_manifest.gd`

**Interfaces:**
- Produces: `tools/import_manifest.json`, shape `{"slices": [{"source": "<path under assets/_source/>", "rect": [x, y, w, h], "out": "<path from project root>"}]}`. Consumed by Tasks 7 and 8.

- [ ] **Step 1: Write the manifest**

Use the rects recorded in Task 1. Replace every value below with the real ones:

```json
{
  "_comment": "Which rect of which source sheet becomes which asset. Every PNG under assets/ (outside _source/) must appear here as an 'out' -- tools/check_palette.gd enforces it, so art cannot be added by hand. 'source' is relative to assets/_source/; 'out' is relative to the project root.",
  "slices": [
    {"source": "buch-outdoor/sheet.png", "rect": [0, 0, 32, 32], "out": "assets/tiles/grass.png"},
    {"source": "buch-outdoor/sheet.png", "rect": [0, 0, 32, 32], "out": "assets/tiles/water.png"},
    {"source": "buch-outdoor/sheet.png", "rect": [0, 0, 32, 48], "out": "assets/objects/oak_tree.png"},
    {"source": "bukket-characters/template_w.bmp", "rect": [0, 0, 32, 64], "out": "assets/characters/player.png"},
    {"source": "bukket-characters/template_c.bmp", "rect": [0, 0, 32, 64], "out": "assets/characters/rabbit.png"}
  ]
}
```

- [ ] **Step 2: Write the failing test**

Create `tests/test_import_manifest.gd`:

```gdscript
extends GutTest
## Pins tools/import_manifest.json to data/*.json.
##
## This is the one seam Phase 3c creates where two committed files can
## silently disagree: a rect resized without updating the sprite_rect its
## content definition declares renders the sprite at the wrong size, and
## no other test would notice.

const MANIFEST: String = "res://tools/import_manifest.json"

var _slices: Array = []
var _registry: ContentRegistry


func before_each() -> void:
	_registry = ContentRegistry.new()
	var errs: PackedStringArray = _registry.load_from_dir("res://data")
	assert_eq(errs.size(), 0, "shipped content validates: %s" % ", ".join(errs))

	var f: FileAccess = FileAccess.open(MANIFEST, FileAccess.READ)
	assert_not_null(f, "the manifest is readable")
	if f == null:
		return
	var parser: JSON = JSON.new()
	var err: int = parser.parse(f.get_as_text())
	f.close()
	assert_eq(err, OK, "the manifest parses")
	_slices = parser.data.get("slices", []) if err == OK else []


func test_the_manifest_is_not_empty() -> void:
	assert_gt(_slices.size(), 0, "at least one slice is declared")


func test_every_slice_names_a_readable_source() -> void:
	for s: Dictionary in _slices:
		var path: String = "res://assets/_source/%s" % str(s["source"])
		assert_true(FileAccess.file_exists(path), "source exists: %s" % path)


func test_every_rect_is_positive() -> void:
	for s: Dictionary in _slices:
		var r: Array = s["rect"]
		assert_eq(r.size(), 4, "%s rect is [x, y, w, h]" % str(s["out"]))
		assert_gt(int(r[2]), 0, "%s width is positive" % str(s["out"]))
		assert_gt(int(r[3]), 0, "%s height is positive" % str(s["out"]))


func test_every_output_is_claimed_by_exactly_one_slice() -> void:
	var seen: Dictionary = {}
	for s: Dictionary in _slices:
		var out: String = str(s["out"])
		assert_false(seen.has(out), "%s is produced by only one slice" % out)
		seen[out] = true


func test_every_output_is_referenced_by_a_content_definition() -> void:
	# An asset nothing draws is dead weight, and more likely a typo in a
	# sprite path than a deliberate spare.
	var sprites: Dictionary = {}
	for sid: String in _registry.all_string_ids():
		var def: Dictionary = _registry.def_of(_registry.numeric_of(sid))
		var sprite: String = str(def.get("sprite", ""))
		if not sprite.is_empty():
			sprites[sprite] = sid
	for s: Dictionary in _slices:
		var res_path: String = "res://%s" % str(s["out"])
		assert_true(sprites.has(res_path),
			"%s is named by a content definition" % res_path)


func test_every_content_sprite_is_produced_by_the_manifest() -> void:
	# The other direction: a definition pointing at art the pipeline does
	# not generate is how a dangling sprite reference survives, which is
	# the bug rabbit.json had before Phase 3b.
	var outs: Dictionary = {}
	for s: Dictionary in _slices:
		outs["res://%s" % str(s["out"])] = true
	for sid: String in _registry.all_string_ids():
		var def: Dictionary = _registry.def_of(_registry.numeric_of(sid))
		var sprite: String = str(def.get("sprite", ""))
		if sprite.is_empty():
			continue
		assert_true(outs.has(sprite), "%s (%s) is produced by the manifest" % [sprite, sid])


func test_declared_sprite_rects_match_the_slice_sizes() -> void:
	# The seam this whole file exists for.
	var by_out: Dictionary = {}
	for s: Dictionary in _slices:
		by_out["res://%s" % str(s["out"])] = s
	for sid: String in _registry.all_string_ids():
		var def: Dictionary = _registry.def_of(_registry.numeric_of(sid))
		var sprite: String = str(def.get("sprite", ""))
		if not def.has("sprite_rect") or not by_out.has(sprite):
			continue
		var declared: Array = def["sprite_rect"]
		var slice_rect: Array = by_out[sprite]["rect"]
		assert_eq(int(declared[2]), int(slice_rect[2]),
			"%s: sprite_rect width matches the slice" % sid)
		assert_eq(int(declared[3]), int(slice_rect[3]),
			"%s: sprite_rect height matches the slice" % sid)
```

- [ ] **Step 3: Run it and watch it fail, then pass**

```bash
./tools/run_tests.sh 2>&1 | tail -25
```

If `test_declared_sprite_rects_match_the_slice_sizes` fails, the tree in Buch's sheet is not 32×48. **Fix `data/object/oak_tree.json`'s `sprite_rect` to match the real art**, not the manifest to match the JSON — the art is the fact here.

Expected once consistent: PASS. Totals: **21 scripts, 191 tests**.

- [ ] **Step 4: Commit**

```bash
git add tools/import_manifest.json tests/test_import_manifest.gd data/object/oak_tree.json
git commit -m "$(cat <<'EOF'
feat: record what came from where, and test that it agrees

The manifest is the committed record of which rect of which source sheet
becomes which asset, which is what makes the import reproducible.

It creates one seam where two committed files can silently disagree: a
rect resized without updating the sprite_rect its content definition
declares renders the sprite wrong and nothing else would catch it. The
test pins both directions -- every output is drawn by a definition, and
every definition's sprite is produced by the manifest. The second
direction is the dangling-sprite bug rabbit.json had before Phase 3b.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

- [ ] **Step 5: Tick this task**

```bash
python3 tools/mark_task_done.py 6 --plan docs/superpowers/plans/2026-09-10-rp1-phase3c-art-pipeline.md
git add docs/superpowers/plans/2026-09-10-rp1-phase3c-art-pipeline.md
git commit -m "docs: tick Phase 3c task 6"
```

---

## Task 7: `tools/quantize.gd`

A thin driver. All colour logic is in `PaletteMap`; all provenance is in the manifest. This file does file I/O and cropping.

**Files:**
- Create: `tools/quantize.gd`

- [ ] **Step 1: Write it**

```gdscript
extends SceneTree
## Derives assets/ from assets/_source/.
##
## Build-time only, never shipped. Run:
##   ./tools/godot.sh --headless --path . -s tools/quantize.gd
##
## For every slice in tools/import_manifest.json: crop the rect out of the
## source sheet, map it onto Apollo, binarize alpha, write the PNG. Then
## print a mapping report, which is how a colour that crossed a ramp gets
## noticed and pinned in tools/palette_overrides.json.
##
## Re-running is safe and produces byte-identical output: quantizing is
## idempotent and nothing here depends on iteration order.

const MANIFEST: String = "res://tools/import_manifest.json"
const PALETTE: String = "res://tools/palette/apollo.json"
const OVERRIDES: String = "res://tools/palette_overrides.json"
const SOURCE_ROOT: String = "res://assets/_source/"


func _init() -> void:
	var map: PaletteMap = PaletteMap.new()
	var errs: PackedStringArray = map.load_palette(PALETTE)
	errs.append_array(map.load_overrides(OVERRIDES))
	if not errs.is_empty():
		for e: String in errs:
			printerr("palette: %s" % e)
		quit(1)
		return

	var slices: Array = _read_slices()
	if slices.is_empty():
		printerr("no slices in %s" % MANIFEST)
		quit(1)
		return

	var totals: Dictionary = {}
	var written: int = 0
	for s: Dictionary in slices:
		if not _write_slice(map, s, totals):
			quit(1)
			return
		written += 1

	_print_report(map, totals)
	print("quantize: wrote %d asset(s) from %d source sheet(s)" % [
		written, _distinct_sources(slices)])
	quit(0)


func _read_slices() -> Array:
	if not FileAccess.file_exists(MANIFEST):
		printerr("manifest not found: %s" % MANIFEST)
		return []
	var f: FileAccess = FileAccess.open(MANIFEST, FileAccess.READ)
	if f == null:
		printerr("cannot open manifest: %s" % MANIFEST)
		return []
	var text: String = f.get_as_text()
	f.close()
	var parser: JSON = JSON.new()
	if parser.parse(text) != OK:
		printerr("manifest is not valid JSON: %s at line %d" % [
			parser.get_error_message(), parser.get_error_line()])
		return []
	return parser.data.get("slices", [])


func _write_slice(map: PaletteMap, s: Dictionary, totals: Dictionary) -> bool:
	var src_path: String = SOURCE_ROOT + str(s["source"])
	# Image.load_from_file rather than load(): assets/_source/ carries a
	# .gdignore, so the engine never imported these files and
	# ResourceLoader cannot see them. That is deliberate -- it keeps the
	# sources out of the exported PCK. The engine warns that this "will not
	# work on export", which is correct and irrelevant: this script only
	# ever runs under -s at build time.
	var sheet: Image = Image.load_from_file(src_path)
	if sheet == null:
		printerr("cannot read source: %s" % src_path)
		return false

	var r: Array = s["rect"]
	var rect: Rect2i = Rect2i(int(r[0]), int(r[1]), int(r[2]), int(r[3]))
	if not Rect2i(Vector2i.ZERO, sheet.get_size()).encloses(rect):
		printerr("%s: rect %s is outside %s (%dx%d)" % [
			str(s["out"]), str(rect), src_path, sheet.get_width(), sheet.get_height()])
		return false

	var cropped: Image = sheet.get_region(rect)
	var quantized: Image = map.quantize_image(cropped)

	for row: Dictionary in map.last_report():
		var key: String = str(row["from"])
		if not totals.has(key):
			totals[key] = {"to": row["to"], "ramp": row["ramp"], "count": 0}
		totals[key]["count"] = int(totals[key]["count"]) + int(row["count"])

	var out_path: String = "res://%s" % str(s["out"])
	DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
	var err: int = quantized.save_png(out_path)
	if err != OK:
		printerr("cannot write %s: %d" % [out_path, err])
		return false
	print("  %s  %dx%d  <- %s %s" % [
		str(s["out"]), rect.size.x, rect.size.y, str(s["source"]), str(r)])
	return true


func _distinct_sources(slices: Array) -> int:
	var seen: Dictionary = {}
	for s: Dictionary in slices:
		seen[str(s["source"])] = true
	return seen.size()


## Every distinct source colour across every slice, biggest first.
##
## This is the artifact a human reads. A row whose ramp looks wrong for the
## thing being drawn -- a trunk shadow in Neutral, say -- is a candidate
## for tools/palette_overrides.json.
func _print_report(map: PaletteMap, totals: Dictionary) -> void:
	var rows: Array = []
	for src: String in totals:
		rows.append({
			"from": src,
			"to": totals[src]["to"],
			"ramp": totals[src]["ramp"],
			"count": totals[src]["count"],
		})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["count"] != b["count"]:
			return a["count"] > b["count"]
		return a["from"] < b["from"])

	var total: int = 0
	for row: Dictionary in rows:
		total += int(row["count"])
	print("")
	print("mapping report -- %d distinct source colours, %d visible pixels" % [
		rows.size(), total])
	print("  %-9s %-9s %-8s %8s  %s" % ["source", "apollo", "ramp", "pixels", "share"])
	for row: Dictionary in rows:
		print("  #%-8s #%-8s %-8s %8d  %5.2f%%" % [
			row["from"], row["to"], row["ramp"], row["count"],
			100.0 * float(row["count"]) / float(total)])
	print("")
```

- [ ] **Step 2: Run it**

```bash
./tools/godot.sh --headless --path . -s tools/quantize.gd
```

Expected: one line per asset, then the mapping report, then `quantize: wrote 5 asset(s) from 2 source sheet(s)`.

- [ ] **Step 3: Verify it is reproducible**

```bash
md5 assets/tiles/grass.png assets/objects/oak_tree.png assets/characters/player.png
./tools/godot.sh --headless --path . -s tools/quantize.gd >/dev/null
md5 assets/tiles/grass.png assets/objects/oak_tree.png assets/characters/player.png
```

Expected: identical hashes both times. If they differ, something depends on iteration order — fix that before continuing, because it would make every future diff noise. (On Linux use `md5sum`.)

- [ ] **Step 4: Commit the tool only**

The regenerated art is committed in Task 9, after the report has been read and overrides decided.

```bash
git add tools/quantize.gd
git commit -m "$(cat <<'EOF'
feat: derive assets/ from assets/_source/

Crops each manifest rect out of its source sheet, maps it onto Apollo,
binarizes alpha and writes the PNG. All colour logic is in PaletteMap and
all provenance is in the manifest; this file is I/O and cropping.

Slices rather than committing the sheet as an atlas. That keeps every
content definition owning its whole PNG, so TilesetBuilder and
EntityRenderer need no change and Stage 1 acceptance criterion 8 --
"adding a new tree type = one JSON file + one PNG, no code change" --
stays literally true.

Uses Image.load_from_file, not load(): assets/_source/ is .gdignore'd so
ResourceLoader cannot see it, which is what keeps the sources out of the
PCK. The engine's "will not work on export" warning is correct and
irrelevant for a build-time script.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

- [ ] **Step 5: Tick this task**

```bash
python3 tools/mark_task_done.py 7 --plan docs/superpowers/plans/2026-09-10-rp1-phase3c-art-pipeline.md
git add docs/superpowers/plans/2026-09-10-rp1-phase3c-art-pipeline.md
git commit -m "docs: tick Phase 3c task 7"
```

---

## Task 8: CI gate 6 — the palette check

**Files:**
- Create: `tools/check_palette.gd`, `tools/check_palette.sh`

- [ ] **Step 1: Write the checker**

`tools/check_palette.gd`:

```gdscript
extends SceneTree
## CI gate 6: every pixel in assets/ is an Apollo colour.
##
## docs/palette.md section 1 states the rule and admits it was "honoured by
## hand" until this existed. A palette that governs only the art we happen
## to remember to check is a style guide, not a constraint.
##
## There is deliberately NO exemption mechanism. The Phase 3a and 3b debug
## swatches were the only exempt files and Phase 3c deletes them; a general
## exemption list is how the rule decays back into a suggestion.

const PALETTE: String = "res://tools/palette/apollo.json"
const MANIFEST: String = "res://tools/import_manifest.json"
const ASSET_ROOT: String = "res://assets"
const SOURCE_DIR: String = "res://assets/_source"

## Offending pixels reported per file before truncating. A wholly
## off-palette image would otherwise print a million lines.
const MAX_REPORTED: int = 8

var _failures: int = 0


func _init() -> void:
	var map: PaletteMap = PaletteMap.new()
	var errs: PackedStringArray = map.load_palette(PALETTE)
	if not errs.is_empty():
		for e: String in errs:
			printerr("palette: %s" % e)
		quit(2)
		return

	var declared: Dictionary = _manifest_outputs()
	var pngs: PackedStringArray = PackedStringArray()
	_collect(ASSET_ROOT, pngs)
	pngs.sort()

	for path: String in pngs:
		_check_declared(path, declared)
		_check_pixels(path, map)

	if _failures > 0:
		printerr("")
		printerr("Palette gate: %d problem(s). Every pixel in assets/ must be one of" % _failures)
		printerr("the 46 Apollo colours in docs/palette.md, with alpha 0 or 255.")
		printerr("Fix by re-running the pipeline, not by editing a PNG:")
		printerr("  ./tools/godot.sh --headless --path . -s tools/quantize.gd")
		printerr("If a colour is landing in the wrong ramp, pin it in")
		printerr("tools/palette_overrides.json and re-run.")
		quit(1)
		return
	print("Palette: OK (%d file(s))" % pngs.size())
	quit(0)


func _manifest_outputs() -> Dictionary:
	var out: Dictionary = {}
	if not FileAccess.file_exists(MANIFEST):
		return out
	var f: FileAccess = FileAccess.open(MANIFEST, FileAccess.READ)
	if f == null:
		return out
	var parser: JSON = JSON.new()
	var err: int = parser.parse(f.get_as_text())
	f.close()
	if err != OK:
		return out
	for s: Variant in parser.data.get("slices", []):
		out["res://%s" % str(s["out"])] = true
	return out


func _collect(dir_path: String, into: PackedStringArray) -> void:
	# assets/_source/ holds art as downloaded. It is off-palette by
	# definition -- re-quantizing it is the whole point of the pipeline.
	if dir_path == SOURCE_DIR:
		return
	var d: DirAccess = DirAccess.open(dir_path)
	if d == null:
		return
	d.list_dir_begin()
	var name: String = d.get_next()
	while name != "":
		if name.begins_with("."):
			name = d.get_next()
			continue
		var full: String = "%s/%s" % [dir_path, name]
		if d.current_is_dir():
			_collect(full, into)
		elif name.get_extension().to_lower() == "png":
			into.append(full)
		name = d.get_next()
	d.list_dir_end()


## Art must be reproducible, not merely on-palette. A hand-made PNG dropped
## into assets/ could pass the pixel check and still be underivable.
func _check_declared(path: String, declared: Dictionary) -> void:
	if declared.is_empty():
		return
	if not declared.has(path):
		printerr("%s: not produced by tools/import_manifest.json" % path)
		_failures += 1


func _check_pixels(path: String, map: PaletteMap) -> void:
	var img: Image = Image.load_from_file(path)
	if img == null:
		printerr("%s: cannot be read as an image" % path)
		_failures += 1
		return
	var bad_colour: int = 0
	var bad_alpha: int = 0
	for y: int in range(img.get_height()):
		for x: int in range(img.get_width()):
			var c: Color = img.get_pixel(x, y)
			if c.a8 != 0 and c.a8 != 255:
				bad_alpha += 1
				if bad_alpha <= MAX_REPORTED:
					printerr("%s: (%d,%d) alpha %d is neither 0 nor 255" % [path, x, y, c.a8])
				continue
			if c.a8 == 0:
				continue
			if not map.has_colour(Color(c.r, c.g, c.b, 1.0)):
				bad_colour += 1
				if bad_colour <= MAX_REPORTED:
					printerr("%s: (%d,%d) #%s is not an Apollo colour (nearest #%s)" % [
						path, x, y, Color(c.r, c.g, c.b, 1.0).to_html(false),
						map.nearest(Color(c.r, c.g, c.b, 1.0)).to_html(false)])
	if bad_colour > MAX_REPORTED:
		printerr("%s: ... and %d more off-palette pixel(s)" % [path, bad_colour - MAX_REPORTED])
	if bad_alpha > MAX_REPORTED:
		printerr("%s: ... and %d more partial-alpha pixel(s)" % [path, bad_alpha - MAX_REPORTED])
	if bad_colour > 0 or bad_alpha > 0:
		_failures += 1
```

- [ ] **Step 2: Write the shell entry point**

`tools/check_palette.sh`:

```bash
#!/usr/bin/env bash
# CI gate 6. docs/palette.md section 1 names this file; the pixel walk is in
# tools/check_palette.gd because bash cannot read PNGs.
set -euo pipefail
cd "$(dirname "$0")/.."

[[ -d assets ]] || { echo "No assets/ directory yet; nothing to check."; exit 0; }

exec ./tools/godot.sh --headless --path . -s tools/check_palette.gd
```

```bash
chmod +x tools/check_palette.sh
```

- [ ] **Step 3: Watch each rule fail**

Do not skip this. A gate nobody has seen fail is a gate nobody knows works.

```bash
# Rule 1: an off-palette colour.
cp assets/tiles/grass.png /tmp/grass.bak
python3 - <<'EOF'
from PIL import Image
im = Image.open("assets/tiles/grass.png").convert("RGBA")
im.putpixel((0, 0), (255, 0, 255, 255))
im.save("assets/tiles/grass.png")
EOF
./tools/check_palette.sh; echo "exit=$? (expect 1, naming (0,0) and #ff00ff)"
cp /tmp/grass.bak assets/tiles/grass.png

# Rule 2: partial alpha.
python3 - <<'EOF'
from PIL import Image
im = Image.open("assets/tiles/grass.png").convert("RGBA")
r, g, b, _ = im.getpixel((1, 1))
im.putpixel((1, 1), (r, g, b, 128))
im.save("assets/tiles/grass.png")
EOF
./tools/check_palette.sh; echo "exit=$? (expect 1, naming alpha 128)"
cp /tmp/grass.bak assets/tiles/grass.png

# Rule 3: an undeclared PNG.
cp assets/tiles/grass.png assets/tiles/sneaky.png
./tools/check_palette.sh; echo "exit=$? (expect 1, 'not produced by tools/import_manifest.json')"
rm assets/tiles/sneaky.png

# And green again.
./tools/check_palette.sh; echo "exit=$? (expect 0)"
```

If the PIL edits are unavailable, make the same three changes with any image editor — the point is seeing each message.

- [ ] **Step 4: Commit**

```bash
git add tools/check_palette.gd tools/check_palette.sh
git commit -m "$(cat <<'EOF'
ci: fail the build on an off-palette pixel

docs/palette.md section 1 has named tools/check_palette.sh since it was
written and admitted the rule was "honoured by hand" until it existed.
The pixel walk is in GDScript because bash cannot read PNGs; the shell
file keeps the name the documentation already promises.

Three rules: an off-palette colour, an alpha that is neither 0 nor 255,
and a PNG the manifest does not produce. The third is what stops the gate
being bypassed by hand-making a PNG that happens to be on-palette but
cannot be re-derived.

No exemption mechanism, deliberately. The debug swatches were the only
exempt files and this phase deletes them; a general exemption list is how
the rule decays back into a suggestion.

Each rule was seen to fail before being trusted.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

- [ ] **Step 5: Tick this task**

```bash
python3 tools/mark_task_done.py 8 --plan docs/superpowers/plans/2026-09-10-rp1-phase3c-art-pipeline.md
git add docs/superpowers/plans/2026-09-10-rp1-phase3c-art-pipeline.md
git commit -m "docs: tick Phase 3c task 8"
```

---

## Task 9: Generate the real art and read the report

The first task with an aesthetic judgement in it. Everything so far was mechanical.

**Files:**
- Modify: `assets/tiles/*.png`, `assets/objects/*.png`, `assets/characters/*.png`, possibly `tools/palette_overrides.json`

- [ ] **Step 1: Run the pipeline and capture the report**

```bash
./tools/godot.sh --headless --path . -s tools/quantize.gd | tee /tmp/mapping-report.txt
```

- [ ] **Step 2: Read the report against `palette.md` §3**

For each row, ask whether the ramp is right for the thing being drawn. `palette.md` §4 gives the intended assignments:

| Subject | Base | Shadow | Highlight |
|---|---|---|---|
| Grass | `#75a743` | `#468232` | `#a8ca58` |
| Water surface | `#4f8fba` | `#3c5e8b` | `#73bed3` |
| Oak trunk | `#7a4841` | `#4d2b32` | `#ad7757` |
| Oak canopy | `#468232` | `#25562e` | `#75a743` |

A trunk colour landing in `neutral` or `red`, or a canopy colour landing in `gold`, is the mud `palette.md` §3 warns about. A trunk landing in `tan` is correct.

- [ ] **Step 3: Add overrides only for rows that are actually wrong**

For each, add an entry to `tools/palette_overrides.json`:

```json
{
  "overrides": [
    {"from": "6d471e", "to": "7a4841",
     "why": "oak trunk mid-tone landed in the Gold ramp; palette.md section 4 puts trunks in Tan"}
  ]
}
```

Then re-run and re-read:

```bash
./tools/godot.sh --headless --path . -s tools/quantize.gd | tee /tmp/mapping-report.txt
```

If no row is wrong, leave the table empty and say so in the commit message. An empty override table is a good result, not a missing step.

- [ ] **Step 4: Look at the art**

```bash
./tools/godot.sh --path .
```

Walk around. The zone still uses the Phase 3b debug generator, so expect a grass field with a pond and a lattice of trees. Confirm by eye: grass reads as grass, water as water, trees have a trunk and a canopy that are different colours, and the player is visible against the grass.

If a sprite looks wrong in a way no override fixes, the rect is wrong — go back to Task 1's grid overlays and correct the manifest.

- [ ] **Step 5: Run the palette gate**

```bash
./tools/check_palette.sh
```

Expected: `Palette: OK (5 file(s))`.

- [ ] **Step 6: Commit the art**

```bash
git add assets/tiles/ assets/objects/ assets/characters/ tools/palette_overrides.json
git commit -m "$(cat <<'EOF'
feat: replace the debug swatches with real quantized art

Generated by tools/quantize.gd from the committed sources. Every pixel is
one of the 46 Apollo colours and alpha is 0 or 255 throughout, so the
palette gate passes without exemptions for the first time.

[If overrides were needed, list each one and why here. If none were, say
so: the nearest-colour mapping put every source colour in the ramp
palette.md section 4 intends.]

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

- [ ] **Step 7: Tick this task**

```bash
python3 tools/mark_task_done.py 9 --plan docs/superpowers/plans/2026-09-10-rp1-phase3c-art-pipeline.md
git add docs/superpowers/plans/2026-09-10-rp1-phase3c-art-pipeline.md
git commit -m "docs: tick Phase 3c task 9"
```

---

## Task 10: Delete the placeholders and update the documentation

**Files:**
- Delete: `tools/make_placeholder_art.gd`, `tools/make_placeholder_art.gd.uid`
- Modify: `docs/palette.md`, `assets/CREDITS.md`, `assets/*/LICENSE.txt`, `docs/rp1-game-dev-plan.md`, `docs/superpowers/specs/2026-08-23-rp1-stage0-stage1-design.md`

- [ ] **Step 1: Delete the placeholder generator**

```bash
git rm tools/make_placeholder_art.gd tools/make_placeholder_art.gd.uid
```

- [ ] **Step 2: Update `docs/palette.md`**

Four edits:

1. §1's enforcement table — both rows change from `Phase 3c` to `**Done.**`, the `tools/check_palette.sh` row's "CI gate 6" becomes "**CI gate 5**" (see the numbering note in this plan's header), and the sentence "Until those exist, the rule is honoured by hand." is deleted.
2. The whole `### Exemption: the Phase 3a and 3b debug swatches` subsection is deleted. Not amended — deleted. There are no exemptions.
3. §4's assignment table — check each row against the mapping report and correct any that the real art contradicts. These were written before any art existed.
4. §6's open items — tick items 2 and 3, and replace item 1 with the measured result:

```markdown
- [ ] **Validate against Elin.** Partially done. One screenshot (a sunny
      meadow at midday) was measured during the Phase 3c design:

      | Measure | Result |
      |---|---|
      | Mean OKLab error to nearest Apollo colour | 0.056 |
      | Median / p90 | 0.055 / 0.074 |
      | Mean gap between adjacent steps within a ramp | 0.109 |
      | Ramp usage by pixel share | green 85.1%, neutral 6.5%, tan 4.6%, gold 3.5%, blue 0.0% |
      | Chroma change after quantization | **+37.1%** |
      | Lightness change | +0.6% |

      Error at roughly half a ramp step is a good result. The chroma figure
      is not: Apollo renders the scene 37% more saturated, which
      contradicts section 2's reason for choosing it. Blue and Purple --
      12 of 46 colours -- do essentially nothing outdoors.

      **Not acted on, for two reasons.** The method measures the wrong
      surface: Elin's on-screen colour is base sprites multiplied by
      real-time lighting, so the olive cast is partly shadow rather than
      pigment, and its underlying art is very likely more saturated than
      measured. RP1 has no lighting in Stage 1, so flatter, more saturated
      base art may be the correct compensation. And the sample is one
      screenshot of the 8-12 this item asks for, of the most
      saturated-green scene the game has.

      Remaining work: 7-11 more screenshots across biomes and times of day.
      **Reference images are never committed** -- section 7 forbids copying
      Elin art into this project. Measure, record the numbers here, delete
      the image. See docs/reference/README.md.
```

- [ ] **Step 3: Update `assets/CREDITS.md`**

Replace the three placeholder rows and the note above them:

```markdown
## Packs

| Pack | Author | Source | Licence |
|---|---|---|---|
| Outdoor 32x32 tileset | Buch | <https://opengameart.org/content/outdoor-32x32-tileset> | CC0 |
| Top-Down RPG Character Sprites | Bukket Games | <https://opengameart.org/content/top-down-rpg-character-sprites> | CC-BY 3.0 |

**The Bukket Games entry is a licence condition, not a courtesy.** CC-BY
requires attribution wherever the work is distributed, which includes any
exported build's credits. Every other asset here is CC0 and would survive
this file being deleted; that one would not.

All imported art is re-quantized onto the Apollo palette at import time by
`tools/quantize.gd` and is therefore not pixel-identical to the packs as
published. The unmodified originals are in `assets/_source/`.
```

- [ ] **Step 4: Update the three `assets/*/LICENSE.txt` files**

Each of `assets/tiles/`, `assets/objects/` and `assets/characters/` currently describes project-generated placeholders. Replace with the real provenance — for example `assets/characters/LICENSE.txt`:

```
Derived art. Do not edit these PNGs by hand.

Source:  assets/_source/bukket-characters/  (Bukket Games, CC-BY 3.0)
         https://opengameart.org/content/top-down-rpg-character-sprites
Derived: tools/quantize.gd, per tools/import_manifest.json
Licence: CC-BY 3.0, inherited from the source. ATTRIBUTION REQUIRED --
         see assets/CREDITS.md.

Re-quantized onto the Apollo palette (docs/palette.md), so these differ in
colour from the pack as published. Regenerate with:
  ./tools/godot.sh --headless --path . -s tools/quantize.gd
```

Write the equivalent for `assets/tiles/` and `assets/objects/`, both sourced from `assets/_source/buch-outdoor/` under CC0 with attribution requested but not required.

- [ ] **Step 5: Correct the stale Kenney references**

Kenney is not used — every top-down Kenney pixel pack is 16×16 and this project is 32×32. Leaving the references is how the next session gets misled.

- `docs/rp1-game-dev-plan.md:344` — "Kenney tileset imported" → the real packs
- `docs/rp1-game-dev-plan.md:460` — the risk row's "Start with Kenney only"
- `docs/rp1-game-dev-plan.md:471` — "Download Kenney's Roguelike/RPG pack and Tiny Town"
- `docs/superpowers/specs/2026-08-23-rp1-stage0-stage1-design.md:460` — the Phase 3c bullet
- `docs/superpowers/specs/2026-08-23-rp1-stage0-stage1-design.md:521` — the risk row

Add a one-line note at line 226 of the dev plan, where Kenney is recommended at length, rather than deleting the section: the reasoning there is sound and the size mismatch is the specific thing that ruled it out.

- [ ] **Step 6: Confirm nothing still references the deleted generator**

```bash
grep -rn "make_placeholder_art\|debug swatch\|placeholder swatch" --include="*.gd" --include="*.md" --include="*.json" --include="*.yml" . | grep -v "docs/superpowers/plans/" | grep -v "docs/superpowers/specs/"
```

Expected: no output. Plans and specs are historical records and keep their original wording.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "$(cat <<'EOF'
docs: retire the placeholder art and its exemption

The swatches are gone, so docs/palette.md loses the exemption section
rather than having it amended -- there are now no exemptions, which is the
point of the gate.

Records the partial Elin validation in section 6: quantization error is
about half a ramp step, but Apollo renders the reference 37% more
saturated, contradicting section 2's rationale. Not acted on, because the
method measures lit output rather than base art and the sample is one
midday meadow. The remaining work and the rule that reference images are
never committed are written down there.

Corrects the Kenney references across the dev plan and the Stage 0/1
spec. Every Kenney top-down pixel pack is 16x16 and this project is
32x32; leaving the references is how the next session gets misled.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

- [ ] **Step 8: Tick this task**

```bash
python3 tools/mark_task_done.py 10 --plan docs/superpowers/plans/2026-09-10-rp1-phase3c-art-pipeline.md
git add docs/superpowers/plans/2026-09-10-rp1-phase3c-art-pipeline.md
git commit -m "docs: tick Phase 3c task 10"
```

---

## Task 11: Wire gate 6 into CI and run every gate

**Files:**
- Modify: `.github/workflows/ci.yml`

- [ ] **Step 1: Add the gate**

In `.github/workflows/ci.yml`, after the `# Gate 4` asset-licences step in the `verify` job:

```yaml
      # Gate 5
      - name: Palette
        run: ./tools/check_palette.sh
```

The export job's verification step is currently commented `# Gate 5`. Renumber it to `# Gate 6`, so numbering follows execution order. Task 10 already corrected `docs/palette.md` to say gate 5; if it did not, do it now — a gate number that lies is worse than the edit.

- [ ] **Step 2: Verify the exported build still ships its textures**

The export gate greps for `RP1 rendered <N> cells`, which is the assertion that textures reached the PCK. `assets/_source/` is `.gdignore`'d, so it must not appear in the export — but the derived art must.

```bash
./tools/godot.sh --headless --path . --import
mkdir -p build/linux
./tools/godot.sh --headless --path . --export-release "Linux" build/linux/rp1.x86_64
ls -la build/linux/
```

Then confirm the sources are absent and the assets are present:

```bash
strings build/linux/rp1.x86_64 build/linux/*.pck 2>/dev/null | grep -c "assets/_source" || true
```

Expected: `0`. If it is not zero, `.gdignore` is not doing its job and the sources are shipping to users.

- [ ] **Step 3: Run every gate**

```bash
./tools/run_tests.sh
./tools/godot.sh --headless --path . -s tools/guard.gd
./tools/godot.sh --headless --path . -s tools/smoke.gd
./tools/check_asset_licences.sh
./tools/check_palette.sh
```

Expected: all five green. Test totals: **21 scripts, 191 tests**.

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "$(cat <<'EOF'
ci: add the palette gate

Gate 5 in the verify job; the export verification renumbers to gate 6 so
the numbering follows execution order and matches docs/palette.md.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

- [ ] **Step 5: Tick this task**

```bash
python3 tools/mark_task_done.py 11 --plan docs/superpowers/plans/2026-09-10-rp1-phase3c-art-pipeline.md
git add docs/superpowers/plans/2026-09-10-rp1-phase3c-art-pipeline.md
git commit -m "docs: tick Phase 3c task 11"
```

---

## Task 12 (optional): `tools/palette_report.gd`

Only worth doing if it stays under about 40 lines. `docs/palette.md` §6 still needs 7–11 more screenshots measured, and doing that with throwaway scripts each time invites inconsistent numbers.

**Files:**
- Create: `tools/palette_report.gd`

- [ ] **Step 1: Write it**

```gdscript
extends SceneTree
## Measures any image against Apollo. For docs/palette.md section 6.
##
##   ./tools/godot.sh --headless --path . -s tools/palette_report.gd -- <path>
##
## Reference images are NOT committed (section 7 forbids copying Elin art
## into this project). Point this at one in docs/reference/, record the
## numbers in section 6, delete the image.

const PALETTE: String = "res://tools/palette/apollo.json"


func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.is_empty():
		printerr("usage: -s tools/palette_report.gd -- <image path>")
		quit(2)
		return
	var img: Image = Image.load_from_file(args[0])
	if img == null:
		printerr("cannot read %s" % args[0])
		quit(2)
		return

	var map: PaletteMap = PaletteMap.new()
	var errs: PackedStringArray = map.load_palette(PALETTE)
	if not errs.is_empty():
		printerr("palette: %s" % ", ".join(errs))
		quit(2)
		return

	var _q: Image = map.quantize_image(img)
	var rows: Array[Dictionary] = map.last_report()
	var total: int = 0
	var ramps: Dictionary = {}
	for r: Dictionary in rows:
		total += int(r["count"])
		ramps[r["ramp"]] = int(ramps.get(r["ramp"], 0)) + int(r["count"])

	print("%s  %dx%d  %d distinct colours" % [
		args[0], img.get_width(), img.get_height(), rows.size()])
	print("ramp usage by pixel share:")
	var names: Array = ramps.keys()
	names.sort()
	for n: String in names:
		print("  %-8s %5.1f%%" % [n, 100.0 * float(ramps[n]) / float(total)])
	quit(0)
```

- [ ] **Step 2: Run it against a reference image**

```bash
./tools/godot.sh --headless --path . -s tools/palette_report.gd -- docs/reference/elin1.png
```

Expected: green around 85%, blue near 0% — matching the numbers already in `palette.md` §6, which is the check that this tool agrees with the design-time measurement.

- [ ] **Step 3: Commit**

```bash
git add tools/palette_report.gd
git commit -m "$(cat <<'EOF'
feat: measure any image against Apollo

docs/palette.md section 6 needs 7-11 more screenshots measured, and doing
that with a throwaway script each time invites numbers that cannot be
compared. Reuses PaletteMap so the tool and the pipeline cannot disagree.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

- [ ] **Step 4: Tick this task**

```bash
python3 tools/mark_task_done.py 12 --plan docs/superpowers/plans/2026-09-10-rp1-phase3c-art-pipeline.md
git add docs/superpowers/plans/2026-09-10-rp1-phase3c-art-pipeline.md
git commit -m "docs: tick Phase 3c task 12"
```

---

## Definition of done for Phase 3c

- [ ] `./tools/check_palette.sh` green, and **each of its three rules seen to fail**
- [ ] No PNG under `assets/` outside `_source/` has an off-palette pixel or partial alpha
- [ ] Re-running `tools/quantize.gd` produces byte-identical PNGs
- [ ] `./tools/run_tests.sh` green — **21 scripts, 191 tests**, up from 18 and 163
- [ ] The 163 pre-existing tests pass **unmodified** (the evidence that slicing avoided a renderer change)
- [ ] `tools/guard.gd`, `tools/smoke.gd`, `check_asset_licences.sh` still green
- [ ] The exported build contains no `assets/_source` path and still prints `RP1 rendered <N> cells`
- [ ] `tools/make_placeholder_art.gd` deleted; no non-historical file mentions it
- [ ] `docs/palette.md` has no exemption section, and §1's table shows both tools done
- [ ] `assets/CREDITS.md` names both packs, with Bukket marked licence-required
- [ ] All three `assets/*/LICENSE.txt` describe real provenance
- [ ] No stale Kenney reference outside `docs/superpowers/plans/` and `specs/`
- [ ] `CLAUDE.md` unchanged — character sprites are still 32×64
- [ ] Walked the zone and looked at it: grass, water and trees read correctly

**Not done in this phase, by design:** autotiling and transition tiles, walk-cycle animation (Bukket's frames are imported; nothing animates until Phase 6), the data-authored zone and `AnimalSystem` (Phase 4), save wiring (Phase 5), and the remaining §6 Elin screenshots, which need someone to run the game.
