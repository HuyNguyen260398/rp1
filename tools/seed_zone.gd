extends SceneTree
## Writes the first draft of data/zone/home/. Build-time only, never shipped.
##
##   ./tools/godot.sh --headless --path . -s tools/seed_zone.gd
##
## DELETED at the end of Phase 4a. Its output is the source of truth: once
## the PNGs are committed, edit them in a pixel editor, not by editing this.

const OUT_DIR: String = "res://data/zone/home"

const GRASS: Color = Color8(0, 255, 0)
const WATER: Color = Color8(0, 0, 255)
const EMPTY: Color = Color8(0, 0, 0)
const OAK: Color = Color8(0, 128, 0)

const SIZE: Vector2i = Vector2i(8, 8)


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)

	var terrain: Image = _filled(GRASS)
	terrain.set_pixel(5, 5, WATER)
	terrain.set_pixel(6, 5, WATER)
	terrain.set_pixel(5, 6, WATER)
	terrain.set_pixel(6, 6, WATER)

	var object: Image = _filled(EMPTY)
	object.set_pixel(2, 2, OAK)

	# Stage 1 renders flat. The column is carried and persisted from day one
	# because adding one to a save format later is painful.
	var height: Image = _filled(EMPTY)

	var failures: int = 0
	failures += _save(terrain, "terrain.png")
	failures += _save(object, "object.png")
	failures += _save(height, "height.png")

	if failures > 0:
		printerr("seed_zone: %d file(s) failed to write" % failures)
		quit(1)
		return
	print("seed_zone: wrote a %dx%d zone to %s" % [SIZE.x, SIZE.y, OUT_DIR])
	quit(0)


func _filled(c: Color) -> Image:
	var img: Image = Image.create_empty(SIZE.x, SIZE.y, false, Image.FORMAT_RGBA8)
	img.fill(c)
	return img


func _save(img: Image, file_name: String) -> int:
	var err: int = img.save_png(OUT_DIR.path_join(file_name))
	if err != OK:
		printerr("seed_zone: cannot write %s (error %d)" % [file_name, err])
		return 1
	return 0
