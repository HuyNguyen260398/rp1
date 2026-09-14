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

## sound_id -> the variation index played last, so the next one differs.
var _last_variation: Dictionary = {}

var _zone_id: String = ""
var _bed_sound_id: String = ""
var _bed_cue: AudioCue = null
var _master_volume: float = 0.8
var _muted: bool = false


## Resolves sound ids against content. Called once per world.
func configure(p_registry: ContentRegistry) -> void:
	_registry = p_registry
	_step_accumulator = 0.0


## The whole per-frame rule. Returns the cues to play, usually empty and
## never more than one footstep: a frame spike must not machine-gun.
func tick(distance_moved: float, terrain_id: int) -> Array[AudioCue]:
	var cues: Array[AudioCue] = []
	if _registry == null or _muted:
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

	var variation: int = _pick_variation(sound_id, streams.size())
	var gain_db: float = float(def.get("gain_db", 0.0)) + linear_to_db(_master_volume)
	return AudioCue.make(sound_id, variation, gain_db)


## Uniform over every variation except the one just played. Picking from a
## range one smaller and then stepping over the previous index is uniform
## and terminates; rejecting and retrying is neither.
func _pick_variation(sound_id: String, count: int) -> int:
	if count <= 1:
		return 0
	var previous: int = int(_last_variation.get(sound_id, -1))
	var index: int = rng.randi_range(0, count - 2)
	if previous >= 0 and index >= previous:
		index += 1
	_last_variation[sound_id] = index
	return index


## Sets the bed for the zone being entered. "" is a valid ambient id and
## means silence, which is how a zone opts out rather than by omission.
## Idempotent: re-entering the zone already playing changes nothing.
func enter_zone(zone_id: String, ambient_sound_id: String) -> void:
	if zone_id == _zone_id and ambient_sound_id == _bed_sound_id:
		return
	_zone_id = zone_id
	_bed_sound_id = ambient_sound_id
	_rebuild_bed()


## The bed that should be playing, as a cue, or null for silence.
func bed() -> AudioCue:
	if _muted:
		return null
	return _bed_cue


func set_master_volume(v: float) -> void:
	_master_volume = clampf(v, 0.0, 1.0)
	_rebuild_bed()


func master_volume() -> float:
	return _master_volume


func set_muted(m: bool) -> void:
	_muted = m


func is_muted() -> bool:
	return _muted


## The bed cue is rebuilt rather than recomputed per call, so that
## re-entering a zone can be detected as "the same cue object" and the
## stage has a cheap identity check for "is this still the same bed".
func _rebuild_bed() -> void:
	if _registry == null or _bed_sound_id == "":
		_bed_cue = null
		return
	_bed_cue = _cue_for(_bed_sound_id)
