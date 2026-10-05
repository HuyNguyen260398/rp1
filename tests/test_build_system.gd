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
