extends GutTest

var _r: ContentRegistry


func before_each() -> void:
	_r = ContentRegistry.new()
	var errs: PackedStringArray = _r.load_from_dir("res://data")
	assert_eq(errs.size(), 0, "shipped content validates: %s" % ", ".join(errs))


func test_builds_a_source_for_every_definition_with_art() -> void:
	var res: TilesetBuildResult = TilesetBuilder.build(_r)
	assert_not_null(res.tileset, "a tileset is returned")
	assert_eq(res.errors.size(), 0, "no errors: %s" % ", ".join(res.errors))
	# grass, water and oak_tree have art. rabbit is a creature and is not
	# a tile, so it is not expected to produce a source.
	assert_eq(res.tileset.get_source_count(), 3, "one source per tile definition")


func test_every_tile_definition_maps_to_a_real_source() -> void:
	var res: TilesetBuildResult = TilesetBuilder.build(_r)
	for sid: String in ["grass", "water", "oak_tree"]:
		var numeric: int = _r.numeric_of(sid)
		var source: int = res.source_for(numeric)
		assert_ne(source, -1, "%s has a source" % sid)
		assert_true(res.tileset.has_source(source), "%s source exists in the tileset" % sid)


func test_unmapped_ids_return_minus_one() -> void:
	var res: TilesetBuildResult = TilesetBuilder.build(_r)
	assert_eq(res.source_for(999999), -1, "an id that was never registered")
	assert_eq(res.source_for(ContentRegistry.ID_UNKNOWN), -1, "id 0 is empty, never a source")


func test_source_assignment_is_deterministic() -> void:
	# Two builds from equivalent registries must agree, or the renderer's
	# output would not be reproducible and could not be asserted on.
	var other: ContentRegistry = ContentRegistry.new()
	var _e: PackedStringArray = other.load_from_dir("res://data")
	var a: TilesetBuildResult = TilesetBuilder.build(_r)
	var b: TilesetBuildResult = TilesetBuilder.build(other)
	for sid: String in ["grass", "water", "oak_tree"]:
		assert_eq(a.source_for(_r.numeric_of(sid)), b.source_for(other.numeric_of(sid)),
			"source id for %s is stable across builds" % sid)


func test_tile_size_is_the_project_constant() -> void:
	var res: TilesetBuildResult = TilesetBuilder.build(_r)
	assert_eq(res.tileset.tile_size, Vector2i(32, 32), "32x32, per the art constants")


func _source_of(res: TilesetBuildResult, string_id: String) -> TileSetAtlasSource:
	var sid: int = res.source_for(_r.numeric_of(string_id))
	return res.tileset.get_source(sid) as TileSetAtlasSource


func test_sprite_rect_sets_the_region_size() -> void:
	# oak_tree.json declares sprite_rect [0, 0, 32, 48].
	var res: TilesetBuildResult = TilesetBuilder.build(_r)
	var oak: TileSetAtlasSource = _source_of(res, "oak_tree")
	assert_eq(oak.texture_region_size, Vector2i(32, 48), "oak uses its declared rect")


func test_absent_sprite_rect_defaults_to_the_tile_size() -> void:
	var res: TilesetBuildResult = TilesetBuilder.build(_r)
	var grass: TileSetAtlasSource = _source_of(res, "grass")
	assert_eq(grass.texture_region_size, Vector2i(32, 32), "grass falls back to 32x32")


func test_y_offset_becomes_the_texture_origin() -> void:
	# oak_tree.json declares y_offset -16, so a 48px sprite sits with its
	# base on its tile instead of floating half a tile high.
	var res: TilesetBuildResult = TilesetBuilder.build(_r)
	var oak: TileSetAtlasSource = _source_of(res, "oak_tree")
	var td: TileData = oak.get_tile_data(Vector2i.ZERO, 0)
	assert_eq(td.texture_origin, Vector2i(0, -16), "y_offset reaches texture_origin")


func test_no_offset_means_no_origin_shift() -> void:
	var res: TilesetBuildResult = TilesetBuilder.build(_r)
	var grass: TileSetAtlasSource = _source_of(res, "grass")
	var td: TileData = grass.get_tile_data(Vector2i.ZERO, 0)
	assert_eq(td.texture_origin, Vector2i.ZERO, "grass is not shifted")


func test_a_missing_sprite_is_recorded_and_skipped() -> void:
	# A definition whose art is absent must not abort the build, must not
	# paint a wrong tile, and must not shift anyone else's source id.
	var before: TilesetBuildResult = TilesetBuilder.build(_r)
	var grass_source: int = before.source_for(_r.numeric_of("grass"))

	_r.register({
		"id": "ghost_tile", "category": "terrain", "display_name": "Ghost",
		"sprite": "res://assets/tiles/does_not_exist.png",
	})
	var after: TilesetBuildResult = TilesetBuilder.build(_r)

	assert_eq(after.source_for(_r.numeric_of("ghost_tile")), -1, "ghost gets no source")
	assert_eq(after.errors.size(), 1, "the failure is reported: %s" % ", ".join(after.errors))
	assert_true(", ".join(after.errors).contains("ghost_tile"), "the error names the definition")
	assert_eq(after.source_for(_r.numeric_of("grass")), grass_source,
		"a broken definition does not shift other source ids")


func test_placeholder_content_is_skipped() -> void:
	# Content named in a save but missing from the build has no art by
	# definition. Inventing one would hide the problem.
	var numeric: int = _r.register_placeholder("removed_thing")
	var res: TilesetBuildResult = TilesetBuilder.build(_r)
	assert_true(_r.is_placeholder(numeric), "precondition: it is a placeholder")
	assert_eq(res.source_for(numeric), -1, "placeholders are not drawn")
	assert_eq(res.errors.size(), 0, "and are not reported as errors")
