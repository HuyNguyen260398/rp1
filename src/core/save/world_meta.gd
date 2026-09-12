class_name WorldMeta
extends RefCounted
## The root meta.json: what Continue reads to know a world exists.
##
## JSON rather than binary for the same reason zone_meta.json is: it is
## small, cold, and worth reading with `cat` when a save misbehaves.
##
## `player_entity_id` is recorded rather than rediscovered by scanning for
## the row whose type is "player". A scan would silently pick the first of
## two player rows if a bug ever produced them; naming the id makes that
## state detectable instead.

const SAVE_VERSION: int = 1

var save_version: int = SAVE_VERSION
var zone_id: String = "home"
var player_entity_id: int = 0
var created_unix: int = 0
var last_played_unix: int = 0
var playtime: float = 0.0


static func path_in(save_root: String) -> String:
	return save_root.path_join("meta.json")


func to_json_string() -> String:
	return JSON.stringify({
		"save_version": save_version,
		"zone_id": zone_id,
		"player_entity_id": player_entity_id,
		"created_unix": created_unix,
		"last_played_unix": last_played_unix,
		"playtime": playtime,
	}, "  ", true)


static func from_json_string(text: String) -> DecodeResult:
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		return DecodeResult.failure("meta.json: malformed JSON")
	if not (json.data is Dictionary):
		return DecodeResult.failure("meta.json: top level is not an object")

	var doc: Dictionary = json.data
	var version: int = int(doc.get("save_version", SAVE_VERSION))
	if version > SAVE_VERSION:
		return DecodeResult.failure(
			"meta.json: save_version %d is newer than this build supports (%d)"
			% [version, SAVE_VERSION]
		)

	var m: WorldMeta = WorldMeta.new()
	m.save_version = version
	m.zone_id = str(doc.get("zone_id", "home"))
	m.player_entity_id = int(doc.get("player_entity_id", 0))
	m.created_unix = int(doc.get("created_unix", 0))
	m.last_played_unix = int(doc.get("last_played_unix", 0))
	m.playtime = float(doc.get("playtime", 0.0))
	return DecodeResult.success(m)
