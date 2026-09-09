extends GutTest

const BODY: Vector2 = Vector2(0.625, 0.5)
const BOUNDS: Rect2 = Rect2(Vector2.ZERO, Vector2(32.0, 32.0))
const TICK: float = 1.0 / 60.0

var _none: Array[Rect2i] = []


func test_body_is_anchored_at_the_feet() -> void:
	var r: Rect2 = MovementSystem.body_rect(Vector2(4.0, 3.0), BODY)
	assert_almost_eq(r.position.x, 3.6875, 0.0001)
	assert_almost_eq(r.position.y, 2.5, 0.0001)
	assert_almost_eq(r.end.y, 3.0, 0.0001, "pos.y is the bottom edge")


func test_unobstructed_movement_advances() -> void:
	var p: Vector2 = MovementSystem.move(
		Vector2(4.0, 4.0), Vector2(4.5, 0.0), TICK, BODY, _none, BOUNDS)
	assert_almost_eq(p.x, 4.075, 0.0001)
	assert_almost_eq(p.y, 4.0, 0.0001)


func test_a_wall_stops_movement_head_on() -> void:
	var solids: Array[Rect2i] = [Rect2i(6, 3, 1, 2)]
	var p: Vector2 = Vector2(4.0, 4.0)
	for i: int in range(200):
		p = MovementSystem.move(p, Vector2(4.5, 0.0), TICK, BODY, solids, BOUNDS)
	assert_almost_eq(p.x, 5.6875, 0.0001, "stops with the body edge against tile 6")


func test_walking_diagonally_into_a_wall_slides_along_it() -> void:
	# A vertical wall at x = 6. Moving north-east should keep the northward
	# component even though the eastward one is blocked.
	var solids: Array[Rect2i] = [Rect2i(6, 0, 1, 32)]
	var p: Vector2 = Vector2(5.5, 10.0)
	for i: int in range(60):
		p = MovementSystem.move(p, Vector2(4.5, -4.5), TICK, BODY, solids, BOUNDS)
	assert_almost_eq(p.x, 5.6875, 0.0001, "blocked eastward")
	assert_lt(p.y, 6.5, "but still moved north")


func test_an_inside_corner_stops_both_axes() -> void:
	var solids: Array[Rect2i] = [Rect2i(6, 0, 1, 32), Rect2i(0, 2, 32, 1)]
	var p: Vector2 = Vector2(5.5, 4.0)
	for i: int in range(120):
		p = MovementSystem.move(p, Vector2(4.5, -4.5), TICK, BODY, solids, BOUNDS)
	assert_almost_eq(p.x, 5.6875, 0.0001)
	assert_almost_eq(p.y, 3.5, 0.0001, "feet stop below the horizontal wall")


func test_bounds_clamp_west_and_north() -> void:
	var p: Vector2 = Vector2(1.0, 1.0)
	for i: int in range(200):
		p = MovementSystem.move(p, Vector2(-4.5, -4.5), TICK, BODY, _none, BOUNDS)
	assert_almost_eq(p.x, 0.3125, 0.0001)
	assert_almost_eq(p.y, 0.5, 0.0001, "the feet point is a body height below the top edge")


func test_bounds_clamp_east_and_south() -> void:
	var p: Vector2 = Vector2(30.0, 30.0)
	for i: int in range(200):
		p = MovementSystem.move(p, Vector2(4.5, 4.5), TICK, BODY, _none, BOUNDS)
	assert_almost_eq(p.x, 31.6875, 0.0001)
	assert_almost_eq(p.y, 32.0, 0.0001)


func test_a_frame_spike_does_not_tunnel_through_a_wall() -> void:
	# A half-second hitch steps 2.25 tiles. Landing INSIDE a wall is still
	# resolved correctly, so a smaller spike proves nothing -- this one
	# clears the far side of the wall entirely, which is real tunnelling.
	var solids: Array[Rect2i] = [Rect2i(6, 0, 1, 32)]
	var p: Vector2 = MovementSystem.move(
		Vector2(5.5, 10.0), Vector2(4.5, 0.0), 0.5, BODY, solids, BOUNDS)
	assert_almost_eq(p.x, 5.6875, 0.0001, "stopped by the wall, not teleported past it")


func test_substepping_does_not_change_an_unobstructed_move() -> void:
	var p: Vector2 = MovementSystem.move(
		Vector2(4.0, 4.0), Vector2(4.5, 0.0), 0.25, BODY, _none, BOUNDS)
	assert_almost_eq(p.x, 5.125, 0.0001, "4.0 + 4.5 * 0.25")


func test_facing_covers_all_eight_octants() -> void:
	assert_eq(MovementSystem.facing_from(Vector2(0, 1), 0), MovementSystem.FACING_S)
	assert_eq(MovementSystem.facing_from(Vector2(1, 1), 0), MovementSystem.FACING_SE)
	assert_eq(MovementSystem.facing_from(Vector2(1, 0), 0), MovementSystem.FACING_E)
	assert_eq(MovementSystem.facing_from(Vector2(1, -1), 0), MovementSystem.FACING_NE)
	assert_eq(MovementSystem.facing_from(Vector2(0, -1), 0), MovementSystem.FACING_N)
	assert_eq(MovementSystem.facing_from(Vector2(-1, -1), 0), MovementSystem.FACING_NW)
	assert_eq(MovementSystem.facing_from(Vector2(-1, 0), 0), MovementSystem.FACING_W)
	assert_eq(MovementSystem.facing_from(Vector2(-1, 1), 0), MovementSystem.FACING_SW)


func test_facing_is_held_when_velocity_is_zero() -> void:
	# Releasing every key must not snap the character back to a default,
	# or persisting `facing` in Phase 5 means nothing.
	assert_eq(
		MovementSystem.facing_from(Vector2.ZERO, MovementSystem.FACING_W),
		MovementSystem.FACING_W
	)
