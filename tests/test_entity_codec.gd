extends GutTest


func _sample_store() -> EntityStore:
	var s: EntityStore = EntityStore.new()
	var a: int = s.spawn(3, Vector2(10.5, -20.25))
	s.set_facing(a, 4)
	var b: int = s.spawn(9, Vector2(0.0, 127.75))
	s.set_facing(b, 1)
	return s


func test_header_is_readable_without_decompressing() -> void:
	var bytes: PackedByteArray = EntityCodec.encode(_sample_store())
	assert_eq(bytes.decode_u8(0), 0x52)
	assert_eq(bytes.decode_u8(3), 0x45, "E for entities")
	assert_eq(bytes.decode_u32(4), EntityCodec.FORMAT_VERSION)
	assert_eq(bytes.decode_u32(8), 2, "entity count")


func test_round_trip_preserves_entities() -> void:
	var original: EntityStore = _sample_store()
	var result: DecodeResult = EntityCodec.decode(EntityCodec.encode(original))
	assert_true(result.ok, "decode succeeded: %s" % result.error)
	var back: EntityStore = result.value
	assert_eq(back.count(), original.count())
	for id: int in original.ids():
		assert_true(back.has(id), "entity %d survived" % id)
		assert_eq(back.get_type_id(id), original.get_type_id(id))
		assert_eq(back.get_facing(id), original.get_facing(id))
		assert_almost_eq(back.get_position(id).x, original.get_position(id).x, 0.001)
		assert_almost_eq(back.get_position(id).y, original.get_position(id).y, 0.001)


func test_next_id_survives_the_round_trip() -> void:
	# Without this, a reloaded world reissues ids that saved entities hold.
	var original: EntityStore = _sample_store()
	var back: EntityStore = EntityCodec.decode(EntityCodec.encode(original)).value
	assert_eq(back.next_id(), original.next_id())
	assert_ne(back.spawn(1, Vector2.ZERO), original.ids()[0])


func test_despawned_entities_are_not_written() -> void:
	var s: EntityStore = _sample_store()
	assert_true(s.despawn(s.ids()[0]))
	var bytes: PackedByteArray = EntityCodec.encode(s)
	assert_eq(bytes.decode_u32(8), 1, "only the live entity is written")
	assert_eq((EntityCodec.decode(bytes).value as EntityStore).count(), 1)


func test_empty_store_round_trips() -> void:
	var result: DecodeResult = EntityCodec.decode(EntityCodec.encode(EntityStore.new()))
	assert_true(result.ok)
	assert_eq((result.value as EntityStore).count(), 0)


func test_bad_magic_is_rejected() -> void:
	var bytes: PackedByteArray = EntityCodec.encode(_sample_store())
	bytes.encode_u8(3, 0x43)  # "C" -- a chunk file, not an entity file
	var result: DecodeResult = EntityCodec.decode(bytes)
	assert_false(result.ok)
	assert_string_contains(result.error, "magic")


func test_truncated_file_fails_gracefully() -> void:
	var bytes: PackedByteArray = EntityCodec.encode(_sample_store())
	assert_false(EntityCodec.decode(bytes.slice(0, bytes.size() - 5)).ok)


func test_count_larger_than_payload_is_rejected() -> void:
	# A corrupted count must not cause an out-of-bounds read.
	var bytes: PackedByteArray = EntityCodec.encode(_sample_store())
	bytes.encode_u32(8, 100000)
	assert_false(EntityCodec.decode(bytes).ok)
