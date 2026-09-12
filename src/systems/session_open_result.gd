class_name SessionOpenResult
extends RefCounted
## What GameSession returns from open_new and open_saved.
##
## One result type for both entry points, rather than ZoneLoadResult from
## one and DecodeResult from the other: the router would otherwise have to
## branch on shape before it could branch on outcome. A separate file,
## matching DecodeResult, ZoneLoadResult and TilesetBuildResult.

var ok: bool = false
var error: String = ""
var zone: Zone = null

## Only meaningful when `is_new` is false; a new world has no player yet.
var player_entity_id: int = 0

## Only meaningful when `is_new` is true. Tile units, matching EntityStore.
var player_spawn: Vector2 = Vector2.ZERO

var is_new: bool = false

## Non-fatal problems beside a world that is still usable -- an unreadable
## map layer, an unknown string id. Same policy as ZoneLoadResult.errors.
var warnings: PackedStringArray = []


static func failure(msg: String) -> SessionOpenResult:
	var r: SessionOpenResult = SessionOpenResult.new()
	r.error = msg
	return r
