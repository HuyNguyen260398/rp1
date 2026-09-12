extends GutTest
## Every game-loop rule, exercised without a node in sight.
##
## save_root is injected on every session. A test that wrote to
## user://saves/ would destroy the developer's world on every run.

var _root: String = "user://test_saves/session"
var _registry: ContentRegistry


func before_each() -> void:
	_registry = ContentRegistry.new()
	assert_eq(_registry.load_from_dir("res://data").size(), 0)
	_wipe()


func after_each() -> void:
	_wipe()


func _wipe() -> void:
	_rm_rf(_root)
	DirAccess.make_dir_recursive_absolute(_root)


func _rm_rf(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for sub_dir: String in DirAccess.get_directories_at(dir):
		_rm_rf(dir.path_join(sub_dir))
	for file_name: String in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(file_name))
	DirAccess.remove_absolute(dir)


func _session() -> GameSession:
	var s: GameSession = GameSession.new()
	s.save_root = _root
	return s


func test_an_empty_root_holds_no_save() -> void:
	assert_false(_session().has_save())
	assert_false(_session().has_backup())


func test_open_new_loads_the_authored_zone() -> void:
	var s: GameSession = _session()
	var r: SessionOpenResult = s.open_new("res://data/zone/home", _registry)
	assert_true(r.ok, r.error)
	assert_true(r.is_new)
	assert_not_null(r.zone)
	assert_eq(r.zone.size_tiles, Vector2i(128, 128))
	assert_ne(r.player_spawn, Vector2.ZERO)


func test_open_new_does_not_write_until_asked() -> void:
	# The player row does not exist yet -- World spawns it and calls
	# adopt_player. Saving before that would record player_entity_id 0.
	var s: GameSession = _session()
	s.open_new("res://data/zone/home", _registry)
	assert_false(s.has_save())
	assert_true(s.needs_full_save)


func test_open_new_from_a_missing_directory_fails_cleanly() -> void:
	var r: SessionOpenResult = _session().open_new("res://data/zone/nope", _registry)
	assert_false(r.ok)
	assert_null(r.zone)


func test_opening_a_missing_save_fails_without_crashing() -> void:
	var r: SessionOpenResult = _session().open_saved(_registry)
	assert_false(r.ok)
	assert_string_contains(r.error, "no save")


func test_open_saved_reports_a_malformed_meta_rather_than_crashing() -> void:
	var f: FileAccess = FileAccess.open(WorldMeta.path_in(_root), FileAccess.WRITE)
	f.store_string("{ not json")
	f.close()
	var r: SessionOpenResult = _session().open_saved(_registry)
	assert_false(r.ok)
	assert_string_contains(r.error, "malformed")


func test_close_drops_the_world() -> void:
	var s: GameSession = _session()
	s.open_new("res://data/zone/home", _registry)
	s.close()
	assert_null(s.zone)
	assert_eq(s.player_entity_id, 0)


func _opened() -> GameSession:
	var s: GameSession = _session()
	var r: SessionOpenResult = s.open_new("res://data/zone/home", _registry)
	assert_true(r.ok, r.error)
	var id: int = r.zone.entities.spawn(_registry.numeric_of("player"), r.player_spawn)
	s.adopt_player(id)
	return s


func test_the_first_save_writes_every_chunk() -> void:
	# Nothing in Stage 1 dirties a tile, so a dirty-only first save writes
	# an empty chunks/ directory and Continue paints a black screen.
	var s: GameSession = _opened()
	assert_eq(s.save_now(_registry, "new_world").size(), 0)

	var chunks: PackedStringArray = DirAccess.get_files_at(
		_root.path_join("zones/home/chunks"))
	assert_eq(chunks.size(), 16, "a 128x128 zone is 4x4 chunks")
	assert_true(s.has_save())
	assert_false(s.needs_full_save)


func test_saving_records_the_player_entity_id() -> void:
	var s: GameSession = _opened()
	s.save_now(_registry, "new_world")
	var result: DecodeResult = WorldMeta.from_json_string(
		FileAccess.get_file_as_string(WorldMeta.path_in(_root)))
	assert_true(result.ok, result.error)
	assert_eq((result.value as WorldMeta).player_entity_id, s.player_entity_id)


func test_a_new_world_round_trips_through_a_second_session() -> void:
	var first: GameSession = _opened()
	var pid: int = first.player_entity_id
	first.zone.entities.set_position(pid, Vector2(33.5, 44.5))
	first.zone.entities.set_facing(pid, 3)
	first.save_now(_registry, "quit")

	var second: GameSession = _session()
	var r: SessionOpenResult = second.open_saved(_registry)
	assert_true(r.ok, r.error)
	assert_eq(r.player_entity_id, pid)
	assert_eq(r.zone.entities.get_position(pid), Vector2(33.5, 44.5))
	assert_eq(r.zone.entities.get_facing(pid), 3)


