extends GutTest
## Every audio rule. The director is node-free on purpose: cadence is the
## kind of thing that is obvious by ear and invisible in review, so it is
## tested rather than listened to.

var _registry: ContentRegistry
var _director: AudioDirector
var _grass: int


func before_each() -> void:
	_registry = ContentRegistry.new()
	# Registered by hand rather than loaded from data/, so these tests
	# keep passing when the shipped content is retuned.
	_grass = _registry.register({
		"id": "grass", "category": "terrain", "display_name": "Grass",
		"sprite": "res://assets/tiles/grass.png", "walkable": true,
		"footstep": "step_grass",
	})
	var _sound: int = _registry.register({
		"id": "step_grass", "category": "sound", "display_name": "Grass footstep",
		"streams": ["a.ogg", "b.ogg", "c.ogg"], "gain_db": -6.0, "loop": false,
	})
	_director = AudioDirector.new()
	_director.rng = RandomNumberGenerator.new()
	_director.rng.seed = 1
	_director.configure(_registry)


func test_standing_still_is_silent() -> void:
	assert_eq(_director.tick(0.0, _grass).size(), 0)


func test_a_step_lands_once_the_distance_is_covered() -> void:
	assert_eq(_director.tick(AudioDirector.STEP_DISTANCE * 0.5, _grass).size(), 0)
	assert_eq(_director.tick(AudioDirector.STEP_DISTANCE * 0.5, _grass).size(), 1)


func test_the_accumulator_carries_the_remainder() -> void:
	# Otherwise short frames would round away distance and the cadence
	# would drift slower the higher the frame rate.
	var _first: Array[AudioCue] = _director.tick(AudioDirector.STEP_DISTANCE * 1.5, _grass)
	assert_eq(_director.tick(AudioDirector.STEP_DISTANCE * 0.5, _grass).size(), 1)


func test_one_enormous_frame_emits_one_step_not_a_burst() -> void:
	# A frame spike, or a debugger pause, must not machine-gun.
	assert_eq(_director.tick(AudioDirector.STEP_DISTANCE * 40.0, _grass).size(), 1)


func test_a_frame_spike_does_not_leave_a_step_owed() -> void:
	# The tick after the spike has covered no ground at all. If the
	# backlog were carried, it would step anyway -- audibly, while the
	# player stands still.
	var _spike: Array[AudioCue] = _director.tick(AudioDirector.STEP_DISTANCE * 40.0, _grass)
	assert_eq(_director.tick(0.0, _grass).size(), 0)


func test_the_cue_names_the_terrains_sound() -> void:
	var cues: Array[AudioCue] = _director.tick(AudioDirector.STEP_DISTANCE, _grass)
	assert_eq(cues.size(), 1)
	assert_eq(cues[0].sound_id, "step_grass")


func _step() -> AudioCue:
	var cues: Array[AudioCue] = _director.tick(AudioDirector.STEP_DISTANCE, _grass)
	assert_eq(cues.size(), 1)
	return cues[0]


func test_a_variation_is_never_repeated_consecutively() -> void:
	var previous: int = -1
	for i: int in range(40):
		var cue: AudioCue = _step()
		assert_ne(cue.variation, previous, "variation repeated on step %d" % i)
		previous = cue.variation


func test_every_variation_is_reachable() -> void:
	# A skip-the-last-index rule implemented off by one would quietly
	# never play the last sample in the list.
	var seen: Dictionary = {}
	for i: int in range(60):
		seen[_step().variation] = true
	assert_eq(seen.size(), 3)


func test_a_single_variation_sound_repeats_rather_than_going_silent() -> void:
	var r: ContentRegistry = ContentRegistry.new()
	var terrain: int = r.register({
		"id": "sand", "category": "terrain", "display_name": "Sand",
		"sprite": "res://assets/tiles/sand.png", "walkable": true,
		"footstep": "step_sand",
	})
	var _s: int = r.register({
		"id": "step_sand", "category": "sound", "display_name": "Sand footstep",
		"streams": ["only.ogg"],
	})
	var d: AudioDirector = AudioDirector.new()
	d.configure(r)
	assert_eq(d.tick(AudioDirector.STEP_DISTANCE, terrain)[0].variation, 0)
	assert_eq(d.tick(AudioDirector.STEP_DISTANCE, terrain)[0].variation, 0)


func test_a_terrain_without_a_footstep_is_silent() -> void:
	var r: ContentRegistry = ContentRegistry.new()
	var water: int = r.register({
		"id": "water", "category": "terrain", "display_name": "Water",
		"sprite": "res://assets/tiles/water.png", "walkable": false,
	})
	var d: AudioDirector = AudioDirector.new()
	d.configure(r)
	assert_eq(d.tick(AudioDirector.STEP_DISTANCE, water).size(), 0)


func test_a_footstep_naming_content_this_build_lacks_is_silent() -> void:
	# The save-layer placeholder rule, applied to audio: content named but
	# missing is silence, never a crash and never an engine error.
	var r: ContentRegistry = ContentRegistry.new()
	var terrain: int = r.register({
		"id": "moss", "category": "terrain", "display_name": "Moss",
		"sprite": "res://assets/tiles/moss.png", "walkable": true,
		"footstep": "step_moss_that_was_deleted",
	})
	var d: AudioDirector = AudioDirector.new()
	d.configure(r)
	assert_eq(d.tick(AudioDirector.STEP_DISTANCE, terrain).size(), 0)
