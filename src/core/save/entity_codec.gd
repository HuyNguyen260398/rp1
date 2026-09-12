class_name EntityCodec
extends RefCounted
## EntityStore <-> bytes, using the same plaintext-header pattern as
## ChunkCodec. Only live rows are written, so despawned slots do not
## accumulate in save files.

const FORMAT_VERSION: int = 1
const HEADER_BYTES: int = 24
const ROW_BYTES: int = 18

const MAGIC_0: int = 0x52  # R
const MAGIC_1: int = 0x50  # P
const MAGIC_2: int = 0x31  # 1
const MAGIC_3: int = 0x45  # E

const OFF_VERSION: int = 4
const OFF_COUNT: int = 8
const OFF_NEXT_ID: int = 12


static func _has_magic(bytes: PackedByteArray) -> bool:
	if bytes.size() < HEADER_BYTES:
		return false
	return (
		bytes.decode_u8(0) == MAGIC_0
		and bytes.decode_u8(1) == MAGIC_1
		and bytes.decode_u8(2) == MAGIC_2
		and bytes.decode_u8(3) == MAGIC_3
	)


static func encode(store: EntityStore) -> PackedByteArray:
	var live: PackedInt32Array = store.ids()

	var rows: PackedByteArray = PackedByteArray()
	rows.resize(live.size() * ROW_BYTES)
	rows.fill(0)
	var o: int = 0
	for id: int in live:
		rows.encode_u32(o, id)
		rows.encode_u16(o + 4, store.get_type_id(id))
		rows.encode_float(o + 6, store.get_position(id).x)
		rows.encode_float(o + 10, store.get_position(id).y)
		rows.encode_u8(o + 14, store.get_facing(id))
		rows.encode_u8(o + 15, store.get_entity_flags(id))
		rows.encode_u16(o + 16, 0)  # blob_offset, reserved
		o += ROW_BYTES

	var out: PackedByteArray = PackedByteArray()
	out.resize(HEADER_BYTES)
	out.fill(0)
	out.encode_u8(0, MAGIC_0)
	out.encode_u8(1, MAGIC_1)
	out.encode_u8(2, MAGIC_2)
	out.encode_u8(3, MAGIC_3)
	out.encode_u32(OFF_VERSION, FORMAT_VERSION)
	out.encode_u32(OFF_COUNT, live.size())
	out.encode_u32(OFF_NEXT_ID, store.next_id())
	out.append_array(rows)
	return out


static func decode(bytes: PackedByteArray) -> DecodeResult:
	if bytes.size() < HEADER_BYTES:
		return DecodeResult.failure("entities: file shorter than header")
	if not _has_magic(bytes):
		return DecodeResult.failure("entities: bad magic, not an RP1E file")

	var version: int = bytes.decode_u32(OFF_VERSION)
	if version > FORMAT_VERSION:
		return DecodeResult.failure(
			"entities: format version %d is newer than supported version %d"
			% [version, FORMAT_VERSION]
		)

	var count: int = bytes.decode_u32(OFF_COUNT)
	var expected: int = HEADER_BYTES + count * ROW_BYTES
	if bytes.size() != expected:
		return DecodeResult.failure(
			"entities: file is %d bytes, expected %d for %d entities (truncated or corrupt count?)"
			% [bytes.size(), expected, count]
		)

	var store: EntityStore = EntityStore.new()
	var o: int = HEADER_BYTES
	for i: int in range(count):
		var pos: Vector2 = Vector2(
			bytes.decode_float(o + 6), bytes.decode_float(o + 10))
		store.restore_row(
			bytes.decode_u32(o),
			bytes.decode_u16(o + 4),
			pos,
			bytes.decode_u8(o + 14),
			bytes.decode_u8(o + 15),
			bytes.decode_u16(o + 16),
			pos,  # v1 has no home column; Task 4 replaces this
		)
		o += ROW_BYTES

	store.set_next_id(bytes.decode_u32(OFF_NEXT_ID))
	return DecodeResult.success(store)
