class_name AudioDirector
extends RefCounted
## Every audio rule in the game. Node-free, so all of it is testable
## headless -- which matters more here than elsewhere, because audio
## faults are obvious in play and invisible in review.
##
## Distance, not time, drives footsteps. See the plan's Task 3 for why.

## Tiles between footsteps. At the player's 4.5 tiles/second this is a
## step every 0.36 s, about 2.8 a second. Retune against that sum.
const STEP_DISTANCE: float = 1.6

## Injected so tests are deterministic, exactly as AnimalSystem does it.
var rng: RandomNumberGenerator = RandomNumberGenerator.new()

var _registry: ContentRegistry = null
var _step_accumulator: float = 0.0


## Resolves sound ids against content. Called once per world.
func configure(p_registry: ContentRegistry) -> void:
	_registry = p_registry
	_step_accumulator = 0.0


## The whole per-frame rule. Returns the cues to play, usually empty and
## never more than one footstep: a frame spike must not machine-gun.
func tick(distance_moved: float, terrain_id: int) -> Array[AudioCue]:
	var cues: Array[AudioCue] = []
	if _registry == null:
		return cues

	_step_accumulator += distance_moved
	if _step_accumulator < STEP_DISTANCE:
		return cues
	# Subtract rather than zero, so the remainder carries and the cadence
	# does not drift with the frame rate.
	_step_accumulator -= STEP_DISTANCE
	# A frame spike, or a debugger pause, can leave more than a whole step
	# banked. Drop that backlog: one long frame is one step, and the steps
	# it "owes" are not played later into an empty room.
	if _step_accumulator > STEP_DISTANCE:
		_step_accumulator = 0.0

	var sound_id: String = str(_registry.def_of(terrain_id).get("footstep", ""))
	if sound_id == "":
		return cues

	var cue: AudioCue = _cue_for(sound_id)
	if cue != null:
		cues.append(cue)
	return cues


## Null when the sound is not in this build: a footstep naming content
## that was removed is silence, not a crash.
func _cue_for(sound_id: String) -> AudioCue:
	var def: Dictionary = _registry.def_of(_registry.numeric_of(sound_id))
	var streams: Array = def.get("streams", [])
	if streams.is_empty():
		return null
	return AudioCue.make(sound_id, 0, float(def.get("gain_db", 0.0)))
