class_name AudioCue
extends RefCounted
## One sound to play, once.
##
## The cue carries its final level rather than a reference to the sound
## def, so AudioStage never computes a level and there is exactly one
## place in the project where the mix can be wrong.

## The sound's string id, resolved against ContentRegistry by the stage.
var sound_id: String = ""

## Which of the sound's streams to play: an index into its `streams`.
var variation: int = 0

## The sound's authored gain_db with master volume already folded in.
var gain_db: float = 0.0


static func make(p_sound_id: String, p_variation: int, p_gain_db: float) -> AudioCue:
	var c: AudioCue = AudioCue.new()
	c.sound_id = p_sound_id
	c.variation = p_variation
	c.gain_db = p_gain_db
	return c
