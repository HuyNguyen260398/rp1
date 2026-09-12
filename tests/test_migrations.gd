extends GutTest


func test_current_version_needs_no_migration() -> void:
	assert_false(Migrations.needs_migration(ChunkCodec.FORMAT_VERSION))


func test_older_version_needs_migration() -> void:
	assert_true(Migrations.needs_migration(ChunkCodec.FORMAT_VERSION - 1))


func test_migrating_the_current_version_is_a_no_op() -> void:
	var c: Chunk = Chunk.new(Vector2i(0, 0))
	c.set_terrain(Vector2i(1, 1), 42)
	var result: DecodeResult = Migrations.migrate_chunk(ChunkCodec.FORMAT_VERSION, c)
	assert_true(result.ok, result.error)
	assert_eq((result.value as Chunk).get_terrain(Vector2i(1, 1)), 42)


func test_unknown_older_version_reports_a_clear_error() -> void:
	var result: DecodeResult = Migrations.migrate_chunk(0, Chunk.new(Vector2i.ZERO))
	assert_false(result.ok)
	assert_string_contains(result.error, "0")


func test_committed_v1_fixture_still_loads() -> void:
	# The regression guard. When FORMAT_VERSION becomes 2, this test proves
	# version 1 files written by shipped builds still open.
	var path: String = "res://tests/fixtures/v1_chunk.chunk"
	assert_true(FileAccess.file_exists(path), "fixture is committed")

	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
	assert_eq(ChunkCodec.peek_version(bytes), 1, "fixture is a version 1 file")

	var decoded: DecodeResult = ChunkCodec.decode(bytes)
	assert_true(decoded.ok, "v1 fixture decodes: %s" % decoded.error)

	var c: Chunk = decoded.value
	assert_eq(c.coord, Vector2i(1, 2))
	for y: int in range(32):
		for x: int in range(32):
			var l: Vector2i = Vector2i(x, y)
			assert_eq(c.get_terrain(l), (x * 31 + y * 17) % 65536)
			assert_eq(c.get_height(l), (x + y) % 256)


func test_v1_entities_fixture_still_decodes() -> void:
	# This passes trivially today, when v1 is current. It is committed now
	# so that the format bump has a real v1 file to migrate, written by the
	# real v1 encoder rather than hand-assembled after the fact.
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(
		"res://tests/fixtures/v1_entities.dat")
	assert_gt(bytes.size(), 0, "fixture is missing; run tools/make_fixture.gd")

	var result: DecodeResult = EntityCodec.decode(bytes)
	assert_true(result.ok, result.error)

	var store: EntityStore = result.value
	assert_eq(store.count(), 3)
	assert_eq(store.get_position(1), Vector2(4.5, 9.5))
	assert_eq(store.get_position(3), Vector2(127.5, 0.5))
	assert_eq(store.get_facing(2), 2)
	assert_eq(store.next_id(), 4)
