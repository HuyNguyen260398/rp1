extends GutTest

var _r: ContentRegistry


func before_each() -> void:
	_r = ContentRegistry.new()


func test_loads_the_repository_data_directory_without_errors() -> void:
	var errs: PackedStringArray = _r.load_from_dir("res://data")
	assert_eq(errs.size(), 0, "shipped content validates: %s" % ", ".join(errs))
	assert_true(_r.has_string("grass"))
	assert_true(_r.has_string("oak_tree"))
	assert_true(_r.has_string("rabbit"))


func test_zero_is_reserved_for_unknown() -> void:
	var _e: PackedStringArray = _r.load_from_dir("res://data")
	for sid: String in _r.all_string_ids():
		assert_ne(_r.numeric_of(sid), ContentRegistry.ID_UNKNOWN,
			"real content never gets id 0")


func test_string_and_numeric_lookup_are_inverse() -> void:
	var _e: PackedStringArray = _r.load_from_dir("res://data")
	for sid: String in _r.all_string_ids():
		assert_eq(_r.string_of(_r.numeric_of(sid)), sid)


func test_unknown_string_maps_to_id_unknown() -> void:
	var _e: PackedStringArray = _r.load_from_dir("res://data")
	assert_eq(_r.numeric_of("no_such_thing"), ContentRegistry.ID_UNKNOWN)
	assert_false(_r.has_string("no_such_thing"))


func test_assignment_is_deterministic_across_loads() -> void:
	# Two registries built from the same data must agree, or a save
	# written by one would be misread by the other.
	var a: ContentRegistry = ContentRegistry.new()
	var b: ContentRegistry = ContentRegistry.new()
	var _e1: PackedStringArray = a.load_from_dir("res://data")
	var _e2: PackedStringArray = b.load_from_dir("res://data")
	for sid: String in a.all_string_ids():
		assert_eq(a.numeric_of(sid), b.numeric_of(sid), "id for %s is stable" % sid)


func test_definition_is_retrievable() -> void:
	var _e: PackedStringArray = _r.load_from_dir("res://data")
	var d: Dictionary = _r.def_of(_r.numeric_of("oak_tree"))
	assert_eq(d["display_name"], "Oak Tree")
	assert_true(d["blocks_movement"])


func test_malformed_json_is_reported_not_crashed() -> void:
	var dir: String = "user://bad_content"
	DirAccess.make_dir_recursive_absolute(dir.path_join("terrain"))
	DirAccess.make_dir_recursive_absolute(dir.path_join("schema"))
	var s: FileAccess = FileAccess.open(dir.path_join("schema/terrain.json"), FileAccess.WRITE)
	s.store_string('{"category":"terrain","required":{"id":"String","category":"String"},"optional":{}}')
	s.close()
	var f: FileAccess = FileAccess.open(dir.path_join("terrain/broken.json"), FileAccess.WRITE)
	f.store_string("{ this is not json")
	f.close()

	var errs: PackedStringArray = _r.load_from_dir(dir)
	assert_gt(errs.size(), 0, "malformed JSON produces an error rather than a crash")
	assert_string_contains(errs[0], "broken.json")


func test_schema_violation_is_reported() -> void:
	var dir: String = "user://bad_schema"
	DirAccess.make_dir_recursive_absolute(dir.path_join("terrain"))
	DirAccess.make_dir_recursive_absolute(dir.path_join("schema"))
	var s: FileAccess = FileAccess.open(dir.path_join("schema/terrain.json"), FileAccess.WRITE)
	s.store_string('{"category":"terrain","required":{"id":"String","category":"String","display_name":"String"},"optional":{}}')
	s.close()
	var f: FileAccess = FileAccess.open(dir.path_join("terrain/nodisplay.json"), FileAccess.WRITE)
	f.store_string('{"id":"x","category":"terrain"}')
	f.close()

	var errs: PackedStringArray = _r.load_from_dir(dir)
	assert_gt(errs.size(), 0)
	assert_string_contains(errs[0], "display_name")


func test_placeholder_retains_its_original_string() -> void:
	var _e: PackedStringArray = _r.load_from_dir("res://data")
	var id: int = _r.register_placeholder("removed_content")
	assert_ne(id, ContentRegistry.ID_UNKNOWN)
	assert_true(_r.is_placeholder(id))
	assert_eq(_r.string_of(id), "removed_content", "the original string survives")


func test_registering_the_same_placeholder_twice_returns_the_same_id() -> void:
	var _e: PackedStringArray = _r.load_from_dir("res://data")
	assert_eq(_r.register_placeholder("gone"), _r.register_placeholder("gone"))


func test_real_content_is_not_a_placeholder() -> void:
	var _e: PackedStringArray = _r.load_from_dir("res://data")
	assert_false(_r.is_placeholder(_r.numeric_of("grass")))
