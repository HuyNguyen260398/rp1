# Phase 4b — Living World Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The eight rabbits standing motionless in `data/zone/home/zone.json`
wander, flee the player and walk home again — headlessly, deterministically,
and driven entirely by numbers in `data/creature/rabbit.json`.

**Architecture:** One new file. `AnimalSystem` is a node-free `RefCounted` in
`src/systems/` holding per-animal state in a `Dictionary` keyed by entity id,
with an injected `RandomNumberGenerator` so every test is exactly
reproducible. It chooses a desired velocity per animal and hands it to the
existing `MovementSystem.move()` against the existing
`CollisionBuilder.solids_near()`, so an animal collides with precisely the
geometry the player does. `main.gd` ticks it from `_physics_process`.

**Tech Stack:** Godot 4.7.2 standard build, GDScript, GUT for tests.

**Spec:** `docs/superpowers/specs/2026-09-12-rp1-phase4b-living-world-design.md`

## Global Constraints

Every task's requirements implicitly include this section.

- Godot **4.7.2 standard build**, never the Mono build. Invoke it only through
  `./tools/godot.sh` — never a hardcoded binary path.
- **GDScript only.** Static typing everywhere: `var x: int = 0`,
  `func f(a: Vector2i) -> void:`.
- `src/core/` and `src/systems/` extend **`RefCounted` or `Object` only**, and
  may not contain the strings `get_tree(`, `Engine.`, `.tscn`, `get_node(`,
  `add_child(` or `queue_free(`. Enforced by `tools/guard.gd`.
- Run tests **only** with `./tools/run_tests.sh`. Never call `gut_cmdln.gd`
  directly: the runner does a mandatory `--import` pass first, and without it
  GUT reports missing `class_name`s and still exits 0.
- **TDD, strictly.** Write the failing test, run it, watch it fail for the
  right reason, implement minimally, watch it pass.
- All game content lives in `data/*.json`. Never hardcode content in GDScript,
  and **never `match` over content types** — an animal is any creature whose
  `wander_radius` is greater than zero, never one whose id is `"rabbit"`.
- Presentation reads world data; world data never reads presentation.
- Tile size is 32x32, but **every number in this plan is in tile units**, as
  `EntityStore` and `MovementSystem` already are. A speed of 2.0 is two tiles
  per second.
- Commit prefixes: `feat:`, `test:`, `ci:`, `docs:`, `fix:`.
- **Each task produces two commits:** the code, then a `docs:` commit ticking
  that task's checkboxes. Tick them with
  `python3 tools/mark_task_done.py <N> --plan docs/superpowers/plans/2026-09-12-rp1-phase4b-living-world.md`
  — never by hand.

---

## File structure

**Created**

| Path | Responsibility |
|---|---|
| `src/systems/animal_system.gd` | The whole phase. Mode selection, target choice, per-animal state |
| `tests/test_creature_schema.gd` | The creature contract, including the new behaviour fields |
| `tests/test_animal_system.gd` | Wander, flee, return, determinism, pruning |
| `tests/test_animal_budget.gd` | 64 animals tick inside a frame |

**Modified**

| Path | Change |
|---|---|
| `data/schema/creature.json` | Six new optional fields |
| `data/creature/rabbit.json` | The authored numbers |
| `src/presentation/main.gd` | Holds the registry and the system; ticks it in `_physics_process` |
| `docs/superpowers/specs/2026-08-23-rp1-stage0-stage1-design.md` | §10: the dirty channel moves to Stage 2 |

`AnimalSystem` is the only file that knows what an animal does. `MovementSystem`
and `CollisionBuilder` are used unchanged — this plan modifies neither.

---

## Task order and why

Task 1 is content, because every later task reads those fields and a test that
invents its own would prove nothing about the shipped rabbit.

Tasks 2-6 build one behaviour rule at a time against a generated fixture zone,
never the shipped one, so none of them depend on what `data/zone/home/` happens
to contain today. Task 2 deliberately ships a system that moves nothing: the
lazy home anchor, the pruning rule and "which entities animate" are all
testable before a single animal takes a step, and getting them wrong later is
expensive.

Task 7 wires it into the game and measures it. Task 8 closes the phase.

---

## Task 1: The behaviour fields, authored

**Files:**
- Modify: `data/schema/creature.json`, `data/creature/rabbit.json`
- Test: `tests/test_creature_schema.gd`

**Interfaces:**
- Consumes: `SchemaValidator.validate(def: Dictionary, schema: Dictionary) -> PackedStringArray` (existing)
- Produces: the six field names every later task reads —
  `wander_speed`, `wander_interval`, `flee_radius`, `flee_speed`,
  `body_width`, `body_height`, all `float`, alongside the existing
  `wander_radius` (`int`) and `flees_player` (`bool`).

- [x] **Step 1: Write the failing test**

Create `tests/test_creature_schema.gd`:

```gdscript
extends GutTest
## The creature contract, including the behaviour fields AnimalSystem reads.
##
## SchemaValidator checks the TOP LEVEL ONLY. That is exactly why these
## fields are flat rather than nested inside a "wander" block: a typo in a
## nested block would be silently ignored, which is the failure the
## unknown-field rule exists to prevent. These tests are what make that
## claim true rather than merely intended.

const SCHEMA_PATH: String = "res://data/schema/creature.json"
const RABBIT_PATH: String = "res://data/creature/rabbit.json"
const PLAYER_PATH: String = "res://data/creature/player.json"

var _schema: Dictionary


func _read(path: String) -> Dictionary:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	assert_not_null(f, "%s must exist" % path)
	if f == null:
		return {}
	var text: String = f.get_as_text()
	f.close()
	var parser: JSON = JSON.new()
	assert_eq(parser.parse(text), OK, "%s must be valid JSON" % path)
	return parser.data as Dictionary


func before_each() -> void:
	_schema = _read(SCHEMA_PATH)


func test_the_shipped_creatures_validate() -> void:
	for path: String in [RABBIT_PATH, PLAYER_PATH]:
		assert_eq(SchemaValidator.validate(_read(path), _schema), PackedStringArray(),
			"%s must satisfy the creature schema" % path)


func test_every_behaviour_field_is_declared() -> void:
	var optional: Dictionary = _schema.get("optional", {})
	for field: String in ["wander_radius", "wander_speed", "wander_interval",
			"flees_player", "flee_radius", "flee_speed",
			"body_width", "body_height"]:
		assert_true(optional.has(field),
			"'%s' must be a declared optional field, or a creature carrying it is rejected"
				% field)


func test_a_typo_in_a_behaviour_field_is_rejected() -> void:
	var def: Dictionary = _read(RABBIT_PATH)
	def["wander_radus"] = 6
	assert_gt(SchemaValidator.validate(def, _schema).size(), 0,
		"a misspelt field must be an error, not a setting that does nothing")


func test_a_behaviour_field_of_the_wrong_type_is_rejected() -> void:
	var def: Dictionary = _read(RABBIT_PATH)
	def["flees_player"] = "yes"
	assert_gt(SchemaValidator.validate(def, _schema).size(), 0,
		"flees_player is a bool; a string must not pass")


func test_the_rabbit_carries_every_number_animal_system_reads() -> void:
	var rabbit: Dictionary = _read(RABBIT_PATH)
	for field: String in ["wander_radius", "wander_speed", "wander_interval",
			"flees_player", "flee_radius", "flee_speed",
			"body_width", "body_height"]:
		assert_true(rabbit.has(field), "rabbit.json must author '%s'" % field)
	assert_gt(float(rabbit["wander_radius"]), 0.0,
		"a wander_radius above zero is what makes an entity an animal")
	assert_gt(float(rabbit["flee_radius"]) * 1.5, float(rabbit["flee_radius"]),
		"precondition for the calm distance in AnimalSystem")


func test_the_player_is_not_an_animal() -> void:
	var player: Dictionary = _read(PLAYER_PATH)
	assert_false(player.has("wander_radius"),
		"the player must have no wander_radius, or AnimalSystem would drive it")
```

- [x] **Step 2: Run the test and watch it fail**

Run: `./tools/run_tests.sh`

