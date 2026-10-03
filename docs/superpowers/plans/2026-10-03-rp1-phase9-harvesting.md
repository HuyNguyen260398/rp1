# Phase 9 — Harvesting: the World into the Inventory Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Pressing an `interact` key while facing a tree or a rock removes it
from the world through the Phase 7 mutation spine and credits its yield to
the Phase 8 inventory, and both survive a relaunch.

**Architecture:** `HarvestSystem` (`RefCounted`, `src/systems/`) is the single
place that answers *may this tile be harvested, and what does it give*. It
reads the `harvestable` field content has declared since Stage 1, checks it
against the `ContentRegistry`, and only then writes: `Zone.set_object` to
clear the tile, `Walkability.recompute_chunk` to open it, `Inventory.add` to
credit the roll. Every refusal happens before the first write. `World` emits
`interact_requested(tile)` with the tile the player faces and `main.gd`
routes it to the system — presentation emits, the router decides (spec §3.5).
Nothing new is persisted: the chunk reaches disk because its version moved,
the count because `inventory.json` is written on every save.

**Tech Stack:** Godot 4.7.2 stable (standard build, **not** Mono), GDScript
only, GUT for tests.

**Spec:** `docs/superpowers/specs/2026-09-22-rp1-stage2-design.md` — §2
(the `harvestable` hook), §3.1 (the mutation spine), §3.5 (routing), the
Phase 9 entry in §4, and acceptance criterion 3 in §5.

## Global Constraints

- Godot **4.7.2**, standard build. Invoke only through `./tools/godot.sh`.
- GDScript only. No C#. No `TileMap` — `TileMapLayer` only.
- Static typing everywhere: `var x: int = 0`, `func f(a: Vector2i) -> void:`.
- `src/core/` and `src/systems/` **MUST NOT reference Godot nodes.** No
  `extends Node`, no `get_tree()`, no `Engine.`, no `.tscn`. `RefCounted`
  only. Enforced by `tools/guard.gd`.
- Presentation reads from world data. World data never reads from presentation.
- All game content lives in `data/*.json`. Never `match` over content
  types — look them up in `ContentRegistry`. **No object id, item id or
  amount is written in GDScript in this phase**; what a tree yields is
  whatever its JSON says.
- Never use `load()`, `ResourceLoader`, or `.tres`/`.res` for save data.
- Saves persist **string ids**, never runtime numeric ids.
- No save format changes in this phase. `chunk_codec`, `entity_codec`,
  `inventory_codec` and `save_manager` are not modified.
- Run tests with `./tools/run_tests.sh` — never `gut_cmdln.gd` directly. The
  runner does a mandatory `--import` pass first; without it GUT reports missing
  `class_name`s **and exits 0**, so a broken suite looks green.
- TDD: write the failing test, watch it fail, implement minimally, watch it pass.
- Every file in `core/` and `systems/` has a matching test in `tests/`.
  (Result value objects — `HarvestResult` here, like `SessionOpenResult` —
  are exercised through the system that returns them.)
- Conventional commit prefixes: `feat:`, `test:`, `ci:`, `docs:`, `fix:`.
- Each task produces two commits: the code, then a `docs:` commit ticking that
  task's checkboxes with `python3 tools/mark_task_done.py <n> --plan <this file>`.
- Godot writes a `.uid` beside every new `.gd` file on the import pass.
  **Commit it with the script**; every existing script's `.uid` is tracked.

## Decisions this plan makes

The spec's Phase 9 entry is three lines. These are the calls it leaves open,
made here so they can be challenged in review rather than discovered in code:

1. **One press, one harvest.** No chop timer, no hit count, no tool. The
   stage's loop is chop → wood → wall; a duration is a tuning feature with no
   consumer yet.
2. **Anything with `harvestable` can be harvested** — trees *and* rocks. The
   five shipped objects that declare it are `oak_tree`, `pine_tree`,
   `dead_tree`, `rock_small` and `rock_large`. Restricting to trees would be
   a `match` over content.
3. **The target is the tile the player faces**, the same tile `debug_place`
   uses. The mouse cursor is Phase 10.
4. **`interact` is bound to `E` and to gamepad `A`** (button 0). It is a
   real action, not a debug one, so it goes through `InputMap` with a
   gamepad binding like `pause`.
5. **The yield is rolled uniformly in the authored `[min, max]`** from an
   RNG the system owns, randomized at boot like `AudioDirector`'s.
6. **A yield that does not resolve refuses the harvest** — the tree stays.
   Destroying an object and crediting nothing is the worse failure.
7. **Feedback is the tree disappearing plus a console line.** There is no
   inventory UI until Phase 10 and no chop sound asset in the build.
   `debug_grant` (`G`) stays until Phase 10, as its comment says.

## Known gap, pinned but not fixed here

