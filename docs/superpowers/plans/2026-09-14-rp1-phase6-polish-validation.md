# Phase 6 — Polish and Validation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The first audio the project has ever had, a save indicator, a title
card and a controls hint, a volume slider and mute that survive a relaunch —
and an exported build proven to run on a machine that has never had Godot.

**Architecture:** All audio policy lives in `AudioDirector`, a node-free
`RefCounted` in `src/systems/`: footstep cadence, which sound the terrain
underfoot calls for, which variation, the ambient bed, master volume and mute.
It returns `AudioCue` values; `presentation/audio_stage.gd` drains them into
`AudioStreamPlayer`s and holds no rules at all. Sounds are a fourth content
category in `data/sound/`, so no `res://` path and no part of the mix lives in
code. Settings are a second, deliberately tiny persistence surface at the
`user://` root, separate from the world save.

**Tech Stack:** Godot 4.7.2 standard build, GDScript with static typing, GUT
for tests, Ogg Vorbis for audio.

**Spec:** `docs/superpowers/specs/2026-09-14-rp1-phase6-polish-validation-design.md`

## Global Constraints

Copied from `CLAUDE.md` and the spec. Every task's requirements implicitly
include this section.

- Godot **4.7.2**, standard build. **Not the Mono build.** Invoke Godot only
  through `./tools/godot.sh`. Never hardcode a binary path.
- GDScript only. Static typing everywhere: `var x: int = 0`,
  `func f(a: Vector2i) -> void:`.
- `src/core/` and `src/systems/` **MUST NOT reference Godot nodes.** No
  `extends Node`, no `get_tree()`, no `Engine.`, no `.tscn`, no `add_child(`,
  no `get_node(`, no `queue_free(`. These folders extend `RefCounted` only.
  Enforced by `tools/guard.gd`. An `AudioStream` is a `Resource`, not a node —
  but it still belongs in `src/presentation/`, because loading one is
  presentation.
- Run tests with `./tools/run_tests.sh` — never call `gut_cmdln.gd` directly.
  The runner does a mandatory `--import` pass first; without it GUT reports
  missing `class_name`s **and exits 0**, so a broken suite looks green.
- All game content lives in `data/*.json`. Never hardcode content in GDScript.
  **Never write `match` over content types** — look it up in `ContentRegistry`.
- New content types require a schema validation test.
- Never use `load()`, `ResourceLoader`, or `.tres`/`.res` for **save data**.
  Loading an authored `res://` asset is a different thing and is how
  `entity_renderer.gd` and `tileset_builder.gd` already work: guard with
  `ResourceLoader.exists()`, then `load()`, then cache.
- All writes are atomic: temp file, `flush()`, `close()`, then rename — via
  `SaveManager.atomic_write`.
- Palette is fixed — Apollo, 46 colours. Every UI `Color` is written in
  `src/ui/ui_theme.gd` and nowhere else, because `check_palette.sh` cannot see
  a `Color` literal and only `tests/test_ui_theme.gd` catches one.
- **Never add a CC-NC asset** — it excludes a Steam release. Audio is **CC0 or
  CC-BY only**; flag CC-BY-SA before committing to a pack. Every folder under
  `assets/` needs a `LICENSE.txt`, and `assets/CREDITS.md` is written at import
  time, not later.
- **Tests must never write to `user://saves/` or to the real
  `user://settings.json`.** Every test injects a path under `user://test_*/`
  and removes it in `after_each`.
- Conventional commit prefixes: `feat:`, `test:`, `ci:`, `docs:`, `fix:`.
  There is no `chore:` in this project.
- Each task produces two commits: the code, then a `docs:` commit ticking that
  task's checkboxes. **Always pass `--plan`** —
  `python3 tools/mark_task_done.py <N> --plan docs/superpowers/plans/2026-09-14-rp1-phase6-polish-validation.md`
  — because the tool's default glob points at the Phase 0-2 plan and will
  silently tick the wrong document. Never tick a checkbox by hand. The
  Definition of done at the end is a section, not a task:
  `python3 tools/mark_task_done.py --section "Definition of done" --plan <this file>`.

---

## File Structure

**Create:**

| File | Responsibility |
|---|---|
| `data/schema/sound.json` | Schema for the fourth content category |
| `data/sound/*.json` | One file per sound: streams, gain, loop |
| `src/systems/audio_cue.gd` | One cue: `sound_id`, `variation`, `gain_db` |
| `src/systems/audio_director.gd` | Every audio rule. Node-free, fully tested |
| `src/core/settings.gd` | `user://settings.json`: read, write, defaults |
| `src/presentation/audio_stage.gd` | Cues in, `AudioStreamPlayer`s out. No rules |
| `src/ui/save_indicator.gd` | "Saved" label, fades in and out |
| `src/ui/title_card.gd` | The zone's `display_name` on entry |
| `src/ui/controls_hint.gd` | WASD / Esc, once per player |
| `tests/test_sound_schema.gd` | The new category validates as intended |
| `tests/test_audio_director.gd` | Every rule in `AudioDirector` |
| `tests/test_settings.gd` | Round trip, defaults, malformed input |
| `assets/audio/LICENSE.txt` | Source, author, licence for the audio pack |
| `docs/playtests/<date>-phase6-findings.md` | The play pass, triaged |

**Modify:**

| File | Change |
|---|---|
| `src/core/content_registry.gd` | `"sound"` appended to `CATEGORIES` |
| `data/schema/terrain.json` | Optional `footstep: String` |
| `data/schema/zone.json` | Optional `ambient: String` |
| `data/terrain/*.json` | `footstep` on grass and dirt; water stays silent |
| `data/zone/home/zone.json` | `ambient` |
| `src/core/zone.gd` | `ambient: String` field |
| `src/core/zone_loader.gd` | Carries `ambient` from the authored zone |
| `src/core/save/save_manager.gd` | `ambient` in `zone_meta.json`, both ways |
| `src/presentation/player.gd` | Publishes `distance_moved_last_step` |
| `src/presentation/world.gd` | Owns `AudioStage`, `tick_audio(director)` |
| `src/presentation/main.gd` | Builds the director, wires settings and the three UI pieces |
| `src/ui/pause_menu.gd` | Volume slider and mute toggle |
| `src/ui/ui_theme.gd` | `HSlider` and `CheckButton` styling |
| `tests/test_ui_theme.gd` | The new theme entries exist |
| `tests/test_content_registry.gd` | Existing numeric ids do not shift |
| `tools/smoke.gd` | Ticks the director so CI exercises it headless |

**Task order is bottom-up.** Content schema first, then the director that reads
it, then settings, then the assets, and only then anything that makes a sound
or draws a pixel. Every task leaves the suite green and the game runnable.

**Two decisions this plan makes that the spec left implicit**, both called out
where they land:

1. **The ambient bed is persisted in `zone_meta.json`** (Task 2). `Continue`
   never reads `data/zone/home/zone.json`, so a bed named only in authored data
   would be silent on every loaded world. The field is optional and defaults to
   `""`, so saves written before this phase still load — Task 2 proves that
   with a test rather than asserting it.
2. **`Player` publishes the distance it travelled** (Task 7) rather than
   `World` recomputing it. The value already exists inside
   `_physics_process`; recomputing it outside would duplicate the collision
   result and drift from it.

---
## Task 1: Sound becomes the fourth content category

The category every later task reads from. Nothing plays yet: this task only
teaches the registry that `data/sound/` exists and that its files are valid.

`"sound"` is **appended** to `CATEGORIES`, never inserted. `load_from_dir`
walks categories in order and assigns numeric ids as it goes, so appending
leaves terrain, object and creature ids exactly where they are. Saves persist
strings and translate through `id_map.json`, so shifting them would be
survivable — but there is no reason to shift them, and the test in Step 1
pins that.

**Files:**
- Create: `data/schema/sound.json`
- Create: `tests/test_sound_schema.gd`
- Modify: `src/core/content_registry.gd:10` (`CATEGORIES`)
- Test: `tests/test_content_registry.gd`

**Interfaces:**
- Produces: the `sound` category, readable through the existing
  `ContentRegistry.numeric_of(string_id) -> int` and
  `ContentRegistry.def_of(numeric_id) -> Dictionary`. A sound def is
  `{id, category, display_name, streams: Array, gain_db: float, loop: bool}`.

- [x] **Step 1: Write the failing tests**

Create `tests/test_sound_schema.gd`:

```gdscript
extends GutTest
## The sound category: one file per sound, listing its stream variations.

const SCHEMA_PATH: String = "res://data/schema/sound.json"


func _schema() -> Dictionary:
	var json: JSON = JSON.new()
	assert_eq(json.parse(FileAccess.get_file_as_string(SCHEMA_PATH)), OK,
		"sound.json must be valid JSON")
	return json.data as Dictionary


func _valid_def() -> Dictionary:
	return {
		"id": "step_grass",
		"category": "sound",
		"display_name": "Grass footstep",
		"streams": ["res://assets/audio/step_grass_1.ogg"],
		"gain_db": -6.0,
		"loop": false,
	}


func test_a_minimal_sound_validates() -> void:
	assert_eq(SchemaValidator.validate(_valid_def(), _schema()).size(), 0)


func test_streams_is_required() -> void:
	# A sound with no stream is a silent bug rather than a loud one: it
	# would validate, register, and then play nothing.
	var d: Dictionary = _valid_def()
	d.erase("streams")
	var errs: PackedStringArray = SchemaValidator.validate(d, _schema())
	assert_eq(errs.size(), 1)
	assert_string_contains(errs[0], "streams")


func test_gain_and_loop_are_optional() -> void:
	var d: Dictionary = _valid_def()
	d.erase("gain_db")
	d.erase("loop")
	assert_eq(SchemaValidator.validate(d, _schema()).size(), 0)


func test_an_unknown_field_is_rejected() -> void:
	# Catches "stream" for "streams", which would otherwise register a
	# sound that can never play.
	var d: Dictionary = _valid_def()
	d["stream"] = "res://assets/audio/step_grass_1.ogg"
	var errs: PackedStringArray = SchemaValidator.validate(d, _schema())
	assert_eq(errs.size(), 1)
	assert_string_contains(errs[0], "stream")


func test_the_wrong_category_is_rejected() -> void:
	var d: Dictionary = _valid_def()
	d["category"] = "creature"
	assert_eq(SchemaValidator.validate(d, _schema()).size(), 1)
```

Add to `tests/test_content_registry.gd`:

```gdscript
func test_sound_is_the_last_category() -> void:
	# Appended, not inserted: load_from_dir assigns numeric ids in
	# category order, so inserting would renumber every creature and
	# object in the build.
	assert_eq(ContentRegistry.CATEGORIES[ContentRegistry.CATEGORIES.size() - 1], "sound")


func test_the_real_content_loads_without_errors() -> void:
	var r: ContentRegistry = ContentRegistry.new()
	var errors: PackedStringArray = r.load_from_dir("res://data")
	assert_eq(errors.size(), 0, "\n".join(errors))
	assert_true(r.has_string("grass"))
```

