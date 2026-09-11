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
	# Asserted against a registered definition rather than oak_tree.json.
	# The oak was the only oversized sprite in the project and stopped being
	# one in Phase 3c, when the real art turned out to be 32x32 -- so this
	# no longer has a shipped definition to lean on. A synthetic one keeps
	# the behaviour covered and stops the test tracking content decisions.
	_r.register({
		"id": "tall_thing", "category": "object", "display_name": "Tall Thing",
		"sprite": "res://assets/characters/player.png", "sprite_rect": [0, 0, 32, 48],
	})
	var res: TilesetBuildResult = TilesetBuilder.build(_r)
	var tall: TileSetAtlasSource = _source_of(res, "tall_thing")
	assert_eq(tall.texture_region_size, Vector2i(32, 48), "a declared rect is used")


func test_absent_sprite_rect_defaults_to_the_tile_size() -> void:
	var res: TilesetBuildResult = TilesetBuilder.build(_r)
	var grass: TileSetAtlasSource = _source_of(res, "grass")
	assert_eq(grass.texture_region_size, Vector2i(32, 32), "grass falls back to 32x32")


func test_oversized_sprites_sit_on_their_tile() -> void:
	# Godot centres an oversized atlas region on its tile, which leaves a
	# 48px sprite hanging 8px below a 32px tile. Base alignment is
	# (H - T) / 2, derived from geometry rather than authored per asset.
	# Verified against a real framebuffer: origin 8 puts a 48px sprite's base
	# exactly on the tile's bottom edge. Synthetic since Phase 3c, for the
	# reason given in test_sprite_rect_sets_the_region_size.
	_r.register({
		"id": "tall_thing", "category": "object", "display_name": "Tall Thing",
		"sprite": "res://assets/characters/player.png", "sprite_rect": [0, 0, 32, 48],
	})
	var res: TilesetBuildResult = TilesetBuilder.build(_r)
	var tall: TileSetAtlasSource = _source_of(res, "tall_thing")
	var td: TileData = tall.get_tile_data(Vector2i.ZERO, 0)
	assert_eq(td.texture_origin, Vector2i(0, 8), "a 48px sprite lifts 8 to stand on a 32px tile")


func test_tile_sized_sprites_need_no_shift() -> void:
	var res: TilesetBuildResult = TilesetBuilder.build(_r)
	var grass: TileSetAtlasSource = _source_of(res, "grass")
	var td: TileData = grass.get_tile_data(Vector2i.ZERO, 0)
	assert_eq(td.texture_origin, Vector2i.ZERO, "a 32px sprite is already aligned")


func test_y_offset_nudges_from_the_base_aligned_position() -> void:
	# y_offset is a deliberate override for art that should not stand flat
	# on its tile -- a hanging sign, say. Negative moves the sprite up,
	# which is the intuitive direction; texture_origin is subtracted by the
	# engine, so the sign flips on the way in.
	#
	# The texture is player.png only because it is the one asset still tall
	# enough to hold a 48px region: an atlas source cannot carve a rect
	# bigger than its texture, and the oak became 32x32 in Phase 3c.
	_r.register({
		"id": "hanging_sign", "category": "object", "display_name": "Sign",
		"sprite": "res://assets/characters/player.png",
		"sprite_rect": [0, 0, 32, 48], "y_offset": -10,
	})
	var res: TilesetBuildResult = TilesetBuilder.build(_r)
	var sign_src: TileSetAtlasSource = _source_of(res, "hanging_sign")
	var td: TileData = sign_src.get_tile_data(Vector2i.ZERO, 0)
	assert_eq(td.texture_origin, Vector2i(0, 18), "base-align 8, plus 10 more for a -10 nudge")


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