**Chunks have no backup.** `SaveManager.save_zone` rotates only
`entities.dat` (its header says "A Stage 2 that makes chunks mutable must
rotate them too"), while `meta.json` and `inventory.json` do rotate. So
"load backup" after a harvest opens the *live* chunks with the *previous*
inventory: the tree is gone and its wood is not counted. Nothing is
duplicated, and a backup is only offered when the live save fails to open,
but it is a loss.

Fixing it is not a one-liner — per-file `.bak` rotation combined with
incremental chunk saves would restore chunks from different saves — so it is
out of this phase. Task 3 pins today's behaviour with a test named for the
gap, so whoever adds chunk backups is told to update it.

## Review Focus

1. **Interacting with nothing, with a wall, or past the zone's edge.** The
   player expects nothing to happen and nothing to break — Task 3,
   `test_reaching_outside_the_zone_is_refused`,
   `test_an_empty_tile_is_refused`, `test_an_object_with_no_yield_is_refused`.
2. **Yield amounts arrive from JSON as floats** (`[2.0, 4.0]`), and
   hand-edited content can be wrong in every way (min above max, zero,
   fractional, strings, a missing or misspelt item). Expected: whole-number
   floats work; anything else refuses, names the problem, and leaves the
   tree — Task 2, `test_every_malformed_yield_is_named`; Task 3,
   `test_a_malformed_yield_leaves_the_tree_standing`.
3. **Chopping after the world has already been saved once.** The first save
   writes every chunk; later ones write only chunks whose version moved.
   Expected: the tree is still gone after a relaunch — Task 3,
   `test_a_harvest_after_the_first_save_reaches_disk`.
4. **Standing on a tile boundary, or facing diagonally.** Expected: the
   tile harvested is the one the character visibly faces, measured from the
   body's centre — Task 1's `facing_tile` tests.
5. **Loading the backup after a harvest.** See "Known gap" above — Task 3,
   `test_a_backup_load_keeps_the_harvest_but_not_its_yield`.

---

## File Structure

| File | Responsibility |
|---|---|
| `src/systems/movement_system.gd` | **Modify.** Gains `facing_tile`, lifted out of `World` so it is testable headless. |
| `src/systems/harvest_system.gd` | **Create.** `yield_error` (does a `harvestable` resolve?) and `harvest` (do it). |
| `src/systems/harvest_result.gd` | **Create.** What `harvest` returns: ok or a refusal reason. |
| `src/presentation/world.gd` | **Modify.** `interact_requested` signal; `_player_facing_tile` delegates. |
| `src/presentation/main.gd` | **Modify.** Owns the `HarvestSystem`; routes the signal to it. |
| `src/ui/controls_hint.gd` | **Modify.** The hint names the new key. |
| `project.godot` | **Modify.** `interact` action on `E` and gamepad `A`. |

Tests: `tests/test_movement_system.gd`, `tests/test_harvest_system.gd` (new),
`tests/test_game_session.gd`, `tests/test_input_map.gd`.

---

## Task 1: `MovementSystem.facing_tile`

`World._player_facing_tile()` already computes the tile the player faces, for
`debug_place`. It lives in a Node, so nothing tests it. Harvesting makes it
the targeting rule for a real feature, so it moves to `MovementSystem`
unchanged and gains tests. `World` keeps a one-line wrapper.

**Files:**
- Modify: `src/systems/movement_system.gd` — append after `facing_from`
- Modify: `src/presentation/world.gd` — `_player_facing_tile` (last function in the file)
- Test: `tests/test_movement_system.gd`

**Interfaces:**
- Produces: `MovementSystem.facing_tile(pos: Vector2, body: Vector2, facing: int) -> Vector2i`
  — `pos` is the feet point in tile units, `body` the collision box size in
  tiles, `facing` an octant `0..7` (`FACING_S` … `FACING_SW`). Returns the
  neighbouring tile in that direction; it may be out of bounds, and callers
  check.

- [x] **Step 1: Write the failing tests**

Append to `tests/test_movement_system.gd`:

```gdscript


func test_facing_tile_is_the_neighbour_in_each_of_the_eight_directions() -> void:
	# Feet at (5.5, 5.75) under a half-tile-tall body: the body's centre is
	# at (5.5, 5.5), so the character stands on tile (5, 5).
	var feet: Vector2 = Vector2(5.5, 5.75)
	var body: Vector2 = Vector2(0.625, 0.5)
	var want: Dictionary = {
		MovementSystem.FACING_S: Vector2i(5, 6),
		MovementSystem.FACING_SE: Vector2i(6, 6),
		MovementSystem.FACING_E: Vector2i(6, 5),
		MovementSystem.FACING_NE: Vector2i(6, 4),
		MovementSystem.FACING_N: Vector2i(5, 4),
		MovementSystem.FACING_NW: Vector2i(4, 4),
		MovementSystem.FACING_W: Vector2i(4, 5),
		MovementSystem.FACING_SW: Vector2i(4, 6),
	}
	for facing: int in want:
		assert_eq(MovementSystem.facing_tile(feet, body, facing), want[facing],
			"facing %d" % facing)


func test_facing_tile_measures_from_the_body_centre_not_the_feet() -> void:
	# Feet exactly on the line between tiles (5, 5) and (5, 6). The feet
	# point alone would say (5, 6); the body is drawn in (5, 5), and that
	# is the tile the player believes they are standing on.
	assert_eq(
		MovementSystem.facing_tile(
			Vector2(5.5, 6.0), Vector2(0.625, 0.5), MovementSystem.FACING_N),
		Vector2i(5, 4))


func test_facing_tile_at_the_zone_edge_is_out_of_bounds_not_clamped() -> void:
	# Bounds are the caller's question: a clamped answer would make the
	# player harvest the tile they are standing on.
	assert_eq(
		MovementSystem.facing_tile(
			Vector2(0.5, 0.75), Vector2(0.625, 0.5), MovementSystem.FACING_NW),
		Vector2i(-1, -1))
```

- [x] **Step 2: Run the tests to verify they fail**

Run: `./tools/run_tests.sh`
Expected: FAIL, exit 3 — `test_movement_system.gd` does not parse:
`Static function "facing_tile()" not found in base "MovementSystem"`.

- [x] **Step 3: Write the implementation**

Append to `src/systems/movement_system.gd`:

```gdscript


## The tile one step from a body in the direction it faces.
##
## `pos` is the feet point, the bottom-centre of the body; the tile a
## character stands on is the one under the body's centre, not under its
## bottom edge. `facing` is an octant index from facing_from(): 0 is south
## and each step turns a quarter of PI toward east, so this is its inverse.
## A diagonal facing yields the diagonal neighbour.
##
## The result is not clamped. At a zone edge it is out of bounds, and the
## caller asks Zone.in_bounds().
static func facing_tile(pos: Vector2, body: Vector2, facing: int) -> Vector2i:
	var centre: Vector2 = pos - Vector2(0.0, body.y * 0.5)
	var standing: Vector2i = Vector2i(floori(centre.x), floori(centre.y))
	var dir: Vector2 = Vector2.from_angle(PI * 0.5 - facing * PI * 0.25)
	return standing + Vector2i(roundi(dir.x), roundi(dir.y))
```

In `src/presentation/world.gd`, replace the whole of `_player_facing_tile`
— its doc comment and its body, from `## The tile one step from the player`
to the end of the file — with:

```gdscript
## The tile the player faces. The rule lives in MovementSystem, where it
## is tested; this only supplies the player's row.
func _player_facing_tile() -> Vector2i:
	return MovementSystem.facing_tile(
		zone.entities.get_position(player_entity_id),
		_player.body,
		zone.entities.get_facing(player_entity_id))
```

- [x] **Step 4: Run the tests to verify they pass**

Run: `./tools/run_tests.sh`
Expected: PASS, all suites.

Run: `./tools/godot.sh --headless --path . -s tools/smoke.gd`
Expected: `Smoke test: OK (300 iterations)`, exit 0.

- [x] **Step 5: Commit**

```bash
git add src/systems/movement_system.gd src/presentation/world.gd tests/test_movement_system.gd
git commit -m "feat: the tile a body faces, as a tested rule"
```

- [x] **Step 6: Tick the task**

```bash
python3 tools/mark_task_done.py 1 --plan docs/superpowers/plans/2026-10-03-rp1-phase9-harvesting.md
git add docs/superpowers/plans/2026-10-03-rp1-phase9-harvesting.md
git commit -m "docs: tick Phase 9 task 1"
```

---

## Task 2: `harvestable` resolves

`harvestable` has been in `data/object/*.json` since Stage 1 and the schema
checks only that it is a `Dictionary`. This task gives it a meaning:
`{"item": <id of a registered item>, "amount": [min, max]}` with whole
numbers and `1 <= min <= max`. One static function says what is wrong with
one, and a test runs it over every shipped object so bad content fails CI
rather than failing a player.

`JSON.parse` returns every number as a float, so `[2, 4]` in a file arrives
as `[2.0, 4.0]`. Whole-number floats are accepted; `2.5` is not.

**Files:**
- Create: `src/systems/harvest_system.gd`
- Test: `tests/test_harvest_system.gd`

**Interfaces:**
- Consumes: `ContentRegistry.numeric_of(string_id: String) -> int`,
  `.is_placeholder(numeric_id: int) -> bool`,
  `.def_of(numeric_id: int) -> Dictionary` (existing); the `item` category
  (Phase 8).
- Produces: `HarvestSystem.yield_error(harvestable: Variant, registry: ContentRegistry) -> String`
  — static. `""` when the value is a well-formed, resolvable yield;
  otherwise one sentence starting with `"harvestable"` naming the problem.

- [x] **Step 1: Write the failing tests**

Create `tests/test_harvest_system.gd`:

```gdscript
extends GutTest
## Harvesting: an object leaves the world and its yield enters the
## inventory. Built on a registry assembled here, so no test depends on
## what data/ happens to ship -- except the one that checks data/ itself.


func _registry() -> ContentRegistry:
	var r: ContentRegistry = ContentRegistry.new()
	r.register({"id": "grass", "category": "terrain", "display_name": "Grass",
		"sprite": "res://none.png", "walkable": true})
	r.register({"id": "wood", "category": "item", "display_name": "Wood"})
	r.register({"id": "rabbit", "category": "creature", "display_name": "Rabbit",
		"sprite": "res://none.png"})
	r.register({"id": "wall", "category": "object", "display_name": "Wall",
		"sprite": "res://none.png", "blocks_movement": true})
	return r


# --- yield_error ------------------------------------------------------

func test_a_well_formed_yield_has_no_error() -> void:
	assert_eq(HarvestSystem.yield_error({"item": "wood", "amount": [2, 4]}, _registry()), "")


func test_the_whole_number_floats_json_produces_are_accepted() -> void:
	# JSON.parse hands back 2.0 and 4.0 for a file that says [2, 4].
	assert_eq(HarvestSystem.yield_error({"item": "wood", "amount": [2.0, 4.0]}, _registry()), "")


func test_a_fixed_amount_is_a_valid_range() -> void:
	assert_eq(HarvestSystem.yield_error({"item": "wood", "amount": [3, 3]}, _registry()), "")


func test_every_malformed_yield_is_named() -> void:
	var r: ContentRegistry = _registry()
	var _ghost: int = r.register_placeholder("ghost")
	# [the harvestable value, a fragment the error must contain]
	var cases: Array = [
		["wood", "not an object"],
		[{"amount": [1, 2]}, "string id"],
		[{"item": "", "amount": [1, 2]}, "string id"],
		[{"item": 7, "amount": [1, 2]}, "string id"],
		[{"item": "mithril", "amount": [1, 2]}, "not in this build"],
		[{"item": "ghost", "amount": [1, 2]}, "not in this build"],
		[{"item": "rabbit", "amount": [1, 2]}, "not an item"],
		[{"item": "wood"}, "[min, max]"],
		[{"item": "wood", "amount": 3}, "[min, max]"],
		[{"item": "wood", "amount": [1]}, "[min, max]"],
		[{"item": "wood", "amount": [1, 2, 3]}, "[min, max]"],
		[{"item": "wood", "amount": [1.5, 2]}, "whole number"],
		[{"item": "wood", "amount": ["1", "2"]}, "whole number"],
		[{"item": "wood", "amount": [0, 2]}, "below 1"],
		[{"item": "wood", "amount": [-1, 2]}, "below 1"],
		[{"item": "wood", "amount": [4, 2]}, "below its minimum"],
	]
	for c: Array in cases:
		var err: String = HarvestSystem.yield_error(c[0], r)
		assert_string_contains(err, str(c[1]))
		assert_true(err.begins_with("harvestable"), "'%s' names the field" % err)


func test_every_shipped_harvestable_resolves() -> void:
	# The check that makes bad content fail CI instead of failing a player.
	var r: ContentRegistry = ContentRegistry.new()
	assert_eq(r.load_from_dir("res://data").size(), 0)
	var checked: int = 0
	for sid: String in r.all_string_ids():
		var def: Dictionary = r.def_of(r.numeric_of(sid))
		if not def.has("harvestable"):
			continue
		assert_eq(HarvestSystem.yield_error(def["harvestable"], r), "", sid)
		checked += 1
	assert_gt(checked, 0, "the loop must not pass by finding nothing to check")
```

- [x] **Step 2: Run the tests to verify they fail**

Run: `./tools/run_tests.sh`
Expected: FAIL, exit 3 — `test_harvest_system.gd` does not parse:
`Identifier "HarvestSystem" not declared in the current scope`.

- [x] **Step 3: Write the implementation**

Create `src/systems/harvest_system.gd`:

```gdscript
class_name HarvestSystem
extends RefCounted
## Turns a harvestable object into items.
##
## `harvestable` is authored on the object: {"item": id, "amount": [min,
## max]}. Nothing here names a tree, a rock or wood -- what an object
## yields is whatever its JSON says, so a new harvestable is a data file.

## Rolls the amount. Owned here so a test can seed it.
var rng: RandomNumberGenerator = RandomNumberGenerator.new()


## What is wrong with a `harvestable` value, or "" if nothing is.
##
## Takes a Variant because that is what content hands over: the schema
## guarantees only that the field is a Dictionary. Amounts may be the
## whole-number floats JSON produces. The item must be real content of
## the item category -- a yield into an id nothing defines would destroy
## the object and credit something the build cannot name.
static func yield_error(harvestable: Variant, registry: ContentRegistry) -> String:
	if not (harvestable is Dictionary):
		return "harvestable is not an object"
	var h: Dictionary = harvestable

	var item: Variant = h.get("item")
	if not (item is String) or (item as String).is_empty():
		return "harvestable.item is not a string id"
	var item_id: String = item
	var item_numeric: int = registry.numeric_of(item_id)
	if item_numeric == ContentRegistry.ID_UNKNOWN or registry.is_placeholder(item_numeric):
		return "harvestable.item '%s' is not in this build" % item_id
	if str(registry.def_of(item_numeric).get("category", "")) != "item":
		return "harvestable.item '%s' is not an item" % item_id

	var amount: Variant = h.get("amount")
	if not (amount is Array) or (amount as Array).size() != 2:
		return "harvestable.amount is not [min, max]"
	var bounds: Array = amount
	for v: Variant in bounds:
		if not _is_whole(v):
			return "harvestable.amount holds a value that is not a whole number"
	var lo: int = roundi(float(bounds[0]))
	var hi: int = roundi(float(bounds[1]))
	if lo < 1:
		return "harvestable.amount minimum is below 1"
	if hi < lo:
		return "harvestable.amount maximum is below its minimum"
	return ""


static func _is_whole(v: Variant) -> bool:
	if not (v is int or v is float):
		return false
	return is_equal_approx(float(v), roundf(float(v)))
```

- [x] **Step 4: Run the tests to verify they pass**

Run: `./tools/run_tests.sh`
Expected: PASS, all suites.

Run: `./tools/godot.sh --headless --path . -s tools/guard.gd`
Expected: `Architecture guard: clean`.

- [x] **Step 5: Commit**

```bash
git add src/systems/harvest_system.gd src/systems/harvest_system.gd.uid tests/test_harvest_system.gd tests/test_harvest_system.gd.uid
git commit -m "feat: harvestable resolves against the registry"
```

- [x] **Step 6: Tick the task**

```bash
python3 tools/mark_task_done.py 2 --plan docs/superpowers/plans/2026-10-03-rp1-phase9-harvesting.md
git add docs/superpowers/plans/2026-10-03-rp1-phase9-harvesting.md
git commit -m "docs: tick Phase 9 task 2"
```

---

## Task 3: `HarvestSystem.harvest`, and proof it persists

The harvest itself. Every check runs before the first write, so a refusal
mutates nothing — no tile, no flag, no count. On success three things
change, in this order:

1. `Zone.set_object(tile, ID_UNKNOWN)` — advances the chunk's version, which
   is how the renderer, the collider and the save each learn of it (§3.1).
2. `Walkability.recompute_chunk` — the tile was blocked by the object and is
   now open. Never set the flag byte by hand: `FLAG_BLOCKS_LIGHT` shares it.
3. `Inventory.add` — cannot refuse here, because `yield_error` already
   guaranteed a non-empty item id and an amount of at least 1.

The session tests are the phase's "done when": chop, relaunch, the tree is
still gone and the yield is still counted. They need no new production code
beyond `harvest` — the chunk is written because its version moved (Phase 7)
and the inventory because every save writes it (Phase 8) — which is exactly
what they prove.

**Files:**
- Create: `src/systems/harvest_result.gd`
- Modify: `src/systems/harvest_system.gd` — append `harvest`
- Test: `tests/test_harvest_system.gd`, `tests/test_game_session.gd`

**Interfaces:**
- Consumes: `HarvestSystem.yield_error` and `HarvestSystem.rng` (Task 2);
  `Inventory.add(item_id: String, amount: int) -> bool` (Phase 8);
  `Zone.in_bounds`, `.get_object`, `.set_object`, `.get_chunk`;
  `Walkability.recompute_chunk(chunk: Chunk, registry: ContentRegistry) -> int`;
  `Coords.world_to_chunk(w: Vector2i) -> Vector2i` (all existing).
- Produces:
  - `HarvestResult` — `ok: bool`; `reason: String` (`""` when ok, else one of
    `HarvestResult.OUT_OF_BOUNDS`, `.NOTHING_THERE`, `.NOT_HARVESTABLE`,
    `.BAD_YIELD`); `detail: String` (set for `BAD_YIELD`);
    `object_id: String`, `item_id: String`, `amount: int` (set when ok).
  - `HarvestSystem.harvest(zone: Zone, tile: Vector2i, inventory: Inventory, registry: ContentRegistry) -> HarvestResult`
    — an instance method, because it uses `rng`.

- [ ] **Step 1: Write the failing tests**

Append to `tests/test_harvest_system.gd`:

```gdscript


# --- harvest ----------------------------------------------------------

const TREE: Vector2i = Vector2i(5, 5)
const WALL: Vector2i = Vector2i(7, 5)
const EMPTY: Vector2i = Vector2i(9, 5)


func _registry_with_tree(harvestable: Variant) -> ContentRegistry:
	var r: ContentRegistry = _registry()
	r.register({"id": "tree", "category": "object", "display_name": "Tree",
		"sprite": "res://none.png", "blocks_movement": true,
		"harvestable": harvestable})
	return r


## One chunk of walkable grass with a tree at TREE and a wall at WALL.
func _zone(r: ContentRegistry) -> Zone:
	var zone: Zone = Zone.new("fixture", Vector2i(32, 32))
	var grass: int = r.numeric_of("grass")
	for y: int in range(32):
		for x: int in range(32):
			zone.set_terrain(Vector2i(x, y), grass)
	zone.set_object(TREE, r.numeric_of("tree"))
	zone.set_object(WALL, r.numeric_of("wall"))
	var _changed: int = Walkability.recompute_zone(zone, r)
	return zone


func _harvester() -> HarvestSystem:
	var h: HarvestSystem = HarvestSystem.new()
	h.rng.seed = 1
	return h


func _version(zone: Zone) -> int:
	return zone.get_chunk(Vector2i.ZERO).version


func _assert_refused(
	result: HarvestResult, reason: String, zone: Zone, inv: Inventory, version_before: int
) -> void:
	assert_false(result.ok)
	assert_eq(result.reason, reason)
	assert_eq(_version(zone), version_before, "a refused harvest writes no tile")
	assert_true(inv.is_empty(), "a refused harvest credits nothing")


func test_harvesting_removes_the_object_and_credits_its_yield() -> void:
	var r: ContentRegistry = _registry_with_tree({"item": "wood", "amount": [3, 3]})
	var zone: Zone = _zone(r)
	var inv: Inventory = Inventory.new()
	var result: HarvestResult = _harvester().harvest(zone, TREE, inv, r)
	assert_true(result.ok, result.detail)
	assert_eq(result.reason, "")
	assert_eq(zone.get_object(TREE), ContentRegistry.ID_UNKNOWN)
	assert_eq(inv.count_of("wood"), 3)
	assert_eq(result.object_id, "tree")
	assert_eq(result.item_id, "wood")
	assert_eq(result.amount, 3)


func test_the_cleared_tile_becomes_walkable() -> void:
	var r: ContentRegistry = _registry_with_tree({"item": "wood", "amount": [1, 1]})
	var zone: Zone = _zone(r)
	assert_false(zone.is_walkable(TREE), "precondition: the tree blocks")
	var _result: HarvestResult = _harvester().harvest(zone, TREE, Inventory.new(), r)
	assert_true(zone.is_walkable(TREE))


func test_a_harvest_advances_the_chunk_version() -> void:
	# The version is the only way the renderer, the collider and the save
	# learn that a tile changed.
	var r: ContentRegistry = _registry_with_tree({"item": "wood", "amount": [1, 1]})
	var zone: Zone = _zone(r)
	var before: int = _version(zone)
	var _result: HarvestResult = _harvester().harvest(zone, TREE, Inventory.new(), r)
	assert_gt(_version(zone), before)


func test_the_amount_stays_in_the_authored_range_and_reaches_both_ends() -> void:
	var r: ContentRegistry = _registry_with_tree({"item": "wood", "amount": [2, 4]})
	var zone: Zone = _zone(r)
	var inv: Inventory = Inventory.new()
	var h: HarvestSystem = _harvester()
	var seen: Dictionary = {}
	var total: int = 0
	for i: int in range(60):
		zone.set_object(TREE, r.numeric_of("tree"))
		var result: HarvestResult = h.harvest(zone, TREE, inv, r)
		seen[result.amount] = true
		total += result.amount
	var amounts: Array = seen.keys()
	amounts.sort()
	assert_eq(amounts, [2, 3, 4], "every value in the range, and nothing outside it")
	assert_eq(inv.count_of("wood"), total, "every roll was credited")


func test_json_float_amounts_yield_whole_numbers() -> void:
	var r: ContentRegistry = _registry_with_tree({"item": "wood", "amount": [2.0, 2.0]})
	var inv: Inventory = Inventory.new()
	var result: HarvestResult = _harvester().harvest(_zone(r), TREE, inv, r)
	assert_true(result.ok, result.detail)
	assert_eq(result.amount, 2)
	assert_eq(inv.count_of("wood"), 2)


func test_reaching_outside_the_zone_is_refused() -> void:
	var r: ContentRegistry = _registry_with_tree({"item": "wood", "amount": [1, 1]})
	var zone: Zone = _zone(r)
	var inv: Inventory = Inventory.new()
	var before: int = _version(zone)
	for tile: Vector2i in [Vector2i(-1, 5), Vector2i(32, 5), Vector2i(5, -1), Vector2i(5, 32)]:
		_assert_refused(_harvester().harvest(zone, tile, inv, r),
			HarvestResult.OUT_OF_BOUNDS, zone, inv, before)


func test_an_empty_tile_is_refused() -> void:
	var r: ContentRegistry = _registry_with_tree({"item": "wood", "amount": [1, 1]})
	var zone: Zone = _zone(r)
	var inv: Inventory = Inventory.new()
	var before: int = _version(zone)
	_assert_refused(_harvester().harvest(zone, EMPTY, inv, r),
		HarvestResult.NOTHING_THERE, zone, inv, before)


func test_an_object_with_no_yield_is_refused() -> void:
	var r: ContentRegistry = _registry_with_tree({"item": "wood", "amount": [1, 1]})
	var zone: Zone = _zone(r)
	var inv: Inventory = Inventory.new()
	var before: int = _version(zone)
	_assert_refused(_harvester().harvest(zone, WALL, inv, r),
		HarvestResult.NOT_HARVESTABLE, zone, inv, before)
	assert_eq(zone.get_object(WALL), r.numeric_of("wall"), "the wall is still there")


func test_content_the_build_cannot_see_is_not_harvestable() -> void:
	# A placeholder: an object a save names and this build does not ship.
	var r: ContentRegistry = _registry_with_tree({"item": "wood", "amount": [1, 1]})
	var zone: Zone = _zone(r)
	var gone: int = r.register_placeholder("gone")
	zone.set_object(EMPTY, gone)
	var inv: Inventory = Inventory.new()
	var before: int = _version(zone)
	_assert_refused(_harvester().harvest(zone, EMPTY, inv, r),
		HarvestResult.NOT_HARVESTABLE, zone, inv, before)
	assert_eq(zone.get_object(EMPTY), gone, "the placeholder keeps its tile")


func test_a_malformed_yield_leaves_the_tree_standing() -> void:
	# Destroying the object and crediting nothing is the worse failure.
	var r: ContentRegistry = _registry_with_tree({"item": "mithril", "amount": [1, 2]})
	var zone: Zone = _zone(r)
	var inv: Inventory = Inventory.new()
	var before: int = _version(zone)
	var result: HarvestResult = _harvester().harvest(zone, TREE, inv, r)
	_assert_refused(result, HarvestResult.BAD_YIELD, zone, inv, before)
	assert_eq(zone.get_object(TREE), r.numeric_of("tree"))
	assert_string_contains(result.detail, "tree")
	assert_string_contains(result.detail, "mithril")


func test_a_second_harvest_of_the_same_tile_finds_nothing() -> void:
	var r: ContentRegistry = _registry_with_tree({"item": "wood", "amount": [3, 3]})
	var zone: Zone = _zone(r)
	var inv: Inventory = Inventory.new()
	var h: HarvestSystem = _harvester()
	assert_true(h.harvest(zone, TREE, inv, r).ok)
	var again: HarvestResult = h.harvest(zone, TREE, inv, r)
	assert_false(again.ok)
	assert_eq(again.reason, HarvestResult.NOTHING_THERE)
	assert_eq(inv.count_of("wood"), 3, "one tree, one yield")
```

Append to `tests/test_game_session.gd`:

```gdscript


# --- harvesting -------------------------------------------------------

## The first tile of the authored zone holding anything harvestable.
func _first_harvestable(zone: Zone) -> Vector2i:
	for y: int in range(zone.size_tiles.y):
		for x: int in range(zone.size_tiles.x):
			var tile: Vector2i = Vector2i(x, y)
			if _registry.def_of(zone.get_object(tile)).has("harvestable"):
				return tile
	return Vector2i(-1, -1)


func _harvest(s: GameSession, tile: Vector2i) -> HarvestResult:
	var h: HarvestSystem = HarvestSystem.new()
	h.rng.seed = 1
	return h.harvest(s.zone, tile, s.inventory, _registry)


func test_a_harvested_object_stays_gone_and_its_yield_stays_counted() -> void:
	# The phase's "done when": chop, relaunch, still gone, still counted.
	var first: GameSession = _opened()
	var tile: Vector2i = _first_harvestable(first.zone)
	assert_true(first.zone.in_bounds(tile), "the authored zone has something to harvest")
	var got: HarvestResult = _harvest(first, tile)
	assert_true(got.ok, got.detail)
	assert_eq(first.save_now(_registry, "quit").size(), 0)
	first.close()

	var second: GameSession = _session()
	var r: SessionOpenResult = second.open_saved(_registry)
	assert_true(r.ok, r.error)
	assert_eq(second.zone.get_object(tile), ContentRegistry.ID_UNKNOWN,
		"the harvested object did not come back")
	assert_eq(second.inventory.count_of(got.item_id), got.amount)


func test_a_harvest_after_the_first_save_reaches_disk() -> void:
	# The first save writes every chunk. This one is incremental: it must
	# write the harvested chunk because its version moved, and only that.
	var first: GameSession = _opened()
	assert_eq(first.save_now(_registry, "new_world").size(), 0)
	var tile: Vector2i = _first_harvestable(first.zone)
	var got: HarvestResult = _harvest(first, tile)
	assert_true(got.ok, got.detail)
	assert_eq(first.save_now(_registry, "autosave").size(), 0)
	first.close()

	var second: GameSession = _session()
	assert_true(second.open_saved(_registry).ok)
	assert_eq(second.zone.get_object(tile), ContentRegistry.ID_UNKNOWN)
	assert_eq(second.inventory.count_of(got.item_id), got.amount)


func test_a_backup_load_keeps_the_harvest_but_not_its_yield() -> void:
	# KNOWN GAP, pinned on purpose -- see the Phase 9 plan. Chunks have no
	# backup (save_manager.gd: "A Stage 2 that makes chunks mutable must
	# rotate them too"), while inventory.json does. So the backup is the
	# live chunks with the previous inventory: the object is gone and its
	# yield is not counted. When chunk backups land this test must change,
	# and the right assertion is that both come back together.
	var s: GameSession = _opened()
	assert_eq(s.save_now(_registry, "first").size(), 0)
	var tile: Vector2i = _first_harvestable(s.zone)
	var got: HarvestResult = _harvest(s, tile)
	assert_true(got.ok, got.detail)
	assert_eq(s.save_now(_registry, "second").size(), 0)

	var restored: GameSession = _session()
	var r: SessionOpenResult = restored.open_saved(_registry, true)
	assert_true(r.ok, r.error)
	assert_eq(restored.zone.get_object(tile), ContentRegistry.ID_UNKNOWN)
	assert_eq(restored.inventory.count_of(got.item_id), 0)
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `./tools/run_tests.sh`
Expected: FAIL, exit 3 — `test_harvest_system.gd` and `test_game_session.gd`
do not parse: `Could not find type "HarvestResult" in the current scope`.

- [ ] **Step 3: Write the implementation**

Create `src/systems/harvest_result.gd`:

```gdscript
class_name HarvestResult
extends RefCounted
## What HarvestSystem.harvest returns.
##
## A refusal carries a reason the caller can branch on rather than a
## sentence to parse. Only BAD_YIELD is a fault worth logging -- it means
## content is wrong -- and it alone fills `detail`. The others are the
## player reaching for something that gives nothing.

const OUT_OF_BOUNDS: String = "out_of_bounds"
const NOTHING_THERE: String = "nothing_there"
const NOT_HARVESTABLE: String = "not_harvestable"
const BAD_YIELD: String = "bad_yield"

var ok: bool = false

## Empty when `ok`; otherwise one of the constants above.
var reason: String = ""
var detail: String = ""

## Only meaningful when `ok`: the string id of the object removed, the
## item credited, and how many.
var object_id: String = ""
var item_id: String = ""
var amount: int = 0


static func refusal(p_reason: String, p_detail: String = "") -> HarvestResult:
	var r: HarvestResult = HarvestResult.new()
	r.reason = p_reason
	r.detail = p_detail
	return r
```

Append to `src/systems/harvest_system.gd`:

```gdscript


## Removes the object on `tile` and credits its yield to `inventory`.
##
## Every refusal returns before the first write, so a refused harvest
## changes no tile, no flag and no count. The object is cleared through
## Zone.set_object, which advances the chunk's version: that is how the
## renderer, the collider and the save each learn of it, with nothing
## here knowing they exist.
func harvest(
	zone: Zone, tile: Vector2i, inventory: Inventory, registry: ContentRegistry
) -> HarvestResult:
	if not zone.in_bounds(tile):
		return HarvestResult.refusal(HarvestResult.OUT_OF_BOUNDS)
	var obj: int = zone.get_object(tile)
	if obj == ContentRegistry.ID_UNKNOWN:
		return HarvestResult.refusal(HarvestResult.NOTHING_THERE)
	var def: Dictionary = registry.def_of(obj)
	if registry.is_placeholder(obj) or not def.has("harvestable"):
		return HarvestResult.refusal(HarvestResult.NOT_HARVESTABLE)
	var object_id: String = registry.string_of(obj)
	var problem: String = yield_error(def["harvestable"], registry)
	if problem != "":
		return HarvestResult.refusal(
			HarvestResult.BAD_YIELD, "%s: %s" % [object_id, problem])

	var yields: Dictionary = def["harvestable"]
	var bounds: Array = yields["amount"]
	var amount: int = rng.randi_range(roundi(float(bounds[0])), roundi(float(bounds[1])))
	var item_id: String = str(yields["item"])

	zone.set_object(tile, ContentRegistry.ID_UNKNOWN)
	# Walkability owns the walkable rule; setting the flag byte by hand
	# would also clobber FLAG_BLOCKS_LIGHT, which shares it.
	var _changed: int = Walkability.recompute_chunk(
		zone.get_chunk(Coords.world_to_chunk(tile)), registry)
	# Cannot refuse: yield_error guaranteed an id and an amount of at least 1.
	var _added: bool = inventory.add(item_id, amount)

	var r: HarvestResult = HarvestResult.new()
	r.ok = true
	r.object_id = object_id
	r.item_id = item_id
	r.amount = amount
	return r
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `./tools/run_tests.sh`
Expected: PASS, all suites.

Run: `./tools/godot.sh --headless --path . -s tools/guard.gd`
Expected: `Architecture guard: clean`.

Run: `git status --short tests/fixtures`
Expected: no output — no test wrote into a committed fixture.

- [ ] **Step 5: Commit**

```bash
git add src/systems/harvest_result.gd src/systems/harvest_result.gd.uid src/systems/harvest_system.gd tests/test_harvest_system.gd tests/test_game_session.gd
git commit -m "feat: harvesting moves an object into the inventory, and it stays moved"
```

- [ ] **Step 6: Tick the task**

```bash
python3 tools/mark_task_done.py 3 --plan docs/superpowers/plans/2026-10-03-rp1-phase9-harvesting.md
git add docs/superpowers/plans/2026-10-03-rp1-phase9-harvesting.md
git commit -m "docs: tick Phase 9 task 3"
```

---

## Task 4: The `interact` key, routed

The player's side of it. `World` hears the key and says *where* — the tile
the player faces. `main.gd` holds the session, so it decides *what*: it asks
`HarvestSystem`, and prints the result. `World` is `PROCESS_MODE_PAUSABLE`,
so the key is not heard while paused, and it does not exist at the menu.

The signal carries a tile and no verb. Phase 10's build mode will want the
same key to mean other things; the router is where that is decided.

**Files:**
- Modify: `project.godot` — `[input]`, after `pause`
- Modify: `src/presentation/world.gd` — a signal, and `_unhandled_input`
- Modify: `src/presentation/main.gd` — `_harvest` var, `_ready`, `_enter_world`, a handler
- Modify: `src/ui/controls_hint.gd` — the hint text
- Test: `tests/test_input_map.gd`

**Interfaces:**
- Consumes: `HarvestSystem.harvest(zone, tile, inventory, registry) -> HarvestResult`,
  `HarvestSystem.rng`, `HarvestResult.ok/.reason/.detail/.object_id/.item_id/.amount`,
  `HarvestResult.BAD_YIELD` (Task 3); `World._player_facing_tile()` (Task 1);
  `GameSession.zone`, `GameSession.inventory` (existing).
- Produces: the `interact` input action; `World.interact_requested(tile: Vector2i)`.

- [ ] **Step 1: Write the failing tests**

Append to `tests/test_input_map.gd`:

```gdscript


func test_the_interact_action_is_bound_to_e() -> void:
	assert_true(InputMap.has_action("interact"))
	var found: bool = false
	for event: InputEvent in InputMap.action_get_events("interact"):
		if event is InputEventKey and (event as InputEventKey).physical_keycode == KEY_E:
			found = true
	assert_true(found, "interact is not bound to E")


func test_the_interact_action_is_bound_to_a_gamepad_button() -> void:
	# A real action, not a debug one: it gets a gamepad binding like pause.
	var found: bool = false
	for event: InputEvent in InputMap.action_get_events("interact"):
		if event is InputEventJoypadButton:
			found = true
	assert_true(found, "interact has no gamepad binding")
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `./tools/run_tests.sh`
Expected: FAIL — `interact is not bound to E` and
`interact has no gamepad binding`.

- [ ] **Step 3: Add the action, the signal and the route**

In `project.godot`, directly after the closing `}` of `pause` and before
`debug_place`, add (physical keycode 69 is `E`; joypad button 0 is `A`):

```
interact={
"deadzone": 0.2,
"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":69,"key_label":0,"unicode":0,"location":0,"echo":false,"script":null)
, Object(InputEventJoypadButton,"resource_local_to_scene":false,"resource_name":"","device":-1,"button_index":0,"pressure":0.0,"pressed":false,"script":null)
]
}
```

In `src/presentation/world.gd`, directly after the class doc comment and
before `var zone: Zone = null`, add:

```gdscript
## Emitted when the player presses interact, carrying the tile they face.
## The world only says where. What interacting there means is the
## router's decision -- Stage 2 design 3.5: presentation emits, the
## router decides -- so no presentation node writes to the Zone for it.
signal interact_requested(tile: Vector2i)

