extends GutTest
## Bulk counts of items by string id. No registry in sight: the inventory
## must hold an id this build does not ship without zeroing it.

var _inv: Inventory


func before_each() -> void:
	_inv = Inventory.new()


func test_a_new_inventory_is_empty() -> void:
	assert_true(_inv.is_empty())
	assert_eq(_inv.item_ids().size(), 0)
	assert_eq(_inv.count_of("wood"), 0)


func test_adding_accumulates() -> void:
	assert_true(_inv.add("wood", 3))
	assert_true(_inv.add("wood", 4))
	assert_eq(_inv.count_of("wood"), 7)
	assert_false(_inv.is_empty())


func test_items_are_counted_independently() -> void:
	_inv.add("wood", 3)
	_inv.add("stone", 5)
	assert_eq(_inv.count_of("wood"), 3)
	assert_eq(_inv.count_of("stone"), 5)


func test_adding_a_non_positive_amount_refuses_and_changes_nothing() -> void:
	_inv.add("wood", 2)
	assert_false(_inv.add("wood", 0))
	assert_false(_inv.add("wood", -5))
	assert_eq(_inv.count_of("wood"), 2)


func test_adding_under_an_empty_id_refuses() -> void:
	assert_false(_inv.add("", 5))
	assert_true(_inv.is_empty())


func test_removing_decrements() -> void:
	_inv.add("wood", 5)
	assert_true(_inv.remove("wood", 2))
	assert_eq(_inv.count_of("wood"), 3)


func test_removing_exactly_what_is_held_empties_the_entry() -> void:
	_inv.add("wood", 5)
	assert_true(_inv.remove("wood", 5))
	assert_eq(_inv.count_of("wood"), 0)
	assert_false(_inv.item_ids().has("wood"), "a zero count is not stored")
	assert_true(_inv.is_empty())


func test_removing_more_than_is_held_refuses_and_changes_nothing() -> void:
	_inv.add("wood", 5)
	assert_false(_inv.remove("wood", 6))
	assert_eq(_inv.count_of("wood"), 5, "a refused removal never goes partway")


func test_removing_something_never_held_refuses() -> void:
	assert_false(_inv.remove("stone", 1))
	assert_true(_inv.is_empty())


func test_removing_a_non_positive_amount_refuses_and_changes_nothing() -> void:
	_inv.add("wood", 5)
	assert_false(_inv.remove("wood", 0))
	# A negative removal would be an add through the back door.
	assert_false(_inv.remove("wood", -3))
	assert_eq(_inv.count_of("wood"), 5)


func test_can_afford_at_the_boundary() -> void:
	_inv.add("wood", 2)
	assert_true(_inv.can_afford({"wood": 2}), "exactly enough is enough")
	assert_false(_inv.can_afford({"wood": 3}), "one short is not")


func test_can_afford_needs_every_item_in_the_cost() -> void:
	_inv.add("wood", 5)
	_inv.add("stone", 1)
	assert_true(_inv.can_afford({"wood": 2, "stone": 1}))
	assert_false(_inv.can_afford({"wood": 2, "stone": 2}))
	assert_false(_inv.can_afford({"wood": 2, "iron": 1}), "an unheld item is unaffordable")


func test_the_empty_cost_is_always_affordable() -> void:
	assert_true(_inv.can_afford({}))


func test_can_afford_accepts_the_integral_floats_json_produces() -> void:
	# JSON.parse gives floats for every number, and cost will come from
	# data/*.json in Phase 10.
	_inv.add("wood", 2)
	assert_true(_inv.can_afford({"wood": 2.0}))
	assert_false(_inv.can_afford({"wood": 3.0}))


func test_can_afford_refuses_a_malformed_cost() -> void:
	_inv.add("wood", 5)
	assert_false(_inv.can_afford({"wood": -1}), "a negative cost is a refund, not a price")
	assert_false(_inv.can_afford({"wood": 1.5}), "half a plank is not a price")
	assert_false(_inv.can_afford({"wood": "2"}), "a string is not a price")


func test_can_afford_does_not_spend() -> void:
	_inv.add("wood", 2)
	var _ok: bool = _inv.can_afford({"wood": 2})
	assert_eq(_inv.count_of("wood"), 2)


func test_item_ids_are_sorted() -> void:
	_inv.add("wood", 1)
	_inv.add("stone", 1)
	_inv.add("clay", 1)
	assert_eq(_inv.item_ids(), PackedStringArray(["clay", "stone", "wood"]))


func test_an_id_unknown_to_any_registry_is_held_like_any_other() -> void:
	_inv.add("mithril", 4)
	assert_eq(_inv.count_of("mithril"), 4)
