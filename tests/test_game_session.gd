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
	# A fresh ChunkWatcher has seen nothing, and changed() defaults an
	# unseen chunk to -1, which never equals a real version. So a first
	# save writes every chunk even without needs_full_save -- the old
	# black-screen-Continue hazard is gone, and this pins that down.
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


func test_the_gap_predicate_agrees_with_what_the_gap_save_does() -> void:
	# save_if_gap_elapsed returns an empty array both when it saved and
	# when it declined, so a caller that needs to know which -- the save
	# indicator -- has to be able to ask first. Without this, every
	# alt-tab reports "Saved" whether or not anything was written.
	var s: GameSession = _opened()
	s.save_now(_registry, "new_world")
	assert_false(s.save_gap_elapsed(), "a save just ran, so the gap has not elapsed")

	s.tick(GameSession.MIN_SAVE_GAP + 1.0, _registry)
	assert_true(s.save_gap_elapsed(), "the gap has elapsed, so a focus loss would save")
	assert_eq(s.save_if_gap_elapsed(_registry, "focus_lost").size(), 0)
	assert_false(s.save_gap_elapsed(), "and the save it just did resets the gap")


# --- inventory --------------------------------------------------------

func _inventory_file() -> String:
	return InventoryCodec.path_in(_root)


func test_a_new_world_starts_with_an_empty_inventory() -> void:
	assert_true(_opened().inventory.is_empty())


func test_every_save_writes_the_inventory_even_when_empty() -> void:
	var s: GameSession = _opened()
	assert_eq(s.save_now(_registry, "new_world").size(), 0)
	assert_true(FileAccess.file_exists(_inventory_file()))


func test_the_inventory_survives_a_close_and_reopen() -> void:
	var first: GameSession = _opened()
	first.inventory.add("wood", 12)
	first.inventory.add("stone", 3)
	assert_eq(first.save_now(_registry, "quit").size(), 0)
	first.close()

	var second: GameSession = _session()
	var r: SessionOpenResult = second.open_saved(_registry)
	assert_true(r.ok, r.error)
	assert_eq(second.inventory.count_of("wood"), 12)
	assert_eq(second.inventory.count_of("stone"), 3)


func test_new_world_resets_the_inventory() -> void:
	# The same session object is reused by main.gd across worlds, and the
	# old world's inventory.json is still on disk when New World saves.
	var s: GameSession = _opened()
	s.inventory.add("wood", 40)
	s.save_now(_registry, "quit")

	var r: SessionOpenResult = s.open_new("res://data/zone/home", _registry)
	assert_true(r.ok, r.error)
	assert_true(s.inventory.is_empty(), "open_new starts from nothing")
	var id: int = r.zone.entities.spawn(_registry.numeric_of("player"), r.player_spawn)
	s.adopt_player(id)
	assert_eq(s.save_now(_registry, "new_world").size(), 0)

	var reopened: GameSession = _session()
	assert_true(reopened.open_saved(_registry).ok)
	assert_eq(reopened.inventory.count_of("wood"), 0,
		"the overwritten world's wood did not survive into the new one")


func test_close_empties_the_inventory() -> void:
	var s: GameSession = _opened()
	s.inventory.add("wood", 5)
	s.close()
	assert_true(s.inventory.is_empty())


func test_a_save_with_no_inventory_file_opens_empty() -> void:
	var first: GameSession = _opened()
	first.save_now(_registry, "quit")
	assert_eq(DirAccess.remove_absolute(_inventory_file()), OK)

	var second: GameSession = _session()
	var r: SessionOpenResult = second.open_saved(_registry)
	assert_true(r.ok, r.error)
	assert_true(second.inventory.is_empty())


func test_a_malformed_inventory_fails_the_open_and_changes_nothing() -> void:
	var first: GameSession = _opened()
	first.save_now(_registry, "quit")
	var f: FileAccess = FileAccess.open(_inventory_file(), FileAccess.WRITE)
	f.store_string('{"format_version": 1, "items": {"wood": -3}}')
	f.close()

	var second: GameSession = _session()
	second.inventory.add("marker", 1)
	var r: SessionOpenResult = second.open_saved(_registry)
	assert_false(r.ok, "a corrupt inventory is not quietly emptied")
	assert_string_contains(r.error, "inventory.json")
	assert_null(second.zone, "a failed open does not half-commit the world")
	assert_eq(second.inventory.count_of("marker"), 1,
		"a failed open leaves the inventory it found")