- [x] **Step 2: Run them and watch them fail**

Run: `./tools/run_tests.sh`
Expected: FAIL — `res://data/schema/sound.json` does not exist, so
`FileAccess.get_file_as_string` returns `""` and the parse assert fails; and
`CATEGORIES` has three entries, the last of which is `"creature"`.

- [x] **Step 3: Write the schema**

Create `data/schema/sound.json`:

```json
{
  "category": "sound",
  "required": {
    "id": "String", "category": "String", "display_name": "String",
    "streams": "Array"
  },
  "optional": {"gain_db": "float", "loop": "bool", "tags": "Array"}
}
```

- [x] **Step 4: Append the category**

In `src/core/content_registry.gd:10`:

```gdscript
const CATEGORIES: PackedStringArray = ["terrain", "object", "creature", "sound"]
```

`load_from_dir` already skips a category whose directory is absent, so the
build stays green until Task 8 adds `data/sound/`.

- [x] **Step 5: Run the tests and watch them pass**

Run: `./tools/run_tests.sh`
Expected: PASS, and the total rises by the six new cases.

- [x] **Step 6: Commit**

```bash
git add data/schema/sound.json tests/test_sound_schema.gd \
        tests/test_content_registry.gd src/core/content_registry.gd
git commit -m "feat: sound becomes the fourth content category"
```

- [x] **Step 7: Tick the plan**

```bash
python3 tools/mark_task_done.py 1 --plan docs/superpowers/plans/2026-09-14-rp1-phase6-polish-validation.md
git add docs/superpowers/plans/2026-09-14-rp1-phase6-polish-validation.md
git commit -m "docs: tick Phase 6 task 1"
```

---

## Task 2: Terrain and zone name their sounds, and the bed survives a save

`footstep` on a terrain and `ambient` on a zone. Both optional, both `String`,
both naming a sound id.

The part that needs care is the bed. `GameSession.open_saved` never reads
`data/zone/home/zone.json` — it builds the zone from the save — so a bed named
only in authored data would play on New World and be silent on every Continue.
`ambient` therefore goes into `zone_meta.json` as well, defaulting to `""` when
absent so that saves written before this phase still load.

**Files:**
- Modify: `data/schema/terrain.json`, `data/schema/zone.json`
- Modify: `src/core/zone.gd` (add `ambient`)
- Modify: `src/core/zone_loader.gd:43` (read `ambient` beside `biome`)
- Modify: `src/core/save/save_manager.gd:66-73` (write) and `:143-144` (read)
- Test: `tests/test_zone_schema.gd`, `tests/test_zone_loader.gd`,
  `tests/test_save_manager.gd`

**Interfaces:**
- Consumes: the `sound` category from Task 1.
- Produces: `Zone.ambient: String` — a sound id, `""` for a silent zone.
  Read by `AudioDirector.enter_zone` in Task 5 and by the router in Task 9.

- [x] **Step 1: Write the failing tests**

Add to `tests/test_zone_schema.gd`:

```gdscript
func test_ambient_is_an_optional_string() -> void:
	var doc: Dictionary = _valid_doc()
	doc["ambient"] = "bed_meadow"
	assert_eq(SchemaValidator.validate(doc, _schema), PackedStringArray())
```

Add to `tests/test_zone_loader.gd`:

```gdscript
func test_ambient_is_carried_from_the_authored_zone() -> void:
	var r: ContentRegistry = ContentRegistry.new()
	var _e: PackedStringArray = r.load_from_dir("res://data")
	var result: ZoneLoadResult = ZoneLoader.load_zone("res://data/zone/home", r)
	assert_not_null(result.zone, "\n".join(result.errors))
	assert_eq(result.zone.ambient, "bed_meadow")
```

Add to `tests/test_save_manager.gd`:

```gdscript
func test_ambient_round_trips_through_zone_meta() -> void:
	var zone: Zone = _zone()
	zone.ambient = "bed_meadow"
	var errors: PackedStringArray = SaveManager.save_zone(
		_root, zone, _registry, true)
	assert_eq(errors.size(), 0, "\n".join(errors))

	var back: DecodeResult = SaveManager.load_zone(_root, zone.id, _registry)
	assert_true(back.ok, back.error)
	assert_eq((back.value as Zone).ambient, "bed_meadow")


func test_a_zone_meta_without_ambient_loads_silent() -> void:
	# Every save written before Phase 6 has no ambient key. It must load
	# as a silent zone rather than as a failure.
	var zone: Zone = _zone()
	var errors: PackedStringArray = SaveManager.save_zone(
		_root, zone, _registry, true)
	assert_eq(errors.size(), 0, "\n".join(errors))

	var meta_path: String = _root.path_join("zones/%s/zone_meta.json" % zone.id)
	var json: JSON = JSON.new()
	assert_eq(json.parse(FileAccess.get_file_as_string(meta_path)), OK)
	var doc: Dictionary = json.data as Dictionary
	doc.erase("ambient")
	var f: FileAccess = FileAccess.open(meta_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(doc, "  ", true))
	f.close()

	var back: DecodeResult = SaveManager.load_zone(_root, zone.id, _registry)
	assert_true(back.ok, back.error)
	assert_eq((back.value as Zone).ambient, "")
```

- [x] **Step 2: Run them and watch them fail**

Run: `./tools/run_tests.sh`
Expected: FAIL — `ambient` is not a known field on `Zone`, and the schema
rejects it as an unknown field on a zone document.

- [x] **Step 3: Widen the two schemas**

`data/schema/terrain.json` — add to `optional`:

```json
  "optional": {"walkable": "bool", "tags": "Array", "footstep": "String"}
```

`data/schema/zone.json` — add to `optional`:

```json
  "optional": {
    "biome": "String", "generation_seed": "int", "entities": "Array",
    "ambient": "String"
  }
```

- [x] **Step 4: Carry `ambient` through the zone**

In `src/core/zone.gd`, beside `biome`:

```gdscript
## The ambient bed's sound id. "" is a silent zone, which is what every
## zone saved before Phase 6 decodes to.
var ambient: String = ""
```

In `src/core/zone_loader.gd`, after the `biome` line (`:43`):

```gdscript
	zone.ambient = str(doc.get("ambient", ""))
```

In `src/core/save/save_manager.gd`, in the `meta` dictionary (`:66-73`):

```gdscript
		"ambient": zone.ambient,
```

and beside the `biome` read (`:144`):

```gdscript
	zone.ambient = str(meta.get("ambient", ""))
```

- [x] **Step 5: Author the content**

`data/zone/home/zone.json` — add at the top level, beside `"biome"`:

```json
  "ambient": "bed_meadow",
```

`data/terrain/grass.json` and `data/terrain/dirt.json` gain a `footstep`:

```json
{"id": "grass", "category": "terrain", "display_name": "Grass",
 "sprite": "res://assets/tiles/grass.png", "walkable": true,
 "footstep": "step_grass", "tags": ["natural"]}
```

```json
{"id": "dirt", "category": "terrain", "display_name": "Dirt",
 "sprite": "res://assets/tiles/dirt.png", "walkable": true,
 "footstep": "step_dirt", "tags": ["natural"]}
```

Leave `data/terrain/water.json` without a `footstep`. A terrain with no
footstep is silent, and water is the case that proves the default is the safe
one.

The sounds these name do not exist until Task 8. That is deliberate and
harmless: the registry validates fields, not file paths, and `AudioDirector`
treats a sound it cannot resolve as silence (Task 4).

- [x] **Step 6: Run the tests and watch them pass**

Run: `./tools/run_tests.sh`
Expected: PASS.

Then confirm the content gate is still happy with the widened schemas:

```bash
./tools/check_zone.sh
```
Expected: `Zone gate: OK (1 zone(s))`.

- [x] **Step 7: Commit**

```bash
git add data/schema src/core/zone.gd src/core/zone_loader.gd \
        src/core/save/save_manager.gd data/zone/home/zone.json data/terrain \
        tests/test_zone_schema.gd tests/test_zone_loader.gd tests/test_save_manager.gd
git commit -m "feat: terrain and zones name their sounds"
```

- [x] **Step 8: Tick the plan**

```bash
python3 tools/mark_task_done.py 2 --plan docs/superpowers/plans/2026-09-14-rp1-phase6-polish-validation.md
git add docs/superpowers/plans/2026-09-14-rp1-phase6-polish-validation.md
git commit -m "docs: tick Phase 6 task 2"
```

---
## Task 3: AudioCue, and footsteps paced by distance

The first half of the director: a cue type, and the rule that turns distance
travelled into footsteps. No terrain lookup and no variations yet — those are
Task 4 — so this task can be read and reviewed as one idea.

**Why distance and not a timer.** Every case a timer gets wrong falls out of
distance for free: a normalized diagonal does not step faster, sliding along a
wall steps more slowly because less ground was covered, walking into a tree
steps not at all, and standing still is silent with no special case.

`STEP_DISTANCE` is 1.6 tiles. The player's `speed` is 4.5 tiles per second, so
that is a step every 0.36 s — about 2.8 a second, a jog. A more intuitive 0.9
would be five a second, which is a drum roll. Retune against that sum, not by
taste alone.

**Files:**
- Create: `src/systems/audio_cue.gd`
- Create: `src/systems/audio_director.gd`
- Create: `tests/test_audio_director.gd`

**Interfaces:**
- Produces: `AudioCue` with `sound_id: String`, `variation: int`,
  `gain_db: float`; and `AudioDirector.tick(distance_moved: float,
  terrain_id: int) -> Array[AudioCue]`, which returns at most one cue.

- [ ] **Step 1: Write the failing tests**

Create `tests/test_audio_director.gd`:

```gdscript
extends GutTest
## Every audio rule. The director is node-free on purpose: cadence is the
## kind of thing that is obvious by ear and invisible in review, so it is
## tested rather than listened to.

var _registry: ContentRegistry
var _director: AudioDirector
var _grass: int


func before_each() -> void:
	_registry = ContentRegistry.new()
	# Registered by hand rather than loaded from data/, so these tests
	# keep passing when the shipped content is retuned.
	_grass = _registry.register({
		"id": "grass", "category": "terrain", "display_name": "Grass",
		"sprite": "res://assets/tiles/grass.png", "walkable": true,
		"footstep": "step_grass",
	})
	var _sound: int = _registry.register({
		"id": "step_grass", "category": "sound", "display_name": "Grass footstep",
		"streams": ["a.ogg", "b.ogg", "c.ogg"], "gain_db": -6.0, "loop": false,
	})
	_director = AudioDirector.new()
	_director.rng = RandomNumberGenerator.new()
	_director.rng.seed = 1
	_director.configure(_registry)


func test_standing_still_is_silent() -> void:
	assert_eq(_director.tick(0.0, _grass).size(), 0)


func test_a_step_lands_once_the_distance_is_covered() -> void:
	assert_eq(_director.tick(AudioDirector.STEP_DISTANCE * 0.5, _grass).size(), 0)
	assert_eq(_director.tick(AudioDirector.STEP_DISTANCE * 0.5, _grass).size(), 1)


func test_the_accumulator_carries_the_remainder() -> void:
	# Otherwise short frames would round away distance and the cadence
	# would drift slower the higher the frame rate.
	var _first: Array[AudioCue] = _director.tick(AudioDirector.STEP_DISTANCE * 1.5, _grass)
	assert_eq(_director.tick(AudioDirector.STEP_DISTANCE * 0.5, _grass).size(), 1)


func test_one_enormous_frame_emits_one_step_not_a_burst() -> void:
	# A frame spike, or a debugger pause, must not machine-gun.
	assert_eq(_director.tick(AudioDirector.STEP_DISTANCE * 40.0, _grass).size(), 1)


func test_a_frame_spike_does_not_leave_a_step_owed() -> void:
	# The tick after the spike has covered no ground at all. If the
	# backlog were carried, it would step anyway -- audibly, while the
	# player stands still.
	var _spike: Array[AudioCue] = _director.tick(AudioDirector.STEP_DISTANCE * 40.0, _grass)
	assert_eq(_director.tick(0.0, _grass).size(), 0)


func test_the_cue_names_the_terrains_sound() -> void:
	var cues: Array[AudioCue] = _director.tick(AudioDirector.STEP_DISTANCE, _grass)
	assert_eq(cues.size(), 1)
	assert_eq(cues[0].sound_id, "step_grass")
```

- [ ] **Step 2: Run them and watch them fail**

Run: `./tools/run_tests.sh`
Expected: FAIL — GUT cannot resolve the `AudioDirector` and `AudioCue`
class names.

- [ ] **Step 3: Write AudioCue**

Create `src/systems/audio_cue.gd`:

```gdscript
class_name AudioCue
extends RefCounted
## One sound to play, once.
##
## The cue carries its final level rather than a reference to the sound
## def, so AudioStage never computes a level and there is exactly one
## place in the project where the mix can be wrong.

## The sound's string id, resolved against ContentRegistry by the stage.
var sound_id: String = ""

## Which of the sound's streams to play: an index into its `streams`.
var variation: int = 0

## The sound's authored gain_db with master volume already folded in.
var gain_db: float = 0.0


static func make(p_sound_id: String, p_variation: int, p_gain_db: float) -> AudioCue:
	var c: AudioCue = AudioCue.new()
	c.sound_id = p_sound_id
	c.variation = p_variation
	c.gain_db = p_gain_db
	return c
```

- [ ] **Step 4: Write the director's cadence**

Create `src/systems/audio_director.gd`:

```gdscript
class_name AudioDirector
extends RefCounted
## Every audio rule in the game. Node-free, so all of it is testable
## headless -- which matters more here than elsewhere, because audio
## faults are obvious in play and invisible in review.
##
## Distance, not time, drives footsteps. See the plan's Task 3 for why.

## Tiles between footsteps. At the player's 4.5 tiles/second this is a
## step every 0.36 s, about 2.8 a second. Retune against that sum.
const STEP_DISTANCE: float = 1.6

## Injected so tests are deterministic, exactly as AnimalSystem does it.
var rng: RandomNumberGenerator = RandomNumberGenerator.new()

var _registry: ContentRegistry = null
var _step_accumulator: float = 0.0


## Resolves sound ids against content. Called once per world.
func configure(p_registry: ContentRegistry) -> void:
	_registry = p_registry
	_step_accumulator = 0.0


## The whole per-frame rule. Returns the cues to play, usually empty and
## never more than one footstep: a frame spike must not machine-gun.
func tick(distance_moved: float, terrain_id: int) -> Array[AudioCue]:
	var cues: Array[AudioCue] = []
	if _registry == null:
		return cues

	_step_accumulator += distance_moved
	if _step_accumulator < STEP_DISTANCE:
		return cues
	# Subtract rather than zero, so the remainder carries and the cadence
	# does not drift with the frame rate.
	_step_accumulator -= STEP_DISTANCE
	# A frame spike, or a debugger pause, can leave more than a whole step
	# banked. Drop that backlog: one long frame is one step, and the steps
	# it "owes" are not played later into an empty room.
	if _step_accumulator > STEP_DISTANCE:
		_step_accumulator = 0.0

	var sound_id: String = str(_registry.def_of(terrain_id).get("footstep", ""))
	if sound_id == "":
		return cues

	var cue: AudioCue = _cue_for(sound_id)
	if cue != null:
		cues.append(cue)
	return cues


## Null when the sound is not in this build: a footstep naming content
## that was removed is silence, not a crash.
func _cue_for(sound_id: String) -> AudioCue:
	var def: Dictionary = _registry.def_of(_registry.numeric_of(sound_id))
	var streams: Array = def.get("streams", [])
	if streams.is_empty():
		return null
	return AudioCue.make(sound_id, 0, float(def.get("gain_db", 0.0)))
```

- [ ] **Step 5: Run the tests and watch them pass**

Run: `./tools/run_tests.sh`
Expected: PASS.

- [ ] **Step 6: Check the architecture guard**

Run: `./tools/godot.sh --headless --path . -s tools/guard.gd`
Expected: `Architecture guard: clean`. The director is in `src/systems/`, so
a stray `Node` reference fails here rather than in review.

- [ ] **Step 7: Commit**

```bash
git add src/systems/audio_cue.gd src/systems/audio_director.gd tests/test_audio_director.gd
git commit -m "feat: footsteps paced by distance travelled"
```

- [ ] **Step 8: Tick the plan**

```bash
python3 tools/mark_task_done.py 3 --plan docs/superpowers/plans/2026-09-14-rp1-phase6-polish-validation.md
git add docs/superpowers/plans/2026-09-14-rp1-phase6-polish-validation.md
git commit -m "docs: tick Phase 6 task 3"
```

---

## Task 4: Variations, and the sound that is missing from the build

Three grass samples in rotation, never the same one twice in a row. The
repeated-sample effect is the most audible flaw in cheap footstep audio and it
costs one stored integer to avoid.

The selection is uniform over *the others*: pick from a range one smaller than
the list, then skip past the index just played. That is uniform over the
remaining variations and cannot loop forever, which a reject-and-retry loop
can.

**Files:**
- Modify: `src/systems/audio_director.gd`
- Test: `tests/test_audio_director.gd`

**Interfaces:**
- Consumes: `AudioDirector.tick` and `AudioCue` from Task 3.
- Produces: no new signatures. `AudioCue.variation` becomes meaningful.

- [ ] **Step 1: Write the failing tests**

Add to `tests/test_audio_director.gd`:

```gdscript
func _step() -> AudioCue:
	var cues: Array[AudioCue] = _director.tick(AudioDirector.STEP_DISTANCE, _grass)
	assert_eq(cues.size(), 1)
	return cues[0]


func test_a_variation_is_never_repeated_consecutively() -> void:
	var previous: int = -1
	for i: int in range(40):
		var cue: AudioCue = _step()
		assert_ne(cue.variation, previous, "variation repeated on step %d" % i)
		previous = cue.variation


func test_every_variation_is_reachable() -> void:
	# A skip-the-last-index rule implemented off by one would quietly
	# never play the last sample in the list.
	var seen: Dictionary = {}
	for i: int in range(60):
		seen[_step().variation] = true
	assert_eq(seen.size(), 3)


func test_a_single_variation_sound_repeats_rather_than_going_silent() -> void:
	var r: ContentRegistry = ContentRegistry.new()
	var terrain: int = r.register({
		"id": "sand", "category": "terrain", "display_name": "Sand",
		"sprite": "res://assets/tiles/sand.png", "walkable": true,
		"footstep": "step_sand",
	})
	var _s: int = r.register({
		"id": "step_sand", "category": "sound", "display_name": "Sand footstep",
		"streams": ["only.ogg"],
	})
	var d: AudioDirector = AudioDirector.new()
	d.configure(r)
	assert_eq(d.tick(AudioDirector.STEP_DISTANCE, terrain)[0].variation, 0)
	assert_eq(d.tick(AudioDirector.STEP_DISTANCE, terrain)[0].variation, 0)


func test_a_terrain_without_a_footstep_is_silent() -> void:
	var r: ContentRegistry = ContentRegistry.new()
	var water: int = r.register({
		"id": "water", "category": "terrain", "display_name": "Water",
		"sprite": "res://assets/tiles/water.png", "walkable": false,
	})
	var d: AudioDirector = AudioDirector.new()
	d.configure(r)
	assert_eq(d.tick(AudioDirector.STEP_DISTANCE, water).size(), 0)


func test_a_footstep_naming_content_this_build_lacks_is_silent() -> void:
	# The save-layer placeholder rule, applied to audio: content named but
	# missing is silence, never a crash and never an engine error.
	var r: ContentRegistry = ContentRegistry.new()
	var terrain: int = r.register({
		"id": "moss", "category": "terrain", "display_name": "Moss",
		"sprite": "res://assets/tiles/moss.png", "walkable": true,
		"footstep": "step_moss_that_was_deleted",
	})
	var d: AudioDirector = AudioDirector.new()
	d.configure(r)
	assert_eq(d.tick(AudioDirector.STEP_DISTANCE, terrain).size(), 0)
```

- [ ] **Step 2: Run them and watch them fail**

Run: `./tools/run_tests.sh`
Expected: FAIL — `test_a_variation_is_never_repeated_consecutively` fails on
the second step, because `_cue_for` hardcodes variation 0.

- [ ] **Step 3: Implement the rotation**

In `src/systems/audio_director.gd`, add the field and replace `_cue_for`:

```gdscript
## sound_id -> the variation index played last, so the next one differs.
var _last_variation: Dictionary = {}
```

```gdscript
## Null when the sound is not in this build: a footstep naming content
## that was removed is silence, not a crash.
func _cue_for(sound_id: String) -> AudioCue:
	var def: Dictionary = _registry.def_of(_registry.numeric_of(sound_id))
	var streams: Array = def.get("streams", [])
	if streams.is_empty():
		return null

	var variation: int = _pick_variation(sound_id, streams.size())
	return AudioCue.make(sound_id, variation, float(def.get("gain_db", 0.0)))


## Uniform over every variation except the one just played. Picking from a
## range one smaller and then stepping over the previous index is uniform
## and terminates; rejecting and retrying is neither.
func _pick_variation(sound_id: String, count: int) -> int:
	if count <= 1:
		return 0
	var previous: int = int(_last_variation.get(sound_id, -1))
	var index: int = rng.randi_range(0, count - 2)
	if previous >= 0 and index >= previous:
		index += 1
	_last_variation[sound_id] = index
	return index
```

- [ ] **Step 4: Run the tests and watch them pass**

