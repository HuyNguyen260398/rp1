# Phase 5 — Game Loop Closure Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A main menu in front of the world, a pause menu inside it, autosave
behind it — and the four save-layer defects that only a real round trip
exposes, fixed with a regression test each.

**Architecture:** All game-loop policy lives in `GameSession`, a node-free
`RefCounted` in `src/systems/`: whether a save exists, what New World means,
when autosave fires, how the backup rotates. `main.gd` shrinks to a router
owning the `ContentRegistry`, a `Theme`, a UI `CanvasLayer` and — only while
playing — one `World` child holding everything `main.gd` does today. The menus
hold no logic; they emit signals and the router calls the session. That is why
every rule in this phase is testable headless and no menu needs a test.

**Tech Stack:** Godot 4.7.2 standard build, GDScript with static typing, GUT
for tests.

**Spec:** `docs/superpowers/specs/2026-09-12-rp1-phase5-game-loop-design.md`

## Global Constraints

Copied from `CLAUDE.md` and the spec. Every task's requirements implicitly
include this section.

- Godot **4.7.2**, standard build. **Not the Mono build.** Invoke Godot only
  through `./tools/godot.sh`. Never hardcode a binary path.
- GDScript only. Static typing everywhere: `var x: int = 0`,
  `func f(a: Vector2i) -> void:`.
- `src/core/` and `src/systems/` **MUST NOT reference Godot nodes.** No
  `extends Node`, no `get_tree()`, no `Engine.`, no `.tscn`, no `add_child(`,
  no `get_node(`, no `queue_free(`. These folders extend `RefCounted` only.
  Enforced by `tools/guard.gd`. `Theme`, `StyleBoxFlat`, `Font` and `Image`
  are `Resource` types, **not nodes** — but they belong in `src/ui/`
  regardless, because they are presentation.
- Run tests with `./tools/run_tests.sh` — never call `gut_cmdln.gd` directly.
  The runner does a mandatory `--import` pass first; without it GUT reports
  missing `class_name`s **and exits 0**, so a broken suite looks green.
- Never use `load()`, `ResourceLoader`, or `.tres`/`.res` for save data.
- **`get_var()` always passes `false`.** (Nothing in this phase uses it. It is
  here so nobody adds one.)
- Every binary file starts with a 4-byte magic and a `u32` format version,
  both plaintext, outside any compressed region.
- All writes are atomic: temp file, `flush()`, `close()`, then rename.
- Saves persist **string ids**, never runtime numeric ids.
- Any change to a save format requires a migration function and a test that
  loads a committed fixture from the previous version.
- Palette is fixed — Apollo, 46 colours, `tools/palette/apollo.json`. Do not
  introduce new colours.
- **Tests must never write to `user://saves/`.** Every test injects a
  `save_root` under `user://test_saves/` and removes it in `after_each`. A
  test that wrote to the real root would destroy the developer's world on
  every run.
- Conventional commit prefixes: `feat:`, `test:`, `ci:`, `docs:`, `fix:`.
- Each task produces two commits: the code, then a `docs:` commit ticking that
  task's checkboxes. **Always pass `--plan`** —
  `python3 tools/mark_task_done.py <N> --plan docs/superpowers/plans/2026-09-12-rp1-phase5-game-loop.md` — because the
  tool's default glob points at the Phase 0-2 plan and will silently tick
  the wrong document. Never tick a checkbox by hand.

---

## File Structure

**Create:**

| File | Responsibility |
|---|---|
| `src/systems/session_open_result.gd` | Typed result of opening a world: `ok`, `error`, `zone`, `player_entity_id`, `player_spawn`, `is_new` |
| `src/systems/game_session.gd` | All game-loop policy: has_save, open_new, open_saved, autosave clock, save_now, playtime |
| `src/core/save/world_meta.gd` | `meta.json` at the save root: read, write, defaults |
| `src/presentation/world.gd` | Everything `main.gd` does today, built from a `Zone` it is handed |
| `src/ui/ui_theme.gd` | One `Theme` built from Apollo colours; the only place a `Color` is written |
| `src/ui/main_menu.gd` | New World / Continue / Quit. Emits signals, holds no logic |
| `src/ui/pause_menu.gd` | Resume / Quit to Menu / Quit to Desktop. Emits signals |
| `src/ui/confirm_panel.gd` | In-scene confirm/report panel. Not `ConfirmationDialog` |
| `tests/test_world_meta.gd` | meta.json round trip, defaults, malformed input |
| `tests/test_game_session.gd` | Every rule in `GameSession` |
| `tests/test_ui_theme.gd` | Every theme colour is one of Apollo's 46 |
| `tests/test_input_map.gd` | The `pause` action exists and the movement actions survived a hand-edit |
| `tests/fixtures/v1_entities.dat` | Committed v1 fixture, written by the real v1 encoder |

**Modify:**

| File | Change |
|---|---|
| `src/core/entity_store.gd` | `_home_x` / `_home_y` columns, `get_home`, `set_home` |
| `src/core/save/entity_codec.gd` | Format v2: home in the row, 18 → 26 bytes |
| `src/core/save/migrations.gd` | Entity migration path beside the chunk path |
| `src/core/save/save_manager.gd` | Entity type-id remap, walkability recompute, `keep_backup` |
| `src/systems/animal_system.gd` | Anchor home from the store, not from current position; `home_of` |
| `src/presentation/player.gd` | `adopt()` beside `spawn()` |
| `src/presentation/main.gd` | Shrinks to a router |
| `project.godot` | `pause` input action |
| `tools/make_fixture.gd` | Also writes the entities fixture |
| `tools/smoke.gd` | Session round trip on top of the data-layer one |
| `tests/test_entity_store.gd`, `tests/test_entity_codec.gd`, `tests/test_migrations.gd`, `tests/test_save_manager.gd`, `tests/test_animal_system.gd` | New cases |

**Task order is bottom-up.** The store grows a column, the codec learns to
carry it, the save layer's four defects are fixed, the session is built on top,
and only then does anything render. Every task leaves the suite green and the
game runnable.

---

## Task 1: The entity store carries a home anchor

The column every later task depends on. `spawn()` anchors home at the spawn
position, which is exactly the lazy capture `AnimalSystem` does today — so
this task changes no behaviour, it only moves where the value lives.

**Files:**
- Modify: `src/core/entity_store.gd`
- Modify: `src/core/save/entity_codec.gd:85-92` (the `restore_row` call site)
- Test: `tests/test_entity_store.gd`

**Interfaces:**
- Produces: `EntityStore.get_home(id: int) -> Vector2`,
  `EntityStore.set_home(id: int, pos: Vector2) -> void`, and
  `EntityStore.restore_row(id: int, type_id: int, pos: Vector2, facing: int, entity_flags: int, blob_offset: int, home: Vector2) -> void`
  — note `home` is appended last, so existing calls break loudly rather than
  silently taking the wrong argument.

- [x] **Step 1: Write the failing tests**

Add to `tests/test_entity_store.gd`:

```gdscript
func test_spawn_anchors_home_at_the_spawn_position() -> void:
	var s: EntityStore = EntityStore.new()
	var id: int = s.spawn(7, Vector2(4.5, 9.5))
	assert_eq(s.get_home(id), Vector2(4.5, 9.5))


func test_moving_an_entity_does_not_move_its_home() -> void:
	var s: EntityStore = EntityStore.new()
	var id: int = s.spawn(7, Vector2(4.5, 9.5))
	s.set_position(id, Vector2(40.0, 90.0))
	assert_eq(s.get_home(id), Vector2(4.5, 9.5))
	assert_eq(s.get_position(id), Vector2(40.0, 90.0))


func test_set_home_is_independent_of_position() -> void:
	var s: EntityStore = EntityStore.new()
	var id: int = s.spawn(7, Vector2(4.5, 9.5))
	s.set_home(id, Vector2(1.5, 2.5))
	assert_eq(s.get_home(id), Vector2(1.5, 2.5))
	assert_eq(s.get_position(id), Vector2(4.5, 9.5))


func test_a_reused_slot_does_not_inherit_the_previous_home() -> void:
	# Slot reuse is the one path where a stale column value survives a
	# despawn. Without the reuse branch setting home, the new entity would
	# silently adopt the dead one's anchor.
	var s: EntityStore = EntityStore.new()
	var first: int = s.spawn(7, Vector2(4.5, 9.5))
	assert_true(s.despawn(first))
	var second: int = s.spawn(7, Vector2(60.5, 60.5))
	assert_eq(s.get_home(second), Vector2(60.5, 60.5))


func test_restore_row_takes_home_verbatim() -> void:
	var s: EntityStore = EntityStore.new()
	s.restore_row(9, 7, Vector2(4.5, 9.5), 2, EntityStore.FLAG_ACTIVE, 0, Vector2(1.5, 2.5))
	assert_eq(s.get_position(9), Vector2(4.5, 9.5))
	assert_eq(s.get_home(9), Vector2(1.5, 2.5))
```

- [x] **Step 2: Run them and watch them fail**

Run: `./tools/run_tests.sh`
Expected: FAIL — `get_home` is not a known method, and `restore_row` is called
with 7 arguments but expects 6.

- [x] **Step 3: Add the columns**

In `src/core/entity_store.gd`, beside `_x` / `_y`:

```gdscript
## Where the entity belongs, as opposed to where it currently is.
## AnimalSystem wanders around this point and walks back to it. It is a
## column rather than system state because it is authored data: a home
## rebuilt from current position on every load lets the authored world
## erode across sessions. See Phase 5 design §5.
var _home_x: PackedFloat32Array = PackedFloat32Array()
var _home_y: PackedFloat32Array = PackedFloat32Array()
```

In `spawn()`, the fresh-slot branch appends `pos.x` / `pos.y` to the two new
arrays, and the reuse branch assigns `_home_x[slot] = pos.x` /
`_home_y[slot] = pos.y`. Both branches must be touched — the reuse branch is
what `test_a_reused_slot_does_not_inherit_the_previous_home` checks.

Then the accessors, matching the shape of `get_position` / `set_position`:

```gdscript
func get_home(id: int) -> Vector2:
	var slot: int = _slot_by_id[id]
	return Vector2(_home_x[slot], _home_y[slot])


func set_home(id: int, pos: Vector2) -> void:
	var slot: int = _slot_by_id[id]
	_home_x[slot] = pos.x
	_home_y[slot] = pos.y
```

And `restore_row` gains a trailing `home: Vector2` parameter that appends to
both arrays.

- [x] **Step 4: Fix the one call site**

`EntityCodec.decode` calls `restore_row`. v1 bytes carry no home, and the
value that reproduces today's behaviour exactly is the entity's position:

```gdscript
		var pos: Vector2 = Vector2(bytes.decode_float(o + 6), bytes.decode_float(o + 10))
		store.restore_row(
			bytes.decode_u32(o),
			bytes.decode_u16(o + 4),
			pos,
			bytes.decode_u8(o + 14),
			bytes.decode_u8(o + 15),
			bytes.decode_u16(o + 16),
			pos,  # v1 has no home column; Task 4 replaces this
		)
```

- [x] **Step 5: Run the whole suite**

Run: `./tools/run_tests.sh`
Expected: PASS, including every pre-existing entity and codec test.

- [x] **Step 6: Commit**

```bash
git add src/core/entity_store.gd src/core/save/entity_codec.gd tests/test_entity_store.gd
git commit -m "feat: entity store carries a home anchor"
```

- [x] **Step 7: Tick the plan**

```bash
python3 tools/mark_task_done.py 1 --plan docs/superpowers/plans/2026-09-12-rp1-phase5-game-loop.md
git add docs/superpowers/plans/2026-09-12-rp1-phase5-game-loop.md
git commit -m "docs: tick Phase 5 task 1"
```

---

## Task 2: Animals anchor from the store

`AnimalSystem` captures `home` lazily from wherever it first sees the animal
standing. After Task 1 the store holds the real anchor, so the system reads it
from there. This is the behaviour change the whole home-persistence argument is
for; the tests in Tasks 3–4 make it survive a save.

**Files:**
- Modify: `src/systems/animal_system.gd:96-104` (the lazy-init block)
- Test: `tests/test_animal_system.gd`

**Interfaces:**
- Consumes: `EntityStore.get_home(id) -> Vector2` (Task 1)
- Produces: `AnimalSystem.home_of(id: int) -> Vector2` — returns
  `Vector2.ZERO` for an untracked id, matching how `mode_of` handles one.

- [x] **Step 1: Write the failing test**

Add to `tests/test_animal_system.gd`:

```gdscript
func test_home_comes_from_the_store_not_from_where_the_animal_stands() -> void:
	# A rabbit that was saved mid-flee is restored far from home. Its
	# anchor must be the one the save carried, not the spot the load
	# happened to drop it on -- otherwise the authored world erodes a
	# little on every save/load cycle. Phase 5 design §5.
	var zone: Zone = _grass_zone()
	var id: int = zone.entities.spawn(_registry.numeric_of("rabbit"), Vector2(10.5, 10.5))
	zone.entities.set_home(id, Vector2(20.5, 20.5))

	var animals: AnimalSystem = AnimalSystem.new()
	animals.rng.seed = 1
	animals.tick(zone, _registry, CollisionBuilder.new(), Vector2(99.0, 99.0), 1.0 / 60.0)

	assert_eq(animals.home_of(id), Vector2(20.5, 20.5))


func test_home_of_an_untracked_id_is_zero() -> void:
	var animals: AnimalSystem = AnimalSystem.new()
	assert_eq(animals.home_of(12345), Vector2.ZERO)
```