func test_the_backup_carries_its_own_inventory() -> void:
	var s: GameSession = _opened()
	s.inventory.add("wood", 5)
	s.save_now(_registry, "first")
	s.inventory.add("wood", 2)
	s.save_now(_registry, "second")

	var restored: GameSession = _session()
	var r: SessionOpenResult = restored.open_saved(_registry, true)
	assert_true(r.ok, r.error)
	assert_eq(restored.inventory.count_of("wood"), 5,
		"the backup is the previous save, inventory included")


func test_a_backup_with_no_inventory_opens_empty() -> void:
	# A Stage 1 save that has been saved once by a Stage 2 build: its
	# meta.json.bak exists, but no inventory.json.bak was ever written.
	var s: GameSession = _opened()
	s.save_now(_registry, "first")
	s.save_now(_registry, "second")
	assert_eq(DirAccess.remove_absolute(_inventory_file() + ".bak"), OK)

	var restored: GameSession = _session()
	var r: SessionOpenResult = restored.open_saved(_registry, true)
	assert_true(r.ok, r.error)
	assert_true(restored.inventory.is_empty())


const STAGE1_SAVE: String = "res://tests/fixtures/stage1_save"


func test_a_stage1_save_opens_with_an_empty_inventory() -> void:
	# Written by the Stage 1 build at a175711, before inventories existed.
	# "No migration needed" has to fail loudly here if it stops being true.
	assert_false(FileAccess.file_exists(InventoryCodec.path_in(STAGE1_SAVE)),
		"precondition: the fixture predates inventory.json")
	var s: GameSession = GameSession.new()
	s.save_root = STAGE1_SAVE
	var r: SessionOpenResult = s.open_saved(_registry)
	assert_true(r.ok, r.error)
	assert_eq(r.zone.id, "home")
	assert_true(r.zone.entities.has(r.player_entity_id))
	assert_true(s.inventory.is_empty())
	assert_almost_eq(s.playtime, 61.0, 0.001)


func test_a_stage1_save_gains_an_inventory_on_its_first_stage2_save() -> void:
	var s: GameSession = GameSession.new()
	s.save_root = STAGE1_SAVE
	assert_true(s.open_saved(_registry).ok)
	# Redirected before saving: the committed fixture must never be written.
	s.save_root = _root
	s.needs_full_save = true
	s.inventory.add("wood", 3)
	assert_eq(s.save_now(_registry, "upgrade").size(), 0)

	var again: GameSession = _session()
	assert_true(again.open_saved(_registry).ok)
	assert_eq(again.inventory.count_of("wood"), 3)


# --- harvesting -------------------------------------------------------

## The first tile of the authored zone holding anything harvestable.
func _first_harvestable(zone: Zone) -> Vector2i:
	for y: int in range(zone.size_tiles.y):
		for x: int in range(zone.size_tiles.x):
			var tile: Vector2i = Vector2i(x, y)
			if _registry.def_of(zone.get_object(tile)).has("harvestable"):
				return tile
	return Vector2i(-1, -1)


func _harvest(s: GameSession, tile: Vector2i) -> HarvestResult:
	var h: HarvestSystem = HarvestSystem.new()
	h.rng.seed = 1
	return h.harvest(s.zone, tile, s.inventory, _registry)


func test_a_harvested_object_stays_gone_and_its_yield_stays_counted() -> void:
	# The phase's "done when": chop, relaunch, still gone, still counted.
	var first: GameSession = _opened()
	var tile: Vector2i = _first_harvestable(first.zone)
	assert_true(first.zone.in_bounds(tile), "the authored zone has something to harvest")
	var got: HarvestResult = _harvest(first, tile)
	assert_true(got.ok, got.detail)
	assert_eq(first.save_now(_registry, "quit").size(), 0)
	first.close()

	var second: GameSession = _session()
	var r: SessionOpenResult = second.open_saved(_registry)
	assert_true(r.ok, r.error)
	assert_eq(second.zone.get_object(tile), ContentRegistry.ID_UNKNOWN,
		"the harvested object did not come back")
	assert_eq(second.inventory.count_of(got.item_id), got.amount)


func test_a_harvest_after_the_first_save_reaches_disk() -> void:
	# The first save writes every chunk. This one is incremental: it must
	# write the harvested chunk because its version moved, and only that.
	var first: GameSession = _opened()
	assert_eq(first.save_now(_registry, "new_world").size(), 0)
	var tile: Vector2i = _first_harvestable(first.zone)
	var got: HarvestResult = _harvest(first, tile)
	assert_true(got.ok, got.detail)
	assert_eq(first.save_now(_registry, "autosave").size(), 0)
	first.close()

	var second: GameSession = _session()
	assert_true(second.open_saved(_registry).ok)
	assert_eq(second.zone.get_object(tile), ContentRegistry.ID_UNKNOWN)
	assert_eq(second.inventory.count_of(got.item_id), got.amount)


