class_name EntityStore
extends RefCounted
## Per-zone entity storage, struct-of-arrays.
##
## Mirrors the Chunk column layout so there is one serialisation pattern in
## the codebase rather than two. Entities belong to a zone rather than a
## chunk, so crossing a chunk boundary is a position update and nothing more.

const INVALID_ID: int = 0

const FLAG_ACTIVE: int = 1 << 0
const FLAG_PERSISTED: int = 1 << 1

var _id: PackedInt32Array = PackedInt32Array()
var _type_id: PackedInt32Array = PackedInt32Array()
var _x: PackedFloat32Array = PackedFloat32Array()
var _y: PackedFloat32Array = PackedFloat32Array()
## Where the entity belongs, as opposed to where it currently is.
## AnimalSystem wanders around this point and walks back to it. It is a
## column rather than system state because it is authored data: a home
## rebuilt from current position on every load lets the authored world
## erode across sessions. See Phase 5 design section 5.
var _home_x: PackedFloat32Array = PackedFloat32Array()
var _home_y: PackedFloat32Array = PackedFloat32Array()
var _facing: PackedByteArray = PackedByteArray()
var _flags: PackedByteArray = PackedByteArray()
## Offset into a side buffer for variable-length per-entity state.
## Unused in Stage 1, present so the save format does not change later.
var _blob_offset: PackedInt32Array = PackedInt32Array()

var _free_slots: PackedInt32Array = PackedInt32Array()
var _slot_by_id: Dictionary = {}
var _next_id: int = 1


func next_id() -> int:
	return _next_id


func set_next_id(value: int) -> void:
	_next_id = value


func count() -> int:
	return _slot_by_id.size()


func row_count() -> int:
	return _id.size()


func has(id: int) -> bool:
	return _slot_by_id.has(id)


func spawn(
	type_id: int,
	pos: Vector2,
	entity_flags: int = FLAG_ACTIVE | FLAG_PERSISTED
) -> int:
	var id: int = _next_id
	_next_id += 1

	var slot: int
	if _free_slots.is_empty():
		slot = _id.size()
		_id.append(id)
		_type_id.append(type_id)
		_x.append(pos.x)
		_y.append(pos.y)
		_home_x.append(pos.x)
		_home_y.append(pos.y)
		_facing.append(0)
		_flags.append(entity_flags)
		_blob_offset.append(0)
	else:
		slot = _free_slots[_free_slots.size() - 1]
		_free_slots.remove_at(_free_slots.size() - 1)
		_id[slot] = id
		_type_id[slot] = type_id
		_x[slot] = pos.x
		_y[slot] = pos.y
		_home_x[slot] = pos.x
		_home_y[slot] = pos.y
		_facing[slot] = 0
		_flags[slot] = entity_flags
		_blob_offset[slot] = 0

	_slot_by_id[id] = slot
	return id


func despawn(id: int) -> bool:
	if not _slot_by_id.has(id):
		return false
	var slot: int = _slot_by_id[id]
	_id[slot] = INVALID_ID
	_flags[slot] = 0
	_free_slots.append(slot)
	_slot_by_id.erase(id)
	return true


func ids() -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	for slot: int in range(_id.size()):
		if _id[slot] != INVALID_ID:
			out.append(_id[slot])
	return out


func get_type_id(id: int) -> int:
	return _type_id[_slot_by_id[id]]


## Codec support: rewrite a row's type through the save's id translation.
func set_type_id(id: int, type_id: int) -> void:
	_type_id[_slot_by_id[id]] = type_id


func get_position(id: int) -> Vector2:
	var slot: int = _slot_by_id[id]
	return Vector2(_x[slot], _y[slot])


func set_position(id: int, pos: Vector2) -> void:
	var slot: int = _slot_by_id[id]
	_x[slot] = pos.x
	_y[slot] = pos.y


func get_home(id: int) -> Vector2:
	var slot: int = _slot_by_id[id]
	return Vector2(_home_x[slot], _home_y[slot])


func set_home(id: int, pos: Vector2) -> void:
	var slot: int = _slot_by_id[id]
	_home_x[slot] = pos.x
	_home_y[slot] = pos.y


func get_facing(id: int) -> int:
	return _facing[_slot_by_id[id]]


func set_facing(id: int, facing: int) -> void:
	_facing[_slot_by_id[id]] = facing


func get_entity_flags(id: int) -> int:
	return _flags[_slot_by_id[id]]


## Codec support: rebuild a row verbatim during load.
func restore_row(
	id: int, type_id: int, pos: Vector2, facing: int, entity_flags: int,
	blob_offset: int, home: Vector2
) -> void:
	var slot: int = _id.size()
	_id.append(id)
	_type_id.append(type_id)
	_x.append(pos.x)
	_y.append(pos.y)
	_home_x.append(home.x)
	_home_y.append(home.y)
	_facing.append(facing)
	_flags.append(entity_flags)
	_blob_offset.append(blob_offset)
	_slot_by_id[id] = slot
