extends GutTest
## AnimalSystem drives every creature whose content gives it a wander radius.
##
## Every test builds its own zone and its own registry, so none of them
## depend on what data/zone/home/ happens to contain today, and the seed is
## always explicit -- a behaviour test that cannot be reproduced exactly is
## a behaviour test that will be deleted the first time it flakes.

const SEED: int = 424242

var _zone: Zone
var _registry: ContentRegistry
var _collision: CollisionBuilder
var _system: AnimalSystem


## A 32x32 field of walkable grass: one chunk, no obstacles.
func _make_zone() -> Zone:
	var zone: Zone = Zone.new("fixture", Vector2i(32, 32))
	var grass: int = _registry.numeric_of("grass")
	for y: int in range(32):
		for x: int in range(32):
			zone.set_terrain(Vector2i(x, y), grass)
	Walkability.recompute_zone(zone, _registry)
	zone.clear_dirty()
	return zone


func before_each() -> void:
	_registry = ContentRegistry.new()
	_registry.register({"id": "grass", "category": "terrain",
		"display_name": "Grass", "sprite": "res://none.png", "walkable": true})
	_registry.register({"id": "water", "category": "terrain",
		"display_name": "Water", "sprite": "res://none.png", "walkable": false})
	_registry.register({"id": "rabbit", "category": "creature",
		"display_name": "Rabbit", "sprite": "res://none.png",
		"wander_radius": 6, "wander_speed": 1.5, "wander_interval": 3.0,
		"flees_player": true, "flee_radius": 5.0, "flee_speed": 4.0,
		"body_width": 0.5, "body_height": 0.375})
	_registry.register({"id": "player", "category": "creature",
		"display_name": "Player", "sprite": "res://none.png"})
	_registry.register({"id": "cow", "category": "creature",
		"display_name": "Cow", "sprite": "res://none.png",
		"wander_radius": 4, "wander_speed": 1.0, "wander_interval": 4.0,
		"flees_player": false})

	_zone = _make_zone()
	_collision = CollisionBuilder.new()
	_system = AnimalSystem.new()
	_system.rng = RandomNumberGenerator.new()
	_system.rng.seed = SEED


func _spawn(string_id: String, at: Vector2) -> int:
	return _zone.entities.spawn(_registry.numeric_of(string_id), at)


## Advances the simulation `ticks` times at a fixed 60 Hz step, with the
## player parked far away unless told otherwise.
func _run(ticks: int, player_pos: Vector2 = Vector2(-100.0, -100.0)) -> void:
	for i: int in range(ticks):
		_system.tick(_zone, _registry, _collision, player_pos, 1.0 / 60.0)


func test_a_creature_with_a_wander_radius_is_tracked() -> void:
	var id: int = _spawn("rabbit", Vector2(16.5, 16.5))
	_run(1)
	assert_eq(_system.tracked_ids(), PackedInt32Array([id]))


func test_a_creature_without_a_wander_radius_is_never_tracked() -> void:
	var _id: int = _spawn("player", Vector2(16.5, 16.5))
	_run(10)
	assert_eq(_system.tracked_ids(), PackedInt32Array(),
		"the player is inert because its content says so, not because of a type check")


func test_the_player_is_never_moved() -> void:
	var id: int = _spawn("player", Vector2(16.5, 16.5))
	_run(60)
	assert_eq(_zone.entities.get_position(id), Vector2(16.5, 16.5))


func test_an_untracked_id_has_no_mode() -> void:
	assert_eq(_system.mode_of(9999), -1)


func test_an_animal_starts_in_wander() -> void:
	var id: int = _spawn("rabbit", Vector2(16.5, 16.5))
	_run(1)
	assert_eq(_system.mode_of(id), AnimalSystem.MODE_WANDER)


func test_a_despawned_animal_is_pruned() -> void:
	var id: int = _spawn("rabbit", Vector2(16.5, 16.5))
	_run(1)
	assert_eq(_system.tracked_ids().size(), 1, "precondition: it was tracked")

	var _ok: bool = _zone.entities.despawn(id)
	_run(1)

	assert_eq(_system.tracked_ids(), PackedInt32Array(),
		"state keyed by a dead id would leak for the life of the process")


func test_an_animal_spawned_later_is_picked_up() -> void:
	_run(5)
	var id: int = _spawn("rabbit", Vector2(10.5, 10.5))
	_run(1)
	assert_eq(_system.tracked_ids(), PackedInt32Array([id]),
		"a Phase 5 load spawns animals after boot and must need no registration call")
