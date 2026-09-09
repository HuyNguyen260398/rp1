class_name FollowCamera
extends Camera2D
## Follows an entity, clamped to the zone's bounds.
##
## Named FollowCamera rather than Camera: a bare `Camera` risks colliding
## with engine-reserved names.

const TILE_SIZE: int = 32

## 1280x720 at 2x shows 20 x 11.25 tiles, which frames a 128x128 zone as a
## place you move through rather than a map you survey.
@export var follow_zoom: float = 2.0

var target_id: int = EntityStore.INVALID_ID

var _entities: EntityStore = null


func setup(zone: Zone) -> void:
	_entities = zone.entities
	zoom = Vector2(follow_zoom, follow_zoom)
	# Smoothing plus pixel snapping produces sub-pixel jitter, and crisp
	# beats smooth at this resolution.
	position_smoothing_enabled = false
	limit_left = 0
	limit_top = 0
	limit_right = zone.size_tiles.x * TILE_SIZE
	limit_bottom = zone.size_tiles.y * TILE_SIZE


func _process(_delta: float) -> void:
	if _entities == null or not _entities.has(target_id):
		return
	global_position = _entities.get_position(target_id) * float(TILE_SIZE)
