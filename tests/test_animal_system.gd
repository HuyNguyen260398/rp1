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


## The tile under an entity's feet, clamped into the zone.
##
## MovementSystem clamps a body to the zone rect, so a position resting
## exactly on the bottom or right edge floors to an index one past the last
## tile. That is legal -- the player does it too, and Phase 3b verified it --
## so clamping keeps these assertions about walkability rather than about
## that boundary. The position itself is asserted to be in the rect
## separately.
func _tile_under(p: Vector2) -> Vector2i:
	return Vector2i(
		clampi(floori(p.x), 0, _zone.size_tiles.x - 1),
		clampi(floori(p.y), 0, _zone.size_tiles.y - 1)
	)


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


## A 32x32 zone whose middle column is water, so there is real geometry to
## be blocked by.
func _make_walled_zone() -> Zone:
	var zone: Zone = Zone.new("walled", Vector2i(32, 32))
	var grass: int = _registry.numeric_of("grass")
	var water: int = _registry.numeric_of("water")
	for y: int in range(32):
		for x: int in range(32):
			zone.set_terrain(Vector2i(x, y), water if x == 16 else grass)
	Walkability.recompute_zone(zone, _registry)
	zone.clear_dirty()
	return zone


func test_an_animal_moves() -> void:
	var id: int = _spawn("rabbit", Vector2(16.5, 16.5))
	_run(300)
	assert_ne(_zone.entities.get_position(id), Vector2(16.5, 16.5),
		"five seconds of wandering must go somewhere")


func test_an_animal_stays_within_its_wander_radius() -> void:
	var home: Vector2 = Vector2(16.5, 16.5)
	var id: int = _spawn("rabbit", home)
	# The radius is 6 tiles. A target may be drawn AT the radius, and the
	# animal stops within ARRIVE_EPSILON of it and may overshoot by one
	# tick of travel, so the true bound is nearer 6.03 than 6.0.
	for i: int in range(600):
		_system.tick(_zone, _registry, _collision, Vector2(-100.0, -100.0), 1.0 / 60.0)
		assert_lt(_zone.entities.get_position(id).distance_to(home), 6.5,
			"tick %d left the wander radius with no player anywhere near" % i)


func test_wandering_never_ends_a_tick_inside_a_solid() -> void:
	_zone = _make_walled_zone()
	var id: int = _spawn("rabbit", Vector2(10.5, 16.5))
	for i: int in range(600):
		_system.tick(_zone, _registry, _collision, Vector2(-100.0, -100.0), 1.0 / 60.0)
		var p: Vector2 = _zone.entities.get_position(id)
		assert_true(Rect2(Vector2.ZERO, Vector2(_zone.size_tiles)).has_point(p),
			"tick %d left the zone at %s" % [i, p])
		var tile: Vector2i = _tile_under(p)
		assert_true(_zone.is_walkable(tile),
			"tick %d put the rabbit on %s, which is not walkable" % [i, tile])


func test_an_enclosed_animal_dwells_rather_than_spinning() -> void:
	# A single walkable tile ringed by water: every target draw is rejected.
	var zone: Zone = Zone.new("box", Vector2i(32, 32))
	var grass: int = _registry.numeric_of("grass")
	var water: int = _registry.numeric_of("water")
	for y: int in range(32):
		for x: int in range(32):
			zone.set_terrain(Vector2i(x, y), water)
	zone.set_terrain(Vector2i(16, 16), grass)
	Walkability.recompute_zone(zone, _registry)
	zone.clear_dirty()
	_zone = zone

	var id: int = _spawn("rabbit", Vector2(16.5, 16.5))
	_run(300)

	var p: Vector2 = _zone.entities.get_position(id)
	assert_almost_eq(p.x, 16.5, 0.6, "it has nowhere to go, so it stays on its tile")
	assert_almost_eq(p.y, 16.5, 0.6, "it has nowhere to go, so it stays on its tile")


func test_the_same_seed_reproduces_the_same_walk() -> void:
	var id_a: int = _spawn("rabbit", Vector2(16.5, 16.5))
	_run(120)
	var first: Vector2 = _zone.entities.get_position(id_a)

	before_each()
	var id_b: int = _spawn("rabbit", Vector2(16.5, 16.5))
	_run(120)

	assert_eq(_zone.entities.get_position(id_b), first,
		"same seed, same walk -- or no behaviour test here means anything")