```

In the same file, replace `_unhandled_input` — keeping the
`## World is PROCESS_MODE_PAUSABLE, so this is not heard while paused.`
comment above it — with:

```gdscript
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact"):
		get_viewport().set_input_as_handled()
		if zone != null and zone.entities.has(player_entity_id):
			interact_requested.emit(_player_facing_tile())
		return
	if event.is_action_pressed("debug_place"):
		get_viewport().set_input_as_handled()
		_debug_place_wall()
```

In `src/presentation/main.gd`, after `var _session: GameSession = null`, add:

```gdscript
var _harvest: HarvestSystem = null
```

In `_ready`, directly after `_session = GameSession.new()`, add:

```gdscript

	_harvest = HarvestSystem.new()
	_harvest.rng.randomize()
```

In `_enter_world`, directly after `add_child(_world)`, add:

```gdscript
	_world.interact_requested.connect(_on_interact_requested)
```

In the same file, directly after `_enter_world` and before
`func _on_quit_to_menu`, add:

```gdscript
## The world said which tile the player reached for; this decides what
## that means. Until build mode it means one thing: harvest it. A refusal
## is silence -- there was nothing to take -- unless the content itself
## is wrong, which is worth an error.
func _on_interact_requested(tile: Vector2i) -> void:
	if _world == null or _session.zone == null:
		return
	var result: HarvestResult = _harvest.harvest(
		_session.zone, tile, _session.inventory, _registry)
	if result.ok:
		print("RP1 harvested %s: %s +%d (now %d)" % [
			result.object_id, result.item_id, result.amount,
			_session.inventory.count_of(result.item_id)])
	elif result.reason == HarvestResult.BAD_YIELD:
		push_error("harvest refused: %s" % result.detail)


```

