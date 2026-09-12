class_name AnimalSystem
extends RefCounted
## Wander, flee and return, for every creature whose content gives it a
## wander radius.
##
## Deliberately dumb. This exists to validate the entity pipeline end to
## end -- authored spawn, simulation tick, collision, render -- not to be
## good at AI. Pathfinding, hunger and schedules are Stage 5.
##
## An instance rather than a set of statics, for the same reason
## CollisionBuilder is one: it caches per-animal state that would otherwise
## have to live in the caller, and the caller is presentation, which is the
## layer that should hold the least. MovementSystem's purity is the right
## shape for resolving one move and the wrong shape for remembering where a
## rabbit was going.
##
## Nothing here is persisted. EntityStore's blob column exists for exactly
## this kind of state and stays unused: a saved wander target would cost a
## format change, a migration and a fixture test for something the player
## cannot perceive.

const MODE_WANDER: int = 0
const MODE_FLEE: int = 1
const MODE_RETURN: int = 2

## Target draws before an animal gives up and dwells. A rabbit ringed by
## water must not spin through a thousand rejected draws every frame.
const MAX_TARGET_TRIES: int = 4

## How close counts as arrived, in tiles.
const ARRIVE_EPSILON: float = 0.2

# Fallbacks for optional fields. This is engine behaviour rather than
# content -- the same treatment ZoneLoader gives biome and generation_seed
# -- and it keeps a half-authored creature moving rather than motionless
# with no error anywhere.
const DEFAULT_WANDER_SPEED: float = 1.5
const DEFAULT_WANDER_INTERVAL: float = 3.0
const DEFAULT_BODY: Vector2 = Vector2(0.5, 0.375)
const DEFAULT_FLEE_RADIUS: float = 5.0
const DEFAULT_FLEE_SPEED: float = 4.0

## Injected so every test is exactly reproducible. The caller seeds it;
## main.gd uses the zone's generation_seed, so one world always behaves the
## same way.
var rng: RandomNumberGenerator = RandomNumberGenerator.new()

## entity id -> {home: Vector2, target: Vector2, timer: float, mode: int}
var _state: Dictionary = {}


func tracked_ids() -> PackedInt32Array:
	var out: PackedInt32Array = []
	for id: int in _state:
		out.append(id)
	out.sort()
	return out


func mode_of(id: int) -> int:
	if not _state.has(id):
		return -1
	return int((_state[id] as Dictionary)["mode"])


## Advances every animal by `delta`. Returns the number that moved.
func tick(
	zone: Zone,
	registry: ContentRegistry,
	collision: CollisionBuilder,
	player_pos: Vector2,
	delta: float
) -> int:
	var moved: int = 0
	var live: Dictionary = {}

	for id: int in zone.entities.ids():
		var def: Dictionary = registry.def_of(zone.entities.get_type_id(id))
		# An animal is any creature with somewhere to wander. There is no
		# check against "rabbit" here and there must never be one: a second
		# animal is one JSON file plus one PNG.
		if float(def.get("wander_radius", 0)) <= 0.0:
			continue
		live[id] = true

		var pos: Vector2 = zone.entities.get_position(id)
		if not _state.has(id):
			# Home is captured lazily, wherever the animal is first seen.
			# Animals restored by a Phase 5 load are therefore anchored
			# where the save put them, with no load hook and no
			# registration call.
			_state[id] = {
				"home": pos, "target": pos, "timer": 0.0, "mode": MODE_WANDER,
				"interval": float(def.get("wander_interval", DEFAULT_WANDER_INTERVAL)),
			}

		var s: Dictionary = _state[id]
		var radius: float = float(def.get("wander_radius", 0))
		var speed: float = float(def.get("wander_speed", DEFAULT_WANDER_SPEED))
		var flees: bool = bool(def.get("flees_player", false))
		var flee_radius: float = float(def.get("flee_radius", DEFAULT_FLEE_RADIUS))
		var to_player: float = pos.distance_to(player_pos)

		# An animal whose content does not say it flees never consults
		# flee_radius at all: to it, the player is scenery.
		if flees and to_player < flee_radius:
			s["mode"] = MODE_FLEE

		var velocity: Vector2 = Vector2.ZERO
		if int(s["mode"]) == MODE_FLEE:
			velocity = _flee_velocity(
				pos, player_pos, float(def.get("flee_speed", DEFAULT_FLEE_SPEED)))
		else:
			velocity = _wander_velocity(s, pos, radius, speed, zone, delta)

		if velocity.is_zero_approx():
			continue

		var body: Vector2 = Vector2(
			float(def.get("body_width", DEFAULT_BODY.x)),
			float(def.get("body_height", DEFAULT_BODY.y))
		)
		# The same call Player._physics_process makes, with the same slack:
		# the area only selects which chunks are consulted, and solids_near
		# returns whole chunks regardless.
		var area: Rect2 = Rect2(pos - Vector2(2.0, 2.0), Vector2(4.0, 4.0))
		var solids: Array[Rect2i] = collision.solids_near(zone, area)
		var bounds: Rect2 = Rect2(Vector2.ZERO, Vector2(zone.size_tiles))
		var next: Vector2 = MovementSystem.move(
			pos, velocity, delta, body, solids, bounds)

		if next.distance_to(pos) <= 0.0:
			continue
		zone.entities.set_position(id, next)
		zone.entities.set_facing(
			id, MovementSystem.facing_from(velocity, zone.entities.get_facing(id)))
		moved += 1

	# .keys() returns a copy, so erasing inside this loop is safe.
	for id: int in _state.keys():
		if not live.has(id):
			_state.erase(id)

	return moved


