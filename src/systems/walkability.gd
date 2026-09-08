class_name Walkability
extends RefCounted
## Derives the FLAG_WALKABLE bit from content definitions.
##
## The composite rule lives here and nowhere else:
##
##   walkable = terrain.walkable AND NOT object.blocks_movement
##
## Note the two vocabularies. Terrain declares `walkable` and objects declare
## `blocks_movement` -- different names, opposite polarity. That asymmetry is
## already in the content schemas; this is the one place that reconciles it.
##
## Both functions return the number of tiles whose flag CHANGED, which is what
## makes the staleness guard testable: recompute an already-correct chunk and
## expect zero.


static func recompute_chunk(chunk: Chunk, registry: ContentRegistry) -> int:
	var changed: int = 0
	for y: int in range(Coords.CHUNK_SIZE):
		for x: int in range(Coords.CHUNK_SIZE):
			var l: Vector2i = Vector2i(x, y)
			var walkable: bool = _tile_is_walkable(chunk, l, registry)
			var flags: int = chunk.get_flags(l)
			if ((flags & Chunk.FLAG_WALKABLE) != 0) == walkable:
				continue
			# Set or clear one bit. FLAG_BLOCKS_LIGHT shares this byte and
			# must survive untouched.
			if walkable:
				flags |= Chunk.FLAG_WALKABLE
			else:
				flags &= ~Chunk.FLAG_WALKABLE
			chunk.set_flags(l, flags)
			changed += 1
	return changed


static func recompute_zone(zone: Zone, registry: ContentRegistry) -> int:
	var changed: int = 0
	for c: Vector2i in zone.chunk_coords():
		changed += recompute_chunk(zone.get_chunk(c), registry)
	return changed


static func _tile_is_walkable(chunk: Chunk, l: Vector2i, registry: ContentRegistry) -> bool:
	var terrain: int = chunk.get_terrain(l)
	# Unpainted void is not floor. Content id 0 is ID_UNKNOWN, meaning the
	# cell was never painted -- not that something unknown stands there.
	if terrain == ContentRegistry.ID_UNKNOWN:
		return false
	# A placeholder is content the build cannot see. Stage 1 design 6.4
	# point 3 makes it non-blocking: walking through a gap where a mod used
	# to be beats being walled in by something invisible.
	if not registry.is_placeholder(terrain):
		if not bool(registry.def_of(terrain).get("walkable", true)):
			return false

	var obj: int = chunk.get_object(l)
	if obj == ContentRegistry.ID_UNKNOWN or registry.is_placeholder(obj):
		return true
	return not bool(registry.def_of(obj).get("blocks_movement", false))
