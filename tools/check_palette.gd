extends SceneTree
## The palette gate: every pixel in assets/ is an Apollo colour.
##
## docs/palette.md section 1 states the rule and admits it was "honoured by
## hand" until this existed. A palette that governs only the art we happen
## to remember to check is a style guide, not a constraint.
##
## There is deliberately NO exemption mechanism. The Phase 3a and 3b debug
## swatches were the only exempt files and Phase 3c deletes them; a general
## exemption list is how the rule decays back into a suggestion.

const PALETTE: String = "res://tools/palette/apollo.json"
const MANIFEST: String = "res://tools/import_manifest.json"
const ASSET_ROOT: String = "res://assets"
const SOURCE_DIR: String = "res://assets/_source"

## Offending pixels reported per file before truncating. A wholly
## off-palette image would otherwise print a million lines.
const MAX_REPORTED: int = 8

var _failures: int = 0


func _init() -> void:
	var map: PaletteMap = PaletteMap.new()
	var errs: PackedStringArray = map.load_palette(PALETTE)
	if not errs.is_empty():
		for e: String in errs:
			printerr("palette: %s" % e)
		quit(2)
		return

	var declared: Dictionary = _manifest_outputs()
	var pngs: PackedStringArray = PackedStringArray()
	_collect(ASSET_ROOT, pngs)
	pngs.sort()

	for path: String in pngs:
		_check_declared(path, declared)
		_check_pixels(path, map)

	if _failures > 0:
		printerr("")
		printerr("Palette gate: %d problem(s). Every pixel in assets/ must be one of" % _failures)
		printerr("the 46 Apollo colours in docs/palette.md, with alpha 0 or 255.")
		printerr("Fix by re-running the pipeline, not by editing a PNG:")
		printerr("  ./tools/godot.sh --headless --path . -s tools/quantize.gd")
		printerr("If a colour is landing in the wrong ramp, pin it in")
		printerr("tools/palette_overrides.json and re-run.")
		quit(1)
		return
	print("Palette: OK (%d file(s))" % pngs.size())
	quit(0)


func _manifest_outputs() -> Dictionary:
	var out: Dictionary = {}
	if not FileAccess.file_exists(MANIFEST):
		return out
	var f: FileAccess = FileAccess.open(MANIFEST, FileAccess.READ)
	if f == null:
		return out
	var parser: JSON = JSON.new()
	var err: int = parser.parse(f.get_as_text())
	f.close()
	if err != OK:
		return out
	for s: Variant in parser.data.get("slices", []):
		out["res://%s" % str(s["out"])] = true
	return out


func _collect(dir_path: String, into: PackedStringArray) -> void:
	# assets/_source/ holds art as downloaded. It is off-palette by
	# definition -- re-quantizing it is the whole point of the pipeline.
	if dir_path == SOURCE_DIR:
		return
	var d: DirAccess = DirAccess.open(dir_path)
	if d == null:
		return
	d.list_dir_begin()
	var name: String = d.get_next()
	while name != "":
		if name.begins_with("."):
			name = d.get_next()
			continue
		var full: String = "%s/%s" % [dir_path, name]
		if d.current_is_dir():
			_collect(full, into)
		elif name.get_extension().to_lower() == "png":
			into.append(full)
		name = d.get_next()
	d.list_dir_end()


## Art must be reproducible, not merely on-palette. A hand-made PNG dropped
## into assets/ could pass the pixel check and still be underivable.
func _check_declared(path: String, declared: Dictionary) -> void:
	if declared.is_empty():
		return
	if not declared.has(path):
		printerr("%s: not produced by tools/import_manifest.json" % path)
		_failures += 1


func _check_pixels(path: String, map: PaletteMap) -> void:
	# Image.load_from_file reads the PNG on disk. load() would hand back the
	# engine's *imported* copy instead, which is a compressed texture whose
	# pixels are no longer the ones a reviewer sees in the file -- the gate
	# has to check what is committed. The engine warns that this "will not
	# work on export", which is correct and irrelevant: this only ever runs
	# under -s at build time.
	var img: Image = Image.load_from_file(path)
	if img == null:
		printerr("%s: cannot be read as an image" % path)
		_failures += 1
		return
	var bad_colour: int = 0
	var bad_alpha: int = 0
	for y: int in range(img.get_height()):
		for x: int in range(img.get_width()):
			var c: Color = img.get_pixel(x, y)
			if c.a8 != 0 and c.a8 != 255:
				bad_alpha += 1
				if bad_alpha <= MAX_REPORTED:
					printerr("%s: (%d,%d) alpha %d is neither 0 nor 255" % [path, x, y, c.a8])
				continue
			if c.a8 == 0:
				continue
			if not map.has_colour(Color(c.r, c.g, c.b, 1.0)):
				bad_colour += 1
				if bad_colour <= MAX_REPORTED:
					printerr("%s: (%d,%d) #%s is not an Apollo colour (nearest #%s)" % [
						path, x, y, Color(c.r, c.g, c.b, 1.0).to_html(false),
						map.nearest(Color(c.r, c.g, c.b, 1.0)).to_html(false)])
	if bad_colour > MAX_REPORTED:
		printerr("%s: ... and %d more off-palette pixel(s)" % [path, bad_colour - MAX_REPORTED])
	if bad_alpha > MAX_REPORTED:
		printerr("%s: ... and %d more partial-alpha pixel(s)" % [path, bad_alpha - MAX_REPORTED])
	if bad_colour > 0 or bad_alpha > 0:
		_failures += 1
