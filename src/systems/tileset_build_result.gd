class_name TilesetBuildResult
extends RefCounted
## What TilesetBuilder returns.
##
## A separate file rather than an inner class, matching DecodeResult.

var tileset: TileSet = null

## numeric content id -> TileSet source id.
var source_id_by_numeric: Dictionary = {}

## Definitions that could not be turned into a source. A build reports
## these rather than aborting: one missing PNG must not blank the world.
var errors: PackedStringArray = []


## Returns the TileSet source id for a content id, or -1 if there is none.
##
## -1 is deliberate: it is what TileMapLayer itself uses for "no cell", so
## a caller can pass the result straight through. Note that source id 0 is
## a VALID source, while content id 0 is ID_UNKNOWN meaning "empty tile" --
## two different sentinels that are easy to confuse.
func source_for(numeric_id: int) -> int:
	if numeric_id == 0:
		return -1
	return source_id_by_numeric.get(numeric_id, -1)
