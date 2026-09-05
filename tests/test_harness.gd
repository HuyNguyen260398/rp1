extends GutTest


func test_harness_runs() -> void:
	assert_eq(1 + 1, 2, "the test harness executes assertions")


func test_byte_encoding_available() -> void:
	# Guards the engine API the whole data layer is built on.
	var b: PackedByteArray = PackedByteArray()
	b.resize(4)
	b.encode_u16(0, 65535)
	assert_eq(b.decode_u16(0), 65535, "u16 round-trips through PackedByteArray")
