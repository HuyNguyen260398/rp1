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
