class_name GameSession
extends RefCounted
## Every game-loop decision, with no node in sight.
##
## Whether a save exists, what New World means, when autosave fires, how the
## backup rotates, how playtime accumulates. The router node calls into this
## and the menus call the router; nothing about the loop is decided inside a
## Node, which is what makes all of it testable headless.
##
## `save_root` is a variable rather than a constant so tests can point it at
## a throwaway directory. A test that wrote to user://saves/ would destroy
## the developer's world on every run.

## Five minutes of unpaused play.
const AUTOSAVE_INTERVAL: float = 300.0

## Alt-tabbing repeatedly must not mean saving repeatedly.
const MIN_SAVE_GAP: float = 5.0

const DEFAULT_SAVE_ROOT: String = "user://saves/home"

var save_root: String = DEFAULT_SAVE_ROOT

var zone: Zone = null
var player_entity_id: int = 0
var playtime: float = 0.0

## The first save of a world must write every chunk. Nothing in Stage 1
## dirties a tile -- building is out of scope and animals move entity rows,
## not tiles -- so a dirty-only first save writes no chunks at all and
## Continue loads a black screen.
var needs_full_save: bool = false

var _since_autosave: float = 0.0
var _since_any_save: float = 0.0


func has_save() -> bool:
	return FileAccess.file_exists(WorldMeta.path_in(save_root))


func has_backup() -> bool:
	return FileAccess.file_exists(WorldMeta.path_in(save_root) + ".bak")


## Loads the authored zone. Writes nothing: the player row does not exist
## until World spawns it and calls adopt_player, and the first save has to
## record that id.
func open_new(zone_dir: String, registry: ContentRegistry) -> SessionOpenResult:
	var loaded: ZoneLoadResult = ZoneLoader.load_zone(zone_dir, registry)
	if loaded.zone == null:
		return SessionOpenResult.failure(
			"could not load the zone from %s: %s" % [zone_dir, ", ".join(loaded.errors)])

	zone = loaded.zone
	player_entity_id = 0
	playtime = 0.0
	needs_full_save = true
	_since_autosave = 0.0
	_since_any_save = 0.0

	var r: SessionOpenResult = SessionOpenResult.new()
	r.ok = true
	r.zone = zone
	r.player_spawn = loaded.player_spawn
	r.is_new = true
	r.warnings = loaded.errors
	return r


func open_saved(registry: ContentRegistry, use_backup: bool = false) -> SessionOpenResult:
	var meta_path: String = WorldMeta.path_in(save_root)
	if use_backup:
		meta_path += ".bak"
	if not FileAccess.file_exists(meta_path):
		return SessionOpenResult.failure("no save at %s" % meta_path)

	var meta_result: DecodeResult = WorldMeta.from_json_string(
		FileAccess.get_file_as_string(meta_path))
	if not meta_result.ok:
		return SessionOpenResult.failure(meta_result.error)
	var meta: WorldMeta = meta_result.value

	var decoded: DecodeResult = SaveManager.load_zone(
		save_root, meta.zone_id, registry, use_backup)
	if not decoded.ok:
		return SessionOpenResult.failure(decoded.error)

	var loaded_zone: Zone = decoded.value
	if not loaded_zone.entities.has(meta.player_entity_id):
		return SessionOpenResult.failure(
			"save names player entity %d, which is not in entities.dat"
			% meta.player_entity_id)

	zone = loaded_zone
	playtime = meta.playtime
	player_entity_id = meta.player_entity_id
	needs_full_save = false
	_since_autosave = 0.0
	_since_any_save = 0.0

	var r: SessionOpenResult = SessionOpenResult.new()
	r.ok = true
	r.zone = zone
	r.player_entity_id = player_entity_id
	r.is_new = false
	return r


## World calls this once it has spawned the player into a new world.
func adopt_player(id: int) -> void:
	player_entity_id = id


func close() -> void:
	zone = null
	player_entity_id = 0
	playtime = 0.0
	needs_full_save = false
	_since_autosave = 0.0
	_since_any_save = 0.0


## Advances playtime and the autosave clock. Returns true if it saved.
##
## Driven by accumulated delta rather than by the wall clock, so a paused
## game's clock genuinely stops and every rule here is reproducible in a
## test without waiting five minutes.
func tick(delta: float, registry: ContentRegistry) -> bool:
	if zone == null:
		return false
	playtime += delta
	_since_autosave += delta
	_since_any_save += delta
	if _since_autosave < AUTOSAVE_INTERVAL:
		return false
	save_now(registry, "autosave")
	return true


## Saves unless one ran within MIN_SAVE_GAP. Returns whatever save_now
## would have returned, or an empty array when it declined to save.
func save_if_gap_elapsed(registry: ContentRegistry, reason: String) -> PackedStringArray:
	if _since_any_save < MIN_SAVE_GAP:
		return PackedStringArray()
	return save_now(registry, reason)


func save_now(registry: ContentRegistry, reason: String) -> PackedStringArray:
	if zone == null:
		return PackedStringArray(["cannot save: no world is open"])

	var started: int = Time.get_ticks_msec()
	var errors: PackedStringArray = SaveManager.save_zone(
		save_root, zone, registry, needs_full_save, true)

	var meta: WorldMeta = WorldMeta.new()
	meta.zone_id = zone.id
	meta.player_entity_id = player_entity_id
	meta.last_played_unix = int(Time.get_unix_time_from_system())
	meta.created_unix = meta.last_played_unix
	meta.playtime = playtime

	# A world is created once. Every later save inherits that timestamp
	# rather than claiming the world was made just now.
	var meta_path: String = WorldMeta.path_in(save_root)
	if FileAccess.file_exists(meta_path):
		var prior: DecodeResult = WorldMeta.from_json_string(
			FileAccess.get_file_as_string(meta_path))
		if prior.ok and (prior.value as WorldMeta).created_unix > 0:
			meta.created_unix = (prior.value as WorldMeta).created_unix

	var meta_err: String = SaveManager.atomic_write(
		meta_path, meta.to_json_string().to_utf8_buffer(), true)
	if meta_err != "":
		errors.append(meta_err)

	if errors.is_empty():
		needs_full_save = false
		_since_autosave = 0.0
		_since_any_save = 0.0
		print("RP1 saved (%s) in %d ms" % [reason, Time.get_ticks_msec() - started])
	return errors
