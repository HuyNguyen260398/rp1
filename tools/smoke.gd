extends SceneTree
## Boot check: exercises the data layer end to end and exits non-zero on any
## failure. Runs genuinely headless -- no rendering involved.

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

	var root: String = "user://smoke_save"
	var save_errs: PackedStringArray = SaveManager.save_zone(root, zone, registry, true)
	_check(save_errs.is_empty(), "save failed: %s" % ", ".join(save_errs))

	var loaded: DecodeResult = SaveManager.load_zone(root, "smoke", registry)
	_check(loaded.ok, "load failed: %s" % loaded.error)
	if loaded.ok:
		var back: Zone = loaded.value
		_check(back.get_terrain(Vector2i(0, 0)) == grass, "tile survived the round trip")
		_check(back.entities.count() == 1, "entity survived the round trip")

	for f: String in _failures:
		printerr("SMOKE FAILURE: ", f)
	if _failures.is_empty():
		print("Smoke test: OK (%d iterations)" % ITERATIONS)
		quit(0)
	else:
		printerr("Smoke test: %d failure(s)" % _failures.size())
		quit(1)
