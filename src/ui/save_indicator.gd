class_name SaveIndicator
extends Control
## "Saved", briefly, in a corner.
##
## No test: it holds no rules, exactly like the Phase 5 menus. What it
## reports -- whether a save happened -- is GameSession's business and is
## tested there.

const HOLD_SECONDS: float = 1.2
const FADE_SECONDS: float = 0.6

var _label: Label = null
var _tween: Tween = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_label = Label.new()
	_label.text = "Saved"
	_label.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	_label.position = Vector2(-96.0, 16.0)
	_label.modulate.a = 0.0
	add_child(_label)


func flash() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_label.modulate.a = 1.0
	_tween = create_tween()
	_tween.tween_interval(HOLD_SECONDS)
	_tween.tween_property(_label, "modulate:a", 0.0, FADE_SECONDS)
