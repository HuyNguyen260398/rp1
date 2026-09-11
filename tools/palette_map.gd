class_name PaletteMap
extends RefCounted
## Maps arbitrary colours onto the fixed Apollo palette.
##
## Build-time only. Nothing in the running game loads this -- it exists so
## that imported art can be re-derived onto the palette by a tool rather
## than by hand, which is what makes docs/palette.md a constraint instead
## of a style guide.
##
## Distance is Euclidean in OKLab, not RGB. RGB distance picks visibly
## wrong shades in dark greens and blues, which are precisely the ramps
## this game spends most of its pixels in -- an Elin meadow screenshot
## measured 85% Green.

## Alpha at or above this becomes opaque; below becomes fully transparent.
## Under project-wide Nearest filtering, partial alpha has no meaning.
const ALPHA_THRESHOLD: int = 128

var _colours: PackedColorArray = PackedColorArray()
var _labs: Array[Vector3] = []
var _ramp_by_index: PackedStringArray = PackedStringArray()
var _exact: Dictionary = {}    ## hex string -> true
var _memo: Dictionary = {}     ## hex string -> Color
var _overrides: Dictionary = {}  ## source hex -> Color
var _report: Dictionary = {}   ## source hex -> count, for the last quantize


func size() -> int:
	return _colours.size()


func load_palette(path: String) -> PackedStringArray:
	var errs: PackedStringArray = PackedStringArray()
	if not FileAccess.file_exists(path):
		errs.append("palette not found: %s" % path)
		return errs
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		errs.append("cannot open palette: %s" % path)
		return errs
	var text: String = f.get_as_text()
	f.close()

	var parser: JSON = JSON.new()
	if parser.parse(text) != OK:
		errs.append("palette is not valid JSON: %s at line %d" % [
			parser.get_error_message(), parser.get_error_line()])
		return errs
	var data: Variant = parser.data
	if typeof(data) != TYPE_DICTIONARY or not data.has("ramps"):
		errs.append("palette has no 'ramps' object")
		return errs

	# Ramp names sorted, so index assignment is stable regardless of how the
	# JSON parser orders keys. Two runs must produce identical output.
	var ramp_names: Array = data["ramps"].keys()
	ramp_names.sort()
	for ramp: String in ramp_names:
		for hexs: String in data["ramps"][ramp]:
			var c: Color = Color(hexs)
			_colours.append(c)
			_labs.append(_to_oklab(c))
			_ramp_by_index.append(ramp)
			_exact[c.to_html(false)] = true
	if _colours.is_empty():
		errs.append("palette contains no colours")
	return errs


## Pins specific source colours to a chosen palette step.
##
## Nearest-colour honours palette.md section 5 and can violate section 3 by
## mixing ramps within one sprite, which is what produces mud. Rather than
## a ramp-aware heuristic -- which breaks on any multi-coloured sprite, and
## a tree is a trunk plus a canopy -- the mapping stays simple and a human
## pins the exceptions. Each one is a reviewable line with its reason
## attached, and survives re-quantization; hand-editing the output PNG
## instead would hide the decision in a binary and lose it on the next run.
##
## A missing file is not an error. Having no overrides is the healthy case.
func load_overrides(path: String) -> PackedStringArray:
	var errs: PackedStringArray = PackedStringArray()
	if not FileAccess.file_exists(path):
		return errs
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		errs.append("cannot open overrides: %s" % path)
		return errs
	var text: String = f.get_as_text()
	f.close()

	var parser: JSON = JSON.new()
	if parser.parse(text) != OK:
		errs.append("overrides are not valid JSON: %s at line %d" % [
			parser.get_error_message(), parser.get_error_line()])
		return errs
	var entries: Variant = parser.data.get("overrides", []) if typeof(parser.data) == TYPE_DICTIONARY else []

	for e: Variant in entries:
		if typeof(e) != TYPE_DICTIONARY:
			errs.append("override is not an object: %s" % str(e))
			continue
		var src: String = str(e.get("from", "")).to_lower()
		var dst: String = str(e.get("to", "")).to_lower()
		if src.is_empty() or dst.is_empty():
			errs.append("override needs 'from' and 'to': %s" % str(e))
			continue
		# The reason is required. An override with no explanation is
		# indistinguishable from a mistake six months later.
		if str(e.get("why", "")).strip_edges().is_empty():
			errs.append("override %s -> %s has no 'why'" % [src, dst])
			continue
		# An override chooses between palette steps. It is never a way to
		# smuggle a forty-seventh colour past the gate.
		if not _exact.has(dst):
			errs.append("override target #%s is not a palette colour" % dst)
			continue
		_overrides[src] = Color(dst)

	# Overrides change what nearest() returns, so anything already memoised
	# is stale.
	_memo.clear()
	return errs


## Exact membership. Distinct from nearest(): the gate asks whether a pixel
## is literally on the palette, not what it would round to.
func has_colour(c: Color) -> bool:
	return _exact.has(c.to_html(false))


func nearest(c: Color) -> Color:
	var key: String = c.to_html(false)
	if _overrides.has(key):
		return _overrides[key]
	if _memo.has(key):
		return _memo[key]
	var out: Color = _colours[_nearest_index(c)]
	_memo[key] = out
	return out


