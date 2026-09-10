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


## Exact membership. Distinct from nearest(): the gate asks whether a pixel
## is literally on the palette, not what it would round to.
func has_colour(c: Color) -> bool:
	return _exact.has(c.to_html(false))


func nearest(c: Color) -> Color:
	var key: String = c.to_html(false)
	if _memo.has(key):
		return _memo[key]
	var out: Color = _colours[_nearest_index(c)]
	_memo[key] = out
	return out


func ramp_of(c: Color) -> String:
	return _ramp_by_index[_nearest_index(c)]


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
