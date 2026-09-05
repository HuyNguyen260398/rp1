class_name Coords
extends RefCounted
## World <-> chunk <-> local coordinate conversion.
##
## Pure static functions, no state. Negative coordinates are the whole
## reason this is a separate module: naive integer division truncates
## toward zero, which puts world tile -1 in chunk 0 alongside tile 0.

const CHUNK_SIZE: int = 32
const TILES_PER_CHUNK: int = CHUNK_SIZE * CHUNK_SIZE


## Floor division: rounds toward negative infinity, unlike `/`.
## `(a - posmod(a, b))` is always an exact multiple of b.
static func floordiv(a: int, b: int) -> int:
	return (a - posmod(a, b)) / b


static func world_to_chunk(w: Vector2i) -> Vector2i:
	return Vector2i(floordiv(w.x, CHUNK_SIZE), floordiv(w.y, CHUNK_SIZE))


static func world_to_local(w: Vector2i) -> Vector2i:
	return Vector2i(posmod(w.x, CHUNK_SIZE), posmod(w.y, CHUNK_SIZE))


static func local_index(l: Vector2i) -> int:
	return l.y * CHUNK_SIZE + l.x


static func chunk_origin(c: Vector2i) -> Vector2i:
	return c * CHUNK_SIZE
