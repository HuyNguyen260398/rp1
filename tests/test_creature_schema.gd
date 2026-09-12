extends GutTest
## The creature contract, including the behaviour fields AnimalSystem reads.
##
## SchemaValidator checks the TOP LEVEL ONLY. That is exactly why these
## fields are flat rather than nested inside a "wander" block: a typo in a
## nested block would be silently ignored, which is the failure the
## unknown-field rule exists to prevent. These tests are what make that
## claim true rather than merely intended.

const SCHEMA_PATH: String = "res://data/schema/creature.json"
const RABBIT_PATH: String = "res://data/creature/rabbit.json"
const PLAYER_PATH: String = "res://data/creature/player.json"

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


func test_the_shipped_creatures_validate() -> void:
	for path: String in [RABBIT_PATH, PLAYER_PATH]:
		assert_eq(SchemaValidator.validate(_read(path), _schema), PackedStringArray(),
			"%s must satisfy the creature schema" % path)


func test_every_behaviour_field_is_declared() -> void:
	var optional: Dictionary = _schema.get("optional", {})
	for field: String in ["wander_radius", "wander_speed", "wander_interval",
			"flees_player", "flee_radius", "flee_speed",
			"body_width", "body_height"]:
		assert_true(optional.has(field),
			"'%s' must be a declared optional field, or a creature carrying it is rejected"
				% field)


func test_a_typo_in_a_behaviour_field_is_rejected() -> void:
	var def: Dictionary = _read(RABBIT_PATH)
	def["wander_radus"] = 6
	assert_gt(SchemaValidator.validate(def, _schema).size(), 0,
		"a misspelt field must be an error, not a setting that does nothing")


func test_a_behaviour_field_of_the_wrong_type_is_rejected() -> void:
	var def: Dictionary = _read(RABBIT_PATH)
	def["flees_player"] = "yes"
	assert_gt(SchemaValidator.validate(def, _schema).size(), 0,
		"flees_player is a bool; a string must not pass")


func test_the_rabbit_carries_every_number_animal_system_reads() -> void:
	var rabbit: Dictionary = _read(RABBIT_PATH)
	for field: String in ["wander_radius", "wander_speed", "wander_interval",
			"flees_player", "flee_radius", "flee_speed",
			"body_width", "body_height"]:
		assert_true(rabbit.has(field), "rabbit.json must author '%s'" % field)
	assert_gt(float(rabbit["wander_radius"]), 0.0,
		"a wander_radius above zero is what makes an entity an animal")
	assert_gt(float(rabbit["flee_radius"]) * 1.5, float(rabbit["flee_radius"]),
		"precondition for the calm distance in AnimalSystem")


func test_the_player_is_not_an_animal() -> void:
	var player: Dictionary = _read(PLAYER_PATH)
	assert_false(player.has("wander_radius"),
		"the player must have no wander_radius, or AnimalSystem would drive it")
