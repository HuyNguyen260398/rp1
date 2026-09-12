extends SceneTree
## Emits a labelled swatch image for hand-editing a zone's maps.
##
##   ./tools/godot.sh --headless --path . -s tools/zone_legend.gd
##
## Output is build/zone_legend.png, which is a build artefact and is not
## committed. Open it beside the map in a pixel editor and pick colours
## from it, so a tile id never has to be typed from memory.

const ZONE_DOC: String = "res://data/zone/home/zone.json"
const OUT: String = "res://build/zone_legend.png"

const SWATCH: int = 24
const LABEL_WIDTH: int = 160
const ROW_HEIGHT: int = 28


func _init() -> void:
	var f: FileAccess = FileAccess.open(ZONE_DOC, FileAccess.READ)
	if f == null:
		printerr("zone_legend: cannot open %s" % ZONE_DOC)
		quit(1)
		return
	var parser: JSON = JSON.new()
	var err: int = parser.parse(f.get_as_text())
	f.close()
	if err != OK:
		printerr("zone_legend: %s is not valid JSON" % ZONE_DOC)
		quit(1)
		return

	var legend: Dictionary = (parser.data as Dictionary).get("legend", {})
	var rows: Array = []
	for layer: String in legend:
		var entries: Dictionary = legend[layer]
		var hexes: Array = entries.keys()
		hexes.sort()
		for hex: String in hexes:
			var name: Variant = entries[hex]
			rows.append([layer, hex, "(empty)" if name == null else str(name)])

	if rows.is_empty():
		printerr("zone_legend: no legend entries found")
		quit(1)
		return

	var img: Image = Image.create_empty(
		LABEL_WIDTH + SWATCH + 8, rows.size() * ROW_HEIGHT, false, Image.FORMAT_RGBA8)
	img.fill(Color8(24, 24, 24))
	for n: int in range(rows.size()):
		var hex: String = rows[n][1]
		var c: Color = Color.from_string("#" + hex, Color.MAGENTA)
		img.fill_rect(Rect2i(4, n * ROW_HEIGHT + 2, SWATCH, SWATCH), c)

	DirAccess.make_dir_recursive_absolute("res://build")
	var save_err: int = img.save_png(OUT)
	if save_err != OK:
		printerr("zone_legend: cannot write %s (error %d)" % [OUT, save_err])
		quit(1)
		return

	# The image carries the colours; the console carries the names. Drawing
	# text into an Image needs a font and a viewport, which is a lot of
	# machinery for a build-time crib sheet.
	print("zone_legend: %d entries -> %s" % [rows.size(), OUT])
	for n: int in range(rows.size()):
		print("  row %2d  %-8s #%s  %s" % [n, rows[n][0], rows[n][1], rows[n][2]])
	quit(0)
