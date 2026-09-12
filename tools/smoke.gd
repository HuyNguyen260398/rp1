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

	# --- movement --------------------------------------------------------
	# A purpose-built fixture: an 8x8 patch of grass with one oak in it.
	# The zone above is scattered tiles and is not walkable enough to test
	# against.
	var mzone: Zone = Zone.new("move", Vector2i(32, 32))
	var oak: int = registry.numeric_of("oak_tree")
	_check(oak != ContentRegistry.ID_UNKNOWN, "oak_tree is registered")
	for y: int in range(8):
		for x: int in range(8):
			mzone.set_terrain(Vector2i(x, y), grass)
	mzone.set_object(Vector2i(4, 2), oak)

	_check(Walkability.recompute_zone(mzone, registry) > 0, "walkability set some flags")
	_check(mzone.is_walkable(Vector2i(2, 2)), "plain grass is walkable")
	_check(not mzone.is_walkable(Vector2i(4, 2)), "grass under an oak is not walkable")

	var collision: CollisionBuilder = CollisionBuilder.new()
	var solids: Array[Rect2i] = collision.solids_near(
		mzone, Rect2(Vector2.ZERO, Vector2(8.0, 8.0)))
	# Not just "produced some rects": the fixture's 24 unpainted columns
	# guarantee a non-empty result regardless of whether oak-blocking works
	# at all, so assert the oak's own rect is actually in there.
	_check(solids.has(Rect2i(4, 2, 1, 1)), "collision builder did not produce the oak's own rect at (4, 2)")

	var body: Vector2 = Vector2(0.625, 0.5)
	var bounds: Rect2 = Rect2(Vector2.ZERO, Vector2(mzone.size_tiles))
	var tick: float = 1.0 / 60.0

	# Row 2 has the oak at x = 4. Walking east must stop short of it.
	var blocked: Vector2 = Vector2(2.5, 2.5)
	for i: int in range(120):
		blocked = MovementSystem.move(blocked, Vector2(4.5, 0.0), tick, body, solids, bounds)
	_check(blocked.x < 4.0, "walking east into the oak stopped at %.3f" % blocked.x)

	# Row 5 is clear, so the same walk must actually get somewhere -- but
	# the fixture's unpainted region starts at x = 8, so collision working
	# stops it there too, at exactly 7.6875 (8 minus half the 0.625-wide
	# body). A lower bound alone would also pass with collision disabled
	# entirely (the walk would reach 11.5), so check both sides: past the
	# grass, short of the unpainted column.
	var open: Vector2 = Vector2(2.5, 5.5)
	for i: int in range(120):
		open = MovementSystem.move(open, Vector2(4.5, 0.0), tick, body, solids, bounds)
	_check(open.x > 7.0 and open.x < 8.0,
		"walking east across open grass should stop just short of the unpainted column at x=8, reached %.4f" % open.x)

	# --- entity rendering ------------------------------------------------
	var entity_renderer: EntityRenderer = EntityRenderer.new()
	root.add_child(entity_renderer)
	entity_renderer.setup(registry)
	entity_renderer.entities = mzone.entities
	var player_type: int = registry.numeric_of("player")
	_check(player_type != ContentRegistry.ID_UNKNOWN, "player is registered")
	mzone.entities.spawn(player_type, Vector2(2.5, 2.5))
	_check(entity_renderer.refresh() == 1, "entity renderer drew the player")
	_check(entity_renderer.visible_count() == 1, "exactly one sprite is visible")
	entity_renderer.queue_free()

	renderer.queue_free()

	# --- session ---------------------------------------------------------
	# The layer above the data-layer round trip above: a build can export
	# cleanly, render, and still be unable to reopen its own save.
	var session_root: String = "user://smoke_session"
	var session: GameSession = GameSession.new()
	session.save_root = session_root

	var opened: SessionOpenResult = session.open_new("res://data/zone/home", registry)
	_check(opened.ok, "opening a new world failed: %s" % opened.error)
	if opened.ok:
		var pid: int = opened.zone.entities.spawn(
			registry.numeric_of("player"), opened.player_spawn)
		session.adopt_player(pid)
		opened.zone.entities.set_position(pid, Vector2(33.5, 44.5))
		opened.zone.entities.set_facing(pid, 3)

		var save_errors: PackedStringArray = session.save_now(registry, "smoke")
		_check(save_errors.is_empty(), "session save failed: %s" % ", ".join(save_errors))
		var written: int = DirAccess.get_files_at(
			session_root.path_join("zones/home/chunks")).size()
		_check(written == 16,
			"a first save must write all 16 chunks, not only dirty ones; wrote %d" % written)

		var again: GameSession = GameSession.new()
		again.save_root = session_root
		var reopened: SessionOpenResult = again.open_saved(registry)
		_check(reopened.ok, "reopening the save failed: %s" % reopened.error)
		if reopened.ok:
			_check(reopened.player_entity_id == pid, "the player id changed across a save")
			_check(reopened.zone.entities.get_position(pid) == Vector2(33.5, 44.5),
				"the player did not come back where they were left")
			_check(reopened.zone.entities.get_facing(pid) == 3,
				"the player's facing was not restored")

	for f: String in _failures:
		printerr("SMOKE FAILURE: ", f)
	if _failures.is_empty():
		print("Smoke test: OK (%d iterations)" % ITERATIONS)
		quit(0)
	else:
		printerr("Smoke test: %d failure(s)" % _failures.size())
		quit(1)
