class_name World
extends Node2D
## The running game: renderer, entities, player, camera, animals.
##
## Handed a Zone rather than loading one, so it does not know or care
## whether that zone was authored for a new world or decoded from a save.
## Everything here was main.gd's _ready() before Phase 5 gave main.gd a
## menu to show first.

## Emitted when the player presses interact, carrying the tile they face.
## The world only says where. What interacting there means is the
## router's decision -- Stage 2 design 3.5: presentation emits, the
## router decides -- so no presentation node writes to the Zone for it.
signal interact_requested(tile: Vector2i)

var zone: Zone = null
var player_entity_id: int = EntityStore.INVALID_ID

var _registry: ContentRegistry = null
var _animals: AnimalSystem = null
var _renderer: ZoneRenderer = null
var _entity_renderer: EntityRenderer = null
var _player: Player = null
var _camera: FollowCamera = null
var _collision: CollisionBuilder = null
var _audio: AudioStage = null


## Assembles the world. Returns the problems worth showing the player;
## the caller decides how to report them.
func build(registry: ContentRegistry, result: SessionOpenResult) -> PackedStringArray:
	var errors: PackedStringArray = []

	# Nested Y-sorted nodes flatten into this one's sort, so the object
	# layer's tiles and the entity sprites interleave by their y position.
	y_sort_enabled = true

	# The router is PROCESS_MODE_ALWAYS so it can hear the un-pause key,
	# and process_mode is inherited: without this the player would keep
	# walking while the pause menu is open.
	process_mode = Node.PROCESS_MODE_PAUSABLE

	_registry = registry
	zone = result.zone

	_renderer = ZoneRenderer.new()
	_renderer.name = "ZoneRenderer"
	add_child(_renderer)

	for e: String in _renderer.setup(registry):
		errors.append("tileset: %s" % e)

	var painted: int = _renderer.render_zone(zone)
	_renderer.zone = zone

	# The export gate asserts this count is non-zero. A build can export
	# cleanly and still ship without its textures, exactly as it nearly
	# shipped without data/*.json.
	print("RP1 rendered %d cells" % painted)

	_entity_renderer = EntityRenderer.new()
	_entity_renderer.name = "EntityRenderer"
	add_child(_entity_renderer)
	_entity_renderer.setup(registry)
	_entity_renderer.entities = zone.entities

	_audio = AudioStage.new()
	_audio.name = "AudioStage"
	add_child(_audio)
	_audio.setup(registry)

	_collision = CollisionBuilder.new()

	_animals = AnimalSystem.new()
	_animals.rng = RandomNumberGenerator.new()
	# Seeded from the zone rather than from the clock, so one world always
	# behaves the same way and a bug reported against it is reproducible.
	_animals.rng.seed = zone.generation_seed

	_player = Player.new()
	_player.name = "Player"
	add_child(_player)
	if result.is_new:
		var spawn_near: Vector2i = Vector2i(
			floori(result.player_spawn.x), floori(result.player_spawn.y))
		player_entity_id = _player.spawn(zone, registry, _collision, spawn_near)
	else:
		# The save already holds a player row. Spawning here would leave
		# two of them.
		_player.adopt(zone, _collision, result.player_entity_id)
		player_entity_id = _player.entity_id
	print("RP1 player at %s" % zone.entities.get_position(player_entity_id))

	_camera = FollowCamera.new()
	_camera.name = "FollowCamera"
	add_child(_camera)
	_camera.setup(zone)
	_camera.target_id = player_entity_id
	_camera.make_current()

	return errors


## Animals move in the physics step, alongside the player, so both see the
## same fixed delta and the same collision geometry. Called by the router
## rather than run from _physics_process, so pausing is decided in one
## place.
func tick_animals(delta: float) -> void:
	if _animals == null or zone == null:
		return
	if _player == null or not zone.entities.has(player_entity_id):
		return
	var _moved: int = _animals.tick(
		zone,
		_registry,
		_collision,
		zone.entities.get_position(player_entity_id),
		delta
	)


## Drops cached collision rects for every chunk edited since the last
## step, so a tile placed this frame is solid to the player and the animals
## on the next one. Called by the router before tick_animals(): the router
## is an ancestor of the player, so it runs first in the physics step and
## both movers read the same, current geometry.
func tick_collision() -> void:
	if _collision == null or zone == null:
		return
	var _dropped: int = _collision.invalidate_changed(zone)


## Audio is ticked from the same physics step as movement, so the distance
## the player covered and the cues it produces belong to the same frame.
## The director is passed in rather than owned: it outlives the world, so
## a volume change on the menu is not lost when a world is torn down.
func tick_audio(director: AudioDirector) -> void:
	if _player == null or zone == null or _audio == null:
		return
	var pos: Vector2 = zone.entities.get_position(player_entity_id)
	var tile: Vector2i = Vector2i(floori(pos.x), floori(pos.y))
	var terrain_id: int = zone.get_terrain(tile) if zone.in_bounds(tile) else 0
	_audio.play(director.tick(_player.distance_moved_last_step, terrain_id))
	_audio.set_bed(director.bed())


# --- debug ------------------------------------------------------------

## World is PROCESS_MODE_PAUSABLE, so this is not heard while paused.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact"):
		get_viewport().set_input_as_handled()
		if zone != null and zone.entities.has(player_entity_id):
			interact_requested.emit(_player_facing_tile())
		return
	if event.is_action_pressed("debug_place"):
		get_viewport().set_input_as_handled()
		_debug_place_wall()


## DEBUG ONLY -- removed in Phase 10 when build mode lands. This exists to
## prove the Phase 7 mutation spine end to end: one edit, seen by the
## renderer, the collider and the save without any of them robbing the
## others.
func _debug_place_wall() -> void:
	if zone == null or not zone.entities.has(player_entity_id):
		return
	var tile: Vector2i = _player_facing_tile()
	if not zone.in_bounds(tile):
		return
	if zone.get_object(tile) != ContentRegistry.ID_UNKNOWN:
		return
	# A wall dropped across the player's own body would trap them inside a
	# solid, which is a movement bug report rather than a spine test.
	var feet: Vector2 = zone.entities.get_position(player_entity_id)
	var tile_rect: Rect2 = Rect2(Vector2(tile), Vector2.ONE)
	if tile_rect.intersects(MovementSystem.body_rect(feet, _player.body)):
		return
	zone.set_object(tile, _registry.numeric_of("wall_wood"))
	# Walkability owns the walkable rule; setting the flag byte by hand
	# would also clobber FLAG_BLOCKS_LIGHT, which shares it.
	var _changed: int = Walkability.recompute_chunk(
		zone.get_chunk(Coords.world_to_chunk(tile)), _registry)


## The tile the player faces. The rule lives in MovementSystem, where it
## is tested; this only supplies the player's row.
func _player_facing_tile() -> Vector2i:
	return MovementSystem.facing_tile(
		zone.entities.get_position(player_entity_id),
		_player.body,
		zone.entities.get_facing(player_entity_id))
