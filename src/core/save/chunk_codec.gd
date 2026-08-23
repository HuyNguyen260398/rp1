class_name ChunkCodec
extends RefCounted
## Chunk <-> bytes.
##
## The header is plaintext and sits OUTSIDE the compressed payload, so the
## format version can be read before choosing a parse strategy.
## FileAccess.open_compressed() would bury the version inside the compressed
## stream, making it unreadable until after a guess had already been made.

const FORMAT_VERSION: int = 1
const HEADER_BYTES: int = 24

const COMPRESSION_NONE: int = 0
const COMPRESSION_ZSTD: int = 1

const MAGIC_0: int = 0x52  # R
const MAGIC_1: int = 0x50  # P
const MAGIC_2: int = 0x31  # 1
const MAGIC_3: int = 0x43  # C

const OFF_VERSION: int = 4
const OFF_CHUNK_X: int = 8
const OFF_CHUNK_Y: int = 12
const OFF_PAYLOAD_SIZE: int = 16
const OFF_COMPRESSION: int = 20


static func _has_magic(bytes: PackedByteArray) -> bool:
	if bytes.size() < HEADER_BYTES:
		return false
	return (
		bytes.decode_u8(0) == MAGIC_0
		and bytes.decode_u8(1) == MAGIC_1
		and bytes.decode_u8(2) == MAGIC_2
		and bytes.decode_u8(3) == MAGIC_3
	)


static func peek_version(bytes: PackedByteArray) -> int:
	return bytes.decode_u32(OFF_VERSION) if _has_magic(bytes) else -1


static func encode(chunk: Chunk) -> PackedByteArray:
	var payload: PackedByteArray = PackedByteArray()
	payload.append_array(chunk.terrain_id)
	payload.append_array(chunk.floor_id)
	payload.append_array(chunk.object_id)
	payload.append_array(chunk.height)
	payload.append_array(chunk.flags)

	var compressed: PackedByteArray = payload.compress(FileAccess.COMPRESSION_ZSTD)

	var out: PackedByteArray = PackedByteArray()
	out.resize(HEADER_BYTES)
	out.fill(0)
	out.encode_u8(0, MAGIC_0)
	out.encode_u8(1, MAGIC_1)
	out.encode_u8(2, MAGIC_2)
	out.encode_u8(3, MAGIC_3)
	out.encode_u32(OFF_VERSION, FORMAT_VERSION)
	out.encode_s32(OFF_CHUNK_X, chunk.coord.x)
	out.encode_s32(OFF_CHUNK_Y, chunk.coord.y)
	out.encode_u32(OFF_PAYLOAD_SIZE, payload.size())
	out.encode_u8(OFF_COMPRESSION, COMPRESSION_ZSTD)
	out.append_array(compressed)
	return out


static func decode(bytes: PackedByteArray) -> DecodeResult:
	if bytes.size() < HEADER_BYTES:
		return DecodeResult.failure("chunk: file shorter than header (%d bytes)" % bytes.size())
	if not _has_magic(bytes):
		return DecodeResult.failure("chunk: bad magic, not an RP1C file")

	var version: int = bytes.decode_u32(OFF_VERSION)
	if version > FORMAT_VERSION:
		return DecodeResult.failure(
			"chunk: format version %d is newer than supported version %d"
			% [version, FORMAT_VERSION]
		)

	var payload_size: int = bytes.decode_u32(OFF_PAYLOAD_SIZE)
	if payload_size != Chunk.PAYLOAD_BYTES:
		return DecodeResult.failure(
			"chunk: payload size %d, expected %d" % [payload_size, Chunk.PAYLOAD_BYTES]
		)

	var body: PackedByteArray = bytes.slice(HEADER_BYTES)
	if body.is_empty():
		# decompress() pushes an engine error on a zero-length buffer, and a
		# header with no payload is detectably corrupt without asking it.
		return DecodeResult.failure("chunk: header present but payload is empty (truncated?)")

	var payload: PackedByteArray
	match bytes.decode_u8(OFF_COMPRESSION):
		COMPRESSION_NONE:
			payload = body
		COMPRESSION_ZSTD:
			payload = body.decompress(payload_size, FileAccess.COMPRESSION_ZSTD)
		_:
			return DecodeResult.failure("chunk: unknown compression mode")

	if payload.size() != payload_size:
		# decompress() returns an empty array on a truncated stream.
		return DecodeResult.failure(
			"chunk: payload decompressed to %d bytes, expected %d (file truncated?)"
			% [payload.size(), payload_size]
		)

	var chunk: Chunk = Chunk.new(
		Vector2i(bytes.decode_s32(OFF_CHUNK_X), bytes.decode_s32(OFF_CHUNK_Y))
	)
	var u16: int = Chunk.U16_COLUMN_BYTES
	var u8: int = Chunk.U8_COLUMN_BYTES
	var o: int = 0
	chunk.terrain_id = payload.slice(o, o + u16); o += u16
	chunk.floor_id = payload.slice(o, o + u16); o += u16
	chunk.object_id = payload.slice(o, o + u16); o += u16
	chunk.height = payload.slice(o, o + u8); o += u8
	chunk.flags = payload.slice(o, o + u8)
	# Freshly loaded data matches disk, so it is not pending a write.
	chunk.dirty = false
	return DecodeResult.success(chunk)
