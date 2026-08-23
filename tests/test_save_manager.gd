extends GutTest

var _root: String = "user://test_saves/w1"
var _registry: ContentRegistry


func before_each() -> void:
	_registry = ContentRegistry.new()
	var errs: PackedStringArray = _registry.load_from_dir("res://data")
	assert_eq(errs.size(), 0)
	_wipe()


func after_each() -> void:
	_wipe()


func _wipe() -> void:
	_rm_rf(_root)
	DirAccess.make_dir_recursive_absolute(_root)


func _rm_rf(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for sub_dir: String in DirAccess.get_directories_at(dir):
		_rm_rf(dir.path_join(sub_dir))
	for file_name: String in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(file_name))
	DirAccess.remove_absolute(dir)


func _zone() -> Zone:
	var z: Zone = Zone.new("home", Vector2i(128, 128))
	z.generation_seed = 4242
	var grass: int = _registry.numeric_of("grass")
	var tree: int = _registry.numeric_of("oak_tree")
	for y: int in range(128):
		for x: int in range(128):
			z.set_terrain(Vector2i(x, y), grass)
			z.set_flags(Vector2i(x, y), Chunk.FLAG_WALKABLE)
	z.set_object(Vector2i(10, 10), tree)
	z.set_height(Vector2i(10, 10), 3)
	var rabbit: int = z.entities.spawn(_registry.numeric_of("rabbit"), Vector2(64.5, 64.5))
	z.entities.set_facing(rabbit, 2)
	return z


func test_atomic_write_leaves_no_temp_file() -> void:
	var path: String = _root.path_join("x.bin")
	assert_eq(SaveManager.atomic_write(path, PackedByteArray([1, 2, 3])), "")
	assert_true(FileAccess.file_exists(path))
	assert_false(FileAccess.file_exists(path + ".tmp"), "temp file was renamed away")


func test_atomic_write_overwrites_existing_content() -> void:
	var path: String = _root.path_join("x.bin")
	var _a: String = SaveManager.atomic_write(path, PackedByteArray([1, 2, 3, 4]))
	var _b: String = SaveManager.atomic_write(path, PackedByteArray([9]))
	assert_eq(FileAccess.get_file_as_bytes(path), PackedByteArray([9]))


func test_save_writes_the_expected_layout() -> void:
	var errs: PackedStringArray = SaveManager.save_zone(_root, _zone(), _registry, true)
	assert_eq(errs.size(), 0, "save produced no errors: %s" % ", ".join(errs))
	assert_true(FileAccess.file_exists(_root.path_join("id_map.json")))
	assert_true(FileAccess.file_exists(_root.path_join("zones/home/zone_meta.json")))
	assert_true(FileAccess.file_exists(_root.path_join("zones/home/entities.dat")))
	assert_true(FileAccess.file_exists(_root.path_join("zones/home/chunks/0_0.chunk")))
	assert_eq(DirAccess.get_files_at(_root.path_join("zones/home/chunks")).size(), 16,
		"a 128x128 zone is 4x4 chunks")


func test_round_trip_preserves_the_whole_zone() -> void:
	var original: Zone = _zone()
	var _e: PackedStringArray = SaveManager.save_zone(_root, original, _registry, true)

	var result: DecodeResult = SaveManager.load_zone(_root, "home", _registry)
	assert_true(result.ok, "load succeeded: %s" % result.error)
	var back: Zone = result.value

	assert_eq(back.id, "home")
	assert_eq(back.size_tiles, Vector2i(128, 128))
	assert_eq(back.generation_seed, 4242)
	assert_eq(back.get_object(Vector2i(10, 10)), _registry.numeric_of("oak_tree"))
	assert_eq(back.get_height(Vector2i(10, 10)), 3)
	assert_true(back.is_walkable(Vector2i(0, 0)))
	assert_eq(back.entities.count(), 1)


func test_chunk_payloads_round_trip_byte_identical() -> void:
	var original: Zone = _zone()
	var _e: PackedStringArray = SaveManager.save_zone(_root, original, _registry, true)
	var back: Zone = SaveManager.load_zone(_root, "home", _registry).value
	for c: Vector2i in original.chunk_coords():
		var a: Chunk = original.get_chunk(c)
		var b: Chunk = back.get_chunk(c)
		assert_not_null(b, "chunk %s survived" % c)
		assert_eq(b.terrain_id, a.terrain_id, "terrain column identical at %s" % c)
		assert_eq(b.object_id, a.object_id)
		assert_eq(b.height, a.height)
		assert_eq(b.flags, a.flags)


