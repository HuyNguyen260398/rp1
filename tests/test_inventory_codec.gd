extends GutTest
## inventory.json: round trip, and every way the file can lie.


func _decode(text: String) -> DecodeResult:
	return InventoryCodec.from_json_string(text)


func test_the_file_sits_beside_meta_json() -> void:
	assert_eq(InventoryCodec.path_in("user://saves/home"),
		"user://saves/home/inventory.json")


func test_a_round_trip_preserves_every_count() -> void:
	var inv: Inventory = Inventory.new()
	inv.add("wood", 12)
	inv.add("stone", 3)
	var r: DecodeResult = _decode(InventoryCodec.to_json_string(inv))
	assert_true(r.ok, r.error)
	var back: Inventory = r.value
	assert_eq(back.count_of("wood"), 12)
	assert_eq(back.count_of("stone"), 3)
	assert_eq(back.item_ids(), inv.item_ids())


func test_an_empty_inventory_round_trips_as_empty() -> void:
	var r: DecodeResult = _decode(InventoryCodec.to_json_string(Inventory.new()))
	assert_true(r.ok, r.error)
	assert_true((r.value as Inventory).is_empty())


func test_the_file_names_its_format_version_and_string_ids() -> void:
	var inv: Inventory = Inventory.new()
	inv.add("wood", 2)
	var json: JSON = JSON.new()
	assert_eq(json.parse(InventoryCodec.to_json_string(inv)), OK)
	var doc: Dictionary = json.data
	assert_eq(int(doc["format_version"]), InventoryCodec.FORMAT_VERSION)
	assert_eq(int((doc["items"] as Dictionary)["wood"]), 2,
		"items are keyed by string id, never a runtime numeric")


func test_an_item_the_build_does_not_know_survives_a_round_trip() -> void:
	# The placeholder rule for a string-keyed file: the codec never asks
	# the registry, so a renamed or deleted item keeps its count.
	var r: DecodeResult = _decode(
		'{"format_version": 1, "items": {"mithril": 4, "wood": 1}}')
	assert_true(r.ok, r.error)
	var inv: Inventory = r.value
	assert_eq(inv.count_of("mithril"), 4)
	var again: DecodeResult = _decode(InventoryCodec.to_json_string(inv))
	assert_eq((again.value as Inventory).count_of("mithril"), 4)


func test_a_zero_count_is_dropped_not_refused() -> void:
	var r: DecodeResult = _decode('{"format_version": 1, "items": {"wood": 0}}')
	assert_true(r.ok, r.error)
	assert_true((r.value as Inventory).is_empty())


func test_a_missing_items_key_is_an_empty_inventory() -> void:
	var r: DecodeResult = _decode('{"format_version": 1}')
	assert_true(r.ok, r.error)
	assert_true((r.value as Inventory).is_empty())


func test_malformed_json_is_a_failure_not_a_crash() -> void:
	var r: DecodeResult = _decode("{ not json")
	assert_false(r.ok)
	assert_string_contains(r.error, "inventory.json")


func test_a_top_level_that_is_not_an_object_is_refused() -> void:
	assert_false(_decode("[1, 2, 3]").ok)


func test_items_that_is_not_an_object_is_refused() -> void:
	assert_false(_decode('{"format_version": 1, "items": ["wood"]}').ok)


func test_a_newer_format_version_is_refused() -> void:
	var r: DecodeResult = _decode(
		'{"format_version": %d, "items": {}}' % (InventoryCodec.FORMAT_VERSION + 1))
	assert_false(r.ok)
	assert_string_contains(r.error, "newer")


func test_a_negative_count_is_refused_naming_the_item() -> void:
	var r: DecodeResult = _decode('{"format_version": 1, "items": {"wood": -3}}')
	assert_false(r.ok)
	assert_string_contains(r.error, "wood")


func test_a_fractional_count_is_refused() -> void:
	assert_false(_decode('{"format_version": 1, "items": {"wood": 2.5}}').ok)


func test_a_count_that_is_not_a_number_is_refused() -> void:
	assert_false(_decode('{"format_version": 1, "items": {"wood": "12"}}').ok)
