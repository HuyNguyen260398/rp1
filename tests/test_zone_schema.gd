extends GutTest
## data/schema/zone.json is the contract for an authored zone document.
##
## SchemaValidator enforces four rules -- required fields, field types,
## unknown fields, and a category match -- and this asserts all four apply
## here, so a typo in zone.json is an error rather than a setting that
## silently does nothing.

const SCHEMA_PATH: String = "res://data/schema/zone.json"
const ZONE_PATH: String = "res://data/zone/home/zone.json"

var _schema: Dictionary


func _read(path: String) -> Dictionary:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	assert_not_null(f, "%s must exist" % path)
	if f == null:
		return {}
	var text: String = f.get_as_text()
	f.close()
	var parser: JSON = JSON.new()
	assert_eq(parser.parse(text), OK, "%s must be valid JSON" % path)
	return parser.data as Dictionary


func before_each() -> void:
	_schema = _read(SCHEMA_PATH)


func _valid_doc() -> Dictionary:
	return {
		"id": "t",
		"category": "zone",
		"display_name": "T",
		"size": [8, 8],
		"maps": {"terrain": "terrain.png"},
		"legend": {"terrain": {"00ff00": "grass"}},
		"player_spawn": [4.5, 4.5],
	}


func test_the_shipped_zone_validates() -> void:
	assert_eq(SchemaValidator.validate(_read(ZONE_PATH), _schema), PackedStringArray(),
		"data/zone/home/zone.json must satisfy its own schema")


func test_a_minimal_document_validates() -> void:
	assert_eq(SchemaValidator.validate(_valid_doc(), _schema), PackedStringArray())


func test_each_required_field_is_required() -> void:
	for field: String in ["id", "category", "display_name", "size", "maps",
			"legend", "player_spawn"]:
		var doc: Dictionary = _valid_doc()
		doc.erase(field)
		assert_gt(SchemaValidator.validate(doc, _schema).size(), 0,
			"removing '%s' must be an error" % field)


func test_an_unknown_field_is_rejected() -> void:
	var doc: Dictionary = _valid_doc()
	doc["spawn_point"] = [1, 1]
	assert_gt(SchemaValidator.validate(doc, _schema).size(), 0,
		"a typo'd key must be an error, not a setting that does nothing")


func test_the_wrong_category_is_rejected() -> void:
	var doc: Dictionary = _valid_doc()
	doc["category"] = "terrain"
	assert_gt(SchemaValidator.validate(doc, _schema).size(), 0)


func test_the_optional_fields_are_accepted() -> void:
	var doc: Dictionary = _valid_doc()
	doc["biome"] = "temperate"
	doc["generation_seed"] = 0
	doc["entities"] = [{"type": "rabbit", "at": [2.5, 2.5]}]
	assert_eq(SchemaValidator.validate(doc, _schema), PackedStringArray())
