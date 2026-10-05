# Phase 10a — Build Rules and the Mouse Cursor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** In build mode, a left click places the selected wall on the tile
under the mouse and spends its authored cost, a right click removes a built
object and refunds it, and both survive a relaunch.

**Architecture:** `BuildSystem` (`RefCounted`, `src/systems/`) is the single
place that answers *may this edit happen*. It takes a `BuildCommand` value
object and returns a `BuildResult`; `check` asks without writing and `apply`
writes only after `check` accepts, so every refusal precedes the first write.
What is placeable, and what it costs, is the `cost` field on content — no id
or amount is written in GDScript. `BuildCursor` (`src/presentation/`) turns
mouse events into commands and emits them; it tints by calling a probe the
router hands it, so the rule is asked and never re-implemented. `main.gd`
routes commands to `BuildSystem` — presentation emits, the router decides
(spec §3.5). Nothing new is persisted: the chunk reaches disk because its
version moved, the counts because `inventory.json` is written on every save.

**Tech Stack:** Godot 4.7.2 stable (standard build, **not** Mono), GDScript
only, GUT for tests.

**Spec:** `docs/superpowers/specs/2026-09-22-rp1-stage2-design.md` — §3.2
(edits are commands), §3.3 (`cost`), §3.5 (build mode and the cursor), the
Phase 10 entry in §4 as amended 2026-10-05, and acceptance criteria 1, 2, 4
and 11 in §5.

## Global Constraints

- Godot **4.7.2**, standard build. Invoke only through `./tools/godot.sh`.
- GDScript only. No C#. No `TileMap` — `TileMapLayer` only.
- Static typing everywhere: `var x: int = 0`, `func f(a: Vector2i) -> void:`.
- `src/core/` and `src/systems/` **MUST NOT reference Godot nodes.** No
  `extends Node`, no `get_tree()`, no `Engine.`, no `.tscn`. `RefCounted`
  only. Enforced by `tools/guard.gd`.
- Presentation reads from world data. World data never reads from
  presentation. **No presentation node writes to a `Zone` or an `Inventory`**
  — `BuildCursor` emits a command and `main.gd` routes it.
- All game content lives in `data/*.json`. Never `match` over content
  types — look them up in `ContentRegistry`. **No object id, item id or
  amount is written in GDScript under `src/` in this phase**; what a wall
  costs is whatever its JSON says.
- Never use `load()`, `ResourceLoader`, or `.tres`/`.res` for save data.
- Saves persist **string ids**, never runtime numeric ids.
- No save format changes in this phase. `chunk_codec`, `entity_codec`,
  `inventory_codec` and `save_manager` are not modified.
- Palette is fixed. The cursor draws only in colours `UiTheme` already
  declares, fully opaque.
- Run tests with `./tools/run_tests.sh` — never `gut_cmdln.gd` directly. The
  runner does a mandatory `--import` pass first; without it GUT reports missing
  `class_name`s **and exits 0**, so a broken suite looks green.
- TDD: write the failing test, watch it fail, implement minimally, watch it pass.
- Every file in `core/` and `systems/` has a matching test in `tests/`.
  (Value objects — `BuildCommand` and `BuildResult` here, like
  `HarvestResult` — are exercised through the system that uses them.)
- Conventional commit prefixes: `feat:`, `test:`, `ci:`, `docs:`, `fix:`.
- Each task produces two commits: the code, then a `docs:` commit ticking that
  task's checkboxes with `python3 tools/mark_task_done.py <n> --plan <this file>`.
- Godot writes a `.uid` beside every new `.gd` file on the import pass.
  **Commit it with the script**; every existing script's `.uid` is tracked.

## Decisions this plan makes

The spec's Phase 10 entry is five lines. On 2026-10-05 the developer chose:
**split into 10a and 10b**; **floors are a new `floor` content category,
cosmetic, built in 10b**; **chopping stays on `E`**. The spec is amended to
say so. These are the remaining calls, made here so they can be challenged
in review rather than discovered in code:

1. **Placeable means "declares `cost`".** There is no `placeable` flag and no
   list in code. An empty `cost` (`{}`) is valid and means free.
2. **Shipped costs:** `wall_wood` 2 wood, `wall_stone` 2 stone, `door`
   3 wood, `window` 1 wood + 1 stone. Tuning is a JSON edit.
3. **Roofs get no `cost`, so they are not placeable.** A roof is authored as
   a movement-blocking object; placing one without elevation rendering just
   makes a wall with a roof's picture. Parked in `IDEAS.md`.
4. **Removable means the same thing: "declares `cost`".** Build mode cannot
   remove a tree or a rock — that is harvesting, and it would bypass the
   yield. Removing a wall the zone was *authored* with refunds its cost like
   any other; that is salvage, not an exploit worth a provenance column.
5. **The refund is the full cost.** The spec says "refunded on remove" and a
   partial refund is a tuning feature with no consumer yet.
6. **An object may only be placed on an empty object tile whose ground is
   walkable.** No walls on water or on unpainted void. After the "empty"
   check this is exactly `Zone.is_walkable(tile)`, so the walkable rule stays
   in `Walkability` and is not restated.
7. **A movement-blocking object cannot be placed on a tile any entity's body
   overlaps** — the player or an animal. A non-blocking object can. Bodies
   come from the creature definition (`body_width`/`body_height`, falling
   back to `AnimalSystem.DEFAULT_BODY`). `player.json` gains the body
   `Player` already uses, and a test pins the two together.
8. **Reach is unlimited.** Any tile the mouse can point at, in bounds, can be
   edited. A range limit is a survival-game rule; this is a sandbox.
9. **One click, one tile.** No drag-to-paint. Parked in `IDEAS.md`.
10. **Controls:** `B` toggles build mode (the key `debug_place` held).
    Left click places, right click removes, the mouse wheel cycles the
    selection through every placeable in id order. The wheel is 10a's
    stand-in for 10b's palette. `build_mode` has **no gamepad binding** —
    spec §3.5 accepts that debt, and this plan records it in `IDEAS.md`.
11. **`E` still harvests in build mode, and `Esc` still pauses.** Build mode
    adds the mouse; it takes nothing away.
12. **Feedback is a tile outline and one status line.** The outline is
    `UiTheme.ACCENT` when the place command would be accepted and
    `UiTheme.DANGER` when it would not. The status line names the selection,
    its cost and what the player holds. A refused click is silent. The
    palette and a real inventory display are 10b.
13. **`BuildSystem` is all static.** It owns no state — unlike
    `HarvestSystem`, which owns an RNG.
14. **Both debug keys are removed**: `debug_place` (`B`) and `debug_grant`
    (`G`), with their functions and tests, as their own comments promise.

## Known gap, inherited and unchanged

**Chunks have no backup** (see the Phase 9 plan). "Load backup" after
building opens the live chunks with the previous inventory: the wall stands
and its wood is not spent. Phase 9 pinned this with
`test_a_backup_load_keeps_the_harvest_but_not_its_yield`; this phase does
not change it and does not add a second pin for the same gap.

## Review Focus

1. **Clicking where nothing can be built** — outside the zone, on water, on
   unpainted void, on a tree, on an existing wall. Expected: nothing changes
   and nothing is spent — Task 2, `test_a_tile_outside_the_zone_is_refused`,
   `test_water_and_void_are_refused`, `test_an_occupied_tile_is_refused`.
2. **Walling in yourself or a rabbit.** Expected: refused while any body
   overlaps the tile, including a body straddling two tiles — Task 2,
   `test_a_blocking_object_cannot_be_placed_on_an_entity`,
   `test_a_body_straddling_two_tiles_blocks_both`.
3. **Costs arrive from JSON as floats** (`{"wood": 2.0}`), and hand-edited
   content can be wrong in every way (not an object, a misspelt item, a
   creature id, zero, negative, fractional, a string). Expected: whole-number
   floats work; anything else refuses, names the problem, and neither places
   nor refunds — Task 1, `test_every_malformed_cost_is_named`; Task 2,
   `test_a_malformed_cost_places_nothing`; Task 3,
   `test_a_malformed_cost_refunds_nothing`.
4. **Building after the world has already been saved once.** The first save
   writes every chunk; later ones write only chunks whose version moved.
   Expected: a wall removed after the first save is still gone after a
   relaunch — Task 3, `test_a_removal_after_the_first_save_reaches_disk`.
5. **Clicking when build mode should not hear it** — before pressing `B`,
   while paused, after leaving build mode. Expected: nothing happens —
   Task 4, `test_an_inactive_cursor_ignores_clicks`; Task 5's scripted run,
   steps 1, 7 and 10.

---

## File Structure

| File | Responsibility |
|---|---|
| `data/schema/object.json` | **Modify.** `cost` becomes an optional `Dictionary`. |
| `data/object/{wall_wood,wall_stone,door,window}.json` | **Modify.** Each gains a `cost`. |
| `data/creature/player.json` | **Modify.** Gains the body `Player` already uses. |
| `src/systems/build_command.gd` | **Create.** The edit as a value: action, tile, layer, content id. |
| `src/systems/build_result.gd` | **Create.** What `check`/`apply` return: ok or a refusal reason. |
| `src/systems/build_system.gd` | **Create.** `cost_error`, `cost_of`, `placeables`, `check`, `apply`. |
| `src/presentation/build_cursor.gd` | **Create.** Mode toggle, mouse → tile, selection, outline; emits commands. |
| `src/ui/build_status.gd` | **Create.** The one-line readout, and the function that words it. |
| `src/presentation/world.gd` | **Modify.** Owns the cursor; `debug_place` goes. |
| `src/presentation/main.gd` | **Modify.** Routes commands to `BuildSystem`; `debug_grant` goes. |
| `src/ui/controls_hint.gd` | **Modify.** The hint names the new key. |
| `project.godot` | **Modify.** `build_mode` replaces `debug_place`; `debug_grant` removed. |
| `IDEAS.md` | **Modify.** What this phase parks. |

Tests: `tests/test_build_system.gd` (new), `tests/test_build_cursor.gd` (new),
`tests/test_build_status.gd` (new), `tests/test_game_session.gd`,
`tests/test_input_map.gd`.

---

## Task 1: `cost` on content

What a thing costs is authored on the thing. This task makes the field legal,
gives four objects one, and writes the function that says whether a `cost` is
usable — the same shape as Phase 9's `yield_error`, for the same reason: bad
content must fail CI, not a player.

**Files:**
- Create: `src/systems/build_system.gd`
- Create: `tests/test_build_system.gd`
- Modify: `data/schema/object.json`
- Modify: `data/object/wall_wood.json`, `data/object/wall_stone.json`,
  `data/object/door.json`, `data/object/window.json`

**Interfaces:**
- Consumes: `ContentRegistry.numeric_of/def_of/is_placeholder/all_string_ids`,
  `ContentRegistry.ID_UNKNOWN` (existing).
- Produces:
  - `BuildSystem.LAYERS: PackedStringArray` — the layers that can be edited;
    a layer's name is the content category that lives on it. `["object"]`.
  - `BuildSystem.cost_error(cost: Variant, registry: ContentRegistry) -> String`
    — `""` when usable.
  - `BuildSystem.cost_of(def: Dictionary) -> Dictionary` — item id (`String`)
    → amount (`int`). Call only when `cost_error(def["cost"], …)` is `""`.
  - `BuildSystem.placeables(registry: ContentRegistry) -> PackedStringArray`
    — sorted string ids.

- [x] **Step 1: Write the failing tests**

Create `tests/test_build_system.gd`:

```gdscript
extends GutTest
## Building: a command either changes the world and the inventory
## together, or changes neither. Built on a registry assembled here, so no
## test depends on what data/ happens to ship -- except the ones that
## check data/ itself.


func _registry() -> ContentRegistry:
	var r: ContentRegistry = ContentRegistry.new()
	r.register({"id": "grass", "category": "terrain", "display_name": "Grass",
		"sprite": "res://none.png", "walkable": true})
	r.register({"id": "water", "category": "terrain", "display_name": "Water",
		"sprite": "res://none.png", "walkable": false})
	r.register({"id": "wood", "category": "item", "display_name": "Wood"})
	r.register({"id": "stone", "category": "item", "display_name": "Stone"})
	r.register({"id": "rabbit", "category": "creature", "display_name": "Rabbit",
		"sprite": "res://none.png", "body_width": 0.5, "body_height": 0.375})
	r.register({"id": "wall", "category": "object", "display_name": "Wall",
		"sprite": "res://none.png", "blocks_movement": true, "cost": {"wood": 2}})
	r.register({"id": "window", "category": "object", "display_name": "Window",
		"sprite": "res://none.png", "blocks_movement": true,
		"cost": {"wood": 1, "stone": 1}})
	r.register({"id": "rug", "category": "object", "display_name": "Rug",
		"sprite": "res://none.png", "blocks_movement": false, "cost": {"wood": 1}})
	r.register({"id": "tree", "category": "object", "display_name": "Tree",
		"sprite": "res://none.png", "blocks_movement": true})
	return r


# --- cost_error -------------------------------------------------------

func test_a_well_formed_cost_has_no_error() -> void:
	assert_eq(BuildSystem.cost_error({"wood": 2}, _registry()), "")


func test_the_whole_number_floats_json_produces_are_accepted() -> void:
	# JSON.parse hands back 2.0 for a file that says 2.
	assert_eq(BuildSystem.cost_error({"wood": 2.0, "stone": 1.0}, _registry()), "")


func test_an_empty_cost_is_valid_and_means_free() -> void:
	assert_eq(BuildSystem.cost_error({}, _registry()), "")


func test_every_malformed_cost_is_named() -> void:
	var r: ContentRegistry = _registry()
	var _ghost: int = r.register_placeholder("ghost")
	# [the cost value, a fragment the error must contain]
	var cases: Array = [
		["wood", "not an object"],
		[2, "not an object"],
		[{"mithril": 1}, "not in this build"],
		[{"ghost": 1}, "not in this build"],
		[{"rabbit": 1}, "not an item"],
		[{"wall": 1}, "not an item"],
		[{"wood": 1.5}, "whole number"],
		[{"wood": "2"}, "whole number"],
		[{"wood": 0}, "below 1"],
		[{"wood": -1}, "below 1"],
		[{"wood": 2, "stone": 0}, "below 1"],
	]
	for c: Array in cases:
		var err: String = BuildSystem.cost_error(c[0], r)
		assert_string_contains(err, str(c[1]))
		assert_true(err.begins_with("cost"), "'%s' names the field" % err)


func test_cost_of_hands_back_whole_numbers() -> void:
	var cost: Dictionary = BuildSystem.cost_of({"cost": {"wood": 2.0, "stone": 1}})
	assert_eq(cost, {"wood": 2, "stone": 1})
	assert_eq(typeof(cost["wood"]), TYPE_INT)


# --- placeables -------------------------------------------------------

func test_placeables_are_the_content_that_declares_a_cost_in_id_order() -> void:
	# The tree has no cost. Wood is content, but not on a buildable layer.
	assert_eq(BuildSystem.placeables(_registry()),
		PackedStringArray(["rug", "wall", "window"]))


func test_a_placeholder_is_never_placeable() -> void:
	var r: ContentRegistry = _registry()
	var _ghost: int = r.register_placeholder("ghost_wall")
	assert_false(BuildSystem.placeables(r).has("ghost_wall"))


# --- data/ ------------------------------------------------------------

func test_every_shipped_cost_resolves() -> void:
	# The check that makes bad content fail CI instead of failing a player.
	var r: ContentRegistry = ContentRegistry.new()
	var errors: PackedStringArray = r.load_from_dir("res://data")
	assert_eq(errors.size(), 0, "\n".join(errors))
	var checked: int = 0
	for sid: String in r.all_string_ids():
		var def: Dictionary = r.def_of(r.numeric_of(sid))
		if not def.has("cost"):
			continue
		assert_eq(BuildSystem.cost_error(def["cost"], r), "", sid)
		checked += 1
	assert_gt(checked, 0, "the loop must not pass by finding nothing to check")


func test_the_shipped_build_has_something_to_place() -> void:
	var r: ContentRegistry = ContentRegistry.new()
	var _e: PackedStringArray = r.load_from_dir("res://data")
	assert_gt(BuildSystem.placeables(r).size(), 0)
```

- [x] **Step 2: Run the tests to verify they fail**

Run: `./tools/run_tests.sh`
Expected: FAIL — exit 3, `a test script failed to load`, because
`BuildSystem` does not exist yet.

- [x] **Step 3: Write `BuildSystem`'s content half**

Create `src/systems/build_system.gd`:

```gdscript
class_name BuildSystem
extends RefCounted
## Decides whether an edit to the world may happen, and makes it.
##
## What can be built, and what it costs, is authored on the content:
## {"cost": {item id: amount}}. Nothing here names a wall or wood -- a new
## placeable is a data file. All static: this owns no state.

## The layers that can be edited. A layer's name is the content category
## that lives on it, so a definition says where it goes by what it is.
const LAYERS: PackedStringArray = ["object"]


## What is wrong with a `cost` value, or "" if nothing is.
##
## Takes a Variant because that is what content hands over: the schema
## guarantees only that the field is a Dictionary. Amounts may be the
## whole-number floats JSON produces. Every key must be real content of
## the item category -- a cost in an id nothing defines could never be
## paid, and its refund would credit something the build cannot name.
## An empty cost is valid: the thing is free.
static func cost_error(cost: Variant, registry: ContentRegistry) -> String:
	if not (cost is Dictionary):
		return "cost is not an object"
	var entries: Dictionary = cost
	for key: Variant in entries:
		var item_id: String = str(key)
		var item_numeric: int = registry.numeric_of(item_id)
		if item_numeric == ContentRegistry.ID_UNKNOWN or registry.is_placeholder(item_numeric):
			return "cost names '%s', which is not in this build" % item_id
		if str(registry.def_of(item_numeric).get("category", "")) != "item":
			return "cost names '%s', which is not an item" % item_id
		var amount: Variant = entries[key]
		if not (amount is int or amount is float) \
				or not is_equal_approx(float(amount), roundf(float(amount))):
			return "cost of '%s' is not a whole number" % item_id
		if roundi(float(amount)) < 1:
			return "cost of '%s' is below 1" % item_id
	return ""


## The cost of `def` as item id -> whole amount. Only meaningful once
## cost_error() has returned "" for it.
static func cost_of(def: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var entries: Dictionary = def.get("cost", {})
	for key: Variant in entries:
		out[str(key)] = roundi(float(entries[key]))
	return out


## Every string id that can be placed, sorted. Content with a malformed
## cost is still listed: placing it refuses and names the fault, which is
## better than it silently vanishing from the list.
static func placeables(registry: ContentRegistry) -> PackedStringArray:
	var out: PackedStringArray = []
	for string_id: String in registry.all_string_ids():
		var numeric: int = registry.numeric_of(string_id)
		if registry.is_placeholder(numeric):
			continue
		var def: Dictionary = registry.def_of(numeric)
		if def.has("cost") and LAYERS.has(str(def.get("category", ""))):
			out.append(string_id)
	out.sort()
	return out
```

- [x] **Step 4: Make `cost` legal and author it**

In `data/schema/object.json`, change the `optional` block to:

```json
  "optional": {
    "sprite_rect": "Array", "y_offset": "int", "blocks_movement": "bool",
    "blocks_light": "bool", "harvestable": "Dictionary", "cost": "Dictionary",
    "tags": "Array"
  }
```

In each of the four object files, add a `cost` after `tags`. The last line of
each becomes:

`data/object/wall_wood.json`:
```json
 "tags": ["built", "wall"], "cost": {"wood": 2}}
```

`data/object/wall_stone.json`:
```json
 "tags": ["built", "wall"], "cost": {"stone": 2}}
```

`data/object/door.json`:
```json
 "tags": ["built", "door"], "cost": {"wood": 3}}
```

`data/object/window.json`:
```json
 "tags": ["built", "window"], "cost": {"wood": 1, "stone": 1}}
```

`roof_shingle.json` and `roof_thatch.json` are deliberately left alone
(decision 3).

- [x] **Step 5: Run the tests to verify they pass**

Run: `./tools/run_tests.sh`
Expected: PASS, all suites. `test_every_shipped_cost_resolves` checks four
definitions.

To see the schema change is load-bearing, temporarily remove `"cost":
"Dictionary",` from `object.json` and re-run: expected FAIL in
`test_every_shipped_cost_resolves` (and in every other test that loads
`res://data`) with four `unknown field 'cost'` errors. Restore it.

- [x] **Step 6: Commit**

```bash
git add src/systems/build_system.gd src/systems/build_system.gd.uid \
  tests/test_build_system.gd tests/test_build_system.gd.uid \
  data/schema/object.json data/object/wall_wood.json data/object/wall_stone.json \
  data/object/door.json data/object/window.json
git commit -m "feat: placeable content declares its cost"
```

- [x] **Step 7: Tick the task**

```bash
python3 tools/mark_task_done.py 1 --plan docs/superpowers/plans/2026-10-05-rp1-phase10a-build-rules-cursor.md
git add docs/superpowers/plans/2026-10-05-rp1-phase10a-build-rules-cursor.md
git commit -m "docs: tick Phase 10a task 1"
```

---

## Task 2: Placing — `BuildCommand`, `BuildResult`, `check`, `apply`

The rule set for putting something into the world. `check` answers without
writing, which is what lets the cursor tint by asking. `apply` calls `check`
first, so there is exactly one copy of every rule.

**Files:**
- Create: `src/systems/build_command.gd`
- Create: `src/systems/build_result.gd`
- Modify: `src/systems/build_system.gd` — append `check`, `apply` and helpers
- Modify: `data/creature/player.json`
- Test: `tests/test_build_system.gd`

**Interfaces:**
- Consumes: `BuildSystem.LAYERS`, `cost_error`, `cost_of` (Task 1);
  `Zone.in_bounds/get_object/set_object/is_walkable/get_chunk/entities`,
  `EntityStore.ids/get_type_id/get_position`, `Inventory.can_afford/remove`,
  `Walkability.recompute_chunk`, `MovementSystem.body_rect`,
  `AnimalSystem.DEFAULT_BODY`, `Coords.world_to_chunk` (existing).
- Produces:
  - `BuildCommand.PLACE`, `BuildCommand.REMOVE`, `BuildCommand.LAYER_OBJECT`
    (`String` constants); fields `action: String`, `tile: Vector2i`,
    `layer: String`, `content_id: String`.
  - `BuildCommand.place(tile: Vector2i, layer: String, content_id: String) -> BuildCommand`
  - `BuildCommand.remove(tile: Vector2i, layer: String) -> BuildCommand`
  - `BuildResult` reasons: `OUT_OF_BOUNDS`, `BAD_COMMAND`, `NOT_PLACEABLE`,
    `BAD_COST`, `OCCUPIED`, `BAD_GROUND`, `BLOCKED_BY_ENTITY`, `CANT_AFFORD`,
    `NOTHING_THERE`, `NOT_REMOVABLE`; fields `ok: bool`, `reason: String`,
    `detail: String`, `content_id: String`, `cost: Dictionary`.
  - `BuildResult.refusal(reason: String, detail: String = "") -> BuildResult`
  - `BuildResult.accepted(content_id: String, cost: Dictionary) -> BuildResult`
  - `BuildSystem.check(cmd: BuildCommand, zone: Zone, inventory: Inventory, registry: ContentRegistry) -> BuildResult`
  - `BuildSystem.apply(cmd: BuildCommand, zone: Zone, inventory: Inventory, registry: ContentRegistry) -> BuildResult`
  - In this task a `REMOVE` command is refused with `BAD_COMMAND`; Task 3
    replaces that.

- [x] **Step 1: Write the failing tests**

Append to `tests/test_build_system.gd`:

