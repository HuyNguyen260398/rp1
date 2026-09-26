# Phase 7 — The Mutation Spine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the shared dirty flag with a per-chunk version counter and
per-consumer watchers, so that a tile edit reaches the renderer, the collider
and the save independently — then prove it by placing one wall that survives a
relaunch.

**Architecture:** `Chunk.dirty: bool` becomes `Chunk.version: int`, bumped by
every write. A new `ChunkWatcher` holds one consumer's last-seen version per
chunk and answers "what changed for me". Nothing clears shared state, so the
renderer, the save and the collider cannot starve each other. `Zone` loses
`dirty_chunk_coords()` and `clear_dirty()` entirely — leaving them would leave
the bug reachable.

**Tech Stack:** Godot 4.7.2 stable (standard build, **not** Mono), GDScript
only, GUT for tests.

**Spec:** `docs/superpowers/specs/2026-09-22-rp1-stage2-design.md` — §3.1 (the
mutation spine), §3.2 (edits as commands), and the Phase 7 entry in §4.

## Global Constraints

- Godot **4.7.2**, standard build. Invoke only through `./tools/godot.sh`.
- GDScript only. No C#. No `TileMap` — `TileMapLayer` only.
- Static typing everywhere: `var x: int = 0`, `func f(a: Vector2i) -> void:`.
- `src/core/` and `src/systems/` **MUST NOT reference Godot nodes.** No
  `extends Node`, no `get_tree()`, no `Engine.`, no `.tscn`. `RefCounted`
  only. Enforced by `tools/guard.gd`.
- Presentation reads from world data. World data never reads from presentation.
- Run tests with `./tools/run_tests.sh` — never `gut_cmdln.gd` directly. The
  runner does a mandatory `--import` pass first; without it GUT reports missing
  `class_name`s **and exits 0**, so a broken suite looks green.
- TDD: write the failing test, watch it fail, implement minimally, watch it pass.
- Every file in `core/` and `systems/` has a matching test in `tests/`.
- Conventional commit prefixes: `feat:`, `test:`, `ci:`, `docs:`, `fix:`.
- Each task produces two commits: the code, then a `docs:` commit ticking that
  task's checkboxes with `python3 tools/mark_task_done.py <n> --plan <this file>`.

---

## File Structure

| File | Responsibility |
|---|---|
| `src/core/chunk.gd` | **Modify.** `dirty: bool` → `version: int`; five setters bump it. |
| `src/core/chunk_watcher.gd` | **Create.** One consumer's last-seen version per chunk. The only place the comparison lives. |
| `src/core/zone.gd` | **Modify.** Delete `dirty_chunk_coords()` and `clear_dirty()`. |
| `src/core/zone_loader.gd` | **Modify.** Drop the post-load `clear_dirty()`. |
| `src/core/save/chunk_codec.gd` | **Modify.** Line 122 assigns `dirty`; becomes a version assignment. |
| `src/core/save/save_manager.gd` | **Modify.** `save_zone` takes a `ChunkWatcher`; the two `clear_dirty()` calls go. |
| `src/systems/game_session.gd` | **Modify.** Owns the save's watcher across saves, since `SaveManager` is all statics. |
| `src/systems/collision_builder.gd` | **Modify.** Incremental invalidation via its own watcher; correct the stale "Phase 4" header. |
| `src/presentation/zone_renderer.gd` | **Modify.** `refresh_dirty` → `refresh_changed`, backed by its own watcher. |
| `src/presentation/world.gd` | **Modify.** The debug place action for Task 7. |
| `tools/smoke.gd` | **Modify.** Uses the new names; gains a race assertion. |

Tests: `tests/test_chunk.gd`, `tests/test_chunk_watcher.gd` (new),
`tests/test_zone.gd`, `tests/test_chunk_codec.gd`, `tests/test_save_manager.gd`,
`tests/test_zone_loader.gd`, `tests/test_collision_builder.gd`,
`tests/test_animal_system.gd`, `tests/test_animal_budget.gd`,
`tests/test_game_session.gd`.

---

## Task 1: Chunk carries a version, not a flag

A counter rather than a boolean is the whole fix: a boolean can only be
consumed once, and two consumers consuming it is the bug.

**Files:**
- Modify: `src/core/chunk.gd:18` (the declaration), `:49`, `:58`, `:67`, `:76`, `:85` (the five setters)
- Modify: `src/core/save/chunk_codec.gd:122`
- Test: `tests/test_chunk.gd:22`, `:66-74`; `tests/test_chunk_codec.gd:61-64`

**Interfaces:**
- Produces: `Chunk.version: int`, starting at `0`, strictly increasing on every
  write. `Chunk.dirty` no longer exists.

- [x] **Step 1: Rewrite the two failing tests in `tests/test_chunk.gd`**