In `src/ui/controls_hint.gd`, change the label text line to:

```gdscript
	_label.text = "WASD or arrows to move    E to harvest    Esc to pause"
```

and the file's first doc line from `## WASD / Esc, once per player, ever.` to:

```gdscript
## WASD / E / Esc, once per player, ever.
```

- [ ] **Step 4: Run the tests and every local gate**

Run: `./tools/run_tests.sh`
Expected: PASS, all suites; `test_the_movement_actions_still_exist` still
passes, proving the hand-edited `[input]` section is intact.

Run each, and expect exit 0 from all:

```bash
./tools/godot.sh --headless --path . -s tools/guard.gd      # Architecture guard: clean
./tools/godot.sh --headless --path . -s tools/smoke.gd      # Smoke test: OK
./tools/check_asset_licences.sh                             # Asset licences: OK
./tools/check_palette.sh                                    # Palette: OK
./tools/check_zone.sh                                       # Zone gate: OK
```

- [ ] **Step 5: Prove the phase end to end**

`main.gd` and `World` have no unit tests, so the key → signal → router →
system → save path is proved by driving the real main scene with real key
events, in two separate processes so the relaunch is real.

**It runs against a throwaway save root.** Do not prove this by hand in the
developer's own world without asking: `user://saves/home` is a real save.