```gdscript


# --- placing ----------------------------------------------------------

const EMPTY: Vector2i = Vector2i(9, 5)
const TREE: Vector2i = Vector2i(5, 5)
const BUILT: Vector2i = Vector2i(7, 5)
const WATER: Vector2i = Vector2i(3, 3)
const VOID: Vector2i = Vector2i(20, 20)
const RABBIT: Vector2i = Vector2i(12, 5)


## One chunk of walkable grass: water at WATER, nothing painted at VOID,
## a tree at TREE, a wall already standing at BUILT, a rabbit on RABBIT.
func _zone(r: ContentRegistry) -> Zone:
	var zone: Zone = Zone.new("fixture", Vector2i(32, 32))
	var grass: int = r.numeric_of("grass")
	for y: int in range(32):
		for x: int in range(32):
			if Vector2i(x, y) != VOID:
				zone.set_terrain(Vector2i(x, y), grass)
	zone.set_terrain(WATER, r.numeric_of("water"))
	zone.set_object(TREE, r.numeric_of("tree"))
	zone.set_object(BUILT, r.numeric_of("wall"))
	var _rabbit: int = zone.entities.spawn(
		r.numeric_of("rabbit"), Vector2(RABBIT) + Vector2(0.5, 0.75))
	var _changed: int = Walkability.recompute_zone(zone, r)
	return zone


func _rich() -> Inventory:
	var inv: Inventory = Inventory.new()
	var _w: bool = inv.add("wood", 10)
	var _s: bool = inv.add("stone", 10)
	return inv


func _counts(inv: Inventory) -> Dictionary:
	var out: Dictionary = {}
	for item_id: String in inv.item_ids():
		out[item_id] = inv.count_of(item_id)
	return out


func _version(zone: Zone) -> int:
	return zone.get_chunk(Vector2i.ZERO).version


func _place(tile: Vector2i, content_id: String) -> BuildCommand:
	return BuildCommand.place(tile, BuildCommand.LAYER_OBJECT, content_id)


## Applies `cmd`, expecting a refusal that changed nothing at all.
func _assert_refused(
	cmd: BuildCommand, reason: String, zone: Zone, inv: Inventory, r: ContentRegistry
) -> BuildResult:
	var version_before: int = _version(zone)
	var counts_before: Dictionary = _counts(inv)
	var result: BuildResult = BuildSystem.apply(cmd, zone, inv, r)
	assert_false(result.ok)
	assert_eq(result.reason, reason)
	assert_eq(_version(zone), version_before, "a refused command writes no tile")
	assert_eq(_counts(inv), counts_before, "a refused command moves no item")
	return result


func test_placing_writes_the_object_and_spends_its_cost() -> void:
	var r: ContentRegistry = _registry()
	var zone: Zone = _zone(r)
	var inv: Inventory = _rich()
	var result: BuildResult = BuildSystem.apply(_place(EMPTY, "wall"), zone, inv, r)
	assert_true(result.ok, result.reason)
	assert_eq(result.reason, "")
	assert_eq(zone.get_object(EMPTY), r.numeric_of("wall"))
	assert_eq(inv.count_of("wood"), 8)
	assert_eq(inv.count_of("stone"), 10)
	assert_eq(result.content_id, "wall")
	assert_eq(result.cost, {"wood": 2})


func test_a_placed_wall_blocks_the_tile() -> void:
	var r: ContentRegistry = _registry()
	var zone: Zone = _zone(r)
	assert_true(zone.is_walkable(EMPTY), "precondition: open ground")
	var _res: BuildResult = BuildSystem.apply(_place(EMPTY, "wall"), zone, _rich(), r)
	assert_false(zone.is_walkable(EMPTY))


func test_placing_advances_the_chunk_version() -> void:
	# That is how the renderer, the collider and the save learn of it.
	var r: ContentRegistry = _registry()
	var zone: Zone = _zone(r)
	var before: int = _version(zone)
	var _res: BuildResult = BuildSystem.apply(_place(EMPTY, "wall"), zone, _rich(), r)
	assert_gt(_version(zone), before)


func test_a_cost_in_two_items_spends_both() -> void:
	var r: ContentRegistry = _registry()
	var zone: Zone = _zone(r)
	var inv: Inventory = _rich()
	var result: BuildResult = BuildSystem.apply(_place(EMPTY, "window"), zone, inv, r)
	assert_true(result.ok, result.reason)
	assert_eq(inv.count_of("wood"), 9)
	assert_eq(inv.count_of("stone"), 9)


func test_exactly_enough_is_enough() -> void:
	var r: ContentRegistry = _registry()
	var zone: Zone = _zone(r)
	var inv: Inventory = Inventory.new()
	var _w: bool = inv.add("wood", 2)
	assert_true(BuildSystem.apply(_place(EMPTY, "wall"), zone, inv, r).ok)
	assert_true(inv.is_empty())


func test_one_short_is_refused() -> void:
	var r: ContentRegistry = _registry()
	var zone: Zone = _zone(r)
	var inv: Inventory = Inventory.new()
	var _w: bool = inv.add("wood", 1)
	var _res: BuildResult = _assert_refused(
		_place(EMPTY, "wall"), BuildResult.CANT_AFFORD, zone, inv, r)
	assert_eq(zone.get_object(EMPTY), ContentRegistry.ID_UNKNOWN)


func test_short_of_one_item_of_two_spends_neither() -> void:
	var r: ContentRegistry = _registry()
	var zone: Zone = _zone(r)
	var inv: Inventory = Inventory.new()
	var _w: bool = inv.add("wood", 5)
	var _res: BuildResult = _assert_refused(
		_place(EMPTY, "window"), BuildResult.CANT_AFFORD, zone, inv, r)


func test_check_answers_without_writing() -> void:
	var r: ContentRegistry = _registry()
	var zone: Zone = _zone(r)
	var inv: Inventory = _rich()
	var before: int = _version(zone)
	var result: BuildResult = BuildSystem.check(_place(EMPTY, "wall"), zone, inv, r)
	assert_true(result.ok)
	assert_eq(result.cost, {"wood": 2})
	assert_eq(_version(zone), before)
	assert_eq(inv.count_of("wood"), 10)
	assert_eq(zone.get_object(EMPTY), ContentRegistry.ID_UNKNOWN)


func test_a_tile_outside_the_zone_is_refused() -> void:
	var r: ContentRegistry = _registry()
	var zone: Zone = _zone(r)
	var inv: Inventory = _rich()
	for tile: Vector2i in [Vector2i(-1, 5), Vector2i(5, -1), Vector2i(32, 5), Vector2i(5, 32)]:
		var _res: BuildResult = _assert_refused(
			_place(tile, "wall"), BuildResult.OUT_OF_BOUNDS, zone, inv, r)


func test_water_and_void_are_refused() -> void:
	var r: ContentRegistry = _registry()
	var zone: Zone = _zone(r)
	var inv: Inventory = _rich()
	for tile: Vector2i in [WATER, VOID]:
		var _res: BuildResult = _assert_refused(
			_place(tile, "wall"), BuildResult.BAD_GROUND, zone, inv, r)
		assert_eq(zone.get_object(tile), ContentRegistry.ID_UNKNOWN)


func test_an_occupied_tile_is_refused() -> void:
	var r: ContentRegistry = _registry()
	var zone: Zone = _zone(r)
	var inv: Inventory = _rich()
	var _a: BuildResult = _assert_refused(
		_place(TREE, "wall"), BuildResult.OCCUPIED, zone, inv, r)
	assert_eq(zone.get_object(TREE), r.numeric_of("tree"), "the tree is untouched")
	var _b: BuildResult = _assert_refused(
		_place(BUILT, "window"), BuildResult.OCCUPIED, zone, inv, r)
	assert_eq(zone.get_object(BUILT), r.numeric_of("wall"), "the wall is not replaced")


func test_only_content_with_a_cost_on_that_layer_is_placeable() -> void:
	var r: ContentRegistry = _registry()
	var _ghost: int = r.register_placeholder("ghost")
	var zone: Zone = _zone(r)
	var inv: Inventory = _rich()
	# nothing named; unknown; a save's leftover; no cost; not an object
	for content_id: String in ["", "mithril_wall", "ghost", "tree", "wood"]:
		var _res: BuildResult = _assert_refused(
			_place(EMPTY, content_id), BuildResult.NOT_PLACEABLE, zone, inv, r)


func test_a_malformed_cost_places_nothing() -> void:
	var r: ContentRegistry = _registry()
	r.register({"id": "broken", "category": "object", "display_name": "Broken",
		"sprite": "res://none.png", "cost": {"mithril": 1}})
	var zone: Zone = _zone(r)
	var result: BuildResult = _assert_refused(
		_place(EMPTY, "broken"), BuildResult.BAD_COST, zone, _rich(), r)
	assert_string_contains(result.detail, "broken")
	assert_string_contains(result.detail, "mithril")


func test_an_unknown_layer_or_action_is_refused() -> void:
	var r: ContentRegistry = _registry()
	var zone: Zone = _zone(r)
	var inv: Inventory = _rich()
	var _a: BuildResult = _assert_refused(
		BuildCommand.place(EMPTY, "ceiling", "wall"), BuildResult.BAD_COMMAND, zone, inv, r)
	var odd: BuildCommand = _place(EMPTY, "wall")
	odd.action = "rotate"
	var _b: BuildResult = _assert_refused(odd, BuildResult.BAD_COMMAND, zone, inv, r)


func test_a_blocking_object_cannot_be_placed_on_an_entity() -> void:
	var r: ContentRegistry = _registry()
	var zone: Zone = _zone(r)
	var _res: BuildResult = _assert_refused(
		_place(RABBIT, "wall"), BuildResult.BLOCKED_BY_ENTITY, zone, _rich(), r)


func test_a_body_straddling_two_tiles_blocks_both() -> void:
	var r: ContentRegistry = _registry()
	var zone: Zone = _zone(r)
	var inv: Inventory = _rich()
	# Feet exactly on the line between x = 15 and x = 16: half a body each side.
	var _id: int = zone.entities.spawn(r.numeric_of("rabbit"), Vector2(16.0, 9.75))
	for tile: Vector2i in [Vector2i(15, 9), Vector2i(16, 9)]:
		var _res: BuildResult = _assert_refused(
			_place(tile, "wall"), BuildResult.BLOCKED_BY_ENTITY, zone, inv, r)
	assert_true(BuildSystem.check(_place(Vector2i(17, 9), "wall"), zone, inv, r).ok,
		"the next tile along is free")


func test_an_object_that_does_not_block_may_go_under_an_entity() -> void:
	var r: ContentRegistry = _registry()
	var zone: Zone = _zone(r)
	var result: BuildResult = BuildSystem.apply(_place(RABBIT, "rug"), zone, _rich(), r)
	assert_true(result.ok, result.reason)
	assert_true(zone.is_walkable(RABBIT), "a rug does not wall the rabbit in")


func test_the_player_definition_carries_the_body_the_player_node_uses() -> void:
	# BuildSystem reads bodies from content; Player moves with its own
	# exported body. If these drift, a wall can be placed across the player.
	var r: ContentRegistry = ContentRegistry.new()
	var _e: PackedStringArray = r.load_from_dir("res://data")
	var def: Dictionary = r.def_of(r.numeric_of("player"))
	var player: Player = autofree(Player.new())
	assert_eq(
		Vector2(float(def.get("body_width", 0.0)), float(def.get("body_height", 0.0))),
		player.body)
```

- [x] **Step 2: Run the tests to verify they fail**

Run: `./tools/run_tests.sh`
Expected: FAIL — exit 3, `a test script failed to load`, because
`BuildCommand` and `BuildResult` do not exist yet.

- [x] **Step 3: Write the two value objects**

Create `src/systems/build_command.gd`:

```gdscript
class_name BuildCommand
extends RefCounted
## One edit to the world, as a value.
##
## An edit is an object rather than a setter call so that it can one day
## be kept: undo is a stack of these (Stage 2 design 3.2). Nothing keeps
## them yet.

const PLACE: String = "place"
const REMOVE: String = "remove"

## A layer is named for the content category that lives on it.
const LAYER_OBJECT: String = "object"

var action: String = PLACE
var tile: Vector2i = Vector2i.ZERO
var layer: String = LAYER_OBJECT

## The string id to place. Empty for a removal, which takes whatever is
## on the tile.
var content_id: String = ""


static func place(p_tile: Vector2i, p_layer: String, p_content_id: String) -> BuildCommand:
	var c: BuildCommand = BuildCommand.new()
	c.action = PLACE
	c.tile = p_tile
	c.layer = p_layer
	c.content_id = p_content_id
	return c


static func remove(p_tile: Vector2i, p_layer: String) -> BuildCommand:
	var c: BuildCommand = BuildCommand.new()
	c.action = REMOVE
	c.tile = p_tile
	c.layer = p_layer
	return c
```

Create `src/systems/build_result.gd`:

```gdscript
class_name BuildResult
extends RefCounted
## What BuildSystem.check and BuildSystem.apply return.
##
## A refusal carries a reason the caller can branch on rather than a
## sentence to parse. BAD_COST and BAD_COMMAND are faults -- content or
## code is wrong -- and they fill `detail`. The others are the player
## pointing at something that cannot be done.

const OUT_OF_BOUNDS: String = "out_of_bounds"
const BAD_COMMAND: String = "bad_command"
const NOT_PLACEABLE: String = "not_placeable"
const BAD_COST: String = "bad_cost"
const OCCUPIED: String = "occupied"
const BAD_GROUND: String = "bad_ground"
const BLOCKED_BY_ENTITY: String = "blocked_by_entity"
const CANT_AFFORD: String = "cant_afford"
const NOTHING_THERE: String = "nothing_there"
const NOT_REMOVABLE: String = "not_removable"

var ok: bool = false

## Empty when `ok`; otherwise one of the constants above.
var reason: String = ""
var detail: String = ""

## Only meaningful when `ok`: the string id placed or removed, and the
## items it spends (a placement) or gives back (a removal), id -> amount.
var content_id: String = ""
var cost: Dictionary = {}


static func refusal(p_reason: String, p_detail: String = "") -> BuildResult:
	var r: BuildResult = BuildResult.new()
	r.reason = p_reason
	r.detail = p_detail
	return r


static func accepted(p_content_id: String, p_cost: Dictionary) -> BuildResult:
	var r: BuildResult = BuildResult.new()
	r.ok = true
	r.content_id = p_content_id
	r.cost = p_cost
	return r
```

