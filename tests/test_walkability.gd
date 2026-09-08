extends GutTest

var _r: ContentRegistry
var _grass: int
var _water: int
var _oak: int
var _chunk: Chunk


func before_each() -> void:
	_r = ContentRegistry.new()
	_grass = _r.register({"id": "grass", "category": "terrain", "display_name": "Grass",
		"sprite": "res://none.png", "walkable": true})
	_water = _r.register({"id": "water", "category": "terrain", "display_name": "Water",
		"sprite": "res://none.png", "walkable": false})
	_oak = _r.register({"id": "oak", "category": "object", "display_name": "Oak",
		"sprite": "res://none.png", "blocks_movement": true})
	_chunk = Chunk.new(Vector2i(0, 0))


func test_walkable_terrain_sets_the_flag() -> void:
	_chunk.set_terrain(Vector2i(1, 1), _grass)
	Walkability.recompute_chunk(_chunk, _r)
	assert_true(_chunk.is_walkable(Vector2i(1, 1)))


func test_unwalkable_terrain_clears_the_flag() -> void:
	_chunk.set_terrain(Vector2i(1, 1), _water)
	Walkability.recompute_chunk(_chunk, _r)
	assert_false(_chunk.is_walkable(Vector2i(1, 1)))


func test_a_blocking_object_overrides_walkable_terrain() -> void:
	_chunk.set_terrain(Vector2i(2, 2), _grass)
	_chunk.set_object(Vector2i(2, 2), _oak)
	Walkability.recompute_chunk(_chunk, _r)
	assert_false(_chunk.is_walkable(Vector2i(2, 2)), "grass under an oak is not walkable")


func test_terrain_missing_walkable_defaults_to_walkable() -> void:
	var path: int = _r.register({"id": "path", "category": "terrain",
		"display_name": "Path", "sprite": "res://none.png"})
	_chunk.set_terrain(Vector2i(3, 3), path)
	Walkability.recompute_chunk(_chunk, _r)
	assert_true(_chunk.is_walkable(Vector2i(3, 3)), "optional in the schema, so absent means walkable")


func test_object_missing_blocks_movement_defaults_to_passable() -> void:
	var flower: int = _r.register({"id": "flower", "category": "object",
		"display_name": "Flower", "sprite": "res://none.png"})
	_chunk.set_terrain(Vector2i(4, 4), _grass)
	_chunk.set_object(Vector2i(4, 4), flower)
	Walkability.recompute_chunk(_chunk, _r)
	assert_true(_chunk.is_walkable(Vector2i(4, 4)))


func test_object_id_zero_is_empty_not_unknown() -> void:
	_chunk.set_terrain(Vector2i(5, 5), _grass)
	_chunk.set_object(Vector2i(5, 5), ContentRegistry.ID_UNKNOWN)
	Walkability.recompute_chunk(_chunk, _r)
	assert_true(_chunk.is_walkable(Vector2i(5, 5)), "id 0 means empty cell, not unknown thing")


func test_terrain_id_zero_is_not_floor() -> void:
	Walkability.recompute_chunk(_chunk, _r)
	assert_false(_chunk.is_walkable(Vector2i(6, 6)), "unpainted void is not walkable")


func test_a_placeholder_object_never_blocks() -> void:
	# Stage 1 design 6.4 point 3: an unknown id is non-blocking for movement.
	var ghost: int = _r.register_placeholder("mod:removed_statue")
	_chunk.set_terrain(Vector2i(7, 7), _grass)
	_chunk.set_object(Vector2i(7, 7), ghost)
	Walkability.recompute_chunk(_chunk, _r)
	assert_true(_chunk.is_walkable(Vector2i(7, 7)), "content you cannot see must not wall you in")


func test_blocks_light_survives_a_recompute() -> void:
	_chunk.set_terrain(Vector2i(8, 8), _grass)
	_chunk.set_flags(Vector2i(8, 8), Chunk.FLAG_BLOCKS_LIGHT)
	Walkability.recompute_chunk(_chunk, _r)
	var flags: int = _chunk.get_flags(Vector2i(8, 8))
	assert_true((flags & Chunk.FLAG_BLOCKS_LIGHT) != 0, "the other bit shares this byte")
	assert_true((flags & Chunk.FLAG_WALKABLE) != 0)


func test_recomputing_a_correct_chunk_changes_nothing() -> void:
	_chunk.set_terrain(Vector2i(9, 9), _grass)
	Walkability.recompute_chunk(_chunk, _r)
	assert_eq(Walkability.recompute_chunk(_chunk, _r), 0, "the staleness guard")


func test_recompute_zone_covers_every_chunk() -> void:
	var z: Zone = Zone.new("t", Vector2i(64, 64))
	z.set_terrain(Vector2i(1, 1), _grass)
	z.set_terrain(Vector2i(40, 40), _water)
	Walkability.recompute_zone(z, _r)
	assert_true(z.is_walkable(Vector2i(1, 1)))
	assert_false(z.is_walkable(Vector2i(40, 40)))
