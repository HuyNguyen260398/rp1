class_name InventoryCodec
extends RefCounted
## inventory.json, beside meta.json in the save root.
##
## JSON for the same reason meta.json is: small, cold, and worth reading
## with `cat`. A file of its own rather than a field in a binary codec, so
## a save written before inventories existed simply has no file and opens
## as empty, with no migration.
##
## The codec never consults the ContentRegistry. Keys are string ids and
## pass through verbatim, so an item this build does not ship keeps its
## count. A count that is not a whole, non-negative number fails the
## decode instead of being clamped: a failed open offers the backup, while
## a silently emptied inventory is loss the player finds later.

const FORMAT_VERSION: int = 1


static func path_in(save_root: String) -> String:
	return save_root.path_join("inventory.json")


static func to_json_string(inv: Inventory) -> String:
	var items: Dictionary = {}
	for item_id: String in inv.item_ids():
		items[item_id] = inv.count_of(item_id)
	return JSON.stringify({
		"format_version": FORMAT_VERSION,
		"items": items,
	}, "  ", true)


static func from_json_string(text: String) -> DecodeResult:
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		return DecodeResult.failure("inventory.json: malformed JSON")
	if not (json.data is Dictionary):
		return DecodeResult.failure("inventory.json: top level is not an object")

	var doc: Dictionary = json.data
	var version: int = int(doc.get("format_version", FORMAT_VERSION))
	if version > FORMAT_VERSION:
		return DecodeResult.failure(
			"inventory.json: format_version %d is newer than this build supports (%d)"
			% [version, FORMAT_VERSION]
		)

	var items: Variant = doc.get("items", {})
	if not (items is Dictionary):
		return DecodeResult.failure("inventory.json: 'items' is not an object")

	var inv: Inventory = Inventory.new()
	for key: Variant in items:
		var item_id: String = str(key)
		var raw: Variant = (items as Dictionary)[key]
		if not (raw is int or raw is float) \
				or not is_equal_approx(float(raw), roundf(float(raw))) \
				or float(raw) < 0.0:
			return DecodeResult.failure(
				"inventory.json: count for '%s' is not a whole number >= 0" % item_id)
		var _added: bool = inv.add(item_id, int(raw))
	return DecodeResult.success(inv)
