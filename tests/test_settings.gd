extends GutTest
## user://settings.json. Never under saves/: settings outlive worlds.

const PATH: String = "user://test_settings/settings.json"


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute("user://test_settings")
	_wipe()


func after_each() -> void:
	_wipe()


func _wipe() -> void:
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(PATH)


func test_the_default_path_is_outside_the_save_root() -> void:
	# A world that has to be deleted must not cost the player their volume.
	assert_eq(Settings.DEFAULT_PATH, "user://settings.json")
	assert_false(Settings.DEFAULT_PATH.contains("saves"))


func test_defaults_when_no_file_exists() -> void:
	var s: Settings = Settings.load_from(PATH)
	assert_almost_eq(s.master_volume, 0.8, 0.001)
	assert_false(s.muted)
	assert_false(s.controls_hint_shown)


func test_round_trips_every_field() -> void:
	var s: Settings = Settings.new()
	s.master_volume = 0.35
	s.muted = true
	s.controls_hint_shown = true
	assert_eq(s.save_to(PATH), "")

	var back: Settings = Settings.load_from(PATH)
	assert_almost_eq(back.master_volume, 0.35, 0.001)
	assert_true(back.muted)
	assert_true(back.controls_hint_shown)


func test_malformed_json_loads_defaults_rather_than_failing() -> void:
	var f: FileAccess = FileAccess.open(PATH, FileAccess.WRITE)
	f.store_string("{not json at all")
	f.close()
	var s: Settings = Settings.load_from(PATH)
	assert_almost_eq(s.master_volume, 0.8, 0.001)


func test_a_json_array_loads_defaults_rather_than_failing() -> void:
	var f: FileAccess = FileAccess.open(PATH, FileAccess.WRITE)
	f.store_string("[1, 2, 3]")
	f.close()
	assert_almost_eq(Settings.load_from(PATH).master_volume, 0.8, 0.001)


func test_a_missing_field_takes_its_default() -> void:
	var f: FileAccess = FileAccess.open(PATH, FileAccess.WRITE)
	f.store_string('{"version": 1, "muted": true}')
	f.close()
	var s: Settings = Settings.load_from(PATH)
	assert_true(s.muted)
	assert_almost_eq(s.master_volume, 0.8, 0.001)


func test_volume_from_disk_is_clamped() -> void:
	# A hand-edited settings.json must not be able to blow the mix up.
	var f: FileAccess = FileAccess.open(PATH, FileAccess.WRITE)
	f.store_string('{"version": 1, "master_volume": 99.0}')
	f.close()
	assert_almost_eq(Settings.load_from(PATH).master_volume, 1.0, 0.001)


func test_the_file_is_human_readable() -> void:
	var s: Settings = Settings.new()
	assert_eq(s.save_to(PATH), "")
	var text: String = FileAccess.get_file_as_string(PATH)
	assert_string_contains(text, "\n")
	assert_string_contains(text, "master_volume")