Replace `test_setters_mark_the_chunk_dirty` and
`test_getters_do_not_mark_the_chunk_dirty`, and fix the assertion at line 22:

```gdscript
func test_a_fresh_chunk_starts_at_version_zero() -> void:
	assert_eq(_c.version, 0, "a freshly constructed chunk is at version 0")


func test_every_setter_advances_the_version() -> void:
	var before: int = _c.version
	_c.set_terrain(Vector2i(1, 1), 7)
	assert_gt(_c.version, before, "writing terrain advances the version")

	before = _c.version
	_c.set_floor(Vector2i(1, 1), 7)
	assert_gt(_c.version, before, "writing floor advances the version")

	before = _c.version
	_c.set_object(Vector2i(1, 1), 7)
	assert_gt(_c.version, before, "writing object advances the version")

	before = _c.version
	_c.set_height(Vector2i(1, 1), 3)
	assert_gt(_c.version, before, "writing height advances the version")

	before = _c.version
	_c.set_flags(Vector2i(1, 1), 1)
	assert_gt(_c.version, before, "writing flags advances the version")


func test_the_version_never_goes_backwards() -> void:
	# Two consumers compare against a remembered number. If a write could
	# lower it, a consumer that had already seen a higher one would go
	# blind to every later edit.
	var seen: int = _c.version
	for i: int in range(50):
		_c.set_object(Vector2i(i % 32, 0), i)
		assert_gt(_c.version, seen, "version decreased or stalled on write %d" % i)
		seen = _c.version


func test_getters_do_not_advance_the_version() -> void:
	_c.set_object(Vector2i(2, 2), 5)
	var after_write: int = _c.version
	var _t: int = _c.get_terrain(Vector2i(2, 2))
	var _o: int = _c.get_object(Vector2i(2, 2))
	assert_eq(_c.version, after_write, "reading must not advance the version")
```

- [x] **Step 2: Run them and watch them fail**

Run: `./tools/run_tests.sh`
Expected: FAIL — `Invalid access to property or key 'version' on a base object of type 'RefCounted (Chunk)'`.

- [x] **Step 3: Change the declaration in `src/core/chunk.gd`**

Replace line 18:

```gdscript
## Advanced by every write. Consumers remember the number they last acted
## on and compare, rather than consuming a shared flag: a boolean can only
## be consumed once, and the renderer, the save and the collider all need
## to see the same edit. See the Stage 2 design §3.1.
var version: int = 0
```

- [x] **Step 4: Bump it in all five setters**

In each of `set_terrain`, `set_floor`, `set_object`, `set_height` and
`set_flags`, replace `dirty = true` with:

```gdscript
	version += 1
```

- [x] **Step 5: Fix the decoder**

`src/core/save/chunk_codec.gd:122` currently reads `chunk.dirty = false`.
Replace it, keeping the comment's intent:

```gdscript
	# Freshly loaded data matches disk, so no consumer owes it work. The
	# decoded chunk starts at version 0 and every watcher starts empty,
	# which compares equal.
	chunk.version = 0
```

- [x] **Step 6: Fix the codec test**

In `tests/test_chunk_codec.gd`, replace `test_decoded_chunk_is_not_dirty`:

```gdscript
func test_a_decoded_chunk_starts_at_version_zero() -> void:
	var c: Chunk = _sample_chunk()
	var back: Chunk = ChunkCodec.decode(ChunkCodec.encode(c)).value as Chunk
	assert_eq(back.version, 0, "a chunk read from disk owes no consumer work")
```

- [x] **Step 7: Run the tests**

Run: `./tools/run_tests.sh`
Expected: the Chunk and ChunkCodec tests PASS. Tests in `test_zone.gd`,
`test_save_manager.gd`, `test_zone_loader.gd`, `test_animal_system.gd` and
`test_animal_budget.gd` will still FAIL — they call `clear_dirty()` and
`dirty_chunk_coords()`, which Task 3 removes. That is expected here.

- [x] **Step 8: Commit**

```bash
git add src/core/chunk.gd src/core/save/chunk_codec.gd tests/test_chunk.gd tests/test_chunk_codec.gd
git commit -m "feat: a chunk carries a version, not a dirty flag"
```

- [x] **Step 9: Tick the plan**

```bash
python3 tools/mark_task_done.py 1 --plan docs/superpowers/plans/2026-09-22-rp1-phase7-mutation-spine.md
git add docs/superpowers/plans/2026-09-22-rp1-phase7-mutation-spine.md
git commit -m "docs: tick Phase 7 task 1"
```

---

## Task 2: ChunkWatcher — one consumer's view of what changed

The comparison lives in exactly one place. Three consumers implementing
"have I seen this version" separately is three chances to get it wrong.

**Files:**
- Create: `src/core/chunk_watcher.gd`
- Test: `tests/test_chunk_watcher.gd`

