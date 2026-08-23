extends GutTest

var _z: Zone


func before_each() -> void:
	_z = Zone.new("home", Vector2i(128, 128))


func test_metadata_is_stored() -> void:
	assert_eq(_z.id, "home")
	assert_eq(_z.size_tiles, Vector2i(128, 128))
	assert_not_null(_z.entities)


func test_chunks_are_created_lazily() -> void:
	assert_null(_z.get_chunk(Vector2i(0, 0)), "no chunk until asked to create one")
	assert_not_null(_z.get_chunk(Vector2i(0, 0), true))
	assert_not_null(_z.get_chunk(Vector2i(0, 0)), "created chunk is retained")


func test_writing_a_tile_creates_its_chunk() -> void:
	_z.set_terrain(Vector2i(100, 100), 5)
	assert_not_null(_z.get_chunk(Vector2i(3, 3)), "tile 100,100 lives in chunk 3,3")


func test_tile_access_by_world_coordinate() -> void:
	_z.set_terrain(Vector2i(40, 70), 9)
	assert_eq(_z.get_terrain(Vector2i(40, 70)), 9)


func test_reading_an_unwritten_tile_returns_zero_without_allocating() -> void:
	assert_eq(_z.get_terrain(Vector2i(64, 64)), 0)
	assert_null(_z.get_chunk(Vector2i(2, 2)), "reads must not allocate chunks")


func test_tiles_across_a_chunk_boundary_are_distinct() -> void:
	# The classic off-by-one: 31 and 32 are adjacent tiles in different chunks.
	_z.set_terrain(Vector2i(31, 0), 111)
	_z.set_terrain(Vector2i(32, 0), 222)
	assert_eq(_z.get_terrain(Vector2i(31, 0)), 111)
	assert_eq(_z.get_terrain(Vector2i(32, 0)), 222)
	assert_eq(_z.get_chunk(Vector2i(0, 0)).get_terrain(Vector2i(31, 0)), 111)
	assert_eq(_z.get_chunk(Vector2i(1, 0)).get_terrain(Vector2i(0, 0)), 222)


func test_negative_world_coordinates_work() -> void:
	_z.set_terrain(Vector2i(-1, -1), 77)
	assert_eq(_z.get_terrain(Vector2i(-1, -1)), 77)
	assert_eq(_z.get_chunk(Vector2i(-1, -1)).get_terrain(Vector2i(31, 31)), 77)


func test_all_five_columns_are_addressable_by_world_coordinate() -> void:
	var w: Vector2i = Vector2i(45, 45)
	_z.set_terrain(w, 1)
	_z.set_floor(w, 2)
	_z.set_object(w, 3)
	_z.set_height(w, 4)
	_z.set_flags(w, Chunk.FLAG_WALKABLE)
	assert_eq(_z.get_terrain(w), 1)
	assert_eq(_z.get_floor(w), 2)
	assert_eq(_z.get_object(w), 3)
	assert_eq(_z.get_height(w), 4)
	assert_true(_z.is_walkable(w))


func test_in_bounds() -> void:
	assert_true(_z.in_bounds(Vector2i(0, 0)))
	assert_true(_z.in_bounds(Vector2i(127, 127)))
	assert_false(_z.in_bounds(Vector2i(128, 0)))
	assert_false(_z.in_bounds(Vector2i(-1, 0)))


func test_dirty_tracking() -> void:
	assert_eq(_z.dirty_chunk_coords().size(), 0)
	_z.set_terrain(Vector2i(0, 0), 1)
	_z.set_terrain(Vector2i(64, 0), 1)
	assert_eq(_z.dirty_chunk_coords().size(), 2, "two chunks touched")
	_z.clear_dirty()
	assert_eq(_z.dirty_chunk_coords().size(), 0)


func test_chunk_coords_are_sorted_for_determinism() -> void:
	var _a: Chunk = _z.get_chunk(Vector2i(2, 1), true)
	var _b: Chunk = _z.get_chunk(Vector2i(0, 0), true)
	var _c: Chunk = _z.get_chunk(Vector2i(1, 0), true)
	assert_eq(
		_z.chunk_coords(),
		[Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 1)] as Array[Vector2i]
	)


func test_fifty_thousand_writes_read_back_correctly() -> void:
	# Scale check for the persistence round-trip in Task 13.
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 12345
	var expected: Dictionary = {}
	for i: int in range(50000):
		var w: Vector2i = Vector2i(rng.randi_range(0, 127), rng.randi_range(0, 127))
		var v: int = rng.randi_range(0, 65535)
		_z.set_terrain(w, v)
		expected[w] = v
	for w: Vector2i in expected:
		assert_eq(_z.get_terrain(w), expected[w])
