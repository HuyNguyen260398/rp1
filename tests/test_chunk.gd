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
	assert_eq(_c.version, 0, "a freshly constructed chunk is at version 0")


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


func test_a_fresh_chunk_starts_at_version_zero() -> void:
	assert_eq(_c.version, 0, "a freshly constructed chunk is at version 0")


func test_every_setter_advances_the_version() -> void:
	var before: int = _c.version
	_c.set_terrain(Vector2i(1, 1), 7)
	assert_gt(_c.version, before, "writing terrain advances the version")

	before = _c.version
	_c.set_floor(Vector2i(1, 1), 7)
	assert_gt(_c.version, before, "writing floor advances the version")

	before = _c.version
	_c.set_object(Vector2i(1, 1), 7)
	assert_gt(_c.version, before, "writing object advances the version")

	before = _c.version
	_c.set_height(Vector2i(1, 1), 3)
	assert_gt(_c.version, before, "writing height advances the version")

	before = _c.version
	_c.set_flags(Vector2i(1, 1), 1)
	assert_gt(_c.version, before, "writing flags advances the version")


func test_the_version_never_goes_backwards() -> void:
	# Two consumers compare against a remembered number. If a write could
	# lower it, a consumer that had already seen a higher one would go
	# blind to every later edit.
	var seen: int = _c.version
	for i: int in range(50):
		_c.set_object(Vector2i(i % 32, 0), i)
		assert_gt(_c.version, seen, "version decreased or stalled on write %d" % i)
		seen = _c.version


func test_getters_do_not_advance_the_version() -> void:
	_c.set_object(Vector2i(2, 2), 5)
	var after_write: int = _c.version
	var _t: int = _c.get_terrain(Vector2i(2, 2))
	var _o: int = _c.get_object(Vector2i(2, 2))
	assert_eq(_c.version, after_write, "reading must not advance the version")


func test_walkable_flag() -> void:
	var l: Vector2i = Vector2i(3, 4)
	assert_false(_c.is_walkable(l), "zeroed flags mean not walkable")
	_c.set_flags(l, Chunk.FLAG_WALKABLE)
	assert_true(_c.is_walkable(l))
	_c.set_flags(l, Chunk.FLAG_WALKABLE | Chunk.FLAG_BLOCKS_LIGHT)
	assert_true(_c.is_walkable(l), "walkable survives other flags being set")
