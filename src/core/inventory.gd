class_name Inventory
extends RefCounted
## Bulk counts of items, keyed by string id.
##
## No slots and no stack limits: a building sandbox spends resources in
## bulk. Keys are string ids rather than registry numerics, so the
## inventory persists without a translation table, and an item this build
## does not ship keeps its count instead of being zeroed. That is also why
## nothing here consults the ContentRegistry.
##
## A zero count is never stored. Every method that refuses leaves the
## inventory exactly as it was.

var _counts: Dictionary = {}  ## item id (String) -> count (int), always > 0


func count_of(item_id: String) -> int:
	return _counts.get(item_id, 0)


func is_empty() -> bool:
	return _counts.is_empty()


func item_ids() -> PackedStringArray:
	var out: PackedStringArray = []
	for item_id: String in _counts:
		out.append(item_id)
	out.sort()
	return out


func add(item_id: String, amount: int) -> bool:
	if item_id.is_empty() or amount <= 0:
		return false
	_counts[item_id] = count_of(item_id) + amount
	return true


func remove(item_id: String, amount: int) -> bool:
	if amount <= 0:
		return false
	var held: int = count_of(item_id)
	if amount > held:
		return false
	if amount == held:
		_counts.erase(item_id)
	else:
		_counts[item_id] = held - amount
	return true


## `cost` maps item id to amount, straight from JSON, so an amount may
## arrive as an integral float. Anything that is not a whole, non-negative
## number makes the cost unaffordable rather than quietly rounded.
func can_afford(cost: Dictionary) -> bool:
	for item_id: Variant in cost:
		var amount: Variant = cost[item_id]
		if not (amount is int or amount is float):
			return false
		if not is_equal_approx(float(amount), roundf(float(amount))):
			return false
		var need: int = int(amount)
		if need < 0 or need > count_of(str(item_id)):
			return false
	return true
