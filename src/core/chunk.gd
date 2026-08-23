class_name Chunk
extends RefCounted
## A 32x32 block of tiles, stored as five parallel byte columns.
##
## Columns are PackedByteArray rather than PackedInt32Array so that the
## in-memory representation IS the storage format: serialising a chunk is a
## buffer concatenation with no width conversion, and a chunk costs 8 KB
## rather than 20 KB.

const U16_COLUMN_BYTES: int = Coords.TILES_PER_CHUNK * 2
const U8_COLUMN_BYTES: int = Coords.TILES_PER_CHUNK
const PAYLOAD_BYTES: int = U16_COLUMN_BYTES * 3 + U8_COLUMN_BYTES * 2

const FLAG_WALKABLE: int = 1 << 0
const FLAG_BLOCKS_LIGHT: int = 1 << 1

var coord: Vector2i
var dirty: bool = false

var terrain_id: PackedByteArray
var floor_id: PackedByteArray
var object_id: PackedByteArray
var height: PackedByteArray
var flags: PackedByteArray


func _init(p_coord: Vector2i = Vector2i.ZERO) -> void:
	coord = p_coord
	terrain_id = _new_column(U16_COLUMN_BYTES)
	floor_id = _new_column(U16_COLUMN_BYTES)
	object_id = _new_column(U16_COLUMN_BYTES)
	height = _new_column(U8_COLUMN_BYTES)
	flags = _new_column(U8_COLUMN_BYTES)


static func _new_column(size: int) -> PackedByteArray:
	var c: PackedByteArray = PackedByteArray()
	c.resize(size)
	c.fill(0)
	return c


func get_terrain(l: Vector2i) -> int:
	return terrain_id.decode_u16(Coords.local_index(l) * 2)


func set_terrain(l: Vector2i, value: int) -> void:
	terrain_id.encode_u16(Coords.local_index(l) * 2, value)
	dirty = true


func get_floor(l: Vector2i) -> int:
	return floor_id.decode_u16(Coords.local_index(l) * 2)


func set_floor(l: Vector2i, value: int) -> void:
	floor_id.encode_u16(Coords.local_index(l) * 2, value)
	dirty = true


func get_object(l: Vector2i) -> int:
	return object_id.decode_u16(Coords.local_index(l) * 2)


func set_object(l: Vector2i, value: int) -> void:
	object_id.encode_u16(Coords.local_index(l) * 2, value)
	dirty = true


func get_height(l: Vector2i) -> int:
	return height[Coords.local_index(l)]


func set_height(l: Vector2i, value: int) -> void:
	height[Coords.local_index(l)] = value
	dirty = true


func get_flags(l: Vector2i) -> int:
	return flags[Coords.local_index(l)]


func set_flags(l: Vector2i, value: int) -> void:
	flags[Coords.local_index(l)] = value
	dirty = true


func is_walkable(l: Vector2i) -> bool:
	return (flags[Coords.local_index(l)] & FLAG_WALKABLE) != 0