Write the script outside the repository (it is never committed):

```bash
DRIVE="${TMPDIR:-/tmp}/phase9_drive.gd"
cat > "$DRIVE" <<'EOF'
extends SceneTree
## Throwaway: Phase 9's end-to-end proof. Run as "a", then as "b" in a
## second process. Uses its own save root; the real one is never touched.

const ROOT: String = "user://test_saves/phase9_drive"
const STATE: String = "user://test_saves/phase9_drive_state.json"

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


func _expect(label: String, got: Variant, want: Variant) -> void:
	var ok: bool = got == want
	if not ok:
		_failed = true
	print("DRIVE %s: %s -> %s (want %s)" % ["ok  " if ok else "FAIL", label, got, want])


## The first harvestable tile with walkable ground directly south of it.
func _target(zone: Zone, registry: ContentRegistry) -> Vector2i:
	for y: int in range(zone.size_tiles.y):
		for x: int in range(zone.size_tiles.x):
			var t: Vector2i = Vector2i(x, y)
			if registry.def_of(zone.get_object(t)).has("harvestable") \
					and zone.is_walkable(t + Vector2i(0, 1)):
				return t
	return Vector2i(-1, -1)


## Stands the player on the tile south of `t`, facing north at it.
func _stand_below(zone: Zone, pid: int, t: Vector2i) -> void:
	zone.entities.set_position(pid, Vector2(t.x + 0.5, t.y + 1.75))
	zone.entities.set_facing(pid, MovementSystem.FACING_N)


func _total(inv: Inventory) -> int:
	var n: int = 0
	for id: String in inv.item_ids():
		n += inv.count_of(id)
	return n


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

		var t1: Vector2i = _target(zone, registry)
		_expect("1 the zone has something to harvest", zone.in_bounds(t1), true)
		_stand_below(zone, pid, t1)
		await _frames(2)
		await _key(KEY_E)
		_expect("1 E removed the object", zone.get_object(t1), 0)
		_expect("1 the tile is walkable now", zone.is_walkable(t1), true)
		var after_first: int = _total(inv)
		_expect("1 something was credited", after_first > 0, true)

		await _key(KEY_E)
		_expect("2 E at the empty tile credits nothing", _total(inv), after_first)

		var t2: Vector2i = _target(zone, registry)
		_stand_below(zone, pid, t2)
		await _frames(2)
		await _key(KEY_ESCAPE)
		_expect("3 Esc paused the tree", paused, true)
		await _key(KEY_E)
		_expect("3 E while paused harvests nothing", zone.get_object(t2) != 0, true)
		await _key(KEY_ESCAPE)
		_expect("3 Esc unpaused", paused, false)
		await _key(KEY_E)
		_expect("3 E after unpausing harvests", zone.get_object(t2), 0)

		var counts: Dictionary = {}
		for id: String in inv.item_ids():
			counts[id] = inv.count_of(id)
		_main._on_quit_to_menu()
		await _frames(3)
		_expect("4 back at the menu", _main._world == null, true)
		var f: FileAccess = FileAccess.open(STATE, FileAccess.WRITE)
		f.store_string(JSON.stringify(
			{"tiles": [[t1.x, t1.y], [t2.x, t2.y]], "counts": counts}))
		f.close()
	else:
		var state: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(STATE))
		_main._on_continue_requested()
		await _frames(3)
		var zone: Zone = _main._session.zone
		_expect("5 relaunched and continued", zone != null, true)
		for xy: Array in state["tiles"]:
			var t: Vector2i = Vector2i(int(xy[0]), int(xy[1]))
			_expect("5 %s is still gone" % t, zone.get_object(t), 0)
		for id: String in state["counts"]:
			_expect("5 %s is still counted" % id,
				_main._session.inventory.count_of(id), int(state["counts"][id]))
		print("DRIVE inventory.json on disk:")
		print(FileAccess.get_file_as_string(ROOT.path_join("inventory.json")))
		_wipe(ROOT)
		DirAccess.remove_absolute(STATE)
	quit(1 if _failed else 0)
EOF
./tools/godot.sh --headless --path . -s "$DRIVE" -- a 2>&1 | grep -E "DRIVE|RP1 harvested|RP1 saved|ERROR"
./tools/godot.sh --headless --path . -s "$DRIVE" -- b 2>&1 | grep -E "DRIVE|RP1 harvested|RP1 saved|ERROR|wood|stone"
rm -f "$DRIVE"
```