`_grass_zone()` already exists in this file — reuse it rather than building a
new fixture. If its name differs, use whatever the file's existing walkable
zone helper is called; do not add a second one.

- [x] **Step 2: Run it and watch it fail**

Run: `./tools/run_tests.sh`
Expected: FAIL — `home_of` is not a known method.

- [x] **Step 3: Read home from the store, and expose it**

In the lazy-init block, replace `"home": pos` with
`"home": zone.entities.get_home(id)`, and update the comment, which currently
explains the old behaviour:

```gdscript
		if not _state.has(id):
			# Home comes from the entity row, which the save carries and
			# spawn() anchors at the spawn position. Reading it from `pos`
			# instead would re-anchor every animal to wherever a load
			# dropped it, moving the authored world a little each time.
			_state[id] = {
				"home": zone.entities.get_home(id),
				"target": pos, "timer": 0.0, "mode": MODE_WANDER,
				"interval": float(def.get("wander_interval", DEFAULT_WANDER_INTERVAL)),
			}
```

Then, beside `mode_of`:

```gdscript
## The anchor this animal wanders around. Vector2.ZERO if untracked.
func home_of(id: int) -> Vector2:
	if not _state.has(id):
		return Vector2.ZERO
	return _state[id]["home"]
```

- [x] **Step 4: Run the whole suite**

Run: `./tools/run_tests.sh`
Expected: PASS. The existing animal tests spawn animals and never call
`set_home`, so their anchors are unchanged — `spawn()` puts home at the spawn
position, which is what the lazy capture produced before.

- [x] **Step 5: Commit**

```bash
git add src/systems/animal_system.gd tests/test_animal_system.gd
git commit -m "feat: animals anchor from the entity row, not from where they stand"
```

- [x] **Step 6: Tick the plan**

```bash
python3 tools/mark_task_done.py 2 --plan docs/superpowers/plans/2026-09-12-rp1-phase5-game-loop.md
git add docs/superpowers/plans/2026-09-12-rp1-phase5-game-loop.md
git commit -m "docs: tick Phase 5 task 2"
```

---

## Task 3: Commit a v1 entities fixture — before the format changes

`CLAUDE.md` requires a test that loads a committed fixture from the previous
version. That fixture has to be written by the **real v1 encoder**, so it must
be generated and committed *before* Task 4 bumps the format. A fixture
hand-assembled after the bump proves only that the test author can write bytes.

**Files:**
- Modify: `tools/make_fixture.gd`
- Create: `tests/fixtures/v1_entities.dat`
- Test: `tests/test_migrations.gd`

**Interfaces:**
- Produces: `tests/fixtures/v1_entities.dat` — 3 entities, ids 1–3,
  `next_id` 4, positions `(4.5, 9.5)`, `(20.25, 33.75)`, `(127.5, 0.5)`,
  facings 0/2/3, all flagged `FLAG_ACTIVE | FLAG_PERSISTED`.

- [x] **Step 1: Extend the fixture tool**

Append to `tools/make_fixture.gd`'s `_init`, before `quit(0)`:

```gdscript
	var store: EntityStore = EntityStore.new()
	var a: int = store.spawn(11, Vector2(4.5, 9.5))
	var b: int = store.spawn(12, Vector2(20.25, 33.75))
	var c: int = store.spawn(13, Vector2(127.5, 0.5))
	store.set_facing(b, 2)
	store.set_facing(c, 3)

	var ent_path: String = "res://tests/fixtures/v%d_entities.dat" % EntityCodec.FORMAT_VERSION
	var ef: FileAccess = FileAccess.open(ent_path, FileAccess.WRITE)
	ef.store_buffer(EntityCodec.encode(store))
	ef.close()
	print("wrote ", ent_path)
```

Update the file's docstring: it writes *fixtures*, plural, one per codec.

- [x] **Step 2: Generate the fixture**

Run: `./tools/godot.sh --headless --path . -s tools/make_fixture.gd`
Expected: prints `wrote res://tests/fixtures/v1_entities.dat`. Confirm with
`ls -l tests/fixtures/` that the file is **78 bytes** (24-byte header + 3 rows
of 18).

- [x] **Step 3: Write the test that reads it**

Add to `tests/test_migrations.gd`:

```gdscript
func test_v1_entities_fixture_still_decodes() -> void:
	# This passes trivially today, when v1 is current. It is committed now
	# so that Task 4's format bump has a real v1 file to migrate, written
	# by the real v1 encoder.
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(
		"res://tests/fixtures/v1_entities.dat")
	assert_gt(bytes.size(), 0, "fixture is missing; run tools/make_fixture.gd")

	var result: DecodeResult = EntityCodec.decode(bytes)
	assert_true(result.ok, result.error)

	var store: EntityStore = result.value
	assert_eq(store.count(), 3)
	assert_eq(store.get_position(1), Vector2(4.5, 9.5))
	assert_eq(store.get_position(3), Vector2(127.5, 0.5))
	assert_eq(store.get_facing(2), 2)
	assert_eq(store.next_id(), 4)
```

- [x] **Step 4: Run the suite**

Run: `./tools/run_tests.sh`
Expected: PASS.

- [x] **Step 5: Commit**

```bash
git add tools/make_fixture.gd tests/fixtures/v1_entities.dat tests/test_migrations.gd
git commit -m "test: commit a v1 entities fixture before the format changes"
```

- [x] **Step 6: Tick the plan**

```bash
python3 tools/mark_task_done.py 3 --plan docs/superpowers/plans/2026-09-12-rp1-phase5-game-loop.md
git add docs/superpowers/plans/2026-09-12-rp1-phase5-game-loop.md
git commit -m "docs: tick Phase 5 task 3"
```

---

## Task 4: Entity format v2 carries home

The first time the migration machinery written in Phase 2 actually migrates
anything. The v1 → v2 rule is that home defaults to the row's saved
**position**, which is exactly the lazy capture v1 builds performed — so a v1
save loads and behaves identically to the current build.

**Files:**
- Modify: `src/core/save/entity_codec.gd`
- Modify: `src/core/save/migrations.gd`
- Test: `tests/test_entity_codec.gd`, `tests/test_migrations.gd`

**Interfaces:**
- Consumes: `EntityStore.get_home` / `restore_row(..., home)` (Task 1)
- Produces: `EntityCodec.FORMAT_VERSION == 2`, `EntityCodec.ROW_BYTES == 26`,
  `Migrations.migrate_entities(version: int, store: EntityStore) -> DecodeResult`

- [x] **Step 1: Write the failing tests**

Add to `tests/test_entity_codec.gd`:

```gdscript
func test_home_round_trips_independently_of_position() -> void:
	var store: EntityStore = EntityStore.new()
	var id: int = store.spawn(11, Vector2(4.5, 9.5))
	store.set_home(id, Vector2(64.25, 12.75))

	var result: DecodeResult = EntityCodec.decode(EntityCodec.encode(store))
	assert_true(result.ok, result.error)
	var back: EntityStore = result.value
	assert_eq(back.get_position(id), Vector2(4.5, 9.5))
	assert_eq(back.get_home(id), Vector2(64.25, 12.75))


func test_the_row_is_twenty_six_bytes() -> void:
	# Guards the header arithmetic: a wrong ROW_BYTES makes decode reject
	# every file it wrote, with a confusing "truncated" message.
	var store: EntityStore = EntityStore.new()
	store.spawn(11, Vector2(1.5, 1.5))
	store.spawn(12, Vector2(2.5, 2.5))
	assert_eq(EntityCodec.encode(store).size(), EntityCodec.HEADER_BYTES + 2 * 26)
```

Add to `tests/test_migrations.gd`:

```gdscript
func test_v1_entities_migrate_with_home_defaulting_to_position() -> void:
	# The v1 build anchored home wherever the animal stood, so defaulting
	# home to the saved position makes a v1 save behave after the upgrade
	# exactly as it behaved before it.
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(
		"res://tests/fixtures/v1_entities.dat")
	var result: DecodeResult = EntityCodec.decode(bytes)
	assert_true(result.ok, result.error)

	var store: EntityStore = result.value
	assert_eq(store.get_home(1), store.get_position(1))
	assert_eq(store.get_home(3), Vector2(127.5, 0.5))


func test_entities_from_the_future_are_refused_not_guessed_at() -> void:
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(
		"res://tests/fixtures/v1_entities.dat")
	bytes.encode_u32(EntityCodec.OFF_VERSION, EntityCodec.FORMAT_VERSION + 1)
	var result: DecodeResult = EntityCodec.decode(bytes)
	assert_false(result.ok)
	assert_string_contains(result.error, "newer")
```

- [x] **Step 2: Run them and watch them fail**

Run: `./tools/run_tests.sh`
Expected: FAIL — `test_the_row_is_twenty_six_bytes` reports 18-byte rows, and
the home round trip returns the position because Task 1 left home hardwired to
`pos` in `decode`.

- [x] **Step 3: Bump the codec**

In `src/core/save/entity_codec.gd`:

```gdscript
const FORMAT_VERSION: int = 2
const ROW_BYTES: int = 26
```

`encode` writes the two new floats at the end of the row:

```gdscript
		rows.encode_u16(o + 16, 0)  # blob_offset, reserved
		rows.encode_float(o + 18, store.get_home(id).x)
		rows.encode_float(o + 22, store.get_home(id).y)
```

`decode` reads a row whose width depends on the file's version, because a v1
file's rows are 18 bytes. Replace the fixed `ROW_BYTES` arithmetic:

```gdscript
	var version: int = bytes.decode_u32(OFF_VERSION)
	if version > FORMAT_VERSION:
		return DecodeResult.failure(
			"entities: format version %d is newer than supported version %d"
			% [version, FORMAT_VERSION]
		)

	var row_bytes: int = ROW_BYTES if version >= 2 else 18
	var count: int = bytes.decode_u32(OFF_COUNT)
	var expected: int = HEADER_BYTES + count * row_bytes
	if bytes.size() != expected:
		return DecodeResult.failure(
			"entities: file is %d bytes, expected %d for %d entities (truncated or corrupt count?)"
			% [bytes.size(), expected, count]
		)
```

and in the row loop:

```gdscript
		var pos: Vector2 = Vector2(bytes.decode_float(o + 6), bytes.decode_float(o + 10))
		# v1 rows have no home column. Defaulting it to the position is the
		# migration: it reproduces exactly what the v1 build did at runtime.
		var home: Vector2 = pos
		if version >= 2:
			home = Vector2(bytes.decode_float(o + 18), bytes.decode_float(o + 22))
		store.restore_row(
			bytes.decode_u32(o),
			bytes.decode_u16(o + 4),
			pos,
			bytes.decode_u8(o + 14),
			bytes.decode_u8(o + 15),
			bytes.decode_u16(o + 16),
			home,
		)
		o += row_bytes
```

- [x] **Step 4: Record the migration where migrations are recorded**

`Migrations` currently documents only the chunk path. The entity upgrade is
performed inside `decode` — a widening read, not a post-hoc rewrite — and that
decision needs to be written down where the next person will look for it. In
`src/core/save/migrations.gd`:

```gdscript
const CURRENT_ENTITY_VERSION: int = EntityCodec.FORMAT_VERSION


## Entity rows migrate *during* decode rather than after it, because v1 and
## v2 rows are different widths: the reader has to know the version to walk
## the file at all. This function exists so the upgrade path is discoverable
## from the same place as the chunk one, and so a v3 that cannot be handled
## by a widening read has somewhere to go.
static func entities_need_migration(version: int) -> bool:
	return version < CURRENT_ENTITY_VERSION
```

Extend the class docstring's "To add version 2" recipe to mention
`tools/make_fixture.gd` writing both fixtures.

- [x] **Step 5: Run the whole suite**

Run: `./tools/run_tests.sh`
Expected: PASS, including both v1-fixture tests from Task 3 — which now prove
the migration rather than the status quo.

- [x] **Step 6: Commit**

```bash
git add src/core/save/entity_codec.gd src/core/save/migrations.gd tests/test_entity_codec.gd tests/test_migrations.gd
git commit -m "feat: entity format v2 carries the home anchor"
```

- [x] **Step 7: Tick the plan**

```bash
python3 tools/mark_task_done.py 4 --plan docs/superpowers/plans/2026-09-12-rp1-phase5-game-loop.md
git add docs/superpowers/plans/2026-09-12-rp1-phase5-game-loop.md
git commit -m "docs: tick Phase 5 task 4"
```

---

## Task 5: Entity type ids survive content being added