Expected: FAIL. `test_every_behaviour_field_is_declared` fails on
`wander_speed` — the schema declares only `wander_radius`, `flees_player` and
`tags` — and `test_the_rabbit_carries_every_number_animal_system_reads` fails
on the same field.

- [x] **Step 3: Extend the schema**

Replace `data/schema/creature.json` with:

```json
{
  "category": "creature",
  "required": {"id": "String", "category": "String", "display_name": "String", "sprite": "String"},
  "optional": {
    "wander_radius": "int", "wander_speed": "float", "wander_interval": "float",
    "flees_player": "bool", "flee_radius": "float", "flee_speed": "float",
    "body_width": "float", "body_height": "float", "tags": "Array"
  }
}
```

- [x] **Step 4: Author the rabbit**

Replace `data/creature/rabbit.json` with:

```json
{"id": "rabbit", "category": "creature", "display_name": "Rabbit",
 "sprite": "res://assets/characters/rabbit.png",
 "wander_radius": 6, "wander_speed": 1.5, "wander_interval": 3.0,
 "flees_player": true, "flee_radius": 5.0, "flee_speed": 4.0,
 "body_width": 0.5, "body_height": 0.375,
 "tags": ["animal", "prey"]}
```

The player walks at 4.0 tiles/second (`src/presentation/player.gd`), so a
fleeing rabbit exactly matches the player and cannot be caught by walking —
which is the intended feel. Its body is smaller than the player's
0.625 x 0.5, so it fits through gaps the player cannot.

Leave `data/creature/player.json` untouched. It carries no `wander_radius`,
which is the whole of how `AnimalSystem` knows not to drive it.

- [x] **Step 5: Run the tests and watch them pass**

Run: `./tools/run_tests.sh`

Expected: PASS, one new script and seven new tests.

- [x] **Step 6: Commit**

```bash
git add data/schema/creature.json data/creature/rabbit.json tests/test_creature_schema.gd
git commit -m "$(cat <<'EOF'
feat: author the rabbit's behaviour numbers

Phase 4a reserved wander_radius and flees_player and left them unused.
This fills them in and extends the same FLAT shape, which is the load-
bearing decision: SchemaValidator checks the top level only, so a typo
inside a nested "wander" block would be silently ignored -- exactly the
failure the unknown-field rule exists to prevent. Flat fields are covered
by the validator the project already has.

A rabbit flees at 4.0 tiles/second, the player's own speed, so it cannot
be caught by walking.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

- [x] **Step 7: Tick this task**

```bash
python3 tools/mark_task_done.py 1 --plan docs/superpowers/plans/2026-09-12-rp1-phase4b-living-world.md
git add docs/superpowers/plans/2026-09-12-rp1-phase4b-living-world.md
git commit -m "docs: tick Phase 4b task 1"
```

---

## Task 2: `AnimalSystem` that moves nothing

**Files:**
- Create: `src/systems/animal_system.gd`
- Test: `tests/test_animal_system.gd`

**Interfaces:**
- Consumes: `Zone`, `EntityStore`, `ContentRegistry`, `CollisionBuilder`
- Produces:
  - `AnimalSystem.new()`, with `var rng: RandomNumberGenerator`
  - `tick(zone: Zone, registry: ContentRegistry, collision: CollisionBuilder, player_pos: Vector2, delta: float) -> int`,
    returning the number of animals that moved
  - `tracked_ids() -> PackedInt32Array`, the entity ids it currently holds
    state for — the seam the pruning test needs
  - `MODE_WANDER: int = 0`, `MODE_FLEE: int = 1`, `MODE_RETURN: int = 2`
  - `mode_of(id: int) -> int`, returning `-1` for an untracked id

This task deliberately ships a system where `tick()` always returns 0. The
lazy home anchor, the pruning rule and the data-driven "which entities
animate" test are all provable before anything moves, and each is expensive to
retrofit.

- [x] **Step 1: Write the failing test**

Create `tests/test_animal_system.gd`:

```gdscript
extends GutTest
## AnimalSystem drives every creature whose content gives it a wander radius.
##
## Every test builds its own zone and its own registry, so none of them
## depend on what data/zone/home/ happens to contain today, and the seed is
## always explicit -- a behaviour test that cannot be reproduced exactly is
## a behaviour test that will be deleted the first time it flakes.

const SEED: int = 424242

var _zone: Zone
var _registry: ContentRegistry
var _collision: CollisionBuilder
var _system: AnimalSystem


## A 32x32 field of walkable grass: one chunk, no obstacles.
func _make_zone() -> Zone:
	var zone: Zone = Zone.new("fixture", Vector2i(32, 32))
	var grass: int = _registry.numeric_of("grass")
	for y: int in range(32):
		for x: int in range(32):
			zone.set_terrain(Vector2i(x, y), grass)
	Walkability.recompute_zone(zone, _registry)
	zone.clear_dirty()
	return zone


func before_each() -> void:
	_registry = ContentRegistry.new()
	_registry.register({"id": "grass", "category": "terrain",
		"display_name": "Grass", "sprite": "res://none.png", "walkable": true})
	_registry.register({"id": "water", "category": "terrain",
		"display_name": "Water", "sprite": "res://none.png", "walkable": false})
	_registry.register({"id": "rabbit", "category": "creature",
		"display_name": "Rabbit", "sprite": "res://none.png",
		"wander_radius": 6, "wander_speed": 1.5, "wander_interval": 3.0,
		"flees_player": true, "flee_radius": 5.0, "flee_speed": 4.0,
		"body_width": 0.5, "body_height": 0.375})
	_registry.register({"id": "player", "category": "creature",
		"display_name": "Player", "sprite": "res://none.png"})
	_registry.register({"id": "cow", "category": "creature",
		"display_name": "Cow", "sprite": "res://none.png",
		"wander_radius": 4, "wander_speed": 1.0, "wander_interval": 4.0,
		"flees_player": false})

	_zone = _make_zone()
	_collision = CollisionBuilder.new()
	_system = AnimalSystem.new()
	_system.rng = RandomNumberGenerator.new()
	_system.rng.seed = SEED


func _spawn(string_id: String, at: Vector2) -> int:
	return _zone.entities.spawn(_registry.numeric_of(string_id), at)


## Advances the simulation `ticks` times at a fixed 60 Hz step, with the
## player parked far away unless told otherwise.
func _run(ticks: int, player_pos: Vector2 = Vector2(-100.0, -100.0)) -> void:
	for i: int in range(ticks):
		_system.tick(_zone, _registry, _collision, player_pos, 1.0 / 60.0)


func test_a_creature_with_a_wander_radius_is_tracked() -> void:
	var id: int = _spawn("rabbit", Vector2(16.5, 16.5))
	_run(1)
	assert_eq(_system.tracked_ids(), PackedInt32Array([id]))


func test_a_creature_without_a_wander_radius_is_never_tracked() -> void:
	var _id: int = _spawn("player", Vector2(16.5, 16.5))
	_run(10)
	assert_eq(_system.tracked_ids(), PackedInt32Array(),
		"the player is inert because its content says so, not because of a type check")


func test_the_player_is_never_moved() -> void:
	var id: int = _spawn("player", Vector2(16.5, 16.5))
	_run(60)
	assert_eq(_zone.entities.get_position(id), Vector2(16.5, 16.5))


func test_an_untracked_id_has_no_mode() -> void:
	assert_eq(_system.mode_of(9999), -1)


func test_an_animal_starts_in_wander() -> void:
	var id: int = _spawn("rabbit", Vector2(16.5, 16.5))
	_run(1)
	assert_eq(_system.mode_of(id), AnimalSystem.MODE_WANDER)


func test_a_despawned_animal_is_pruned() -> void:
	var id: int = _spawn("rabbit", Vector2(16.5, 16.5))
	_run(1)
	assert_eq(_system.tracked_ids().size(), 1, "precondition: it was tracked")

	var _ok: bool = _zone.entities.despawn(id)
	_run(1)

	assert_eq(_system.tracked_ids(), PackedInt32Array(),
		"state keyed by a dead id would leak for the life of the process")