**Interfaces:**
- Consumes: `Chunk.version` (Task 1), `Zone.chunk_coords()`, `Zone.get_chunk()`.
- Produces:
  - `ChunkWatcher.changed(zone: Zone) -> Array[Vector2i]` — coords whose
    version differs from the one last marked seen, in `chunk_coords()` order.
  - `ChunkWatcher.mark_seen(zone: Zone) -> void` — records every chunk's
    current version.
  - `ChunkWatcher.forget() -> void` — drops all memory, so the next
    `changed()` reports every chunk. Used when a consumer is pointed at a
    different zone.

- [x] **Step 1: Write the failing test**

Create `tests/test_chunk_watcher.gd`:

```gdscript
extends GutTest
## The multi-consumer dirty channel, which Stage 1 did not have and the
## Stage 2 design §3.1 requires.

var _z: Zone = null


func before_each() -> void:
	_z = Zone.new("test", Vector2i(64, 64))
	# Touch every chunk into existence, then agree they are all seen.
	for c: Vector2i in _z.chunk_coords():
		var _c: Chunk = _z.get_chunk(c, true)


func test_a_fresh_watcher_reports_every_chunk() -> void:
	# A watcher that has never looked has seen nothing, so everything is
	# work. This is what makes the initial full paint fall out for free.
	var w: ChunkWatcher = ChunkWatcher.new()
	assert_eq(w.changed(_z).size(), _z.chunk_coords().size())


func test_marking_seen_makes_a_quiet_zone_report_nothing() -> void:
	var w: ChunkWatcher = ChunkWatcher.new()
	w.mark_seen(_z)
	assert_eq(w.changed(_z), [] as Array[Vector2i])


func test_a_write_is_reported_to_the_watcher() -> void:
	var w: ChunkWatcher = ChunkWatcher.new()
	w.mark_seen(_z)
	_z.set_object(Vector2i(5, 5), 3)
	assert_eq(w.changed(_z), [Vector2i(0, 0)] as Array[Vector2i])


func test_changed_is_idempotent_until_marked_seen() -> void:
	# Asking twice must answer twice. A consumer that asks, fails, and
	# asks again has not lost the work.
	var w: ChunkWatcher = ChunkWatcher.new()
	w.mark_seen(_z)
	_z.set_object(Vector2i(5, 5), 3)
	assert_eq(w.changed(_z).size(), 1)
	assert_eq(w.changed(_z).size(), 1, "asking did not consume the answer")
	w.mark_seen(_z)
	assert_eq(w.changed(_z).size(), 0)


func test_two_watchers_do_not_starve_each_other() -> void:
	# THE regression test for this phase. In Stage 1 the renderer and the
	# save both called zone.clear_dirty(); whichever ran second saw
	# nothing, and an edit could reach the screen without reaching disk.
	var renderer: ChunkWatcher = ChunkWatcher.new()
	var saver: ChunkWatcher = ChunkWatcher.new()
	renderer.mark_seen(_z)
	saver.mark_seen(_z)

	_z.set_object(Vector2i(5, 5), 3)

	assert_eq(renderer.changed(_z).size(), 1, "the renderer sees the edit")
	renderer.mark_seen(_z)
	assert_eq(saver.changed(_z).size(), 1,
		"the save still sees the edit after the renderer consumed it")


func test_forget_reports_everything_again() -> void:
	var w: ChunkWatcher = ChunkWatcher.new()
	w.mark_seen(_z)
	assert_eq(w.changed(_z).size(), 0)
	w.forget()
	assert_eq(w.changed(_z).size(), _z.chunk_coords().size())


func test_a_chunk_created_after_the_last_look_is_reported() -> void:
	var small: Zone = Zone.new("small", Vector2i(64, 64))
	var w: ChunkWatcher = ChunkWatcher.new()
	w.mark_seen(small)
	small.set_object(Vector2i(40, 40), 9)
	assert_true(w.changed(small).has(Vector2i(1, 1)),
		"a chunk brought into existence by a write is work")
```

- [x] **Step 2: Run it and watch it fail**

Run: `./tools/run_tests.sh`
Expected: FAIL — GUT cannot resolve the `ChunkWatcher` class name.

- [x] **Step 3: Write the implementation**

Create `src/core/chunk_watcher.gd`:

```gdscript
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
```

Note the `-1` default in `changed()`: a chunk never seen cannot compare equal
to version `0`, which is what makes a fresh watcher report everything.

- [x] **Step 4: Run the test**

Run: `./tools/run_tests.sh`
Expected: all seven `test_chunk_watcher.gd` tests PASS.

- [x] **Step 5: Commit**

```bash
git add src/core/chunk_watcher.gd tests/test_chunk_watcher.gd
git commit -m "feat: a per-consumer chunk watcher"
```

- [x] **Step 6: Tick the plan**

