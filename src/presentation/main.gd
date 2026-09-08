extends Node2D
## Phase 3a entry point: build a debug zone and draw it.
##
## The zone generated here is scaffolding, not content. It is the one
## place this phase knowingly bends the "all content lives in data/*.json"
## rule, and it bends it for a fixture rather than for content. Phase 4
## replaces _build_debug_zone() with a zone authored as data.

const ZONE_SIZE: Vector2i = Vector2i(128, 128)
const POND_CENTRE: Vector2i = Vector2i(40, 40)
const POND_RADIUS: int = 8
const TREE_SPACING: int = 11

var _renderer: ZoneRenderer = null


func _ready() -> void:
	var registry: ContentRegistry = ContentRegistry.new()
	var errs: PackedStringArray = registry.load_from_dir("res://data")
	if not errs.is_empty():
		push_error("content failed to load: %s" % ", ".join(errs))
	print("RP1 booted with %d content definitions" % registry.all_string_ids().size())

	_renderer = ZoneRenderer.new()
	_renderer.name = "ZoneRenderer"
	add_child(_renderer)

	var art_errs: PackedStringArray = _renderer.setup(registry)
	for e: String in art_errs:
		push_error("tileset: %s" % e)

	var zone: Zone = _build_debug_zone(registry)
	var painted: int = _renderer.render_zone(zone)
	_renderer.zone = zone

	# The export gate asserts this count is non-zero. A build can export
	# cleanly and still ship without its textures, exactly as it nearly
	# shipped without data/*.json.
	print("RP1 rendered %d cells" % painted)


## TEMPORARY -- deleted in Phase 4 when zones are authored as data.
func _build_debug_zone(registry: ContentRegistry) -> Zone:
	var zone: Zone = Zone.new("debug", ZONE_SIZE)
	var grass: int = registry.numeric_of("grass")
	var water: int = registry.numeric_of("water")
	var oak: int = registry.numeric_of("oak_tree")

	for y: int in range(ZONE_SIZE.y):
		for x: int in range(ZONE_SIZE.x):
			var w: Vector2i = Vector2i(x, y)
			var in_pond: bool = Vector2(w - POND_CENTRE).length() <= float(POND_RADIUS)
			zone.set_terrain(w, water if in_pond else grass)
			zone.set_flags(w, 0 if in_pond else Chunk.FLAG_WALKABLE)
			# A lattice, skipping the pond, so the result is easy to eyeball.
			if not in_pond and x % TREE_SPACING == 0 and y % TREE_SPACING == 0:
				zone.set_object(w, oak)

	# The renderer has just painted everything; the flags this generator
	# set are not pending work for it.
	zone.clear_dirty()
	return zone
