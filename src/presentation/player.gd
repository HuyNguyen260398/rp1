class_name Player
extends Node
## Input, spawning, and holding the zone's collision cache. Owns no position
## of its own.
##
## The player's position lives in an EntityStore row, so the renderer, the
## camera and Phase 5's save all read one source of truth -- and persisting
## the player needs no code beyond the entity codec that already exists.
##
## This node reads input, asks MovementSystem to resolve the move, and
## writes the result back. It does not draw anything: EntityRenderer draws
## the player through the same pool as every other entity.
##
## The CollisionBuilder is injected by spawn() rather than constructed here:
## it is per-zone state (Phase 3b design §3.4), not player state, and
## Phase 4's invalidate() hook needs a caller outside Player able to reach
## the same cache the player consults.

## How far the spawn search will look before giving up.
const SPAWN_SEARCH_RADIUS: int = 64

## Tiles per second. The figure the substepping bound in MovementSystem is
## calculated against.
@export var speed: float = 4.5

## Collision box in tiles, anchored bottom-centre on the position. The
## sprite is 32x64; a body that size could not walk between two trees the
## character visually fits between.
@export var body: Vector2 = Vector2(0.625, 0.5)

var zone: Zone = null
var entity_id: int = EntityStore.INVALID_ID

var _collision: CollisionBuilder = null


func spawn(p_zone: Zone, registry: ContentRegistry, collision: CollisionBuilder, near: Vector2i) -> int:
	zone = p_zone
	_collision = collision
	var tile: Vector2i = find_spawn_tile(p_zone, near)
	# Centre of the tile: +0.5 on both axes.
	entity_id = p_zone.entities.spawn(
		registry.numeric_of("player"), Vector2(tile) + Vector2(0.5, 0.5)
	)
	return entity_id


## Takes over the player row a save restored. The counterpart to spawn():
## a loaded world already has a player, and spawning a second one would
## leave two player rows in the store.
func adopt(p_zone: Zone, collision: CollisionBuilder, id: int) -> void:
	zone = p_zone
	_collision = collision
	entity_id = id


## Rings outward from `near` until a walkable tile turns up.
##
## A hardcoded spawn is what Phase 4's authored zone breaks silently: the
## character appears inside a tree, cannot move, and nothing logs an error.
static func find_spawn_tile(p_zone: Zone, near: Vector2i) -> Vector2i:
	if p_zone.in_bounds(near) and p_zone.is_walkable(near):
		return near
	for r: int in range(1, SPAWN_SEARCH_RADIUS + 1):
		for dy: int in range(-r, r + 1):
			for dx: int in range(-r, r + 1):
				# Only the ring's edge; the interior was covered by a
				# smaller radius already.
				if absi(dx) != r and absi(dy) != r:
					continue
				var t: Vector2i = near + Vector2i(dx, dy)
				if p_zone.in_bounds(t) and p_zone.is_walkable(t):
					return t
	push_error("player: no walkable spawn within %d tiles of %s" % [SPAWN_SEARCH_RADIUS, near])
	return near


func _physics_process(delta: float) -> void:
	if zone == null or not zone.entities.has(entity_id):
		return

	var dir: Vector2 = Vector2(
		Input.get_axis("move_left", "move_right"),
		Input.get_axis("move_up", "move_down")
	)
	# Normalize only past unit length, so a diagonal carries no speed bonus
	# while analogue input keeps its magnitude.
	if dir.length_squared() > 1.0:
		dir = dir.normalized()
	var velocity: Vector2 = dir * speed

	var pos: Vector2 = zone.entities.get_position(entity_id)
	# This area only selects which chunks solids_near() consults -- it
	# gathers whole chunks, not rects clipped to the area -- so being
	# generous with the slack costs nothing; it cannot pull in more than
	# the chunk-granular result would anyway.
	var area: Rect2 = Rect2(pos - Vector2(2.0, 2.0), Vector2(4.0, 4.0))
	var solids: Array[Rect2i] = _collision.solids_near(zone, area)
	var bounds: Rect2 = Rect2(Vector2.ZERO, Vector2(zone.size_tiles))

	var moved: Vector2 = MovementSystem.move(pos, velocity, delta, body, solids, bounds)
	zone.entities.set_position(entity_id, moved)
	zone.entities.set_facing(
		entity_id, MovementSystem.facing_from(velocity, zone.entities.get_facing(entity_id))
	)
