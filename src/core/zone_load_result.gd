class_name ZoneLoadResult
extends RefCounted
## What ZoneLoader returns.
##
## A separate file rather than an inner class, matching DecodeResult and
## TilesetBuildResult.
##
## `zone` is null only when the document itself could not be read or did
## not satisfy the schema. Every other problem is an entry in `errors`
## beside a zone that is still usable: one unreadable map must not blank
## the world, exactly as one missing PNG must not (TilesetBuildResult).

var zone: Zone = null

## Tile units, matching EntityStore: the centre of tile (1,1) is (1.5, 1.5).
var player_spawn: Vector2 = Vector2.ZERO

var errors: PackedStringArray = []
