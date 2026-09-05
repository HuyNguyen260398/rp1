extends SceneTree
## Captures a PNG of the main scene.
##
## Requires a real rendering driver: --headless uses a dummy driver with no
## framebuffer, so this must run windowed (or under xvfb-run on Linux CI).
##
##   ./tools/godot.sh --path . -s tools/screenshot.gd -- --out=shot.png

const DEFAULT_OUT: String = "user://screenshot.png"
const WARMUP_FRAMES: int = 10

var _frames: int = 0
var _out: String = DEFAULT_OUT


func _init() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.substr(6)
	var scene: PackedScene = load("res://scenes/main.tscn")
	root.add_child(scene.instantiate())


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < WARMUP_FRAMES:
		return false

	var image: Image = root.get_texture().get_image()
	if image == null:
		printerr("screenshot: no framebuffer. Are you running --headless?")
		quit(1)
		return true

	var err: int = image.save_png(_out)
	if err != OK:
		printerr("screenshot: save_png failed (error %d)" % err)
		quit(1)
		return true

	print("wrote ", _out)
	quit(0)
	return true
