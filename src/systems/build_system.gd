class_name BuildSystem
extends RefCounted
## Decides whether an edit to the world may happen, and makes it.
##
## What can be built, and what it costs, is authored on the content:
## {"cost": {item id: amount}}. Nothing here names a wall or wood -- a new
## placeable is a data file. All static: this owns no state.

## The layers that can be edited. A layer's name is the content category
## that lives on it, so a definition says where it goes by what it is.
const LAYERS: PackedStringArray = ["object"]


## What is wrong with a `cost` value, or "" if nothing is.
##
## Takes a Variant because that is what content hands over: the schema
## guarantees only that the field is a Dictionary. Amounts may be the
## whole-number floats JSON produces. Every key must be real content of
## the item category -- a cost in an id nothing defines could never be
## paid, and its refund would credit something the build cannot name.
## An empty cost is valid: the thing is free.
static func cost_error(cost: Variant, registry: ContentRegistry) -> String:
	if not (cost is Dictionary):
		return "cost is not an object"
	var entries: Dictionary = cost
	for key: Variant in entries:
		var item_id: String = str(key)
		var item_numeric: int = registry.numeric_of(item_id)
		if item_numeric == ContentRegistry.ID_UNKNOWN or registry.is_placeholder(item_numeric):
			return "cost names '%s', which is not in this build" % item_id
		if str(registry.def_of(item_numeric).get("category", "")) != "item":
			return "cost names '%s', which is not an item" % item_id
		var amount: Variant = entries[key]
		if not (amount is int or amount is float) \
				or not is_equal_approx(float(amount), roundf(float(amount))):
			return "cost of '%s' is not a whole number" % item_id
		if roundi(float(amount)) < 1:
			return "cost of '%s' is below 1" % item_id
	return ""


## The cost of `def` as item id -> whole amount. Only meaningful once
## cost_error() has returned "" for it.
static func cost_of(def: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var entries: Dictionary = def.get("cost", {})
	for key: Variant in entries:
		out[str(key)] = roundi(float(entries[key]))
	return out


## Every string id that can be placed, sorted. Content with a malformed
## cost is still listed: placing it refuses and names the fault, which is
## better than it silently vanishing from the list.
static func placeables(registry: ContentRegistry) -> PackedStringArray:
	var out: PackedStringArray = []
	for string_id: String in registry.all_string_ids():
		var numeric: int = registry.numeric_of(string_id)
		if registry.is_placeholder(numeric):
			continue
		var def: Dictionary = registry.def_of(numeric)
		if def.has("cost") and LAYERS.has(str(def.get("category", ""))):
			out.append(string_id)
	out.sort()
	return out
