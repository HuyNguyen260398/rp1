class_name TitleCard
extends Control
## The zone's name, on arrival.
##
## No test, for the same reason as the other two: no rules. Whether the
## name is right is ZoneLoader's and SaveManager's business.

const FADE_IN: float = 0.8
const HOLD: float = 2.0
const FADE_OUT: float = 1.2

var _label: Label = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_label = Label.new()
	_label.add_theme_font_size_override("font_size", UiTheme.TITLE_FONT_SIZE)
	_label.add_theme_color_override("font_color", UiTheme.TEXT)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_label.position = Vector2(0.0, 64.0)
	_label.modulate.a = 0.0
	add_child(_label)


func show_zone(zone_name: String) -> void:
	if zone_name == "":
		return
	_label.text = zone_name
	_label.modulate.a = 0.0
	var tween: Tween = create_tween()
	tween.tween_property(_label, "modulate:a", 1.0, FADE_IN)
	tween.tween_interval(HOLD)
	tween.tween_property(_label, "modulate:a", 0.0, FADE_OUT)
