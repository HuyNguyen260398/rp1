extends GutTest
## ZoneLoader turns an authored directory into a Zone.
##
## Every fixture is written into user:// by the test itself, so the
## expected result is visible beside the input rather than hidden in a
## committed binary.

const GRASS: Color = Color8(0, 255, 0)
const WATER: Color = Color8(0, 0, 255)
const OAK: Color = Color8(0, 128, 0)
const EMPTY: Color = Color8(0, 0, 0)

var _dir: String
var _registry: ContentRegistry


func before_each() -> void:
	_dir = "user://zone_fixture_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(_dir)
	_registry = ContentRegistry.new()
	_registry.register({"id": "grass", "category": "terrain",
		"display_name": "Grass", "sprite": "res://none.png", "walkable": true})
	_registry.register({"id": "water", "category": "terrain",
		"display_name": "Water", "sprite": "res://none.png", "walkable": false})
	_registry.register({"id": "oak_tree", "category": "object",
		"display_name": "Oak", "sprite": "res://none.png", "blocks_movement": true})
	_registry.register({"id": "rabbit", "category": "creature",
		"display_name": "Rabbit", "sprite": "res://none.png"})


func after_each() -> void:
	# user:// persists between runs; fixtures would otherwise accumulate.
	var d: DirAccess = DirAccess.open(_dir)
	if d != null:
		for f: String in d.get_files():
			d.remove(f)
	DirAccess.remove_absolute(_dir)


## Writes a map whose every pixel is `fill`, then overrides the pixels in
## `overrides` (Vector2i -> Color).
func _write_map(file_name: String, size: Vector2i, fill: Color,
		overrides: Dictionary = {}) -> void:
	var img: Image = Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
	img.fill(fill)
	for p: Vector2i in overrides:
		img.set_pixelv(p, overrides[p])
	img.save_png(_dir.path_join(file_name))