```bash
python3 tools/mark_task_done.py 2 --plan docs/superpowers/plans/2026-09-22-rp1-phase7-mutation-spine.md
git add docs/superpowers/plans/2026-09-22-rp1-phase7-mutation-spine.md
git commit -m "docs: tick Phase 7 task 2"
```

---

## Task 3: Zone loses the shared flag

Leaving `clear_dirty()` in place would leave the bug reachable by anyone who
reaches for the familiar name. It goes.

**Files:**
- Modify: `src/core/zone.gd:58-68` (delete both functions)
- Modify: `src/core/zone_loader.gd:79-81`
- Test: `tests/test_zone.gd:74-80`, `tests/test_zone_loader.gd:413-416`,
  `tests/test_animal_system.gd:25`, `:139`, `:185`,
  `tests/test_animal_budget.gd:38`

**Interfaces:**
- Consumes: `ChunkWatcher` (Task 2).
- Produces: `Zone` with no `dirty_chunk_coords()` and no `clear_dirty()`.
  Callers use a `ChunkWatcher`.

- [x] **Step 1: Replace the Zone dirty test**

In `tests/test_zone.gd`, replace `test_dirty_tracking`:

```gdscript
func test_writes_advance_the_version_of_each_touched_chunk() -> void:
	var w: ChunkWatcher = ChunkWatcher.new()
	w.mark_seen(_z)
	assert_eq(w.changed(_z).size(), 0)
	_z.set_object(Vector2i(1, 1), 4)
	_z.set_object(Vector2i(40, 40), 4)
	assert_eq(w.changed(_z).size(), 2, "two chunks touched")
	w.mark_seen(_z)
	assert_eq(w.changed(_z).size(), 0)
```

- [x] **Step 2: Replace the loader test**

In `tests/test_zone_loader.gd`, replace `test_the_zone_comes_back_with_no_dirty_chunks`:

```gdscript
func test_a_freshly_loaded_zone_owes_a_watcher_nothing_once_seen() -> void:
	# The loader used to clear_dirty() after building. With versions there
	# is nothing to clear: a consumer marks the loaded state as seen and
	# only later edits are work.
	var r: ZoneLoadResult = _load_ok()
	var w: ChunkWatcher = ChunkWatcher.new()
	w.mark_seen(r.zone)
	assert_eq(w.changed(r.zone), [] as Array[Vector2i],
		"a loaded zone reports no work once seen")
```

- [x] **Step 3: Run them and watch them fail**

Run: `./tools/run_tests.sh`
Expected: FAIL — the new tests fail, and the existing `clear_dirty()` calls in
`test_animal_system.gd` and `test_animal_budget.gd` still compile because the
function still exists.

- [x] **Step 4: Delete both functions from `src/core/zone.gd`**

Remove `dirty_chunk_coords()` (lines 58-64) and `clear_dirty()` (lines 66-68)
entirely. Leave `install_chunk`'s comment at line 39 intact but correct it:

```gdscript
## Installs a pre-built chunk, used by the loader. Does not advance its
## version: a loaded chunk matches disk, so no consumer owes it work.
```

- [x] **Step 5: Drop the loader's clear**

In `src/core/zone_loader.gd`, delete the `zone.clear_dirty()` call at line 81
and replace the comment above it:

```gdscript
	# Nothing to clear: install_chunk() never advances a version, so a
	# freshly built zone is already at the state a watcher will mark seen.
```

- [x] **Step 6: Fix the four incidental call sites**

In `tests/test_animal_system.gd` (lines 25, 139, 185) and
`tests/test_animal_budget.gd` (line 38), these tests called `zone.clear_dirty()`
only to establish a quiet baseline. They no longer need it — **delete the
line** in all four places. Nothing replaces it: animals move entities, not
tiles, so they never advanced a chunk version in the first place.

- [x] **Step 7: Run the tests**

Run: `./tools/run_tests.sh`
Expected: `test_zone.gd`, `test_zone_loader.gd`, `test_animal_system.gd` and
`test_animal_budget.gd` PASS. `test_save_manager.gd` still FAILS — Task 4
fixes it. `tools/smoke.gd` is not run by the suite.

- [x] **Step 8: Commit**

```bash
git add src/core/zone.gd src/core/zone_loader.gd tests/test_zone.gd tests/test_zone_loader.gd tests/test_animal_system.gd tests/test_animal_budget.gd
git commit -m "feat: the zone no longer owns a shared dirty flag"
```

- [x] **Step 9: Tick the plan**

```bash
python3 tools/mark_task_done.py 3 --plan docs/superpowers/plans/2026-09-22-rp1-phase7-mutation-spine.md
git add docs/superpowers/plans/2026-09-22-rp1-phase7-mutation-spine.md
git commit -m "docs: tick Phase 7 task 3"
```

---

## Task 4: The save takes a watcher, and the race gets a test

