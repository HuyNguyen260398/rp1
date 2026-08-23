extends GutTest

const SCHEMA: Dictionary = {
	"category": "object",
	"required": {"id": "String", "category": "String", "display_name": "String"},
	"optional": {"blocks_movement": "bool", "tags": "Array", "y_offset": "int"},
}


func _valid_def() -> Dictionary:
	return {"id": "oak_tree", "category": "object", "display_name": "Oak Tree"}


func test_valid_definition_has_no_errors() -> void:
	assert_eq(SchemaValidator.validate(_valid_def(), SCHEMA).size(), 0)


func test_valid_definition_with_optionals() -> void:
	var d: Dictionary = _valid_def()
	d["blocks_movement"] = true
	d["tags"] = ["natural", "tree"]
	d["y_offset"] = -16
	assert_eq(SchemaValidator.validate(d, SCHEMA).size(), 0)


func test_missing_required_field_is_an_error() -> void:
	var d: Dictionary = _valid_def()
	d.erase("display_name")
	var errs: PackedStringArray = SchemaValidator.validate(d, SCHEMA)
	assert_eq(errs.size(), 1)
	assert_string_contains(errs[0], "display_name")


func test_wrong_required_type_is_an_error() -> void:
	var d: Dictionary = _valid_def()
	d["display_name"] = 42
	var errs: PackedStringArray = SchemaValidator.validate(d, SCHEMA)
	assert_eq(errs.size(), 1)
	assert_string_contains(errs[0], "display_name")


func test_wrong_optional_type_is_an_error() -> void:
	var d: Dictionary = _valid_def()
	d["blocks_movement"] = "yes"
	assert_eq(SchemaValidator.validate(d, SCHEMA).size(), 1)


func test_unknown_field_is_an_error() -> void:
	# Catches typos like "block_movement", which would otherwise be
	# silently ignored and produce a walkable tree.
	var d: Dictionary = _valid_def()
	d["block_movement"] = true
	var errs: PackedStringArray = SchemaValidator.validate(d, SCHEMA)
	assert_eq(errs.size(), 1)
	assert_string_contains(errs[0], "block_movement")


func test_category_mismatch_is_an_error() -> void:
	var d: Dictionary = _valid_def()
	d["category"] = "creature"
	var errs: PackedStringArray = SchemaValidator.validate(d, SCHEMA)
	assert_eq(errs.size(), 1)
	assert_string_contains(errs[0], "category")


func test_json_numbers_parsed_as_float_satisfy_int_fields() -> void:
	# JSON.parse_string produces floats for every number. An int field
	# must accept 16.0 but reject 16.5.
	var d: Dictionary = _valid_def()
	d["y_offset"] = -16.0
	assert_eq(SchemaValidator.validate(d, SCHEMA).size(), 0, "-16.0 is a valid int")
	d["y_offset"] = -16.5
	assert_eq(SchemaValidator.validate(d, SCHEMA).size(), 1, "-16.5 is not an int")


func test_all_problems_are_reported_at_once() -> void:
	var d: Dictionary = {"id": "x", "category": "wrong", "bogus": 1}
	assert_eq(SchemaValidator.validate(d, SCHEMA).size(), 3, "missing, mismatch, unknown")