func test_an_animal_spawned_later_is_picked_up() -> void:
	_run(5)
	var id: int = _spawn("rabbit", Vector2(10.5, 10.5))
	_run(1)
	assert_eq(_system.tracked_ids(), PackedInt32Array([id]),
		"a Phase 5 load spawns animals after boot and must need no registration call")
```

- [x] **Step 2: Run the test and watch it fail**

Run: `./tools/run_tests.sh`

Expected: FAIL — the suite will not load, reporting an unknown identifier
`AnimalSystem`. `run_tests.sh` exits 3 on that ("a test script failed to
load"), which is the runner working as designed.

- [x] **Step 3: Write the skeleton**

Create `src/systems/animal_system.gd`:

```gdscript
class_name AnimalSystem
extends RefCounted
## Wander, flee and return, for every creature whose content gives it a
## wander radius.
##
## Deliberately dumb. This exists to validate the entity pipeline end to
## end -- authored spawn, simulation tick, collision, render -- not to be
## good at AI. Pathfinding, hunger and schedules are Stage 5.
##
## An instance rather than a set of statics, for the same reason
## CollisionBuilder is one: it caches per-animal state that would otherwise
## have to live in the caller, and the caller is presentation, which is the
## layer that should hold the least. MovementSystem's purity is the right
## shape for resolving one move and the wrong shape for remembering where a
## rabbit was going.
##
## Nothing here is persisted. EntityStore's blob column exists for exactly
## this kind of state and stays unused: a saved wander target would cost a
## format change, a migration and a fixture test for something the player
## cannot perceive.

const MODE_WANDER: int = 0
const MODE_FLEE: int = 1
const MODE_RETURN: int = 2

## Injected so every test is exactly reproducible. The caller seeds it;
## main.gd uses the zone's generation_seed, so one world always behaves the
## same way.
var rng: RandomNumberGenerator = RandomNumberGenerator.new()

## entity id -> {home: Vector2, target: Vector2, timer: float, mode: int}
var _state: Dictionary = {}


func tracked_ids() -> PackedInt32Array:
	var out: PackedInt32Array = []
	for id: int in _state:
		out.append(id)
	out.sort()
	return out


func mode_of(id: int) -> int:
	if not _state.has(id):
		return -1
	return int((_state[id] as Dictionary)["mode"])


## Advances every animal by `delta`. Returns the number that moved.
func tick(
	zone: Zone,
	registry: ContentRegistry,
	collision: CollisionBuilder,
	player_pos: Vector2,
	delta: float
) -> int:
	var moved: int = 0
	var live: Dictionary = {}

	for id: int in zone.entities.ids():
		var def: Dictionary = registry.def_of(zone.entities.get_type_id(id))
		# An animal is any creature with somewhere to wander. There is no
		# check against "rabbit" here and there must never be one: a second
		# animal is one JSON file plus one PNG.
		if float(def.get("wander_radius", 0)) <= 0.0:
			continue
		live[id] = true

		var pos: Vector2 = zone.entities.get_position(id)
		if not _state.has(id):
			# Home is captured lazily, wherever the animal is first seen.
			# Animals restored by a Phase 5 load are therefore anchored
			# where the save put them, with no load hook and no
			# registration call.
			_state[id] = {
				"home": pos, "target": pos, "timer": 0.0, "mode": MODE_WANDER,
			}

	# .keys() returns a copy, so erasing inside this loop is safe.
	for id: int in _state.keys():
		if not live.has(id):
			_state.erase(id)

	return moved
```

- [x] **Step 4: Run the tests and watch them pass**

Run: `./tools/run_tests.sh`

Expected: PASS, one new script and seven new tests.

- [x] **Step 5: Confirm the architecture guard is still clean**

Run: `./tools/godot.sh --headless --path . -s tools/guard.gd`

Expected: `Architecture guard: clean`. `RandomNumberGenerator`, `Dictionary`
and `Vector2` are none of them nodes.

- [x] **Step 6: Commit**

```bash
git add src/systems/animal_system.gd tests/test_animal_system.gd
git commit -m "$(cat <<'EOF'
feat: track animals without moving them yet

Three rules that are cheap now and expensive to retrofit: which entities
animate is a data question (wander_radius above zero, never a check
against "rabbit"), home is captured lazily so a Phase 5 load needs no
registration hook, and dead ids are pruned every tick so state cannot
leak for the life of the process.

tick() returns 0 by construction. Movement arrives in the next task.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

- [x] **Step 7: Tick this task**

```bash
python3 tools/mark_task_done.py 2 --plan docs/superpowers/plans/2026-09-12-rp1-phase4b-living-world.md
git add docs/superpowers/plans/2026-09-12-rp1-phase4b-living-world.md
git commit -m "docs: tick Phase 4b task 2"
```

---

## Task 3: Wander

**Files:**
- Modify: `src/systems/animal_system.gd`
- Test: `tests/test_animal_system.gd`

**Interfaces:**
- Consumes:
  - `CollisionBuilder.solids_near(zone: Zone, area: Rect2) -> Array[Rect2i]`
  - `MovementSystem.move(pos: Vector2, velocity: Vector2, delta: float, body: Vector2, solids: Array[Rect2i], bounds: Rect2) -> Vector2`
  - `MovementSystem.facing_from(velocity: Vector2, current: int) -> int`
- Produces: no signature change. `tick()` now returns a real count, and
  these constants become readable by tests:
  `MAX_TARGET_TRIES: int = 4`, `ARRIVE_EPSILON: float = 0.2`,
  `DEFAULT_WANDER_SPEED: float = 1.5`, `DEFAULT_WANDER_INTERVAL: float = 3.0`,
  `DEFAULT_BODY: Vector2 = Vector2(0.5, 0.375)`

- [x] **Step 1: Write the failing tests**

Append to `tests/test_animal_system.gd`:

```gdscript
## A 32x32 zone whose middle column is water, so there is real geometry to
## be blocked by.
func _make_walled_zone() -> Zone:
	var zone: Zone = Zone.new("walled", Vector2i(32, 32))
	var grass: int = _registry.numeric_of("grass")
	var water: int = _registry.numeric_of("water")
	for y: int in range(32):
		for x: int in range(32):
			zone.set_terrain(Vector2i(x, y), water if x == 16 else grass)
	Walkability.recompute_zone(zone, _registry)
	zone.clear_dirty()
	return zone


func test_an_animal_moves() -> void:
	var id: int = _spawn("rabbit", Vector2(16.5, 16.5))
	_run(300)
	assert_ne(_zone.entities.get_position(id), Vector2(16.5, 16.5),
		"five seconds of wandering must go somewhere")


func test_an_animal_stays_within_its_wander_radius() -> void:
	var home: Vector2 = Vector2(16.5, 16.5)
	var id: int = _spawn("rabbit", home)
	# The radius is 6 tiles. A target may be drawn AT the radius, and the
	# animal stops within ARRIVE_EPSILON of it and may overshoot by one
	# tick of travel, so the true bound is nearer 6.03 than 6.0.
	for i: int in range(600):
		_system.tick(_zone, _registry, _collision, Vector2(-100.0, -100.0), 1.0 / 60.0)
		assert_lt(_zone.entities.get_position(id).distance_to(home), 6.5,
			"tick %d left the wander radius with no player anywhere near" % i)


func test_wandering_never_ends_a_tick_inside_a_solid() -> void:
	_zone = _make_walled_zone()
	var id: int = _spawn("rabbit", Vector2(10.5, 16.5))
	for i: int in range(600):
		_system.tick(_zone, _registry, _collision, Vector2(-100.0, -100.0), 1.0 / 60.0)
		var p: Vector2 = _zone.entities.get_position(id)
		var tile: Vector2i = Vector2i(floori(p.x), floori(p.y))
		assert_true(_zone.is_walkable(tile),
			"tick %d put the rabbit on %s, which is not walkable" % [i, tile])


func test_an_enclosed_animal_dwells_rather_than_spinning() -> void:
	# A single walkable tile ringed by water: every target draw is rejected.
	var zone: Zone = Zone.new("box", Vector2i(32, 32))
	var grass: int = _registry.numeric_of("grass")
	var water: int = _registry.numeric_of("water")
	for y: int in range(32):
		for x: int in range(32):
			zone.set_terrain(Vector2i(x, y), water)
	zone.set_terrain(Vector2i(16, 16), grass)
	Walkability.recompute_zone(zone, _registry)
	zone.clear_dirty()
	_zone = zone

	var id: int = _spawn("rabbit", Vector2(16.5, 16.5))
	_run(300)

	var p: Vector2 = _zone.entities.get_position(id)
	assert_almost_eq(p.x, 16.5, 0.6, "it has nowhere to go, so it stays on its tile")
	assert_almost_eq(p.y, 16.5, 0.6, "it has nowhere to go, so it stays on its tile")


func test_the_same_seed_reproduces_the_same_walk() -> void:
	var id_a: int = _spawn("rabbit", Vector2(16.5, 16.5))
	_run(120)
	var first: Vector2 = _zone.entities.get_position(id_a)

	before_each()
	var id_b: int = _spawn("rabbit", Vector2(16.5, 16.5))
	_run(120)

	assert_eq(_zone.entities.get_position(id_b), first,
		"same seed, same walk -- or no behaviour test here means anything")


func test_a_different_seed_walks_differently() -> void:
	var id_a: int = _spawn("rabbit", Vector2(16.5, 16.5))
	_run(120)
	var first: Vector2 = _zone.entities.get_position(id_a)

	before_each()
	_system.rng.seed = SEED + 1
	var id_b: int = _spawn("rabbit", Vector2(16.5, 16.5))
	_run(120)

	assert_ne(_zone.entities.get_position(id_b), first)


func test_identical_animals_do_not_move_in_lockstep() -> void:
	# The dwell interval is jittered, so eight rabbits authored from one
	# definition must not share a heartbeat.
	var a: int = _spawn("rabbit", Vector2(10.5, 10.5))
	var b: int = _spawn("rabbit", Vector2(10.5, 10.5))
	_run(240)
	assert_ne(_zone.entities.get_position(a), _zone.entities.get_position(b))


func test_facing_follows_movement() -> void:
	var id: int = _spawn("rabbit", Vector2(16.5, 16.5))
	_zone.entities.set_facing(id, MovementSystem.FACING_N)
	_run(300)
	# Not asserting a specific octant -- that would be asserting the RNG.
	# Asserting only that facing is maintained, as the player's is.
	assert_between(_zone.entities.get_facing(id), 0, 7)


func test_tick_reports_how_many_moved() -> void:
	var _a: int = _spawn("rabbit", Vector2(10.5, 10.5))
	var _b: int = _spawn("rabbit", Vector2(20.5, 20.5))
	var _p: int = _spawn("player", Vector2(16.5, 16.5))
	# Run until at least one has stopped dwelling and started walking.
	var seen: int = 0
	for i: int in range(600):
		seen = maxi(seen, _system.tick(
			_zone, _registry, _collision, Vector2(-100.0, -100.0), 1.0 / 60.0))
	assert_gt(seen, 0, "something moved")
	assert_lt(seen, 3, "the player is not one of them")
```

- [x] **Step 2: Run the tests and watch them fail**

Run: `./tools/run_tests.sh`

Expected: FAIL. `tick()` returns 0 and never writes a position, so
`test_an_animal_moves`, `test_a_different_seed_walks_differently`,
`test_identical_animals_do_not_move_in_lockstep` and
`test_tick_reports_how_many_moved` all fail. The bounded ones
(`..._stays_within_its_wander_radius`, `..._never_ends_a_tick_inside_a_solid`,
`..._dwells_rather_than_spinning`, `test_the_same_seed_...`) pass trivially
against a motionless animal — they are there to stay true once it moves.

- [x] **Step 3: Implement wander**

In `src/systems/animal_system.gd`, add the constants below `MODE_RETURN`:

```gdscript
## Target draws before an animal gives up and dwells. A rabbit ringed by
## water must not spin through a thousand rejected draws every frame.
const MAX_TARGET_TRIES: int = 4

## How close counts as arrived, in tiles.
const ARRIVE_EPSILON: float = 0.2

# Fallbacks for optional fields. This is engine behaviour rather than
# content -- the same treatment ZoneLoader gives biome and generation_seed
# -- and it keeps a half-authored creature moving rather than motionless
# with no error anywhere.
const DEFAULT_WANDER_SPEED: float = 1.5
const DEFAULT_WANDER_INTERVAL: float = 3.0
const DEFAULT_BODY: Vector2 = Vector2(0.5, 0.375)
```

Replace the body of the `for id: int in zone.entities.ids():` loop, after the
lazy-registration block, with:

```gdscript
		var s: Dictionary = _state[id]
		var radius: float = float(def.get("wander_radius", 0))
		var speed: float = float(def.get("wander_speed", DEFAULT_WANDER_SPEED))

		var velocity: Vector2 = _wander_velocity(s, pos, radius, speed, zone, delta)

		if velocity.is_zero_approx():
			continue

		var body: Vector2 = Vector2(
			float(def.get("body_width", DEFAULT_BODY.x)),
			float(def.get("body_height", DEFAULT_BODY.y))
		)
		# The same call Player._physics_process makes, with the same slack:
		# the area only selects which chunks are consulted, and solids_near
		# returns whole chunks regardless.
		var area: Rect2 = Rect2(pos - Vector2(2.0, 2.0), Vector2(4.0, 4.0))
		var solids: Array[Rect2i] = collision.solids_near(zone, area)
		var bounds: Rect2 = Rect2(Vector2.ZERO, Vector2(zone.size_tiles))
		var next: Vector2 = MovementSystem.move(
			pos, velocity, delta, body, solids, bounds)

		if next.distance_to(pos) <= 0.0:
			continue
		zone.entities.set_position(id, next)
		zone.entities.set_facing(
			id, MovementSystem.facing_from(velocity, zone.entities.get_facing(id)))
		moved += 1
```

and add the two helpers at the end of the file:

```gdscript
## Dwell, then walk to a target drawn near home. Returns a desired velocity,
## or zero while standing still.
func _wander_velocity(
	s: Dictionary, pos: Vector2, radius: float, speed: float,
	zone: Zone, delta: float
) -> Vector2:
	if float(s["timer"]) > 0.0:
		s["timer"] = float(s["timer"]) - delta
		if float(s["timer"]) <= 0.0:
			_pick_target(s, pos, radius, zone)
		return Vector2.ZERO

	var target: Vector2 = s["target"]
	if pos.distance_to(target) <= ARRIVE_EPSILON:
		# Arrived. Stand still for a jittered interval so animals authored
		# from one definition do not share a heartbeat.
		s["timer"] = _interval_for(s)
		return Vector2.ZERO
	return (target - pos).normalized() * speed


## Draws a point uniformly from the disc of `radius` around home.
##
## sqrt() on the radius is what makes it uniform: without it, points bunch
## toward the centre and an animal barely leaves its anchor.
func _pick_target(s: Dictionary, pos: Vector2, radius: float, zone: Zone) -> void:
	var home: Vector2 = s["home"]
	for _try: int in range(MAX_TARGET_TRIES):
		var angle: float = rng.randf() * TAU
		var dist: float = sqrt(rng.randf()) * radius
		var candidate: Vector2 = home + Vector2(cos(angle), sin(angle)) * dist
		var tile: Vector2i = Vector2i(floori(candidate.x), floori(candidate.y))
		if zone.in_bounds(tile) and zone.is_walkable(tile):
			s["target"] = candidate
			return
	# Every draw was blocked. Stay put; the next dwell will try again.
	s["target"] = pos
```

and, so the jitter has one home:

```gdscript
## The dwell interval, jittered +/-50%.
func _interval_for(s: Dictionary) -> float:
	var base: float = float(s.get("interval", DEFAULT_WANDER_INTERVAL))
	return base * rng.randf_range(0.5, 1.5)
```

`_interval_for` reads the interval from the state dictionary, so store it at
registration. Extend the lazy-registration block in `tick()` to:

```gdscript
		if not _state.has(id):
			_state[id] = {
				"home": pos, "target": pos, "timer": 0.0, "mode": MODE_WANDER,
				"interval": float(def.get("wander_interval", DEFAULT_WANDER_INTERVAL)),
			}
```

- [x] **Step 4: Run the tests and watch them pass**

