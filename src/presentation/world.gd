class_name World
extends Node2D
## The running game: renderer, entities, player, camera, animals.
##
## Handed a Zone rather than loading one, so it does not know or care
## whether that zone was authored for a new world or decoded from a save.
## Everything here was main.gd's _ready() before Phase 5 gave main.gd a
## menu to show first.

var zone: Zone = null
var player_entity_id: int = EntityStore.INVALID_ID

var _registry: ContentRegistry = null
var _animals: AnimalSystem = null
var _renderer: ZoneRenderer = null
var _entity_renderer: EntityRenderer = null
var _player: Player = null
var _camera: FollowCamera = null
var _collision: CollisionBuilder = null


## Assembles the world. Returns the problems worth showing the player;
## the caller decides how to report them.
func build(registry: ContentRegistry, result: SessionOpenResult) -> PackedStringArray:
	var errors: PackedStringArray = []

	# Nested Y-sorted nodes flatten into this one's sort, so the object
	# layer's tiles and the entity sprites interleave by their y position.
	y_sort_enabled = true

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
