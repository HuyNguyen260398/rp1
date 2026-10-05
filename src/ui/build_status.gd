class_name BuildStatus
extends Control
## What build mode is about to place, what it costs, and what is held.
##
## One line of text until the palette and the inventory display exist.
## The node holds no rules, like the menus; line() is its one function
## with something to get wrong, and it is tested.

const GAP: String = "    "
const HINT: String = "Left click place    Right click remove    Wheel select    B exit"

var _label: Label = null


## The readout for `content_id`, or for nothing when it is empty. Costs
## are worded from the content, so a retuned or new placeable reads
## correctly with no change here.
static func line(
	content_id: String, inventory: Inventory, registry: ContentRegistry
) -> String:
	if content_id.is_empty():
		return GAP.join(PackedStringArray(["BUILD", "nothing to build"]))
	var def: Dictionary = registry.def_of(registry.numeric_of(content_id))
	var parts: PackedStringArray = ["BUILD", str(def.get("display_name", content_id))]
	if BuildSystem.cost_error(def.get("cost"), registry) != "":
		parts.append("cost unreadable")
		return GAP.join(parts)
	var cost: Dictionary = BuildSystem.cost_of(def)
	if cost.is_empty():
		parts.append("free")
	var item_ids: Array = cost.keys()
	item_ids.sort()
	for item_id: String in item_ids:
		var item: Dictionary = registry.def_of(registry.numeric_of(item_id))
		parts.append("%s %d (have %d)" % [
			str(item.get("display_name", item_id)),
			int(cost[item_id]), inventory.count_of(item_id)])
	return GAP.join(parts)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	# The clicks under this text belong to the build cursor.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false

	_label = Label.new()
	_label.add_theme_color_override("font_color", UiTheme.TEXT)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_label.position.y = 12.0
	add_child(_label)


func show_line(text: String) -> void:
	_label.text = "%s\n%s" % [text, HINT]
	visible = true
