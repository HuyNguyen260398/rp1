class_name EntityRenderer
extends Node2D
## Draws EntityStore rows as a pool of Sprite2D nodes.
##
## Presentation reads world data and never writes it. Nothing here may
## mutate the store it is handed.
##
## y_sort_enabled is set on this node so its sprites flatten into the
## parent's sort and interleave with the object layer's tiles. Without it
## the whole renderer sorts as a single item and every entity draws in
## front of every tree.

const TILE_SIZE: int = 32

var entities: EntityStore = null

var _registry: ContentRegistry = null
var _pool: Array[Sprite2D] = []
## Numeric type id -> Texture2D, or null for one that could not be loaded.
## Failures are cached too, so a missing PNG logs once rather than sixty
## times a second.
var _textures: Dictionary = {}


func _ready() -> void:
	y_sort_enabled = true


func setup(registry: ContentRegistry) -> void:
	_registry = registry
	# Set here too, not just in _ready(): _ready() does not fire
	# synchronously on add_child() from SceneTree._init(), which is how the
	# headless smoke test drives this node. Same reasoning as
	# zone_renderer.gd's _ensure_layers().
	y_sort_enabled = true


func _process(_delta: float) -> void:
	refresh()


## Repaints every row. Returns the number of sprites actually drawn.
func refresh() -> int:
	if entities == null or _registry == null:
		return 0
	var ids: PackedInt32Array = entities.ids()
	var shown: int = 0
	for i: int in range(ids.size()):
		var texture: Texture2D = _texture_for(entities.get_type_id(ids[i]))
		if texture == null:
			continue
		var sprite: Sprite2D = _sprite_at(shown)
		sprite.texture = texture
		# Bottom-centre anchoring: the texture's bottom edge lands on the
		# entity position, which is the feet point. Derived from geometry,
		# so a 32x64 player and a 32x32 rabbit both stand correctly with no
		# content field and no per-type tuning -- the principle commit
		# ad8956c established for the tileset builder.
		sprite.offset = Vector2(0.0, -float(texture.get_height()) * 0.5)
		sprite.position = entities.get_position(ids[i]) * float(TILE_SIZE)
		sprite.visible = true
		shown += 1
	# Surplus sprites are hidden, not freed: entity counts churn and
	# allocating nodes per frame is what pooling exists to avoid.
	for i: int in range(shown, _pool.size()):
		_pool[i].visible = false
	return shown


func visible_count() -> int:
	var n: int = 0
	for s: Sprite2D in _pool:
		if s.visible:
			n += 1
	return n


func _sprite_at(index: int) -> Sprite2D:
	while _pool.size() <= index:
		var s: Sprite2D = Sprite2D.new()
		s.centered = true
		add_child(s)
		_pool.append(s)
	return _pool[index]


func _texture_for(type_id: int) -> Texture2D:
	if _textures.has(type_id):
		return _textures[type_id]
	var path: String = str(_registry.def_of(type_id).get("sprite", ""))
	var texture: Texture2D = null
	# Checked before load() rather than testing the result for null:
	# load() on a missing path pushes an engine-level error. Same guard as
	# tileset_builder.gd:49.
	if path.is_empty() or not ResourceLoader.exists(path):
		push_error("entity sprite: cannot load '%s' for %s"
			% [path, _registry.string_of(type_id)])
	else:
		texture = load(path) as Texture2D
	_textures[type_id] = texture
	return texture