Spec §2.2. `EntityCodec` writes the runtime numeric `type_id`, and
`SaveManager.load_zone` remaps the three tile columns and nothing else. Add one
creature JSON and every entity in every existing save is reinterpreted.

The translation table is already built two lines above where it is needed.

**Files:**
- Modify: `src/core/save/save_manager.gd:139-144`
- Test: `tests/test_save_manager.gd`

**Interfaces:**
- Consumes: `IdMap.build_translation(registry) -> PackedInt32Array` (existing)

- [x] **Step 1: Write the failing test**

Add to `tests/test_save_manager.gd`:

```gdscript
func test_entity_type_ids_survive_content_added_after_the_save() -> void:
	# ContentRegistry allocates numeric ids in load order, so registering
	# one extra creature before the real content shifts every id after it.
	# This is the exact scenario the string-id rule exists for, and until
	# now load_zone remapped the tile columns and left entity rows alone.
	var zone: Zone = _zone()
	var rabbit_id: int = zone.entities.spawn(
		_registry.numeric_of("rabbit"), Vector2(10.5, 10.5))
	var errs: PackedStringArray = SaveManager.save_zone(_root, zone, _registry, true)
	assert_eq(errs.size(), 0, ", ".join(errs))

	var shifted: ContentRegistry = ContentRegistry.new()
	shifted.register({
		"id": "aardvark", "category": "creature", "display_name": "Aardvark",
		"sprite": "", "wander_radius": 4,
	})
	var load_errs: PackedStringArray = shifted.load_from_dir("res://data")
	assert_eq(load_errs.size(), 0, ", ".join(load_errs))
	assert_ne(shifted.numeric_of("rabbit"), _registry.numeric_of("rabbit"),
		"the fixture registry must actually shift ids, or this proves nothing")

	var result: DecodeResult = SaveManager.load_zone(_root, "home", shifted)
	assert_true(result.ok, result.error)
	var back: Zone = result.value
	assert_eq(shifted.string_of(back.entities.get_type_id(rabbit_id)), "rabbit")


func test_an_entity_type_missing_from_the_build_becomes_the_placeholder() -> void:
	var zone: Zone = _zone()
	var gone: int = _registry.register({
		"id": "dodo", "category": "creature", "display_name": "Dodo", "sprite": "",
	})
	var id: int = zone.entities.spawn(gone, Vector2(5.5, 5.5))
	SaveManager.save_zone(_root, zone, _registry, true)

	# A registry built from data/ alone has never heard of a dodo.
	var plain: ContentRegistry = ContentRegistry.new()
	plain.load_from_dir("res://data")
	var result: DecodeResult = SaveManager.load_zone(_root, "home", plain)
	assert_true(result.ok, result.error)

	var type_id: int = (result.value as Zone).entities.get_type_id(id)
	assert_eq(plain.string_of(type_id), "dodo",
		"a missing entity type must keep its string, not be zeroed")
	assert_true(plain.is_placeholder(type_id))
```

- [x] **Step 2: Run them and watch them fail**

Run: `./tools/run_tests.sh`
Expected: FAIL — the first asserts `"rabbit"` and gets whatever content now
holds the old number; the second gets `""` or an unrelated id.

- [x] **Step 3: Remap the rows**

In `SaveManager.load_zone`, where `entities.dat` is decoded:

```gdscript
	var ent_path: String = zdir.path_join("entities.dat")
	if FileAccess.file_exists(ent_path):
		var ent: DecodeResult = EntityCodec.decode(FileAccess.get_file_as_bytes(ent_path))
		if not ent.ok:
			return DecodeResult.failure("entities.dat: %s" % ent.error)
		var store: EntityStore = ent.value
		# Entity type ids are runtime numbers like the tile columns, and
		# shift for the same reason. Remapping the columns and not the rows
		# meant one new creature JSON turned every rabbit in every save
		# into whatever now held its number.
		for id: int in store.ids():
			var saved: int = store.get_type_id(id)
			if saved < table.size():
				store.set_type_id(id, table[saved])
			else:
				store.set_type_id(id, ContentRegistry.ID_UNKNOWN)
		zone.entities = store
```

`EntityStore` has no `set_type_id`. Add it beside `get_type_id`, matching the
shape of the other setters:

```gdscript
func set_type_id(id: int, type_id: int) -> void:
	_type_id[_slot_by_id[id]] = type_id
```

- [x] **Step 4: Run the whole suite**

Run: `./tools/run_tests.sh`
Expected: PASS. `IdMap.build_translation` already resolves a saved string
absent from the build through `register_placeholder`, which is why the second
test passes without extra work.

- [x] **Step 5: Commit**

```bash
git add src/core/save/save_manager.gd src/core/entity_store.gd tests/test_save_manager.gd
git commit -m "fix: remap entity type ids on load, not just tile columns"
```

- [x] **Step 6: Tick the plan**

```bash
python3 tools/mark_task_done.py 5 --plan docs/superpowers/plans/2026-09-12-rp1-phase5-game-loop.md
git add docs/superpowers/plans/2026-09-12-rp1-phase5-game-loop.md
git commit -m "docs: tick Phase 5 task 5"
```

---

## Task 6: Walkability is recomputed on load

Spec §2.3, and the debt recorded at Stage 1 design line 313. `flags` is derived
data; a save written before a content change carries stale flags and the player
walks through a tree.

**Files:**
- Modify: `src/core/save/save_manager.gd` (end of `load_zone`)
- Test: `tests/test_save_manager.gd`

**Interfaces:**
- Consumes: `Walkability.recompute_zone(zone: Zone, registry: ContentRegistry) -> int`

- [x] **Step 1: Write the failing test**

```gdscript
func test_walkability_is_recomputed_on_load_not_trusted_from_disk() -> void:
	# flags is derived from terrain and object content, so a save written
	# before a content change carries stale flags. ZoneLoader already
	# refuses to trust an authored flags value; load_zone must not trust a
	# saved one either.
	var zone: Zone = _zone()
	var oak: int = _registry.numeric_of("oak_tree")
	zone.set_object(Vector2i(3, 3), oak)
	# Deliberately wrong: say the tile under the oak is walkable, and that
	# a plain grass tile is not.
	zone.set_flags(Vector2i(3, 3), Chunk.FLAG_WALKABLE)
	zone.set_flags(Vector2i(5, 5), 0)
	SaveManager.save_zone(_root, zone, _registry, true)

	var result: DecodeResult = SaveManager.load_zone(_root, "home", _registry)
	assert_true(result.ok, result.error)
	var back: Zone = result.value
	assert_false(back.is_walkable(Vector2i(3, 3)), "the oak's tile came back walkable")
	assert_true(back.is_walkable(Vector2i(5, 5)), "plain grass came back blocked")
```

- [x] **Step 2: Run it and watch it fail**

Run: `./tools/run_tests.sh`
Expected: FAIL on the first assertion — the wrong flags round-trip faithfully.

- [x] **Step 3: Recompute after the chunks are installed**

At the end of `load_zone`, after the entity block and before the return:

```gdscript
	# flags is derived, never authored and never trusted from disk: a save
	# written before a content change carries stale values. Same reasoning
	# as ZoneLoader, which refuses an authored flags column outright.
	Walkability.recompute_zone(zone, registry)

	return DecodeResult.success(zone)
```

- [x] **Step 4: Run the whole suite**

Run: `./tools/run_tests.sh`
Expected: PASS. Note this marks chunks dirty; `load_zone` already sets
`chunk.dirty = false` per chunk as it installs them, so add a
`zone.clear_dirty()` immediately after the recompute — a freshly loaded world
is by definition not in need of saving, and leaving it dirty would make the
first autosave rewrite all 16 chunks for nothing.

- [x] **Step 5: Commit**

```bash
git add src/core/save/save_manager.gd tests/test_save_manager.gd
git commit -m "fix: recompute walkability on load instead of trusting saved flags"
```

- [x] **Step 6: Tick the plan**

```bash
python3 tools/mark_task_done.py 6 --plan docs/superpowers/plans/2026-09-12-rp1-phase5-game-loop.md
git add docs/superpowers/plans/2026-09-12-rp1-phase5-game-loop.md
git commit -m "docs: tick Phase 5 task 6"
```

---

## Task 7: Backup rotation and recovery

Spec §4. One `.bak` rotation, defined **per file** rather than per directory:
rotating the whole save directory would mean copying the world on every
autosave, which stops being viable the moment Stage 2 makes chunks mutable.

Only the files an autosave rewrites are rotated. In Stage 1 that is
`entities.dat` (here) and `meta.json` (Task 9). Chunks are written once and
never again, so they have no `.bak` until something starts rewriting them.

**Files:**
- Modify: `src/core/save/save_manager.gd` (`atomic_write`, `save_zone`, `load_zone`)
- Test: `tests/test_save_manager.gd`

**Interfaces:**
- Produces: `SaveManager.atomic_write(path: String, bytes: PackedByteArray, keep_backup: bool = false) -> String`,
  `SaveManager.save_zone(save_root: String, zone: Zone, registry: ContentRegistry, all_chunks: bool = false, keep_backup: bool = false) -> PackedStringArray`,
  `SaveManager.load_zone(save_root: String, zone_id: String, registry: ContentRegistry, use_backup: bool = false) -> DecodeResult`

- [x] **Step 1: Write the failing tests**

```gdscript
func test_the_first_write_leaves_no_backup() -> void:
	var path: String = _root.path_join("thing.dat")
	assert_eq(SaveManager.atomic_write(path, "one".to_utf8_buffer(), true), "")
	assert_false(FileAccess.file_exists(path + ".bak"))


func test_a_second_write_rotates_the_first_into_the_backup() -> void:
	var path: String = _root.path_join("thing.dat")
	SaveManager.atomic_write(path, "one".to_utf8_buffer(), true)
	SaveManager.atomic_write(path, "two".to_utf8_buffer(), true)
	assert_eq(FileAccess.get_file_as_string(path), "two")
	assert_eq(FileAccess.get_file_as_string(path + ".bak"), "one")


func test_only_one_rotation_is_kept() -> void:
	var path: String = _root.path_join("thing.dat")
	for text: String in ["one", "two", "three"]:
		SaveManager.atomic_write(path, text.to_utf8_buffer(), true)
	assert_eq(FileAccess.get_file_as_string(path), "three")
	assert_eq(FileAccess.get_file_as_string(path + ".bak"), "two")
	assert_false(FileAccess.file_exists(path + ".bak.bak"))


func test_loading_from_the_backup_returns_the_previous_entities() -> void:
	var zone: Zone = _zone()
	var id: int = zone.entities.spawn(_registry.numeric_of("rabbit"), Vector2(10.5, 10.5))
	SaveManager.save_zone(_root, zone, _registry, true, true)

	zone.entities.set_position(id, Vector2(99.5, 99.5))
	SaveManager.save_zone(_root, zone, _registry, false, true)

	var live: DecodeResult = SaveManager.load_zone(_root, "home", _registry, false)
	var backup: DecodeResult = SaveManager.load_zone(_root, "home", _registry, true)
	assert_true(live.ok, live.error)
	assert_true(backup.ok, backup.error)
	assert_eq((live.value as Zone).entities.get_position(id), Vector2(99.5, 99.5))
	assert_eq((backup.value as Zone).entities.get_position(id), Vector2(10.5, 10.5))
```

- [x] **Step 2: Run them and watch them fail**

Run: `./tools/run_tests.sh`
Expected: FAIL — `atomic_write` takes two arguments, not three.

- [x] **Step 3: Rotate inside atomic_write**

```gdscript
## `keep_backup` renames any existing file to `path + ".bak"` before the
## new one takes its place. The window between the two renames is one
## rename wide, and a crash inside it leaves the .bak intact -- which is
## what load_zone's `use_backup` is for.
static func atomic_write(
	path: String, bytes: PackedByteArray, keep_backup: bool = false
) -> String:
	var dir: String = path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		var mk: int = DirAccess.make_dir_recursive_absolute(dir)
		if mk != OK:
			return "cannot create directory %s (error %d)" % [dir, mk]

	var tmp: String = path + ".tmp"
	var f: FileAccess = FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return "cannot open %s (error %d)" % [tmp, FileAccess.get_open_error()]
	f.store_buffer(bytes)
	f.flush()
	f.close()

	if keep_backup and FileAccess.file_exists(path):
		var rot: int = DirAccess.rename_absolute(path, path + ".bak")
		if rot != OK:
			return "cannot rotate %s to .bak (error %d)" % [path, rot]

	var err: int = DirAccess.rename_absolute(tmp, path)
	if err != OK:
		return "cannot rename %s -> %s (error %d)" % [tmp, path, err]
	return ""
```

- [x] **Step 4: Thread it through save_zone and load_zone**

`save_zone` gains `keep_backup: bool = false` and passes it to the
`entities.dat` write **only**. `id_map.json`, `zone_meta.json` and the chunks
keep `false`: they are written once per world and a rotation of an unchanged
file just doubles the disk cost.

`load_zone` gains `use_backup: bool = false`:

```gdscript
	var ent_name: String = "entities.dat.bak" if use_backup else "entities.dat"
	var ent_path: String = zdir.path_join(ent_name)
```