func ramp_of(c: Color) -> String:
	return _ramp_by_index[_nearest_index(c)]


## Cuts a chroma-key colour and named rectangles out of a source crop.
##
## Two things the packs make necessary, both properties of the source
## rather than of the palette, so they happen before quantize_image().
##
## The Bukket character templates are 24-bit BMPs with no alpha channel at
## all; their background is a white chroma key. And every 32x64 frame in
## them carries a 2x8 black registration tick at frame-local (30, 56) --
## no 32x64 window of the sheet avoids one, and it cannot be keyed by
## colour because it is the same black as the eyes. So the manifest names
## the rectangle.
##
## Both decisions live in tools/import_manifest.json, next to the rect
## they belong to, for the same reason overrides do: a decision recorded
## in reviewable JSON survives a re-run, and one made by editing the
## output PNG does not.
##
## Static, and returns a new image; the input is untouched.
static func cut_transparent(img: Image, key_hex: String, erase: Array) -> Image:
	var out: Image = img.duplicate()
	out.convert(Image.FORMAT_RGBA8)
	if not key_hex.is_empty():
		var key: String = key_hex.to_lower()
		for y: int in range(out.get_height()):
			for x: int in range(out.get_width()):
				var c: Color = out.get_pixel(x, y)
				if c.a8 > 0 and Color(c.r, c.g, c.b, 1.0).to_html(false) == key:
					out.set_pixel(x, y, Color(0.0, 0.0, 0.0, 0.0))
	var bounds: Rect2i = Rect2i(Vector2i.ZERO, out.get_size())
	for r: Variant in erase:
		# A rect running off the edge is a manifest typo, not a crash.
		var rect: Rect2i = bounds.intersection(
			Rect2i(int(r[0]), int(r[1]), int(r[2]), int(r[3])))
		for y: int in range(rect.position.y, rect.end.y):
			for x: int in range(rect.position.x, rect.end.x):
				out.set_pixel(x, y, Color(0.0, 0.0, 0.0, 0.0))
	return out


## Maps every visible pixel onto the palette and binarizes alpha.
##
## Colours are mapped through nearest(), which is memoised by hex, so the
## work is proportional to the number of DISTINCT colours rather than to
## the pixel count -- pixel art is flat, and a sheet has a few dozen
## colours against hundreds of thousands of pixels. It also guarantees
## that identical source colours map identically, so a flat region can
## never come out speckled.
##
## Returns a new image; the input is untouched.
func quantize_image(img: Image) -> Image:
	_report.clear()
	var w: int = img.get_width()
	var h: int = img.get_height()
	var out: Image = Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y: int in range(h):
		for x: int in range(w):
			var src: Color = img.get_pixel(x, y)
			# Under project-wide Nearest filtering partial alpha has no
			# meaning, and "alpha is 0 or 255, never between" is an
			# invariant the palette gate can actually check.
			if src.a8 < ALPHA_THRESHOLD:
				out.set_pixel(x, y, Color(0.0, 0.0, 0.0, 0.0))
				continue
			var opaque: Color = Color(src.r, src.g, src.b, 1.0)
			var key: String = opaque.to_html(false)
			_report[key] = int(_report.get(key, 0)) + 1
			out.set_pixel(x, y, nearest(opaque))
	return out


## What the last quantize_image() call did, biggest source colour first.
## This is how a mapping that crosses a ramp gets noticed -- see
## load_overrides().
func last_report() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for src: String in _report:
		var c: Color = Color(src)
		rows.append({
			"from": src,
			"to": nearest(c).to_html(false),
			"ramp": ramp_of(c),
			"count": _report[src],
		})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		# Count descending, then hex ascending so ties are deterministic
		# and two runs produce identical reports.
		if a["count"] != b["count"]:
			return a["count"] > b["count"]
		return a["from"] < b["from"])
	return rows


func _nearest_index(c: Color) -> int:
	var target: Vector3 = _to_oklab(c)
	var best: int = 0
	var best_d: float = INF
	for i: int in range(_labs.size()):
		# Squared distance: monotonic in distance, and skips a sqrt per
		# comparison across 46 colours per distinct source colour.
		var d: float = (_labs[i] - target).length_squared()
		if d < best_d:
			best_d = d
			best = i
	return best


## sRGB -> OKLab. Björn Ottosson's matrices, unchanged.
##
## OKLab is perceptually uniform, so Euclidean distance in it corresponds
## to perceived difference. The cube roots are safe: linear components are
## never negative for a valid colour.
static func _to_oklab(c: Color) -> Vector3:
	var lin: Color = c.srgb_to_linear()
	var l: float = 0.4122214708 * lin.r + 0.5363325363 * lin.g + 0.0514459929 * lin.b
	var m: float = 0.2119034982 * lin.r + 0.6806995451 * lin.g + 0.1073969566 * lin.b
	var s: float = 0.0883024619 * lin.r + 0.2817188376 * lin.g + 0.6299787005 * lin.b
	var l_: float = pow(l, 1.0 / 3.0)
	var m_: float = pow(m, 1.0 / 3.0)
	var s_: float = pow(s, 1.0 / 3.0)
	return Vector3(
		0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_,
		1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_,
		0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_)