`SaveManager` is all static functions, so it has nowhere to keep a watcher.
`GameSession` owns it, because it is the thing that lives across saves.

**Files:**
- Modify: `src/core/save/save_manager.gd:52-55` (signature), `:83`, `:100`, `:161`, `:188-190`
- Modify: `src/systems/game_session.gd:162-163`
- Test: `tests/test_save_manager.gd:117-135`, `:263-270`

**Interfaces:**
- Consumes: `ChunkWatcher` (Task 2).
- Produces:
  `SaveManager.save_zone(save_root: String, zone: Zone, registry: ContentRegistry, watcher: ChunkWatcher, all_chunks: bool = false, keep_backup: bool = false) -> PackedStringArray`
  — `watcher` is required and inserted after `registry`.

- [x] **Step 1: Write the failing tests**

In `tests/test_save_manager.gd`, replace `test_only_dirty_chunks_are_rewritten`
and `test_a_freshly_loaded_zone_is_not_dirty`:

```gdscript
func test_only_changed_chunks_are_rewritten() -> void:
	var z: Zone = _sample_zone()
	var w: ChunkWatcher = ChunkWatcher.new()
	var _e: PackedStringArray = SaveManager.save_zone(_root, z, _registry, w, true)
	assert_eq(w.changed(z).size(), 0, "a full save leaves nothing owing")

	z.set_object(Vector2i(1, 1), 3)
	assert_eq(w.changed(z), [Vector2i(0, 0)] as Array[Vector2i])

	var written: Array[String] = _chunk_files_touched_by(
		func() -> void:
			var _e2: PackedStringArray = SaveManager.save_zone(_root, z, _registry, w)
	)
	assert_eq(written, ["0_0.chunk"], "only the changed chunk was written")


func test_the_renderer_consuming_first_does_not_rob_the_save() -> void:
	# The Stage 1 bug, as a test. Both consumers used to clear one flag.
	var z: Zone = _sample_zone()
	var saver: ChunkWatcher = ChunkWatcher.new()
	var renderer: ChunkWatcher = ChunkWatcher.new()
	var _e: PackedStringArray = SaveManager.save_zone(_root, z, _registry, saver, true)
	renderer.mark_seen(z)

	z.set_object(Vector2i(1, 1), 3)

	# The renderer repaints and records, exactly as _process does.
	assert_eq(renderer.changed(z).size(), 1)
	renderer.mark_seen(z)

	# The save must still see the edit.
	assert_eq(saver.changed(z), [Vector2i(0, 0)] as Array[Vector2i],
		"the save lost an edit the renderer had already drawn")


func test_a_freshly_loaded_zone_owes_the_save_nothing() -> void:
	var loaded: Zone = _save_and_reload()
	var w: ChunkWatcher = ChunkWatcher.new()
	w.mark_seen(loaded)
	assert_eq(w.changed(loaded).size(), 0)
```

If `_chunk_files_touched_by` does not already exist in this file, add it —
compare the chunk directory listing and mtimes around the call, or simply
delete the chunk directory before the second save and assert on what
reappears. Pick whichever matches the helpers already in the file; do not
invent a second style.

- [x] **Step 2: Run them and watch them fail**

Run: `./tools/run_tests.sh`
Expected: FAIL — `save_zone` takes 5 arguments, not 6.

- [x] **Step 3: Change the signature**

In `src/core/save/save_manager.gd`, replace lines 52-55:

```gdscript
## `watcher` is the caller's record of what it has already written. It is
## required rather than optional: an accidental omission would silently
## write every chunk on every save, which is the kind of regression that
## looks like a performance problem months later.
static func save_zone(
	save_root: String, zone: Zone, registry: ContentRegistry,
	watcher: ChunkWatcher,
	all_chunks: bool = false, keep_backup: bool = false
) -> PackedStringArray:
```

- [x] **Step 4: Use the watcher, and stop clearing**

Replace line 83:

```gdscript
	var targets: Array[Vector2i] = zone.chunk_coords() if all_chunks else watcher.changed(zone)
```

Replace the `if errors.is_empty(): zone.clear_dirty()` block near line 100:

```gdscript
	if errors.is_empty():
		watcher.mark_seen(zone)
```

At line 161, inside `_translate_column`'s caller, `chunk.dirty = false`
becomes nothing — **delete the line**. Rewriting an id column is not a
content change the player made, but it does change bytes on disk, so the
chunk's version must not be forced backwards. Leaving the version alone is
correct: the recompute path saves with `all_chunks = true` anyway.

At lines 188-190, delete the `zone.clear_dirty()` call and replace the
comment:

```gdscript
	# The recompute rewrote every chunk with all_chunks = true, so the
	# watcher was already marked seen above. Nothing further is owed.
```

- [x] **Step 5: Give GameSession the watcher**

In `src/systems/game_session.gd`, add near the other fields:

```gdscript
## The save's own view of what it has written. Held here rather than in
## SaveManager, which is all static functions and has nowhere to keep it.
var _save_watcher: ChunkWatcher = ChunkWatcher.new()
```

Update the call at line 162-163:

```gdscript
	var errors: PackedStringArray = SaveManager.save_zone(
		save_root, zone, registry, _save_watcher, needs_full_save, true)
```

Wherever `GameSession` opens a different zone (`open_new` and `open_saved`),
add `_save_watcher.forget()` after the zone is assigned — versions are per
zone, and carrying them across worlds would make the first save of a new world
skip chunks.

- [x] **Step 6: Correct two comments that versions made stale, and leave `all_chunks` alone**

`src/systems/game_session.gd:30` and `tests/test_game_session.gd:105` both
explain that "nothing in Stage 1 dirties a tile, so a dirty-only first save
writes no chunks at all". That reasoning no longer holds and the replacement
matters:

> A fresh `ChunkWatcher` has seen nothing, and `changed()` defaults an unseen
> chunk to `-1`, which never equals a real version. **So a first save writes
> every chunk even without `all_chunks`** — the old hazard is gone.

Reword both comments to say that.

**Do not delete `needs_full_save` or the `all_chunks` parameter.** It looks
redundant now and is not: the id-recompute path in `save_manager.gd` rewrites
every chunk's id columns and must write them all regardless of what any
watcher believes. Removing the flag would make a recompute write only the
chunks a player happened to touch, which corrupts the rest silently.

- [x] **Step 7: Run the tests**

Run: `./tools/run_tests.sh`
Expected: PASS, all scripts. This is the first point in the phase where the
whole suite is green again.

- [x] **Step 8: Commit**

```bash
git add src/core/save/save_manager.gd src/systems/game_session.gd tests/test_save_manager.gd tests/test_game_session.gd
git commit -m "feat: the save keeps its own record of what it has written"
```

- [x] **Step 9: Tick the plan**

```bash
python3 tools/mark_task_done.py 4 --plan docs/superpowers/plans/2026-09-22-rp1-phase7-mutation-spine.md
git add docs/superpowers/plans/2026-09-22-rp1-phase7-mutation-spine.md
git commit -m "docs: tick Phase 7 task 4"
```

---

## Task 5: The renderer repaints from its own watcher

**Files:**
- Modify: `src/presentation/zone_renderer.gd:115-132`
- Modify: `tools/smoke.gd:59-67`

**Interfaces:**
- Consumes: `ChunkWatcher` (Task 2).
- Produces: `ZoneRenderer.refresh_changed(p_zone: Zone) -> int` — returns cells
  painted, `0` when nothing changed. `refresh_dirty` no longer exists.

- [ ] **Step 1: Rewrite the repaint path**

In `src/presentation/zone_renderer.gd`, add a field beside `var zone: Zone`:

```gdscript
var _watcher: ChunkWatcher = ChunkWatcher.new()
```

Replace `refresh_dirty` (lines 115-126):

```gdscript
## Repaints only the chunks whose version has moved since this renderer
## last painted them. The only repaint permitted from _process: a full
## render_zone() every frame would be 16,384 set_cell calls per frame.
##
## The watcher is private to the renderer. Nothing is cleared, so the save
## and the collider still see the same edits -- see Stage 2 design §3.1.
func refresh_changed(p_zone: Zone) -> int:
	var changed: Array[Vector2i] = _watcher.changed(p_zone)
	if changed.is_empty():
		return 0
	var painted: int = 0
	for c: Vector2i in changed:
		painted += _paint_chunk(p_zone, c)
	_watcher.mark_seen(p_zone)
	return painted
```

Update `_process` to call the new name:

```gdscript
func _process(_delta: float) -> void:
	if zone != null:
		refresh_changed(zone)
```

In `render_zone()`, after the full paint, add:

```gdscript
	_watcher.forget()
	_watcher.mark_seen(zone)
```

so a full paint leaves the renderer owing nothing, and pointing the renderer
at a different zone does not carry stale versions across.

- [ ] **Step 2: Update the smoke test**

In `tools/smoke.gd`, replace lines 59-67:

```gdscript
	# A chunk whose version moved is repainted; an untouched one is not.
	var before_dirty: int = renderer.cells_painted()
	_check(renderer.refresh_changed(zone) == 0, "a quiet zone repaints nothing")
	zone.set_object(Vector2i(1, 1), 0)
	var repainted: int = renderer.refresh_changed(zone)
	_check(repainted > 0, "a changed chunk repaints")
	_check(repainted < painted, "a changed repaint touches one chunk, not the whole zone")
	_check(renderer.cells_painted() == before_dirty,
		"repainting a chunk does not change the cell count")
```

- [ ] **Step 3: Run the tests and the smoke test**