Document on `load_zone` that chunks have no backup because nothing rewrites
them yet, and that a Stage 2 which does must rotate them too.

- [x] **Step 5: Run the whole suite**

Run: `./tools/run_tests.sh`
Expected: PASS. Existing callers pass neither new argument and are unaffected
by both defaults.

- [x] **Step 6: Commit**

```bash
git add src/core/save/save_manager.gd tests/test_save_manager.gd
git commit -m "feat: one .bak rotation per rewritten save file, and recovery from it"
```

- [x] **Step 7: Tick the plan**

```bash
python3 tools/mark_task_done.py 7 --plan docs/superpowers/plans/2026-09-12-rp1-phase5-game-loop.md
git add docs/superpowers/plans/2026-09-12-rp1-phase5-game-loop.md
git commit -m "docs: tick Phase 5 task 7"
```

---

## Task 8: WorldMeta — the file that says a world exists

Spec §2.4 and §4. `SaveManager` writes `id_map.json` at the root and
`zone_meta.json` per zone; nothing writes the root `meta.json` the Stage 1
design specifies. Continue needs something to test for, and something to
report.

**Files:**
- Create: `src/core/save/world_meta.gd`
- Create: `tests/test_world_meta.gd`

**Interfaces:**
- Produces: `WorldMeta` with fields `save_version: int`, `zone_id: String`,
  `player_entity_id: int`, `created_unix: int`, `last_played_unix: int`,
  `playtime: float`; `WorldMeta.path_in(save_root: String) -> String`,
  `to_json_string() -> String`, `WorldMeta.from_json_string(text: String) -> DecodeResult`

- [x] **Step 1: Write the failing tests**

Create `tests/test_world_meta.gd`:

```gdscript
extends GutTest


func test_path_is_meta_json_at_the_save_root() -> void:
	assert_eq(WorldMeta.path_in("user://saves/home"), "user://saves/home/meta.json")


func test_round_trips_every_field() -> void:
	var m: WorldMeta = WorldMeta.new()
	m.zone_id = "home"
	m.player_entity_id = 42
	m.created_unix = 1757635200
	m.last_played_unix = 1757638800
	m.playtime = 1234.5

	var result: DecodeResult = WorldMeta.from_json_string(m.to_json_string())
	assert_true(result.ok, result.error)
	var back: WorldMeta = result.value
	assert_eq(back.zone_id, "home")
	assert_eq(back.player_entity_id, 42)
	assert_eq(back.created_unix, 1757635200)
	assert_eq(back.last_played_unix, 1757638800)
	assert_almost_eq(back.playtime, 1234.5, 0.001)


func test_json_is_human_readable() -> void:
	# meta.json is small and cold and worth reading with `cat`, which is
	# the whole reason it is JSON and not part of a binary file.
	var m: WorldMeta = WorldMeta.new()
	assert_string_contains(m.to_json_string(), "\n")


func test_malformed_json_is_a_failure_not_a_crash() -> void:
	var result: DecodeResult = WorldMeta.from_json_string("{ not json")
	assert_false(result.ok)
	assert_string_contains(result.error, "meta.json")


func test_json_that_is_not_an_object_is_a_failure() -> void:
	var result: DecodeResult = WorldMeta.from_json_string("[1, 2, 3]")
	assert_false(result.ok)


func test_a_save_version_from_the_future_is_refused() -> void:
	var result: DecodeResult = WorldMeta.from_json_string(
		'{"save_version": 99, "zone_id": "home"}')
	assert_false(result.ok)
	assert_string_contains(result.error, "newer")


func test_missing_fields_take_defaults() -> void:
	var result: DecodeResult = WorldMeta.from_json_string('{"save_version": 1}')
	assert_true(result.ok, result.error)
	var back: WorldMeta = result.value
	assert_eq(back.zone_id, "home")
	assert_eq(back.playtime, 0.0)
```

- [x] **Step 2: Run them and watch them fail**

Run: `./tools/run_tests.sh`
Expected: FAIL — `WorldMeta` is not a known identifier.

- [x] **Step 3: Write it**

Create `src/core/save/world_meta.gd`:

```gdscript
class_name WorldMeta
extends RefCounted
## The root meta.json: what Continue reads to know a world exists.
##
## JSON rather than binary for the same reason zone_meta.json is: it is
## small, cold, and worth reading with `cat` when a save misbehaves.
##
## `player_entity_id` is recorded rather than rediscovered by scanning for
## the row whose type is "player". A scan would silently pick the first of
## two player rows if a bug ever produced them; naming the id makes that
## state detectable instead.

const SAVE_VERSION: int = 1

var save_version: int = SAVE_VERSION
var zone_id: String = "home"
var player_entity_id: int = 0
var created_unix: int = 0
var last_played_unix: int = 0
var playtime: float = 0.0


static func path_in(save_root: String) -> String:
	return save_root.path_join("meta.json")


func to_json_string() -> String:
	return JSON.stringify({
		"save_version": save_version,
		"zone_id": zone_id,
		"player_entity_id": player_entity_id,
		"created_unix": created_unix,
		"last_played_unix": last_played_unix,
		"playtime": playtime,
	}, "  ", true)


static func from_json_string(text: String) -> DecodeResult:
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		return DecodeResult.failure("meta.json: malformed JSON")
	if not (json.data is Dictionary):
		return DecodeResult.failure("meta.json: top level is not an object")

	var doc: Dictionary = json.data
	var version: int = int(doc.get("save_version", SAVE_VERSION))
	if version > SAVE_VERSION:
		return DecodeResult.failure(
			"meta.json: save_version %d is newer than this build supports (%d)"
			% [version, SAVE_VERSION]
		)

	var m: WorldMeta = WorldMeta.new()
	m.save_version = version
	m.zone_id = str(doc.get("zone_id", "home"))
	m.player_entity_id = int(doc.get("player_entity_id", 0))
	m.created_unix = int(doc.get("created_unix", 0))
	m.last_played_unix = int(doc.get("last_played_unix", 0))
	m.playtime = float(doc.get("playtime", 0.0))
	return DecodeResult.success(m)
```

- [x] **Step 4: Run the whole suite**

Run: `./tools/run_tests.sh`
Expected: PASS.

- [x] **Step 5: Check the architecture guard still passes**

Run: `./tools/godot.sh --headless --path . -s tools/guard.gd`
Expected: exit 0. `WorldMeta` extends `RefCounted` and touches no node.

- [x] **Step 6: Commit**

```bash
git add src/core/save/world_meta.gd tests/test_world_meta.gd
git commit -m "feat: WorldMeta, the root meta.json a save is recognised by"
```

- [x] **Step 7: Tick the plan**

```bash
python3 tools/mark_task_done.py 8 --plan docs/superpowers/plans/2026-09-12-rp1-phase5-game-loop.md
git add docs/superpowers/plans/2026-09-12-rp1-phase5-game-loop.md
git commit -m "docs: tick Phase 5 task 8"
```

---

## Task 9: GameSession opens a world

The first half of the session: existence checks and the two ways in. The
autosave clock is Task 10.

The first save of a world must pass `all_chunks = true` (spec §2.1) — nothing
in Stage 1 dirties a tile, so a dirty-only first save writes an empty
`chunks/` directory and Continue paints a black screen. `needs_full_save`
carries that decision from `open_new` to the first `save_now`.

**Files:**
- Create: `src/systems/session_open_result.gd`
- Create: `src/systems/game_session.gd`
- Create: `tests/test_game_session.gd`

**Interfaces:**
- Consumes: `WorldMeta` (Task 8), `SaveManager.load_zone(..., use_backup)` (Task 7),
  `ZoneLoader.load_zone(dir, registry) -> ZoneLoadResult` (existing)
- Produces: `SessionOpenResult` with `ok: bool`, `error: String`,
  `zone: Zone`, `player_entity_id: int`, `player_spawn: Vector2`,
  `is_new: bool`, `warnings: PackedStringArray`; and on `GameSession`:
  `save_root: String`, `zone: Zone`, `player_entity_id: int`,
  `playtime: float`, `needs_full_save: bool`, `has_save() -> bool`,
  `has_backup() -> bool`,
  `open_new(zone_dir: String, registry: ContentRegistry) -> SessionOpenResult`,
  `open_saved(registry: ContentRegistry, use_backup: bool = false) -> SessionOpenResult`,
  `adopt_player(id: int) -> void`, `close() -> void`

- [x] **Step 1: Write the failing tests**

Create `tests/test_game_session.gd`. Copy the `_rm_rf` / `_wipe` helpers from
`tests/test_save_manager.gd` — the save root must be a throwaway directory, and
**never** `user://saves/`:

```gdscript
extends GutTest

var _root: String = "user://test_saves/session"
var _registry: ContentRegistry


func before_each() -> void:
	_registry = ContentRegistry.new()
	assert_eq(_registry.load_from_dir("res://data").size(), 0)
	_wipe()


func after_each() -> void:
	_wipe()


func _wipe() -> void:
	_rm_rf(_root)
	DirAccess.make_dir_recursive_absolute(_root)


func _rm_rf(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for sub_dir: String in DirAccess.get_directories_at(dir):
		_rm_rf(dir.path_join(sub_dir))
	for file_name: String in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(file_name))
	DirAccess.remove_absolute(dir)


func _session() -> GameSession:
	var s: GameSession = GameSession.new()
	s.save_root = _root
	return s


func test_an_empty_root_holds_no_save() -> void:
	assert_false(_session().has_save())
	assert_false(_session().has_backup())


func test_open_new_loads_the_authored_zone() -> void:
	var s: GameSession = _session()
	var r: SessionOpenResult = s.open_new("res://data/zone/home", _registry)
	assert_true(r.ok, r.error)
	assert_true(r.is_new)
	assert_not_null(r.zone)
	assert_eq(r.zone.size_tiles, Vector2i(128, 128))
	assert_ne(r.player_spawn, Vector2.ZERO)


func test_open_new_does_not_write_until_asked() -> void:
	# The player row does not exist yet -- World spawns it and calls
	# adopt_player. Saving before that would record player_entity_id 0.
	var s: GameSession = _session()
	s.open_new("res://data/zone/home", _registry)
	assert_false(s.has_save())
	assert_true(s.needs_full_save)


func test_opening_a_missing_save_fails_without_crashing() -> void:
	var r: SessionOpenResult = _session().open_saved(_registry)
	assert_false(r.ok)
	assert_string_contains(r.error, "no save")


func test_open_saved_reports_a_malformed_meta_rather_than_crashing() -> void:
	var f: FileAccess = FileAccess.open(WorldMeta.path_in(_root), FileAccess.WRITE)
	f.store_string("{ not json")
	f.close()
	var r: SessionOpenResult = _session().open_saved(_registry)
	assert_false(r.ok)
	assert_string_contains(r.error, "malformed")


func test_close_drops_the_world() -> void:
	var s: GameSession = _session()
	s.open_new("res://data/zone/home", _registry)
	s.close()
	assert_null(s.zone)
	assert_eq(s.player_entity_id, 0)
```

- [x] **Step 2: Run them and watch them fail**

Run: `./tools/run_tests.sh`
Expected: FAIL — `GameSession` is not a known identifier.

- [x] **Step 3: Write SessionOpenResult**

Create `src/systems/session_open_result.gd`:

```gdscript
class_name SessionOpenResult
extends RefCounted
## What GameSession returns from open_new and open_saved.
##
## One result type for both entry points, rather than ZoneLoadResult from
## one and DecodeResult from the other: the router would otherwise have to
## branch on shape before it could branch on outcome. A separate file
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
```

- [x] **Step 4: Write the opening half of GameSession**

Create `src/systems/game_session.gd`:

```gdscript
class_name GameSession
extends RefCounted
## Every game-loop decision, with no node in sight.
##
## Whether a save exists, what New World means, when autosave fires, how the
## backup rotates, how playtime accumulates. The router node calls into this
## and the menus call the router; nothing about the loop is decided inside a
## Node, which is what makes all of it testable headless.
##
## `save_root` is a variable rather than a constant so tests can point it at
## a throwaway directory. A test that wrote to user://saves/ would destroy
## the developer's world on every run.

const DEFAULT_SAVE_ROOT: String = "user://saves/home"

var save_root: String = DEFAULT_SAVE_ROOT

var zone: Zone = null
var player_entity_id: int = 0
var playtime: float = 0.0

## The first save of a world must write every chunk. Nothing in Stage 1
## dirties a tile -- building is out of scope and animals move entity rows,
## not tiles -- so a dirty-only first save writes no chunks at all and
## Continue loads a black screen.
var needs_full_save: bool = false


func has_save() -> bool:
	return FileAccess.file_exists(WorldMeta.path_in(save_root))


func has_backup() -> bool:
	return FileAccess.file_exists(WorldMeta.path_in(save_root) + ".bak")


## Loads the authored zone. Writes nothing: the player row does not exist
## until World spawns it and calls adopt_player, and the first save has to
## record that id.
func open_new(zone_dir: String, registry: ContentRegistry) -> SessionOpenResult:
	var loaded: ZoneLoadResult = ZoneLoader.load_zone(zone_dir, registry)
	if loaded.zone == null:
		return SessionOpenResult.failure(
			"could not load the zone from %s: %s" % [zone_dir, ", ".join(loaded.errors)])

	zone = loaded.zone
	player_entity_id = 0
	playtime = 0.0
	needs_full_save = true

	var r: SessionOpenResult = SessionOpenResult.new()
	r.ok = true
	r.zone = zone
	r.player_spawn = loaded.player_spawn
	r.is_new = true
	r.warnings = loaded.errors
	return r


func open_saved(registry: ContentRegistry, use_backup: bool = false) -> SessionOpenResult:
	var meta_path: String = WorldMeta.path_in(save_root)
	if use_backup:
		meta_path += ".bak"
	if not FileAccess.file_exists(meta_path):
		return SessionOpenResult.failure("no save at %s" % meta_path)

	var meta_result: DecodeResult = WorldMeta.from_json_string(
		FileAccess.get_file_as_string(meta_path))
	if not meta_result.ok:
		return SessionOpenResult.failure(meta_result.error)
	var meta: WorldMeta = meta_result.value

	var decoded: DecodeResult = SaveManager.load_zone(
		save_root, meta.zone_id, registry, use_backup)
	if not decoded.ok:
		return SessionOpenResult.failure(decoded.error)

	zone = decoded.value
	playtime = meta.playtime
	needs_full_save = false

	if not zone.entities.has(meta.player_entity_id):
		return SessionOpenResult.failure(
			"save names player entity %d, which is not in entities.dat"
			% meta.player_entity_id)
	player_entity_id = meta.player_entity_id

	var r: SessionOpenResult = SessionOpenResult.new()
	r.ok = true
	r.zone = zone
	r.player_entity_id = player_entity_id
	r.is_new = false
	return r


## World calls this once it has spawned the player into a new world.
func adopt_player(id: int) -> void:
	player_entity_id = id


func close() -> void:
	zone = null
	player_entity_id = 0
	playtime = 0.0
	needs_full_save = false
```

- [x] **Step 5: Run the whole suite and the guard**

Run: `./tools/run_tests.sh && ./tools/godot.sh --headless --path . -s tools/guard.gd`
Expected: PASS, and the guard exits 0 — `GameSession` extends `RefCounted` and
names no node.

- [x] **Step 6: Commit**

```bash
git add src/systems/session_open_result.gd src/systems/game_session.gd tests/test_game_session.gd
git commit -m "feat: GameSession opens a world, new or saved"
```

- [x] **Step 7: Tick the plan**

```bash
python3 tools/mark_task_done.py 9 --plan docs/superpowers/plans/2026-09-12-rp1-phase5-game-loop.md
git add docs/superpowers/plans/2026-09-12-rp1-phase5-game-loop.md
git commit -m "docs: tick Phase 5 task 9"
```

---

## Task 10: GameSession saves, on a clock

The autosave clock is driven by accumulated `delta` rather than by
`Time.get_ticks_msec`, which makes every rule here exactly reproducible in a
test and means a paused game's clock genuinely stops.

**Files:**
- Modify: `src/systems/game_session.gd`
- Test: `tests/test_game_session.gd`

**Interfaces:**
- Produces: `GameSession.AUTOSAVE_INTERVAL: float = 300.0`,
  `GameSession.MIN_SAVE_GAP: float = 5.0`,
  `tick(delta: float, registry: ContentRegistry) -> bool`,
  `save_now(registry: ContentRegistry, reason: String) -> PackedStringArray`,
  `save_if_gap_elapsed(registry: ContentRegistry, reason: String) -> PackedStringArray`

- [x] **Step 1: Write the failing tests**

```gdscript
func _opened() -> GameSession:
	var s: GameSession = _session()
	var r: SessionOpenResult = s.open_new("res://data/zone/home", _registry)
	assert_true(r.ok, r.error)
	var id: int = r.zone.entities.spawn(
		_registry.numeric_of("player"), r.player_spawn)
	s.adopt_player(id)
	return s


func test_the_first_save_writes_every_chunk() -> void:
	# The §2.1 regression guard. Nothing in Stage 1 dirties a tile, so a
	# dirty-only first save writes an empty chunks/ directory and Continue
	# paints a black screen.
	var s: GameSession = _opened()
	assert_eq(s.save_now(_registry, "new_world").size(), 0)

	var chunks: PackedStringArray = DirAccess.get_files_at(
		_root.path_join("zones/home/chunks"))
	assert_eq(chunks.size(), 16, "a 128x128 zone is 4x4 chunks")
	assert_true(s.has_save())
	assert_false(s.needs_full_save)


func test_saving_records_the_player_entity_id() -> void:
	var s: GameSession = _opened()
	s.save_now(_registry, "new_world")
	var result: DecodeResult = WorldMeta.from_json_string(
		FileAccess.get_file_as_string(WorldMeta.path_in(_root)))
	assert_true(result.ok, result.error)
	assert_eq((result.value as WorldMeta).player_entity_id, s.player_entity_id)


func test_a_new_world_round_trips_through_a_second_session() -> void:
	var first: GameSession = _opened()
	var pid: int = first.player_entity_id
	first.zone.entities.set_position(pid, Vector2(33.5, 44.5))
	first.zone.entities.set_facing(pid, 3)
	first.save_now(_registry, "quit")

	var second: GameSession = _session()
	var r: SessionOpenResult = second.open_saved(_registry)
	assert_true(r.ok, r.error)
	assert_eq(r.player_entity_id, pid)
	assert_eq(r.zone.entities.get_position(pid), Vector2(33.5, 44.5))
	assert_eq(r.zone.entities.get_facing(pid), 3)


func test_autosave_fires_once_at_the_interval() -> void:
	var s: GameSession = _opened()
	s.save_now(_registry, "new_world")

	var step: float = 1.0
	var elapsed: float = 0.0
	var saves: int = 0
	while elapsed < GameSession.AUTOSAVE_INTERVAL - step:
		if s.tick(step, _registry):
			saves += 1
		elapsed += step
	assert_eq(saves, 0, "autosave fired before the interval elapsed")

	assert_true(s.tick(step * 2.0, _registry), "autosave did not fire at the interval")
	assert_false(s.tick(step, _registry), "autosave fired twice")


func test_ticking_accumulates_playtime() -> void:
	var s: GameSession = _opened()
	s.tick(1.5, _registry)
	s.tick(2.5, _registry)
	assert_almost_eq(s.playtime, 4.0, 0.001)


func test_playtime_survives_a_close_and_reopen() -> void:
	var s: GameSession = _opened()
	s.tick(120.0, _registry)
	s.save_now(_registry, "quit")
	s.close()

	var again: GameSession = _session()
	assert_true(again.open_saved(_registry).ok)
	assert_almost_eq(again.playtime, 120.0, 0.001)


func test_a_second_save_inside_the_gap_is_skipped() -> void:
	# Alt-tabbing repeatedly must not mean saving repeatedly.
	var s: GameSession = _opened()
	s.save_now(_registry, "new_world")
	assert_eq(s.save_if_gap_elapsed(_registry, "focus_lost").size(), 0)
	assert_false(FileAccess.file_exists(
		_root.path_join("zones/home/entities.dat.bak")),
		"a skipped save still rotated the backup")

	s.tick(GameSession.MIN_SAVE_GAP + 1.0, _registry)
	s.save_if_gap_elapsed(_registry, "focus_lost")
	assert_true(FileAccess.file_exists(
		_root.path_join("zones/home/entities.dat.bak")))


func test_saving_with_no_world_open_is_an_error_not_a_crash() -> void:
	var s: GameSession = _session()
	assert_gt(s.save_now(_registry, "autosave").size(), 0)


func test_ticking_with_no_world_open_does_nothing() -> void:
	var s: GameSession = _session()
	assert_false(s.tick(600.0, _registry))
	assert_eq(s.playtime, 0.0)


func test_a_corrupt_live_save_can_be_recovered_from_the_backup() -> void:
	var s: GameSession = _opened()
	var pid: int = s.player_entity_id
	s.zone.entities.set_position(pid, Vector2(10.5, 10.5))
	s.save_now(_registry, "new_world")
	s.tick(GameSession.MIN_SAVE_GAP + 1.0, _registry)
	s.zone.entities.set_position(pid, Vector2(60.5, 60.5))
	s.save_now(_registry, "autosave")

	# Truncate the live entities file the way a power cut would.
	var f: FileAccess = FileAccess.open(
		_root.path_join("zones/home/entities.dat"), FileAccess.WRITE)
	f.store_buffer(PackedByteArray([0x52, 0x50]))
	f.close()

	var broken: SessionOpenResult = _session().open_saved(_registry, false)
	assert_false(broken.ok)

	var recovered: SessionOpenResult = _session().open_saved(_registry, true)
	assert_true(recovered.ok, recovered.error)
	assert_eq(recovered.zone.entities.get_position(pid), Vector2(10.5, 10.5))
```

- [x] **Step 2: Run them and watch them fail**

Run: `./tools/run_tests.sh`
Expected: FAIL — `tick`, `save_now` and `save_if_gap_elapsed` do not exist.

- [x] **Step 3: Implement the clock and the save**

Add to `src/systems/game_session.gd`:

```gdscript
## Five minutes of unpaused play. Spec §7.
const AUTOSAVE_INTERVAL: float = 300.0

## Alt-tabbing repeatedly must not mean saving repeatedly.
const MIN_SAVE_GAP: float = 5.0

var _since_autosave: float = 0.0
var _since_any_save: float = 0.0
```

`close()` resets both to `0.0`; `open_new` and `open_saved` do the same.

```gdscript
## Advances playtime and the autosave clock. Returns true if it saved.
##
## Driven by accumulated delta rather than by the wall clock, so a paused
## game's clock genuinely stops and every rule here is reproducible in a
## test without waiting five minutes.
func tick(delta: float, registry: ContentRegistry) -> bool:
	if zone == null:
		return false
	playtime += delta
	_since_autosave += delta
	_since_any_save += delta
	if _since_autosave < AUTOSAVE_INTERVAL:
		return false
	save_now(registry, "autosave")
	return true


## Saves unless one ran within MIN_SAVE_GAP. Returns the errors save_now
## would have returned, or an empty array when it declined to save.
func save_if_gap_elapsed(registry: ContentRegistry, reason: String) -> PackedStringArray:
	if _since_any_save < MIN_SAVE_GAP:
		return PackedStringArray()
	return save_now(registry, reason)


func save_now(registry: ContentRegistry, reason: String) -> PackedStringArray:
	if zone == null:
		return PackedStringArray(["cannot save: no world is open"])

	var started: int = Time.get_ticks_msec()
	var errors: PackedStringArray = SaveManager.save_zone(
		save_root, zone, registry, needs_full_save, true)

	var meta: WorldMeta = WorldMeta.new()
	meta.zone_id = zone.id
	meta.player_entity_id = player_entity_id
	meta.last_played_unix = int(Time.get_unix_time_from_system())
	meta.created_unix = meta.last_played_unix
	meta.playtime = playtime

	# Preserve the original creation time across saves.
	var existing_path: String = WorldMeta.path_in(save_root)
	if FileAccess.file_exists(existing_path):
		var prior: DecodeResult = WorldMeta.from_json_string(
			FileAccess.get_file_as_string(existing_path))
		if prior.ok and (prior.value as WorldMeta).created_unix > 0:
			meta.created_unix = (prior.value as WorldMeta).created_unix

	var meta_err: String = SaveManager.atomic_write(
		existing_path, meta.to_json_string().to_utf8_buffer(), true)
	if meta_err != "":
		errors.append(meta_err)

	if errors.is_empty():
		needs_full_save = false
		_since_autosave = 0.0
		_since_any_save = 0.0
		print("RP1 saved (%s) in %d ms" % [reason, Time.get_ticks_msec() - started])
	return errors
```

`Time` is an engine singleton, not a node, so `guard.gd` permits it — but
confirm the guard's rule list in Step 5 rather than assuming.

- [x] **Step 4: Run the whole suite**

Run: `./tools/run_tests.sh`
Expected: PASS, all of it.

- [x] **Step 5: Run the architecture guard**

Run: `./tools/godot.sh --headless --path . -s tools/guard.gd`
Expected: exit 0. If the guard rejects `Time.`, that is a real finding, not a
nuisance: report it rather than weakening the guard, and replace the timing
print with the caller passing elapsed time in.

- [x] **Step 6: Commit**

```bash
git add src/systems/game_session.gd tests/test_game_session.gd
git commit -m "feat: GameSession autosaves on a delta-driven clock"
```

- [x] **Step 7: Tick the plan**

```bash
python3 tools/mark_task_done.py 10 --plan docs/superpowers/plans/2026-09-12-rp1-phase5-game-loop.md
git add docs/superpowers/plans/2026-09-12-rp1-phase5-game-loop.md
git commit -m "docs: tick Phase 5 task 10"
```

---

## Task 11: The player can be adopted, not only spawned