Expected, process `a`: two `RP1 harvested <object>: <item> +N (now M)`
lines, every `DRIVE` line reads `ok`, and no `DRIVE FAIL`. Process `b`:
every `DRIVE` line reads `ok`, and the printed `inventory.json` holds the
counts process `a` ended with. Neither run may print `harvest refused`.
`ERROR: 2 resources still in use at exit` is printed by both runs: it is
the script quitting with the main scene still loaded, not a failure.

Write what each numbered step printed in the commit message body. If any
line reads `FAIL`, stop and report it — do not tick the task.

This is a scripted run, not a hand run, and the commit body and the PR
description must say so. A person pressing `E` at a tree in a window is
still worth doing once before the phase is called closed; ask the developer
whether to do it in their real world.

- [ ] **Step 6: Commit**

```bash
git add project.godot src/presentation/world.gd src/presentation/main.gd src/ui/controls_hint.gd tests/test_input_map.gd
git commit -m "feat: E harvests the tile the player faces

Scripted run against a throwaway save root: <one line per step 1-5>"
```

- [ ] **Step 7: Tick the task**

```bash
python3 tools/mark_task_done.py 4 --plan docs/superpowers/plans/2026-10-03-rp1-phase9-harvesting.md
git add docs/superpowers/plans/2026-10-03-rp1-phase9-harvesting.md
git commit -m "docs: tick Phase 9 task 4"
```

