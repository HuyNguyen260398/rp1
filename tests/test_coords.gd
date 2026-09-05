extends GutTest


func test_chunk_size_is_32() -> void:
	assert_eq(Coords.CHUNK_SIZE, 32)
	assert_eq(Coords.TILES_PER_CHUNK, 1024)


func test_floordiv_rounds_toward_negative_infinity() -> void:
	assert_eq(Coords.floordiv(0, 32), 0)
	assert_eq(Coords.floordiv(31, 32), 0)
	assert_eq(Coords.floordiv(32, 32), 1)
	assert_eq(Coords.floordiv(63, 32), 1)
	assert_eq(Coords.floordiv(-1, 32), -1, "-1 belongs to chunk -1, not 0")
	assert_eq(Coords.floordiv(-32, 32), -1)
	assert_eq(Coords.floordiv(-33, 32), -2)


func test_world_to_chunk_handles_negative_quadrants() -> void:
	assert_eq(Coords.world_to_chunk(Vector2i(0, 0)), Vector2i(0, 0))
	assert_eq(Coords.world_to_chunk(Vector2i(31, 31)), Vector2i(0, 0))
	assert_eq(Coords.world_to_chunk(Vector2i(32, 32)), Vector2i(1, 1))
	assert_eq(Coords.world_to_chunk(Vector2i(-1, -1)), Vector2i(-1, -1))
	assert_eq(Coords.world_to_chunk(Vector2i(-32, -32)), Vector2i(-1, -1))
	assert_eq(Coords.world_to_chunk(Vector2i(-33, -33)), Vector2i(-2, -2))
	assert_eq(Coords.world_to_chunk(Vector2i(-1, 40)), Vector2i(-1, 1), "mixed signs")


func test_world_to_local_is_always_in_range() -> void:
	for w: int in range(-70, 70):
		var l: Vector2i = Coords.world_to_local(Vector2i(w, w))
		assert_between(l.x, 0, 31, "local x in range for world %d" % w)
		assert_between(l.y, 0, 31, "local y in range for world %d" % w)


func test_chunk_and_local_reconstruct_world_coordinate() -> void:
	# The invariant the whole tile-addressing scheme rests on.
	for wx: int in range(-70, 70):
		for wy: int in [-33, -1, 0, 31, 32, 65]:
			var w: Vector2i = Vector2i(wx, wy)
			var c: Vector2i = Coords.world_to_chunk(w)
			var l: Vector2i = Coords.world_to_local(w)
			assert_eq(
				Coords.chunk_origin(c) + l, w,
				"chunk_origin + local reconstructs %s" % w
			)


func test_local_index_is_row_major() -> void:
	assert_eq(Coords.local_index(Vector2i(0, 0)), 0)
	assert_eq(Coords.local_index(Vector2i(1, 0)), 1)
	assert_eq(Coords.local_index(Vector2i(0, 1)), 32)
	assert_eq(Coords.local_index(Vector2i(31, 31)), 1023)


func test_local_index_is_unique_across_the_chunk() -> void:
	var seen: Dictionary = {}
	for y: int in range(32):
		for x: int in range(32):
			var i: int = Coords.local_index(Vector2i(x, y))
			assert_false(seen.has(i), "index %d is not reused" % i)
			seen[i] = true
	assert_eq(seen.size(), 1024)
