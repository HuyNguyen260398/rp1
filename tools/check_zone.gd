extends SceneTree
## The zone gate: every authored zone under data/zone/ loads clean and is
## fit to play.
##
## This calls ZoneLoader rather than reading the PNGs itself. A gate with
## its own copy of the format is a gate that eventually disagrees with the
## game, and the disagreement always surfaces as a bug nobody can
## reproduce -- the same reasoning that has palette_report.gd reuse
## PaletteMap.
##
## The loader is deliberately forgiving at runtime: an unreadable map costs
## one layer, not the world. This is where that forgiveness stops.

const ZONE_ROOT: String = "res://data/zone"
const MAPS: PackedStringArray = ["terrain.png", "object.png", "height.png"]
const MAX_REPORTED: int = 8

var _failures: int = 0


func _init() -> void:
	var registry: ContentRegistry = ContentRegistry.new()
	var content_errors: PackedStringArray = registry.load_from_dir("res://data")
	if not content_errors.is_empty():
		for e: String in content_errors:
			printerr("content: %s" % e)
		printerr("Zone gate: content does not load, so no zone can be checked.")
		quit(2)
		return

	var dirs: PackedStringArray = DirAccess.get_directories_at(ZONE_ROOT)
	if dirs.is_empty():
		print("Zone gate: no zones under %s" % ZONE_ROOT)
		quit(0)
		return
	dirs.sort()

	for name: String in dirs:
		_check_zone(ZONE_ROOT.path_join(name), registry)

	if _failures > 0:
		printerr("")
		printerr("Zone gate: %d problem(s)." % _failures)
		printerr("A zone is data/zone/<id>/zone.json plus one PNG per tile column.")
		printerr("Colours are declared in the legend; every colour used must be")
		printerr("declared, every terrain tile must be painted, and the spawn must")
		printerr("be somewhere the player can stand. To see which colour is which:")
		printerr("  ./tools/godot.sh --headless --path . -s tools/zone_legend.gd")
		quit(1)
		return
	print("Zone gate: OK (%d zone(s))" % dirs.size())
	quit(0)


func _fail(message: String) -> void:
	printerr(message)
	_failures += 1


func _check_zone(dir: String, registry: ContentRegistry) -> void:
	var result: ZoneLoadResult = ZoneLoader.load_zone(dir, registry)

	# Rule: whatever the loader reports at runtime is a build failure here.
	# This covers unknown colours, malformed legend keys, wrong map sizes,
	# partial alpha, and any legend id or entity type the build cannot
	# resolve -- all of which the loader turns into placeholders and carries
	# on with, which is right in a shipped game and wrong in a commit.
	for e: String in result.errors:
		_fail("%s: %s" % [dir, e])

	if result.zone == null:
		_fail("%s: did not load at all" % dir)
		return

	_check_fully_painted(dir, result.zone)
	_check_spawn(dir, result)
	_check_import_modes(dir)
	_report_unused_legend(dir, result.zone, registry)


## An unpainted terrain tile is ID_UNKNOWN, which Walkability treats as void
## rather than floor: a hole in the world the player cannot cross and
## nothing logs.
func _check_fully_painted(dir: String, zone: Zone) -> void:
	var holes: int = 0
	for y: int in range(zone.size_tiles.y):
		for x: int in range(zone.size_tiles.x):
			if zone.get_terrain(Vector2i(x, y)) != ContentRegistry.ID_UNKNOWN:
				continue
			holes += 1
			if holes <= MAX_REPORTED:
				_fail("%s: terrain tile (%d,%d) is unpainted" % [dir, x, y])
	if holes > MAX_REPORTED:
		printerr("%s: ... and %d more unpainted terrain tile(s)"
			% [dir, holes - MAX_REPORTED])


func _check_spawn(dir: String, result: ZoneLoadResult) -> void:
	var zone: Zone = result.zone
	var tile: Vector2i = Vector2i(
		floori(result.player_spawn.x), floori(result.player_spawn.y))
	if not zone.in_bounds(tile):
		_fail("%s: player_spawn %s is outside the zone" % [dir, tile])
		return
	if not zone.is_walkable(tile):
		_fail("%s: player_spawn %s is blocked; the player would start inside something"
			% [dir, tile])


## Opening the project in the editor is exactly the kind of ordinary act
## that reverts an import mode, and the consequence -- maps missing from the
## export pack -- shows up only in a shipped build.
func _check_import_modes(dir: String) -> void:
	for map_name: String in MAPS:
		var path: String = dir.path_join(map_name + ".import")
		if not FileAccess.file_exists(path):
			_fail("%s: missing; the map would be imported as a texture" % path)
			continue
		var f: FileAccess = FileAccess.open(path, FileAccess.READ)
		if f == null:
			_fail("%s: cannot open" % path)
			continue
		var text: String = f.get_as_text()
		f.close()
		if not text.contains('importer="keep"'):
			_fail('%s: must say importer="keep"; re-apply it and re-import' % path)


## Reported, never failed: an author adds a colour before painting with it,
## and failing on that would make the format annoying to work in for no
## safety gain.
func _report_unused_legend(dir: String, zone: Zone, registry: ContentRegistry) -> void:
	# Compare by string id. Numeric ids are assigned per registry instance
	# and mean nothing outside it.
	var used: Dictionary = {}
	for y: int in range(zone.size_tiles.y):
		for x: int in range(zone.size_tiles.x):
			var w: Vector2i = Vector2i(x, y)
			used[registry.string_of(zone.get_terrain(w))] = true
			used[registry.string_of(zone.get_object(w))] = true

	var parser: JSON = JSON.new()
	var f: FileAccess = FileAccess.open(dir.path_join("zone.json"), FileAccess.READ)
	if f == null:
		return
	var err: int = parser.parse(f.get_as_text())
	f.close()
	if err != OK:
		return

	var legend: Dictionary = (parser.data as Dictionary).get("legend", {})
	for layer: String in legend:
		for hex: String in legend[layer]:
			var value: Variant = legend[layer][hex]
			if value == null:
				continue
			if not used.has(str(value)):
				print("%s: note: legend %s #%s (%s) is declared but unused"
					% [dir, layer, hex, str(value)])
