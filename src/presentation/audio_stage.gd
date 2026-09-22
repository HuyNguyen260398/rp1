class_name AudioStage
extends Node
## Cues in, AudioStreamPlayers out. Holds no rules: every decision about
## what plays, when, and how loud was made by AudioDirector.
##
## Streams are resolved through ContentRegistry and cached, guarding with
## ResourceLoader.exists() before load() because load() on a missing path
## pushes an engine-level error. Same guard as entity_renderer.gd:64.

## Footsteps are short; four covers overlap at any believable cadence.
const VOICES: int = 4

var _registry: ContentRegistry = null
var _voices: Array[AudioStreamPlayer] = []
var _next_voice: int = 0
var _bed_player: AudioStreamPlayer = null
var _bed_cue: AudioCue = null
var _streams: Dictionary = {}   ## "sound_id:variation" -> AudioStream


func setup(p_registry: ContentRegistry) -> void:
	_registry = p_registry
	for i: int in range(VOICES):
		var player: AudioStreamPlayer = AudioStreamPlayer.new()
		player.name = "Voice%d" % i
		add_child(player)
		_voices.append(player)

	_bed_player = AudioStreamPlayer.new()
	_bed_player.name = "Bed"
	add_child(_bed_player)


func play(cues: Array[AudioCue]) -> void:
	for cue: AudioCue in cues:
		var stream: AudioStream = _stream_for(cue)
		if stream == null:
			continue
		var player: AudioStreamPlayer = _voices[_next_voice]
		_next_voice = (_next_voice + 1) % VOICES
		player.stream = stream
		player.volume_db = cue.gain_db
		player.play()


## Null stops the bed. The same cue twice is deliberately a no-op: the
## director returns an identical object while the zone is unchanged, so
## this is what keeps a Continue from restarting the ambience.
func set_bed(cue: AudioCue) -> void:
	if cue == _bed_cue:
		return
	_bed_cue = cue

	if cue == null:
		_bed_player.stop()
		return

	var stream: AudioStream = _stream_for(cue)
	if stream == null:
		_bed_player.stop()
		return
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	_bed_player.stream = stream
	_bed_player.volume_db = cue.gain_db
	_bed_player.play()


func _stream_for(cue: AudioCue) -> AudioStream:
	var key: String = "%s:%d" % [cue.sound_id, cue.variation]
	if _streams.has(key):
		return _streams[key]

	var def: Dictionary = _registry.def_of(_registry.numeric_of(cue.sound_id))
	var streams: Array = def.get("streams", [])
	var stream: AudioStream = null
	if cue.variation < 0 or cue.variation >= streams.size():
		push_error("audio: %s has no variation %d" % [cue.sound_id, cue.variation])
	else:
		var path: String = str(streams[cue.variation])
		if not ResourceLoader.exists(path):
			push_error("audio: cannot load '%s' for %s" % [path, cue.sound_id])
		else:
			stream = load(path) as AudioStream
	_streams[key] = stream
	return stream