`Player.spawn()` always creates a new entity row. A loaded world already has
one, and spawning a second would leave two player rows in the store — the
exact state `WorldMeta.player_entity_id` exists to make detectable.

**Files:**
- Modify: `src/presentation/player.gd`
- Test: `tests/test_player_spawn.gd`

**Interfaces:**
- Produces: `Player.adopt(p_zone: Zone, collision: CollisionBuilder, id: int) -> void`

- [x] **Step 1: Write the failing test**

Add to `tests/test_player_spawn.gd`:

```gdscript
func test_adopt_takes_over_an_existing_row_without_creating_one() -> void:
	var zone: Zone = _walkable_zone()
	var registry: ContentRegistry = _registry()
	var existing: int = zone.entities.spawn(
		registry.numeric_of("player"), Vector2(12.5, 34.5))
	var before: int = zone.entities.count()

	var player: Player = Player.new()
	player.adopt(zone, CollisionBuilder.new(), existing)

	assert_eq(zone.entities.count(), before, "adopt spawned a second player row")
	assert_eq(player.entity_id, existing)
	assert_eq(zone.entities.get_position(player.entity_id), Vector2(12.5, 34.5))
	player.free()
```

Reuse whatever zone and registry helpers this file already has; do not add
parallel ones.

- [x] **Step 2: Run it and watch it fail**

Run: `./tools/run_tests.sh`
Expected: FAIL — `adopt` is not a known method.

- [x] **Step 3: Implement it**

In `src/presentation/player.gd`, beside `spawn()`:

```gdscript
## Takes over the player row a save restored. The counterpart to spawn():
## a loaded world already has a player, and spawning a second one would
## leave two player rows in the store.
func adopt(p_zone: Zone, collision: CollisionBuilder, id: int) -> void:
	zone = p_zone
	_collision = collision
	entity_id = id
```

- [x] **Step 4: Run the whole suite**

Run: `./tools/run_tests.sh`
Expected: PASS.

- [x] **Step 5: Commit**

```bash
git add src/presentation/player.gd tests/test_player_spawn.gd
git commit -m "feat: Player.adopt takes over a restored entity row"
```

- [x] **Step 6: Tick the plan**

```bash
python3 tools/mark_task_done.py 11 --plan docs/superpowers/plans/2026-09-12-rp1-phase5-game-loop.md
git add docs/superpowers/plans/2026-09-12-rp1-phase5-game-loop.md
git commit -m "docs: tick Phase 5 task 11"
```

---

## Task 12: Extract World from main.gd

Almost entirely a move. `main.gd` currently loads content, builds the zone and
assembles renderer, player, camera and animals in one `_ready`. Everything
except the content registry becomes `World`, which is handed a `Zone` instead
of loading one.

The game must still boot and play identically at the end of this task. The
router's menus arrive in Tasks 13–16; until then `main.gd` opens a new world
immediately, exactly as it does today.

**Files:**
- Create: `src/presentation/world.gd`
- Modify: `src/presentation/main.gd`
- Test: verified by `tools/smoke.gd` and a screenshot, not by a unit test —
  `World` is an assembly of nodes with no logic of its own.

**Interfaces:**
- Consumes: `SessionOpenResult` (Task 9), `Player.adopt` (Task 11),
  `GameSession.adopt_player` (Task 9)
- Produces: `World.build(registry: ContentRegistry, result: SessionOpenResult) -> PackedStringArray`,
  `World.tick_animals(delta: float) -> void`, `World.zone: Zone`,
  `World.player_entity_id: int`

- [x] **Step 1: Create World with the code that already exists**

Create `src/presentation/world.gd` declaring `class_name World` and
`extends Node2D` — the router refers to it by name. Move the body of
`main.gd:_ready()` into `build()`, from `y_sort_enabled = true` onward,
**omitting** the `ContentRegistry` construction — the router owns that now and
passes it in. Move `_physics_process` into `tick_animals(delta)`, called by the
router, so pausing is decided in one place.

The two behavioural changes, both from `result`:

```gdscript
	# The zone comes from the session -- authored for a new world, decoded
	# from the save for a continued one. World does not know or care which.
	var zone: Zone = result.zone
```

and the player:

```gdscript
	_player = Player.new()
	_player.name = "Player"
	add_child(_player)
	if result.is_new:
		var near: Vector2i = Vector2i(
			floori(result.player_spawn.x), floori(result.player_spawn.y))
		player_entity_id = _player.spawn(zone, registry, _collision, near)
	else:
		# The save already holds a player row. Spawning here would leave
		# two of them.
		_player.adopt(zone, _collision, result.player_entity_id)
		player_entity_id = _player.entity_id
```

`build` returns the accumulated art and render errors as a
`PackedStringArray` instead of calling `push_error` inline, so the router can
show them. Keep the `print` lines: the export gate asserts on the rendered
cell count.

- [x] **Step 2: Reduce main.gd to a boot shim**

For this task only, `main.gd` keeps booting straight into a world:

```gdscript
extends Node2D
## Entry point. Task 16 turns this into the menu router; for now it opens a
## new world at boot, exactly as it did before World was extracted.

@export var zone_dir: String = "res://data/zone/home"

var _registry: ContentRegistry = null
var _session: GameSession = null
var _world: World = null


func _ready() -> void:
	_registry = ContentRegistry.new()
	var errs: PackedStringArray = _registry.load_from_dir("res://data")
	for e: String in errs:
		push_error("content failed to load: %s" % e)
	print("RP1 booted with %d content definitions" % _registry.all_string_ids().size())

	_session = GameSession.new()
	var result: SessionOpenResult = _session.open_new(zone_dir, _registry)
	if not result.ok:
		push_error(result.error)
		return

	_world = World.new()
	_world.name = "World"
	add_child(_world)
	for e: String in _world.build(_registry, result):
		push_error(e)
	_session.adopt_player(_world.player_entity_id)


func _physics_process(delta: float) -> void:
	if _world != null:
		_world.tick_animals(delta)
```

- [x] **Step 3: Run the tests, the guard and the smoke test**

Run:
```bash
./tools/run_tests.sh
./tools/godot.sh --headless --path . -s tools/guard.gd
./tools/godot.sh --headless --path . -s tools/smoke.gd
```
Expected: all three pass. The smoke test still exercises the data layer
directly and is unaffected; Task 17 extends it.

- [x] **Step 4: Look at it**

Run: `./tools/godot.sh --headless --path . -s tools/screenshot.gd`
Expected: a PNG showing the zone and the player, indistinguishable from before
the extraction. Open it and confirm.

- [x] **Step 5: Commit**

```bash
git add src/presentation/world.gd src/presentation/main.gd
git commit -m "refactor: extract World from main.gd, built from a session result"
```

- [x] **Step 6: Tick the plan**

```bash
python3 tools/mark_task_done.py 12 --plan docs/superpowers/plans/2026-09-12-rp1-phase5-game-loop.md
git add docs/superpowers/plans/2026-09-12-rp1-phase5-game-loop.md
git commit -m "docs: tick Phase 5 task 12"
```

---

## Task 13: A theme built from the palette

`tools/check_palette.sh` scans `assets/**.png` and cannot see a `Color`
literal in GDScript, so a code-built theme would sit outside the palette rule
entirely. A test provides the same guarantee without an eighth CI gate.

This task adds no files under `assets/`, so no `LICENSE.txt` and no
`CREDITS.md` entry: the phase imports no third-party art.

**Files:**
- Create: `src/ui/ui_theme.gd`
- Create: `tests/test_ui_theme.gd`

**Interfaces:**
- Produces: `UiTheme.colours() -> Dictionary` (name → `Color`),
  `UiTheme.build() -> Theme`, and the constants `BACKGROUND`, `PANEL`,
  `BORDER`, `TEXT`, `TEXT_DIM`, `TEXT_DISABLED`, `ACCENT`, `DANGER`

- [x] **Step 1: Write the failing test**

Create `tests/test_ui_theme.gd`:

```gdscript
extends GutTest


func _apollo_hexes() -> Dictionary:
	var json: JSON = JSON.new()
	assert_eq(json.parse(FileAccess.get_file_as_string(
		"res://tools/palette/apollo.json")), OK)
	var out: Dictionary = {}
	for ramp: String in (json.data as Dictionary)["ramps"]:
		for hex: String in (json.data as Dictionary)["ramps"][ramp]:
			out[hex.to_lower()] = true
	return out


func test_the_palette_file_holds_forty_six_colours() -> void:
	# If this ever fails, the palette changed and every colour below needs
	# rechecking rather than the assertion relaxing.
	assert_eq(_apollo_hexes().size(), 46)


func test_every_theme_colour_is_on_the_palette() -> void:
	# check_palette.sh scans assets/**.png and cannot see a Color literal
	# in GDScript. This is the palette rule's enforcement for UI code.
	var allowed: Dictionary = _apollo_hexes()
	for name: String in UiTheme.colours():
		var c: Color = UiTheme.colours()[name]
		assert_true(allowed.has(c.to_html(false).to_lower()),
			"%s is #%s, which is not an Apollo colour" % [name, c.to_html(false)])


func test_build_returns_a_theme_with_the_controls_the_menus_use() -> void:
	var theme: Theme = UiTheme.build()
	assert_not_null(theme)
	assert_true(theme.has_stylebox("normal", "Button"))
	assert_true(theme.has_stylebox("hover", "Button"))
	assert_true(theme.has_stylebox("disabled", "Button"))
	assert_true(theme.has_stylebox("panel", "PanelContainer"))
	assert_true(theme.has_color("font_color", "Button"))
	assert_true(theme.has_color("font_disabled_color", "Button"))
```

- [x] **Step 2: Run it and watch it fail**

Run: `./tools/run_tests.sh`
Expected: FAIL — `UiTheme` is not a known identifier.

- [x] **Step 3: Write the theme**

Create `src/ui/ui_theme.gd`. Every colour is an Apollo hex, named by the ramp
it comes from so the next person can check it against `docs/palette.md`:

```gdscript
class_name UiTheme
extends RefCounted
## The one place in the project a UI Color is written.
##
## check_palette.sh scans assets/**.png and cannot see a Color literal, so
## tests/test_ui_theme.gd asserts every constant here is one of Apollo's 46.
## Adding a colour anywhere else in src/ui/ escapes both.
##
## Phase 6 replaces the insides of build() -- a real pixel font, 9-slice
## panels -- without any menu script changing.

const BACKGROUND: Color = Color("10141f")      # neutral 2
const PANEL: Color = Color("202e37")           # neutral 4
const BORDER: Color = Color("577277")          # neutral 6
const TEXT: Color = Color("c7cfcc")            # neutral 9
const TEXT_DIM: Color = Color("819796")        # neutral 7
const TEXT_DISABLED: Color = Color("394a50")   # neutral 5
const ACCENT: Color = Color("de9e41")          # gold 5
const DANGER: Color = Color("a53030")          # red 4

const FONT_SIZE: int = 16
const TITLE_FONT_SIZE: int = 32


static func colours() -> Dictionary:
	return {
		"BACKGROUND": BACKGROUND, "PANEL": PANEL, "BORDER": BORDER,
		"TEXT": TEXT, "TEXT_DIM": TEXT_DIM, "TEXT_DISABLED": TEXT_DISABLED,
		"ACCENT": ACCENT, "DANGER": DANGER,
	}


static func _box(fill: Color, border: Color) -> StyleBoxFlat:
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(2)
	box.set_content_margin_all(12)
	return box


static func build() -> Theme:
	var theme: Theme = Theme.new()
	theme.default_font_size = FONT_SIZE

	theme.set_stylebox("normal", "Button", _box(PANEL, BORDER))
	theme.set_stylebox("hover", "Button", _box(PANEL, ACCENT))
	theme.set_stylebox("pressed", "Button", _box(BORDER, ACCENT))
	theme.set_stylebox("focus", "Button", _box(PANEL, ACCENT))
	theme.set_stylebox("disabled", "Button", _box(BACKGROUND, TEXT_DISABLED))
	theme.set_color("font_color", "Button", TEXT)
	theme.set_color("font_hover_color", "Button", ACCENT)
	theme.set_color("font_disabled_color", "Button", TEXT_DISABLED)

	theme.set_stylebox("panel", "PanelContainer", _box(PANEL, BORDER))
	theme.set_color("font_color", "Label", TEXT)
	return theme
```

The built-in fallback font is used as-is. It is not a pixel font and will look
like a placeholder, which it is — Phase 6 owns the UI frame. Do not spend time
here trying to make it look right.

- [x] **Step 4: Run the whole suite**

Run: `./tools/run_tests.sh`
Expected: PASS. If `test_the_palette_file_holds_forty_six_colours` fails,
stop — the palette changed and that is a bigger finding than this task.

- [x] **Step 5: Commit**

```bash
git add src/ui/ui_theme.gd tests/test_ui_theme.gd
git commit -m "feat: a UI theme built from the Apollo palette, enforced by test"
```

- [x] **Step 6: Tick the plan**

```bash
python3 tools/mark_task_done.py 13 --plan docs/superpowers/plans/2026-09-12-rp1-phase5-game-loop.md
git add docs/superpowers/plans/2026-09-12-rp1-phase5-game-loop.md
git commit -m "docs: tick Phase 5 task 13"
```

