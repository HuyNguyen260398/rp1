class_name Settings
extends RefCounted
## user://settings.json: the player's preferences, not their world.
##
## Deliberately NOT under saves/. Volume must survive New World, and a
## world that has to be deleted must not cost the player their settings.
##
## load_from never fails. A malformed settings file starting the game at
## defaults is right; a malformed settings file preventing the game from
## starting at all is not, and that is what a strict parser would do here.

const DEFAULT_PATH: String = "user://settings.json"
const VERSION: int = 1

var master_volume: float = 0.8
var muted: bool = false
var controls_hint_shown: bool = false


## Always returns a usable Settings, whatever is on disk.
static func load_from(path: String = DEFAULT_PATH) -> Settings:
	var s: Settings = Settings.new()
	if not FileAccess.file_exists(path):
		return s

	var json: JSON = JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		push_warning("settings.json: malformed, using defaults")
		return s
	if not (json.data is Dictionary):
		push_warning("settings.json: top level is not an object, using defaults")
		return s

	var doc: Dictionary = json.data
	s.master_volume = clampf(float(doc.get("master_volume", s.master_volume)), 0.0, 1.0)
	s.muted = bool(doc.get("muted", s.muted))
	s.controls_hint_shown = bool(doc.get("controls_hint_shown", s.controls_hint_shown))
	return s


## "" on success, the error otherwise. Atomic, like every other write.
func save_to(path: String = DEFAULT_PATH) -> String:
	var doc: Dictionary = {
		"version": VERSION,
		"master_volume": master_volume,
		"muted": muted,
		"controls_hint_shown": controls_hint_shown,
	}
	return SaveManager.atomic_write(path, JSON.stringify(doc, "  ", true).to_utf8_buffer())
