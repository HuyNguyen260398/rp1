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


## Whether `cmd` may happen, without making it happen. The cursor asks
## this every frame, so it must never write.
static func check(
	cmd: BuildCommand, zone: Zone, inventory: Inventory, registry: ContentRegistry
) -> BuildResult:
	if not zone.in_bounds(cmd.tile):
		return BuildResult.refusal(BuildResult.OUT_OF_BOUNDS)
	if not LAYERS.has(cmd.layer):
		return BuildResult.refusal(
			BuildResult.BAD_COMMAND, "unknown layer '%s'" % cmd.layer)
	if cmd.action == BuildCommand.PLACE:
		return _check_place(cmd, zone, inventory, registry)
	return BuildResult.refusal(
		BuildResult.BAD_COMMAND, "unknown action '%s'" % cmd.action)


## Makes `cmd` happen if check() accepts it.
##
## Every refusal returns before the first write, so a refused command
## changes no tile, no flag and no count. The tile is written through
## Zone.set_object, which advances the chunk's version: that is how the
## renderer, the collider and the save each learn of it, with nothing
## here knowing they exist.
static func apply(
	cmd: BuildCommand, zone: Zone, inventory: Inventory, registry: ContentRegistry
) -> BuildResult:
	var result: BuildResult = check(cmd, zone, inventory, registry)
	if not result.ok:
		return result
	for item_id: String in result.cost:
		# Cannot refuse: check() proved the whole cost affordable.
		var _spent: bool = inventory.remove(item_id, int(result.cost[item_id]))
	zone.set_object(cmd.tile, registry.numeric_of(cmd.content_id))
	# Walkability owns the walkable rule; setting the flag byte by hand
	# would also clobber FLAG_BLOCKS_LIGHT, which shares it.
	var _changed: int = Walkability.recompute_chunk(
		zone.get_chunk(Coords.world_to_chunk(cmd.tile)), registry)
	return result


static func _check_place(
	cmd: BuildCommand, zone: Zone, inventory: Inventory, registry: ContentRegistry
) -> BuildResult:
	var numeric: int = registry.numeric_of(cmd.content_id)
	if numeric == ContentRegistry.ID_UNKNOWN or registry.is_placeholder(numeric):
		return BuildResult.refusal(BuildResult.NOT_PLACEABLE)
	var def: Dictionary = registry.def_of(numeric)
	if str(def.get("category", "")) != cmd.layer or not def.has("cost"):
		return BuildResult.refusal(BuildResult.NOT_PLACEABLE)
	var problem: String = cost_error(def["cost"], registry)
	if problem != "":
		return BuildResult.refusal(
			BuildResult.BAD_COST, "%s: %s" % [cmd.content_id, problem])

	if zone.get_object(cmd.tile) != ContentRegistry.ID_UNKNOWN:
		return BuildResult.refusal(BuildResult.OCCUPIED)
	# With no object on the tile, its walkable flag is the terrain's
	# answer alone: water and unpainted void are not ground to build on.
	if not zone.is_walkable(cmd.tile):
		return BuildResult.refusal(BuildResult.BAD_GROUND)
	if bool(def.get("blocks_movement", false)) and _entity_on(zone, cmd.tile, registry):
		return BuildResult.refusal(BuildResult.BLOCKED_BY_ENTITY)

	var cost: Dictionary = cost_of(def)
	if not inventory.can_afford(cost):
		return BuildResult.refusal(BuildResult.CANT_AFFORD)
	return BuildResult.accepted(cmd.content_id, cost)


## Whether any entity's body overlaps `tile`. A solid dropped across a
## body would trap it inside something it cannot walk out of.
static func _entity_on(zone: Zone, tile: Vector2i, registry: ContentRegistry) -> bool:
	var tile_rect: Rect2 = Rect2(Vector2(tile), Vector2.ONE)
	for id: int in zone.entities.ids():
		var def: Dictionary = registry.def_of(zone.entities.get_type_id(id))
		var body: Vector2 = Vector2(
			float(def.get("body_width", AnimalSystem.DEFAULT_BODY.x)),
			float(def.get("body_height", AnimalSystem.DEFAULT_BODY.y)))
		if tile_rect.intersects(
				MovementSystem.body_rect(zone.entities.get_position(id), body)):
			return true
	return false