- [x] **Step 4: Write `check` and `apply`**

Append to `src/systems/build_system.gd`:

```gdscript


## Whether `cmd` may happen, without making it happen. The cursor asks
## this every frame, so it must never write.
static func check(
	cmd: BuildCommand, zone: Zone, inventory: Inventory, registry: ContentRegistry
) -> BuildResult:
	if not zone.in_bounds(cmd.tile):
		return BuildResult.refusal(BuildResult.OUT_OF_BOUNDS)
	if not LAYERS.has(cmd.layer):
		return BuildResult.refusal(
			BuildResult.BAD_COMMAND, "unknown layer '%s'" % cmd.layer)
	if cmd.action == BuildCommand.PLACE:
		return _check_place(cmd, zone, inventory, registry)
	return BuildResult.refusal(
		BuildResult.BAD_COMMAND, "unknown action '%s'" % cmd.action)


## Makes `cmd` happen if check() accepts it.
##
## Every refusal returns before the first write, so a refused command
## changes no tile, no flag and no count. The tile is written through
## Zone.set_object, which advances the chunk's version: that is how the
## renderer, the collider and the save each learn of it, with nothing
## here knowing they exist.
static func apply(
	cmd: BuildCommand, zone: Zone, inventory: Inventory, registry: ContentRegistry
) -> BuildResult:
	var result: BuildResult = check(cmd, zone, inventory, registry)
	if not result.ok:
		return result
	for item_id: String in result.cost:
		# Cannot refuse: check() proved the whole cost affordable.
		var _spent: bool = inventory.remove(item_id, int(result.cost[item_id]))
	zone.set_object(cmd.tile, registry.numeric_of(cmd.content_id))
	# Walkability owns the walkable rule; setting the flag byte by hand
	# would also clobber FLAG_BLOCKS_LIGHT, which shares it.
	var _changed: int = Walkability.recompute_chunk(
		zone.get_chunk(Coords.world_to_chunk(cmd.tile)), registry)
	return result


static func _check_place(
	cmd: BuildCommand, zone: Zone, inventory: Inventory, registry: ContentRegistry
) -> BuildResult:
	var numeric: int = registry.numeric_of(cmd.content_id)
	if numeric == ContentRegistry.ID_UNKNOWN or registry.is_placeholder(numeric):
		return BuildResult.refusal(BuildResult.NOT_PLACEABLE)
	var def: Dictionary = registry.def_of(numeric)
	if str(def.get("category", "")) != cmd.layer or not def.has("cost"):
		return BuildResult.refusal(BuildResult.NOT_PLACEABLE)
	var problem: String = cost_error(def["cost"], registry)
	if problem != "":
		return BuildResult.refusal(
			BuildResult.BAD_COST, "%s: %s" % [cmd.content_id, problem])

	if zone.get_object(cmd.tile) != ContentRegistry.ID_UNKNOWN:
		return BuildResult.refusal(BuildResult.OCCUPIED)
	# With no object on the tile, its walkable flag is the terrain's
	# answer alone: water and unpainted void are not ground to build on.
	if not zone.is_walkable(cmd.tile):
		return BuildResult.refusal(BuildResult.BAD_GROUND)
	if bool(def.get("blocks_movement", false)) and _entity_on(zone, cmd.tile, registry):
		return BuildResult.refusal(BuildResult.BLOCKED_BY_ENTITY)

	var cost: Dictionary = cost_of(def)
	if not inventory.can_afford(cost):
		return BuildResult.refusal(BuildResult.CANT_AFFORD)
	return BuildResult.accepted(cmd.content_id, cost)


## Whether any entity's body overlaps `tile`. A solid dropped across a
## body would trap it inside something it cannot walk out of.
static func _entity_on(zone: Zone, tile: Vector2i, registry: ContentRegistry) -> bool:
	var tile_rect: Rect2 = Rect2(Vector2(tile), Vector2.ONE)
	for id: int in zone.entities.ids():
		var def: Dictionary = registry.def_of(zone.entities.get_type_id(id))
		var body: Vector2 = Vector2(
			float(def.get("body_width", AnimalSystem.DEFAULT_BODY.x)),
			float(def.get("body_height", AnimalSystem.DEFAULT_BODY.y)))
		if tile_rect.intersects(
				MovementSystem.body_rect(zone.entities.get_position(id), body)):
			return true
	return false
```

- [x] **Step 5: Give the player definition its body**

Replace `data/creature/player.json` with (the values are `Player.body`'s
defaults, `Vector2(0.625, 0.5)`):

```json
{"id": "player", "category": "creature", "display_name": "Player",
 "sprite": "res://assets/characters/player.png",
 "body_width": 0.625, "body_height": 0.5, "tags": ["player"]}
```

- [x] **Step 6: Run the tests to verify they pass**

Run: `./tools/run_tests.sh`
Expected: PASS, all suites — including every existing animal, player-spawn
and session test, which prove the player definition's new fields change
nothing that reads it today.

Run: `./tools/godot.sh --headless --path . -s tools/guard.gd`
Expected: `Architecture guard: clean`, exit 0.

- [x] **Step 7: Commit**

```bash
git add src/systems/build_command.gd src/systems/build_command.gd.uid \
  src/systems/build_result.gd src/systems/build_result.gd.uid \
  src/systems/build_system.gd tests/test_build_system.gd data/creature/player.json
git commit -m "feat: BuildSystem places content and spends its cost"
```

- [x] **Step 8: Tick the task**

```bash
python3 tools/mark_task_done.py 2 --plan docs/superpowers/plans/2026-10-05-rp1-phase10a-build-rules-cursor.md
git add docs/superpowers/plans/2026-10-05-rp1-phase10a-build-rules-cursor.md
git commit -m "docs: tick Phase 10a task 2"
```

---

## Task 3: Removing, and proof that both directions persist

The other half of the command, and the phase's "done when" as tests: a
placed wall and a removed wall each survive a save, a close and a reopen
with the inventory to match.

**Files:**
- Modify: `src/systems/build_system.gd` — `check`, `apply`, new `_check_remove`
- Test: `tests/test_build_system.gd`, `tests/test_game_session.gd`

**Interfaces:**
- Consumes: everything Task 2 produced; `Inventory.add`;
  `ContentRegistry.string_of`; `GameSession.zone/inventory/save_now/close/open_saved`
  and the test helpers `_opened()` and `_session()` already in
  `tests/test_game_session.gd`.
- Produces: `BuildSystem.check`/`apply` accept `BuildCommand.REMOVE`. On
  success `BuildResult.content_id` is the string id removed and
  `BuildResult.cost` is what was refunded.

- [ ] **Step 1: Write the failing tests**

Append to `tests/test_build_system.gd`:

```gdscript


# --- removing ---------------------------------------------------------

func _remove(tile: Vector2i) -> BuildCommand:
	return BuildCommand.remove(tile, BuildCommand.LAYER_OBJECT)


func test_removing_clears_the_object_and_refunds_its_cost() -> void:
	var r: ContentRegistry = _registry()
	var zone: Zone = _zone(r)
	var inv: Inventory = Inventory.new()
	var result: BuildResult = BuildSystem.apply(_remove(BUILT), zone, inv, r)
	assert_true(result.ok, result.reason)
	assert_eq(zone.get_object(BUILT), ContentRegistry.ID_UNKNOWN)
	assert_eq(inv.count_of("wood"), 2)
	assert_eq(result.content_id, "wall")
	assert_eq(result.cost, {"wood": 2})


func test_the_cleared_tile_becomes_walkable() -> void:
	var r: ContentRegistry = _registry()
	var zone: Zone = _zone(r)
	assert_false(zone.is_walkable(BUILT), "precondition: the wall blocks")
	var _res: BuildResult = BuildSystem.apply(_remove(BUILT), zone, Inventory.new(), r)
	assert_true(zone.is_walkable(BUILT))


func test_place_then_remove_leaves_everything_as_it_was() -> void:
	var r: ContentRegistry = _registry()
	var zone: Zone = _zone(r)
	var inv: Inventory = _rich()
	var before: Dictionary = _counts(inv)
	assert_true(BuildSystem.apply(_place(EMPTY, "window"), zone, inv, r).ok)
	assert_true(BuildSystem.apply(_remove(EMPTY), zone, inv, r).ok)
	assert_eq(zone.get_object(EMPTY), ContentRegistry.ID_UNKNOWN)
	assert_true(zone.is_walkable(EMPTY))
	assert_eq(_counts(inv), before)


func test_removing_needs_nothing_in_the_inventory() -> void:
	# A removal is never unaffordable, and its check says so without writing.
	var r: ContentRegistry = _registry()
	var zone: Zone = _zone(r)
	var before: int = _version(zone)
	assert_true(BuildSystem.check(_remove(BUILT), zone, Inventory.new(), r).ok)
	assert_eq(_version(zone), before)
	assert_eq(zone.get_object(BUILT), r.numeric_of("wall"))


func test_an_empty_tile_has_nothing_to_remove() -> void:
	var r: ContentRegistry = _registry()
	var zone: Zone = _zone(r)
	var _res: BuildResult = _assert_refused(
		_remove(EMPTY), BuildResult.NOTHING_THERE, zone, _rich(), r)


func test_a_tree_is_harvested_not_removed() -> void:
	var r: ContentRegistry = _registry()
	var zone: Zone = _zone(r)
	var _res: BuildResult = _assert_refused(
		_remove(TREE), BuildResult.NOT_REMOVABLE, zone, _rich(), r)
	assert_eq(zone.get_object(TREE), r.numeric_of("tree"))


func test_content_this_build_cannot_name_is_not_removable() -> void:
	# A placeholder keeps its tile so the save round-trips; build mode
	# deleting it would be the silent zeroing the save rules forbid.
	var r: ContentRegistry = _registry()
	var zone: Zone = _zone(r)
	var ghost: int = r.register_placeholder("ghost_wall")
	zone.set_object(EMPTY, ghost)
	var _res: BuildResult = _assert_refused(
		_remove(EMPTY), BuildResult.NOT_REMOVABLE, zone, _rich(), r)
	assert_eq(zone.get_object(EMPTY), ghost)


func test_a_malformed_cost_refunds_nothing() -> void:
	var r: ContentRegistry = _registry()
	var broken: int = r.register({"id": "broken", "category": "object",
		"display_name": "Broken", "sprite": "res://none.png", "cost": {"wood": -3}})
	var zone: Zone = _zone(r)
	zone.set_object(EMPTY, broken)
	var result: BuildResult = _assert_refused(
		_remove(EMPTY), BuildResult.BAD_COST, zone, _rich(), r)
	assert_string_contains(result.detail, "broken")
	assert_eq(zone.get_object(EMPTY), broken)


func test_removing_outside_the_zone_is_refused() -> void:
	var r: ContentRegistry = _registry()
	var zone: Zone = _zone(r)
	var _res: BuildResult = _assert_refused(
		_remove(Vector2i(-1, 0)), BuildResult.OUT_OF_BOUNDS, zone, _rich(), r)
```

Append to `tests/test_game_session.gd`:

```gdscript


# --- building ---------------------------------------------------------

func _place_cmd(tile: Vector2i, content_id: String) -> BuildCommand:
	return BuildCommand.place(tile, BuildCommand.LAYER_OBJECT, content_id)


## Credits `times` multiples of what `content_id` costs, and returns the
## cost of one.
func _grant_cost(s: GameSession, content_id: String, times: int) -> Dictionary:
	var cost: Dictionary = BuildSystem.cost_of(
		_registry.def_of(_registry.numeric_of(content_id)))
	for item_id: String in cost:
		var _added: bool = s.inventory.add(item_id, int(cost[item_id]) * times)
	return cost


## The first tile of the authored zone where `content_id` may be placed.
func _first_buildable(s: GameSession, content_id: String) -> Vector2i:
	for y: int in range(s.zone.size_tiles.y):
		for x: int in range(s.zone.size_tiles.x):
			var tile: Vector2i = Vector2i(x, y)
			if BuildSystem.check(
					_place_cmd(tile, content_id), s.zone, s.inventory, _registry).ok:
				return tile
	return Vector2i(-1, -1)


func test_a_placed_object_survives_a_relaunch_and_its_cost_stays_spent() -> void:
	# The phase's "done when": place, relaunch, still there, still paid for.
	var first: GameSession = _opened()
	var content_id: String = BuildSystem.placeables(_registry)[0]
	var cost: Dictionary = _grant_cost(first, content_id, 3)
	var tile: Vector2i = _first_buildable(first, content_id)
	assert_true(first.zone.in_bounds(tile), "the authored zone has somewhere to build")
	var got: BuildResult = BuildSystem.apply(
		_place_cmd(tile, content_id), first.zone, first.inventory, _registry)
	assert_true(got.ok, got.reason)
	assert_eq(first.save_now(_registry, "quit").size(), 0)
	first.close()

	var second: GameSession = _session()
	var r: SessionOpenResult = second.open_saved(_registry)
	assert_true(r.ok, r.error)
	assert_eq(_registry.string_of(second.zone.get_object(tile)), content_id,
		"the placed object is still there")
	for item_id: String in cost:
		assert_eq(second.inventory.count_of(item_id), int(cost[item_id]) * 2,
			"%s: one cost of three was spent" % item_id)


func test_a_removal_after_the_first_save_reaches_disk() -> void:
	# The first save writes every chunk. The second is incremental: it must
	# write the edited chunk because its version moved again.
	var first: GameSession = _opened()
	var content_id: String = BuildSystem.placeables(_registry)[0]
	var cost: Dictionary = _grant_cost(first, content_id, 3)
	var tile: Vector2i = _first_buildable(first, content_id)
	assert_true(BuildSystem.apply(
		_place_cmd(tile, content_id), first.zone, first.inventory, _registry).ok)
	assert_eq(first.save_now(_registry, "new_world").size(), 0)
	var removed: BuildResult = BuildSystem.apply(
		BuildCommand.remove(tile, BuildCommand.LAYER_OBJECT),
		first.zone, first.inventory, _registry)
	assert_true(removed.ok, removed.reason)
	assert_eq(first.save_now(_registry, "autosave").size(), 0)
	first.close()

	var second: GameSession = _session()
	assert_true(second.open_saved(_registry).ok)
	assert_eq(second.zone.get_object(tile), ContentRegistry.ID_UNKNOWN,
		"the removed object did not come back")
	for item_id: String in cost:
		assert_eq(second.inventory.count_of(item_id), int(cost[item_id]) * 3,
			"%s: the refund was saved" % item_id)
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `./tools/run_tests.sh`
Expected: FAIL. The new removal tests in `test_build_system.gd` fail on
`bad_command` where they expected `ok` or another reason — all but
`test_removing_outside_the_zone_is_refused`, which passes already because
the bounds check comes first — and
`test_a_removal_after_the_first_save_reaches_disk` fails on `bad_command`.
`test_a_placed_object_survives_a_relaunch_and_its_cost_stays_spent`
**passes already** — Task 2 built placing, and the save path needs nothing
new. That is the claim "nothing new is persisted" holding.

- [ ] **Step 3: Implement removal**

In `src/systems/build_system.gd`, in `check`, replace:

```gdscript
	if cmd.action == BuildCommand.PLACE:
		return _check_place(cmd, zone, inventory, registry)
	return BuildResult.refusal(
```

with:

```gdscript
	if cmd.action == BuildCommand.PLACE:
		return _check_place(cmd, zone, inventory, registry)
	if cmd.action == BuildCommand.REMOVE:
		return _check_remove(cmd, zone, registry)
	return BuildResult.refusal(
```

In `apply`, replace everything from `for item_id: String in result.cost:`
down to and including the `zone.set_object(...)` line with:

```gdscript
	if cmd.action == BuildCommand.PLACE:
		for item_id: String in result.cost:
			# Cannot refuse: check() proved the whole cost affordable.
			var _spent: bool = inventory.remove(item_id, int(result.cost[item_id]))
		zone.set_object(cmd.tile, registry.numeric_of(cmd.content_id))
	else:
		zone.set_object(cmd.tile, ContentRegistry.ID_UNKNOWN)
		for item_id: String in result.cost:
			# Cannot refuse: cost_error guaranteed an id and an amount of
			# at least 1.
			var _refunded: bool = inventory.add(item_id, int(result.cost[item_id]))
```

The `Walkability.recompute_chunk` call and `return result` below it stay.

Directly after `_check_place`, add:

```gdscript


## Only what build mode could have placed can be removed by it: content
## that declares a cost. A tree leaves the world through HarvestSystem,
## which is where its yield is decided.
static func _check_remove(
	cmd: BuildCommand, zone: Zone, registry: ContentRegistry
) -> BuildResult:
	var obj: int = zone.get_object(cmd.tile)
	if obj == ContentRegistry.ID_UNKNOWN:
		return BuildResult.refusal(BuildResult.NOTHING_THERE)
	var def: Dictionary = registry.def_of(obj)
	if registry.is_placeholder(obj) or not def.has("cost"):
		return BuildResult.refusal(BuildResult.NOT_REMOVABLE)
	var object_id: String = registry.string_of(obj)
	var problem: String = cost_error(def["cost"], registry)
	if problem != "":
		return BuildResult.refusal(
			BuildResult.BAD_COST, "%s: %s" % [object_id, problem])
	return BuildResult.accepted(object_id, cost_of(def))
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `./tools/run_tests.sh`
Expected: PASS, all suites.

Run: `./tools/godot.sh --headless --path . -s tools/guard.gd`
Expected: `Architecture guard: clean`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add src/systems/build_system.gd tests/test_build_system.gd tests/test_game_session.gd
git commit -m "feat: BuildSystem removes built content and refunds it"
```

- [ ] **Step 6: Tick the task**

```bash
python3 tools/mark_task_done.py 3 --plan docs/superpowers/plans/2026-10-05-rp1-phase10a-build-rules-cursor.md
git add docs/superpowers/plans/2026-10-05-rp1-phase10a-build-rules-cursor.md
git commit -m "docs: tick Phase 10a task 3"
```

---

## Task 4: `BuildCursor`, and the key that turns it on

The project's first mouse gameplay input. The cursor hears `B`, maps the
mouse to a tile, keeps the selection, draws the outline and emits commands.
It decides nothing: whether a command is acceptable is a `probe` the router
supplies, and until Task 5 supplies one the outline is always the refused
colour and a click changes nothing.

`World` is `PROCESS_MODE_PAUSABLE` and the cursor is its child, so the
cursor hears nothing while paused and does not exist at the menu.

**Files:**
- Create: `src/presentation/build_cursor.gd`
- Create: `tests/test_build_cursor.gd`
- Modify: `src/presentation/world.gd` — owns the cursor; `debug_place` goes
- Modify: `project.godot` — `[input]`: `build_mode` replaces `debug_place`
- Modify: `IDEAS.md`
- Test: `tests/test_input_map.gd`

**Interfaces:**
- Consumes: `BuildCommand.place/remove`, `BuildCommand.LAYER_OBJECT`,
  `BuildSystem.placeables` (Tasks 1–2); `TilesetBuilder.TILE_SIZE`,
  `UiTheme.ACCENT`, `UiTheme.DANGER` (existing).
- Produces:
  - the `build_mode` input action (`B`, keyboard only)
  - `World.build_cursor: BuildCursor` — non-null once `World.build()` returns
  - `BuildCursor.active: bool` (read it; change it with `set_active`)
  - `BuildCursor.probe: Callable` — `func(cmd: BuildCommand) -> bool`
  - `BuildCursor.setup(registry: ContentRegistry) -> void`
  - `BuildCursor.selected_id() -> String` — `""` when nothing is placeable
  - `BuildCursor.set_active(value: bool) -> void`
  - `BuildCursor.step_selection(delta: int) -> void`
  - `BuildCursor.place_command(tile: Vector2i) -> BuildCommand` — `null` when
    nothing is selected
  - `static BuildCursor.tile_at(world_px: Vector2) -> Vector2i`
  - signals `build_requested(cmd: BuildCommand)`, `mode_changed(active: bool)`,
    `selection_changed(content_id: String)`

- [ ] **Step 1: Write the failing tests**

Create `tests/test_build_cursor.gd`:

```gdscript
extends GutTest
## The build cursor turns mouse events into commands. It holds no rule
## about what may be built -- that is BuildSystem's, and tested there.


func _registry() -> ContentRegistry:
	var r: ContentRegistry = ContentRegistry.new()
	r.register({"id": "wood", "category": "item", "display_name": "Wood"})
	r.register({"id": "wall", "category": "object", "display_name": "Wall",
		"sprite": "res://none.png", "cost": {"wood": 2}})
	r.register({"id": "rug", "category": "object", "display_name": "Rug",
		"sprite": "res://none.png", "cost": {"wood": 1}})
	r.register({"id": "tree", "category": "object", "display_name": "Tree",
		"sprite": "res://none.png"})
	return r


func _cursor(r: ContentRegistry) -> BuildCursor:
	var cursor: BuildCursor = BuildCursor.new()
	add_child_autofree(cursor)
	cursor.setup(r)
	watch_signals(cursor)
	return cursor


## A press of `button` on the middle of `tile`, delivered straight to the
## cursor. The position is mapped through the same transforms the engine
## applies, so the test does not assume the runner's viewport is unmoved.
func _click(cursor: BuildCursor, button: MouseButton, tile: Vector2i) -> void:
	var world_px: Vector2 = (Vector2(tile) + Vector2(0.5, 0.5)) \
		* Vector2(TilesetBuilder.TILE_SIZE)
	var ev: InputEventMouseButton = InputEventMouseButton.new()
	ev.button_index = button
	ev.pressed = true
	ev.position = cursor.get_viewport().get_canvas_transform() \
		* cursor.get_global_transform() * world_px
	cursor._unhandled_input(ev)


func _press_build_mode(cursor: BuildCursor) -> void:
	var ev: InputEventAction = InputEventAction.new()
	ev.action = "build_mode"
	ev.pressed = true
	cursor._unhandled_input(ev)


# --- mouse to tile ----------------------------------------------------

func test_a_pixel_maps_to_the_tile_that_contains_it() -> void:
	assert_eq(BuildCursor.tile_at(Vector2(0.0, 0.0)), Vector2i(0, 0))
	assert_eq(BuildCursor.tile_at(Vector2(31.9, 31.9)), Vector2i(0, 0))
	assert_eq(BuildCursor.tile_at(Vector2(32.0, 64.0)), Vector2i(1, 2))
	assert_eq(BuildCursor.tile_at(Vector2(1040.0, 816.0)), Vector2i(32, 25))


func test_a_pixel_left_of_or_above_the_zone_maps_outside_it() -> void:
	# Truncating instead of flooring would fold -0.5 onto tile 0 and let a
	# click outside the zone edit its first column.
	assert_eq(BuildCursor.tile_at(Vector2(-0.5, -0.5)), Vector2i(-1, -1))
	assert_eq(BuildCursor.tile_at(Vector2(-32.0, 5.0)), Vector2i(-1, 0))


# --- selection --------------------------------------------------------

func test_the_first_placeable_is_selected_to_begin_with() -> void:
	assert_eq(_cursor(_registry()).selected_id(), "rug")


func test_stepping_the_selection_wraps_both_ways() -> void:
	var cursor: BuildCursor = _cursor(_registry())
	cursor.step_selection(1)
	assert_eq(cursor.selected_id(), "wall")
	assert_signal_emitted_with_parameters(cursor, "selection_changed", ["wall"])
	cursor.step_selection(1)
	assert_eq(cursor.selected_id(), "rug")
	cursor.step_selection(-1)
	assert_eq(cursor.selected_id(), "wall")


func test_a_build_with_nothing_placeable_selects_nothing() -> void:
	var r: ContentRegistry = ContentRegistry.new()
	var cursor: BuildCursor = _cursor(r)
	assert_eq(cursor.selected_id(), "")
	assert_null(cursor.place_command(Vector2i(1, 1)))
	cursor.step_selection(1)
	assert_signal_not_emitted(cursor, "selection_changed")


func test_a_place_command_carries_the_layer_its_content_lives_on() -> void:
	var cmd: BuildCommand = _cursor(_registry()).place_command(Vector2i(4, 7))
	assert_eq(cmd.action, BuildCommand.PLACE)
	assert_eq(cmd.tile, Vector2i(4, 7))
	assert_eq(cmd.content_id, "rug")
	assert_eq(cmd.layer, BuildCommand.LAYER_OBJECT)


# --- mode -------------------------------------------------------------

func test_the_cursor_starts_inactive() -> void:
	assert_false(_cursor(_registry()).active)


func test_the_build_mode_action_toggles_it() -> void:
	var cursor: BuildCursor = _cursor(_registry())
	_press_build_mode(cursor)
	assert_true(cursor.active)
	assert_signal_emitted_with_parameters(cursor, "mode_changed", [true])
	_press_build_mode(cursor)
	assert_false(cursor.active)
	assert_signal_emitted_with_parameters(cursor, "mode_changed", [false])


func test_an_inactive_cursor_ignores_clicks() -> void:
	var cursor: BuildCursor = _cursor(_registry())
	_click(cursor, MOUSE_BUTTON_LEFT, Vector2i(3, 3))
	_click(cursor, MOUSE_BUTTON_RIGHT, Vector2i(3, 3))
	_click(cursor, MOUSE_BUTTON_WHEEL_DOWN, Vector2i(3, 3))
	assert_signal_not_emitted(cursor, "build_requested")
	assert_eq(cursor.selected_id(), "rug")


# --- clicks -----------------------------------------------------------

func test_a_left_click_asks_to_place_the_selection_under_the_mouse() -> void:
	var cursor: BuildCursor = _cursor(_registry())
	cursor.set_active(true)
	_click(cursor, MOUSE_BUTTON_LEFT, Vector2i(6, 2))
	assert_signal_emit_count(cursor, "build_requested", 1)
	var cmd: BuildCommand = get_signal_parameters(cursor, "build_requested")[0]
	assert_eq(cmd.action, BuildCommand.PLACE)
	assert_eq(cmd.tile, Vector2i(6, 2))
	assert_eq(cmd.content_id, "rug")


func test_a_right_click_asks_to_remove_what_is_under_the_mouse() -> void:
	var cursor: BuildCursor = _cursor(_registry())
	cursor.set_active(true)
	_click(cursor, MOUSE_BUTTON_RIGHT, Vector2i(6, 2))
	var cmd: BuildCommand = get_signal_parameters(cursor, "build_requested")[0]
	assert_eq(cmd.action, BuildCommand.REMOVE)
	assert_eq(cmd.tile, Vector2i(6, 2))
	assert_eq(cmd.layer, BuildCommand.LAYER_OBJECT)
	assert_eq(cmd.content_id, "")


func test_the_wheel_steps_the_selection() -> void:
	var cursor: BuildCursor = _cursor(_registry())
	cursor.set_active(true)
	_click(cursor, MOUSE_BUTTON_WHEEL_DOWN, Vector2i(0, 0))
	assert_eq(cursor.selected_id(), "wall")
	_click(cursor, MOUSE_BUTTON_WHEEL_UP, Vector2i(0, 0))
	assert_eq(cursor.selected_id(), "rug")
	assert_signal_not_emitted(cursor, "build_requested")


func test_with_nothing_to_place_a_left_click_asks_for_nothing() -> void:
	var cursor: BuildCursor = _cursor(ContentRegistry.new())
	cursor.set_active(true)
	_click(cursor, MOUSE_BUTTON_LEFT, Vector2i(6, 2))
	assert_signal_not_emitted(cursor, "build_requested")


func test_the_cursor_never_decides_on_its_own() -> void:
	# No probe is set, so the cursor cannot know whether the command is
	# acceptable -- and it emits anyway. The router decides.
	var cursor: BuildCursor = _cursor(_registry())
	cursor.set_active(true)
	_click(cursor, MOUSE_BUTTON_LEFT, Vector2i(-3, -3))
	assert_signal_emit_count(cursor, "build_requested", 1)
```

In `tests/test_input_map.gd`, append:

```gdscript


func test_the_build_mode_action_is_bound_to_b() -> void:
	assert_true(InputMap.has_action("build_mode"))
	var found: bool = false
	for event: InputEvent in InputMap.action_get_events("build_mode"):
		if event is InputEventKey and (event as InputEventKey).physical_keycode == KEY_B:
			found = true
	assert_true(found, "build_mode is not bound to B")


func test_the_debug_place_action_is_gone() -> void:
	# It held B and placed a free wall. Build mode replaced it.
	assert_false(InputMap.has_action("debug_place"))
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `./tools/run_tests.sh`
Expected: FAIL — exit 3, `a test script failed to load`, because
`BuildCursor` does not exist yet.

- [ ] **Step 3: Write the cursor**

Create `src/presentation/build_cursor.gd`:

```gdscript
class_name BuildCursor
extends Node2D
## Build mode's mouse: which tile, which content, and the click.
##
## It emits intent and decides nothing. Whether a command may happen is
## BuildSystem's rule; this asks it through `probe`, which the router
## supplies, and never restates it (Stage 2 design 3.5). It reads the
## registry to know what can be selected and writes to nothing.
##
## This is the project's first mouse gameplay input, and it has no
## controller path. That debt is accepted in the design and listed in
## IDEAS.md.

## A command to place or remove. The router applies it, or refuses.
signal build_requested(cmd: BuildCommand)
signal mode_changed(active: bool)
signal selection_changed(content_id: String)

## func(cmd: BuildCommand) -> bool: would this command be accepted? Only
## the outline's colour depends on it. Unset, the outline reads refused.
var probe: Callable = Callable()

## Read this; change it with set_active() so the signal fires.
var active: bool = false

var _registry: ContentRegistry = null
var _placeables: PackedStringArray = []
var _index: int = 0
var _tile: Vector2i = Vector2i.ZERO
var _accepted: bool = false


## The tile containing a point in world pixels. Floored, not truncated:
## a point just left of the zone is tile -1, not tile 0.
static func tile_at(world_px: Vector2) -> Vector2i:
	return Vector2i(
		floori(world_px.x / TilesetBuilder.TILE_SIZE.x),
		floori(world_px.y / TilesetBuilder.TILE_SIZE.y))


func setup(registry: ContentRegistry) -> void:
	_registry = registry
	_placeables = BuildSystem.placeables(registry)
	_index = 0
	# The parent Y-sorts its children; the outline belongs above all of
	# them wherever it sits.
	z_index = 1


func selected_id() -> String:
	return "" if _placeables.is_empty() else _placeables[_index]


func set_active(value: bool) -> void:
	if active == value:
		return
	active = value
	queue_redraw()
	mode_changed.emit(active)


func step_selection(delta: int) -> void:
	if _placeables.size() < 2:
		return
	_index = posmod(_index + delta, _placeables.size())
	selection_changed.emit(selected_id())


## The command a left click on `tile` means, or null with nothing to
## place. The layer is the selected content's category: a definition says
## where it goes by what it is.
func place_command(tile: Vector2i) -> BuildCommand:
	var content_id: String = selected_id()
	if content_id.is_empty():
		return null
	var def: Dictionary = _registry.def_of(_registry.numeric_of(content_id))
	return BuildCommand.place(tile, str(def.get("category", "")), content_id)


func _process(_delta: float) -> void:
	if not active:
		return
	# Asked every frame rather than on mouse motion: the camera follows
	# the player, so the tile under a still mouse changes as they walk,
	# and what is affordable changes as they harvest.
	var tile: Vector2i = tile_at(get_global_mouse_position())
	var cmd: BuildCommand = place_command(tile)
	var accepted: bool = cmd != null and probe.is_valid() and bool(probe.call(cmd))
	if tile == _tile and accepted == _accepted:
		return
	_tile = tile
	_accepted = accepted
	queue_redraw()


func _draw() -> void:
	if not active:
		return
	var size: Vector2 = Vector2(TilesetBuilder.TILE_SIZE)
	# An outline one pixel wide, inset half a pixel so it lands on whole
	# pixels, in a theme colour at full opacity: nothing drawn here is
	# off the palette.
	draw_rect(
		Rect2(Vector2(_tile) * size + Vector2(0.5, 0.5), size - Vector2.ONE),
		UiTheme.ACCENT if _accepted else UiTheme.DANGER,
		false, 1.0)


## The parent world is PROCESS_MODE_PAUSABLE, so none of this is heard
## while paused.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("build_mode"):
		get_viewport().set_input_as_handled()
		set_active(not active)
		return
	if not active:
		return
	var click: InputEventMouseButton = event as InputEventMouseButton
	if click == null or not click.pressed:
		return
	get_viewport().set_input_as_handled()
	# The click's own position, not the last one _process saw: the two
	# can differ by a frame, and the command must name the tile clicked.
	var local: InputEventMouseButton = make_input_local(click) as InputEventMouseButton
	var tile: Vector2i = tile_at(local.position)
	if click.button_index == MOUSE_BUTTON_LEFT:
		var cmd: BuildCommand = place_command(tile)
		if cmd != null:
			build_requested.emit(cmd)
	elif click.button_index == MOUSE_BUTTON_RIGHT:
		build_requested.emit(BuildCommand.remove(tile, BuildCommand.LAYER_OBJECT))
	elif click.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		step_selection(1)
	elif click.button_index == MOUSE_BUTTON_WHEEL_UP:
		step_selection(-1)
```

- [ ] **Step 4: Bind the key, and give the world its cursor**

In `project.godot`, replace the whole `debug_place={ … }` block (five lines,
from `debug_place={` to its closing `}`) with — same key, physical keycode
66 is `B`:

```
build_mode={
"deadzone": 0.2,
"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":66,"key_label":0,"unicode":0,"location":0,"echo":false,"script":null)
]
}
```

Leave `debug_grant` alone; Task 5 removes it together with the code that
reads it.

In `src/presentation/world.gd`, directly after
`var player_entity_id: int = EntityStore.INVALID_ID`, add:

```gdscript

## Build mode's mouse. Public so the router can connect to it and hand it
## a probe; non-null once build() has returned.
var build_cursor: BuildCursor = null
```

In `build()`, directly after `_camera.make_current()` and before
`return errors`, add:

```gdscript

	build_cursor = BuildCursor.new()
	build_cursor.name = "BuildCursor"
	add_child(build_cursor)
	build_cursor.setup(registry)
```

Replace the `# --- debug ---` section header, `_unhandled_input` and the
whole of `_debug_place_wall` (its doc comment included) with:

```gdscript
# --- input ------------------------------------------------------------

## World is PROCESS_MODE_PAUSABLE, so this is not heard while paused.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact"):
		get_viewport().set_input_as_handled()
		if zone != null and zone.entities.has(player_entity_id):
			interact_requested.emit(_player_facing_tile())
```

`_player_facing_tile` below it stays exactly as it is.

- [ ] **Step 5: Park what this phase declines**

In `IDEAS.md`, directly before `## Unsorted`, add:

```markdown
## Parked during Stage 2

- Undo/redo — edits are already `BuildCommand` objects; the stack is not built
- Blueprint save/load
- **A controller path for the build cursor.** Build mode is mouse-only and
  `build_mode` has no gamepad binding. This is a known Stage 6 cost, accepted
  in the Stage 2 design §3.5, not something to discover there.
- Drag to paint a run of tiles in build mode (10a is one click, one tile)
- Placeable roofs — they need elevation rendering to be anything but a wall
- Doors that open
- A partial refund, or a tool requirement, for removing built things
- A reach limit on building

```

- [ ] **Step 6: Run the tests and every local gate**

Run: `./tools/run_tests.sh`
Expected: PASS, all suites; `test_the_movement_actions_still_exist` and
`test_the_interact_action_is_bound_to_e` still pass, proving the hand-edited
`[input]` section is intact.

Confirm nothing still reads the removed action — expected: no output.

```bash
grep -rn '"debug_place"\|_debug_place_wall()' src tools project.godot
```

Run each, and expect exit 0 from all:

```bash
./tools/godot.sh --headless --path . -s tools/guard.gd      # Architecture guard: clean
./tools/godot.sh --headless --path . -s tools/smoke.gd      # Smoke test: OK
./tools/check_asset_licences.sh                             # Asset licences: OK
./tools/check_palette.sh                                    # Palette: OK
./tools/check_zone.sh                                       # Zone gate: OK
```

- [ ] **Step 7: Commit**

```bash
git add src/presentation/build_cursor.gd src/presentation/build_cursor.gd.uid \
  tests/test_build_cursor.gd tests/test_build_cursor.gd.uid \
  src/presentation/world.gd project.godot tests/test_input_map.gd IDEAS.md
git commit -m "feat: B toggles a build cursor that turns clicks into commands"
```

- [ ] **Step 8: Tick the task**

```bash
python3 tools/mark_task_done.py 4 --plan docs/superpowers/plans/2026-10-05-rp1-phase10a-build-rules-cursor.md
git add docs/superpowers/plans/2026-10-05-rp1-phase10a-build-rules-cursor.md
git commit -m "docs: tick Phase 10a task 4"
```

---

## Task 5: The router, the readout, and the loop end to end

`main.gd` holds the session, so it is where a command meets the rules. This
task connects the cursor to `BuildSystem`, hands the cursor its probe, shows
the player what is selected and what it costs, and deletes the last debug
key. Then it proves chop → wood → wall across a real relaunch.

**Files:**
- Create: `src/ui/build_status.gd`
- Create: `tests/test_build_status.gd`
- Modify: `src/presentation/main.gd`
- Modify: `src/ui/controls_hint.gd`
- Modify: `project.godot` — `[input]`: `debug_grant` removed
- Test: `tests/test_input_map.gd`

**Interfaces:**
- Consumes: `BuildSystem.check/apply/cost_error/cost_of` (Tasks 1–3);
  `BuildResult.ok/.reason/.detail/.content_id`, `BuildResult.BAD_COST`
  (Task 2); `World.build_cursor`, `BuildCursor.probe/.active/.selected_id()`,
  signals `build_requested`, `mode_changed`, `selection_changed` (Task 4);
  `GameSession.zone`, `GameSession.inventory` (existing).
- Produces:
  - `static BuildStatus.line(content_id: String, inventory: Inventory, registry: ContentRegistry) -> String`
  - `BuildStatus.show_line(text: String) -> void`

- [ ] **Step 1: Write the failing tests**

Create `tests/test_build_status.gd`:

```gdscript
extends GutTest
## The build readout's wording. The node that draws it holds no rules;
## this is the one function in it that could be wrong.


func _registry() -> ContentRegistry:
	var r: ContentRegistry = ContentRegistry.new()
	r.register({"id": "wood", "category": "item", "display_name": "Wood"})
	r.register({"id": "stone", "category": "item", "display_name": "Stone"})
	r.register({"id": "window", "category": "object", "display_name": "Window",
		"sprite": "res://none.png", "cost": {"wood": 1, "stone": 1}})
	r.register({"id": "marker", "category": "object", "display_name": "Marker",
		"sprite": "res://none.png", "cost": {}})
	r.register({"id": "broken", "category": "object", "display_name": "Broken",
		"sprite": "res://none.png", "cost": {"mithril": 1}})
	return r


func test_the_line_names_the_selection_its_cost_and_what_is_held() -> void:
	var inv: Inventory = Inventory.new()
	var _w: bool = inv.add("wood", 7)
	# Items in id order, by display name; stone is not held at all.
	assert_eq(BuildStatus.line("window", inv, _registry()),
		"BUILD    Window    Stone 1 (have 0)    Wood 1 (have 7)")


func test_a_free_thing_says_so() -> void:
	assert_eq(BuildStatus.line("marker", Inventory.new(), _registry()),
		"BUILD    Marker    free")


func test_nothing_selected_says_so() -> void:
	assert_eq(BuildStatus.line("", Inventory.new(), _registry()),
		"BUILD    nothing to build")


func test_a_malformed_cost_is_not_presented_as_a_price() -> void:
	assert_eq(BuildStatus.line("broken", Inventory.new(), _registry()),
		"BUILD    Broken    cost unreadable")
```

In `tests/test_input_map.gd`, replace the whole of
`test_the_debug_grant_action_is_bound_to_g` (its `# DEBUG ONLY` comment
included) with:

```gdscript
func test_the_debug_grant_action_is_gone() -> void:
	# It held G and granted free wood. Harvesting replaced it.
	assert_false(InputMap.has_action("debug_grant"))
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `./tools/run_tests.sh`
Expected: FAIL — exit 3, `a test script failed to load`, because
`BuildStatus` does not exist yet.

- [ ] **Step 3: Write the readout**

Create `src/ui/build_status.gd`:

```gdscript
class_name BuildStatus
extends Control
## What build mode is about to place, what it costs, and what is held.
##
## One line of text until the palette and the inventory display exist.
## The node holds no rules, like the menus; line() is its one function
## with something to get wrong, and it is tested.

const GAP: String = "    "
const HINT: String = "Left click place    Right click remove    Wheel select    B exit"

var _label: Label = null


## The readout for `content_id`, or for nothing when it is empty. Costs
## are worded from the content, so a retuned or new placeable reads
## correctly with no change here.
static func line(
	content_id: String, inventory: Inventory, registry: ContentRegistry
) -> String:
	if content_id.is_empty():
		return GAP.join(PackedStringArray(["BUILD", "nothing to build"]))
	var def: Dictionary = registry.def_of(registry.numeric_of(content_id))
	var parts: PackedStringArray = ["BUILD", str(def.get("display_name", content_id))]
	if BuildSystem.cost_error(def.get("cost"), registry) != "":
		parts.append("cost unreadable")
		return GAP.join(parts)
	var cost: Dictionary = BuildSystem.cost_of(def)
	if cost.is_empty():
		parts.append("free")
	var item_ids: Array = cost.keys()
	item_ids.sort()
	for item_id: String in item_ids:
		var item: Dictionary = registry.def_of(registry.numeric_of(item_id))
		parts.append("%s %d (have %d)" % [
			str(item.get("display_name", item_id)),
			int(cost[item_id]), inventory.count_of(item_id)])
	return GAP.join(parts)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	# The clicks under this text belong to the build cursor.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false

	_label = Label.new()
	_label.add_theme_color_override("font_color", UiTheme.TEXT)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_label.position.y = 12.0
	add_child(_label)


func show_line(text: String) -> void:
	_label.text = "%s\n%s" % [text, HINT]
	visible = true
```

- [ ] **Step 4: Route the cursor, and remove the last debug key**

In `project.godot`, delete the whole `debug_grant={ … }` block (five lines,
from `debug_grant={` to its closing `}`).

In `src/presentation/main.gd`, after `var _controls_hint: ControlsHint = null`, add:

```gdscript
var _build_status: BuildStatus = null
```

In `_ready`, directly after `_ui.add_child(_controls_hint)`, add:

```gdscript

	_build_status = BuildStatus.new()
	_build_status.name = "BuildStatus"
	_ui.add_child(_build_status)
```

In `_enter_world`, directly after the loop

```gdscript
	for e: String in _world.build(_registry, result):
		push_error(e)
```

add (the cursor exists only once `build()` has returned):

```gdscript
	_world.build_cursor.probe = _can_build
	_world.build_cursor.build_requested.connect(_on_build_requested)
	_world.build_cursor.mode_changed.connect(_refresh_build_status.unbind(1))
	_world.build_cursor.selection_changed.connect(_refresh_build_status.unbind(1))
```

In `_on_interact_requested`, inside the `if result.ok:` branch, directly
after the `print(...)` call, add:

```gdscript
		# What was just chopped may be what the selection costs.
		_refresh_build_status()
```

and change that function's doc comment — `Until build mode it means one
thing: harvest it.` is no longer true. The comment becomes:

```gdscript
## The world said which tile the player reached for; this decides what
## that means. It means one thing, in build mode or out of it: harvest
## it. A refusal is silence -- there was nothing to take -- unless the
## content itself is wrong, which is worth an error.
```

Directly after `_on_interact_requested` and before `func _on_quit_to_menu`, add:

```gdscript
## The cursor's question: would this command be accepted? It tints by the
## answer. The rule is BuildSystem's; this only supplies what it needs.
func _can_build(cmd: BuildCommand) -> bool:
	if _session.zone == null:
		return false
	return BuildSystem.check(cmd, _session.zone, _session.inventory, _registry).ok


## The cursor said what the player asked for; this is where it meets the
## rules. A refusal is silence -- the outline already said no -- unless
## content or code is wrong, which is worth an error.
func _on_build_requested(cmd: BuildCommand) -> void:
	if _world == null or _session.zone == null:
		return
	var result: BuildResult = BuildSystem.apply(
		cmd, _session.zone, _session.inventory, _registry)
	if result.ok:
		print("RP1 build %s %s at %s" % [cmd.action, result.content_id, cmd.tile])
		_refresh_build_status()
	elif result.reason == BuildResult.BAD_COST or result.reason == BuildResult.BAD_COMMAND:
		push_error("build refused: %s" % result.detail)


func _refresh_build_status() -> void:
	if _world == null or not _world.build_cursor.active:
		_build_status.visible = false
		return
	_build_status.show_line(BuildStatus.line(
		_world.build_cursor.selected_id(), _session.inventory, _registry))


```

In `_on_quit_to_menu`, directly after `_world = null`, add:

```gdscript
	# Build mode lived on the world's cursor and went with it.
	_build_status.visible = false
```

Replace `_unhandled_input` and the whole of `_debug_grant_wood` (its doc
comment included) with:

```gdscript
func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("pause"):
		return
	if _world == null or _confirm.visible:
		return
	get_viewport().set_input_as_handled()
	_set_paused(not get_tree().paused)
```

In `src/ui/controls_hint.gd`, change the label text line to:

```gdscript
	_label.text = "WASD or arrows to move    E to harvest    B to build    Esc to pause"
```

and the file's first doc line to:

```gdscript
## WASD / E / B / Esc, once per player, ever.
```

- [ ] **Step 5: Run the tests and every local gate**

Run: `./tools/run_tests.sh`
Expected: PASS, all suites.

Confirm no debug key survives, and no content is named in the new code —
expected: no output from either.

```bash
grep -rn "debug_grant\|debug_place\|_debug_" src project.godot
grep -nE '"(wood|stone|wall_wood|wall_stone|door|window)"' \
  src/systems/build_system.gd src/systems/build_command.gd src/systems/build_result.gd \
  src/presentation/build_cursor.gd src/ui/build_status.gd src/presentation/main.gd \
  src/presentation/world.gd
```

Run each, and expect exit 0 from all:

```bash
./tools/godot.sh --headless --path . -s tools/guard.gd      # Architecture guard: clean
./tools/godot.sh --headless --path . -s tools/smoke.gd      # Smoke test: OK
./tools/check_asset_licences.sh                             # Asset licences: OK
./tools/check_palette.sh                                    # Palette: OK
./tools/check_zone.sh                                       # Zone gate: OK
```

- [ ] **Step 6: Prove the phase end to end**

`main.gd`, `World` and the routing between them have no unit tests, so the
key → cursor → router → system → save path is proved by driving the real
main scene with real key and mouse events, in two separate processes so the
relaunch is real. Synthetic mouse events were checked to reach
`_unhandled_input` headless, through a zoomed camera, before this plan was
written.

**It runs against a throwaway save root.** Do not prove this by hand in the
developer's own world without asking: `user://saves/home` is a real save.

The script names `wall_wood` — it is a throwaway outside the repository,
and "chop a tree, place a wooden wall" is the sentence it exists to prove.

Write the script outside the repository (it is never committed):

```bash
DRIVE="${TMPDIR:-/tmp}/phase10a_drive.gd"
cat > "$DRIVE" <<'EOF'
extends SceneTree
## Throwaway: Phase 10a's end-to-end proof. Run as "a", then as "b" in a
## second process. Uses its own save root; the real one is never touched.

const ROOT: String = "user://test_saves/phase10a_drive"
const STATE: String = "user://test_saves/phase10a_drive_state.json"
const WALL: String = "wall_wood"

var _main: Node = null
var _failed: bool = false


func _initialize() -> void:
	_run.call_deferred()


func _wipe(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for sub: String in DirAccess.get_directories_at(dir):
		_wipe(dir.path_join(sub))
	for f: String in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)


func _frames(n: int) -> void:
	for i: int in range(n):
		await process_frame


func _key(code: Key) -> void:
	for pressed: bool in [true, false]:
		var ev: InputEventKey = InputEventKey.new()
		ev.physical_keycode = code
		ev.keycode = code
		ev.pressed = pressed
		Input.parse_input_event(ev)
		await _frames(2)


## A press of `button` on the middle of `tile`, as the window would send it.
func _click(tile: Vector2i, button: MouseButton) -> void:
	var world_px: Vector2 = (Vector2(tile) + Vector2(0.5, 0.5)) * 32.0
	var ev: InputEventMouseButton = InputEventMouseButton.new()
	ev.button_index = button
	ev.pressed = true
	ev.position = _main._world.get_viewport().get_canvas_transform() * world_px
	ev.global_position = ev.position
	Input.parse_input_event(ev)
	await _frames(2)


func _expect(label: String, got: Variant, want: Variant) -> void:
	var ok: bool = got == want
	if not ok:
		_failed = true
	print("DRIVE %s: %s -> %s (want %s)" % ["ok  " if ok else "FAIL", label, got, want])


## The first object yielding one of `items`, with walkable ground south of it.
func _tree(zone: Zone, registry: ContentRegistry, items: Array) -> Vector2i:
	for y: int in range(zone.size_tiles.y):
		for x: int in range(zone.size_tiles.x):
			var t: Vector2i = Vector2i(x, y)
			var def: Dictionary = registry.def_of(zone.get_object(t))
			if def.has("harvestable") \
					and items.has((def["harvestable"] as Dictionary)["item"]) \
					and zone.is_walkable(t + Vector2i(0, 1)):
				return t
	return Vector2i(-1, -1)


## Stands the player on the tile south of `t`, facing north at it.
func _stand_below(zone: Zone, pid: int, t: Vector2i) -> void:
	zone.entities.set_position(pid, Vector2(t.x + 0.5, t.y + 1.75))
	zone.entities.set_facing(pid, MovementSystem.FACING_N)


func _player_tile(zone: Zone, pid: int) -> Vector2i:
	var pos: Vector2 = zone.entities.get_position(pid)
	return Vector2i(floori(pos.x), floori(pos.y - 0.25))


## A tile within three of the player where WALL may be placed, not in `skip`.
func _buildable(zone: Zone, inv: Inventory, registry: ContentRegistry,
		pid: int, skip: Array) -> Vector2i:
	var here: Vector2i = _player_tile(zone, pid)
	for dy: int in range(-3, 4):
		for dx: int in range(-3, 4):
			var t: Vector2i = here + Vector2i(dx, dy)
			if skip.has(t):
				continue
			if BuildSystem.check(BuildCommand.place(t, BuildCommand.LAYER_OBJECT, WALL),
					zone, inv, registry).ok:
				return t
	return Vector2i(-1, -1)


func _counts(inv: Inventory) -> Dictionary:
	var out: Dictionary = {}
	for id: String in inv.item_ids():
		out[id] = inv.count_of(id)
	return out


func _name_at(zone: Zone, registry: ContentRegistry, t: Vector2i) -> String:
	return registry.string_of(zone.get_object(t))


func _run() -> void:
	var phase: String = OS.get_cmdline_user_args()[0]
	if phase == "a":
		_wipe(ROOT)
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	await _frames(3)
	_main._session.save_root = ROOT
	_main._settings.controls_hint_shown = true  # so entering a world writes no settings

	if phase == "a":
		_main._on_new_world_requested()
		await _frames(3)
		var zone: Zone = _main._session.zone
		var registry: ContentRegistry = _main._registry
		var inv: Inventory = _main._session.inventory
		var pid: int = _main._session.player_entity_id
		var cursor: BuildCursor = _main._world.build_cursor
		var cost: Dictionary = BuildSystem.cost_of(registry.def_of(registry.numeric_of(WALL)))
		var two_walls: Dictionary = {}
		for id: String in cost:
			two_walls[id] = int(cost[id]) * 2

		# 0: chop, with E, until two walls are affordable.
		var chopped: int = 0
		while not inv.can_afford(two_walls) and chopped < 12:
			var tree: Vector2i = _tree(zone, registry, cost.keys())
			if not zone.in_bounds(tree):
				break
			_stand_below(zone, pid, tree)
			await _frames(2)
			await _key(KEY_E)
			chopped += 1
		_expect("0 chopping with E made two walls affordable", inv.can_afford(two_walls), true)
		await _frames(2)

		var t1: Vector2i = _buildable(zone, inv, registry, pid, [])
		var t2: Vector2i = _buildable(zone, inv, registry, pid, [t1])
		var t3: Vector2i = _buildable(zone, inv, registry, pid, [t1, t2])
		_expect("0 there is somewhere to build", zone.in_bounds(t1) and zone.in_bounds(t2) and zone.in_bounds(t3), true)
		var before: Dictionary = _counts(inv)

		# 1: the mouse does nothing until build mode is on.
		await _click(t1, MOUSE_BUTTON_LEFT)
		_expect("1 a click outside build mode places nothing", zone.get_object(t1), 0)
		_expect("1 no status line outside build mode", _main._build_status.visible, false)

		# 2: B turns it on; the wheel finds the wall.
		await _key(KEY_B)
		_expect("2 B turned build mode on", cursor.active, true)
		_expect("2 the status line is showing", _main._build_status.visible, true)
		var spins: int = 0
		while cursor.selected_id() != WALL and spins < 20:
			await _click(t1, MOUSE_BUTTON_WHEEL_DOWN)
			spins += 1
		_expect("2 the wheel selected the wall", cursor.selected_id(), WALL)

		# 3: left click places and spends.
		await _click(t1, MOUSE_BUTTON_LEFT)
		_expect("3 left click placed the wall", _name_at(zone, registry, t1), WALL)
		_expect("3 the tile is blocked now", zone.is_walkable(t1), false)
		for id: String in cost:
			_expect("3 %s was spent" % id, inv.count_of(id), int(before[id]) - int(cost[id]))
		var after_one: Dictionary = _counts(inv)

		# 4-6: three clicks that must change nothing.
		await _click(t1, MOUSE_BUTTON_LEFT)
		_expect("4 a click on the wall spends nothing more", _counts(inv), after_one)
		var own: Vector2i = _player_tile(zone, pid)
		await _click(own, MOUSE_BUTTON_LEFT)
		_expect("5 no wall on the player's own tile", zone.get_object(own), 0)
		var standing_tree: Vector2i = _tree(zone, registry, cost.keys())
		var tree_obj: int = zone.get_object(standing_tree)
		await _click(standing_tree, MOUSE_BUTTON_RIGHT)
		_expect("6 right click does not remove a tree", zone.get_object(standing_tree), tree_obj)
		_expect("6 and credits nothing", _counts(inv), after_one)

		# 7: paused, the mouse is not heard.
		await _key(KEY_ESCAPE)
		_expect("7 Esc paused the tree", paused, true)
		await _click(t2, MOUSE_BUTTON_LEFT)
		_expect("7 a click while paused places nothing", zone.get_object(t2), 0)
		await _key(KEY_ESCAPE)
		_expect("7 Esc unpaused", paused, false)

		# 8: right click removes and refunds.
		await _click(t1, MOUSE_BUTTON_RIGHT)
		_expect("8 right click removed the wall", zone.get_object(t1), 0)
		_expect("8 the tile is open again", zone.is_walkable(t1), true)
		_expect("8 the cost came back", _counts(inv), before)

		# 9: two walls to carry across the relaunch.
		await _click(t1, MOUSE_BUTTON_LEFT)
		await _click(t2, MOUSE_BUTTON_LEFT)
		_expect("9 wall one stands", _name_at(zone, registry, t1), WALL)
		_expect("9 wall two stands", _name_at(zone, registry, t2), WALL)

		# 10: B turns it off again.
		await _key(KEY_B)
		_expect("10 B turned build mode off", cursor.active, false)
		_expect("10 the status line is gone", _main._build_status.visible, false)
		await _click(t3, MOUSE_BUTTON_LEFT)
		_expect("10 a click after leaving places nothing", zone.get_object(t3), 0)

		var counts: Dictionary = _counts(inv)
		_main._on_quit_to_menu()
		await _frames(3)
		_expect("11 back at the menu", _main._world == null, true)
		var f: FileAccess = FileAccess.open(STATE, FileAccess.WRITE)
		f.store_string(JSON.stringify(
			{"walls": [[t1.x, t1.y], [t2.x, t2.y]], "counts": counts}))
		f.close()
	else:
		var state: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(STATE))
		_main._on_continue_requested()
		await _frames(3)
		var zone: Zone = _main._session.zone
		_expect("12 relaunched and continued", zone != null, true)
		for xy: Array in state["walls"]:
			var t: Vector2i = Vector2i(int(xy[0]), int(xy[1]))
			_expect("12 the wall at %s is still there" % t,
				_name_at(zone, _main._registry, t), WALL)
			_expect("12 and still blocks", zone.is_walkable(t), false)
		_expect("12 the inventory is what it was",
			_counts(_main._session.inventory).size(), (state["counts"] as Dictionary).size())
		for id: String in state["counts"]:
			_expect("12 %s is still counted" % id,
				_main._session.inventory.count_of(id), int(state["counts"][id]))
		_expect("12 build mode does not survive a relaunch",
			_main._world.build_cursor.active, false)
		_wipe(ROOT)
		DirAccess.remove_absolute(STATE)
	quit(1 if _failed else 0)
EOF
./tools/godot.sh --headless --path . -s "$DRIVE" -- a 2>&1 | grep -E "DRIVE|RP1 harvested|RP1 build|RP1 saved|ERROR"
./tools/godot.sh --headless --path . -s "$DRIVE" -- b 2>&1 | grep -E "DRIVE|RP1 build|RP1 saved|ERROR"
rm -f "$DRIVE"
```

Expected, process `a`: one or more `RP1 harvested …` lines, then
`RP1 build place wall_wood at (x, y)`, `RP1 build remove wall_wood at
(x, y)` and two more `place` lines; every `DRIVE` line reads `ok`, and no
`DRIVE FAIL`. Process `b`: every `DRIVE` line reads `ok`. Neither run may
print `build refused` or `harvest refused`.
`ERROR: 2 resources still in use at exit` is printed by both runs: it is
the script quitting with the main scene still loaded, not a failure.

Write what each numbered step printed in the commit message body. If any
line reads `FAIL`, stop and report it — do not tick the task.

This is a scripted run, not a hand run, and the commit body and the PR
description must say so. It cannot see the outline or the status line. A
person pressing `B` and clicking in a window — checking that the outline
sits on the tile under the mouse, turns from red to gold where a wall can
go, and that the status line reads correctly — is still required once
before the phase is called closed; ask the developer whether to do it in
their real world.

- [ ] **Step 7: Commit**

```bash
git add src/ui/build_status.gd src/ui/build_status.gd.uid \
  tests/test_build_status.gd tests/test_build_status.gd.uid \
  src/presentation/main.gd src/ui/controls_hint.gd project.godot tests/test_input_map.gd
git commit -m "feat: build mode places and removes walls with the mouse

Scripted run against a throwaway save root: <one line per step 0-12>"
```

- [ ] **Step 8: Tick the task**

```bash
python3 tools/mark_task_done.py 5 --plan docs/superpowers/plans/2026-10-05-rp1-phase10a-build-rules-cursor.md
git add docs/superpowers/plans/2026-10-05-rp1-phase10a-build-rules-cursor.md
git commit -m "docs: tick Phase 10a task 5"
```

---

## Definition of done

- [ ] Every shipped `cost` resolves to registered items with whole amounts —
      `test_every_shipped_cost_resolves`
- [ ] Placing writes the object, blocks the tile and spends the cost;
      removing clears it, opens the tile and refunds the cost — Tasks 2 and
      3's `test_build_system.gd` tests
- [ ] A refused command changes no tile, no flag and no count — every
      `_assert_refused` case
- [ ] Place, relaunch: the object is still there and its cost still spent —
      `test_a_placed_object_survives_a_relaunch_and_its_cost_stays_spent`
      and Task 5 step 6
- [ ] A removal made after the first save reaches disk —
      `test_a_removal_after_the_first_save_reaches_disk`
- [ ] `B` toggles build mode; left click places, right click removes, the
      wheel selects; none of it is heard while paused or outside build mode
- [ ] `debug_place` and `debug_grant` are gone from `project.godot`, `src/`
      and the tests that pinned them
- [ ] No object id, item id or amount is written in GDScript: Task 5 step
      5's second `grep` prints nothing
- [ ] No save format changed: `git diff main --stat` shows none of
      `chunk_codec.gd`, `entity_codec.gd`, `inventory_codec.gd`, `save_manager.gd`
- [ ] The controller debt and the parked features are in `IDEAS.md`
- [ ] A person has looked at the outline and the status line in a window
- [ ] All six local gates green, and CI green on the branch

Tick with `python3 tools/mark_task_done.py --section "Definition of done" --plan docs/superpowers/plans/2026-10-05-rp1-phase10a-build-rules-cursor.md`.

**Not in this plan — Phase 10b:** the clickable palette, a visible
inventory, and the `floor` content category with place and remove on the
floor layer. Spec acceptance criterion 11 ("a new placeable is one JSON file
and one manifest slice, with no code change") is already true of 10a's
code and is *demonstrated* in 10b, where the first new placeables are added.
