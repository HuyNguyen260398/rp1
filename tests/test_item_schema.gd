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
