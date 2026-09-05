extends GutTest


func _registry() -> ContentRegistry:
	var r: ContentRegistry = ContentRegistry.new()
	var errs: PackedStringArray = r.load_from_dir("res://data")
	assert_eq(errs.size(), 0, "fixture registry loaded")
	return r


func test_map_covers_every_registered_string() -> void:
	var r: ContentRegistry = _registry()
	var m: IdMap = IdMap.from_registry(r)
	for sid: String in r.all_string_ids():
		assert_true(m.entries().has(sid), "%s is in the id map" % sid)


func test_json_round_trip() -> void:
	var m: IdMap = IdMap.from_registry(_registry())
	var result: DecodeResult = IdMap.from_json_string(m.to_json_string())
	assert_true(result.ok, result.error)
	assert_eq((result.value as IdMap).entries(), m.entries())


func test_malformed_json_is_rejected() -> void:
	assert_false(IdMap.from_json_string("{not json").ok)


func test_identical_registries_translate_to_identity() -> void:
	var r: ContentRegistry = _registry()
	var m: IdMap = IdMap.from_registry(r)
	var t: PackedInt32Array = m.build_translation(r)
	for sid: String in r.all_string_ids():
		var n: int = r.numeric_of(sid)
		assert_eq(t[n], n, "%s is unchanged when nothing was added" % sid)


func test_inserting_new_content_does_not_corrupt_old_saves() -> void:
	# The scenario the whole string-id scheme exists to survive: content is
	# added, every numeric id shifts, and an old save must still resolve.
	var old_registry: ContentRegistry = _registry()
	var saved_map: IdMap = IdMap.from_registry(old_registry)
	var saved_grass_id: int = old_registry.numeric_of("grass")

	var new_registry: ContentRegistry = _registry()
	# "aaa_new_thing" sorts before "grass", so grass shifts by one.
	var _n: int = new_registry.register(
		{"id": "aaa_new_thing", "category": "terrain", "display_name": "New",
		 "sprite": "res://assets/tiles/new.png"}
	)

	var t: PackedInt32Array = saved_map.build_translation(new_registry)
	assert_eq(
		new_registry.string_of(t[saved_grass_id]), "grass",
		"the old numeric id still resolves to grass after renumbering"
	)


func test_removed_content_becomes_a_placeholder_retaining_its_string() -> void:
	var registry: ContentRegistry = _registry()
	var m: IdMap = IdMap.new()
	m.set_entry("ghost_tile", 500)

	var t: PackedInt32Array = m.build_translation(registry)
	var mapped: int = t[500]
	assert_ne(mapped, ContentRegistry.ID_UNKNOWN, "removed content is not silently zeroed")
	assert_true(registry.is_placeholder(mapped))
	assert_eq(registry.string_of(mapped), "ghost_tile", "the original string survives")


func test_translation_table_covers_the_highest_saved_id() -> void:
	var m: IdMap = IdMap.new()
	m.set_entry("ghost", 900)
	var t: PackedInt32Array = m.build_translation(_registry())
	assert_eq(t.size(), 901, "table is indexable up to the largest saved id")


func test_id_zero_always_translates_to_unknown() -> void:
	var t: PackedInt32Array = IdMap.from_registry(_registry()).build_translation(_registry())
	assert_eq(t[0], ContentRegistry.ID_UNKNOWN, "empty tiles stay empty")