```bash
./tools/run_tests.sh
./tools/godot.sh --headless --path . -s tools/smoke.gd
```
Expected: tests PASS; smoke prints `Smoke test: OK (300 iterations)`.

- [ ] **Step 4: Commit**

```bash
git add src/presentation/zone_renderer.gd tools/smoke.gd
git commit -m "feat: the renderer repaints from its own watcher"
```

- [ ] **Step 5: Tick the plan**

```bash
python3 tools/mark_task_done.py 5 --plan docs/superpowers/plans/2026-09-22-rp1-phase7-mutation-spine.md
git add docs/superpowers/plans/2026-09-22-rp1-phase7-mutation-spine.md
git commit -m "docs: tick Phase 7 task 5"
```

---

## Task 6: The collider rebuilds only what changed

Stage 1's `CollisionBuilder` caches per chunk and requires an explicit
invalidation call that nobody ever made, because nothing mutated tiles. Now
something does.

**Files:**
- Modify: `src/systems/collision_builder.gd:14-22` (header), plus a new method
- Test: `tests/test_collision_builder.gd`

**Interfaces:**
- Consumes: `ChunkWatcher` (Task 2).
- Produces: `CollisionBuilder.invalidate_changed(zone: Zone) -> int` — drops
  the cached rects for every chunk whose version moved, returns how many were
  dropped.

- [ ] **Step 1: Write the failing test**

Add to `tests/test_collision_builder.gd`:

```gdscript
func test_invalidate_changed_drops_only_the_touched_chunk() -> void:
	var z: Zone = Zone.new("t", Vector2i(64, 64))
	for c: Vector2i in z.chunk_coords():
		var _c: Chunk = z.get_chunk(c, true)
	var b: CollisionBuilder = CollisionBuilder.new()
	for c: Vector2i in z.chunk_coords():
		var _r: Array[Rect2i] = b.rects_for_chunk(z.get_chunk(c))
	assert_eq(b.invalidate_changed(z), 0, "a quiet zone invalidates nothing")

	z.set_flags(Vector2i(1, 1), 0)
	assert_eq(b.invalidate_changed(z), 1, "only the touched chunk is dropped")
	assert_eq(b.invalidate_changed(z), 0, "the drop is not repeated")


func test_a_rebuilt_chunk_reflects_the_new_tiles() -> void:
	# A fresh chunk has every flag byte at 0, which already means NOT
	# walkable -- so "make a tile solid" on a fresh chunk changes nothing
	# and would assert vacuously. Make the chunk walkable first, so that
	# clearing one tile is a real change.
	var z: Zone = Zone.new("t", Vector2i(64, 64))
	var _c: Chunk = z.get_chunk(Vector2i(0, 0), true)
	for y: int in range(Coords.CHUNK_SIZE):
		for x: int in range(Coords.CHUNK_SIZE):
			z.set_flags(Vector2i(x, y), Chunk.FLAG_WALKABLE)

	var b: CollisionBuilder = CollisionBuilder.new()
	var before: int = b.rects_for_chunk(z.get_chunk(Vector2i(0, 0))).size()
	assert_eq(before, 0, "an all-walkable chunk needs no collision rects")

	z.set_flags(Vector2i(2, 2), 0)
	var _n: int = b.invalidate_changed(z)
	assert_gt(b.rects_for_chunk(z.get_chunk(Vector2i(0, 0))).size(), before,
		"the rebuilt chunk reflects the newly solid tile")
```

- [ ] **Step 2: Run it and watch it fail**

Run: `./tools/run_tests.sh`
Expected: FAIL — `invalidate_changed` is not a method of `CollisionBuilder`.

- [ ] **Step 3: Implement it**

Add to `src/systems/collision_builder.gd`:

```gdscript
var _watcher: ChunkWatcher = ChunkWatcher.new()


## Drops cached rects for every chunk whose version has moved since this
## builder last looked. Returns how many were dropped. Call once per frame
## before reading rects; rebuilding 1024 tiles per chunk per frame is not
## affordable, and rebuilding only what changed is the whole point.
func invalidate_changed(zone: Zone) -> int:
	var changed: Array[Vector2i] = _watcher.changed(zone)
	for c: Vector2i in changed:
		_cache.erase(c)
	_watcher.mark_seen(zone)
	return changed.size()
```

- [ ] **Step 4: Correct the stale header**

Replace lines 17-21 of `src/systems/collision_builder.gd`:

```gdscript
## Invalidation is an EXPLICIT call -- invalidate_changed() -- driven by a
## private ChunkWatcher rather than by a shared flag. Stage 1 had a single
## boolean that both ZoneRenderer and SaveManager cleared, so a second
## consumer saw nothing. Phase 7 replaced it with per-chunk versions; see
## the Stage 2 design §3.1.
```

The old text blamed "Phase 4", which never owned this — Phase 4 introduced
entity movement, not tile mutation. Do not preserve that sentence.