---

## Task 14: The main menu and the confirm panel

Built in code rather than as `.tscn` files, matching how every other
presentation node in this project is assembled. Neither node holds logic: they
emit signals, and the router decides what those mean.

The confirm panel is deliberately **not** Godot's `ConfirmationDialog`, which
spawns a native OS window — one that behaves badly fullscreen and cannot be
captured by `tools/screenshot.gd`.

**Files:**
- Create: `src/ui/confirm_panel.gd`
- Create: `src/ui/main_menu.gd`

**Interfaces:**
- Consumes: `UiTheme.build()`, `UiTheme.BACKGROUND`, `UiTheme.TEXT_DIM`,
  `UiTheme.TITLE_FONT_SIZE` (Task 13); `WorldMeta` (Task 8)
- Produces: `ConfirmPanel` — signals `confirmed`, `dismissed`; methods
  `ask(title: String, body: String, confirm_label: String) -> void`,
  `report(title: String, body: String) -> void`.
  `MainMenu` — signals `new_world_requested`, `continue_requested`,
  `quit_requested`; method `set_save_state(has_save: bool, meta: WorldMeta) -> void`

- [x] **Step 1: Write ConfirmPanel**

Create `src/ui/confirm_panel.gd`:

```gdscript
class_name ConfirmPanel
extends Control
## An in-scene confirm/report panel.
##
## Not Godot's ConfirmationDialog, which spawns a native OS window: it
## behaves badly fullscreen and tools/screenshot.gd cannot capture it.

signal confirmed
signal dismissed

var _title: Label = null
var _body: Label = null
var _buttons: HBoxContainer = null


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false

	var dim: ColorRect = ColorRect.new()
	dim.color = Color(UiTheme.BACKGROUND, 0.85)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var centre: CenterContainer = CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(centre)

	var panel: PanelContainer = PanelContainer.new()
	centre.add_child(panel)

	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	column.custom_minimum_size = Vector2(420, 0)
	panel.add_child(column)

	_title = Label.new()
	_title.add_theme_font_size_override("font_size", UiTheme.TITLE_FONT_SIZE)
	column.add_child(_title)

	_body = Label.new()
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.custom_minimum_size = Vector2(420, 0)
	column.add_child(_body)

	_buttons = HBoxContainer.new()
	_buttons.alignment = BoxContainer.ALIGNMENT_END
	_buttons.add_theme_constant_override("separation", 12)
	column.add_child(_buttons)


func _clear_buttons() -> void:
	for child: Node in _buttons.get_children():
		_buttons.remove_child(child)
		child.queue_free()


func _add_button(text: String) -> Button:
	var b: Button = Button.new()
	b.text = text
	_buttons.add_child(b)
	return b


## Two buttons. Cancel takes focus, so a stray Enter never destroys a world.
func ask(title: String, body: String, confirm_label: String) -> void:
	_title.text = title
	_body.text = body
	_clear_buttons()
	var confirm: Button = _add_button(confirm_label)
	var cancel: Button = _add_button("Cancel")
	confirm.pressed.connect(func() -> void:
		visible = false
		confirmed.emit())
	cancel.pressed.connect(func() -> void:
		visible = false
		dismissed.emit())
	visible = true
	cancel.grab_focus()


## One button. Used to report a failure the player can only acknowledge.
func report(title: String, body: String) -> void:
	_title.text = title
	_body.text = body
	_clear_buttons()
	var ok: Button = _add_button("OK")
	ok.pressed.connect(func() -> void:
		visible = false
		dismissed.emit())
	visible = true
	ok.grab_focus()
```

- [x] **Step 2: Write MainMenu**

Create `src/ui/main_menu.gd`:

```gdscript
class_name MainMenu
extends Control
## New World / Continue / Quit.
##
## Emits three signals and knows nothing else. It has never heard of a
## GameSession: the router decides what each button means, which is what
## keeps every game-loop rule in a RefCounted that can be tested headless.

signal new_world_requested
signal continue_requested
signal quit_requested

var _continue_button: Button = null
var _summary: Label = null


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var background: ColorRect = ColorRect.new()
	background.color = UiTheme.BACKGROUND
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var centre: CenterContainer = CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(centre)

	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	column.custom_minimum_size = Vector2(320, 0)
	centre.add_child(column)

	var title: Label = Label.new()
	title.text = "RP1"
	title.add_theme_font_size_override("font_size", UiTheme.TITLE_FONT_SIZE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)

	var new_button: Button = Button.new()
	new_button.text = "New World"
	new_button.pressed.connect(func() -> void: new_world_requested.emit())
	column.add_child(new_button)

	_continue_button = Button.new()
	_continue_button.text = "Continue"
	_continue_button.pressed.connect(func() -> void: continue_requested.emit())
	column.add_child(_continue_button)

	_summary = Label.new()
	_summary.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	_summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_summary)

	var quit_button: Button = Button.new()
	quit_button.text = "Quit"
	quit_button.pressed.connect(func() -> void: quit_requested.emit())
	column.add_child(quit_button)

	new_button.grab_focus()


## Continue is disabled and dimmed when there is nothing to continue. The
## summary line is the only place meta.json is shown to the player, which
## is most of the reason the file is worth having.
func set_save_state(has_save: bool, meta: WorldMeta) -> void:
	_continue_button.disabled = not has_save
	if not has_save:
		_summary.text = "No saved world yet"
		return
	var played: int = int(meta.playtime)
	_summary.text = "%d:%02d played  ·  %s" % [
		played / 3600,
		(played % 3600) / 60,
		Time.get_datetime_string_from_unix_time(meta.last_played_unix, true),
	]
```

- [x] **Step 3: Check both files parse**

There is no unit test here — these are node assemblies with no logic, and the
logic they call is covered by `test_game_session.gd`. They are verified by eye
in Task 16.

Run: `./tools/run_tests.sh && ./tools/godot.sh --headless --path . -s tools/guard.gd`
Expected: PASS and exit 0. Nothing instantiates these files yet, but the
runner's parse check is what matters at this step: a broken script would fail
the run rather than being skipped.

- [x] **Step 4: Commit**

```bash
git add src/ui/confirm_panel.gd src/ui/main_menu.gd
git commit -m "feat: main menu and an in-scene confirm panel"
```

- [x] **Step 5: Tick the plan**

```bash
python3 tools/mark_task_done.py 14 --plan docs/superpowers/plans/2026-09-12-rp1-phase5-game-loop.md
git add docs/superpowers/plans/2026-09-12-rp1-phase5-game-loop.md
git commit -m "docs: tick Phase 5 task 14"
```

---

## Task 15: The pause menu and the pause action

Escape is read through a named `InputMap` action rather than directly, because
controller support in Stage 6 is nearly free if every input goes through
`InputMap` and is a rewrite if it does not. Binding gamepad Start costs one
line now and nothing later.

**Files:**
- Create: `src/ui/pause_menu.gd`
- Modify: `project.godot`
- Create: `tests/test_input_map.gd`

**Interfaces:**
- Produces: `PauseMenu` — signals `resume_requested`, `quit_to_menu_requested`,
  `quit_to_desktop_requested`; the `pause` input action

- [x] **Step 1: Write the failing test**

Create `tests/test_input_map.gd`:

```gdscript
extends GutTest


func test_the_pause_action_exists() -> void:
	# Read through a named action rather than Input.is_key_pressed(KEY_ESCAPE),
	# so gamepad Start works and Stage 6's rebinding has something to rebind.
	assert_true(InputMap.has_action("pause"))


func test_the_pause_action_is_bound_to_escape() -> void:
	var found: bool = false
	for event: InputEvent in InputMap.action_get_events("pause"):
		if event is InputEventKey and (event as InputEventKey).physical_keycode == KEY_ESCAPE:
			found = true
	assert_true(found, "pause is not bound to Escape")


func test_the_movement_actions_still_exist() -> void:
	# project.godot is edited by hand in the next step, and a malformed
	# [input] section can silently drop actions.
	for action: String in ["move_up", "move_down", "move_left", "move_right"]:
		assert_true(InputMap.has_action(action), action)
```

- [x] **Step 2: Run it and watch it fail**

Run: `./tools/run_tests.sh`
Expected: FAIL — `pause` is not in the input map.

- [x] **Step 3: Add the action**

Append to the `[input]` section of `project.godot`, matching the formatting of
the four `move_*` actions exactly:

```
pause={
"deadzone": 0.2,
"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":4194305,"key_label":0,"unicode":0,"location":0,"echo":false,"script":null)
, Object(InputEventJoypadButton,"resource_local_to_scene":false,"resource_name":"","device":-1,"button_index":6,"pressure":0.0,"pressed":false,"script":null)
]
}
```

`4194305` is `KEY_ESCAPE`; button index 6 is `JOY_BUTTON_START`.

- [x] **Step 4: Run the test and watch it pass**

Run: `./tools/run_tests.sh`
Expected: PASS, all three input tests included. If the movement tests now fail,
the hand-edit broke the section — restore it from git and try again.

- [x] **Step 5: Write PauseMenu**

Create `src/ui/pause_menu.gd`:

```gdscript
class_name PauseMenu
extends Control
## Resume / Quit to Menu / Quit to Desktop.
##
## Both quit buttons save before quitting -- but that is the router's job.
## This node emits and forgets, exactly like MainMenu.
##
## The background is translucent rather than opaque: the world stays visible
## behind it, which is the cheapest way to make a pause read as a pause
## rather than as having left the game.

signal resume_requested
signal quit_to_menu_requested
signal quit_to_desktop_requested

var _resume_button: Button = null


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false

	var background: ColorRect = ColorRect.new()
	background.color = Color(UiTheme.BACKGROUND, 0.7)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var centre: CenterContainer = CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(centre)

	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	column.custom_minimum_size = Vector2(320, 0)
	centre.add_child(column)

	var title: Label = Label.new()
	title.text = "Paused"
	title.add_theme_font_size_override("font_size", UiTheme.TITLE_FONT_SIZE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)

	_resume_button = Button.new()
	_resume_button.text = "Resume"
	_resume_button.pressed.connect(func() -> void: resume_requested.emit())
	column.add_child(_resume_button)

	var to_menu: Button = Button.new()
	to_menu.text = "Quit to Menu"
	to_menu.pressed.connect(func() -> void: quit_to_menu_requested.emit())
	column.add_child(to_menu)

	var to_desktop: Button = Button.new()
	to_desktop.text = "Quit to Desktop"
	to_desktop.pressed.connect(func() -> void: quit_to_desktop_requested.emit())
	column.add_child(to_desktop)


## Called by the router when it opens the menu, so keyboard and gamepad
## navigation starts somewhere harmless.
func focus_first() -> void:
	_resume_button.grab_focus()
```

- [x] **Step 6: Run the suite and the guard**

Run: `./tools/run_tests.sh && ./tools/godot.sh --headless --path . -s tools/guard.gd`
Expected: PASS and exit 0.

- [x] **Step 7: Commit**

```bash
git add src/ui/pause_menu.gd project.godot tests/test_input_map.gd
git commit -m "feat: pause menu, behind a named pause action"
```

- [x] **Step 8: Tick the plan**

```bash
python3 tools/mark_task_done.py 15 --plan docs/superpowers/plans/2026-09-12-rp1-phase5-game-loop.md
git add docs/superpowers/plans/2026-09-12-rp1-phase5-game-loop.md
git commit -m "docs: tick Phase 5 task 15"
```

---

## Task 16: The router

Where it all meets. `main.gd` stops booting into a world and starts in the
menu, and the notifications that make save-on-quit and save-on-focus-loss work
get wired.

**Files:**
- Modify: `src/presentation/main.gd`
- Modify: `scenes/main.tscn` — only if the script's node type changed; it
  should not have.

**Interfaces:**
- Consumes: everything from Tasks 9–15

- [ ] **Step 1: Write the router**

Replace `src/presentation/main.gd` entirely:

```gdscript
extends Node2D
## Boots into the menu and owns everything that outlives a world.
##
## The ContentRegistry and the Theme are built once here and survive
## returning to the menu, which is why this phase does not use
## change_scene_to_file: a scene swap would re-parse every JSON under data/
## and rebuild the tileset atlas on every transition.
##
## All policy lives in GameSession. This node translates between it and the
## scene tree, and does nothing else.

@export var zone_dir: String = "res://data/zone/home"

var _registry: ContentRegistry = null
var _session: GameSession = null
var _world: World = null
var _ui: CanvasLayer = null
var _main_menu: MainMenu = null
var _pause_menu: PauseMenu = null
var _confirm: ConfirmPanel = null

## Set when a save fails on the way out, so a second attempt quits anyway.
var _quit_was_refused: bool = false


func _ready() -> void:
	# Without this the window closes before the save runs.
	get_tree().auto_accept_quit = false
	y_sort_enabled = true

	_registry = ContentRegistry.new()
	for e: String in _registry.load_from_dir("res://data"):
		push_error("content failed to load: %s" % e)
	print("RP1 booted with %d content definitions" % _registry.all_string_ids().size())

	_session = GameSession.new()

	_ui = CanvasLayer.new()
	_ui.name = "UI"
	# The pause menu has to keep processing while the tree is paused.
	_ui.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	add_child(_ui)

	var theme: Theme = UiTheme.build()

	_main_menu = MainMenu.new()
	_main_menu.theme = theme
	_main_menu.new_world_requested.connect(_on_new_world_requested)
	_main_menu.continue_requested.connect(_on_continue_requested)
	_main_menu.quit_requested.connect(_save_and_quit)
	_ui.add_child(_main_menu)

	_pause_menu = PauseMenu.new()
	_pause_menu.theme = theme
	_pause_menu.resume_requested.connect(_set_paused.bind(false))
	_pause_menu.quit_to_menu_requested.connect(_on_quit_to_menu)
	_pause_menu.quit_to_desktop_requested.connect(_save_and_quit)
	_ui.add_child(_pause_menu)

	_confirm = ConfirmPanel.new()
	_confirm.theme = theme
	_ui.add_child(_confirm)

	_show_main_menu()


# --- menu -------------------------------------------------------------

func _read_meta() -> WorldMeta:
	var path: String = WorldMeta.path_in(_session.save_root)
	if not FileAccess.file_exists(path):
		return WorldMeta.new()
	var result: DecodeResult = WorldMeta.from_json_string(
		FileAccess.get_file_as_string(path))
	return result.value if result.ok else WorldMeta.new()


func _show_main_menu() -> void:
	_main_menu.visible = true
	_pause_menu.visible = false
	_main_menu.set_save_state(_session.has_save(), _read_meta())


func _on_new_world_requested() -> void:
	if not _session.has_save():
		_start_new_world()
		return
	# Overwriting a world is the one destructive thing this menu can do.
	_confirm.ask(
		"Overwrite your world?",
		"Starting a new world replaces the saved one. This cannot be undone.",
		"Overwrite")
	_confirm.confirmed.connect(_start_new_world, CONNECT_ONE_SHOT)
	_confirm.dismissed.connect(
		func() -> void: _confirm.confirmed.disconnect(_start_new_world),
		CONNECT_ONE_SHOT)


func _start_new_world() -> void:
	var result: SessionOpenResult = _session.open_new(zone_dir, _registry)
	if not result.ok:
		_confirm.report("Could not start a new world", result.error)
		return
	_enter_world(result)
	var errors: PackedStringArray = _session.save_now(_registry, "new_world")
	for e: String in errors:
		push_error("first save failed: %s" % e)
	if not errors.is_empty():
		_confirm.report("Could not save the new world", "\n".join(errors))


func _on_continue_requested() -> void:
	var result: SessionOpenResult = _session.open_saved(_registry, false)
	if result.ok:
		_enter_world(result)
		return

	push_error("continue failed: %s" % result.error)
	if not _session.has_backup():
		_confirm.report("Could not load your world", result.error)
		return
	_confirm.ask(
		"Could not load your world",
		"%s\n\nThere is an earlier backup. Load it instead?" % result.error,
		"Load backup")
	_confirm.confirmed.connect(_continue_from_backup, CONNECT_ONE_SHOT)
	_confirm.dismissed.connect(
		func() -> void: _confirm.confirmed.disconnect(_continue_from_backup),
		CONNECT_ONE_SHOT)


func _continue_from_backup() -> void:
	var result: SessionOpenResult = _session.open_saved(_registry, true)
	if not result.ok:
		_confirm.report("The backup could not be loaded either", result.error)
		return
	_enter_world(result)


# --- world ------------------------------------------------------------

func _enter_world(result: SessionOpenResult) -> void:
	for w: String in result.warnings:
		push_error("zone: %s" % w)

	_world = World.new()
	_world.name = "World"
	add_child(_world)
	for e: String in _world.build(_registry, result):
		push_error(e)

	_session.adopt_player(_world.player_entity_id)
	_main_menu.visible = false
	_set_paused(false)


func _on_quit_to_menu() -> void:
	var errors: PackedStringArray = _session.save_now(_registry, "quit_to_menu")
	if not errors.is_empty():
		for e: String in errors:
			push_error("save failed: %s" % e)
		_confirm.report("Could not save", "\n".join(errors))
		return

	_set_paused(false)
	_world.queue_free()
	_world = null
	_session.close()
	_show_main_menu()


func _set_paused(paused: bool) -> void:
	get_tree().paused = paused
	_pause_menu.visible = paused
	if paused:
		_pause_menu.focus_first()


# --- loop -------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if _world == null:
		return
	_world.tick_animals(delta)
	_session.tick(delta, _registry)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("pause"):
		return
	if _world == null or _confirm.visible:
		return
	get_viewport().set_input_as_handled()
	_set_paused(not get_tree().paused)


# --- quitting ---------------------------------------------------------

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_save_and_quit()
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT and _world != null:
		for e: String in _session.save_if_gap_elapsed(_registry, "focus_lost"):
			push_error("focus-loss save failed: %s" % e)


func _save_and_quit() -> void:
	if _world == null:
		get_tree().quit()
		return

	var errors: PackedStringArray = _session.save_now(_registry, "quit")
	if errors.is_empty() or _quit_was_refused:
		get_tree().quit()
		return

	# One chance to act -- free some disk, close whatever holds the file --
	# and then get out of the player's way. Holding the process hostage
	# over a full disk is worse than losing the session.
	_quit_was_refused = true
	for e: String in errors:
		push_error("save failed on quit: %s" % e)
	_confirm.report(
		"Could not save",
		"%s\n\nQuit again to exit without saving." % "\n".join(errors))
```

- [ ] **Step 2: Run every gate**

```bash
./tools/run_tests.sh
./tools/godot.sh --headless --path . -s tools/guard.gd
./tools/godot.sh --headless --path . -s tools/smoke.gd
```
Expected: all pass.

- [ ] **Step 3: Play every path**

Run the game windowed — not headless — and walk through all of it. On a
machine that has run the game before, delete the save first so Continue starts
disabled: `rm -rf ~/Library/Application\ Support/Godot/app_userdata/RP1/saves`

- [ ] Continue is greyed out, with "No saved world yet" beneath it
- [ ] New World starts a world; the player spawns on grass and moves
- [ ] Escape opens the pause menu; the rabbits freeze
- [ ] Escape again resumes; the rabbits move
- [ ] Quit to Menu returns to a menu where Continue is enabled and shows a playtime
- [ ] Continue puts the player back where they were left, facing the same way
- [ ] New World now asks before overwriting, and Cancel leaves the world intact
- [ ] Close the window with the X, relaunch, Continue: same position again

- [ ] **Step 4: Commit**

```bash
git add src/presentation/main.gd
git commit -m "feat: boot into the menu, save on quit and on focus loss"
```

- [ ] **Step 5: Tick the plan**

```bash
python3 tools/mark_task_done.py 16 --plan docs/superpowers/plans/2026-09-12-rp1-phase5-game-loop.md
git add docs/superpowers/plans/2026-09-12-rp1-phase5-game-loop.md
git commit -m "docs: tick Phase 5 task 16"
```

---

## Task 17: The smoke test opens and reopens a world

`tools/smoke.gd` already round-trips the data layer. This adds the layer above
it, so CI catches a session that exports cleanly and cannot reopen its own
save.

Two of the spec's acceptance criteria are already covered by tests written in
Phase 2 — `test_chunk_payloads_round_trip_byte_identical` and
`test_save_completes_within_the_budget` in `tests/test_save_manager.gd`.
**Confirm both still pass; do not write duplicates.**

**Files:**
- Modify: `tools/smoke.gd`

- [ ] **Step 1: Add the session round trip**

Append a section to `_init`, before the failure report, using a throwaway root
and the real authored zone:

```gdscript
	# --- session ---------------------------------------------------------
	var session_root: String = "user://smoke_session"
	var s: GameSession = GameSession.new()
	s.save_root = session_root

	var opened: SessionOpenResult = s.open_new("res://data/zone/home", registry)
	_check(opened.ok, "opening a new world failed: %s" % opened.error)
	if opened.ok:
		var pid: int = opened.zone.entities.spawn(
			registry.numeric_of("player"), opened.player_spawn)
		s.adopt_player(pid)
		opened.zone.entities.set_position(pid, Vector2(33.5, 44.5))
		opened.zone.entities.set_facing(pid, 3)

		var save_errors: PackedStringArray = s.save_now(registry, "smoke")
		_check(save_errors.is_empty(), "session save failed: %s" % ", ".join(save_errors))
		_check(DirAccess.get_files_at(session_root.path_join("zones/home/chunks")).size() == 16,
			"a first save must write all 16 chunks, not only dirty ones")

		var again: GameSession = GameSession.new()
		again.save_root = session_root
		var reopened: SessionOpenResult = again.open_saved(registry)
		_check(reopened.ok, "reopening the save failed: %s" % reopened.error)
		if reopened.ok:
			_check(reopened.player_entity_id == pid, "the player id changed across a save")
			_check(reopened.zone.entities.get_position(pid) == Vector2(33.5, 44.5),
				"the player did not come back where they were left")
			_check(reopened.zone.entities.get_facing(pid) == 3,
				"the player's facing was not restored")
```

- [ ] **Step 2: Run it**

Run: `./tools/godot.sh --headless --path . -s tools/smoke.gd`
Expected: `Smoke test: OK (300 iterations)`, exit 0.

- [ ] **Step 3: Prove it can fail**

Temporarily change `s.save_now(registry, "smoke")`'s zone to skip the full
save — or simply change the expected position to `Vector2(0.5, 0.5)` — and
confirm the smoke test exits non-zero with a readable message. Revert.

- [ ] **Step 4: Confirm the two acceptance tests still pass**

Run: `./tools/run_tests.sh`
Expected: PASS, including `test_save_completes_within_the_budget`. If the
budget test now fails, the cause is the walkability recompute added in Task 6
or the meta write added in Task 10 — measure before changing the budget, and
report the number rather than relaxing the assertion.

- [ ] **Step 5: Commit**

```bash
git add tools/smoke.gd
git commit -m "ci: smoke test opens a world, saves it, and reopens it"
```

- [ ] **Step 6: Tick the plan**

```bash
python3 tools/mark_task_done.py 17 --plan docs/superpowers/plans/2026-09-12-rp1-phase5-game-loop.md
git add docs/superpowers/plans/2026-09-12-rp1-phase5-game-loop.md
git commit -m "docs: tick Phase 5 task 17"
```

---

## Task 18: Close the phase

- [ ] **Step 1: Run every gate the way CI runs them**

```bash
./tools/run_tests.sh
./tools/godot.sh --headless --path . -s tools/guard.gd
./tools/godot.sh --headless --path . -s tools/smoke.gd
./tools/check_asset_licences.sh
./tools/check_palette.sh
./tools/check_zone.sh
```
Expected: all six exit 0.

- [ ] **Step 2: Walk the acceptance criteria**

Work through §10 of the spec one line at a time, in a real running build, and
record the result of each. Anything that fails is a bug to fix in this phase,
not a note for the next one.

- [ ] **Step 3: Play it for twenty minutes**

Several sessions, quitting and continuing between them. The specific things to
watch for, because they are the ones the tests cannot see:

- rabbits still clustered around where they were authored, not drifting toward
  wherever you tend to stand
- no hitch when the five-minute autosave fires
- the pause menu appearing instantly, with the world frozen behind it

- [ ] **Step 4: Mark the spec accepted**

Change the spec's `**Status:** draft` to `**Status:** accepted`, and update
§12's corrections if anything moved during implementation.

- [ ] **Step 5: Commit**

```bash
git add docs/superpowers/specs/2026-09-12-rp1-phase5-game-loop-design.md
git commit -m "docs: accept the Phase 5 design"
```

- [ ] **Step 6: Tick the plan**

```bash
python3 tools/mark_task_done.py 18 --plan docs/superpowers/plans/2026-09-12-rp1-phase5-game-loop.md
git add docs/superpowers/plans/2026-09-12-rp1-phase5-game-loop.md
git commit -m "docs: tick Phase 5 task 18"
```

---

## Definition of done

- [ ] New World, walk, close the window with the X, relaunch, Continue: the
      player stands where they were left, facing the same way
- [ ] The rabbits are where they were left, and wander around the spots
      `data/zone/home/zone.json` authored rather than around wherever the last
      save caught them
- [ ] Continue is disabled and dimmed when no save exists
- [ ] New World over an existing save asks first
- [ ] Quit to Menu, then Continue, without relaunching the process
- [ ] A save written under a registry missing a creature added since still
      loads, with the rabbit still a rabbit
- [ ] A truncated `entities.dat` reports the error on the menu and offers the
      backup rather than crashing
- [ ] A v1 `entities.dat` fixture loads through the migration
- [ ] A full zone save completes in under 100 ms
- [ ] The first save of a world writes all 16 chunks
- [ ] No menu colour outside the Apollo palette
- [ ] All seven CI gates green
- [ ] No test writes to `user://saves/`
