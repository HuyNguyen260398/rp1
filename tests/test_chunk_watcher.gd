extends GutTest
## The multi-consumer dirty channel, which Stage 1 did not have and the
## Stage 2 design §3.1 requires.

var _z: Zone = null


func before_each() -> void:
	_z = Zone.new("test", Vector2i(64, 64))
	_populate(_z)


## Brings every chunk of a zone into existence. Chunks are created lazily,
## so chunk_coords() on a fresh zone is empty -- iterating it here would
## touch nothing and leave the "reports every chunk" assertions vacuous.
func _populate(z: Zone) -> void:
	var dims: Vector2i = z.size_tiles / Coords.CHUNK_SIZE
	for y: int in range(dims.y):
		for x: int in range(dims.x):
			var _c: Chunk = z.get_chunk(Vector2i(x, y), true)


func test_a_fresh_watcher_reports_every_chunk() -> void:
	# A watcher that has never looked has seen nothing, so everything is
	# work. This is what makes the initial full paint fall out for free.
	var w: ChunkWatcher = ChunkWatcher.new()
	assert_eq(_z.chunk_coords().size(), 4, "the fixture zone is 2x2 chunks")
	assert_eq(w.changed(_z).size(), _z.chunk_coords().size())


func test_marking_seen_makes_a_quiet_zone_report_nothing() -> void:
	var w: ChunkWatcher = ChunkWatcher.new()
	w.mark_seen(_z)
	assert_eq(w.changed(_z), [] as Array[Vector2i])


func test_a_write_is_reported_to_the_watcher() -> void:
	var w: ChunkWatcher = ChunkWatcher.new()
	w.mark_seen(_z)
	_z.set_object(Vector2i(5, 5), 3)
	assert_eq(w.changed(_z), [Vector2i(0, 0)] as Array[Vector2i])


func test_changed_is_idempotent_until_marked_seen() -> void:
	# Asking twice must answer twice. A consumer that asks, fails, and
	# asks again has not lost the work.
	var w: ChunkWatcher = ChunkWatcher.new()
	w.mark_seen(_z)
	_z.set_object(Vector2i(5, 5), 3)
	assert_eq(w.changed(_z).size(), 1)
	assert_eq(w.changed(_z).size(), 1, "asking did not consume the answer")
	w.mark_seen(_z)
	assert_eq(w.changed(_z).size(), 0)


func test_two_watchers_do_not_starve_each_other() -> void:
	# THE regression test for this phase. In Stage 1 the renderer and the
	# save both called zone.clear_dirty(); whichever ran second saw
	# nothing, and an edit could reach the screen without reaching disk.
	var renderer: ChunkWatcher = ChunkWatcher.new()
	var saver: ChunkWatcher = ChunkWatcher.new()
	renderer.mark_seen(_z)
	saver.mark_seen(_z)

	_z.set_object(Vector2i(5, 5), 3)

	assert_eq(renderer.changed(_z).size(), 1, "the renderer sees the edit")
	renderer.mark_seen(_z)
	assert_eq(saver.changed(_z).size(), 1,
		"the save still sees the edit after the renderer consumed it")


func test_forget_reports_everything_again() -> void:
	var w: ChunkWatcher = ChunkWatcher.new()
	w.mark_seen(_z)
	assert_eq(w.changed(_z).size(), 0)
	w.forget()
	assert_eq(w.changed(_z).size(), _z.chunk_coords().size())


func test_a_chunk_created_after_the_last_look_is_reported() -> void:
	var small: Zone = Zone.new("small", Vector2i(64, 64))
	var w: ChunkWatcher = ChunkWatcher.new()
	w.mark_seen(small)
	small.set_object(Vector2i(40, 40), 9)
	assert_true(w.changed(small).has(Vector2i(1, 1)),
		"a chunk brought into existence by a write is work")
