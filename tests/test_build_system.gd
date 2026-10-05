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
