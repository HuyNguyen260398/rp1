extends SceneTree
## Measures any image against Apollo. For docs/palette.md section 6.
##
##   ./tools/godot.sh --headless --path . -s tools/palette_report.gd -- <path> [x,y,w,h]
##
## The optional rect crops before measuring. A screenshot of a running game
## is mostly playfield and partly UI chrome, and chrome is flat dark grey:
## measuring the whole file reports a quarter of the image as Neutral and
## says nothing about the art direction. Crop to the playfield.
##
## Reference images are NOT committed (section 7 forbids copying Elin art
## into this project). Point this at one in docs/reference/, record the
## numbers in section 6, delete the image.

const PALETTE: String = "res://tools/palette/apollo.json"


func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.is_empty():
		printerr("usage: -s tools/palette_report.gd -- <image path>")
		quit(2)
		return
	var img: Image = Image.load_from_file(args[0])
	if img == null:
		printerr("cannot read %s" % args[0])
		quit(2)
		return
	if args.size() > 1:
		var n: PackedStringArray = args[1].split(",")
		if n.size() != 4:
			printerr("rect must be x,y,w,h -- got '%s'" % args[1])
			quit(2)
			return
		var want: Rect2i = Rect2i(int(n[0]), int(n[1]), int(n[2]), int(n[3]))
		var rect: Rect2i = Rect2i(Vector2i.ZERO, img.get_size()).intersection(want)
		if rect.size.x <= 0 or rect.size.y <= 0:
			printerr("rect %s does not overlap the image" % str(want))
			quit(2)
			return
		img = img.get_region(rect)

	var map: PaletteMap = PaletteMap.new()
	var errs: PackedStringArray = map.load_palette(PALETTE)
	if not errs.is_empty():
		printerr("palette: %s" % ", ".join(errs))
		quit(2)
		return

	var _q: Image = map.quantize_image(img)
	var rows: Array[Dictionary] = map.last_report()
	var total: int = 0
	var ramps: Dictionary = {}
	for r: Dictionary in rows:
		total += int(r["count"])
		ramps[r["ramp"]] = int(ramps.get(r["ramp"], 0)) + int(r["count"])

	print("%s  %dx%d  %d distinct colours" % [
		args[0], img.get_width(), img.get_height(), rows.size()])
	print("ramp usage by pixel share:")
	var names: Array = ramps.keys()
	names.sort()
	for n: String in names:
		print("  %-8s %5.1f%%" % [n, 100.0 * float(ramps[n]) / float(total)])
	quit(0)
