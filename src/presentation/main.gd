extends Node2D
## Entry point. Task 16 turns this into the menu router; for now it opens a
## new world at boot, exactly as it did before World was extracted.

## Exported rather than hardcoded: a res:// path in logic is the thing the
## content rules exist to prevent.
@export var zone_dir: String = "res://data/zone/home"

var _registry: ContentRegistry = null
var _session: GameSession = null
var _world: World = null


func _ready() -> void:
	_registry = ContentRegistry.new()
	for e: String in _registry.load_from_dir("res://data"):
		push_error("content failed to load: %s" % e)
	print("RP1 booted with %d content definitions" % _registry.all_string_ids().size())

	_session = GameSession.new()
	var result: SessionOpenResult = _session.open_new(zone_dir, _registry)
	if not result.ok:
		# There is no sensible fallback world. CI gate 7 exists so this
		# state never reaches a build; if it happens anyway, say so loudly
		# rather than rendering an empty screen with no explanation.
		push_error(result.error)
		return
	for w: String in result.warnings:
		push_error("zone: %s" % w)

	_world = World.new()
	_world.name = "World"
	add_child(_world)
	for e: String in _world.build(_registry, result):
		push_error(e)
	_session.adopt_player(_world.player_entity_id)


func _physics_process(delta: float) -> void:
	if _world != null:
		_world.tick_animals(delta)
