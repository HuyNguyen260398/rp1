extends GutTest
## The sound category: one file per sound, listing its stream variations.

const SCHEMA_PATH: String = "res://data/schema/sound.json"


func _schema() -> Dictionary:
	var json: JSON = JSON.new()
	assert_eq(json.parse(FileAccess.get_file_as_string(SCHEMA_PATH)), OK,
		"sound.json must be valid JSON")
	return json.data as Dictionary


func _valid_def() -> Dictionary:
	return {
		"id": "step_grass",
		"category": "sound",
		"display_name": "Grass footstep",
		"streams": ["res://assets/audio/step_grass_1.ogg"],
		"gain_db": -6.0,
		"loop": false,
	}


func test_a_minimal_sound_validates() -> void:
	assert_eq(SchemaValidator.validate(_valid_def(), _schema()).size(), 0)


func test_streams_is_required() -> void:
	# A sound with no stream is a silent bug rather than a loud one: it
	# would validate, register, and then play nothing.
	var d: Dictionary = _valid_def()
	d.erase("streams")
	var errs: PackedStringArray = SchemaValidator.validate(d, _schema())
	assert_eq(errs.size(), 1)
	assert_string_contains(errs[0], "streams")


func test_gain_and_loop_are_optional() -> void:
	var d: Dictionary = _valid_def()
	d.erase("gain_db")
	d.erase("loop")
	assert_eq(SchemaValidator.validate(d, _schema()).size(), 0)


func test_an_unknown_field_is_rejected() -> void:
	# Catches "stream" for "streams", which would otherwise register a
	# sound that can never play.
	var d: Dictionary = _valid_def()
	d["stream"] = "res://assets/audio/step_grass_1.ogg"
	var errs: PackedStringArray = SchemaValidator.validate(d, _schema())
	assert_eq(errs.size(), 1)
	assert_string_contains(errs[0], "stream")


func test_the_wrong_category_is_rejected() -> void:
	var d: Dictionary = _valid_def()
	d["category"] = "creature"
	assert_eq(SchemaValidator.validate(d, _schema()).size(), 1)
