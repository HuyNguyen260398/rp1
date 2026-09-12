extends GutTest
## The zone that actually ships.
##
## Every other loader test uses a generated fixture. This one loads
## data/zone/home/ exactly as the game does, so editing a PNG badly fails
## here rather than at boot.

var _registry: ContentRegistry
var _result: ZoneLoadResult


func before_all() -> void:
	_registry = ContentRegistry.new()
	var errs: PackedStringArray = _registry.load_from_dir("res://data")
	assert_eq(errs, PackedStringArray(), "content must load before a zone can")
	_result = ZoneLoader.load_zone("res://data/zone/home", _registry)


func test_the_home_zone_loads_without_errors() -> void:
	assert_eq(_result.errors, PackedStringArray())
	assert_not_null(_result.zone)


func test_every_terrain_tile_is_painted() -> void:
	# An unpainted terrain tile is ID_UNKNOWN, which Walkability treats as
	# void rather than floor -- a hole in the world. The loader survives
	# one; the shipped zone must not contain one.
	var zone: Zone = _result.zone
	var holes: int = 0
	var first: Vector2i = Vector2i(-1, -1)
	for y: int in range(zone.size_tiles.y):
		for x: int in range(zone.size_tiles.x):
			if zone.get_terrain(Vector2i(x, y)) == ContentRegistry.ID_UNKNOWN:
				holes += 1
				if first.x < 0:
					first = Vector2i(x, y)
	assert_eq(holes, 0, "%d unpainted terrain tile(s), first at %s" % [holes, first])


func test_the_player_spawn_is_in_bounds_and_walkable() -> void:
	var zone: Zone = _result.zone
	var tile: Vector2i = Vector2i(
		floori(_result.player_spawn.x), floori(_result.player_spawn.y))
	assert_true(zone.in_bounds(tile), "spawn %s is outside the zone" % tile)
	assert_true(zone.is_walkable(tile),
		"spawn %s is blocked; the player would start inside something" % tile)
