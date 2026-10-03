# Phase 8 — Items, and an Inventory that Persists Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `item` as the fifth content category, an `Inventory` of bulk
counts in core, and an `inventory.json` beside `meta.json` that survives a
relaunch, resets on New World, and is simply absent from a Stage 1 save.

**Architecture:** Items are data (`data/item/*.json`) registered through the
existing `ContentRegistry` by appending `"item"` to `CATEGORIES`. `Inventory`
is a `RefCounted` string-keyed `Dictionary` of item id → count; it never
touches the registry, so an item the build no longer ships keeps its count
verbatim. `InventoryCodec` turns it into JSON and back with a
`DecodeResult`. `GameSession` owns the live inventory: it resets it on
`open_new` and `close`, reads it on `open_saved` (missing file → empty,
malformed file → the open fails), and writes it atomically with a backup on
every `save_now`. No binary codec changes, so no migration.

**Tech Stack:** Godot 4.7.2 stable (standard build, **not** Mono), GDScript
only, GUT for tests.

**Spec:** `docs/superpowers/specs/2026-09-22-rp1-stage2-design.md` — §3.3
(items), §3.4 (inventory and its persistence), §6 (testing), and the Phase 8
entry in §4.

## Global Constraints

- Godot **4.7.2**, standard build. Invoke only through `./tools/godot.sh`.
- GDScript only. No C#. No `TileMap` — `TileMapLayer` only.
- Static typing everywhere: `var x: int = 0`, `func f(a: Vector2i) -> void:`.
- `src/core/` and `src/systems/` **MUST NOT reference Godot nodes.** No
  `extends Node`, no `get_tree()`, no `Engine.`, no `.tscn`. `RefCounted`
  only. Enforced by `tools/guard.gd`.
- Presentation reads from world data. World data never reads from presentation.
- All game content lives in `data/*.json`. Never `match` over content
  categories — look them up in `ContentRegistry`.
- Never use `load()`, `ResourceLoader`, or `.tres`/`.res` for save data.
- All writes are atomic: temp file, `flush()`, `close()`, then rename — use
  `SaveManager.atomic_write`, never a bare `FileAccess.open(..., WRITE)`.
- Saves persist **string ids**, never runtime numeric ids.
- Content named in a save but missing from the build is **retained with its
  original string** — never silently zeroed.
- Run tests with `./tools/run_tests.sh` — never `gut_cmdln.gd` directly. The
  runner does a mandatory `--import` pass first; without it GUT reports missing
  `class_name`s **and exits 0**, so a broken suite looks green.
- TDD: write the failing test, watch it fail, implement minimally, watch it pass.
- Every file in `core/` and `systems/` has a matching test in `tests/`.
- New content types require a schema validation test.
- Conventional commit prefixes: `feat:`, `test:`, `ci:`, `docs:`, `fix:`.
- Each task produces two commits: the code, then a `docs:` commit ticking that
  task's checkboxes with `python3 tools/mark_task_done.py <n> --plan <this file>`
  (on a Windows machine where `python3` is the Store stub, use `python`).

## Review Focus

1. **New World over an existing world with items in it.** The player expects
   zero of everything. `inventory.json` is rewritten on *every* save, empty
   or not, so the old world's file cannot survive the overwrite — Task 4,
   `test_new_world_resets_the_inventory`, which reopens from a second session.
2. **A save naming an item this build does not ship** (renamed or deleted
   JSON). The player expects the count to come back if the item does; the
   codec never consults the registry, so the key round-trips verbatim — Task 3,
   `test_an_item_the_build_does_not_know_survives_a_round_trip`.
3. **A hand-edited or corrupt `inventory.json`** (negative, fractional or
   string counts; `items` not an object; not JSON at all). The player expects
   not to silently lose everything. The open fails, which routes into
   `main.gd`'s existing "load backup instead?" flow — Task 3's rejection
   tests, and Task 4, `test_a_malformed_inventory_fails_the_open_and_changes_nothing`.
4. **Loading from backup.** The player expects the inventory that belongs to
   that backup; and a Stage 1 save upgraded by one Stage 2 save has
   `meta.json.bak` but no `inventory.json.bak`, which must load as empty, not
   fail — Task 4, `test_the_backup_carries_its_own_inventory` and
   `test_a_backup_with_no_inventory_opens_empty`.
5. **Removing more than is held, or a zero/negative amount.** Expected: the
   call refuses and nothing changes — Task 2,
   `test_removing_more_than_is_held_refuses_and_changes_nothing` and the
   non-positive-amount tests.

---

## File Structure

| File | Responsibility |
|---|---|
| `data/schema/item.json` | **Create.** Schema for the fifth category. |
| `data/item/wood.json`, `data/item/stone.json` | **Create.** The two items the spec names. |
| `src/core/content_registry.gd` | **Modify.** `"item"` appended to `CATEGORIES`. |
| `src/core/inventory.gd` | **Create.** Item id → count; `add`, `remove`, `can_afford`, `count_of`. |
| `src/core/save/inventory_codec.gd` | **Create.** `Inventory` ↔ `inventory.json` text. |
| `src/systems/game_session.gd` | **Modify.** Owns the live inventory; reads, resets and writes it. |
| `tests/fixtures/stage1_save/` | **Create.** A save directory written by the Stage 1 build. |
| `src/presentation/main.gd` | **Modify.** DEBUG ONLY: a key that grants wood. |
| `project.godot` | **Modify.** `debug_grant` action on `G`. |

Tests: `tests/test_item_schema.gd` (new), `tests/test_content_registry.gd`,
`tests/test_inventory.gd` (new), `tests/test_inventory_codec.gd` (new),
`tests/test_game_session.gd`, `tests/test_input_map.gd`.

**Deliberately not in this phase:** `cost` on placeable content and
resolving `harvestable.item` against the registry. `cost` has no consumer
until Phase 10 spends it, and `harvestable` resolves in Phase 9 — adding
either now is a schema field nothing reads.

---

## Task 1: Items, the fifth content category

Same one-line registry change that added `"sound"` in Phase 6. `"item"` is
**appended**, never inserted: `load_from_dir` assigns numeric ids in
category order, so inserting it would renumber every creature and sound.