Run: `./tools/run_tests.sh`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/systems/audio_director.gd tests/test_audio_director.gd
git commit -m "feat: footstep variations that never repeat back to back"
```

- [ ] **Step 6: Tick the plan**

```bash
python3 tools/mark_task_done.py 4 --plan docs/superpowers/plans/2026-09-14-rp1-phase6-polish-validation.md
git add docs/superpowers/plans/2026-09-14-rp1-phase6-polish-validation.md
git commit -m "docs: tick Phase 6 task 4"
```

---
## Task 5: The bed, master volume, and mute

The rest of the director. Three rules, and all three are the kind that are
obvious in play and invisible in review.

**The bed is a cue, not a bare id.** Otherwise master volume would have to be
applied to it somewhere outside the director, and there would be two places
where the mix can be wrong.

**`enter_zone` is idempotent.** Quit to Menu and Continue re-enters the same
zone; a bed that restarted there would audibly cut off mid-breath.

**Mute emits nothing** rather than everything at -80 dB. Silence is then a
policy decision a test can assert, and a muted game does no audio work.

**Files:**
- Modify: `src/systems/audio_director.gd`
- Test: `tests/test_audio_director.gd`

**Interfaces:**
- Consumes: everything from Tasks 3 and 4, including the `_step()` helper
  Task 4 added to `tests/test_audio_director.gd`.
- Produces: `enter_zone(zone_id: String, ambient_sound_id: String) -> void`,
  `bed() -> AudioCue` (null for silence), `set_master_volume(v: float) -> void`
  (clamped to 0.0-1.0), `set_muted(m: bool) -> void`, `is_muted() -> bool`,
  `master_volume() -> float`. Consumed by the router in Task 9 and the pause
  menu in Task 10.

- [ ] **Step 1: Write the failing tests**

Add to `tests/test_audio_director.gd`:

```gdscript
func _with_bed() -> AudioDirector:
	var _s: int = _registry.register({
		"id": "bed_meadow", "category": "sound", "display_name": "Meadow",
		"streams": ["meadow.ogg"], "gain_db": -18.0, "loop": true,
	})
	_director.enter_zone("home", "bed_meadow")
	return _director


func test_no_bed_before_a_zone_is_entered() -> void:
	assert_null(_director.bed())


func test_entering_a_zone_sets_its_bed() -> void:
	var cue: AudioCue = _with_bed().bed()
	assert_not_null(cue)
	assert_eq(cue.sound_id, "bed_meadow")


func test_a_zone_with_no_ambient_is_silent() -> void:
	_director.enter_zone("home", "")
	assert_null(_director.bed())


func test_re_entering_the_same_zone_leaves_the_bed_alone() -> void:
	# Quit to Menu and Continue re-enters the same zone. Restarting the
	# bed there is audible and wrong.
	var first: AudioCue = _with_bed().bed()
	_director.enter_zone("home", "bed_meadow")
	assert_same(first, _director.bed(), "the bed cue was rebuilt")


func test_entering_a_different_zone_replaces_the_bed() -> void:
	var first: AudioCue = _with_bed().bed()
	var _s: int = _registry.register({
		"id": "bed_cave", "category": "sound", "display_name": "Cave",
		"streams": ["cave.ogg"], "loop": true,
	})
	_director.enter_zone("caves", "bed_cave")
	assert_ne(first, _director.bed())
	assert_eq(_director.bed().sound_id, "bed_cave")


func test_master_volume_folds_into_every_cue() -> void:
	# -6 dB authored, halved again by a 0.5 master: the stage never does
	# this sum, so this is the only place it can be wrong.
	_director.set_master_volume(0.5)
	assert_almost_eq(_step().gain_db, -6.0 + linear_to_db(0.5), 0.01)


func test_full_volume_leaves_the_authored_gain_alone() -> void:
	_director.set_master_volume(1.0)
	assert_almost_eq(_step().gain_db, -6.0, 0.01)


func test_master_volume_is_clamped() -> void:
	_director.set_master_volume(4.0)
	assert_almost_eq(_director.master_volume(), 1.0, 0.001)
	_director.set_master_volume(-1.0)
	assert_almost_eq(_director.master_volume(), 0.0, 0.001)


func test_the_bed_carries_master_volume_too() -> void:
	var d: AudioDirector = _with_bed()
	d.set_master_volume(0.5)
	assert_almost_eq(d.bed().gain_db, -18.0 + linear_to_db(0.5), 0.01)


func test_mute_silences_footsteps_and_the_bed() -> void:
	var d: AudioDirector = _with_bed()
	d.set_muted(true)
	assert_eq(d.tick(AudioDirector.STEP_DISTANCE, _grass).size(), 0)
	assert_null(d.bed())


func test_unmuting_restores_the_bed_without_re_entering_the_zone() -> void:
	var d: AudioDirector = _with_bed()
	d.set_muted(true)
	d.set_muted(false)
	assert_not_null(d.bed())
	assert_eq(d.bed().sound_id, "bed_meadow")
```

- [ ] **Step 2: Run them and watch them fail**

Run: `./tools/run_tests.sh`
Expected: FAIL — `enter_zone`, `bed`, `set_master_volume`, `master_volume`
and `set_muted` are not known methods.

- [ ] **Step 3: Implement the three rules**

In `src/systems/audio_director.gd`, add the fields:

```gdscript
var _zone_id: String = ""
var _bed_sound_id: String = ""
var _bed_cue: AudioCue = null
var _master_volume: float = 0.8
var _muted: bool = false
```

and the methods:

```gdscript
## Sets the bed for the zone being entered. "" is a valid ambient id and
## means silence, which is how a zone opts out rather than by omission.
## Idempotent: re-entering the zone already playing changes nothing.
func enter_zone(zone_id: String, ambient_sound_id: String) -> void:
	if zone_id == _zone_id and ambient_sound_id == _bed_sound_id:
		return
	_zone_id = zone_id
	_bed_sound_id = ambient_sound_id
	_rebuild_bed()


## The bed that should be playing, as a cue, or null for silence.
func bed() -> AudioCue:
	if _muted:
		return null
	return _bed_cue


func set_master_volume(v: float) -> void:
	_master_volume = clampf(v, 0.0, 1.0)
	_rebuild_bed()


func master_volume() -> float:
	return _master_volume


func set_muted(m: bool) -> void:
	_muted = m


func is_muted() -> bool:
	return _muted


## The bed cue is rebuilt rather than recomputed per call, so that
## re-entering a zone can be detected as "the same cue object" and the
## stage has a cheap identity check for "is this still the same bed".
func _rebuild_bed() -> void:
	if _registry == null or _bed_sound_id == "":
		_bed_cue = null
		return
	_bed_cue = _cue_for(_bed_sound_id)
```

Then fold master volume into every cue, in `_cue_for`:

```gdscript
	var variation: int = _pick_variation(sound_id, streams.size())
	var gain_db: float = float(def.get("gain_db", 0.0)) + linear_to_db(_master_volume)
	return AudioCue.make(sound_id, variation, gain_db)
```

and make `tick` respect mute, as its first lines:

```gdscript
	if _registry == null or _muted:
		return cues
```

> `linear_to_db(0.0)` is `-INF`, which is correct — a zero master volume is
> silence — and `AudioStage` sets `volume_db` from it without special-casing,
> because Godot treats `-INF` as silent. Mute is still a separate rule: it
> skips the work entirely rather than playing silence.

- [ ] **Step 4: Run the tests and watch them pass**

Run: `./tools/run_tests.sh`
Expected: PASS.

`test_re_entering_the_same_zone_leaves_the_bed_alone` uses `assert_same`, so
it fails if the cue is rebuilt even to an identical value. That is deliberate:
identity is what the stage will use in Task 8 to decide whether to restart the
bed player.

- [ ] **Step 5: Commit**

```bash
git add src/systems/audio_director.gd tests/test_audio_director.gd
git commit -m "feat: the ambient bed, master volume and mute"
```

- [ ] **Step 6: Tick the plan**

```bash
python3 tools/mark_task_done.py 5 --plan docs/superpowers/plans/2026-09-14-rp1-phase6-polish-validation.md
git add docs/superpowers/plans/2026-09-14-rp1-phase6-polish-validation.md
git commit -m "docs: tick Phase 6 task 5"
```

---

## Task 6: Settings, the second persistence surface

`user://settings.json`. Master volume, mute, and whether the controls hint has
been shown.

**It lives at the `user://` root, not under `saves/home/`.** Volume must
survive New World, and a world that has to be deleted must not cost the player
their settings. This is the smallest second persistence surface that can
exist, and it should stay that way.

A corrupt or unreadable settings file **starts the game at defaults**. It must
never be a reason the game will not start — which is exactly the failure mode
a version field plus a strict parser would otherwise introduce.

**Files:**
- Create: `src/core/settings.gd`
- Create: `tests/test_settings.gd`

**Interfaces:**
- Produces: `Settings.DEFAULT_PATH: String`,
  `Settings.load_from(path: String) -> Settings` (never fails),
  `Settings.save_to(path: String) -> String` (returns `""` or an error),
  and the fields `master_volume: float`, `muted: bool`,
  `controls_hint_shown: bool`. Consumed by the router in Task 9.

- [ ] **Step 1: Write the failing tests**

Create `tests/test_settings.gd`:

```gdscript
extends GutTest
## user://settings.json. Never under saves/: settings outlive worlds.

const PATH: String = "user://test_settings/settings.json"


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute("user://test_settings")
	_wipe()


func after_each() -> void:
	_wipe()


func _wipe() -> void:
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(PATH)


func test_the_default_path_is_outside_the_save_root() -> void:
	# A world that has to be deleted must not cost the player their volume.
	assert_eq(Settings.DEFAULT_PATH, "user://settings.json")
	assert_false(Settings.DEFAULT_PATH.contains("saves"))


func test_defaults_when_no_file_exists() -> void:
	var s: Settings = Settings.load_from(PATH)
	assert_almost_eq(s.master_volume, 0.8, 0.001)
	assert_false(s.muted)
	assert_false(s.controls_hint_shown)


func test_round_trips_every_field() -> void:
	var s: Settings = Settings.new()
	s.master_volume = 0.35
	s.muted = true
	s.controls_hint_shown = true
	assert_eq(s.save_to(PATH), "")

	var back: Settings = Settings.load_from(PATH)
	assert_almost_eq(back.master_volume, 0.35, 0.001)
	assert_true(back.muted)
	assert_true(back.controls_hint_shown)


func test_malformed_json_loads_defaults_rather_than_failing() -> void:
	var f: FileAccess = FileAccess.open(PATH, FileAccess.WRITE)
	f.store_string("{not json at all")
	f.close()
	var s: Settings = Settings.load_from(PATH)
	assert_almost_eq(s.master_volume, 0.8, 0.001)


func test_a_json_array_loads_defaults_rather_than_failing() -> void:
	var f: FileAccess = FileAccess.open(PATH, FileAccess.WRITE)
	f.store_string("[1, 2, 3]")
	f.close()
	assert_almost_eq(Settings.load_from(PATH).master_volume, 0.8, 0.001)


func test_a_missing_field_takes_its_default() -> void:
	var f: FileAccess = FileAccess.open(PATH, FileAccess.WRITE)
	f.store_string('{"version": 1, "muted": true}')
	f.close()
	var s: Settings = Settings.load_from(PATH)
	assert_true(s.muted)
	assert_almost_eq(s.master_volume, 0.8, 0.001)


func test_volume_from_disk_is_clamped() -> void:
	# A hand-edited settings.json must not be able to blow the mix up.
	var f: FileAccess = FileAccess.open(PATH, FileAccess.WRITE)
	f.store_string('{"version": 1, "master_volume": 99.0}')
	f.close()
	assert_almost_eq(Settings.load_from(PATH).master_volume, 1.0, 0.001)


func test_the_file_is_human_readable() -> void:
	var s: Settings = Settings.new()
	assert_eq(s.save_to(PATH), "")
	var text: String = FileAccess.get_file_as_string(PATH)
	assert_string_contains(text, "\n")
	assert_string_contains(text, "master_volume")
```