func _write_doc(doc: Dictionary) -> void:
	var f: FileAccess = FileAccess.open(_dir.path_join("zone.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(doc))
	f.close()


## The smallest document the schema accepts, with a terrain map only.
func _doc(size: Vector2i = Vector2i(4, 4)) -> Dictionary:
	return {
		"id": "fixture",
		"category": "zone",
		"display_name": "Fixture",
		"size": [size.x, size.y],
		"maps": {"terrain": "terrain.png"},
		"legend": {"terrain": {"00ff00": "grass", "0000ff": "water"}},
		"player_spawn": [1.5, 1.5],
	}


func test_terrain_pixels_become_tiles() -> void:
	_write_doc(_doc())
	_write_map("terrain.png", Vector2i(4, 4), GRASS, {Vector2i(2, 1): WATER})

	var r: ZoneLoadResult = ZoneLoader.load_zone(_dir, _registry)

	assert_eq(r.errors, PackedStringArray(), "a clean fixture reports nothing")
	assert_not_null(r.zone)
	assert_eq(r.zone.get_terrain(Vector2i(0, 0)), _registry.numeric_of("grass"))
	assert_eq(r.zone.get_terrain(Vector2i(2, 1)), _registry.numeric_of("water"),
		"the pixel at (2,1) is the tile at (2,1) -- x across, y down")
	assert_eq(r.zone.get_terrain(Vector2i(1, 2)), _registry.numeric_of("grass"),
		"and (1,2) is a different tile, so the axes are not transposed")


func test_metadata_comes_from_the_document() -> void:
	var doc: Dictionary = _doc()
	doc["biome"] = "alpine"
	doc["generation_seed"] = 7
	_write_doc(doc)
	_write_map("terrain.png", Vector2i(4, 4), GRASS)

	var r: ZoneLoadResult = ZoneLoader.load_zone(_dir, _registry)

	assert_eq(r.zone.id, "fixture")
	assert_eq(r.zone.display_name, "Fixture")
	assert_eq(r.zone.size_tiles, Vector2i(4, 4))
	assert_eq(r.zone.biome, "alpine")
	assert_eq(r.zone.generation_seed, 7)


func test_player_spawn_is_returned_in_tile_units() -> void:
	_write_doc(_doc())
	_write_map("terrain.png", Vector2i(4, 4), GRASS)

	var r: ZoneLoadResult = ZoneLoader.load_zone(_dir, _registry)

	assert_eq(r.player_spawn, Vector2(1.5, 1.5),
		"tile units, not pixels: the centre of tile (1,1)")


func test_a_missing_directory_reports_an_error_and_no_zone() -> void:
	var r: ZoneLoadResult = ZoneLoader.load_zone("user://no_such_zone", _registry)

	assert_null(r.zone, "there is no half-usable zone to hand back")
	assert_gt(r.errors.size(), 0, "and it must say so rather than fail silently")


func test_malformed_json_reports_an_error_and_no_zone() -> void:
	var f: FileAccess = FileAccess.open(_dir.path_join("zone.json"), FileAccess.WRITE)
	f.store_string("{ not json")
	f.close()

	var r: ZoneLoadResult = ZoneLoader.load_zone(_dir, _registry)

	assert_null(r.zone)
	assert_gt(r.errors.size(), 0)


func test_a_schema_violation_reports_an_error_and_no_zone() -> void:
	var doc: Dictionary = _doc()
	doc.erase("player_spawn")
	_write_doc(doc)
	_write_map("terrain.png", Vector2i(4, 4), GRASS)

	var r: ZoneLoadResult = ZoneLoader.load_zone(_dir, _registry)

	assert_null(r.zone, "an unschematic document is not loaded at all")
	assert_gt(r.errors.size(), 0)


func test_an_unknown_colour_is_an_error_and_leaves_the_tile_unpainted() -> void:
	_write_doc(_doc())
	_write_map("terrain.png", Vector2i(4, 4), GRASS, {Vector2i(3, 3): Color8(1, 2, 3)})

	var r: ZoneLoadResult = ZoneLoader.load_zone(_dir, _registry)

	assert_not_null(r.zone, "one bad pixel must not cost the whole zone")
	assert_eq(r.zone.get_terrain(Vector2i(3, 3)), ContentRegistry.ID_UNKNOWN)
	assert_eq(r.zone.get_terrain(Vector2i(0, 0)), _registry.numeric_of("grass"),
		"and the rest of the map still loaded")
	assert_gt(r.errors.size(), 0)
	assert_string_contains(r.errors[0], "010203",
		"the error names the colour, since that is what the author must find")


func test_unknown_colour_errors_are_capped() -> void:
	_write_doc(_doc(Vector2i(16, 16)))
	# Every pixel a different unknown colour: 256 distinct problems.
	var overrides: Dictionary = {}
	for y: int in range(16):
		for x: int in range(16):
			overrides[Vector2i(x, y)] = Color8(200, x * 4, y * 4)
	_write_map("terrain.png", Vector2i(16, 16), GRASS, overrides)

	var r: ZoneLoadResult = ZoneLoader.load_zone(_dir, _registry)

	assert_lt(r.errors.size(), ZoneLoader.MAX_REPORTED + 3,
		"a wrong colour mode must not produce one error per pixel")
	assert_string_contains(r.errors[r.errors.size() - 1], "more colour(s)",
		"the tail says how many were suppressed")


func test_a_map_of_the_wrong_size_is_skipped_and_reported() -> void:
	_write_doc(_doc(Vector2i(4, 4)))
	_write_map("terrain.png", Vector2i(8, 8), GRASS)

	var r: ZoneLoadResult = ZoneLoader.load_zone(_dir, _registry)

	assert_not_null(r.zone, "the zone still exists, just unpainted")
	assert_eq(r.zone.get_terrain(Vector2i(0, 0)), ContentRegistry.ID_UNKNOWN)
	assert_gt(r.errors.size(), 0)
	assert_string_contains(r.errors[0], "8x8")


func test_a_partly_transparent_pixel_is_reported() -> void:
	_write_doc(_doc())
	_write_map("terrain.png", Vector2i(4, 4), GRASS,
		{Vector2i(1, 1): Color8(0, 255, 0, 128)})

	var r: ZoneLoadResult = ZoneLoader.load_zone(_dir, _registry)

	assert_gt(r.errors.size(), 0, "a map is an index, not art; alpha is meaningless")
	assert_eq(r.zone.get_terrain(Vector2i(1, 1)), ContentRegistry.ID_UNKNOWN)


func test_a_missing_map_file_is_reported_without_losing_the_zone() -> void:
	_write_doc(_doc())
	# No terrain.png written at all.

	var r: ZoneLoadResult = ZoneLoader.load_zone(_dir, _registry)

	assert_not_null(r.zone, "the document parsed, so there is a zone to hand back")
	assert_gt(r.errors.size(), 0)


func test_a_legend_id_this_build_lacks_becomes_a_placeholder() -> void:
	var doc: Dictionary = _doc()
	doc["legend"]["terrain"]["ff00ff"] = "moon_rock"
	_write_doc(doc)
	_write_map("terrain.png", Vector2i(4, 4), GRASS,
		{Vector2i(2, 2): Color8(255, 0, 255)})

	var r: ZoneLoadResult = ZoneLoader.load_zone(_dir, _registry)

	var id: int = r.zone.get_terrain(Vector2i(2, 2))
	assert_ne(id, ContentRegistry.ID_UNKNOWN, "the tile is painted, not dropped")
	assert_true(_registry.is_placeholder(id), "with a placeholder that keeps the string")
	assert_eq(_registry.string_of(id), "moon_rock",
		"so a resave round-trips the original id -- Stage 1 design 6.4")
	# Walkability arrives in Task 6; that a placeholder is non-blocking is
	# asserted there, against a zone whose flags have actually been derived.
	assert_gt(r.errors.size(), 0, "and the build says what it could not find")


func test_a_malformed_legend_key_is_reported() -> void:
	var doc: Dictionary = _doc()
	doc["legend"]["terrain"]["#00ff00"] = "grass"
	_write_doc(doc)
	_write_map("terrain.png", Vector2i(4, 4), GRASS)

	var r: ZoneLoadResult = ZoneLoader.load_zone(_dir, _registry)

	assert_gt(r.errors.size(), 0, "six hex digits, no leading hash")


## The full three-layer document, as data/zone/home/zone.json is shaped.
func _full_doc(size: Vector2i = Vector2i(4, 4)) -> Dictionary:
	var doc: Dictionary = _doc(size)
	doc["maps"] = {
		"terrain": "terrain.png", "object": "object.png", "height": "height.png"
	}
	doc["legend"]["object"] = {"000000": null, "008000": "oak_tree"}
	return doc


func test_object_pixels_become_objects() -> void:
	_write_doc(_full_doc())
	_write_map("terrain.png", Vector2i(4, 4), GRASS)
	_write_map("object.png", Vector2i(4, 4), EMPTY, {Vector2i(1, 3): OAK})
	_write_map("height.png", Vector2i(4, 4), EMPTY)

	var r: ZoneLoadResult = ZoneLoader.load_zone(_dir, _registry)

	assert_eq(r.errors, PackedStringArray())
	assert_eq(r.zone.get_object(Vector2i(1, 3)), _registry.numeric_of("oak_tree"))


func test_a_null_legend_entry_leaves_the_tile_empty() -> void:
	_write_doc(_full_doc())
	_write_map("terrain.png", Vector2i(4, 4), GRASS)
	_write_map("object.png", Vector2i(4, 4), EMPTY)
	_write_map("height.png", Vector2i(4, 4), EMPTY)

	var r: ZoneLoadResult = ZoneLoader.load_zone(_dir, _registry)

	assert_eq(r.errors, PackedStringArray(),
		"black is declared as null, so it is empty rather than unknown")
	assert_eq(r.zone.get_object(Vector2i(0, 0)), ContentRegistry.ID_UNKNOWN)


func test_the_same_colour_may_mean_different_things_per_layer() -> void:
	# 008000 is oak_tree in the object legend. Give it a terrain meaning too
	# and check the layers do not consult each other's legend.
	var doc: Dictionary = _full_doc()
	doc["legend"]["terrain"]["008000"] = "water"
	_write_doc(doc)
	_write_map("terrain.png", Vector2i(4, 4), GRASS, {Vector2i(0, 1): OAK})
	_write_map("object.png", Vector2i(4, 4), EMPTY, {Vector2i(2, 2): OAK})
	_write_map("height.png", Vector2i(4, 4), EMPTY)

	var r: ZoneLoadResult = ZoneLoader.load_zone(_dir, _registry)

	assert_eq(r.errors, PackedStringArray())
	assert_eq(r.zone.get_terrain(Vector2i(0, 1)), _registry.numeric_of("water"))
	assert_eq(r.zone.get_object(Vector2i(2, 2)), _registry.numeric_of("oak_tree"))


func test_height_comes_from_the_red_channel_with_no_legend() -> void:
	_write_doc(_full_doc())
	_write_map("terrain.png", Vector2i(4, 4), GRASS)
	_write_map("object.png", Vector2i(4, 4), EMPTY)
	_write_map("height.png", Vector2i(4, 4), EMPTY, {
		Vector2i(1, 1): Color8(3, 0, 0),
		Vector2i(2, 1): Color8(255, 99, 99),
	})

	var r: ZoneLoadResult = ZoneLoader.load_zone(_dir, _registry)

	assert_eq(r.errors, PackedStringArray(), "height needs no legend entries")
	assert_eq(r.zone.get_height(Vector2i(1, 1)), 3)
	assert_eq(r.zone.get_height(Vector2i(2, 1)), 255,
		"only red is read; green and blue are ignored")
	assert_eq(r.zone.get_height(Vector2i(0, 0)), 0)


func test_a_missing_height_map_is_not_an_error() -> void:
	var doc: Dictionary = _full_doc()
	doc["maps"].erase("height")
	_write_doc(doc)
	_write_map("terrain.png", Vector2i(4, 4), GRASS)
	_write_map("object.png", Vector2i(4, 4), EMPTY)

	var r: ZoneLoadResult = ZoneLoader.load_zone(_dir, _registry)

	assert_eq(r.errors, PackedStringArray(), "height is optional; Stage 1 renders flat")
	assert_eq(r.zone.get_height(Vector2i(2, 2)), 0)