func test_save_completes_within_the_budget() -> void:
	var z: Zone = _zone()
	var start: int = Time.get_ticks_msec()
	var _e: PackedStringArray = SaveManager.save_zone(_root, z, _registry, true)
	var elapsed: int = Time.get_ticks_msec() - start
	assert_lt(elapsed, 100, "full zone save took %d ms, budget is 100 ms" % elapsed)


func test_only_dirty_chunks_are_rewritten() -> void:
	var z: Zone = _zone()
	var _e: PackedStringArray = SaveManager.save_zone(_root, z, _registry, true)
	assert_eq(z.dirty_chunk_coords().size(), 0, "saving clears dirty flags")

	# Deleting the file and asserting it is NOT recreated is deterministic.
	# A modified-time comparison would not be: mtime has one-second
	# granularity, so a rewrite within the same second looks unchanged.
	var untouched: String = _root.path_join("zones/home/chunks/3_3.chunk")
	DirAccess.remove_absolute(untouched)

	z.set_terrain(Vector2i(0, 0), _registry.numeric_of("water"))
	assert_eq(z.dirty_chunk_coords(), [Vector2i(0, 0)] as Array[Vector2i])

	var _e2: PackedStringArray = SaveManager.save_zone(_root, z, _registry)
	assert_false(FileAccess.file_exists(untouched), "clean chunk was not rewritten")
	assert_true(
		FileAccess.file_exists(_root.path_join("zones/home/chunks/0_0.chunk")),
		"the dirty chunk was written"
	)


func test_old_save_still_loads_after_new_content_is_added() -> void:
	# The acceptance criterion the string-id scheme exists to satisfy.
	var original: Zone = _zone()
	var _e: PackedStringArray = SaveManager.save_zone(_root, original, _registry, true)

	var extended: ContentRegistry = ContentRegistry.new()
	var _errs: PackedStringArray = extended.load_from_dir("res://data")
	# Sorts before "grass", so every subsequent numeric id shifts.
	var _n: int = extended.register(
		{"id": "aaa_ash", "category": "terrain", "display_name": "Ash",
		 "sprite": "res://assets/tiles/ash.png"}
	)

	var result: DecodeResult = SaveManager.load_zone(_root, "home", extended)
	assert_true(result.ok, result.error)
	var back: Zone = result.value
	assert_eq(
		extended.string_of(back.get_terrain(Vector2i(0, 0))), "grass",
		"tiles still resolve to grass after renumbering"
	)
	assert_eq(extended.string_of(back.get_object(Vector2i(10, 10))), "oak_tree")


func test_save_referencing_removed_content_loads_as_a_placeholder() -> void:
	var z: Zone = _zone()
	var _e: PackedStringArray = SaveManager.save_zone(_root, z, _registry, true)

	# Rewrite id_map.json as though the save had used a tile this build lacks.
	var map_path: String = _root.path_join("id_map.json")
	var m: IdMap = IdMap.from_json_string(FileAccess.get_file_as_string(map_path)).value
	m.set_entry("mystery_moss", _registry.numeric_of("grass"))
	var _w: String = SaveManager.atomic_write(map_path, m.to_json_string().to_utf8_buffer())

	var fresh: ContentRegistry = ContentRegistry.new()
	var _errs: PackedStringArray = fresh.load_from_dir("res://data")
	var result: DecodeResult = SaveManager.load_zone(_root, "home", fresh)
	assert_true(result.ok, result.error)
	assert_true(fresh.has_string("mystery_moss"), "the unknown string was retained")
	assert_true(fresh.is_placeholder(fresh.numeric_of("mystery_moss")))


func test_loading_a_missing_zone_fails_cleanly() -> void:
	var result: DecodeResult = SaveManager.load_zone(_root, "nowhere", _registry)
	assert_false(result.ok)
	assert_ne(result.error, "")


func test_loading_a_corrupt_chunk_fails_cleanly() -> void:
	var _e: PackedStringArray = SaveManager.save_zone(_root, _zone(), _registry, true)
	var _w: String = SaveManager.atomic_write(
		_root.path_join("zones/home/chunks/0_0.chunk"), PackedByteArray([0, 1, 2, 3])
	)
	var result: DecodeResult = SaveManager.load_zone(_root, "home", _registry)
	assert_false(result.ok, "a corrupt chunk is reported, not silently skipped")
