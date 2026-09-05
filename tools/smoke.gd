extends SceneTree
## Boot check: exercises the data layer end to end, then paints a zone
## through ZoneRenderer, and exits non-zero on any failure.
##
## The render half runs headless too -- TileMapLayer's cell bookkeeping
## works without a display server, which is what lets CI assert on it.

const ITERATIONS: int = 300

var _failures: PackedStringArray = []


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _init() -> void:
	var registry: ContentRegistry = ContentRegistry.new()
	var errs: PackedStringArray = registry.load_from_dir("res://data")
	_check(errs.is_empty(), "content failed to load: %s" % ", ".join(errs))

	var zone: Zone = Zone.new("smoke", Vector2i(128, 128))
	var grass: int = registry.numeric_of("grass")
	_check(grass != ContentRegistry.ID_UNKNOWN, "grass is registered")

	for i: int in range(ITERATIONS):
		var w: Vector2i = Vector2i(i % 128, (i * 7) % 128)
		zone.set_terrain(w, grass)
		zone.set_flags(w, Chunk.FLAG_WALKABLE)
		_check(zone.get_terrain(w) == grass, "tile %s round-trips in memory" % w)

	var id: int = zone.entities.spawn(registry.numeric_of("rabbit"), Vector2(1.0, 2.0))
	_check(zone.entities.has(id), "entity spawned")

	var save_root: String = "user://smoke_save"
	var save_errs: PackedStringArray = SaveManager.save_zone(save_root, zone, registry, true)
	_check(save_errs.is_empty(), "save failed: %s" % ", ".join(save_errs))

	var loaded: DecodeResult = SaveManager.load_zone(save_root, "smoke", registry)
	_check(loaded.ok, "load failed: %s" % loaded.error)
	if loaded.ok:
		var back: Zone = loaded.value
		_check(back.get_terrain(Vector2i(0, 0)) == grass, "tile survived the round trip")
		_check(back.entities.count() == 1, "entity survived the round trip")

	# --- rendering -------------------------------------------------------
	var renderer: ZoneRenderer = ZoneRenderer.new()
	root.add_child(renderer)

	var art_errs: PackedStringArray = renderer.setup(registry)
	_check(art_errs.is_empty(), "tileset build failed: %s" % ", ".join(art_errs))

	var painted: int = renderer.render_zone(zone)
	_check(painted > 0, "render painted no cells at all")
	_check(renderer.cells_painted() == painted,
		"layers hold %d cells but render reported %d" % [renderer.cells_painted(), painted])

	# A chunk marked dirty is repainted; an unmarked one is not touched.
	var before_dirty: int = renderer.cells_painted()
	zone.clear_dirty()
	_check(renderer.refresh_dirty(zone) == 0, "a clean zone repaints nothing")
	zone.set_terrain(Vector2i(0, 0), grass)
	var repainted: int = renderer.refresh_dirty(zone)
	_check(repainted > 0, "a dirtied chunk is repainted")
	_check(repainted < painted, "a dirty repaint touches one chunk, not the whole zone")
	_check(renderer.cells_painted() == before_dirty,
		"repainting a chunk does not change the total cell count")

	renderer.queue_free()

	for f: String in _failures:
		printerr("SMOKE FAILURE: ", f)
	if _failures.is_empty():
		print("Smoke test: OK (%d iterations)" % ITERATIONS)
		quit(0)
	else:
		printerr("Smoke test: %d failure(s)" % _failures.size())
		quit(1)