---

## Definition of done

- [ ] Every shipped `harvestable` resolves to a registered item with a
      valid range — `test_every_shipped_harvestable_resolves`
- [ ] Harvesting clears the object, opens the tile and credits the yield —
      Task 3's `test_harvest_system.gd` tests
- [ ] A refused harvest changes no tile, no flag and no count
- [ ] Chop, relaunch: the object is still gone and the yield still counted —
      `test_a_harvested_object_stays_gone_and_its_yield_stays_counted` and
      Task 4 step 5
- [ ] The same holds for a harvest made after the first save —
      `test_a_harvest_after_the_first_save_reaches_disk`
- [ ] `E` and a gamepad button are bound to `interact`
- [ ] No object id, item id or amount is written in GDScript:
      `grep -nE '"(wood|stone|oak_tree|pine_tree|dead_tree|rock_small|rock_large)"' src/systems/harvest_system.gd src/systems/harvest_result.gd src/presentation/world.gd`
      prints nothing
- [ ] No save format changed: `git diff main --stat` shows none of
      `chunk_codec.gd`, `entity_codec.gd`, `inventory_codec.gd`, `save_manager.gd`
- [ ] All six local gates green, and CI green on the branch

Tick with `python3 tools/mark_task_done.py --section "Definition of done" --plan docs/superpowers/plans/2026-10-03-rp1-phase9-harvesting.md`.
