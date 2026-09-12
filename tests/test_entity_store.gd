extends GutTest

var _s: EntityStore


func before_each() -> void:
	_s = EntityStore.new()


func test_new_store_is_empty() -> void:
	assert_eq(_s.count(), 0)
	assert_eq(_s.ids().size(), 0)


func test_spawn_returns_a_valid_id() -> void:
	var id: int = _s.spawn(7, Vector2(1.5, 2.5))
	assert_ne(id, EntityStore.INVALID_ID, "spawn never returns the invalid id")
	assert_true(_s.has(id))
	assert_eq(_s.count(), 1)


func test_spawn_stores_type_and_position() -> void:
	var id: int = _s.spawn(7, Vector2(1.5, 2.5))
	assert_eq(_s.get_type_id(id), 7)
	assert_almost_eq(_s.get_position(id).x, 1.5, 0.001)
	assert_almost_eq(_s.get_position(id).y, 2.5, 0.001)


func test_ids_are_unique() -> void:
	var seen: Dictionary = {}
	for i: int in range(100):
		var id: int = _s.spawn(1, Vector2.ZERO)
		assert_false(seen.has(id), "id %d issued only once" % id)
		seen[id] = true
	assert_eq(_s.count(), 100)


func test_despawn_removes_the_entity() -> void:
	var id: int = _s.spawn(3, Vector2.ZERO)
	assert_true(_s.despawn(id))
	assert_false(_s.has(id))
	assert_eq(_s.count(), 0)


func test_despawn_of_unknown_id_returns_false() -> void:
	assert_false(_s.despawn(9999))
	assert_false(_s.despawn(EntityStore.INVALID_ID))


func test_ids_are_never_reused_after_despawn() -> void:
	# A recycled id would let a stale reference silently address a
	# different entity. The slot is reused; the id is not.
	var first: int = _s.spawn(1, Vector2.ZERO)
	assert_true(_s.despawn(first))
	var second: int = _s.spawn(1, Vector2.ZERO)
	assert_ne(second, first, "id is not recycled")


func test_slot_is_recycled_so_rows_do_not_grow_without_bound() -> void:
	var a: int = _s.spawn(1, Vector2.ZERO)
	var rows_after_first: int = _s.row_count()
	assert_true(_s.despawn(a))
	var _b: int = _s.spawn(1, Vector2.ZERO)
	assert_eq(_s.row_count(), rows_after_first, "the freed slot was reused")


func test_position_can_be_updated() -> void:
	var id: int = _s.spawn(1, Vector2.ZERO)
	_s.set_position(id, Vector2(-12.25, 300.5))
	assert_almost_eq(_s.get_position(id).x, -12.25, 0.001)
	assert_almost_eq(_s.get_position(id).y, 300.5, 0.001)


func test_facing_round_trips() -> void:
	var id: int = _s.spawn(1, Vector2.ZERO)
	_s.set_facing(id, 5)
	assert_eq(_s.get_facing(id), 5)


func test_ids_lists_only_live_entities() -> void:
	var a: int = _s.spawn(1, Vector2.ZERO)
	var b: int = _s.spawn(1, Vector2.ZERO)
	assert_true(_s.despawn(a))
	var live: PackedInt32Array = _s.ids()
	assert_eq(live.size(), 1)
	assert_eq(live[0], b)


func test_next_id_is_preserved_across_save_and_load() -> void:
	# Loading a save must not restart id allocation, or new entities
	# would collide with saved ones.
	var _a: int = _s.spawn(1, Vector2.ZERO)
	var saved: int = _s.next_id()
	var fresh: EntityStore = EntityStore.new()
	fresh.set_next_id(saved)
	assert_eq(fresh.spawn(1, Vector2.ZERO), saved)


func test_spawn_anchors_home_at_the_spawn_position() -> void:
	var id: int = _s.spawn(7, Vector2(4.5, 9.5))
	assert_eq(_s.get_home(id), Vector2(4.5, 9.5))


func test_moving_an_entity_does_not_move_its_home() -> void:
	var id: int = _s.spawn(7, Vector2(4.5, 9.5))
	_s.set_position(id, Vector2(40.0, 90.0))
	assert_eq(_s.get_home(id), Vector2(4.5, 9.5))
	assert_eq(_s.get_position(id), Vector2(40.0, 90.0))


func test_set_home_is_independent_of_position() -> void:
	var id: int = _s.spawn(7, Vector2(4.5, 9.5))
	_s.set_home(id, Vector2(1.5, 2.5))
	assert_eq(_s.get_home(id), Vector2(1.5, 2.5))
	assert_eq(_s.get_position(id), Vector2(4.5, 9.5))


func test_a_reused_slot_does_not_inherit_the_previous_home() -> void:
	# Slot reuse is the one path where a stale column value survives a
	# despawn. Without the reuse branch setting home, the new entity would
	# silently adopt the dead one's anchor.
	var first: int = _s.spawn(7, Vector2(4.5, 9.5))
	assert_true(_s.despawn(first))
	var second: int = _s.spawn(7, Vector2(60.5, 60.5))
	assert_eq(_s.get_home(second), Vector2(60.5, 60.5))


func test_restore_row_takes_home_verbatim() -> void:
	_s.restore_row(9, 7, Vector2(4.5, 9.5), 2, EntityStore.FLAG_ACTIVE, 0, Vector2(1.5, 2.5))
	assert_eq(_s.get_position(9), Vector2(4.5, 9.5))
	assert_eq(_s.get_home(9), Vector2(1.5, 2.5))