func test_a_different_seed_walks_differently() -> void:
	var id_a: int = _spawn("rabbit", Vector2(16.5, 16.5))
	_run(120)
	var first: Vector2 = _zone.entities.get_position(id_a)

	before_each()
	_system.rng.seed = SEED + 1
	var id_b: int = _spawn("rabbit", Vector2(16.5, 16.5))
	_run(120)

	assert_ne(_zone.entities.get_position(id_b), first)


func test_identical_animals_do_not_move_in_lockstep() -> void:
	# The dwell interval is jittered, so eight rabbits authored from one
	# definition must not share a heartbeat.
	var a: int = _spawn("rabbit", Vector2(10.5, 10.5))
	var b: int = _spawn("rabbit", Vector2(10.5, 10.5))
	_run(240)
	assert_ne(_zone.entities.get_position(a), _zone.entities.get_position(b))


func test_facing_follows_movement() -> void:
	var id: int = _spawn("rabbit", Vector2(16.5, 16.5))
	_zone.entities.set_facing(id, MovementSystem.FACING_N)
	_run(300)
	# Not asserting a specific octant -- that would be asserting the RNG.
	# Asserting only that facing is maintained, as the player's is.
	assert_between(_zone.entities.get_facing(id), 0, 7)


func test_tick_reports_how_many_moved() -> void:
	var _a: int = _spawn("rabbit", Vector2(10.5, 10.5))
	var _b: int = _spawn("rabbit", Vector2(20.5, 20.5))
	var _p: int = _spawn("player", Vector2(16.5, 16.5))
	# Run until at least one has stopped dwelling and started walking.
	var seen: int = 0
	for i: int in range(600):
		seen = maxi(seen, _system.tick(
			_zone, _registry, _collision, Vector2(-100.0, -100.0), 1.0 / 60.0))
	assert_gt(seen, 0, "something moved")
	assert_lt(seen, 3, "the player is not one of them")


func test_a_nearby_player_triggers_flee() -> void:
	var id: int = _spawn("rabbit", Vector2(16.5, 16.5))
	_run(1, Vector2(18.0, 16.5))
	assert_eq(_system.mode_of(id), AnimalSystem.MODE_FLEE)


func test_a_distant_player_does_not() -> void:
	var id: int = _spawn("rabbit", Vector2(16.5, 16.5))
	_run(1, Vector2(16.5 + 20.0, 16.5))
	assert_eq(_system.mode_of(id), AnimalSystem.MODE_WANDER)


func test_fleeing_increases_the_distance_to_the_player() -> void:
	var player: Vector2 = Vector2(14.0, 16.5)
	var id: int = _spawn("rabbit", Vector2(16.5, 16.5))
	var before: float = _zone.entities.get_position(id).distance_to(player)

	_run(30, player)

	assert_gt(_zone.entities.get_position(id).distance_to(player), before,
		"half a second of fleeing must open the gap")


func test_an_animal_that_does_not_flee_ignores_the_player() -> void:
	var id: int = _spawn("cow", Vector2(16.5, 16.5))
	_run(60, Vector2(16.6, 16.5))
	assert_eq(_system.mode_of(id), AnimalSystem.MODE_WANDER,
		"flees_player is false, so the player is scenery -- no code knows what a cow is")


func test_fleeing_may_leave_the_wander_radius() -> void:
	# A player parked just inside the flee radius, on the home side, pushes
	# the rabbit out past its 6-tile fence. A hard fence here would pin it
	# against an invisible wall, which reads as broken.
	var home: Vector2 = Vector2(16.5, 16.5)
	var id: int = _spawn("rabbit", home)
	var escaped: bool = false
	for i: int in range(600):
		var p: Vector2 = _zone.entities.get_position(id)
		# Chase: stand one tile behind the rabbit, on the home side, so it
		# is driven outward rather than in a circle.
		var chase: Vector2 = home
		if p.distance_to(home) > 0.1:
			chase = p + (home - p).normalized()
		_system.tick(_zone, _registry, _collision, chase, 1.0 / 60.0)
		if _zone.entities.get_position(id).distance_to(home) > 6.5:
			escaped = true
			break
	assert_true(escaped, "flee must beat the wander radius")