**Files:**
- Create: `data/schema/item.json`, `data/item/wood.json`, `data/item/stone.json`
- Create: `tests/test_item_schema.gd`
- Modify: `src/core/content_registry.gd:10`
- Modify: `tests/test_content_registry.gd:105-109`

**Interfaces:**
- Produces: the `item` category. An item def is
  `{"id": String, "category": "item", "display_name": String, "tags"?: Array}`,
  read through the existing `ContentRegistry.numeric_of(string_id) -> int` and
  `ContentRegistry.def_of(numeric_id) -> Dictionary`. Shipped ids: `"wood"`,
  `"stone"`.

- [x] **Step 1: Write the failing schema test**

Create `tests/test_item_schema.gd`:

```gdscript
extends GutTest
## The item category: things the inventory counts. An item has no sprite
## yet -- nothing draws one until build mode's palette in Phase 10.

const SCHEMA_PATH: String = "res://data/schema/item.json"


func _schema() -> Dictionary:
	var json: JSON = JSON.new()
	assert_eq(json.parse(FileAccess.get_file_as_string(SCHEMA_PATH)), OK,
		"item.json must be valid JSON")
	return json.data as Dictionary


func _valid_def() -> Dictionary:
	return {
		"id": "wood",
		"category": "item",
		"display_name": "Wood",
		"tags": ["resource"],
	}


func test_a_minimal_item_validates() -> void:
	assert_eq(SchemaValidator.validate(_valid_def(), _schema()).size(), 0)


func test_tags_are_optional() -> void:
	var d: Dictionary = _valid_def()
	d.erase("tags")
	assert_eq(SchemaValidator.validate(d, _schema()).size(), 0)


func test_display_name_is_required() -> void:
	var d: Dictionary = _valid_def()
	d.erase("display_name")
	var errs: PackedStringArray = SchemaValidator.validate(d, _schema())
	assert_eq(errs.size(), 1)
	assert_string_contains(errs[0], "display_name")


func test_an_unknown_field_is_rejected() -> void:
	# Catches a premature "stack_size": §1.1 says counts are bulk, and a
	# field nothing reads is a promise nothing keeps.
	var d: Dictionary = _valid_def()
	d["stack_size"] = 99
	var errs: PackedStringArray = SchemaValidator.validate(d, _schema())
	assert_eq(errs.size(), 1)
	assert_string_contains(errs[0], "stack_size")


func test_the_wrong_category_is_rejected() -> void:
	var d: Dictionary = _valid_def()
	d["category"] = "object"
	assert_eq(SchemaValidator.validate(d, _schema()).size(), 1)


func test_the_shipped_items_register() -> void:
	var r: ContentRegistry = ContentRegistry.new()
	var errors: PackedStringArray = r.load_from_dir("res://data")
	assert_eq(errors.size(), 0, "\n".join(errors))
	for sid: String in ["wood", "stone"]:
		assert_true(r.has_string(sid), "%s is registered" % sid)
		assert_eq(str(r.def_of(r.numeric_of(sid)).get("category", "")), "item",
			"%s is an item" % sid)


func test_oak_trees_already_name_a_real_item() -> void:
	# oak_tree.json has declared {"item": "wood"} since Stage 1. Phase 9
	# resolves it; this pins that the id it names now exists.
	var r: ContentRegistry = ContentRegistry.new()
	var _e: PackedStringArray = r.load_from_dir("res://data")
	var oak: Dictionary = r.def_of(r.numeric_of("oak_tree"))
	var item_id: String = str((oak["harvestable"] as Dictionary)["item"])
	assert_true(r.has_string(item_id), "oak_tree yields '%s', which exists" % item_id)
```

In `tests/test_content_registry.gd`, replace `test_sound_is_the_last_category`
(lines 105-109) with:

```gdscript
func test_item_is_the_last_category() -> void:
	# Appended, not inserted: load_from_dir assigns numeric ids in
	# category order, so inserting would renumber every creature, object
	# and sound in the build.
	assert_eq(ContentRegistry.CATEGORIES[ContentRegistry.CATEGORIES.size() - 1], "item")
	assert_eq(ContentRegistry.CATEGORIES[ContentRegistry.CATEGORIES.size() - 2], "sound")
```

- [x] **Step 2: Run the tests to verify they fail**

Run: `./tools/run_tests.sh`
Expected: FAIL — `test_item_schema.gd` cannot parse `item.json` (missing),
`test_the_shipped_items_register` finds no `wood`, and
`test_item_is_the_last_category` sees `"sound"`.

- [x] **Step 3: Write the schema, the items, and the registry line**

Create `data/schema/item.json`:

```json
{
  "category": "item",
  "required": {"id": "String", "category": "String", "display_name": "String"},
  "optional": {"tags": "Array"}
}
```

Create `data/item/wood.json`:

```json
{"id": "wood", "category": "item", "display_name": "Wood",
 "tags": ["resource"]}
```

Create `data/item/stone.json`:

```json
{"id": "stone", "category": "item", "display_name": "Stone",
 "tags": ["resource"]}
```

In `src/core/content_registry.gd`, change line 10 to:

```gdscript
const CATEGORIES: PackedStringArray = ["terrain", "object", "creature", "sound", "item"]
```

- [x] **Step 4: Run the tests to verify they pass**

Run: `./tools/run_tests.sh`
Expected: PASS, all suites. `test_import_manifest.gd` and
`test_tileset_builder.gd` skip items because items have no `sprite` and are
not a tile category — if either fails, an item grew a field it should not have.

- [x] **Step 5: Commit**

```bash
git add data/schema/item.json data/item/ src/core/content_registry.gd tests/test_item_schema.gd tests/test_content_registry.gd
git commit -m "feat: items, the fifth content category"
```

- [x] **Step 6: Tick the task**

```bash
python3 tools/mark_task_done.py 1 --plan docs/superpowers/plans/2026-09-29-rp1-phase8-items-inventory.md
git add docs/superpowers/plans/2026-09-29-rp1-phase8-items-inventory.md
git commit -m "docs: tick Phase 8 task 1"
```

---

## Task 2: `Inventory` in core

Bulk counts, no slots, no stack limits (§1.1). It holds string ids and never
looks at the registry — that is what lets an item missing from the build keep
its count (the placeholder rule), and it keeps the class testable with no
content loaded at all.

