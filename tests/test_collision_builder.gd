extends GutTest

var _b: CollisionBuilder


func before_each() -> void:
	_b = CollisionBuilder.new()


func _blocked_chunk(coord: Vector2i) -> Chunk:
	# Every tile starts with FLAG_WALKABLE clear, so a fresh chunk is solid.
	return Chunk.new(coord)


func _open_chunk(coord: Vector2i) -> Chunk:
	var c: Chunk = Chunk.new(coord)
	for y: int in range(Coords.CHUNK_SIZE):
		for x: int in range(Coords.CHUNK_SIZE):
			c.set_flags(Vector2i(x, y), Chunk.FLAG_WALKABLE)
	return c


func test_a_fully_open_chunk_has_no_rects() -> void:
	assert_eq(_b.rects_for_chunk(_open_chunk(Vector2i(0, 0))).size(), 0)


func test_a_fully_blocked_chunk_is_one_rect_per_row() -> void:
	var rects: Array[Rect2i] = _b.rects_for_chunk(_blocked_chunk(Vector2i(0, 0)))
	assert_eq(rects.size(), 32, "row-merge yields 32, not 1024 colliders")
	assert_eq(rects[0], Rect2i(0, 0, 32, 1))


func test_a_run_in_the_middle_of_a_row() -> void:
	var c: Chunk = _open_chunk(Vector2i(0, 0))
	for x: int in range(4, 9):
		c.set_flags(Vector2i(x, 3), 0)
	var rects: Array[Rect2i] = _b.rects_for_chunk(c)
	assert_eq(rects.size(), 1)
	assert_eq(rects[0], Rect2i(4, 3, 5, 1))


func test_two_runs_in_one_row_stay_separate() -> void:
	var c: Chunk = _open_chunk(Vector2i(0, 0))
	c.set_flags(Vector2i(2, 0), 0)
	c.set_flags(Vector2i(5, 0), 0)
	var rects: Array[Rect2i] = _b.rects_for_chunk(c)
	assert_eq(rects.size(), 2)
	assert_eq(rects[0], Rect2i(2, 0, 1, 1))
	assert_eq(rects[1], Rect2i(5, 0, 1, 1))


func test_a_run_reaching_the_chunk_edge_is_closed() -> void:
	var c: Chunk = _open_chunk(Vector2i(0, 0))
	c.set_flags(Vector2i(31, 0), 0)
	var rects: Array[Rect2i] = _b.rects_for_chunk(c)
	assert_eq(rects.size(), 1)
	assert_eq(rects[0], Rect2i(31, 0, 1, 1), "the last column must not be dropped")


func test_rects_are_in_world_coordinates() -> void:
	var c: Chunk = _open_chunk(Vector2i(2, 3))
	c.set_flags(Vector2i(1, 1), 0)
	var rects: Array[Rect2i] = _b.rects_for_chunk(c)
	assert_eq(rects[0], Rect2i(65, 97, 1, 1), "chunk 2,3 starts at world tile 64,96")


func test_rects_come_out_row_major() -> void:
	var c: Chunk = _open_chunk(Vector2i(0, 0))
	c.set_flags(Vector2i(0, 5), 0)
	c.set_flags(Vector2i(0, 1), 0)
	var rects: Array[Rect2i] = _b.rects_for_chunk(c)
	assert_eq(rects[0].position.y, 1, "determinism: tests assert on exact output")
	assert_eq(rects[1].position.y, 5)


func test_a_missing_chunk_is_solid() -> void:
	var z: Zone = Zone.new("t", Vector2i(128, 128))
	var rects: Array[Rect2i] = _b.solids_for(z, Vector2i(0, 0))
	assert_eq(rects.size(), 1)
	assert_eq(rects[0], Rect2i(0, 0, 32, 32), "an unloaded region is not somewhere to walk")


func test_solids_near_gathers_every_overlapped_chunk() -> void:
	var z: Zone = Zone.new("t", Vector2i(128, 128))
	# Each of the four chunks gets ONE distinguishing blocked tile at the
	# same local coordinate, so each contributes exactly one rect and the
	# four rects land at four different, predictable world positions. A
	# solids_near() that misses a chunk shows up as a missing rect, not as
	# a size that happens to match by coincidence.
	for c: Vector2i in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
		var chunk: Chunk = _open_chunk(c)
		chunk.set_flags(Vector2i(5, 5), 0)
		z.install_chunk(chunk)
	# A 2x2-tile area straddling the corner where all four chunks meet.
	var rects: Array[Rect2i] = _b.solids_near(z, Rect2(Vector2(31.0, 31.0), Vector2(2.0, 2.0)))
	assert_eq(rects.size(), 4, "one blocked tile from each of the four overlapped chunks")
	var expected: Array[Rect2i] = [
		Rect2i(5, 5, 1, 1),
		Rect2i(37, 5, 1, 1),
		Rect2i(5, 37, 1, 1),
		Rect2i(37, 37, 1, 1),
	]
	for r: Rect2i in expected:
		assert_true(rects.has(r), "missing expected rect %s -- a chunk was not gathered" % [r])


func test_invalidate_forces_a_rebuild() -> void:
	var z: Zone = Zone.new("t", Vector2i(128, 128))
	z.install_chunk(_open_chunk(Vector2i(0, 0)))
	assert_eq(_b.solids_for(z, Vector2i(0, 0)).size(), 0)

	z.get_chunk(Vector2i(0, 0)).set_flags(Vector2i(3, 3), 0)
	assert_eq(_b.solids_for(z, Vector2i(0, 0)).size(), 0, "still the cached answer")

	_b.invalidate(Vector2i(0, 0))
	assert_eq(_b.solids_for(z, Vector2i(0, 0)).size(), 1, "rebuilt after invalidation")