func test_fleeing_never_ends_a_tick_inside_a_solid() -> void:
	_zone = _make_walled_zone()
	var id: int = _spawn("rabbit", Vector2(14.5, 16.5))
	# Push it straight at the water column.
	for i: int in range(300):
		_system.tick(_zone, _registry, _collision, Vector2(12.0, 16.5), 1.0 / 60.0)
		var p: Vector2 = _zone.entities.get_position(id)
		var tile: Vector2i = _tile_under(p)
		assert_true(_zone.is_walkable(tile),
			"tick %d drove the fleeing rabbit onto %s" % [i, tile])


func test_a_frightened_animal_walks_home() -> void:
	var home: Vector2 = Vector2(16.5, 16.5)
	var id: int = _spawn("rabbit", home)

	# Frighten it far out of its radius.
	for i: int in range(600):
		var p: Vector2 = _zone.entities.get_position(id)
		var chase: Vector2 = home
		if p.distance_to(home) > 0.1:
			chase = p + (home - p).normalized()
		_system.tick(_zone, _registry, _collision, chase, 1.0 / 60.0)
		if _zone.entities.get_position(id).distance_to(home) > 7.0:
			break
	assert_gt(_zone.entities.get_position(id).distance_to(home), 7.0,
		"precondition: it was driven outside its radius")

	# Withdraw and let it settle.
	_run(1, Vector2(-100.0, -100.0))
	assert_eq(_system.mode_of(id), AnimalSystem.MODE_RETURN)

	_run(900, Vector2(-100.0, -100.0))
	assert_lt(_zone.entities.get_position(id).distance_to(home), 6.5,
		"fifteen seconds is ample to walk six tiles home")
	assert_eq(_system.mode_of(id), AnimalSystem.MODE_WANDER,
		"and it goes back to wandering once inside")


func test_a_frightened_animal_still_inside_its_radius_just_resumes_wandering() -> void:
	var id: int = _spawn("rabbit", Vector2(16.5, 16.5))
	_run(1, Vector2(18.0, 16.5))
	assert_eq(_system.mode_of(id), AnimalSystem.MODE_FLEE, "precondition")

	_run(1, Vector2(-100.0, -100.0))
	assert_eq(_system.mode_of(id), AnimalSystem.MODE_WANDER,
		"it never left home, so there is nothing to return to")


func test_the_mode_does_not_flicker_at_the_flee_boundary() -> void:
	# A player parked exactly at flee_radius. With a single threshold the
	# animal would flip mode every tick and vibrate in place; the calm
	# distance is 1.5x the flee radius precisely to stop that.
	var id: int = _spawn("rabbit", Vector2(16.5, 16.5))
	var player: Vector2 = Vector2(16.5 + 5.0, 16.5)

	var flips: int = 0
	var last: int = -1
	for i: int in range(120):
		# Re-park the player at exactly flee_radius from wherever it is now.
		var p: Vector2 = _zone.entities.get_position(id)
		player = p + Vector2(5.0, 0.0)
		_system.tick(_zone, _registry, _collision, player, 1.0 / 60.0)
		var mode: int = _system.mode_of(id)
		if last != -1 and mode != last:
			flips += 1
		last = mode
	assert_lt(flips, 3, "%d mode changes in two seconds is a vibrating rabbit" % flips)


func test_returning_never_ends_a_tick_inside_a_solid() -> void:
	_zone = _make_walled_zone()
	var home: Vector2 = Vector2(10.5, 16.5)
	var id: int = _spawn("rabbit", home)
	# Drive it west, away from home, then release it and let it walk back.
	for i: int in range(240):
		_system.tick(_zone, _registry, _collision,
			_zone.entities.get_position(id) + Vector2(1.0, 0.0), 1.0 / 60.0)
	for i: int in range(600):
		_system.tick(_zone, _registry, _collision, Vector2(-100.0, -100.0), 1.0 / 60.0)
		var p: Vector2 = _zone.entities.get_position(id)
		var tile: Vector2i = _tile_under(p)
		assert_true(_zone.is_walkable(tile),
			"tick %d put the returning rabbit on %s" % [i, tile])