- [ ] **Step 2: Run them and watch them fail**

Run: `./tools/run_tests.sh`
Expected: FAIL — GUT cannot resolve the `Settings` class name.

- [ ] **Step 3: Write Settings**

Create `src/core/settings.gd`:

```gdscript
class_name Settings
extends RefCounted
## user://settings.json: the player's preferences, not their world.
##
## Deliberately NOT under saves/. Volume must survive New World, and a
## world that has to be deleted must not cost the player their settings.
##
## load_from never fails. A malformed settings file starting the game at
## defaults is right; a malformed settings file preventing the game from
## starting at all is not, and that is what a strict parser would do here.

const DEFAULT_PATH: String = "user://settings.json"
const VERSION: int = 1

var master_volume: float = 0.8
var muted: bool = false
var controls_hint_shown: bool = false


## Always returns a usable Settings, whatever is on disk.
static func load_from(path: String = DEFAULT_PATH) -> Settings:
	var s: Settings = Settings.new()
	if not FileAccess.file_exists(path):
		return s

	var json: JSON = JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		push_warning("settings.json: malformed, using defaults")
		return s
	if not (json.data is Dictionary):
		push_warning("settings.json: top level is not an object, using defaults")
		return s

	var doc: Dictionary = json.data
	s.master_volume = clampf(float(doc.get("master_volume", s.master_volume)), 0.0, 1.0)
	s.muted = bool(doc.get("muted", s.muted))
	s.controls_hint_shown = bool(doc.get("controls_hint_shown", s.controls_hint_shown))
	return s


## "" on success, the error otherwise. Atomic, like every other write.
func save_to(path: String = DEFAULT_PATH) -> String:
	var doc: Dictionary = {
		"version": VERSION,
		"master_volume": master_volume,
		"muted": muted,
		"controls_hint_shown": controls_hint_shown,
	}
	return SaveManager.atomic_write(path, JSON.stringify(doc, "  ", true).to_utf8_buffer())
```

- [ ] **Step 4: Run the tests and watch them pass**

Run: `./tools/run_tests.sh`
Expected: PASS.

- [ ] **Step 5: Confirm no test touched the real settings file**

```bash
ls ~/"Library/Application Support/Godot/app_userdata/RP1/settings.json" 2>/dev/null \
  && echo "A TEST WROTE THE REAL SETTINGS FILE" || echo "clean"
```
Expected: `clean`. Every test in this task uses `user://test_settings/`.

- [ ] **Step 6: Commit**

```bash
git add src/core/settings.gd tests/test_settings.gd
git commit -m "feat: settings that outlive the world save"
```

- [ ] **Step 7: Tick the plan**

```bash
python3 tools/mark_task_done.py 6 --plan docs/superpowers/plans/2026-09-14-rp1-phase6-polish-validation.md
git add docs/superpowers/plans/2026-09-14-rp1-phase6-polish-validation.md
git commit -m "docs: tick Phase 6 task 6"
```

---
## Task 7: The audio assets, licensed at import time

The first sounds in the repository. Nothing plays them yet — that is Task 8 —
so this task is sourcing, licensing and content files, and it is the one task
in the phase with no test to write.

**What is needed, and nothing more:**

| Sound id | What | Notes |
|---|---|---|
| `step_grass` | 3 footstep variations on grass | short, dry, no reverb tail |
| `step_dirt` | 3 footstep variations on dirt | as above |
| `bed_meadow` | one looping outdoor ambience | seamless loop, 30 s or more |

**Licensing is not optional and not deferrable.** `CLAUDE.md` is absolute:
never add a CC-NC asset — it excludes a Steam release. **CC0 or CC-BY only**,
and flag CC-BY-SA before committing to it. Good CC0 sources are kenney.nl
(uniformly CC0) and the CC0-filtered views of OpenGameArt and freesound;
freesound and OpenGameArt are **per-file** licensed, so the licence must be
checked on the actual file, not the pack page.

**Files:**
- Create: `assets/audio/LICENSE.txt`
- Create: `assets/audio/step_grass_1.ogg` and 7 more `.ogg` files
- Create: `data/sound/step_grass.json`, `step_dirt.json`, `bed_meadow.json`
- Modify: `assets/CREDITS.md`

**Interfaces:**
- Consumes: the schema from Task 1 and the ids named by content in Task 2.
- Produces: the sound ids `step_grass`, `step_dirt`, `bed_meadow`, resolvable
  through `ContentRegistry`.

- [ ] **Step 1: Source the audio, checking the licence on each file**

Every file must be **Ogg Vorbis** (`.ogg`). Convert if the source is WAV:

```bash
ffmpeg -i source.wav -c:a libvorbis -q:a 5 assets/audio/step_grass_1.ogg
```

`.ogg` rather than `.wav` because `AudioStreamOggVorbis` has a runtime `loop`
property that Task 8 sets from the content def, and because an uncompressed
ambient bed is megabytes for no audible gain.

- [ ] **Step 2: Write the licence file before the audio is committed**

Create `assets/audio/LICENSE.txt`, following the form of
`assets/tiles/LICENSE.txt`:

```
Audio assets.

Source:  <pack name> (<author>, <licence>)
         <url>
Files:   step_grass_1-3.ogg, step_dirt_1-3.ogg, bed_meadow.ogg
Licence: <CC0 1.0 | CC-BY 4.0>. <If CC-BY: ATTRIBUTION REQUIRED -- the
         pack's notice reads "<exact text>". See assets/CREDITS.md.>
```

Add the same pack to `assets/CREDITS.md` **now**, in the form the existing
entries use. `CLAUDE.md`: record every pack at import time, not later.

- [ ] **Step 3: Verify the licence gate**

Run: `./tools/check_asset_licences.sh`
Expected: `Asset licences: OK`. It fails if `assets/audio/` has no
`LICENSE.txt`, which is the point.

- [ ] **Step 4: Write the content files**

Create `data/sound/step_grass.json`:

```json
{"id": "step_grass", "category": "sound", "display_name": "Grass footstep",
 "streams": ["res://assets/audio/step_grass_1.ogg",
             "res://assets/audio/step_grass_2.ogg",
             "res://assets/audio/step_grass_3.ogg"],
 "gain_db": -6.0, "loop": false}
```

Create `data/sound/step_dirt.json`:

```json
{"id": "step_dirt", "category": "sound", "display_name": "Dirt footstep",
 "streams": ["res://assets/audio/step_dirt_1.ogg",
             "res://assets/audio/step_dirt_2.ogg",
             "res://assets/audio/step_dirt_3.ogg"],
 "gain_db": -6.0, "loop": false}
```

Create `data/sound/bed_meadow.json`:

```json
{"id": "bed_meadow", "category": "sound", "display_name": "Meadow ambience",
 "streams": ["res://assets/audio/bed_meadow.ogg"],
 "gain_db": -18.0, "loop": true}
```

The bed sits well below the footsteps. An ambient bed that competes with the
foreground is the most common mixing mistake in a first pass, and `gain_db` is
data precisely so this is a JSON edit in Task 14 and not a code change.

- [ ] **Step 5: Import, and confirm the registry sees them**

```bash
./tools/godot.sh --headless --path . --import
./tools/run_tests.sh
```
Expected: PASS, including `test_the_real_content_loads_without_errors` from
Task 1, which now actually exercises `data/sound/`.

Then confirm the paths resolve, which the schema cannot check:

```bash
./tools/godot.sh --headless --path . -s tools/dump_save.gd
```
Expected: it prints the world without new errors. (A missing `.ogg` shows up
as an engine error at load time, not as a validation failure.)

- [ ] **Step 6: Commit**

```bash
git add assets/audio assets/CREDITS.md data/sound
git commit -m "feat: the first audio assets, licensed at import time"
```

- [ ] **Step 7: Tick the plan**

```bash
python3 tools/mark_task_done.py 7 --plan docs/superpowers/plans/2026-09-14-rp1-phase6-polish-validation.md
git add docs/superpowers/plans/2026-09-14-rp1-phase6-polish-validation.md
git commit -m "docs: tick Phase 6 task 7"
```

---

## Task 8: AudioStage, and the first sound the game has ever made

The presentation half. `AudioStage` holds no rules: it turns cues into playing
`AudioStreamPlayer`s and nothing else. Streams are resolved through the
registry with the `ResourceLoader.exists()` guard then `load()`, then cached —
the same pattern as `entity_renderer.gd:_texture_for`.

`Player` publishes the distance it travelled rather than `World` recomputing
it: the value already exists inside `_physics_process`, and recomputing it
outside would duplicate the collision result and drift from it.

**Files:**
- Create: `src/presentation/audio_stage.gd`
- Modify: `src/presentation/player.gd` (publish `distance_moved_last_step`)
- Modify: `src/presentation/world.gd` (own the stage, add `tick_audio`)
- Modify: `src/presentation/main.gd` (build the director, enter the zone)
- Modify: `tools/smoke.gd`

**Interfaces:**
- Consumes: `AudioDirector` (Tasks 3-5), the sounds from Task 7,
  `Zone.ambient` from Task 2.
- Produces: `Player.distance_moved_last_step: float`,
  `World.tick_audio(director: AudioDirector) -> void`,
  `AudioStage.setup(registry: ContentRegistry) -> void`,
  `AudioStage.play(cues: Array[AudioCue]) -> void`,
  `AudioStage.set_bed(cue: AudioCue) -> void`.

- [ ] **Step 1: Publish the distance the player actually travelled**

In `src/presentation/player.gd`, add beside `entity_id`:

```gdscript
## Distance covered in the last physics step, after collision resolution.
## Published rather than recomputed by World: recomputing it outside this
## function would duplicate the collision result and drift from it.
var distance_moved_last_step: float = 0.0
```

and in `_physics_process`, replace the `set_position` line with:

```gdscript
	var moved: Vector2 = MovementSystem.move(pos, velocity, delta, body, solids, bounds)
	distance_moved_last_step = pos.distance_to(moved)
	zone.entities.set_position(entity_id, moved)
```

Note the early `return` at the top of `_physics_process`: when the player has
no zone, `distance_moved_last_step` keeps its last value. Set it to `0.0`
before that return as well, so a world being torn down cannot leave a stale
distance behind:

```gdscript
func _physics_process(delta: float) -> void:
	distance_moved_last_step = 0.0
	if zone == null or not zone.entities.has(entity_id):
		return
```

- [ ] **Step 2: Write AudioStage**

Create `src/presentation/audio_stage.gd`:

```gdscript
class_name AudioStage
extends Node
## Cues in, AudioStreamPlayers out. Holds no rules: every decision about
## what plays, when, and how loud was made by AudioDirector.
##
## Streams are resolved through ContentRegistry and cached, guarding with
## ResourceLoader.exists() before load() because load() on a missing path
## pushes an engine-level error. Same guard as entity_renderer.gd:64.

## Footsteps are short; four covers overlap at any believable cadence.
const VOICES: int = 4

var _registry: ContentRegistry = null
var _voices: Array[AudioStreamPlayer] = []
var _next_voice: int = 0
var _bed_player: AudioStreamPlayer = null
var _bed_cue: AudioCue = null
var _streams: Dictionary = {}   ## "sound_id:variation" -> AudioStream


func setup(p_registry: ContentRegistry) -> void:
	_registry = p_registry
	for i: int in range(VOICES):
		var player: AudioStreamPlayer = AudioStreamPlayer.new()
		player.name = "Voice%d" % i
		add_child(player)
		_voices.append(player)

	_bed_player = AudioStreamPlayer.new()
	_bed_player.name = "Bed"
	add_child(_bed_player)


func play(cues: Array[AudioCue]) -> void:
	for cue: AudioCue in cues:
		var stream: AudioStream = _stream_for(cue)
		if stream == null:
			continue
		var player: AudioStreamPlayer = _voices[_next_voice]
		_next_voice = (_next_voice + 1) % VOICES
		player.stream = stream
		player.volume_db = cue.gain_db
		player.play()


## Null stops the bed. The same cue twice is deliberately a no-op: the
## director returns an identical object while the zone is unchanged, so
## this is what keeps a Continue from restarting the ambience.
func set_bed(cue: AudioCue) -> void:
	if cue == _bed_cue:
		return
	_bed_cue = cue

	if cue == null:
		_bed_player.stop()
		return

	var stream: AudioStream = _stream_for(cue)
	if stream == null:
		_bed_player.stop()
		return
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	_bed_player.stream = stream
	_bed_player.volume_db = cue.gain_db
	_bed_player.play()


func _stream_for(cue: AudioCue) -> AudioStream:
	var key: String = "%s:%d" % [cue.sound_id, cue.variation]
	if _streams.has(key):
		return _streams[key]

	var def: Dictionary = _registry.def_of(_registry.numeric_of(cue.sound_id))
	var streams: Array = def.get("streams", [])
	var stream: AudioStream = null
	if cue.variation < 0 or cue.variation >= streams.size():
		push_error("audio: %s has no variation %d" % [cue.sound_id, cue.variation])
	else:
		var path: String = str(streams[cue.variation])
		if not ResourceLoader.exists(path):
			push_error("audio: cannot load '%s' for %s" % [path, cue.sound_id])
		else:
			stream = load(path) as AudioStream
	_streams[key] = stream
	return stream
```

- [ ] **Step 3: Give World an audio tick**

In `src/presentation/world.gd`, add the field:

```gdscript
var _audio: AudioStage = null
```

in `build()`, after the entity renderer is added:

```gdscript
	_audio = AudioStage.new()
	_audio.name = "AudioStage"
	add_child(_audio)
	_audio.setup(registry)
```

and beside `tick_animals`:

```gdscript
## Audio is ticked from the same physics step as movement, so the distance
## the player covered and the cues it produces belong to the same frame.
## The director is passed in rather than owned: it outlives the world, so
## a volume change on the menu is not lost when a world is torn down.
func tick_audio(director: AudioDirector) -> void:
	if _player == null or zone == null or _audio == null:
		return
	var pos: Vector2 = zone.entities.get_position(player_entity_id)
	var tile: Vector2i = Vector2i(floori(pos.x), floori(pos.y))
	var terrain_id: int = zone.get_terrain(tile) if zone.in_bounds(tile) else 0
	_audio.play(director.tick(_player.distance_moved_last_step, terrain_id))
	_audio.set_bed(director.bed())
```

- [ ] **Step 4: Wire the router**

In `src/presentation/main.gd`, add the field:

```gdscript
var _audio_director: AudioDirector = null
```

in `_ready()`, after `_registry` is built:

```gdscript
	_audio_director = AudioDirector.new()
	_audio_director.rng = RandomNumberGenerator.new()
	_audio_director.rng.randomize()
	_audio_director.configure(_registry)
```

in `_enter_world`, after `_world.build(...)`:

```gdscript
	_audio_director.enter_zone(result.zone.id, result.zone.ambient)
```

in `_physics_process`, beside the animal tick:

```gdscript
	_world.tick_animals(delta)
	_world.tick_audio(_audio_director)
	_session.tick(delta, _registry)
```

and in `_on_quit_to_menu`, before `_world.queue_free()`:

```gdscript
	# The AudioStage is a child of World and dies with it, so the bed
	# stops here whatever the director thinks. Telling the director that
	# too is not tidiness: without it, Continue would re-enter the zone it
	# believes is already playing, take the idempotent path, and hand the
	# fresh AudioStage no bed at all -- a silent world until the next zone
	# change, which in Stage 1 never comes.
	_audio_director.enter_zone("", "")
```

> This is the interaction worth understanding before touching either
> half: **idempotence protects against a repeated `enter_zone`; the reset
> protects against a stale one.** Removing either one produces a bug that
> only shows up on the second world of a session.

- [ ] **Step 5: Make the smoke test exercise the director headlessly**

In `tools/smoke.gd`, after the zone is built, drive a few steps so that CI
catches a director that throws on real content:

```gdscript
	var director: AudioDirector = AudioDirector.new()
	director.configure(registry)
	director.enter_zone(zone.id, zone.ambient)
	var cues: int = 0
	for i: int in range(100):
		cues += director.tick(AudioDirector.STEP_DISTANCE, zone.get_terrain(Vector2i(64, 60))).size()
	print("RP1 audio: %d cues over 100 steps, bed %s"
		% [cues, "yes" if director.bed() != null else "no"])
```

`AudioStage` is not exercised here: it needs a scene tree and an audio device,
and CI has neither. That is the line between the two halves.

- [ ] **Step 6: Run everything**

```bash
./tools/run_tests.sh
./tools/godot.sh --headless --path . -s tools/guard.gd
./tools/godot.sh --headless --path . -s tools/smoke.gd
```
Expected: tests PASS; guard clean — `AudioStage` is in `presentation/`, so
its `extends Node` is legal there and would fail in `systems/`; smoke prints
a non-zero cue count and `bed yes`.

- [ ] **Step 7: Play it — the first listening test**

```bash
./tools/godot.sh --path .
```

New World, then walk. Listening for, in order of how likely they are to be
wrong: footsteps at a walking cadence rather than a drum roll or a limp; the
sound changing between grass and the dirt paths; silence when standing still
and when walking into a tree; the bed audible but underneath, not competing.

Do not tune the numbers yet — Task 14 is where retuning belongs, with the
whole game to listen to. Note what sounds wrong and move on.

- [ ] **Step 8: Commit**

```bash
git add src/presentation tools/smoke.gd
git commit -m "feat: the game makes its first sound"
```

- [ ] **Step 9: Tick the plan**

```bash
python3 tools/mark_task_done.py 8 --plan docs/superpowers/plans/2026-09-14-rp1-phase6-polish-validation.md
git add docs/superpowers/plans/2026-09-14-rp1-phase6-polish-validation.md
git commit -m "docs: tick Phase 6 task 8"
```

---
## Task 9: Volume and mute on the pause menu

Two controls, on a menu that already exists. The menu emits; the router calls
the director and writes the file — the Phase 5 rule that menus hold no logic
is what keeps this task small.

**Writing on every drag would be a write per pixel of slider travel.** The
router writes settings on release and when the pause menu closes, not on every
`value_changed`.

**Files:**
- Modify: `src/ui/ui_theme.gd` (`HSlider` and `CheckButton` styling)
- Modify: `src/ui/pause_menu.gd`
- Modify: `src/presentation/main.gd`
- Test: `tests/test_ui_theme.gd`

**Interfaces:**
- Consumes: `Settings` (Task 6), `AudioDirector.set_master_volume` /
  `set_muted` (Task 5).
- Produces: `PauseMenu.volume_changed(value: float)` and
  `PauseMenu.mute_toggled(muted: bool)` signals, plus
  `PauseMenu.show_settings(volume: float, muted: bool) -> void` for the router
  to push the loaded values in.

- [ ] **Step 1: Write the failing theme test**

Add to `tests/test_ui_theme.gd`:

```gdscript
func test_the_theme_styles_the_settings_controls() -> void:
	# The palette rule has no other enforcement for a control the menus
	# start using: check_palette.sh cannot see a Color, so an unstyled
	# HSlider would ship Godot's default grey and nothing would fail.
	var theme: Theme = UiTheme.build()
	assert_true(theme.has_stylebox("slider", "HSlider"))
	assert_true(theme.has_stylebox("grabber_area", "HSlider"))
	assert_true(theme.has_color("font_color", "CheckButton"))
```

- [ ] **Step 2: Run it and watch it fail**

Run: `./tools/run_tests.sh`
Expected: FAIL — `has_stylebox("slider", "HSlider")` is false.

- [ ] **Step 3: Style the two controls**

In `src/ui/ui_theme.gd`, inside `build()` before `return theme`:

```gdscript
	# A slider's track and its filled portion. ACCENT for the filled part
	# so the level reads at a glance in a dim menu.
	theme.set_stylebox("slider", "HSlider", _box(BACKGROUND, BORDER))
	theme.set_stylebox("grabber_area", "HSlider", _box(ACCENT, ACCENT))
	theme.set_stylebox("grabber_area_highlight", "HSlider", _box(ACCENT, TEXT))

	theme.set_color("font_color", "CheckButton", TEXT)
	theme.set_color("font_hover_color", "CheckButton", ACCENT)
	theme.set_color("font_focus_color", "CheckButton", TEXT)
```

No new `Color` is introduced — every one of these is an existing constant,
which is the whole point of the file.

- [ ] **Step 4: Add the controls to the pause menu**

In `src/ui/pause_menu.gd`, add the signals and fields:

```gdscript
signal volume_changed(value: float)
signal mute_toggled(muted: bool)

var _volume: HSlider = null
var _mute: CheckButton = null
```

In `_ready()`, between the Resume button and `to_menu`:

```gdscript
	var volume_row: HBoxContainer = HBoxContainer.new()
	volume_row.add_theme_constant_override("separation", 12)
	column.add_child(volume_row)

	var volume_label: Label = Label.new()
	volume_label.text = "Volume"
	volume_row.add_child(volume_label)

	_volume = HSlider.new()
	_volume.min_value = 0.0
	_volume.max_value = 1.0
	_volume.step = 0.05
	_volume.custom_minimum_size = Vector2(180, 0)
	_volume.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_volume.value_changed.connect(func(v: float) -> void: volume_changed.emit(v))
	volume_row.add_child(_volume)

	_mute = CheckButton.new()
	_mute.text = "Mute"
	_mute.toggled.connect(func(on: bool) -> void: mute_toggled.emit(on))
	column.add_child(_mute)
```

and add the setter the router uses:

```gdscript
## Pushes the loaded settings into the controls without re-emitting:
## set_value_no_signal, or opening the menu would look like a change and
## write the file back on every pause.
func show_settings(volume: float, muted: bool) -> void:
	_volume.set_value_no_signal(volume)
	_mute.set_pressed_no_signal(muted)
```

- [ ] **Step 5: Wire the router**

In `src/presentation/main.gd`, add the field:

```gdscript
var _settings: Settings = null
```

In `_ready()`, after the director is configured:

```gdscript
	_settings = Settings.load_from()
	_audio_director.set_master_volume(_settings.master_volume)
	_audio_director.set_muted(_settings.muted)
```

after the pause menu is constructed:

```gdscript
	_pause_menu.volume_changed.connect(_on_volume_changed)
	_pause_menu.mute_toggled.connect(_on_mute_toggled)
	_pause_menu.show_settings(_settings.master_volume, _settings.muted)
```

and the handlers, with the write deferred to un-pause:

```gdscript
func _on_volume_changed(value: float) -> void:
	# Applied immediately so the slider is audible while dragging;
	# written on un-pause, because writing per drag event is a file write
	# per pixel of travel.
	_settings.master_volume = value
	_audio_director.set_master_volume(value)


func _on_mute_toggled(muted: bool) -> void:
	_settings.muted = muted
	_audio_director.set_muted(muted)


func _save_settings() -> void:
	var err: String = _settings.save_to()
	if err != "":
		push_error("settings: %s" % err)
```

In `_set_paused`, write them as the menu closes:

```gdscript
func _set_paused(paused: bool) -> void:
	get_tree().paused = paused
	_pause_menu.visible = paused
	if paused:
		_pause_menu.show_settings(_settings.master_volume, _settings.muted)
		_pause_menu.focus_first()
	else:
		_save_settings()
```

and in `_save_and_quit`, before `get_tree().quit()` in the success path, so a
volume change made and then quit from is not lost:

```gdscript
	_save_settings()
```

- [ ] **Step 6: Run the tests**

```bash
./tools/run_tests.sh
./tools/godot.sh --headless --path . -s tools/guard.gd
```
Expected: PASS and clean.

- [ ] **Step 7: Play it**

```bash
./tools/godot.sh --path .
```

Esc to pause. Drag the slider — the bed's level follows while dragging. Mute —
silence, immediately, both bed and footsteps. Resume, Esc again: the controls
show where they were left. Quit, relaunch, Continue: still there.

Then confirm the file:

```bash
cat ~/"Library/Application Support/Godot/app_userdata/RP1/settings.json"
```
Expected: the volume and mute you left, and `settings.json` at the `user://`
root rather than inside `saves/`.

- [ ] **Step 8: Commit**

```bash
git add src/ui src/presentation/main.gd tests/test_ui_theme.gd
git commit -m "feat: volume and mute on the pause menu"
```

- [ ] **Step 9: Tick the plan**

```bash
python3 tools/mark_task_done.py 9 --plan docs/superpowers/plans/2026-09-14-rp1-phase6-polish-validation.md
git add docs/superpowers/plans/2026-09-14-rp1-phase6-polish-validation.md
git commit -m "docs: tick Phase 6 task 9"
```

---

## Task 10: The save indicator

The only one of the three UI pieces that carries information the player cannot
get any other way. Autosave is otherwise invisible, and an invisible autosave
is not trusted — which is exactly the anxiety that makes people quit to the
menu "just in case" every few minutes.

`GameSession.tick` already returns `true` on the frame it saved. This is three
lines of wiring and a label that fades.

**Files:**
- Create: `src/ui/save_indicator.gd`
- Modify: `src/presentation/main.gd`

**Interfaces:**
- Consumes: `GameSession.tick(delta, registry) -> bool` (existing).
- Produces: `SaveIndicator.flash() -> void`.

- [ ] **Step 1: Write the indicator**

Create `src/ui/save_indicator.gd`:

```gdscript
class_name SaveIndicator
extends Control
## "Saved", briefly, in a corner.
##
## No test: it holds no rules, exactly like the Phase 5 menus. What it
## reports -- whether a save happened -- is GameSession's business and is
## tested there.

const HOLD_SECONDS: float = 1.2
const FADE_SECONDS: float = 0.6

var _label: Label = null
var _tween: Tween = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_label = Label.new()
	_label.text = "Saved"
	_label.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	_label.position = Vector2(-96.0, 16.0)
	_label.modulate.a = 0.0
	add_child(_label)


func flash() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_label.modulate.a = 1.0
	_tween = create_tween()
	_tween.tween_interval(HOLD_SECONDS)
	_tween.tween_property(_label, "modulate:a", 0.0, FADE_SECONDS)
```

- [ ] **Step 2: Wire it**

In `src/presentation/main.gd`, add the field:

```gdscript
var _save_indicator: SaveIndicator = null
```

build it in `_ready()` alongside the other UI, inside `_ui`:

```gdscript
	_save_indicator = SaveIndicator.new()
	_save_indicator.name = "SaveIndicator"
	_ui.add_child(_save_indicator)
```

and in `_physics_process`, use the value `tick` already returns:

```gdscript
	if _session.tick(delta, _registry):
		_save_indicator.flash()
```

Also flash it on a successful focus-loss save, in `_notification`:

```gdscript
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT and _world != null:
		var errors: PackedStringArray = _session.save_if_gap_elapsed(_registry, "focus_lost")
		for e: String in errors:
			push_error("focus-loss save failed: %s" % e)
		if errors.is_empty():
			_save_indicator.flash()
```

> Deliberately **not** flashed on the quit paths. A "Saved" that appears as
> the window closes is a flicker nobody can read, and Quit to Menu leaves the
> indicator behind with the world.

- [ ] **Step 3: Verify it**

Testing a five-minute autosave by waiting five minutes is not a test. Verify
it against the focus-loss path instead, which uses the same indicator and
fires in seconds:

```bash
./tools/godot.sh --path .
```

New World, walk for more than five seconds (`MIN_SAVE_GAP`), then click away
to another window. "Saved" appears top-right and fades. Click back, walk,
click away again — it fires each time the gap has elapsed and stays silent
when it has not.

- [ ] **Step 4: Commit**

```bash
git add src/ui/save_indicator.gd src/presentation/main.gd
git commit -m "feat: an autosave the player can see"
```

- [ ] **Step 5: Tick the plan**

```bash
python3 tools/mark_task_done.py 10 --plan docs/superpowers/plans/2026-09-14-rp1-phase6-polish-validation.md
git add docs/superpowers/plans/2026-09-14-rp1-phase6-polish-validation.md
git commit -m "docs: tick Phase 6 task 10"
```

---
## Task 11: The zone title card and the controls hint

The last two UI pieces, together because they are the same shape: a label that
appears on entering a world and goes away on its own.

The title card names the place at the moment the player arrives — "Home
Valley" is authored in `zone.json` and persisted in `zone_meta.json`, so it is
right on Continue as well as on New World.

The hint exists for the clean VM in Task 15, where there is nobody to ask which
keys move. It is shown once per player, ever: the flag is the third field in
`settings.json` and the reason that file has a third field at all.

**Files:**
- Create: `src/ui/title_card.gd`
- Create: `src/ui/controls_hint.gd`
- Modify: `src/presentation/main.gd`

**Interfaces:**
- Consumes: `Zone.display_name` (existing), `Settings.controls_hint_shown`
  (Task 6).
- Produces: `TitleCard.show_zone(name: String) -> void`,
  `ControlsHint.show_once() -> void`.

- [ ] **Step 1: Write the title card**

Create `src/ui/title_card.gd`:

```gdscript
class_name TitleCard
extends Control
## The zone's name, on arrival.
##
## No test, for the same reason as the other two: no rules. Whether the
## name is right is ZoneLoader's and SaveManager's business.

const FADE_IN: float = 0.8
const HOLD: float = 2.0
const FADE_OUT: float = 1.2

var _label: Label = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_label = Label.new()
	_label.add_theme_font_size_override("font_size", UiTheme.TITLE_FONT_SIZE)
	_label.add_theme_color_override("font_color", UiTheme.TEXT)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_label.position = Vector2(0.0, 64.0)
	_label.modulate.a = 0.0
	add_child(_label)


func show_zone(zone_name: String) -> void:
	if zone_name == "":
		return
	_label.text = zone_name
	_label.modulate.a = 0.0
	var tween: Tween = create_tween()
	tween.tween_property(_label, "modulate:a", 1.0, FADE_IN)
	tween.tween_interval(HOLD)
	tween.tween_property(_label, "modulate:a", 0.0, FADE_OUT)
```

- [ ] **Step 2: Write the controls hint**

Create `src/ui/controls_hint.gd`:

```gdscript
class_name ControlsHint
extends Control
## WASD / Esc, once per player, ever.
##
## Exists for the clean-machine test, where there is nobody to ask which
## keys move. Whether it has been shown is settings.json's business; this
## node only draws it.

const HOLD: float = 6.0
const FADE_OUT: float = 1.5

var _label: Label = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_label = Label.new()
	_label.text = "WASD or arrows to move    Esc to pause"
	_label.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_label.position = Vector2(0.0, -48.0)
	_label.modulate.a = 0.0
	add_child(_label)


func show_once() -> void:
	_label.modulate.a = 1.0
	var tween: Tween = create_tween()
	tween.tween_interval(HOLD)
	tween.tween_property(_label, "modulate:a", 0.0, FADE_OUT)
```

- [ ] **Step 3: Wire both**

In `src/presentation/main.gd`, add the fields:

```gdscript
var _title_card: TitleCard = null
var _controls_hint: ControlsHint = null
```

build them in `_ready()` inside `_ui`, **before** the pause menu and confirm
panel are added, so neither can draw over a menu:

```gdscript
	_title_card = TitleCard.new()
	_title_card.name = "TitleCard"
	_ui.add_child(_title_card)

	_controls_hint = ControlsHint.new()
	_controls_hint.name = "ControlsHint"
	_ui.add_child(_controls_hint)
```

and in `_enter_world`, after the director enters the zone:

```gdscript
	_title_card.show_zone(result.zone.display_name)
	if not _settings.controls_hint_shown:
		_controls_hint.show_once()
		_settings.controls_hint_shown = true
		_save_settings()
```

The flag is written immediately rather than at un-pause: a player who sees the
hint and then closes the window with the X has still seen it.

- [ ] **Step 4: Play it**

