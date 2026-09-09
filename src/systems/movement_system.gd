class_name MovementSystem
extends RefCounted
## Resolves a desired move against solid rectangles.
##
## Pure: same inputs, same output, no engine state, no physics tick, no
## display server. That is the whole point -- Stage 1 acceptance criterion
## #1 ("walk from any corner to any other with no collision bugs") is a test
## that runs in CI rather than a play-session somebody performs.
##
## Every argument is in TILE UNITS. `body` is the collision box size in
## tiles, anchored bottom-centre on `pos`: the position IS the feet point,
## which also makes it the Y-sort key with no offset arithmetic.
##
## Resolution is axis-separated, not swept: move on X and push out along X,
## then move on Y and push out along Y. Wall sliding falls out of that for
## free, and it avoids the edge cases a true swept AABB brings for no
## behavioural gain at these speeds.


## The body box in world tile space. `pos` is its bottom-centre.
static func body_rect(pos: Vector2, body: Vector2) -> Rect2:
	return Rect2(pos.x - body.x * 0.5, pos.y - body.y, body.x, body.y)


static func clamp_to_bounds(pos: Vector2, body: Vector2, bounds: Rect2) -> Vector2:
	var half: float = body.x * 0.5
	return Vector2(
		clampf(pos.x, bounds.position.x + half, bounds.end.x - half),
		clampf(pos.y, bounds.position.y + body.y, bounds.end.y)
	)


static func move(
	pos: Vector2,
	velocity: Vector2,
	delta: float,
	body: Vector2,
	solids: Array[Rect2i],
	bounds: Rect2
) -> Vector2:
	var p: Vector2 = pos
	var step: Vector2 = velocity * delta
	p = _slide_axis(p, body, Vector2(step.x, 0.0), solids)
	p = _slide_axis(p, body, Vector2(0.0, step.y), solids)
	return clamp_to_bounds(p, body, bounds)


## Moves along one axis and pushes out of anything it lands inside.
## `step` has exactly one non-zero component.
static func _slide_axis(
	pos: Vector2, body: Vector2, step: Vector2, solids: Array[Rect2i]
) -> Vector2:
	if step.is_zero_approx():
		return pos
	var moved: Vector2 = pos + step
	var r: Rect2 = body_rect(moved, body)
	for s: Rect2i in solids:
		var sr: Rect2 = Rect2(float(s.position.x), float(s.position.y),
			float(s.size.x), float(s.size.y))
		# Rect2.intersects() is exclusive, so a body resting exactly against
		# a wall does not count as overlapping it.
		if not r.intersects(sr):
			continue
		if step.x > 0.0:
			moved.x = sr.position.x - body.x * 0.5
		elif step.x < 0.0:
			moved.x = sr.end.x + body.x * 0.5
		elif step.y > 0.0:
			moved.y = sr.position.y
		else:
			moved.y = sr.end.y + body.y
		r = body_rect(moved, body)
	return moved
