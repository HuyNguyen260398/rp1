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


func test_invalidate_changed_drops_only_the_touched_chunk() -> void:
	# Chunks are created lazily, so chunk_coords() on a fresh zone is empty.
	# Bring all four into existence from size_tiles, or the first-look
	# assertion below compares 0 to 0 and passes vacuously.
	var z: Zone = Zone.new("t", Vector2i(64, 64))
	var dims: Vector2i = z.size_tiles / Coords.CHUNK_SIZE
	for y: int in range(dims.y):
		for x: int in range(dims.x):
			var _c: Chunk = z.get_chunk(Vector2i(x, y), true)
	assert_eq(z.chunk_coords().size(), 4, "the fixture zone is 2x2 chunks")
	var b: CollisionBuilder = CollisionBuilder.new()
	for c: Vector2i in z.chunk_coords():
		var _r: Array[Rect2i] = b.solids_for(z, c)
	# A builder that has never looked has seen nothing, so its first call
	# drops every chunk. That is correct -- it cannot know its cache is
	# current -- and it is what settles the watcher for the asserts below.
	assert_eq(b.invalidate_changed(z), z.chunk_coords().size(),
		"the first look treats every chunk as changed")
	assert_eq(b.invalidate_changed(z), 0, "a quiet zone invalidates nothing")

	z.set_flags(Vector2i(1, 1), 0)
	assert_eq(b.invalidate_changed(z), 1, "only the touched chunk is dropped")
	assert_eq(b.invalidate_changed(z), 0, "the drop is not repeated")


func test_a_rebuilt_chunk_reflects_the_new_tiles() -> void:
	# A fresh chunk has every flag byte at 0, which already means NOT
	# walkable -- so "make a tile solid" on a fresh chunk changes nothing
	# and would assert vacuously. Make the chunk walkable first, so that
	# clearing one tile is a real change.
	var z: Zone = Zone.new("t", Vector2i(64, 64))
	var _c: Chunk = z.get_chunk(Vector2i(0, 0), true)
	for y: int in range(Coords.CHUNK_SIZE):
		for x: int in range(Coords.CHUNK_SIZE):
			z.set_flags(Vector2i(x, y), Chunk.FLAG_WALKABLE)

	# Read through solids_for(), the cached path. rects_for_chunk() never
	# caches, so asserting on it would pass without any invalidation at all.
	var b: CollisionBuilder = CollisionBuilder.new()
	var _n0: int = b.invalidate_changed(z)
	var before: int = b.solids_for(z, Vector2i(0, 0)).size()
	assert_eq(before, 0, "an all-walkable chunk needs no collision rects")

	z.set_flags(Vector2i(2, 2), 0)
	assert_eq(b.solids_for(z, Vector2i(0, 0)).size(), before,
		"without invalidation the cache still holds the old rects")
	var _n: int = b.invalidate_changed(z)
	assert_gt(b.solids_for(z, Vector2i(0, 0)).size(), before,
		"the rebuilt chunk reflects the newly solid tile")
