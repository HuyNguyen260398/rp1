extends GutTest
## Sixty-four animals -- eight times the shipped population -- tick well
## inside one frame.
##
## Builds its own population rather than using data/zone/home/'s eight, so
## the number keeps meaning something when the zone grows. This is the
## same shape as test_zone_load_budget.gd.

const ANIMALS: int = 64
const TICKS: int = 60
## 4 ms of a 16 ms frame, for eight times the population we ship. Generous
## on purpose: a budget test that flakes on a loaded CI runner gets
## deleted, and a deleted test measures nothing.
const BUDGET_MS: int = 240

var _zone: Zone
var _registry: ContentRegistry
var _collision: CollisionBuilder
var _system: AnimalSystem


func before_each() -> void:
	_registry = ContentRegistry.new()
	_registry.register({"id": "grass", "category": "terrain",
		"display_name": "Grass", "sprite": "res://none.png", "walkable": true})
	_registry.register({"id": "rabbit", "category": "creature",
		"display_name": "Rabbit", "sprite": "res://none.png",
		"wander_radius": 6, "wander_speed": 1.5, "wander_interval": 3.0,
		"flees_player": true, "flee_radius": 5.0, "flee_speed": 4.0,
		"body_width": 0.5, "body_height": 0.375})

	_zone = Zone.new("budget", Vector2i(128, 128))
	var grass: int = _registry.numeric_of("grass")
	for y: int in range(128):
		for x: int in range(128):
			_zone.set_terrain(Vector2i(x, y), grass)
	Walkability.recompute_zone(_zone, _registry)
	_zone.clear_dirty()

	var rabbit: int = _registry.numeric_of("rabbit")
	for n: int in range(ANIMALS):
		var _id: int = _zone.entities.spawn(
			rabbit, Vector2(8.5 + float(n % 16) * 7.0, 8.5 + float(n / 16) * 7.0))

	_collision = CollisionBuilder.new()
	_system = AnimalSystem.new()
	_system.rng = RandomNumberGenerator.new()
	_system.rng.seed = 7


func test_sixty_four_animals_tick_inside_the_frame_budget() -> void:
	# One warm-up tick so the collision cache is built and the measurement
	# is of steady-state work rather than of first-touch chunk meshing.
	var _warm: int = _system.tick(_zone, _registry, _collision, Vector2(64.5, 64.5), 1.0 / 60.0)

	var start: int = Time.get_ticks_msec()
	for i: int in range(TICKS):
		var _moved: int = _system.tick(
			_zone, _registry, _collision, Vector2(64.5, 64.5), 1.0 / 60.0)
	var elapsed: int = Time.get_ticks_msec() - start

	assert_lt(elapsed, BUDGET_MS,
		"%d animals x %d ticks took %d ms; the budget is %d ms"
			% [ANIMALS, TICKS, elapsed, BUDGET_MS])
