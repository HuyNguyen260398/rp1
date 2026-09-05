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
