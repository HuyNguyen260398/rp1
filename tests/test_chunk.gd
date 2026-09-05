extends GutTest

var _c: Chunk


func before_each() -> void:
	_c = Chunk.new(Vector2i(2, -3))


func test_column_sizes_match_the_spec() -> void:
	assert_eq(_c.terrain_id.size(), 2048, "u16 column is 1024 * 2 bytes")
	assert_eq(_c.floor_id.size(), 2048)
	assert_eq(_c.object_id.size(), 2048)
	assert_eq(_c.height.size(), 1024, "u8 column is 1024 bytes")
	assert_eq(_c.flags.size(), 1024)
	assert_eq(Chunk.PAYLOAD_BYTES, 8192, "total uncompressed payload")


func test_new_chunk_is_zeroed_and_clean() -> void:
	assert_eq(_c.get_terrain(Vector2i(0, 0)), 0)
	assert_eq(_c.get_height(Vector2i(31, 31)), 0)
	assert_false(_c.dirty, "a freshly constructed chunk is not dirty")


func test_coord_is_stored() -> void:
	assert_eq(_c.coord, Vector2i(2, -3))


func test_terrain_round_trips_at_full_u16_range() -> void:
	_c.set_terrain(Vector2i(5, 7), 65535)
	assert_eq(_c.get_terrain(Vector2i(5, 7)), 65535, "u16 max survives")
	_c.set_terrain(Vector2i(0, 0), 1)
	assert_eq(_c.get_terrain(Vector2i(0, 0)), 1)


func test_columns_are_independent() -> void:
	var l: Vector2i = Vector2i(9, 9)
	_c.set_terrain(l, 11)
	_c.set_floor(l, 22)
	_c.set_object(l, 33)
	_c.set_height(l, 44)
	_c.set_flags(l, 55)
	assert_eq(_c.get_terrain(l), 11)
	assert_eq(_c.get_floor(l), 22)
	assert_eq(_c.get_object(l), 33)
	assert_eq(_c.get_height(l), 44)
	assert_eq(_c.get_flags(l), 55)


func test_neighbouring_tiles_do_not_alias() -> void:
	# Catches a wrong stride in the u16 columns, the most likely bug here.
	_c.set_terrain(Vector2i(0, 0), 4242)
	assert_eq(_c.get_terrain(Vector2i(1, 0)), 0, "adjacent tile untouched")
	assert_eq(_c.get_terrain(Vector2i(0, 1)), 0, "tile on next row untouched")


func test_every_tile_is_addressable() -> void:
	for y: int in range(32):
		for x: int in range(32):
			_c.set_terrain(Vector2i(x, y), (y * 32 + x) % 65536)
	for y: int in range(32):
		for x: int in range(32):
			assert_eq(_c.get_terrain(Vector2i(x, y)), (y * 32 + x) % 65536)


func test_setters_mark_the_chunk_dirty() -> void:
	assert_false(_c.dirty)
	_c.set_height(Vector2i(1, 1), 3)
	assert_true(_c.dirty, "writing a tile marks the chunk dirty")


func test_getters_do_not_mark_the_chunk_dirty() -> void:
	var _unused: int = _c.get_terrain(Vector2i(1, 1))
	assert_false(_c.dirty, "reading must not dirty the chunk")


func test_walkable_flag() -> void:
	var l: Vector2i = Vector2i(3, 4)
	assert_false(_c.is_walkable(l), "zeroed flags mean not walkable")
	_c.set_flags(l, Chunk.FLAG_WALKABLE)
	assert_true(_c.is_walkable(l))
	_c.set_flags(l, Chunk.FLAG_WALKABLE | Chunk.FLAG_BLOCKS_LIGHT)
	assert_true(_c.is_walkable(l), "walkable survives other flags being set")