Run: `./tools/run_tests.sh`

Expected: PASS, nine more tests.

If `test_an_animal_stays_within_its_wander_radius` fails by a small margin,
the cause is the body box rather than the logic: the anchor is a point and the
animal is a box, so the slack in the assertion (0.5 tiles) must exceed half the
body width. Do not widen the assertion past that without saying why.

- [x] **Step 5: Commit**

```bash
git add src/systems/animal_system.gd tests/test_animal_system.gd
git commit -m "$(cat <<'EOF'
feat: animals wander

A target drawn uniformly from a disc around home, walked at wander_speed,
then a jittered dwell. Movement goes through MovementSystem.move() against
CollisionBuilder.solids_near() -- the same two calls Player makes -- so
there is exactly one collision rule in the project and an animal cannot
walk through a wall the player cannot.

Two details that would otherwise be wrong and invisible: sqrt() on the
draw radius, without which points bunch toward the centre and animals
barely leave their anchor; and a retry cap, without which an animal ringed
by water spins through rejected draws every frame.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

- [x] **Step 6: Tick this task**

```bash
python3 tools/mark_task_done.py 3 --plan docs/superpowers/plans/2026-09-12-rp1-phase4b-living-world.md
git add docs/superpowers/plans/2026-09-12-rp1-phase4b-living-world.md
git commit -m "docs: tick Phase 4b task 3"
```

---

## Task 4: Flee

**Files:**
- Modify: `src/systems/animal_system.gd`
- Test: `tests/test_animal_system.gd`

**Interfaces:**
- Consumes: `AnimalSystem.mode_of(id: int) -> int` from Task 2
- Produces: no signature change. New constants:
  `DEFAULT_FLEE_RADIUS: float = 5.0`, `DEFAULT_FLEE_SPEED: float = 4.0`

- [x] **Step 1: Write the failing tests**

Append to `tests/test_animal_system.gd`:

```gdscript
func test_a_nearby_player_triggers_flee() -> void:
	var id: int = _spawn("rabbit", Vector2(16.5, 16.5))
	_run(1, Vector2(18.0, 16.5))
	assert_eq(_system.mode_of(id), AnimalSystem.MODE_FLEE)


func test_a_distant_player_does_not() -> void:
	var id: int = _spawn("rabbit", Vector2(16.5, 16.5))
	_run(1, Vector2(16.5 + 20.0, 16.5))
	assert_eq(_system.mode_of(id), AnimalSystem.MODE_WANDER)


func test_fleeing_increases_the_distance_to_the_player() -> void:
	var player: Vector2 = Vector2(14.0, 16.5)
	var id: int = _spawn("rabbit", Vector2(16.5, 16.5))
	var before: float = _zone.entities.get_position(id).distance_to(player)

	_run(30, player)

	assert_gt(_zone.entities.get_position(id).distance_to(player), before,
		"half a second of fleeing must open the gap")


func test_an_animal_that_does_not_flee_ignores_the_player() -> void:
	var id: int = _spawn("cow", Vector2(16.5, 16.5))
	_run(60, Vector2(16.6, 16.5))
	assert_eq(_system.mode_of(id), AnimalSystem.MODE_WANDER,
		"flees_player is false, so the player is scenery -- no code knows what a cow is")


func test_fleeing_may_leave_the_wander_radius() -> void:
	# A player parked just inside the flee radius, on the home side, pushes
	# the rabbit out past its 6-tile fence. A hard fence here would pin it
	# against an invisible wall, which reads as broken.
	var home: Vector2 = Vector2(16.5, 16.5)
	var id: int = _spawn("rabbit", home)
	var escaped: bool = false
	for i: int in range(600):
		var p: Vector2 = _zone.entities.get_position(id)
		# Chase: stand one tile behind the rabbit, on the home side, so it
		# is driven outward rather than in a circle.
		var chase: Vector2 = home
		if p.distance_to(home) > 0.1:
			chase = p + (home - p).normalized()
		_system.tick(_zone, _registry, _collision, chase, 1.0 / 60.0)
		if _zone.entities.get_position(id).distance_to(home) > 6.5:
			escaped = true
			break
	assert_true(escaped, "flee must beat the wander radius")


func test_fleeing_never_ends_a_tick_inside_a_solid() -> void:
	_zone = _make_walled_zone()
	var id: int = _spawn("rabbit", Vector2(14.5, 16.5))
	# Push it straight at the water column.
	for i: int in range(300):
		_system.tick(_zone, _registry, _collision, Vector2(12.0, 16.5), 1.0 / 60.0)
		var p: Vector2 = _zone.entities.get_position(id)
		var tile: Vector2i = Vector2i(floori(p.x), floori(p.y))
		assert_true(_zone.is_walkable(tile),
			"tick %d drove the fleeing rabbit onto %s" % [i, tile])
```

- [x] **Step 2: Run the tests and watch them fail**

Run: `./tools/run_tests.sh`

Expected: FAIL. `mode_of` never returns `MODE_FLEE`, so
`test_a_nearby_player_triggers_flee` and `test_fleeing_may_leave_the_wander_radius`
fail, and `test_fleeing_increases_the_distance_to_the_player` fails because a
wandering rabbit ignores the player entirely.

- [x] **Step 3: Implement flee**

Add the constants beside the other defaults:

```gdscript
const DEFAULT_FLEE_RADIUS: float = 5.0
const DEFAULT_FLEE_SPEED: float = 4.0
```

In `tick()`, replace the single `_wander_velocity(...)` call with mode
selection followed by a velocity for the chosen mode:

```gdscript
		var s: Dictionary = _state[id]
		var radius: float = float(def.get("wander_radius", 0))
		var speed: float = float(def.get("wander_speed", DEFAULT_WANDER_SPEED))
		var flees: bool = bool(def.get("flees_player", false))
		var flee_radius: float = float(def.get("flee_radius", DEFAULT_FLEE_RADIUS))
		var to_player: float = pos.distance_to(player_pos)

		# An animal whose content does not say it flees never consults
		# flee_radius at all: to it, the player is scenery.
		if flees and to_player < flee_radius:
			s["mode"] = MODE_FLEE

		var velocity: Vector2 = Vector2.ZERO
		if int(s["mode"]) == MODE_FLEE:
			velocity = _flee_velocity(
				pos, player_pos, float(def.get("flee_speed", DEFAULT_FLEE_SPEED)))
		else:
			velocity = _wander_velocity(s, pos, radius, speed, zone, delta)
```

and add the helper:

```gdscript
## Straight away from the player, at flee_speed. Ignores the wander radius:
## a hard fence pins a cornered animal against an invisible wall, which
## reads as broken within thirty seconds of play.
func _flee_velocity(pos: Vector2, player_pos: Vector2, speed: float) -> Vector2:
	var away: Vector2 = pos - player_pos
	if away.is_zero_approx():
		# Exactly co-located, which only happens in a test. Any direction
		# will do; normalized() on a zero vector returns zero and would
		# leave the animal standing inside the player.
		away = Vector2.RIGHT
	return away.normalized() * speed
```

Nothing leaves `MODE_FLEE` yet — that is Task 5, and
`test_a_distant_player_does_not` passes meanwhile because an animal that has
never been frightened is still in `MODE_WANDER`.

- [x] **Step 4: Run the tests and watch them pass**

Run: `./tools/run_tests.sh`

Expected: PASS, six more tests.

- [x] **Step 5: Commit**

```bash
git add src/systems/animal_system.gd tests/test_animal_system.gd
git commit -m "$(cat <<'EOF'
feat: animals flee the player

Fleeing ignores the wander radius on purpose. The alternative -- a hard
fence at the radius -- means a player who walks into it pins the animal
against an invisible wall, which reads as broken immediately.

Whether an animal flees at all is one bool in its content. A creature
with flees_player false never consults flee_radius and treats the player
as scenery, so a cow differs from a rabbit by a field rather than by a
branch on its id.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

- [x] **Step 6: Tick this task**

```bash
python3 tools/mark_task_done.py 4 --plan docs/superpowers/plans/2026-09-12-rp1-phase4b-living-world.md
git add docs/superpowers/plans/2026-09-12-rp1-phase4b-living-world.md
git commit -m "docs: tick Phase 4b task 4"
```

