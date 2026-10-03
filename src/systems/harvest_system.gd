class_name HarvestSystem
extends RefCounted
## Turns a harvestable object into items.
##
## `harvestable` is authored on the object: {"item": id, "amount": [min,
## max]}. Nothing here names a tree, a rock or wood -- what an object
## yields is whatever its JSON says, so a new harvestable is a data file.

## Rolls the amount. Owned here so a test can seed it.
var rng: RandomNumberGenerator = RandomNumberGenerator.new()


## What is wrong with a `harvestable` value, or "" if nothing is.
##
## Takes a Variant because that is what content hands over: the schema
## guarantees only that the field is a Dictionary. Amounts may be the
## whole-number floats JSON produces. The item must be real content of
## the item category -- a yield into an id nothing defines would destroy
## the object and credit something the build cannot name.
static func yield_error(harvestable: Variant, registry: ContentRegistry) -> String:
	if not (harvestable is Dictionary):
		return "harvestable is not an object"
	var h: Dictionary = harvestable

	var item: Variant = h.get("item")
	if not (item is String) or (item as String).is_empty():
		return "harvestable.item is not a string id"
	var item_id: String = item
	var item_numeric: int = registry.numeric_of(item_id)
	if item_numeric == ContentRegistry.ID_UNKNOWN or registry.is_placeholder(item_numeric):
		return "harvestable.item '%s' is not in this build" % item_id
	if str(registry.def_of(item_numeric).get("category", "")) != "item":
		return "harvestable.item '%s' is not an item" % item_id

	var amount: Variant = h.get("amount")
	if not (amount is Array) or (amount as Array).size() != 2:
		return "harvestable.amount is not [min, max]"
	var bounds: Array = amount
	for v: Variant in bounds:
		if not _is_whole(v):
			return "harvestable.amount holds a value that is not a whole number"
	var lo: int = roundi(float(bounds[0]))
	var hi: int = roundi(float(bounds[1]))
	if lo < 1:
		return "harvestable.amount minimum is below 1"
	if hi < lo:
		return "harvestable.amount maximum is below its minimum"
	return ""


static func _is_whole(v: Variant) -> bool:
	if not (v is int or v is float):
		return false
	return is_equal_approx(float(v), roundf(float(v)))