func test_a_backup_load_keeps_the_harvest_but_not_its_yield() -> void:
	# KNOWN GAP, pinned on purpose -- see the Phase 9 plan. Chunks have no
	# backup (save_manager.gd: "A Stage 2 that makes chunks mutable must
	# rotate them too"), while inventory.json does. So the backup is the
	# live chunks with the previous inventory: the object is gone and its
	# yield is not counted. When chunk backups land this test must change,
	# and the right assertion is that both come back together.
	var s: GameSession = _opened()
	assert_eq(s.save_now(_registry, "first").size(), 0)
	var tile: Vector2i = _first_harvestable(s.zone)
	var got: HarvestResult = _harvest(s, tile)
	assert_true(got.ok, got.detail)
	assert_eq(s.save_now(_registry, "second").size(), 0)

	var restored: GameSession = _session()
	var r: SessionOpenResult = restored.open_saved(_registry, true)
	assert_true(r.ok, r.error)
	assert_eq(restored.zone.get_object(tile), ContentRegistry.ID_UNKNOWN)
	assert_eq(restored.inventory.count_of(got.item_id), 0)


# --- building ---------------------------------------------------------

func _place_cmd(tile: Vector2i, content_id: String) -> BuildCommand:
	return BuildCommand.place(tile, BuildCommand.LAYER_OBJECT, content_id)


## Credits `times` multiples of what `content_id` costs, and returns the
## cost of one.
func _grant_cost(s: GameSession, content_id: String, times: int) -> Dictionary:
	var cost: Dictionary = BuildSystem.cost_of(
		_registry.def_of(_registry.numeric_of(content_id)))
	for item_id: String in cost:
		var _added: bool = s.inventory.add(item_id, int(cost[item_id]) * times)
	return cost


## The first tile of the authored zone where `content_id` may be placed.
func _first_buildable(s: GameSession, content_id: String) -> Vector2i:
	for y: int in range(s.zone.size_tiles.y):
		for x: int in range(s.zone.size_tiles.x):
			var tile: Vector2i = Vector2i(x, y)
			if BuildSystem.check(
					_place_cmd(tile, content_id), s.zone, s.inventory, _registry).ok:
				return tile
	return Vector2i(-1, -1)


func test_a_placed_object_survives_a_relaunch_and_its_cost_stays_spent() -> void:
	# The phase's "done when": place, relaunch, still there, still paid for.
	var first: GameSession = _opened()
	var content_id: String = BuildSystem.placeables(_registry)[0]
	var cost: Dictionary = _grant_cost(first, content_id, 3)
	var tile: Vector2i = _first_buildable(first, content_id)
	assert_true(first.zone.in_bounds(tile), "the authored zone has somewhere to build")
	var got: BuildResult = BuildSystem.apply(
		_place_cmd(tile, content_id), first.zone, first.inventory, _registry)
	assert_true(got.ok, got.reason)
	assert_eq(first.save_now(_registry, "quit").size(), 0)
	first.close()

	var second: GameSession = _session()
	var r: SessionOpenResult = second.open_saved(_registry)
	assert_true(r.ok, r.error)
	assert_eq(_registry.string_of(second.zone.get_object(tile)), content_id,
		"the placed object is still there")
	for item_id: String in cost:
		assert_eq(second.inventory.count_of(item_id), int(cost[item_id]) * 2,
			"%s: one cost of three was spent" % item_id)


func test_a_removal_after_the_first_save_reaches_disk() -> void:
	# The first save writes every chunk. The second is incremental: it must
	# write the edited chunk because its version moved again.
	var first: GameSession = _opened()
	var content_id: String = BuildSystem.placeables(_registry)[0]
	var cost: Dictionary = _grant_cost(first, content_id, 3)
	var tile: Vector2i = _first_buildable(first, content_id)
	assert_true(BuildSystem.apply(
		_place_cmd(tile, content_id), first.zone, first.inventory, _registry).ok)
	assert_eq(first.save_now(_registry, "new_world").size(), 0)
	var removed: BuildResult = BuildSystem.apply(
		BuildCommand.remove(tile, BuildCommand.LAYER_OBJECT),
		first.zone, first.inventory, _registry)
	assert_true(removed.ok, removed.reason)
	assert_eq(first.save_now(_registry, "autosave").size(), 0)
	first.close()

	var second: GameSession = _session()
	assert_true(second.open_saved(_registry).ok)
	assert_eq(second.zone.get_object(tile), ContentRegistry.ID_UNKNOWN,
		"the removed object did not come back")
	for item_id: String in cost:
		assert_eq(second.inventory.count_of(item_id), int(cost[item_id]) * 3,
			"%s: the refund was saved" % item_id)