---

## Task 5: Return, and the hysteresis that stops the jitter

**Files:**
- Modify: `src/systems/animal_system.gd`
- Test: `tests/test_animal_system.gd`

**Interfaces:**
- Consumes: `AnimalSystem.MODE_RETURN` from Task 2
- Produces: `CALM_FACTOR: float = 1.5`. The calm distance is
  `flee_radius * CALM_FACTOR`, derived rather than authored.

- [ ] **Step 1: Write the failing tests**

Append to `tests/test_animal_system.gd`:

```gdscript
func test_a_frightened_animal_walks_home() -> void:
	var home: Vector2 = Vector2(16.5, 16.5)
	var id: int = _spawn("rabbit", home)

	# Frighten it far out of its radius.
	for i: int in range(600):
		var p: Vector2 = _zone.entities.get_position(id)
		var chase: Vector2 = home
		if p.distance_to(home) > 0.1:
			chase = p + (home - p).normalized()
		_system.tick(_zone, _registry, _collision, chase, 1.0 / 60.0)
		if _zone.entities.get_position(id).distance_to(home) > 7.0:
			break
	assert_gt(_zone.entities.get_position(id).distance_to(home), 7.0,
		"precondition: it was driven outside its radius")

	# Withdraw and let it settle.
	_run(1, Vector2(-100.0, -100.0))
	assert_eq(_system.mode_of(id), AnimalSystem.MODE_RETURN)

	_run(900, Vector2(-100.0, -100.0))
	assert_lt(_zone.entities.get_position(id).distance_to(home), 6.5,
		"fifteen seconds is ample to walk six tiles home")
	assert_eq(_system.mode_of(id), AnimalSystem.MODE_WANDER,
		"and it goes back to wandering once inside")


func test_a_frightened_animal_still_inside_its_radius_just_resumes_wandering() -> void:
	var id: int = _spawn("rabbit", Vector2(16.5, 16.5))
	_run(1, Vector2(18.0, 16.5))
	assert_eq(_system.mode_of(id), AnimalSystem.MODE_FLEE, "precondition")

	_run(1, Vector2(-100.0, -100.0))
	assert_eq(_system.mode_of(id), AnimalSystem.MODE_WANDER,
		"it never left home, so there is nothing to return to")


func test_the_mode_does_not_flicker_at_the_flee_boundary() -> void:
	# A player parked exactly at flee_radius. With a single threshold the
	# animal would flip mode every tick and vibrate in place; the calm
	# distance is 1.5x the flee radius precisely to stop that.
	var id: int = _spawn("rabbit", Vector2(16.5, 16.5))
	var player: Vector2 = Vector2(16.5 + 5.0, 16.5)

	var flips: int = 0
	var last: int = -1
	for i: int in range(120):
		# Re-park the player at exactly flee_radius from wherever it is now.
		var p: Vector2 = _zone.entities.get_position(id)
		player = p + Vector2(5.0, 0.0)
		_system.tick(_zone, _registry, _collision, player, 1.0 / 60.0)
		var mode: int = _system.mode_of(id)
		if last != -1 and mode != last:
			flips += 1
		last = mode
	assert_lt(flips, 3, "%d mode changes in two seconds is a vibrating rabbit" % flips)


func test_returning_never_ends_a_tick_inside_a_solid() -> void:
	_zone = _make_walled_zone()
	var home: Vector2 = Vector2(10.5, 16.5)
	var id: int = _spawn("rabbit", home)
	# Drive it west, away from home, then release it and let it walk back.
	for i: int in range(240):
		_system.tick(_zone, _registry, _collision,
			_zone.entities.get_position(id) + Vector2(1.0, 0.0), 1.0 / 60.0)
	for i: int in range(600):
		_system.tick(_zone, _registry, _collision, Vector2(-100.0, -100.0), 1.0 / 60.0)
		var p: Vector2 = _zone.entities.get_position(id)
		var tile: Vector2i = Vector2i(floori(p.x), floori(p.y))
		assert_true(_zone.is_walkable(tile),
			"tick %d put the returning rabbit on %s" % [i, tile])
```

- [ ] **Step 2: Run the tests and watch them fail**

Run: `./tools/run_tests.sh`

Expected: FAIL. Nothing ever leaves `MODE_FLEE`, so
`test_a_frightened_animal_walks_home` fails at its first `mode_of` assertion
and `test_a_frightened_animal_still_inside_its_radius_just_resumes_wandering`
fails at its second.

- [ ] **Step 3: Implement the calm distance and the walk home**

Add the constant beside the other defaults:

```gdscript
## The calm distance is flee_radius * CALM_FACTOR. Derived rather than
## authored: with a single threshold, an animal sitting exactly at
## flee_radius flips mode every tick and visibly vibrates in place.
const CALM_FACTOR: float = 1.5
```

In `tick()`, extend the mode selection to the full three-way rule:

```gdscript
		if flees and to_player < flee_radius:
			s["mode"] = MODE_FLEE
		elif int(s["mode"]) == MODE_FLEE and (
				not flees or to_player > flee_radius * CALM_FACTOR):
			# Calm again. Between flee_radius and the calm distance neither
			# branch fires and the mode simply holds, which is the whole
			# point of the gap.
			if pos.distance_to(s["home"]) > radius:
				s["mode"] = MODE_RETURN
			else:
				s["mode"] = MODE_WANDER
				_pick_target(s, pos, radius, zone)
		elif int(s["mode"]) == MODE_RETURN and pos.distance_to(s["home"]) <= radius:
			s["mode"] = MODE_WANDER
			_pick_target(s, pos, radius, zone)
```

and extend the velocity selection:

```gdscript
		var velocity: Vector2 = Vector2.ZERO
		if int(s["mode"]) == MODE_FLEE:
			velocity = _flee_velocity(
				pos, player_pos, float(def.get("flee_speed", DEFAULT_FLEE_SPEED)))
		elif int(s["mode"]) == MODE_RETURN:
			# Straight home at walking pace. Without this, frightened
			# animals migrate across the map over a long session and the
			# zone's authored composition quietly drifts.
			var home: Vector2 = s["home"]
			velocity = (home - pos).normalized() * speed
		else:
			velocity = _wander_velocity(s, pos, radius, speed, zone, delta)
```

- [ ] **Step 4: Run the tests and watch them pass**

Run: `./tools/run_tests.sh`

Expected: PASS, four more tests.

- [ ] **Step 5: Commit**

```bash
git add src/systems/animal_system.gd tests/test_animal_system.gd
git commit -m "$(cat <<'EOF'
feat: frightened animals walk home

Without a return mode, fleeing animals migrate across the map over a long
session and the zone's authored composition quietly drifts away from what
was painted.

The calm distance is 1.5x the flee radius rather than a second authored
number. With a single threshold an animal sitting exactly at flee_radius
flips mode every tick and vibrates in place; the gap between the two
distances is what holds the mode steady, and it has its own test.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

- [ ] **Step 6: Tick this task**

```bash
python3 tools/mark_task_done.py 5 --plan docs/superpowers/plans/2026-09-12-rp1-phase4b-living-world.md
git add docs/superpowers/plans/2026-09-12-rp1-phase4b-living-world.md
git commit -m "docs: tick Phase 4b task 5"
```

---

## Task 6: A blocked animal re-targets

**Files:**
- Modify: `src/systems/animal_system.gd`
- Test: `tests/test_animal_system.gd`

**Interfaces:**
- Produces: `STUCK_EPSILON: float = 0.01`

An animal walking into a wall slides along it, so genuinely stuck means a
corner pointing exactly at its target. Rare, but it lasts for the whole dwell
interval when it happens, and a rabbit pressed into a tree for three seconds
is the kind of thing a player notices immediately.

- [ ] **Step 1: Write the failing tests**

Append to `tests/test_animal_system.gd`:

```gdscript
func test_a_blocked_animal_stops_pressing_into_the_wall() -> void:
	# Home sits hard against the water column, so a good share of the
	# target draws land on the far side of it and the rabbit walks into
	# the wall. Without re-targeting it presses there until its dwell
	# timer expires; with it, the rabbit keeps finding somewhere to go.
	_zone = _make_walled_zone()
	var home: Vector2 = Vector2(15.5, 16.5)
	var id: int = _spawn("rabbit", home)

	var positions: Dictionary = {}
	for i: int in range(900):
		_system.tick(_zone, _registry, _collision, Vector2(-100.0, -100.0), 1.0 / 60.0)
		var p: Vector2 = _zone.entities.get_position(id)
		positions[Vector2i(roundi(p.x * 4.0), roundi(p.y * 4.0))] = true

	assert_gt(positions.size(), 20,
		"fifteen seconds beside a wall visited only %d distinct spots" % positions.size())