func test_animal_homes_survive_the_round_trip() -> void:
	# The reason home became a column at all: a rabbit saved away from its
	# anchor must come back still anchored where it was authored.
	var first: GameSession = _opened()
	var rabbit: int = first.zone.entities.spawn(
		_registry.numeric_of("rabbit"), Vector2(20.5, 20.5))
	first.zone.entities.set_home(rabbit, Vector2(64.5, 64.5))
	first.save_now(_registry, "quit")

	var second: GameSession = _session()
	var r: SessionOpenResult = second.open_saved(_registry)
	assert_true(r.ok, r.error)
	assert_eq(r.zone.entities.get_position(rabbit), Vector2(20.5, 20.5))
	assert_eq(r.zone.entities.get_home(rabbit), Vector2(64.5, 64.5))


func test_autosave_fires_once_at_the_interval() -> void:
	var s: GameSession = _opened()
	s.save_now(_registry, "new_world")

	var step: float = 1.0
	var elapsed: float = 0.0
	var saves: int = 0
	while elapsed < GameSession.AUTOSAVE_INTERVAL - step:
		if s.tick(step, _registry):
			saves += 1
		elapsed += step
	assert_eq(saves, 0, "autosave fired before the interval elapsed")

	assert_true(s.tick(step * 2.0, _registry), "autosave did not fire at the interval")
	assert_false(s.tick(step, _registry), "autosave fired twice")


func test_ticking_accumulates_playtime() -> void:
	var s: GameSession = _opened()
	s.tick(1.5, _registry)
	s.tick(2.5, _registry)
	assert_almost_eq(s.playtime, 4.0, 0.001)


func test_playtime_survives_a_close_and_reopen() -> void:
	var s: GameSession = _opened()
	s.tick(120.0, _registry)
	s.save_now(_registry, "quit")
	s.close()

	var again: GameSession = _session()
	assert_true(again.open_saved(_registry).ok)
	assert_almost_eq(again.playtime, 120.0, 0.001)


func test_created_unix_is_preserved_across_saves() -> void:
	var s: GameSession = _opened()
	s.save_now(_registry, "new_world")
	var first: DecodeResult = WorldMeta.from_json_string(
		FileAccess.get_file_as_string(WorldMeta.path_in(_root)))
	var created: int = (first.value as WorldMeta).created_unix
	assert_gt(created, 0)

	s.tick(GameSession.MIN_SAVE_GAP + 1.0, _registry)
	s.save_now(_registry, "autosave")
	var second: DecodeResult = WorldMeta.from_json_string(
		FileAccess.get_file_as_string(WorldMeta.path_in(_root)))
	assert_eq((second.value as WorldMeta).created_unix, created)


func test_a_second_save_inside_the_gap_is_skipped() -> void:
	# Alt-tabbing repeatedly must not mean saving repeatedly.
	var s: GameSession = _opened()
	s.save_now(_registry, "new_world")
	assert_eq(s.save_if_gap_elapsed(_registry, "focus_lost").size(), 0)
	assert_false(
		FileAccess.file_exists(_root.path_join("zones/home/entities.dat.bak")),
		"a skipped save still rotated the backup")

	s.tick(GameSession.MIN_SAVE_GAP + 1.0, _registry)
	s.save_if_gap_elapsed(_registry, "focus_lost")
	assert_true(FileAccess.file_exists(_root.path_join("zones/home/entities.dat.bak")))


func test_saving_with_no_world_open_is_an_error_not_a_crash() -> void:
	var s: GameSession = _session()
	assert_gt(s.save_now(_registry, "autosave").size(), 0)


func test_ticking_with_no_world_open_does_nothing() -> void:
	var s: GameSession = _session()
	assert_false(s.tick(600.0, _registry))
	assert_eq(s.playtime, 0.0)


func test_a_corrupt_live_save_can_be_recovered_from_the_backup() -> void:
	var s: GameSession = _opened()
	var pid: int = s.player_entity_id
	s.zone.entities.set_position(pid, Vector2(10.5, 10.5))
	s.save_now(_registry, "new_world")
	s.tick(GameSession.MIN_SAVE_GAP + 1.0, _registry)
	s.zone.entities.set_position(pid, Vector2(60.5, 60.5))
	s.save_now(_registry, "autosave")

	# Truncate the live entities file the way a power cut would.
	var f: FileAccess = FileAccess.open(
		_root.path_join("zones/home/entities.dat"), FileAccess.WRITE)
	f.store_buffer(PackedByteArray([0x52, 0x50]))
	f.close()

	var broken: SessionOpenResult = _session().open_saved(_registry, false)
	assert_false(broken.ok)

	var recovered: SessionOpenResult = _session().open_saved(_registry, true)
	assert_true(recovered.ok, recovered.error)
	assert_eq(recovered.zone.entities.get_position(pid), Vector2(10.5, 10.5))