A count of zero is not stored: the key is erased. That keeps `inventory.json`
free of `"wood": 0` litter and makes `item_ids()` mean "what the player has".

**Files:**
- Create: `src/core/inventory.gd`
- Test: `tests/test_inventory.gd`

**Interfaces:**
- Produces:
  - `Inventory.count_of(item_id: String) -> int` — `0` for anything not held.
  - `Inventory.add(item_id: String, amount: int) -> bool` — `false` and no
    change if `item_id` is empty or `amount <= 0`.
  - `Inventory.remove(item_id: String, amount: int) -> bool` — `false` and no
    change if `amount <= 0` or `amount > count_of(item_id)`.
  - `Inventory.can_afford(cost: Dictionary) -> bool` — `cost` is item id →
    amount, as JSON will hand it over (amounts may be integral floats).
    `true` for `{}`. `false` if any amount is negative, non-integral, or not
    a number.
  - `Inventory.item_ids() -> PackedStringArray` — held ids, sorted.
  - `Inventory.is_empty() -> bool`

- [x] **Step 1: Write the failing tests**

Create `tests/test_inventory.gd`:

```gdscript
extends GutTest
## Bulk counts of items by string id. No registry in sight: the inventory
## must hold an id this build does not ship without zeroing it.

var _inv: Inventory


func before_each() -> void:
	_inv = Inventory.new()


func test_a_new_inventory_is_empty() -> void:
	assert_true(_inv.is_empty())
	assert_eq(_inv.item_ids().size(), 0)
	assert_eq(_inv.count_of("wood"), 0)


func test_adding_accumulates() -> void:
	assert_true(_inv.add("wood", 3))
	assert_true(_inv.add("wood", 4))
	assert_eq(_inv.count_of("wood"), 7)
	assert_false(_inv.is_empty())


func test_items_are_counted_independently() -> void:
	_inv.add("wood", 3)
	_inv.add("stone", 5)
	assert_eq(_inv.count_of("wood"), 3)
	assert_eq(_inv.count_of("stone"), 5)


func test_adding_a_non_positive_amount_refuses_and_changes_nothing() -> void:
	_inv.add("wood", 2)
	assert_false(_inv.add("wood", 0))
	assert_false(_inv.add("wood", -5))
	assert_eq(_inv.count_of("wood"), 2)


func test_adding_under_an_empty_id_refuses() -> void:
	assert_false(_inv.add("", 5))
	assert_true(_inv.is_empty())


func test_removing_decrements() -> void:
	_inv.add("wood", 5)
	assert_true(_inv.remove("wood", 2))
	assert_eq(_inv.count_of("wood"), 3)


func test_removing_exactly_what_is_held_empties_the_entry() -> void:
	_inv.add("wood", 5)
	assert_true(_inv.remove("wood", 5))
	assert_eq(_inv.count_of("wood"), 0)
	assert_false(_inv.item_ids().has("wood"), "a zero count is not stored")
	assert_true(_inv.is_empty())


func test_removing_more_than_is_held_refuses_and_changes_nothing() -> void:
	_inv.add("wood", 5)
	assert_false(_inv.remove("wood", 6))
	assert_eq(_inv.count_of("wood"), 5, "a refused removal never goes partway")


func test_removing_something_never_held_refuses() -> void:
	assert_false(_inv.remove("stone", 1))
	assert_true(_inv.is_empty())


func test_removing_a_non_positive_amount_refuses_and_changes_nothing() -> void:
	_inv.add("wood", 5)
	assert_false(_inv.remove("wood", 0))
	# A negative removal would be an add through the back door.
	assert_false(_inv.remove("wood", -3))
	assert_eq(_inv.count_of("wood"), 5)


func test_can_afford_at_the_boundary() -> void:
	_inv.add("wood", 2)
	assert_true(_inv.can_afford({"wood": 2}), "exactly enough is enough")
	assert_false(_inv.can_afford({"wood": 3}), "one short is not")


func test_can_afford_needs_every_item_in_the_cost() -> void:
	_inv.add("wood", 5)
	_inv.add("stone", 1)
	assert_true(_inv.can_afford({"wood": 2, "stone": 1}))
	assert_false(_inv.can_afford({"wood": 2, "stone": 2}))
	assert_false(_inv.can_afford({"wood": 2, "iron": 1}), "an unheld item is unaffordable")


func test_the_empty_cost_is_always_affordable() -> void:
	assert_true(_inv.can_afford({}))


func test_can_afford_accepts_the_integral_floats_json_produces() -> void:
	# JSON.parse gives floats for every number, and cost will come from
	# data/*.json in Phase 10.
	_inv.add("wood", 2)
	assert_true(_inv.can_afford({"wood": 2.0}))
	assert_false(_inv.can_afford({"wood": 3.0}))


func test_can_afford_refuses_a_malformed_cost() -> void:
	_inv.add("wood", 5)
	assert_false(_inv.can_afford({"wood": -1}), "a negative cost is a refund, not a price")
	assert_false(_inv.can_afford({"wood": 1.5}), "half a plank is not a price")
	assert_false(_inv.can_afford({"wood": "2"}), "a string is not a price")


func test_can_afford_does_not_spend() -> void:
	_inv.add("wood", 2)
	var _ok: bool = _inv.can_afford({"wood": 2})
	assert_eq(_inv.count_of("wood"), 2)


func test_item_ids_are_sorted() -> void:
	_inv.add("wood", 1)
	_inv.add("stone", 1)
	_inv.add("clay", 1)
	assert_eq(_inv.item_ids(), PackedStringArray(["clay", "stone", "wood"]))


func test_an_id_unknown_to_any_registry_is_held_like_any_other() -> void:
	_inv.add("mithril", 4)
	assert_eq(_inv.count_of("mithril"), 4)
```

- [x] **Step 2: Run the tests to verify they fail**

Run: `./tools/run_tests.sh`
Expected: FAIL — `Inventory` is not a known class.

- [x] **Step 3: Write the implementation**

Create `src/core/inventory.gd`:

```gdscript
class_name Inventory
extends RefCounted
## Bulk counts of items, keyed by string id.
##
## No slots and no stack limits: a building sandbox spends resources in
## bulk. Keys are string ids rather than registry numerics, so the
## inventory persists without a translation table, and an item this build
## does not ship keeps its count instead of being zeroed. That is also why
## nothing here consults the ContentRegistry.
##
## A zero count is never stored. Every method that refuses leaves the
## inventory exactly as it was.

var _counts: Dictionary = {}  ## item id (String) -> count (int), always > 0


func count_of(item_id: String) -> int:
	return _counts.get(item_id, 0)


func is_empty() -> bool:
	return _counts.is_empty()


func item_ids() -> PackedStringArray:
	var out: PackedStringArray = []
	for item_id: String in _counts:
		out.append(item_id)
	out.sort()
	return out


func add(item_id: String, amount: int) -> bool:
	if item_id.is_empty() or amount <= 0:
		return false
	_counts[item_id] = count_of(item_id) + amount
	return true


func remove(item_id: String, amount: int) -> bool:
	if amount <= 0:
		return false
	var held: int = count_of(item_id)
	if amount > held:
		return false
	if amount == held:
		_counts.erase(item_id)
	else:
		_counts[item_id] = held - amount
	return true


## `cost` maps item id to amount, straight from JSON, so an amount may
## arrive as an integral float. Anything that is not a whole, non-negative
## number makes the cost unaffordable rather than quietly rounded.
func can_afford(cost: Dictionary) -> bool:
	for item_id: Variant in cost:
		var amount: Variant = cost[item_id]
		if not (amount is int or amount is float):
			return false
		if not is_equal_approx(float(amount), roundf(float(amount))):
			return false
		var need: int = int(amount)
		if need < 0 or need > count_of(str(item_id)):
			return false
	return true
```

- [x] **Step 4: Run the tests to verify they pass**

Run: `./tools/run_tests.sh`
Expected: PASS, all suites.

- [x] **Step 5: Commit**

```bash
git add src/core/inventory.gd tests/test_inventory.gd
git commit -m "feat: an inventory of bulk counts"
```

- [x] **Step 6: Tick the task**

```bash
python3 tools/mark_task_done.py 2 --plan docs/superpowers/plans/2026-09-29-rp1-phase8-items-inventory.md
git add docs/superpowers/plans/2026-09-29-rp1-phase8-items-inventory.md
git commit -m "docs: tick Phase 8 task 2"
```

---

## Task 3: `InventoryCodec` — `inventory.json`

JSON rather than binary for the reason `meta.json` is: small, cold, and worth
reading with `cat`. It carries its own `format_version` so a later build can
choose a parse strategy before reading anything else, and a newer version is
refused rather than half-read — the same rule `WorldMeta` applies.

Decoding untrusted text never crashes and never guesses. A count that is
negative, fractional or not a number fails the decode, naming the key. It is
**not** clamped to zero: a quietly emptied inventory is data loss the player
discovers later, while a failed open offers them the backup now.

**Files:**
- Create: `src/core/save/inventory_codec.gd`
- Test: `tests/test_inventory_codec.gd`

**Interfaces:**
- Consumes: `Inventory` (Task 2), `DecodeResult` (existing,
  `src/core/save/decode_result.gd`).
- Produces:
  - `InventoryCodec.FORMAT_VERSION: int = 1`
  - `InventoryCodec.path_in(save_root: String) -> String` — `<root>/inventory.json`
  - `InventoryCodec.to_json_string(inv: Inventory) -> String`
  - `InventoryCodec.from_json_string(text: String) -> DecodeResult` — `value`
    is an `Inventory` on success; `error` starts with `"inventory.json: "`.

- [x] **Step 1: Write the failing tests**

Create `tests/test_inventory_codec.gd`:

```gdscript
extends GutTest
## inventory.json: round trip, and every way the file can lie.


func _decode(text: String) -> DecodeResult:
	return InventoryCodec.from_json_string(text)


func test_the_file_sits_beside_meta_json() -> void:
	assert_eq(InventoryCodec.path_in("user://saves/home"),
		"user://saves/home/inventory.json")


func test_a_round_trip_preserves_every_count() -> void:
	var inv: Inventory = Inventory.new()
	inv.add("wood", 12)
	inv.add("stone", 3)
	var r: DecodeResult = _decode(InventoryCodec.to_json_string(inv))
	assert_true(r.ok, r.error)
	var back: Inventory = r.value
	assert_eq(back.count_of("wood"), 12)
	assert_eq(back.count_of("stone"), 3)
	assert_eq(back.item_ids(), inv.item_ids())


func test_an_empty_inventory_round_trips_as_empty() -> void:
	var r: DecodeResult = _decode(InventoryCodec.to_json_string(Inventory.new()))
	assert_true(r.ok, r.error)
	assert_true((r.value as Inventory).is_empty())


func test_the_file_names_its_format_version_and_string_ids() -> void:
	var inv: Inventory = Inventory.new()
	inv.add("wood", 2)
	var json: JSON = JSON.new()
	assert_eq(json.parse(InventoryCodec.to_json_string(inv)), OK)
	var doc: Dictionary = json.data
	assert_eq(int(doc["format_version"]), InventoryCodec.FORMAT_VERSION)
	assert_eq(int((doc["items"] as Dictionary)["wood"]), 2,
		"items are keyed by string id, never a runtime numeric")


func test_an_item_the_build_does_not_know_survives_a_round_trip() -> void:
	# The placeholder rule for a string-keyed file: the codec never asks
	# the registry, so a renamed or deleted item keeps its count.
	var r: DecodeResult = _decode(
		'{"format_version": 1, "items": {"mithril": 4, "wood": 1}}')
	assert_true(r.ok, r.error)
	var inv: Inventory = r.value
	assert_eq(inv.count_of("mithril"), 4)
	var again: DecodeResult = _decode(InventoryCodec.to_json_string(inv))
	assert_eq((again.value as Inventory).count_of("mithril"), 4)


func test_a_zero_count_is_dropped_not_refused() -> void:
	var r: DecodeResult = _decode('{"format_version": 1, "items": {"wood": 0}}')
	assert_true(r.ok, r.error)
	assert_true((r.value as Inventory).is_empty())


func test_a_missing_items_key_is_an_empty_inventory() -> void:
	var r: DecodeResult = _decode('{"format_version": 1}')
	assert_true(r.ok, r.error)
	assert_true((r.value as Inventory).is_empty())


func test_malformed_json_is_a_failure_not_a_crash() -> void:
	var r: DecodeResult = _decode("{ not json")
	assert_false(r.ok)
	assert_string_contains(r.error, "inventory.json")


func test_a_top_level_that_is_not_an_object_is_refused() -> void:
	assert_false(_decode("[1, 2, 3]").ok)


func test_items_that_is_not_an_object_is_refused() -> void:
	assert_false(_decode('{"format_version": 1, "items": ["wood"]}').ok)


func test_a_newer_format_version_is_refused() -> void:
	var r: DecodeResult = _decode(
		'{"format_version": %d, "items": {}}' % (InventoryCodec.FORMAT_VERSION + 1))
	assert_false(r.ok)
	assert_string_contains(r.error, "newer")


func test_a_negative_count_is_refused_naming_the_item() -> void:
	var r: DecodeResult = _decode('{"format_version": 1, "items": {"wood": -3}}')
	assert_false(r.ok)
	assert_string_contains(r.error, "wood")


func test_a_fractional_count_is_refused() -> void:
	assert_false(_decode('{"format_version": 1, "items": {"wood": 2.5}}').ok)


func test_a_count_that_is_not_a_number_is_refused() -> void:
	assert_false(_decode('{"format_version": 1, "items": {"wood": "12"}}').ok)
```

