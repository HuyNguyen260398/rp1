class_name ChunkWatcher
extends RefCounted
## One consumer's record of the chunk versions it has already acted on.
##
## Stage 1 had a single boolean per chunk that consumers cleared. Two of
## them did -- ZoneRenderer.refresh_dirty() and SaveManager.save_zone() --
## which is harmless only while nothing mutates a tile during play. The
## moment building writes one, whichever consumer ran second saw a clean
## zone, and an edit could reach the screen without reaching disk.
##
## Each consumer owns a watcher and compares rather than consuming. No
## shared state is cleared, so no consumer can starve another. There is
## deliberately no registration step: a watcher is a private object, not a
## subscription, which is what collision_builder.gd's header objected to.

var _seen: Dictionary = {}  ## Vector2i chunk coord -> int version


## Coords whose version differs from the one last marked seen, in
## chunk_coords() order so callers and tests get a stable sequence.
## Asking does not consume: the answer is the same until mark_seen().
func changed(zone: Zone) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for c: Vector2i in zone.chunk_coords():
		var chunk: Chunk = zone.get_chunk(c)
		if chunk == null:
			continue
		if _seen.get(c, -1) != chunk.version:
			out.append(c)
	return out


## Records every chunk's current version as acted on.
func mark_seen(zone: Zone) -> void:
	for c: Vector2i in zone.chunk_coords():
		var chunk: Chunk = zone.get_chunk(c)
		if chunk != null:
			_seen[c] = chunk.version


## Drops all memory, so the next changed() reports every chunk. Used when
## a consumer is pointed at a different zone -- versions are per zone and
## carrying them across would be meaningless.
func forget() -> void:
	_seen.clear()
