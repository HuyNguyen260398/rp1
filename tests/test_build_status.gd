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