- [x] **Step 2: Run the tests to verify they fail**

Run: `./tools/run_tests.sh`
Expected: FAIL — `InventoryCodec` is not a known class.

- [x] **Step 3: Write the implementation**

Create `src/core/save/inventory_codec.gd`:

```gdscript
class_name InventoryCodec
extends RefCounted
## inventory.json, beside meta.json in the save root.
##
## JSON for the same reason meta.json is: small, cold, and worth reading
## with `cat`. A file of its own rather than a field in a binary codec, so
## a save written before inventories existed simply has no file and opens
## as empty, with no migration.
##
## The codec never consults the ContentRegistry. Keys are string ids and
## pass through verbatim, so an item this build does not ship keeps its
## count. A count that is not a whole, non-negative number fails the
## decode instead of being clamped: a failed open offers the backup, while
## a silently emptied inventory is loss the player finds later.

const FORMAT_VERSION: int = 1


static func path_in(save_root: String) -> String:
	return save_root.path_join("inventory.json")


static func to_json_string(inv: Inventory) -> String:
	var items: Dictionary = {}
	for item_id: String in inv.item_ids():
		items[item_id] = inv.count_of(item_id)
	return JSON.stringify({
		"format_version": FORMAT_VERSION,
		"items": items,
	}, "  ", true)


static func from_json_string(text: String) -> DecodeResult:
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		return DecodeResult.failure("inventory.json: malformed JSON")
	if not (json.data is Dictionary):
		return DecodeResult.failure("inventory.json: top level is not an object")

	var doc: Dictionary = json.data
	var version: int = int(doc.get("format_version", FORMAT_VERSION))
	if version > FORMAT_VERSION:
		return DecodeResult.failure(
			"inventory.json: format_version %d is newer than this build supports (%d)"
			% [version, FORMAT_VERSION]
		)

	var items: Variant = doc.get("items", {})
	if not (items is Dictionary):
		return DecodeResult.failure("inventory.json: 'items' is not an object")

	var inv: Inventory = Inventory.new()
	for key: Variant in items:
		var item_id: String = str(key)
		var raw: Variant = (items as Dictionary)[key]
		if not (raw is int or raw is float) \
				or not is_equal_approx(float(raw), roundf(float(raw))) \
				or float(raw) < 0.0:
			return DecodeResult.failure(
				"inventory.json: count for '%s' is not a whole number >= 0" % item_id)
		var _added: bool = inv.add(item_id, int(raw))
	return DecodeResult.success(inv)
```

`inv.add` refuses a zero, which is exactly how a zero count is dropped.

- [x] **Step 4: Run the tests to verify they pass**

Run: `./tools/run_tests.sh`
Expected: PASS, all suites.

- [x] **Step 5: Commit**

```bash
git add src/core/save/inventory_codec.gd tests/test_inventory_codec.gd
git commit -m "feat: inventory.json, beside meta.json"
```

- [x] **Step 6: Tick the task**

```bash
python3 tools/mark_task_done.py 3 --plan docs/superpowers/plans/2026-09-29-rp1-phase8-items-inventory.md
git add docs/superpowers/plans/2026-09-29-rp1-phase8-items-inventory.md
git commit -m "docs: tick Phase 8 task 3"
```

---

## Task 4: The session owns the inventory

`GameSession` already decides what New World, Continue and quitting mean; the
inventory's lifecycle is the same decisions. Four rules:

- `open_new` and `close` replace it with an empty one.
- `open_saved` reads `inventory.json` (or `inventory.json.bak` when
  `use_backup`). **Missing → empty.** Malformed → the open fails and the
  session is left exactly as it was, like every other `open_saved` failure.
  The read happens *before* the session commits to the loaded zone.
- `save_now` writes it on **every** save, empty or not, atomically with
  `keep_backup = true` like `meta.json`. Writing only when non-empty would let
  New World inherit the previous world's file.
- It is written before `meta.json`, so `meta.json` stays the last file a save
  touches.

**Files:**
- Modify: `src/systems/game_session.gd` — a new `inventory` var after
  `playtime` (line 26); `open_new` (55-75); `open_saved` (78-115); `close`
  (123-129); `save_now` (165-199)
- Test: `tests/test_game_session.gd`

**Interfaces:**
- Consumes: `Inventory` (Task 2); `InventoryCodec.path_in`,
  `.to_json_string`, `.from_json_string` (Task 3);
  `SaveManager.atomic_write(path, bytes, keep_backup) -> String` (existing).
- Produces: `GameSession.inventory: Inventory` — never `null`; the live
  inventory for whatever world is open. Task 6's debug key adds to it.

- [x] **Step 1: Write the failing tests**

Append to `tests/test_game_session.gd` (it already has `_session()`,
`_opened()`, `_root` and a wiping `before_each`):

