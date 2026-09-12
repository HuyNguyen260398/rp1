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
