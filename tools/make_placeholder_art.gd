extends SceneTree
## Generates the Phase 3a debug swatches.
##
## These are NOT art. They are flat blocks in obviously-synthetic colours,
## sized to match what the content JSON declares, and they are deleted
## wholesale when the real tileset is imported in Phase 3b.
##
## Colours are deliberately off-palette: docs/palette.md fixes the palette
## as Apollo and exempts these files by name, precisely so a throwaway
## swatch never gets mistaken for a considered choice.

const SWATCHES: Array[Dictionary] = [
	{"path": "res://assets/tiles/grass.png", "size": Vector2i(32, 32), "color": Color(0.36, 0.60, 0.34)},
	{"path": "res://assets/tiles/water.png", "size": Vector2i(32, 32), "color": Color(0.25, 0.45, 0.72)},
	{"path": "res://assets/objects/oak_tree.png", "size": Vector2i(32, 48), "color": Color(0.45, 0.32, 0.22)},
]


func _init() -> void:
	DirAccess.make_dir_recursive_absolute("res://assets/objects")
	for s: Dictionary in SWATCHES:
		var size: Vector2i = s["size"]
		var img: Image = Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
		img.fill(s["color"])
		# A one-pixel darker border makes tile boundaries visible on screen,
		# so "did every cell get painted?" is answerable by looking.
		var edge: Color = Color(s["color"]).darkened(0.35)
		for x: int in range(size.x):
			img.set_pixel(x, 0, edge)
			img.set_pixel(x, size.y - 1, edge)
		for y: int in range(size.y):
			img.set_pixel(0, y, edge)
			img.set_pixel(size.x - 1, y, edge)
		var err: int = img.save_png(s["path"])
		if err != OK:
			printerr("failed to write %s: %d" % [s["path"], err])
			quit(1)
			return
		print("wrote %s (%dx%d)" % [s["path"], size.x, size.y])
	quit(0)