- [ ] **Step 5: Run the tests**

Run: `./tools/run_tests.sh`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add src/systems/collision_builder.gd tests/test_collision_builder.gd
git commit -m "feat: the collider rebuilds only the chunks that changed"
```

- [ ] **Step 7: Tick the plan**

```bash
python3 tools/mark_task_done.py 6 --plan docs/superpowers/plans/2026-09-22-rp1-phase7-mutation-spine.md
git add docs/superpowers/plans/2026-09-22-rp1-phase7-mutation-spine.md
git commit -m "docs: tick Phase 7 task 6"
```

---

## Task 7: One wall, placed and kept

The vertical slice. No UI, no mouse, no inventory, no cost — those are Phases
8 to 10. This proves the spine end to end.

**Files:**
- Modify: `project.godot` (one new `InputMap` action, `debug_place`)
- Modify: `src/presentation/world.gd`
- Test: manual, plus the smoke test's existing save assertions

**Interfaces:**
- Consumes: `Zone.set_object`, `ChunkWatcher` via the renderer, save and
  collider from Tasks 4-6.
- Produces: nothing later phases depend on. **The debug action is removed in
  Phase 10**, when the real build mode lands. Leave a comment saying so.

- [ ] **Step 1: Add the input action**

In `project.godot`, under `[input]`, add a `debug_place` action bound to `B`,
matching the shape of the existing `pause` entry exactly (including
`"deadzone": 0.2`).

- [ ] **Step 2: Place a wall on the faced tile**

In `src/presentation/world.gd`, add:

```gdscript
## DEBUG ONLY -- removed in Phase 10 when build mode lands. This exists to
## prove the Phase 7 mutation spine end to end: one edit, seen by the
## renderer, the collider and the save without any of them robbing the
## others.
func _debug_place_wall() -> void:
	var tile: Vector2i = _player_facing_tile()
	if not zone.in_bounds(tile):
		return
	if zone.get_object(tile) != 0:
		return
	zone.set_object(tile, _registry.numeric_of("wall_wood"))
	zone.set_flags(tile, 0)
```

Wire it in `_unhandled_input` (or wherever `world.gd` already reads input —
follow the file's existing pattern rather than introducing a second one):

```gdscript
	if event.is_action_pressed("debug_place"):
		_debug_place_wall()
```

`_player_facing_tile()` returns the tile one step in the player's facing
direction. If `world.gd` has no such helper, add one next to the existing
facing code and keep it private.

- [ ] **Step 3: Rebuild collision each frame from the watcher**

Wherever `world.gd` ticks the collider, call `invalidate_changed(zone)` before
reading rects, so a placed wall becomes solid on the next frame.

- [ ] **Step 4: Run it and place a wall**

```bash
./tools/godot.sh --path .
```

New World, walk, press **B**. Check by hand:

- [ ] A wooden wall appears on the tile the player faces
- [ ] The player cannot walk into it
- [ ] Pressing B against an occupied tile does nothing
- [ ] Quit to Menu, then Continue — **the wall is still there**
- [ ] Quit the process entirely, relaunch, Continue — **the wall is still there**

The last two are the phase. If the wall survives a Quit to Menu but not a
process relaunch, the save did not see the edit and the watcher wiring in
Task 4 is wrong.

- [ ] **Step 5: Run every gate**

```bash
./tools/run_tests.sh
./tools/godot.sh --headless --path . -s tools/guard.gd
./tools/godot.sh --headless --path . -s tools/smoke.gd
./tools/check_asset_licences.sh
./tools/check_palette.sh
./tools/check_zone.sh
```
Expected: all six exit 0.

- [ ] **Step 6: Commit**

```bash
git add project.godot src/presentation/world.gd
git commit -m "feat: a wall placed in play survives a relaunch"
```

- [ ] **Step 7: Tick the plan**

```bash
python3 tools/mark_task_done.py 7 --plan docs/superpowers/plans/2026-09-22-rp1-phase7-mutation-spine.md
git add docs/superpowers/plans/2026-09-22-rp1-phase7-mutation-spine.md
git commit -m "docs: tick Phase 7 task 7"
```

---

## Definition of done

- [ ] `Chunk.dirty` does not exist anywhere in `src/`, `tools/` or `tests/`
- [ ] `Zone.clear_dirty` and `Zone.dirty_chunk_coords` do not exist
- [ ] A renderer watcher and a save watcher both observe the same edit, proved
      by `test_the_renderer_consuming_first_does_not_rob_the_save`
- [ ] A wall placed with the debug key survives a full process relaunch
- [ ] A placed wall blocks movement on the frame after it is placed
- [ ] Only changed chunks are rewritten on an incremental save
- [ ] `collision_builder.gd`'s header no longer blames Phase 4
- [ ] All six local gates green, and CI green on the branch
