class_name ControlsHint
extends Control
## WASD / Esc, once per player, ever.
##
## Exists for the clean-machine test, where there is nobody to ask which
## keys move. Whether it has been shown is settings.json's business; this
## node only draws it.

const HOLD: float = 6.0
const FADE_OUT: float = 1.5

var _label: Label = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_label = Label.new()
	_label.text = "WASD or arrows to move    Esc to pause"
	_label.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_label.position = Vector2(0.0, -48.0)
	_label.modulate.a = 0.0
	add_child(_label)


func show_once() -> void:
	_label.modulate.a = 1.0
	var tween: Tween = create_tween()
	tween.tween_interval(HOLD)
	tween.tween_property(_label, "modulate:a", 0.0, FADE_OUT)
