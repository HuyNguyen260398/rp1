extends Node2D
## Entry point: load the authored zone and draw it.
##
## The world is data. Everything drawn here comes from data/zone/home/ and
## data/*.json; this file contains no content and no layout.

## Exported rather than hardcoded: a res:// path in logic is the thing the
## content rules exist to prevent. Phase 5's New World flow sets this.
@export var zone_dir: String = "res://data/zone/home"

var _registry: ContentRegistry = null
var _animals: AnimalSystem = null
var _renderer: ZoneRenderer = null
var _entity_renderer: EntityRenderer = null
var _player: Player = null
var _camera: FollowCamera = null
var _collision: CollisionBuilder = null


func _ready() -> void:
	# Nested Y-sorted nodes flatten into this one's sort, so the object
	# layer's tiles and the entity sprites interleave by their y position.
	y_sort_enabled = true

	var registry: ContentRegistry = ContentRegistry.new()
	_registry = registry
	var errs: PackedStringArray = registry.load_from_dir("res://data")
	if not errs.is_empty():
		push_error("content failed to load: %s" % ", ".join(errs))
	print("RP1 booted with %d content definitions" % registry.all_string_ids().size())

	_renderer = ZoneRenderer.new()
	_renderer.name = "ZoneRenderer"
	add_child(_renderer)

	var art_errs: PackedStringArray = _renderer.setup(registry)
	for e: String in art_errs:
		push_error("tileset: %s" % e)

	var load_result: ZoneLoadResult = ZoneLoader.load_zone(zone_dir, registry)
	for e: String in load_result.errors:
		push_error("zone: %s" % e)
	if load_result.zone == null:
		# There is no sensible fallback world. CI gate 7 exists so this
		# state never reaches a build; if it happens anyway, say so loudly
		# rather than rendering an empty screen with no explanation.
		push_error("zone failed to load from %s; nothing to render" % zone_dir)
		return
	var zone: Zone = load_result.zone
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
	var spawn_near: Vector2i = Vector2i(
		floori(load_result.player_spawn.x), floori(load_result.player_spawn.y))
	var pid: int = _player.spawn(zone, registry, _collision, spawn_near)
	print("RP1 player spawned at %s" % zone.entities.get_position(pid))

	_camera = FollowCamera.new()
	_camera.name = "FollowCamera"
	add_child(_camera)
	_camera.setup(zone)
	_camera.target_id = pid
	_camera.make_current()


## Animals move in the physics step, alongside the player, so both see the
## same fixed delta and the same collision geometry.
func _physics_process(delta: float) -> void:
	if _animals == null or _renderer == null or _renderer.zone == null:
		return
	if _player == null or not _renderer.zone.entities.has(_player.entity_id):
		return
	var zone: Zone = _renderer.zone
	var _moved: int = _animals.tick(
		zone,
		_registry,
		_collision,
		zone.entities.get_position(_player.entity_id),
		delta
	)
