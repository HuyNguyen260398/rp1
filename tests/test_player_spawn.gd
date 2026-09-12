extends GutTest
## Coverage for Player.find_spawn_tile -- the ring-search guard against a
## silent Phase 4 failure (spec 3.6): a character spawning inside a tree
## with nothing logged. Static and takes only a Zone, so it is fully
## testable headless from src/presentation/ without instancing a node.


func _walkable_zone(size: Vector2i) -> Zone:
	var z: Zone = Zone.new("t", size)
	for y: int in range(size.y):
		for x: int in range(size.x):
			z.set_flags(Vector2i(x, y), Chunk.FLAG_WALKABLE)
	return z


func test_a_walkable_near_is_returned_unchanged() -> void:
	var z: Zone = _walkable_zone(Vector2i(16, 16))
	var near: Vector2i = Vector2i(8, 8)
	assert_eq(Player.find_spawn_tile(z, near), near)


func test_a_blocked_near_returns_a_walkable_tile_one_ring_out() -> void:
	var z: Zone = _walkable_zone(Vector2i(16, 16))
	var near: Vector2i = Vector2i(8, 8)
	z.set_flags(near, 0)
	var result: Vector2i = Player.find_spawn_tile(z, near)
	assert_true(z.is_walkable(result), "the result must actually be walkable")
	var chebyshev: int = maxi(absi(result.x - near.x), absi(result.y - near.y))
	assert_eq(chebyshev, 1, "the only blocked tile is near itself, so the nearest walkable tile is exactly one ring out")


func test_a_blocked_disc_returns_the_nearest_walkable_tile_outside_it() -> void:
	# Block every tile within Chebyshev distance 3 of near (a 7x7 square);
	# everything outside stays walkable. A ring loop that skips a ring, or
	# scans the interior, would either miss the true nearest tile or return
	# one still inside the disc.
	var size: Vector2i = Vector2i(32, 32)
	var near: Vector2i = Vector2i(16, 16)
	var disc_radius: int = 3
	var z: Zone = Zone.new("t", size)
	for y: int in range(size.y):
		for x: int in range(size.x):
			var t: Vector2i = Vector2i(x, y)
			var d: int = maxi(absi(t.x - near.x), absi(t.y - near.y))
			if d > disc_radius:
				z.set_flags(t, Chunk.FLAG_WALKABLE)

	var result: Vector2i = Player.find_spawn_tile(z, near)
	assert_true(z.is_walkable(result), "the result must actually be walkable")
	var chebyshev: int = maxi(absi(result.x - near.x), absi(result.y - near.y))
	assert_eq(chebyshev, disc_radius + 1, "the nearest walkable ring is exactly one past the blocked disc")


func test_an_out_of_bounds_near_still_resolves_in_bounds() -> void:
	var z: Zone = _walkable_zone(Vector2i(32, 32))
	var near: Vector2i = Vector2i(-5, -5)
	var result: Vector2i = Player.find_spawn_tile(z, near)
	assert_true(z.in_bounds(result), "the result must be inside the zone")
	assert_true(z.is_walkable(result), "the result must actually be walkable")


func test_no_walkable_tile_anywhere_gives_up_and_returns_near() -> void:
	# A fresh zone with no chunks installed and no flags ever set: every
	# tile is unwalkable by default (Chunk.FLAG_WALKABLE starts clear).
	var z: Zone = Zone.new("t", Vector2i(32, 32))
	var near: Vector2i = Vector2i(4, 4)
	assert_eq(Player.find_spawn_tile(z, near), near, "the give-up path returns near rather than hanging")
	# The give-up path is the "silent failure" spec 3.6 guards against, so
	# the guard is only real if it actually logs -- assert the push_error
	# fired rather than merely tolerating it.
	assert_push_error("no walkable spawn within 64 tiles")


func test_adopt_takes_over_an_existing_row_without_creating_one() -> void:
	# A loaded world already has a player row. Spawning here would leave
	# two of them, which is the state WorldMeta.player_entity_id exists to
	# make detectable.
	var registry: ContentRegistry = ContentRegistry.new()
	registry.register({"id": "player", "category": "creature",
		"display_name": "Player", "sprite": "res://none.png"})
	var z: Zone = _walkable_zone(Vector2i(64, 64))
	var existing: int = z.entities.spawn(
		registry.numeric_of("player"), Vector2(12.5, 34.5))
	var before: int = z.entities.count()

	var player: Player = Player.new()
	player.adopt(z, CollisionBuilder.new(), existing)

	assert_eq(z.entities.count(), before, "adopt spawned a second player row")
	assert_eq(player.entity_id, existing)
	assert_eq(z.entities.get_position(player.entity_id), Vector2(12.5, 34.5))
	player.free()
