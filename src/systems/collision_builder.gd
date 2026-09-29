class_name CollisionBuilder
extends RefCounted
## Merges blocked tiles into rectangles.
##
## Per-tile collision shapes are never used: a 32x32 chunk of solid tiles
## would be 1024 of them. Stage 1 merges runs within a row and stops there;
## Stage 2 replaces the body of rects_for_chunk() with greedy meshing behind
## the same signature.
##
## Rects are in WORLD tile coordinates -- the chunk knows its own coords and
## every caller wants world space -- and are emitted in row-major order so
## tests can assert on exact output.
##
## An instance rather than pure statics because it caches. Rebuilding 1024
## tiles per chunk per frame is not affordable.
##
## Invalidation is an EXPLICIT call -- invalidate_changed() -- driven by a
## private ChunkWatcher rather than by a shared flag. Stage 1 had a single
## boolean that both ZoneRenderer and SaveManager cleared, so a second
## consumer saw nothing. Phase 7 replaced it with per-chunk versions; see
## the Stage 2 design §3.1.

var _cache: Dictionary = {}  ## Vector2i chunk coord -> Array[Rect2i]
var _watcher: ChunkWatcher = ChunkWatcher.new()


func rects_for_chunk(chunk: Chunk) -> Array[Rect2i]:
	var out: Array[Rect2i] = []
	var origin: Vector2i = Coords.chunk_origin(chunk.coord)
	for y: int in range(Coords.CHUNK_SIZE):
		var run_start: int = -1
		# One column past the edge, so a run reaching the chunk boundary
		# is closed rather than dropped.
		for x: int in range(Coords.CHUNK_SIZE + 1):
			var blocked: bool = (
				x < Coords.CHUNK_SIZE and not chunk.is_walkable(Vector2i(x, y))
			)
			if blocked and run_start == -1:
				run_start = x
			elif not blocked and run_start != -1:
				out.append(Rect2i(origin.x + run_start, origin.y + y, x - run_start, 1))
				run_start = -1
	return out


func solids_for(zone: Zone, chunk_coord: Vector2i) -> Array[Rect2i]:
	if _cache.has(chunk_coord):
		return _cache[chunk_coord]
	var chunk: Chunk = zone.get_chunk(chunk_coord)
	var rects: Array[Rect2i] = []
	if chunk == null:
		# An unloaded region is solid, matching Walkability's rule that an
		# unpainted tile is not floor. The alternative lets a player walk
		# off into a region that has not been generated.
		var o: Vector2i = Coords.chunk_origin(chunk_coord)
		rects.append(Rect2i(o.x, o.y, Coords.CHUNK_SIZE, Coords.CHUNK_SIZE))
	else:
		rects = rects_for_chunk(chunk)
	_cache[chunk_coord] = rects
	return rects


## Every solid rect in the chunks overlapping `area`, which is in tile units.
func solids_near(zone: Zone, area: Rect2) -> Array[Rect2i]:
	var out: Array[Rect2i] = []
	var lo: Vector2i = Coords.world_to_chunk(
		Vector2i(floori(area.position.x), floori(area.position.y))
	)
	var hi: Vector2i = Coords.world_to_chunk(
		Vector2i(ceili(area.end.x), ceili(area.end.y))
	)
	for cy: int in range(lo.y, hi.y + 1):
		for cx: int in range(lo.x, hi.x + 1):
			out.append_array(solids_for(zone, Vector2i(cx, cy)))
	return out


func invalidate(chunk_coord: Vector2i) -> void:
	_cache.erase(chunk_coord)


## Drops cached rects for every chunk whose version has moved since this
## builder last looked. Returns how many were dropped. Call once per frame
## before reading rects; rebuilding 1024 tiles per chunk per frame is not
## affordable, and rebuilding only what changed is the whole point.
func invalidate_changed(zone: Zone) -> int:
	var changed: Array[Vector2i] = _watcher.changed(zone)
	for c: Vector2i in changed:
		_cache.erase(c)
	_watcher.mark_seen(zone)
	return changed.size()
