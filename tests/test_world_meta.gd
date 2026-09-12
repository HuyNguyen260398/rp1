extends GutTest
## The root meta.json: what Continue reads to know a world exists.


func test_path_is_meta_json_at_the_save_root() -> void:
	assert_eq(WorldMeta.path_in("user://saves/home"), "user://saves/home/meta.json")


func test_round_trips_every_field() -> void:
	var m: WorldMeta = WorldMeta.new()
	m.zone_id = "home"
	m.player_entity_id = 42
	m.created_unix = 1757635200
	m.last_played_unix = 1757638800
	m.playtime = 1234.5

	var result: DecodeResult = WorldMeta.from_json_string(m.to_json_string())
	assert_true(result.ok, result.error)
	var back: WorldMeta = result.value
	assert_eq(back.zone_id, "home")
	assert_eq(back.player_entity_id, 42)
	assert_eq(back.created_unix, 1757635200)
	assert_eq(back.last_played_unix, 1757638800)
	assert_almost_eq(back.playtime, 1234.5, 0.001)


func test_json_is_human_readable() -> void:
	# meta.json is small and cold and worth reading with `cat`, which is
	# the whole reason it is JSON and not part of a binary file.
	var m: WorldMeta = WorldMeta.new()
	assert_string_contains(m.to_json_string(), "\n")


func test_malformed_json_is_a_failure_not_a_crash() -> void:
	var result: DecodeResult = WorldMeta.from_json_string("{ not json")
	assert_false(result.ok)
	assert_string_contains(result.error, "meta.json")


func test_json_that_is_not_an_object_is_a_failure() -> void:
	var result: DecodeResult = WorldMeta.from_json_string("[1, 2, 3]")
	assert_false(result.ok)


func test_a_save_version_from_the_future_is_refused() -> void:
	var result: DecodeResult = WorldMeta.from_json_string(
		'{"save_version": 99, "zone_id": "home"}')
	assert_false(result.ok)
	assert_string_contains(result.error, "newer")


func test_missing_fields_take_defaults() -> void:
	var result: DecodeResult = WorldMeta.from_json_string('{"save_version": 1}')
	assert_true(result.ok, result.error)
	var back: WorldMeta = result.value
	assert_eq(back.zone_id, "home")
	assert_eq(back.playtime, 0.0)
	assert_eq(back.player_entity_id, 0)