```bash
./tools/godot.sh --path .
```

Delete `settings.json` first so the hint is unseen again:

```bash
rm ~/"Library/Application Support/Godot/app_userdata/RP1/settings.json"
```

New World: "Home Valley" fades in at the top and away; the controls hint sits
at the bottom and fades. Quit to Menu, Continue: the title card appears again
(it belongs to arriving), the hint does not (it belongs to the player).

- [ ] **Step 5: Commit**

```bash
git add src/ui/title_card.gd src/ui/controls_hint.gd src/presentation/main.gd
git commit -m "feat: a title card on arrival and a hint for a first world"
```

- [ ] **Step 6: Tick the plan**

```bash
python3 tools/mark_task_done.py 11 --plan docs/superpowers/plans/2026-09-14-rp1-phase6-polish-validation.md
git add docs/superpowers/plans/2026-09-14-rp1-phase6-polish-validation.md
git commit -m "docs: tick Phase 6 task 11"
```

---

## Task 12: A playtest script for Phase 6

The Phase 5 script exists and works; this is its Phase 6 sibling, written
**before** the play pass rather than after, so the pass has a shape and the
findings have somewhere to go.

**Files:**
- Create: `docs/playtests/YYYY-MM-DD-phase6-playtest.md`, dated the day you run it

- [ ] **Step 1: Write the script**

Model it on `docs/playtests/2026-09-14-phase5-playtest.md`: what is already
covered mechanically, then the sessions that need a person. For Phase 6 the
sessions are:

- **Audio, 10 minutes.** Cadence at a walk; the change between grass and dirt;
  silence when still and when blocked; the bed underneath rather than
  competing; no seam when the bed loops (stand still for a full loop and
  listen for the join); mute silent; the slider audible while dragging.
- **The UI frame, 5 minutes.** The title card on New World and on Continue;
  the hint on a first world only; the save indicator on focus loss and at the
  five-minute autosave.
- **Settings, 5 minutes.** Volume and mute surviving relaunch; surviving New
  World; a hand-corrupted `settings.json` starting the game at defaults rather
  than not starting.
- **The thirty minutes** (Task 13).

Each entry names what would make it a failure, not just what to look at.

- [ ] **Step 2: Commit**

```bash
git add docs/playtests
git commit -m "docs: a Phase 6 playtest script"
```

- [ ] **Step 3: Tick the plan**

```bash
python3 tools/mark_task_done.py 12 --plan docs/superpowers/plans/2026-09-14-rp1-phase6-polish-validation.md
git add docs/superpowers/plans/2026-09-14-rp1-phase6-polish-validation.md
git commit -m "docs: tick Phase 6 task 12"
```

---

## Task 13: The thirty minutes, and the triage that bounds them

The bullet in the whole stage with no natural limit. "Fix what actually
annoys" can absorb a year, so the triage rule is the limit, and **"it annoys
me" is not by itself sufficient to make something Stage 1 work.**

**Files:**
- Create: `docs/playtests/YYYY-MM-DD-phase6-findings.md`, dated the day you run it
- Modify: `IDEAS.md` (for everything triaged there)

- [ ] **Step 1: Play for thirty minutes across several sittings**

Not one sitting. Quit and come back, because the things that annoy on the
third return are different from the ones that annoy in the first ten minutes —
and returning is the thing Stage 1 is actually about.

Write findings down **as they happen**, in a list. Do not fix anything yet:
fixing while playing turns thirty minutes of play into three hours of
debugging and one finding.

- [ ] **Step 2: Triage every finding into exactly one bucket**

In the findings file:

| Bucket | Test | Where it goes |
|---|---|---|
| **Fix now** | It annoys, it is in Stage 1 scope, and it is cheap | Step 3 |
| **`IDEAS.md`** | It is Stage 2 wearing a disguise | `IDEAS.md`, with a line of context |
| **Won't fix** | With the reason written down | Stays in the findings file |

A finding with no bucket is not triaged. The phase does not close with one.

- [ ] **Step 3: Fix the fix-now bucket, TDD where there is a rule**

Anything that is a rule — cadence, a threshold, a condition — gets a failing
test first, in `tests/test_audio_director.gd` or wherever it belongs. Anything
that is a number in `data/` is a JSON edit and needs no test: that is what
putting the mix in data bought.

Commit each fix separately, `fix:` prefixed, naming the finding.

- [ ] **Step 4: Re-run everything**

```bash
./tools/run_tests.sh
./tools/godot.sh --headless --path . -s tools/guard.gd
./tools/godot.sh --headless --path . -s tools/smoke.gd
./tools/check_asset_licences.sh
./tools/check_palette.sh
./tools/check_zone.sh
```
Expected: all six exit 0.

- [ ] **Step 5: Commit the findings**

```bash
git add docs/playtests IDEAS.md
git commit -m "docs: Phase 6 play pass findings, triaged"
```

- [ ] **Step 6: Tick the plan**

```bash
python3 tools/mark_task_done.py 13 --plan docs/superpowers/plans/2026-09-14-rp1-phase6-polish-validation.md
git add docs/superpowers/plans/2026-09-14-rp1-phase6-polish-validation.md
git commit -m "docs: tick Phase 6 task 13"
```

---

## Task 14: The clean-machine test

The bullet that actually finds export bugs. Everything before this proves the
game works *here*, on a machine with Godot, its export templates, and an
import cache built over six phases.

**The artifact under test is the zip CI produced**, not a local export. A
local build shares this machine's import cache, which is exactly the
difference that hides the failure.

**Files:**
- Modify: the findings file from Task 13 (the VM run's results)

- [ ] **Step 1: Build the VM**

A fresh Ubuntu or Windows VM that has never had Godot or its export templates
on it. Snapshot it clean before the first run, so a second attempt starts from
the same place rather than from whatever the first one installed.

- [ ] **Step 2: Fetch the CI artifact**

```bash
gh run list --branch main --limit 1
gh run download <run-id> --name rp1-builds --dir /tmp/rp1-builds
```

Copy that zip to the VM by shared folder or drag-and-drop. Do not build
locally and copy that instead — the point is the artifact a player would get.

- [ ] **Step 3: Run the Stage 1 headline on it**

Launch it, then: New World → walk → quit → relaunch → Continue.

Checked specifically, because these only ever fail in an exported build:

- [ ] **Audio actually plays.** A missing or mis-imported `.ogg` is the
      classic export-only failure, and Phase 6 is the first phase that can
      have one
- [ ] The window opens at a sane size on a display that is not this Mac's
- [ ] The save lands in the OS's real user-data directory
      (`~/.local/share/godot/app_userdata/RP1/` on Linux,
      `%APPDATA%\Godot\app_userdata\RP1\` on Windows) and survives relaunch
- [ ] `settings.json` is written there too, beside `saves/`, not inside it
- [ ] No console spam and no missing-resource errors
- [ ] The controls hint appears — this is its whole reason for existing

- [ ] **Step 4: Record the run**

Append the results to the findings file: VM OS and version, the CI run id the
zip came from, and every one of the six checks with its outcome. A pass with
no record is indistinguishable from not having run it.

Anything that fails here is a Phase 6 bug and is fixed in Phase 6.

- [ ] **Step 5: Commit**

```bash
git add docs/playtests
git commit -m "docs: the clean-machine run"
```

- [ ] **Step 6: Tick the plan**

```bash
python3 tools/mark_task_done.py 14 --plan docs/superpowers/plans/2026-09-14-rp1-phase6-polish-validation.md
git add docs/superpowers/plans/2026-09-14-rp1-phase6-polish-validation.md
git commit -m "docs: tick Phase 6 task 14"
```

---

## Task 15: Close the phase, and close Stage 1

- [ ] **Step 1: Run every gate the way CI runs them**

```bash
./tools/run_tests.sh
./tools/godot.sh --headless --path . -s tools/guard.gd
./tools/godot.sh --headless --path . -s tools/smoke.gd
./tools/check_asset_licences.sh
./tools/check_palette.sh
./tools/check_zone.sh
```
Expected: all six exit 0. The seventh gate is the export job, which runs in
CI and was exercised for real in Task 14.

- [ ] **Step 2: Walk the Stage 1 acceptance criteria, not just Phase 6's**

`docs/superpowers/specs/2026-08-23-rp1-stage0-stage1-design.md` §11 is the
list Stage 1 is measured against, and this is the last chance to walk it.
Record the result of each line. The last one is the real test of whether the
architecture worked:

> **Adding a new tree type is one JSON file plus one PNG, with no code change**

Prove it rather than asserting it: add a tree, see it in the world, then
decide whether to keep it.

- [ ] **Step 3: Mark the spec accepted**

Change the Phase 6 spec's `**Status:** draft` to `**Status:** accepted`, and
update its §13 if anything moved during implementation.

- [ ] **Step 4: Commit**

```bash
git add docs/superpowers/specs/2026-09-14-rp1-phase6-polish-validation-design.md
git commit -m "docs: accept the Phase 6 design"
```

- [ ] **Step 5: Tick the plan**

```bash
python3 tools/mark_task_done.py 15 --plan docs/superpowers/plans/2026-09-14-rp1-phase6-polish-validation.md
git add docs/superpowers/plans/2026-09-14-rp1-phase6-polish-validation.md
git commit -m "docs: tick Phase 6 task 15"
```

- [ ] **Step 6: Tick the Definition of done**

Only once every line below actually holds:

```bash
python3 tools/mark_task_done.py --section "Definition of done" \
  --plan docs/superpowers/plans/2026-09-14-rp1-phase6-polish-validation.md
git add docs/superpowers/plans/2026-09-14-rp1-phase6-polish-validation.md
git commit -m "docs: close Phase 6"
```

---

## Definition of done

- [ ] Footsteps match the terrain underfoot and change when it does
- [ ] No footstep while standing still, none while walking into a solid, and
      no faster cadence on a diagonal
- [ ] The same footstep variation never plays twice in a row
- [ ] The ambient bed loops without an audible seam
- [ ] Quit to Menu stops the bed, and Continue starts it again cleanly —
      one bed playing, never two overlapping, never silence
- [ ] Mute is actually silent, and the volume slider is audible while dragging
- [ ] Volume and mute survive a relaunch, and survive New World
- [ ] A malformed `settings.json` starts the game at defaults
- [ ] `settings.json` is at the `user://` root, not inside `saves/`
- [ ] The save indicator appears on autosave and on a focus-loss save
- [ ] The zone title card shows the authored `display_name` on entry
- [ ] The controls hint appears on a first world and never again
- [ ] Every play-pass finding is triaged to fix-now, `IDEAS.md`, or won't-fix
- [ ] The CI-produced zip runs on a VM that has never had Godot, all the way
      through New World → walk → quit → relaunch → Continue, with audio
- [ ] All seven CI gates green
- [ ] No test writes to `user://saves/` or to the real `user://settings.json`
- [ ] No UI colour outside the Apollo palette
- [ ] Every Stage 1 acceptance criterion in the stage design §11 still holds
