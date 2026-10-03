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
