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
			}

	# .keys() returns a copy, so erasing inside this loop is safe.
	for id: int in _state.keys():
		if not live.has(id):
			_state.erase(id)

	return moved