```gdscript
# --- inventory --------------------------------------------------------

func _inventory_file() -> String:
	return InventoryCodec.path_in(_root)


func test_a_new_world_starts_with_an_empty_inventory() -> void:
	assert_true(_opened().inventory.is_empty())


func test_every_save_writes_the_inventory_even_when_empty() -> void:
	var s: GameSession = _opened()
	assert_eq(s.save_now(_registry, "new_world").size(), 0)
	assert_true(FileAccess.file_exists(_inventory_file()))


func test_the_inventory_survives_a_close_and_reopen() -> void:
	var first: GameSession = _opened()
	first.inventory.add("wood", 12)
	first.inventory.add("stone", 3)
	assert_eq(first.save_now(_registry, "quit").size(), 0)
	first.close()

	var second: GameSession = _session()
	var r: SessionOpenResult = second.open_saved(_registry)
	assert_true(r.ok, r.error)
	assert_eq(second.inventory.count_of("wood"), 12)
	assert_eq(second.inventory.count_of("stone"), 3)


func test_new_world_resets_the_inventory() -> void:
	# The same session object is reused by main.gd across worlds, and the
	# old world's inventory.json is still on disk when New World saves.
	var s: GameSession = _opened()
	s.inventory.add("wood", 40)
	s.save_now(_registry, "quit")

	var r: SessionOpenResult = s.open_new("res://data/zone/home", _registry)
	assert_true(r.ok, r.error)
	assert_true(s.inventory.is_empty(), "open_new starts from nothing")
	var id: int = r.zone.entities.spawn(_registry.numeric_of("player"), r.player_spawn)
	s.adopt_player(id)
	assert_eq(s.save_now(_registry, "new_world").size(), 0)

	var reopened: GameSession = _session()
	assert_true(reopened.open_saved(_registry).ok)
	assert_eq(reopened.inventory.count_of("wood"), 0,
		"the overwritten world's wood did not survive into the new one")


func test_close_empties_the_inventory() -> void:
	var s: GameSession = _opened()
	s.inventory.add("wood", 5)
	s.close()
	assert_true(s.inventory.is_empty())


func test_a_save_with_no_inventory_file_opens_empty() -> void:
	var first: GameSession = _opened()
	first.save_now(_registry, "quit")
	assert_eq(DirAccess.remove_absolute(_inventory_file()), OK)

	var second: GameSession = _session()
	var r: SessionOpenResult = second.open_saved(_registry)
	assert_true(r.ok, r.error)
	assert_true(second.inventory.is_empty())


func test_a_malformed_inventory_fails_the_open_and_changes_nothing() -> void:
	var first: GameSession = _opened()
	first.save_now(_registry, "quit")
	var f: FileAccess = FileAccess.open(_inventory_file(), FileAccess.WRITE)
	f.store_string('{"format_version": 1, "items": {"wood": -3}}')
	f.close()

	var second: GameSession = _session()
	second.inventory.add("marker", 1)
	var r: SessionOpenResult = second.open_saved(_registry)
	assert_false(r.ok, "a corrupt inventory is not quietly emptied")
	assert_string_contains(r.error, "inventory.json")
	assert_null(second.zone, "a failed open does not half-commit the world")
	assert_eq(second.inventory.count_of("marker"), 1,
		"a failed open leaves the inventory it found")


func test_the_backup_carries_its_own_inventory() -> void:
	var s: GameSession = _opened()
	s.inventory.add("wood", 5)
	s.save_now(_registry, "first")
	s.inventory.add("wood", 2)
	s.save_now(_registry, "second")

	var restored: GameSession = _session()
	var r: SessionOpenResult = restored.open_saved(_registry, true)
	assert_true(r.ok, r.error)
	assert_eq(restored.inventory.count_of("wood"), 5,
		"the backup is the previous save, inventory included")


func test_a_backup_with_no_inventory_opens_empty() -> void:
	# A Stage 1 save that has been saved once by a Stage 2 build: its
	# meta.json.bak exists, but no inventory.json.bak was ever written.
	var s: GameSession = _opened()
	s.save_now(_registry, "first")
	s.save_now(_registry, "second")
	assert_eq(DirAccess.remove_absolute(_inventory_file() + ".bak"), OK)

	var restored: GameSession = _session()
	var r: SessionOpenResult = restored.open_saved(_registry, true)
	assert_true(r.ok, r.error)
	assert_true(restored.inventory.is_empty())
```

- [x] **Step 2: Run the tests to verify they fail**

Run: `./tools/run_tests.sh`
Expected: FAIL — `GameSession` has no member `inventory`.

- [x] **Step 3: Write the implementation**

In `src/systems/game_session.gd`, after `var playtime: float = 0.0` (line 26):

```gdscript

## The open world's items. Never null: replaced with an empty one on
## open_new and close, read from inventory.json on open_saved.
var inventory: Inventory = Inventory.new()
```

In `open_new`, after `playtime = 0.0`:

```gdscript
	inventory = Inventory.new()
```

In `open_saved`, between the player-entity check (ends line 100) and
`zone = loaded_zone`, insert:

```gdscript

	# Read before anything is committed, so a corrupt inventory leaves the
	# session exactly as a corrupt zone would. A missing file is a save
	# from before inventories existed -- or a backup taken before the
	# first Stage 2 save -- and means empty, not broken.
	var inv_path: String = InventoryCodec.path_in(save_root)
	if use_backup:
		inv_path += ".bak"
	var loaded_inventory: Inventory = Inventory.new()
	if FileAccess.file_exists(inv_path):
		var inv_result: DecodeResult = InventoryCodec.from_json_string(
			FileAccess.get_file_as_string(inv_path))
		if not inv_result.ok:
			return SessionOpenResult.failure(inv_result.error)
		loaded_inventory = inv_result.value
```

and after `zone = loaded_zone`:

```gdscript
	inventory = loaded_inventory
```

In `close`, after `playtime = 0.0`:

```gdscript
	inventory = Inventory.new()
```

In `save_now`, immediately before the `var meta: WorldMeta = WorldMeta.new()`
line, insert:

```gdscript
	# Every save, empty or not: New World overwrites a world whose
	# inventory.json is still on disk, and skipping an empty write would
	# hand the new world the old one's items. Written before meta.json so
	# meta.json stays the last file a save touches.
	var inv_err: String = SaveManager.atomic_write(
		InventoryCodec.path_in(save_root),
		InventoryCodec.to_json_string(inventory).to_utf8_buffer(), true)
	if inv_err != "":
		errors.append(inv_err)

```

- [x] **Step 4: Run the tests to verify they pass**

Run: `./tools/run_tests.sh`
Expected: PASS, all suites — including every pre-existing
`test_game_session.gd` test, which now also writes `inventory.json`.

Also run the smoke gate, which exercises `save_now` end to end:

Run: `./tools/godot.sh --headless --path . -s tools/smoke.gd`
Expected: `Smoke test: OK (300 iterations)`, exit 0.

- [x] **Step 5: Commit**

```bash
git add src/systems/game_session.gd tests/test_game_session.gd
git commit -m "feat: the inventory is saved with the world it belongs to"
```

- [x] **Step 6: Tick the task**

```bash
python3 tools/mark_task_done.py 4 --plan docs/superpowers/plans/2026-09-29-rp1-phase8-items-inventory.md
git add docs/superpowers/plans/2026-09-29-rp1-phase8-items-inventory.md
git commit -m "docs: tick Phase 8 task 4"
```

---

## Task 5: A committed Stage 1 save opens with an empty inventory

Spec §3.4: "No migration needed" is a claim that must fail loudly if it stops
being true. Task 4's missing-file test deletes a file a *Stage 2* build wrote;
this fixture is a save the *Stage 1* build wrote, so it also catches any
future change to `meta.json`, `id_map.json`, the chunk codec or the entity
codec that a Stage 1 world would trip over.