func test_a_stuck_returning_animal_goes_back_to_wandering() -> void:
	# Returning walks straight at home and does not use a target, so a
	# returning animal wedged in a corner has nothing to re-draw. It drops
	# to wander instead, whose targets are drawn around home and therefore
	# pull it back anyway.
	_zone = _make_walled_zone()
	# Home is east of the wall; drive the rabbit west of it, so the walk
	# home runs straight into the water column.
	var home: Vector2 = Vector2(20.5, 16.5)
	var id: int = _spawn("rabbit", home)
	_zone.entities.set_position(id, Vector2(12.5, 16.5))
	_run(1, Vector2(11.0, 16.5))
	_run(600, Vector2(-100.0, -100.0))

	assert_ne(_system.mode_of(id), AnimalSystem.MODE_RETURN,
		"it cannot reach home through a wall and must not spend forever trying")
```

- [ ] **Step 2: Run the tests and watch them fail**

Run: `./tools/run_tests.sh`

Expected: FAIL on `test_a_stuck_returning_animal_goes_back_to_wandering` —
the animal holds `MODE_RETURN` indefinitely, pressed against the water.
`test_a_blocked_animal_stops_pressing_into_the_wall` may pass or fail
depending on the seed; if it passes, do not weaken it. It is there to stay
true, and Step 3 is what makes it reliably true rather than luckily true.

- [ ] **Step 3: Implement the stuck rule**

Add the constant beside the other defaults:

```gdscript
## Movement below this in one tick, while trying to move, means blocked.
const STUCK_EPSILON: float = 0.01
```

In `tick()`, replace the tail of the loop — from `var next: Vector2 = ...`
onward — with:

```gdscript
		var next: Vector2 = MovementSystem.move(
			pos, velocity, delta, body, solids, bounds)

		if next.distance_to(pos) < STUCK_EPSILON:
			# Blocked by geometry. Wandering re-draws a target rather than
			# pressing into the wall until the dwell timer expires.
			# Returning walks straight at home and has no target to
			# re-draw, so it drops to wander, whose targets are drawn
			# around home and pull it back regardless.
			if int(s["mode"]) == MODE_WANDER:
				_pick_target(s, pos, radius, zone)
			elif int(s["mode"]) == MODE_RETURN:
				s["mode"] = MODE_WANDER
				_pick_target(s, pos, radius, zone)
			continue

		zone.entities.set_position(id, next)
		zone.entities.set_facing(
			id, MovementSystem.facing_from(velocity, zone.entities.get_facing(id)))
		moved += 1
```

Note this replaces the earlier `if next.distance_to(pos) <= 0.0: continue`
guard from Task 3 — `STUCK_EPSILON` subsumes it.

- [ ] **Step 4: Run the tests and watch them pass**

Run: `./tools/run_tests.sh`

Expected: PASS, two more tests, and every earlier test still green.

- [ ] **Step 5: Commit**

```bash
git add src/systems/animal_system.gd tests/test_animal_system.gd
git commit -m "$(cat <<'EOF'
feat: a blocked animal picks somewhere else to go

MovementSystem slides along walls, so genuinely stuck needs a corner
pointing at the target -- rare, but it lasts a whole dwell interval, and
a rabbit pressed into a tree for three seconds is the first thing a
player notices.

A returning animal has no target to re-draw, since returning walks
straight at home, so it drops to wander instead. Wander targets are drawn
around home, which pulls it back anyway, and that is cheaper than teaching
this phase to path around an obstacle.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

- [ ] **Step 6: Tick this task**

```bash
python3 tools/mark_task_done.py 6 --plan docs/superpowers/plans/2026-09-12-rp1-phase4b-living-world.md
git add docs/superpowers/plans/2026-09-12-rp1-phase4b-living-world.md
git commit -m "docs: tick Phase 4b task 6"
```

---

## Task 7: Tick it in the game, and measure it

**Files:**
- Modify: `src/presentation/main.gd`
- Test: `tests/test_animal_budget.gd`

**Interfaces:**
- Consumes: `AnimalSystem.tick(...)` complete, `Player.entity_id: int`,
  `ZoneRenderer.zone: Zone`
- Produces: nothing new in code. The game visibly has animals in it.

- [ ] **Step 1: Write the budget test**

Create `tests/test_animal_budget.gd`:

```gdscript
extends GutTest
## Sixty-four animals -- eight times the shipped population -- tick well
## inside one frame.
##
## Builds its own population rather than using data/zone/home/'s eight, so
## the number keeps meaning something when the zone grows. This is the
## same shape as test_zone_load_budget.gd.

const ANIMALS: int = 64
const TICKS: int = 60
## 4 ms of a 16 ms frame, for eight times the population we ship. Generous
## on purpose: a budget test that flakes on a loaded CI runner gets
## deleted, and a deleted test measures nothing.
const BUDGET_MS: int = 240

var _zone: Zone
var _registry: ContentRegistry
var _collision: CollisionBuilder
var _system: AnimalSystem


func before_each() -> void:
	_registry = ContentRegistry.new()
	_registry.register({"id": "grass", "category": "terrain",
		"display_name": "Grass", "sprite": "res://none.png", "walkable": true})
	_registry.register({"id": "rabbit", "category": "creature",
		"display_name": "Rabbit", "sprite": "res://none.png",
		"wander_radius": 6, "wander_speed": 1.5, "wander_interval": 3.0,
		"flees_player": true, "flee_radius": 5.0, "flee_speed": 4.0,
		"body_width": 0.5, "body_height": 0.375})

	_zone = Zone.new("budget", Vector2i(128, 128))
	var grass: int = _registry.numeric_of("grass")
	for y: int in range(128):
		for x: int in range(128):
			_zone.set_terrain(Vector2i(x, y), grass)
	Walkability.recompute_zone(_zone, _registry)
	_zone.clear_dirty()

	var rabbit: int = _registry.numeric_of("rabbit")
	for n: int in range(ANIMALS):
		var _id: int = _zone.entities.spawn(
			rabbit, Vector2(8.5 + float(n % 16) * 7.0, 8.5 + float(n / 16) * 7.0))

	_collision = CollisionBuilder.new()
	_system = AnimalSystem.new()
	_system.rng = RandomNumberGenerator.new()
	_system.rng.seed = 7


func test_sixty_four_animals_tick_inside_the_frame_budget() -> void:
	# One warm-up tick so the collision cache is built and the measurement
	# is of steady-state work rather than of first-touch chunk meshing.
	var _warm: int = _system.tick(_zone, _registry, _collision, Vector2(64.5, 64.5), 1.0 / 60.0)

	var start: int = Time.get_ticks_msec()
	for i: int in range(TICKS):
		var _moved: int = _system.tick(
			_zone, _registry, _collision, Vector2(64.5, 64.5), 1.0 / 60.0)
	var elapsed: int = Time.get_ticks_msec() - start

	assert_lt(elapsed, BUDGET_MS,
		"%d animals x %d ticks took %d ms; the budget is %d ms"
			% [ANIMALS, TICKS, elapsed, BUDGET_MS])
```

- [ ] **Step 2: Run it and watch it pass**

Run: `./tools/run_tests.sh`

Expected: PASS. This is a regression guard rather than a red-to-green step —
`AnimalSystem` is already complete. Do not weaken it to manufacture a failure.
If it FAILS, the cause is real and is almost certainly `solids_near()` being
called with an area spanning more chunks than intended; check the `Rect2` in
`tick()` matches `Player._physics_process`'s.

- [ ] **Step 3: Hold the registry and the system in `main.gd`**