## Dwell, then walk to a target drawn near home. Returns a desired velocity,
## or zero while standing still.
func _wander_velocity(
	s: Dictionary, pos: Vector2, radius: float, speed: float,
	zone: Zone, delta: float
) -> Vector2:
	if float(s["timer"]) > 0.0:
		s["timer"] = float(s["timer"]) - delta
		if float(s["timer"]) <= 0.0:
			_pick_target(s, pos, radius, zone)
		return Vector2.ZERO

	var target: Vector2 = s["target"]
	if pos.distance_to(target) <= ARRIVE_EPSILON:
		# Arrived. Stand still for a jittered interval so animals authored
		# from one definition do not share a heartbeat.
		s["timer"] = _interval_for(s)
		return Vector2.ZERO
	return (target - pos).normalized() * speed


## Draws a point uniformly from the disc of `radius` around home.
##
## sqrt() on the radius is what makes it uniform: without it, points bunch
## toward the centre and an animal barely leaves its anchor.
func _pick_target(s: Dictionary, pos: Vector2, radius: float, zone: Zone) -> void:
	var home: Vector2 = s["home"]
	for _try: int in range(MAX_TARGET_TRIES):
		var angle: float = rng.randf() * TAU
		var dist: float = sqrt(rng.randf()) * radius
		var candidate: Vector2 = home + Vector2(cos(angle), sin(angle)) * dist
		var tile: Vector2i = Vector2i(floori(candidate.x), floori(candidate.y))
		if zone.in_bounds(tile) and zone.is_walkable(tile):
			s["target"] = candidate
			return
	# Every draw was blocked. Stay put; the next dwell will try again.
	s["target"] = pos


## The dwell interval, jittered +/-50%.
func _interval_for(s: Dictionary) -> float:
	var base: float = float(s.get("interval", DEFAULT_WANDER_INTERVAL))
	return base * rng.randf_range(0.5, 1.5)


## Straight away from the player, at flee_speed. Ignores the wander radius:
## a hard fence pins a cornered animal against an invisible wall, which
## reads as broken within thirty seconds of play.
func _flee_velocity(pos: Vector2, player_pos: Vector2, speed: float) -> Vector2:
	var away: Vector2 = pos - player_pos
	if away.is_zero_approx():
		# Exactly co-located, which only happens in a test. Any direction
		# will do; normalized() on a zero vector returns zero and would
		# leave the animal standing inside the player.
		away = Vector2.RIGHT
	return away.normalized() * speed