The fixture is generated **by the Stage 1 code**, at commit `a175711` ("docs:
close Phase 6") — the last commit before Stage 2 began — in a throwaway
worktree. Generating it with today's code would prove nothing.

**Files:**
- Create: `tests/fixtures/stage1_save/` (`meta.json`, `id_map.json`,
  `zones/home/zone_meta.json`, `zones/home/entities.dat`,
  `zones/home/chunks/*.chunk` — 16 chunks)
- Test: `tests/test_game_session.gd`

**Interfaces:**
- Consumes: `GameSession.inventory` (Task 4).
- Produces: `res://tests/fixtures/stage1_save/`, a read-only fixture. Tests
  open it with `save_root` pointed at it and **never save to it**.

- [x] **Step 1: Generate the fixture with the Stage 1 build**

From the repository root, in Git Bash:

```bash
git worktree add ../rp1-stage1 a175711
cat > ../rp1-stage1/make_stage1_save.gd <<'EOF'
extends SceneTree
## Throwaway: writes one Stage 1 save for tests/fixtures/stage1_save/.

func _init() -> void:
	var registry: ContentRegistry = ContentRegistry.new()
	for e: String in registry.load_from_dir("res://data"):
		printerr(e)
	var s: GameSession = GameSession.new()
	s.save_root = "res://stage1_save_out"
	var r: SessionOpenResult = s.open_new("res://data/zone/home", registry)
	if not r.ok:
		printerr(r.error)
		quit(1)
		return
	var pid: int = r.zone.entities.spawn(registry.numeric_of("player"), r.player_spawn)
	s.adopt_player(pid)
	s.playtime = 61.0
	var errors: PackedStringArray = s.save_now(registry, "stage1_fixture")
	for e: String in errors:
		printerr(e)
	quit(0 if errors.is_empty() else 1)
EOF
(cd ../rp1-stage1 && ./tools/godot.sh --headless --path . --import >/dev/null 2>&1; \
 ./tools/godot.sh --headless --path . -s make_stage1_save.gd)
mkdir -p tests/fixtures/stage1_save
cp -r ../rp1-stage1/stage1_save_out/. tests/fixtures/stage1_save/
git worktree remove --force ../rp1-stage1
find tests/fixtures/stage1_save -type f | sort
```

Expected: the script prints `RP1 saved (stage1_fixture) in N ms`, and the
listing shows `meta.json`, `id_map.json`, `zones/home/zone_meta.json`,
`zones/home/entities.dat` and 16 files under `zones/home/chunks/`. There is
**no** `inventory.json` and no `.bak` — if either appears, the worktree was
not at `a175711`; delete the output and start again.

- [x] **Step 2: Write the test**

Append to `tests/test_game_session.gd`:

```gdscript
const STAGE1_SAVE: String = "res://tests/fixtures/stage1_save"


func test_a_stage1_save_opens_with_an_empty_inventory() -> void:
	# Written by the Stage 1 build at a175711, before inventories existed.
	# "No migration needed" has to fail loudly here if it stops being true.
	assert_false(FileAccess.file_exists(InventoryCodec.path_in(STAGE1_SAVE)),
		"precondition: the fixture predates inventory.json")
	var s: GameSession = GameSession.new()
	s.save_root = STAGE1_SAVE
	var r: SessionOpenResult = s.open_saved(_registry)
	assert_true(r.ok, r.error)
	assert_eq(r.zone.id, "home")
	assert_true(r.zone.entities.has(r.player_entity_id))
	assert_true(s.inventory.is_empty())
	assert_almost_eq(s.playtime, 61.0, 0.001)


func test_a_stage1_save_gains_an_inventory_on_its_first_stage2_save() -> void:
	var s: GameSession = GameSession.new()
	s.save_root = STAGE1_SAVE
	assert_true(s.open_saved(_registry).ok)
	# Redirected before saving: the committed fixture must never be written.
	s.save_root = _root
	s.needs_full_save = true
	s.inventory.add("wood", 3)
	assert_eq(s.save_now(_registry, "upgrade").size(), 0)

	var again: GameSession = _session()
	assert_true(again.open_saved(_registry).ok)
	assert_eq(again.inventory.count_of("wood"), 3)
```

- [x] **Step 3: Run the tests**

Run: `./tools/run_tests.sh`
Expected: PASS, all suites. This test passes on first run — the behaviour was
built in Task 4. To see it bite, temporarily change the missing-file branch in
`open_saved` to `return SessionOpenResult.failure("no inventory")`, run the
suite, confirm `test_a_stage1_save_opens_with_an_empty_inventory` FAILS, then
revert that change and confirm PASS again.

Run: `git status --short tests/fixtures/stage1_save`
Expected: only the new, untracked fixture — no test wrote into it.

- [x] **Step 4: Commit**

```bash
git add tests/fixtures/stage1_save tests/test_game_session.gd
git commit -m "test: a committed Stage 1 save opens with an empty inventory"
```

- [x] **Step 5: Tick the task**

```bash
python3 tools/mark_task_done.py 5 --plan docs/superpowers/plans/2026-09-29-rp1-phase8-items-inventory.md
git add docs/superpowers/plans/2026-09-29-rp1-phase8-items-inventory.md
git commit -m "docs: tick Phase 8 task 5"
```

---

## Task 6: A debug way to grant wood

Phase 7's `debug_place` proved the tile spine by hand; this proves the
inventory spine the same way until Phase 9's harvesting produces wood for
real. **DEBUG ONLY, removed in Phase 10** alongside `debug_place`.

It lives in `main.gd`, not `World`, because `main.gd` holds the session and
the session holds the inventory. `main.gd` is `PROCESS_MODE_ALWAYS`, so it
must ignore the key itself while paused or with no world open. It prints the
new count — there is no inventory UI until Phase 10.

The content id `"wood"` is written in GDScript here, as `"wall_wood"` is in
`_debug_place_wall`. That is tolerated only because both are deleted in
Phase 10.

**Files:**
- Modify: `project.godot` — `[input]`, after `debug_place`
- Modify: `src/presentation/main.gd:296-302` (`_unhandled_input`)
- Test: `tests/test_input_map.gd`

**Interfaces:**
- Consumes: `GameSession.inventory` (Task 4), `Inventory.add`,
  `Inventory.count_of` (Task 2).

- [x] **Step 1: Write the failing test**

Append to `tests/test_input_map.gd`:

```gdscript
func test_the_debug_grant_action_is_bound_to_g() -> void:
	# DEBUG ONLY -- removed with debug_place in Phase 10.
	assert_true(InputMap.has_action("debug_grant"))
	var found: bool = false
	for event: InputEvent in InputMap.action_get_events("debug_grant"):
		if event is InputEventKey and (event as InputEventKey).physical_keycode == KEY_G:
			found = true
	assert_true(found, "debug_grant is not bound to G")
```

- [x] **Step 2: Run the test to verify it fails**

Run: `./tools/run_tests.sh`
Expected: FAIL — `debug_grant` does not exist.

- [x] **Step 3: Add the action and the handler**

In `project.godot`, directly after the closing `}` of `debug_place`, add
(physical keycode 71 is `G`):

```
debug_grant={
"deadzone": 0.2,
"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":71,"key_label":0,"unicode":0,"location":0,"echo":false,"script":null)
]
}
```

In `src/presentation/main.gd`, replace `_unhandled_input` with:

```gdscript
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_grant"):
		_debug_grant_wood()
		return
	if not event.is_action_pressed("pause"):
		return
	if _world == null or _confirm.visible:
		return
	get_viewport().set_input_as_handled()
	_set_paused(not get_tree().paused)


## DEBUG ONLY -- removed in Phase 10 with World._debug_place_wall. Stands
## in for harvesting until Phase 9, so the inventory's save path can be
## proved by hand. This node is PROCESS_MODE_ALWAYS, so the pause is
## honoured here rather than by the tree.
func _debug_grant_wood() -> void:
	if _world == null or get_tree().paused:
		return
	get_viewport().set_input_as_handled()
	var _added: bool = _session.inventory.add("wood", 10)
	print("RP1 inventory: wood %d" % _session.inventory.count_of("wood"))
```

- [x] **Step 4: Run the tests and every local gate**

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

- [x] **Step 5: Prove the phase by hand**

Run the game (`./tools/godot.sh --path .`), then:

1. New World (overwrite if asked). Press `G` three times. The console prints
   `RP1 inventory: wood 10`, `20`, `30`.
2. Press `Esc`, press `G`: nothing prints (paused). Unpause.
3. Quit to menu, close the window. Relaunch, Continue, press `G` once:
   the console prints `RP1 inventory: wood 40` — the 30 survived.
4. Quit to menu. New World, confirm the overwrite. Press `G` once: the
   console prints `RP1 inventory: wood 10` — the reset held.
5. Open the save's `inventory.json` (Godot's `user://saves/home/`, on
   Windows `%APPDATA%\Godot\app_userdata\<project name>\saves\home\`) and
   confirm it reads `"wood": 10` under `"items"`.

Write down what you saw for each step in the task's commit message body. If
any step differs, stop and report it — do not tick the task.

- [x] **Step 6: Commit**

```bash
git add project.godot src/presentation/main.gd tests/test_input_map.gd
git commit -m "feat: a debug key that grants wood

Manual run: <one line per step 1-5 above>"
```

- [x] **Step 7: Tick the task**

```bash
python3 tools/mark_task_done.py 6 --plan docs/superpowers/plans/2026-09-29-rp1-phase8-items-inventory.md
git add docs/superpowers/plans/2026-09-29-rp1-phase8-items-inventory.md
git commit -m "docs: tick Phase 8 task 6"
```

---

## Definition of done

- [ ] `ContentRegistry.CATEGORIES` ends `"sound", "item"`, and `wood` and
      `stone` register with no errors
- [ ] `item` has a schema validation test
- [ ] `Inventory` refuses every removal it cannot complete, and changes
      nothing when it does
- [ ] Inventory survives a relaunch — proved by
      `test_the_inventory_survives_a_close_and_reopen` and Task 6 step 3
- [ ] New World resets it — proved by `test_new_world_resets_the_inventory`
      and Task 6 step 4
- [ ] A committed Stage 1 save opens with an empty inventory and no error —
      `test_a_stage1_save_opens_with_an_empty_inventory`
- [ ] A corrupt `inventory.json` fails the open instead of emptying it
- [ ] `chunk_codec` and `entity_codec` are unchanged: `git diff main --stat`
      shows neither file
- [ ] All six local gates green, and CI green on the branch

Tick with `python3 tools/mark_task_done.py --section "Definition of done" --plan docs/superpowers/plans/2026-09-29-rp1-phase8-items-inventory.md`.
