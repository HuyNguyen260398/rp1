extends GutTest


func _sample_chunk() -> Chunk:
	var c: Chunk = Chunk.new(Vector2i(-3, 7))
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 99
	for y: int in range(32):
		for x: int in range(32):
			var l: Vector2i = Vector2i(x, y)
			c.set_terrain(l, rng.randi_range(0, 65535))
			c.set_object(l, rng.randi_range(0, 300))
			c.set_height(l, rng.randi_range(0, 255))
			c.set_flags(l, rng.randi_range(0, 3))
	return c


func test_header_is_readable_without_decompressing() -> void:
	# The entire reason the header sits outside the compressed payload.
	var bytes: PackedByteArray = ChunkCodec.encode(_sample_chunk())
	assert_eq(bytes.decode_u8(0), 0x52, "R")
	assert_eq(bytes.decode_u8(1), 0x50, "P")
	assert_eq(bytes.decode_u8(2), 0x31, "1")
	assert_eq(bytes.decode_u8(3), 0x43, "C")
	assert_eq(bytes.decode_u32(4), ChunkCodec.FORMAT_VERSION)
	assert_eq(bytes.decode_s32(8), -3, "negative chunk x survives")
	assert_eq(bytes.decode_s32(12), 7)
	assert_eq(bytes.decode_u32(16), Chunk.PAYLOAD_BYTES)


func test_peek_version_does_not_decompress() -> void:
	var bytes: PackedByteArray = ChunkCodec.encode(_sample_chunk())
	assert_eq(ChunkCodec.peek_version(bytes), ChunkCodec.FORMAT_VERSION)


func test_round_trip_preserves_every_tile() -> void:
	var original: Chunk = _sample_chunk()
	var result: DecodeResult = ChunkCodec.decode(ChunkCodec.encode(original))
	assert_true(result.ok, "decode succeeded: %s" % result.error)
	var back: Chunk = result.value
	assert_eq(back.coord, original.coord)
	for y: int in range(32):
		for x: int in range(32):
			var l: Vector2i = Vector2i(x, y)
			assert_eq(back.get_terrain(l), original.get_terrain(l))
			assert_eq(back.get_object(l), original.get_object(l))
			assert_eq(back.get_height(l), original.get_height(l))
			assert_eq(back.get_flags(l), original.get_flags(l))


func test_columns_round_trip_byte_identical() -> void:
	var original: Chunk = _sample_chunk()
	var back: Chunk = ChunkCodec.decode(ChunkCodec.encode(original)).value
	assert_eq(back.terrain_id, original.terrain_id)
	assert_eq(back.floor_id, original.floor_id)
	assert_eq(back.object_id, original.object_id)
	assert_eq(back.height, original.height)
	assert_eq(back.flags, original.flags)


func test_decoded_chunk_is_not_dirty() -> void:
	# A chunk just read from disk matches disk, so saving it again is waste.
	var back: Chunk = ChunkCodec.decode(ChunkCodec.encode(_sample_chunk())).value
	assert_false(back.dirty)


func test_compression_actually_shrinks_repetitive_data() -> void:
	var c: Chunk = Chunk.new(Vector2i.ZERO)
	for y: int in range(32):
		for x: int in range(32):
			c.set_terrain(Vector2i(x, y), 1)
	var bytes: PackedByteArray = ChunkCodec.encode(c)
	assert_lt(bytes.size(), 1024, "a uniform chunk compresses far below 8 KB")


func test_bad_magic_is_rejected() -> void:
	var bytes: PackedByteArray = ChunkCodec.encode(_sample_chunk())
	bytes.encode_u8(0, 0x00)
	var result: DecodeResult = ChunkCodec.decode(bytes)
	assert_false(result.ok)
	assert_string_contains(result.error, "magic")
	assert_eq(ChunkCodec.peek_version(bytes), -1)


func test_truncated_file_fails_gracefully() -> void:
	# Power loss mid-write must produce an error, never a crash or a
	# silently half-populated chunk.
	var bytes: PackedByteArray = ChunkCodec.encode(_sample_chunk())
	var truncated: PackedByteArray = bytes.slice(0, bytes.size() / 2)
	var result: DecodeResult = ChunkCodec.decode(truncated)
	assert_false(result.ok, "truncated payload is rejected")
	assert_ne(result.error, "")


func test_header_only_file_fails_gracefully() -> void:
	var bytes: PackedByteArray = ChunkCodec.encode(_sample_chunk())
	assert_false(ChunkCodec.decode(bytes.slice(0, 24)).ok)


func test_empty_buffer_fails_gracefully() -> void:
	assert_false(ChunkCodec.decode(PackedByteArray()).ok)


func test_future_version_is_rejected_with_a_clear_message() -> void:
	var bytes: PackedByteArray = ChunkCodec.encode(_sample_chunk())
	bytes.encode_u32(4, 999)
	var result: DecodeResult = ChunkCodec.decode(bytes)
	assert_false(result.ok)
	assert_string_contains(result.error, "version")