`main.gd` builds a `ContentRegistry` as a local in `_ready()` and drops it.
The tick needs it every frame. Add two fields beside the existing ones:

```gdscript
var _registry: ContentRegistry = null
var _animals: AnimalSystem = null
```

and change the line in `_ready()` that reads

```gdscript
	var registry: ContentRegistry = ContentRegistry.new()
```

to

```gdscript
	var registry: ContentRegistry = ContentRegistry.new()
	_registry = registry
```

Keeping the local means the rest of `_ready()` is untouched.

- [ ] **Step 4: Create and seed the system**

In `_ready()`, immediately after `_collision = CollisionBuilder.new()`:

```gdscript
	_animals = AnimalSystem.new()
	_animals.rng = RandomNumberGenerator.new()
	# Seeded from the zone rather than from the clock, so one world always
	# behaves the same way and a bug reported against it is reproducible.
	_animals.rng.seed = zone.generation_seed
```

- [ ] **Step 5: Tick it**

Add at the end of `src/presentation/main.gd`:

```gdscript
## Animals move in the physics step, alongside the player, so both see the
## same fixed delta and the same collision geometry.
func _physics_process(delta: float) -> void:
	if _animals == null or _renderer == null or _renderer.zone == null:
		return
	if _player == null or not _renderer.zone.entities.has(_player.entity_id):
		return
	var zone: Zone = _renderer.zone
	var _moved: int = _animals.tick(
		zone,
		_registry,
		_collision,
		zone.entities.get_position(_player.entity_id),
		delta
	)
```

Animals read the player's position from the entity store, so depending on node
order they may see last tick's position rather than this one's. At 4 tiles per
second that is under 7 cm of apparent lag; the spec records it as accepted
rather than fixed, because fixing it means an ordering contract between two
nodes for no visible gain.

- [ ] **Step 6: Run every gate**

```bash
./tools/run_tests.sh
./tools/godot.sh --headless --path . -s tools/guard.gd
./tools/godot.sh --headless --path . -s tools/smoke.gd
./tools/check_asset_licences.sh
./tools/check_palette.sh
./tools/check_zone.sh
```

Expected: six green.

- [ ] **Step 7: Watch them move**

```bash
./tools/godot.sh --path . -s tools/screenshot.gd -- --out=/tmp/animals_a.png
./tools/godot.sh --path . -s tools/screenshot.gd -- --out=/tmp/animals_b.png
```

`screenshot.gd` captures after a fixed warm-up, so both shots are of the same
instant of simulated time and will be identical. To see movement, temporarily
raise `WARMUP_FRAMES` in `tools/screenshot.gd` to 200 for the second shot,
compare, then **put it back**. The rabbits nearest the spawn point are around
(30,70) and (34,74); the camera starts at (64,60), so pass through a
temporarily-moved `player_spawn` in `data/zone/home/zone.json` if none is in
frame — and restore it with `git checkout data/zone/home/zone.json`.

Confirm a rabbit is in a different place in the two shots.

- [ ] **Step 8: Commit**

```bash
git add src/presentation/main.gd tests/test_animal_budget.gd
git commit -m "$(cat <<'EOF'
feat: tick the animals in the running game

main.gd holds the registry it previously dropped on the floor and ticks
AnimalSystem in _physics_process, beside the player, so both see the same
fixed delta and the same collision geometry. EntityRenderer already
repaints every frame, so movement needed nothing there.

The RNG is seeded from the zone's generation_seed rather than the clock:
one world always behaves the same way, so a bug reported against it can
be reproduced.

Sixty-four animals -- eight times what we ship -- tick in well under a
quarter of the frame budget.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

- [ ] **Step 9: Tick this task**

```bash
python3 tools/mark_task_done.py 7 --plan docs/superpowers/plans/2026-09-12-rp1-phase4b-living-world.md
git add docs/superpowers/plans/2026-09-12-rp1-phase4b-living-world.md
git commit -m "docs: tick Phase 4b task 7"
```

---

## Task 8: Close the phase

**Files:**
- Modify: `docs/superpowers/specs/2026-08-23-rp1-stage0-stage1-design.md` (§10)

- [ ] **Step 1: Record the dirty channel's move**

The Stage 1 design's Phase 4b bullet still promises the multi-consumer dirty
channel. Replace the `**Phase 4b — living world**` block with:

```markdown
**Phase 4b — living world** *(done)*

- `AnimalSystem`: wander within a radius, flee the player, walk home.
  Deliberately dumb — this validates the entity pipeline, not AI.

*(The multi-consumer dirty channel moved to Stage 2. Nothing in Stage 1
produces a tile mutation: building and harvesting are out of scope, and
animal movement is an entity row rather than a tile, so the channel's only
caller would have been its own test suite. See
`docs/superpowers/specs/2026-09-12-rp1-phase4b-living-world-design.md` §2.)*
```

- [ ] **Step 2: Verify the whole definition of done**

```bash
# Every gate.
./tools/run_tests.sh
./tools/godot.sh --headless --path . -s tools/guard.gd
./tools/godot.sh --headless --path . -s tools/smoke.gd
./tools/check_asset_licences.sh
./tools/check_palette.sh
./tools/check_zone.sh

# No content type is named in code.
grep -n '"rabbit"\|"cow"' src/ -r || echo "no creature id appears in src/"

# The exported build still boots.
./tools/godot.sh --headless --path . --export-pack "Linux" /tmp/rp1_4b.pck
./tools/godot.sh --headless --main-pack /tmp/rp1_4b.pck --quit-after 60 2>&1 | grep "RP1 "
rm -f /tmp/rp1_4b.pck
```

Record each result in the commit message.

- [ ] **Step 3: Prove the sharpest acceptance criterion**

A second animal must be one JSON file, one PNG and one line in a zone's
`entities` list, with no code change.

```bash
cat > data/creature/hare.json <<'JSON'
{"id": "hare", "category": "creature", "display_name": "Hare",
 "sprite": "res://assets/characters/rabbit.png",
 "wander_radius": 10, "wander_speed": 2.5, "wander_interval": 2.0,
 "flees_player": true, "flee_radius": 8.0, "flee_speed": 5.0,
 "body_width": 0.5, "body_height": 0.375,
 "tags": ["animal", "prey"]}
JSON
# Add one entity line to data/zone/home/zone.json:
#   {"type": "hare", "at": [66.5, 62.5]}
./tools/check_zone.sh
./tools/godot.sh --path . -s tools/screenshot.gd -- --out=/tmp/hare.png
```

Expected: the gate stays green and a second animal is visible near the spawn,
with no file under `src/` touched. Then remove it:

```bash
rm data/creature/hare.json
git checkout data/zone/home/zone.json
```

- [ ] **Step 4: Commit**

```bash
git add docs
git commit -m "$(cat <<'EOF'
docs: settle the Phase 4b definition of done

Records the dirty channel's move to Stage 2 in the Stage 1 design, where
the 4a/4b split is already recorded, and closes out the acceptance
criteria.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

- [ ] **Step 5: Tick this task**

```bash
python3 tools/mark_task_done.py 8 --plan docs/superpowers/plans/2026-09-12-rp1-phase4b-living-world.md
git add docs/superpowers/plans/2026-09-12-rp1-phase4b-living-world.md
git commit -m "docs: tick Phase 4b task 8"
```

---

## Definition of done for Phase 4b

- [ ] Animals visibly move: two screenshots of the same scene with a rabbit
      in different places
- [ ] `./tools/run_tests.sh` green, including every test in Tasks 1-7
- [ ] `tools/guard.gd`, `tools/smoke.gd`, `check_asset_licences.sh`,
      `check_palette.sh` and `check_zone.sh` green
- [ ] 64 animals tick inside the frame budget (`test_animal_budget.gd`)
- [ ] **Adding a second animal is one JSON file, one PNG and one line in a
      zone's `entities` list, with no code change** — seen to work, then
      reverted
- [ ] No creature id appears anywhere under `src/`
- [ ] A fleeing animal leaves its wander radius and walks home again
- [ ] The exported build boots and still renders
- [ ] The Stage 1 design §10 records the dirty channel's move to Stage 2
