class_name Zone
extends RefCounted
## A bounded map: chunks of tiles plus the entities standing on them.
##
## Tile access is by absolute world coordinate; the zone resolves the chunk.
## Reads never allocate, so probing an empty region cannot balloon memory.

var id: String
var display_name: String
var size_tiles: Vector2i
var biome: String = "temperate"
var generation_seed: int = 0
var entities: EntityStore

var _chunks: Dictionary = {}  ## Vector2i -> Chunk


func _init(p_id: String = "", p_size: Vector2i = Vector2i(128, 128)) -> void:
	id = p_id
	display_name = p_id
	size_tiles = p_size
	entities = EntityStore.new()


func get_chunk(c: Vector2i, create: bool = false) -> Chunk:
	if _chunks.has(c):
		return _chunks[c]
	if not create:
		return null
	var chunk: Chunk = Chunk.new(c)
	_chunks[c] = chunk
	return chunk


## Installs a pre-built chunk, used by the loader. Does not mark it dirty:
## a chunk just read from disk already matches disk.
func install_chunk(chunk: Chunk) -> void:
	_chunks[chunk.coord] = chunk


func chunk_coords() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for c: Vector2i in _chunks:
		out.append(c)
	out.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.y < b.y if a.y != b.y else a.x < b.x)
	return out


func in_bounds(w: Vector2i) -> bool:
	return w.x >= 0 and w.y >= 0 and w.x < size_tiles.x and w.y < size_tiles.y


func dirty_chunk_coords() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for c: Vector2i in chunk_coords():
		if (_chunks[c] as Chunk).dirty:
			out.append(c)
	return out


func clear_dirty() -> void:
	for c: Vector2i in _chunks:
		(_chunks[c] as Chunk).dirty = false


func get_terrain(w: Vector2i) -> int:
	var c: Chunk = get_chunk(Coords.world_to_chunk(w))
	return 0 if c == null else c.get_terrain(Coords.world_to_local(w))


func set_terrain(w: Vector2i, value: int) -> void:
	get_chunk(Coords.world_to_chunk(w), true).set_terrain(Coords.world_to_local(w), value)


func get_floor(w: Vector2i) -> int:
	var c: Chunk = get_chunk(Coords.world_to_chunk(w))
	return 0 if c == null else c.get_floor(Coords.world_to_local(w))


func set_floor(w: Vector2i, value: int) -> void:
	get_chunk(Coords.world_to_chunk(w), true).set_floor(Coords.world_to_local(w), value)


func get_object(w: Vector2i) -> int:
	var c: Chunk = get_chunk(Coords.world_to_chunk(w))
	return 0 if c == null else c.get_object(Coords.world_to_local(w))


func set_object(w: Vector2i, value: int) -> void:
	get_chunk(Coords.world_to_chunk(w), true).set_object(Coords.world_to_local(w), value)


func get_height(w: Vector2i) -> int:
	var c: Chunk = get_chunk(Coords.world_to_chunk(w))
	return 0 if c == null else c.get_height(Coords.world_to_local(w))


func set_height(w: Vector2i, value: int) -> void:
	get_chunk(Coords.world_to_chunk(w), true).set_height(Coords.world_to_local(w), value)


func get_flags(w: Vector2i) -> int:
	var c: Chunk = get_chunk(Coords.world_to_chunk(w))
	return 0 if c == null else c.get_flags(Coords.world_to_local(w))


func set_flags(w: Vector2i, value: int) -> void:
	get_chunk(Coords.world_to_chunk(w), true).set_flags(Coords.world_to_local(w), value)


func is_walkable(w: Vector2i) -> bool:
	var c: Chunk = get_chunk(Coords.world_to_chunk(w))
	return false if c == null else c.is_walkable(Coords.world_to_local(w))
