# RP1 Phases 0-2 — Foundation, Data Layer, Persistence — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a tested, versioned, node-free world engine — chunked tile data, an entity store, a JSON content registry, and atomic compressed persistence — behind five CI gates, with no rendering.

**Architecture:** Five layers with dependencies pointing strictly downward. `src/core/` and `src/systems/` extend `RefCounted` only and never touch Godot nodes, which makes every line here testable headless in milliseconds. Tile data lives in five parallel `PackedByteArray` columns per 32x32 chunk; entities live in a per-zone struct-of-arrays store. Save files carry a plaintext header outside a ZSTD-compressed payload so the format version is readable before parsing.

**Tech Stack:** Godot 4.7.2 stable (standard, non-Mono build), GDScript with static typing, GUT 9.7.1, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-08-23-rp1-stage0-stage1-design.md`

**Scope:** This plan covers spec Phases 0, 1 and 2. Phases 3-6 (rendering, world content, game loop, polish) get a separate plan written after this one lands, because their design depends on the finished shape of the data layer.

## Global Constraints

Every task's requirements implicitly include this section.

- **Engine:** Godot 4.7.2 stable, **standard (non-Mono) build**. The Mono build hangs in headless mode with no .NET runtime and breaks every CI gate.
- **Local binary:** `~/Applications/Godot.app/Contents/MacOS/Godot`. All commands in this plan use the `./tools/godot.sh` wrapper created in Task 1.
- **Language:** GDScript only. No C#.
- **Static typing everywhere:** `var x: int = 0`, `func f(a: Vector2i) -> void:`. No untyped declarations.
- **`src/core/` and `src/systems/` MUST NOT reference Godot nodes.** No `extends Node`, no `get_tree()`, no `Engine.`, no `.tscn`. These folders extend `RefCounted` only. Enforced by the Task 3 CI gate.
- **All game content lives in `data/*.json`.** Never hardcode content in GDScript. Never write `match` over content types — look it up in `ContentRegistry`.
- **`CHUNK_SIZE` is 32.** Tile size 32x32, character sprites 32x64.
- **Persistence:** never `load()`, `ResourceLoader`, or `.tres` for save data. `get_var()` always passes `false`. Every binary file starts with a 4-byte magic and a `u32` format version, both plaintext. All writes are atomic (temp file, then rename).
- **`godot --headless --path . --import` must succeed before any GUT run.** Without it GUT reports missing class_names **and exits 0**, so a broken setup looks green. The test runner in Task 2 always imports first.
- **TDD.** Every task writes a failing test, watches it fail, implements minimally, watches it pass, commits.

## Commit rhythm

Each task produces **two commits**:

1. **The code commit** — the task's deliverable, written as the second-to-last
   step. Conventional-commit prefixes: `feat:`, `test:`, `ci:`.
2. **The progress commit** — the task's final step ticks its own checkboxes in
   this plan and commits that, so the file is an accurate ledger of what has
   actually been done. Prefix `docs:`.

Never tick checkboxes by hand — a 3,700-line file makes it easy to mark the
wrong task. Use the helper, which ticks exactly one task's boxes and refuses an
unknown task number:

```bash
python3 tools/mark_task_done.py 5          # tick every checkbox in Task 5
python3 tools/mark_task_done.py 5 --undo   # revert if a task is reopened
```

The eleven checkboxes under *Definition of done* are **not** part of any task
and the helper deliberately leaves them alone. Tick those by hand once every
task is complete.

---

## Spec coverage

| Spec Phase 0 task | Covered by |
|---|---|
| 0.1 project created, git initialised | Task 1 |
| 0.2 project settings (Nearest, stretch, integer scaling, 1280x720) | Task 1 |
| 0.3 `CLAUDE.md` + `AGENTS.md` | **Written before this plan runs** -- they govern the agents executing it, so they cannot be a task inside it |
| 0.4 GUT installed, trivial test passing headless | Task 2 |
| 0.5 CI runs the gates on push | Task 16 |
| 0.6 smoke test | Task 15 |
| 0.7 architecture guard | Task 3 |
| 0.8 screenshot script | Task 15 (see the correction there: screenshots cannot run under `--headless`) |

Spec Phase 1 maps to Tasks 4-9, Phase 2 to Tasks 10-14. Spec sections 7
(Presentation) and 6.3 rule 8 (autosave triggers) belong to Phases 3-6 and are
deliberately absent here.

---

## File Structure

| File | Responsibility |
|---|---|
| `project.godot` | Engine settings: Nearest filter, canvas_items stretch, integer scaling, 1280x720 |
| `tools/godot.sh` | Resolves the Godot binary across dev machines and CI |
| `tools/mark_task_done.py` | Ticks one task's checkboxes in this plan (already committed) |
| `tools/run_tests.sh` | Import pass, then GUT; the single entry point for the test suite |
| `tools/guard.gd` | Architecture gate: allowlisted base classes + banned identifiers in core/ and systems/ |
| `tools/smoke.gd` | Boots headless, runs 300 frames, non-zero exit on any error |
| `tools/check_asset_licences.sh` | Fails when a folder under `assets/` lacks `LICENSE.txt` |
| `src/core/coords.gd` | world <-> chunk <-> local conversion. No state. |
| `src/core/chunk.gd` | Five byte columns for 32x32 tiles, dirty flag |
| `src/core/entity_store.gd` | Entity columns, free list, stable IDs |
| `src/core/zone.gd` | Chunk dictionary + entity store + metadata |
| `src/core/schema_validator.gd` | Validates a content definition against a category schema |
| `src/core/content_registry.gd` | Loads JSON, assigns numeric IDs, string <-> numeric lookup |
| `src/core/save/decode_result.gd` | Typed ok/error/value result used by all codecs |
| `src/core/save/chunk_codec.gd` | Chunk <-> bytes, plaintext header + ZSTD payload |
| `src/core/save/entity_codec.gd` | EntityStore <-> bytes, same header pattern |
| `src/core/save/id_map.gd` | Per-save string->numeric map and translation table |
| `src/core/save/migrations.gd` | Version upgrade functions |
| `src/core/save/save_manager.gd` | Atomic writes, dirty-chunk save, zone load |
| `tests/test_*.gd` | One test file per core module |
| `.github/workflows/ci.yml` | Five gates |

---

## Task 1: Project bootstrap and Godot wrapper

**Files:**
- Create: `project.godot`
- Create: `tools/godot.sh`
- Create: `icon.svg`

**Interfaces:**
- Consumes: nothing
- Produces: `./tools/godot.sh` — forwards all arguments to the Godot 4.7.2 binary; honours `$GODOT_BIN` when set, else falls back to `~/Applications/Godot.app/Contents/MacOS/Godot`. Every later task invokes Godot only through this script.

- [x] **Step 1: Create the Godot wrapper**

```bash
mkdir -p tools
cat > tools/godot.sh <<'SH'
#!/usr/bin/env bash
# Resolves the Godot 4.7.2 binary across dev machines and CI.
# Override with GODOT_BIN=/path/to/godot
set -euo pipefail

if [[ -n "${GODOT_BIN:-}" ]]; then
  GODOT="$GODOT_BIN"
elif [[ -x "$HOME/Applications/Godot.app/Contents/MacOS/Godot" ]]; then
  GODOT="$HOME/Applications/Godot.app/Contents/MacOS/Godot"
elif command -v godot >/dev/null 2>&1; then
  GODOT="$(command -v godot)"
else
  echo "ERROR: Godot not found. Set GODOT_BIN or install to ~/Applications/Godot.app" >&2
  exit 127
fi

# Guard against the Mono build, which hangs headless without a .NET runtime.
if "$GODOT" --version 2>/dev/null | grep -q "mono"; then
  echo "ERROR: $GODOT is a Mono build. This project needs the standard build." >&2
  exit 126
fi

exec "$GODOT" "$@"
SH
chmod +x tools/godot.sh
```

- [x] **Step 2: Verify the wrapper reports the right version**

Run: `./tools/godot.sh --version`
Expected: `4.7.2.stable.official.<hash>` with **no** `.mono` in the string.

- [x] **Step 3: Create the project file**

```bash
cat > project.godot <<'CFG'
; Engine configuration file.
config_version=5

[application]

config/name="RP1"
config/description="Pixel-art open-world sandbox"
config/features=PackedStringArray("4.7", "GL Compatibility")
config/icon="res://icon.svg"

[display]

window/size/viewport_width=1280
window/size/viewport_height=720
window/stretch/mode="canvas_items"
window/stretch/aspect="keep"
window/stretch/scale_mode="integer"

[rendering]

textures/canvas_textures/default_texture_filter=0
renderer/rendering_method="gl_compatibility"
renderer/rendering_method.mobile="gl_compatibility"
CFG
```

`default_texture_filter=0` is `Nearest`. This is the project-wide setting the art constants depend on; it is never overridden per-texture.

- [x] **Step 4: Create a placeholder icon**

```bash
cat > icon.svg <<'SVG'
<svg xmlns="http://www.w3.org/2000/svg" width="128" height="128" viewBox="0 0 128 128">
  <rect width="128" height="128" fill="#3b6e4a"/>
  <rect x="32" y="32" width="64" height="64" fill="#c8b88a"/>
</svg>
SVG
```

- [x] **Step 5: Verify the project boots headless and exits cleanly**

Run: `./tools/godot.sh --headless --path . --import`
Expected: exit code 0, and a `.godot/` directory is created.

Check with: `echo $?` and `ls .godot/global_script_class_cache.cfg`

- [x] **Step 6: Commit**

```bash
git add project.godot icon.svg tools/godot.sh
git commit -m "feat: bootstrap Godot 4.7.2 project with pixel-art render settings"
```

- [x] **Step 7: Mark the task complete**

Tick this task's checkboxes and commit the progress, so the plan file itself
records what has been done:

```bash
python3 tools/mark_task_done.py 1
git add docs/superpowers/plans/2026-08-23-rp1-phase0-2-foundation-data-persistence.md
git commit -m "docs: mark Task 1 (Project bootstrap and Godot wrapper) complete"
```


---

## Task 2: GUT test harness

**Files:**
- Create: `addons/gut/**` (vendored from the GUT 9.7.1 release)
- Create: `tools/run_tests.sh`
- Create: `tests/test_harness.gd`

**Interfaces:**
- Consumes: `./tools/godot.sh` from Task 1
- Produces: `./tools/run_tests.sh` — runs the import pass then the full GUT suite; exits 0 when all tests pass, non-zero otherwise. Every later task runs its tests through this script. Test files live in `tests/`, are named `test_*.gd`, and extend `GutTest`.

- [x] **Step 1: Vendor GUT 9.7.1**

GUT is committed to the repo rather than installed from the Asset Library, so CI needs no network and the version cannot drift.

```bash
curl -sL -o /tmp/gut.zip https://github.com/bitwes/Gut/archive/refs/tags/v9.7.1.zip
unzip -q -o /tmp/gut.zip -d /tmp/gutsrc
mkdir -p addons
cp -R /tmp/gutsrc/Gut-9.7.1/addons/gut addons/
rm -rf /tmp/gut.zip /tmp/gutsrc
ls addons/gut/gut_cmdln.gd
```

- [x] **Step 2: Write the test runner**

GUT is quietly permissive in two ways that would each let a broken suite report success, and the runner closes both:

1. **Missing import pass.** Without it GUT prints `Some GUT class_names have not been imported` **and exits 0**.
2. **Unparseable test file.** A test script with a syntax error is skipped with only a `[GUT WARNING] Ignoring script ...` line, and the run **still exits 0**. Found during execution: a `preload` of a not-yet-written file made GUT report "All tests passed" while silently running one script fewer. The runner therefore also asserts that the script count in GUT's summary matches the number of `test_*.gd` files on disk.

```bash
cat > tools/run_tests.sh <<'SH'
#!/usr/bin/env bash
# Single entry point for the test suite.
set -euo pipefail
cd "$(dirname "$0")/.."

# Import pass populates .godot/global_script_class_cache.cfg.
# GUT cannot resolve GutTest without it, and fails with exit code 0.
./tools/godot.sh --headless --path . --import >/dev/null

OUT="$(./tools/godot.sh --headless --path . \
        -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit 2>&1)" || RC=$?
RC="${RC:-0}"
echo "$OUT"

if grep -q "class_names have not been imported" <<<"$OUT"; then
  echo "ERROR: GUT class cache missing; import pass did not take effect." >&2
  exit 2
fi

exit "$RC"
SH
chmod +x tools/run_tests.sh
```

- [x] **Step 3: Write the failing harness test**

```bash
mkdir -p tests
cat > tests/test_harness.gd <<'GD'
extends GutTest


func test_harness_runs() -> void:
	assert_eq(1 + 1, 2, "the test harness executes assertions")


func test_byte_encoding_available() -> void:
	# Guards the engine API the whole data layer is built on.
	var b: PackedByteArray = PackedByteArray()
	b.resize(4)
	b.encode_u16(0, 65535)
	assert_eq(b.decode_u16(0), 65535, "u16 round-trips through PackedByteArray")
GD
```

- [x] **Step 4: Run the suite and verify it passes**

Run: `./tools/run_tests.sh`
Expected: `All tests passed!`, 2 passing tests, exit code 0.

- [x] **Step 5: Verify a failing test actually fails the run**

A test harness that cannot report failure is worse than none. Prove the signal works before trusting it.

```bash
cat > tests/test_temp_fail.gd <<'GD'
extends GutTest
func test_deliberately_fails() -> void:
	assert_eq(1, 2, "deliberate failure")
GD
./tools/run_tests.sh; echo "exit=$?"
rm tests/test_temp_fail.gd
```

Expected: `1 failing tests`, `exit=1`.

- [x] **Step 6: Commit**

```bash
git add addons/gut tools/run_tests.sh tests/test_harness.gd
git commit -m "test: vendor GUT 9.7.1 and add headless test runner

The runner always runs an import pass first. Without it GUT cannot
resolve GutTest and exits 0, which would make a broken suite look
green in CI."
```

- [x] **Step 7: Mark the task complete**

Tick this task's checkboxes and commit the progress, so the plan file itself
records what has been done:

```bash
python3 tools/mark_task_done.py 2
git add docs/superpowers/plans/2026-08-23-rp1-phase0-2-foundation-data-persistence.md
git commit -m "docs: mark Task 2 (GUT test harness) complete"
```


---

## Task 3: Architecture guard gate

**Files:**
- Create: `tools/guard.gd`
- Create: `tests/test_guard.gd`

**Interfaces:**
- Consumes: `./tools/godot.sh`
- Produces: `ArchitectureGuard.scan(roots: PackedStringArray) -> PackedStringArray` — returns one human-readable violation string per offence, empty when clean. `tools/guard.gd` is a `SceneTree` script that runs the scan over `src/core` and `src/systems` and exits 1 on any violation.

The guard is an **allowlist** of permitted base classes plus a banned-identifier scan. A blocklist containing only `extends Node` would pass `extends Node2D`.

- [x] **Step 1: Write the failing test**

```bash
cat > tests/test_guard.gd <<'GD'
extends GutTest

const ArchitectureGuard = preload("res://tools/guard.gd")

var _dir: String = "user://guard_fixture"


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(_dir)


func after_each() -> void:
	for f: String in DirAccess.get_files_at(_dir):
		DirAccess.remove_absolute(_dir.path_join(f))


func _write(name: String, body: String) -> void:
	var f: FileAccess = FileAccess.open(_dir.path_join(name), FileAccess.WRITE)
	f.store_string(body)
	f.close()


func test_refcounted_file_is_clean() -> void:
	_write("ok.gd", "class_name Ok\nextends RefCounted\n\nfunc f() -> int:\n\treturn 1\n")
	var v: PackedStringArray = ArchitectureGuard.scan_dir(_dir)
	assert_eq(v.size(), 0, "a RefCounted file produces no violations")


func test_extends_node2d_is_a_violation() -> void:
	# The precise case a `grep "extends Node"` blocklist would miss.
	_write("bad.gd", "extends Node2D\n")
	var v: PackedStringArray = ArchitectureGuard.scan_dir(_dir)
	assert_eq(v.size(), 1, "extends Node2D is caught")
	assert_string_contains(v[0], "Node2D")


func test_extends_node_is_a_violation() -> void:
	_write("bad.gd", "extends Node\n")
	assert_eq(ArchitectureGuard.scan_dir(_dir).size(), 1)


func test_get_tree_is_a_violation() -> void:
	_write("bad.gd", "extends RefCounted\n\nfunc f() -> void:\n\tget_tree().quit()\n")
	var v: PackedStringArray = ArchitectureGuard.scan_dir(_dir)
	assert_eq(v.size(), 1, "get_tree() is banned even in a RefCounted file")


func test_engine_singleton_is_a_violation() -> void:
	_write("bad.gd", "extends RefCounted\n\nfunc f() -> int:\n\treturn Engine.get_frames_drawn()\n")
	assert_eq(ArchitectureGuard.scan_dir(_dir).size(), 1)


func test_scene_preload_is_a_violation() -> void:
	_write("bad.gd", "extends RefCounted\n\nconst S = preload(\"res://scenes/x.tscn\")\n")
	assert_eq(ArchitectureGuard.scan_dir(_dir).size(), 1)


func test_comments_do_not_trigger_violations() -> void:
	_write("ok.gd", "extends RefCounted\n\n# This class must never extends Node or call get_tree().\n")
	assert_eq(ArchitectureGuard.scan_dir(_dir).size(), 0, "commented mentions are ignored")


func test_multiple_violations_are_all_reported() -> void:
	_write("bad.gd", "extends Node2D\n\nfunc f() -> void:\n\tget_tree().quit()\n")
	assert_eq(ArchitectureGuard.scan_dir(_dir).size(), 2)
GD
```

- [x] **Step 2: Run the test to verify it fails**

Run: `./tools/run_tests.sh`
Expected: FAIL with exit code 3 — `res://tools/guard.gd` does not exist, so the `preload` fails to compile. Note this is caught by the runner's skipped-script check, not by GUT itself: GUT alone reports "All tests passed" and exits 0 here.

- [x] **Step 3: Implement the guard**

```bash
cat > tools/guard.gd <<'GD'
extends SceneTree
## Architecture gate for src/core/ and src/systems/.
##
## These folders are the node-free heart of the project. The gate is an
## allowlist of permitted base classes plus a scan for banned identifiers,
## because a blocklist of "extends Node" would silently pass "extends Node2D".

const ALLOWED_BASES: PackedStringArray = ["RefCounted", "Object"]

const BANNED_IDENTIFIERS: PackedStringArray = [
	"get_tree(",
	"Engine.",
	".tscn",
	"get_node(",
	"add_child(",
	"queue_free(",
]

const GUARDED_ROOTS: PackedStringArray = ["res://src/core", "res://src/systems"]


static func _strip_comment(line: String) -> String:
	# Naive but sufficient: these files contain no "#" inside string literals
	# by convention, and a false negative here only relaxes the gate for a
	# line that is genuinely commented out.
	var i: int = line.find("#")
	return line if i == -1 else line.substr(0, i)


static func scan_file(path: String) -> PackedStringArray:
	var violations: PackedStringArray = []
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		violations.append("%s: cannot open" % path)
		return violations

	var line_no: int = 0
	while not f.eof_reached():
		line_no += 1
		var raw: String = f.get_line()
		var line: String = _strip_comment(raw).strip_edges()
		if line.is_empty():
			continue

		if line.begins_with("extends "):
			var base: String = line.substr(8).strip_edges()
			if not ALLOWED_BASES.has(base):
				violations.append(
					"%s:%d: extends %s (only %s permitted here)"
					% [path, line_no, base, ", ".join(ALLOWED_BASES)]
				)

		for banned: String in BANNED_IDENTIFIERS:
			if line.contains(banned):
				violations.append("%s:%d: banned identifier %s" % [path, line_no, banned])

	f.close()
	return violations


static func scan_dir(root: String) -> PackedStringArray:
	var violations: PackedStringArray = []
	for entry: String in DirAccess.get_directories_at(root):
		violations.append_array(scan_dir(root.path_join(entry)))
	for entry: String in DirAccess.get_files_at(root):
		if entry.ends_with(".gd"):
			violations.append_array(scan_file(root.path_join(entry)))
	return violations


static func scan(roots: PackedStringArray) -> PackedStringArray:
	var violations: PackedStringArray = []
	for root: String in roots:
		if DirAccess.dir_exists_absolute(root):
			violations.append_array(scan_dir(root))
	return violations


func _init() -> void:
	var violations: PackedStringArray = scan(GUARDED_ROOTS)
	for v: String in violations:
		printerr("ARCHITECTURE VIOLATION: ", v)
	if violations.is_empty():
		print("Architecture guard: clean")
		quit(0)
	else:
		printerr("Architecture guard: %d violation(s)" % violations.size())
		quit(1)
GD
```

- [x] **Step 4: Run the tests to verify they pass**

Run: `./tools/run_tests.sh`
Expected: PASS, all 8 guard tests green.

- [x] **Step 5: Verify the gate works end to end**

```bash
mkdir -p src/core
printf 'extends RefCounted\n' > src/core/placeholder.gd
./tools/godot.sh --headless --path . -s tools/guard.gd; echo "clean_exit=$?"

printf 'extends Node2D\n' > src/core/placeholder.gd
./tools/godot.sh --headless --path . -s tools/guard.gd; echo "violation_exit=$?"

printf 'extends RefCounted\n' > src/core/placeholder.gd
```

Expected: `clean_exit=0` then `violation_exit=1`.

- [x] **Step 6: Commit**

```bash
git add tools/guard.gd tests/test_guard.gd src/core/placeholder.gd
git commit -m "test: add architecture guard for node-free core and systems

Allowlist of base classes plus banned identifiers. A blocklist
containing only 'extends Node' would pass 'extends Node2D'."
```

- [x] **Step 7: Mark the task complete**

Tick this task's checkboxes and commit the progress, so the plan file itself
records what has been done:

```bash
python3 tools/mark_task_done.py 3
git add docs/superpowers/plans/2026-08-23-rp1-phase0-2-foundation-data-persistence.md
git commit -m "docs: mark Task 3 (Architecture guard gate) complete"
```


---

## Task 4: Coordinate conversion

**Files:**
- Create: `src/core/coords.gd`
- Create: `tests/test_coords.gd`
- Delete: `src/core/placeholder.gd`

**Interfaces:**
- Consumes: nothing
- Produces: `class_name Coords extends RefCounted` with constants `CHUNK_SIZE: int = 32`, `TILES_PER_CHUNK: int = 1024`, and static functions `floordiv(a: int, b: int) -> int`, `world_to_chunk(w: Vector2i) -> Vector2i`, `world_to_local(w: Vector2i) -> Vector2i`, `local_index(l: Vector2i) -> int`, `chunk_origin(c: Vector2i) -> Vector2i`.

Negative-coordinate floor division is where off-by-one bugs live, so this gets its own module and an exhaustive round-trip test.

- [x] **Step 1: Write the failing test**

```bash
cat > tests/test_coords.gd <<'GD'
extends GutTest


func test_chunk_size_is_32() -> void:
	assert_eq(Coords.CHUNK_SIZE, 32)
	assert_eq(Coords.TILES_PER_CHUNK, 1024)


func test_floordiv_rounds_toward_negative_infinity() -> void:
	assert_eq(Coords.floordiv(0, 32), 0)
	assert_eq(Coords.floordiv(31, 32), 0)
	assert_eq(Coords.floordiv(32, 32), 1)
	assert_eq(Coords.floordiv(63, 32), 1)
	assert_eq(Coords.floordiv(-1, 32), -1, "-1 belongs to chunk -1, not 0")
	assert_eq(Coords.floordiv(-32, 32), -1)
	assert_eq(Coords.floordiv(-33, 32), -2)


func test_world_to_chunk_handles_negative_quadrants() -> void:
	assert_eq(Coords.world_to_chunk(Vector2i(0, 0)), Vector2i(0, 0))
	assert_eq(Coords.world_to_chunk(Vector2i(31, 31)), Vector2i(0, 0))
	assert_eq(Coords.world_to_chunk(Vector2i(32, 32)), Vector2i(1, 1))
	assert_eq(Coords.world_to_chunk(Vector2i(-1, -1)), Vector2i(-1, -1))
	assert_eq(Coords.world_to_chunk(Vector2i(-32, -32)), Vector2i(-1, -1))
	assert_eq(Coords.world_to_chunk(Vector2i(-33, -33)), Vector2i(-2, -2))
	assert_eq(Coords.world_to_chunk(Vector2i(-1, 40)), Vector2i(-1, 1), "mixed signs")


func test_world_to_local_is_always_in_range() -> void:
	for w: int in range(-70, 70):
		var l: Vector2i = Coords.world_to_local(Vector2i(w, w))
		assert_between(l.x, 0, 31, "local x in range for world %d" % w)
		assert_between(l.y, 0, 31, "local y in range for world %d" % w)


func test_chunk_and_local_reconstruct_world_coordinate() -> void:
	# The invariant the whole tile-addressing scheme rests on.
	for wx: int in range(-70, 70):
		for wy: int in [-33, -1, 0, 31, 32, 65]:
			var w: Vector2i = Vector2i(wx, wy)
			var c: Vector2i = Coords.world_to_chunk(w)
			var l: Vector2i = Coords.world_to_local(w)
			assert_eq(
				Coords.chunk_origin(c) + l, w,
				"chunk_origin + local reconstructs %s" % w
			)


func test_local_index_is_row_major() -> void:
	assert_eq(Coords.local_index(Vector2i(0, 0)), 0)
	assert_eq(Coords.local_index(Vector2i(1, 0)), 1)
	assert_eq(Coords.local_index(Vector2i(0, 1)), 32)
	assert_eq(Coords.local_index(Vector2i(31, 31)), 1023)


func test_local_index_is_unique_across_the_chunk() -> void:
	var seen: Dictionary = {}
	for y: int in range(32):
		for x: int in range(32):
			var i: int = Coords.local_index(Vector2i(x, y))
			assert_false(seen.has(i), "index %d is not reused" % i)
			seen[i] = true
	assert_eq(seen.size(), 1024)
GD
```

- [x] **Step 2: Run the test to verify it fails**

Run: `./tools/run_tests.sh`
Expected: FAIL — `Identifier "Coords" not declared in the current scope`.

- [x] **Step 3: Implement Coords**

Integer floor division is used rather than `floori(float(a) / float(b))` because it is exact at every magnitude and involves no float round-trip.

```bash
mkdir -p src/core
cat > src/core/coords.gd <<'GD'
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
GD
rm -f src/core/placeholder.gd
```

- [x] **Step 4: Run the tests to verify they pass**

Run: `./tools/run_tests.sh`
Expected: PASS, 7 coords tests green.

- [x] **Step 5: Commit**

```bash
git add src/core/coords.gd tests/test_coords.gd
git rm -q --cached src/core/placeholder.gd 2>/dev/null || true
git add -A src/core
git commit -m "feat: add coordinate conversion with exact negative floor division"
```

- [x] **Step 6: Mark the task complete**

Tick this task's checkboxes and commit the progress, so the plan file itself
records what has been done:

```bash
python3 tools/mark_task_done.py 4
git add docs/superpowers/plans/2026-08-23-rp1-phase0-2-foundation-data-persistence.md
git commit -m "docs: mark Task 4 (Coordinate conversion) complete"
```


---

## Task 5: Chunk tile storage

**Files:**
- Create: `src/core/chunk.gd`
- Create: `tests/test_chunk.gd`

**Interfaces:**
- Consumes: `Coords.CHUNK_SIZE`, `Coords.TILES_PER_CHUNK`, `Coords.local_index`
- Produces: `class_name Chunk extends RefCounted`.
  - Constants: `U16_COLUMN_BYTES: int = 2048`, `U8_COLUMN_BYTES: int = 1024`, `PAYLOAD_BYTES: int = 8192`, `FLAG_WALKABLE: int = 1`, `FLAG_BLOCKS_LIGHT: int = 2`.
  - Properties: `coord: Vector2i`, `dirty: bool`, and the five columns `terrain_id`, `floor_id`, `object_id` (u16-packed) and `height`, `flags` (u8) — all `PackedByteArray`.
  - `_init(p_coord: Vector2i = Vector2i.ZERO)`.
  - Accessors taking a local `Vector2i`: `get_terrain/set_terrain`, `get_floor/set_floor`, `get_object/set_object`, `get_height/set_height`, `get_flags/set_flags`, each `-> int` / `-> void`; plus `is_walkable(l: Vector2i) -> bool`.
  - Every setter sets `dirty = true`.

- [x] **Step 1: Write the failing test**

```bash
cat > tests/test_chunk.gd <<'GD'
extends GutTest

var _c: Chunk


func before_each() -> void:
	_c = Chunk.new(Vector2i(2, -3))


func test_column_sizes_match_the_spec() -> void:
	assert_eq(_c.terrain_id.size(), 2048, "u16 column is 1024 * 2 bytes")
	assert_eq(_c.floor_id.size(), 2048)
	assert_eq(_c.object_id.size(), 2048)
	assert_eq(_c.height.size(), 1024, "u8 column is 1024 bytes")
	assert_eq(_c.flags.size(), 1024)
	assert_eq(Chunk.PAYLOAD_BYTES, 8192, "total uncompressed payload")


func test_new_chunk_is_zeroed_and_clean() -> void:
	assert_eq(_c.get_terrain(Vector2i(0, 0)), 0)
	assert_eq(_c.get_height(Vector2i(31, 31)), 0)
	assert_false(_c.dirty, "a freshly constructed chunk is not dirty")


func test_coord_is_stored() -> void:
	assert_eq(_c.coord, Vector2i(2, -3))


func test_terrain_round_trips_at_full_u16_range() -> void:
	_c.set_terrain(Vector2i(5, 7), 65535)
	assert_eq(_c.get_terrain(Vector2i(5, 7)), 65535, "u16 max survives")
	_c.set_terrain(Vector2i(0, 0), 1)
	assert_eq(_c.get_terrain(Vector2i(0, 0)), 1)


func test_columns_are_independent() -> void:
	var l: Vector2i = Vector2i(9, 9)
	_c.set_terrain(l, 11)
	_c.set_floor(l, 22)
	_c.set_object(l, 33)
	_c.set_height(l, 44)
	_c.set_flags(l, 55)
	assert_eq(_c.get_terrain(l), 11)
	assert_eq(_c.get_floor(l), 22)
	assert_eq(_c.get_object(l), 33)
	assert_eq(_c.get_height(l), 44)
	assert_eq(_c.get_flags(l), 55)


func test_neighbouring_tiles_do_not_alias() -> void:
	# Catches a wrong stride in the u16 columns, the most likely bug here.
	_c.set_terrain(Vector2i(0, 0), 4242)
	assert_eq(_c.get_terrain(Vector2i(1, 0)), 0, "adjacent tile untouched")
	assert_eq(_c.get_terrain(Vector2i(0, 1)), 0, "tile on next row untouched")


func test_every_tile_is_addressable() -> void:
	for y: int in range(32):
		for x: int in range(32):
			_c.set_terrain(Vector2i(x, y), (y * 32 + x) % 65536)
	for y: int in range(32):
		for x: int in range(32):
			assert_eq(_c.get_terrain(Vector2i(x, y)), (y * 32 + x) % 65536)


func test_setters_mark_the_chunk_dirty() -> void:
	assert_false(_c.dirty)
	_c.set_height(Vector2i(1, 1), 3)
	assert_true(_c.dirty, "writing a tile marks the chunk dirty")


func test_getters_do_not_mark_the_chunk_dirty() -> void:
	var _unused: int = _c.get_terrain(Vector2i(1, 1))
	assert_false(_c.dirty, "reading must not dirty the chunk")


func test_walkable_flag() -> void:
	var l: Vector2i = Vector2i(3, 4)
	assert_false(_c.is_walkable(l), "zeroed flags mean not walkable")
	_c.set_flags(l, Chunk.FLAG_WALKABLE)
	assert_true(_c.is_walkable(l))
	_c.set_flags(l, Chunk.FLAG_WALKABLE | Chunk.FLAG_BLOCKS_LIGHT)
	assert_true(_c.is_walkable(l), "walkable survives other flags being set")
GD
```

- [x] **Step 2: Run the test to verify it fails**

Run: `./tools/run_tests.sh`
Expected: FAIL — `Identifier "Chunk" not declared in the current scope`.

- [x] **Step 3: Implement Chunk**

```bash
cat > src/core/chunk.gd <<'GD'
class_name Chunk
extends RefCounted
## A 32x32 block of tiles, stored as five parallel byte columns.
##
## Columns are PackedByteArray rather than PackedInt32Array so that the
## in-memory representation IS the storage format: serialising a chunk is a
## buffer concatenation with no width conversion, and a chunk costs 8 KB
## rather than 20 KB.

const U16_COLUMN_BYTES: int = Coords.TILES_PER_CHUNK * 2
const U8_COLUMN_BYTES: int = Coords.TILES_PER_CHUNK
const PAYLOAD_BYTES: int = U16_COLUMN_BYTES * 3 + U8_COLUMN_BYTES * 2

const FLAG_WALKABLE: int = 1 << 0
const FLAG_BLOCKS_LIGHT: int = 1 << 1

var coord: Vector2i
var dirty: bool = false

var terrain_id: PackedByteArray
var floor_id: PackedByteArray
var object_id: PackedByteArray
var height: PackedByteArray
var flags: PackedByteArray


func _init(p_coord: Vector2i = Vector2i.ZERO) -> void:
	coord = p_coord
	terrain_id = _new_column(U16_COLUMN_BYTES)
	floor_id = _new_column(U16_COLUMN_BYTES)
	object_id = _new_column(U16_COLUMN_BYTES)
	height = _new_column(U8_COLUMN_BYTES)
	flags = _new_column(U8_COLUMN_BYTES)


static func _new_column(size: int) -> PackedByteArray:
	var c: PackedByteArray = PackedByteArray()
	c.resize(size)
	c.fill(0)
	return c


func get_terrain(l: Vector2i) -> int:
	return terrain_id.decode_u16(Coords.local_index(l) * 2)


func set_terrain(l: Vector2i, value: int) -> void:
	terrain_id.encode_u16(Coords.local_index(l) * 2, value)
	dirty = true


func get_floor(l: Vector2i) -> int:
	return floor_id.decode_u16(Coords.local_index(l) * 2)


func set_floor(l: Vector2i, value: int) -> void:
	floor_id.encode_u16(Coords.local_index(l) * 2, value)
	dirty = true


func get_object(l: Vector2i) -> int:
	return object_id.decode_u16(Coords.local_index(l) * 2)


func set_object(l: Vector2i, value: int) -> void:
	object_id.encode_u16(Coords.local_index(l) * 2, value)
	dirty = true


func get_height(l: Vector2i) -> int:
	return height[Coords.local_index(l)]


func set_height(l: Vector2i, value: int) -> void:
	height[Coords.local_index(l)] = value
	dirty = true


func get_flags(l: Vector2i) -> int:
	return flags[Coords.local_index(l)]


func set_flags(l: Vector2i, value: int) -> void:
	flags[Coords.local_index(l)] = value
	dirty = true


func is_walkable(l: Vector2i) -> bool:
	return (flags[Coords.local_index(l)] & FLAG_WALKABLE) != 0
GD
```

- [x] **Step 4: Run the tests to verify they pass**

Run: `./tools/run_tests.sh`
Expected: PASS, 10 chunk tests green.

- [x] **Step 5: Commit**

```bash
git add src/core/chunk.gd tests/test_chunk.gd
git commit -m "feat: add Chunk with five parallel byte columns"
```

- [x] **Step 6: Mark the task complete**

Tick this task's checkboxes and commit the progress, so the plan file itself
records what has been done:

```bash
python3 tools/mark_task_done.py 5
git add docs/superpowers/plans/2026-08-23-rp1-phase0-2-foundation-data-persistence.md
git commit -m "docs: mark Task 5 (Chunk tile storage) complete"
```


---

## Task 6: Entity store

**Files:**
- Create: `src/core/entity_store.gd`
- Create: `tests/test_entity_store.gd`

**Interfaces:**
- Consumes: nothing
- Produces: `class_name EntityStore extends RefCounted`.
  - Constants: `INVALID_ID: int = 0`, `FLAG_ACTIVE: int = 1`, `FLAG_PERSISTED: int = 2`.
  - `spawn(type_id: int, pos: Vector2, entity_flags: int = FLAG_ACTIVE | FLAG_PERSISTED) -> int` returns a new stable id.
  - `despawn(id: int) -> bool`; `has(id: int) -> bool`; `count() -> int`; `ids() -> PackedInt32Array` (live ids only).
  - `get_type_id(id: int) -> int`; `get_position(id: int) -> Vector2`; `set_position(id: int, pos: Vector2) -> void`; `get_facing(id: int) -> int`; `set_facing(id: int, facing: int) -> void`; `get_entity_flags(id: int) -> int`.
  - `row_count() -> int` and `restore_row(...)` for codecs; `next_id() -> int` and `set_next_id(v: int) -> void` for save/load.

Entities belong to a **zone**, not a chunk, so crossing a chunk boundary is a position update and nothing else. Slots are recycled through a free list, but **ids are never reused within a save**, so a dangling reference fails loudly instead of silently aliasing a different entity.

- [x] **Step 1: Write the failing test**

```bash
cat > tests/test_entity_store.gd <<'GD'
extends GutTest

var _s: EntityStore


func before_each() -> void:
	_s = EntityStore.new()


func test_new_store_is_empty() -> void:
	assert_eq(_s.count(), 0)
	assert_eq(_s.ids().size(), 0)


func test_spawn_returns_a_valid_id() -> void:
	var id: int = _s.spawn(7, Vector2(1.5, 2.5))
	assert_ne(id, EntityStore.INVALID_ID, "spawn never returns the invalid id")
	assert_true(_s.has(id))
	assert_eq(_s.count(), 1)


func test_spawn_stores_type_and_position() -> void:
	var id: int = _s.spawn(7, Vector2(1.5, 2.5))
	assert_eq(_s.get_type_id(id), 7)
	assert_almost_eq(_s.get_position(id).x, 1.5, 0.001)
	assert_almost_eq(_s.get_position(id).y, 2.5, 0.001)


func test_ids_are_unique() -> void:
	var seen: Dictionary = {}
	for i: int in range(100):
		var id: int = _s.spawn(1, Vector2.ZERO)
		assert_false(seen.has(id), "id %d issued only once" % id)
		seen[id] = true
	assert_eq(_s.count(), 100)


func test_despawn_removes_the_entity() -> void:
	var id: int = _s.spawn(3, Vector2.ZERO)
	assert_true(_s.despawn(id))
	assert_false(_s.has(id))
	assert_eq(_s.count(), 0)


func test_despawn_of_unknown_id_returns_false() -> void:
	assert_false(_s.despawn(9999))
	assert_false(_s.despawn(EntityStore.INVALID_ID))


func test_ids_are_never_reused_after_despawn() -> void:
	# A recycled id would let a stale reference silently address a
	# different entity. The slot is reused; the id is not.
	var first: int = _s.spawn(1, Vector2.ZERO)
	assert_true(_s.despawn(first))
	var second: int = _s.spawn(1, Vector2.ZERO)
	assert_ne(second, first, "id is not recycled")


func test_slot_is_recycled_so_rows_do_not_grow_without_bound() -> void:
	var a: int = _s.spawn(1, Vector2.ZERO)
	var rows_after_first: int = _s.row_count()
	assert_true(_s.despawn(a))
	var _b: int = _s.spawn(1, Vector2.ZERO)
	assert_eq(_s.row_count(), rows_after_first, "the freed slot was reused")


func test_position_can_be_updated() -> void:
	var id: int = _s.spawn(1, Vector2.ZERO)
	_s.set_position(id, Vector2(-12.25, 300.5))
	assert_almost_eq(_s.get_position(id).x, -12.25, 0.001)
	assert_almost_eq(_s.get_position(id).y, 300.5, 0.001)


func test_facing_round_trips() -> void:
	var id: int = _s.spawn(1, Vector2.ZERO)
	_s.set_facing(id, 5)
	assert_eq(_s.get_facing(id), 5)


func test_ids_lists_only_live_entities() -> void:
	var a: int = _s.spawn(1, Vector2.ZERO)
	var b: int = _s.spawn(1, Vector2.ZERO)
	assert_true(_s.despawn(a))
	var live: PackedInt32Array = _s.ids()
	assert_eq(live.size(), 1)
	assert_eq(live[0], b)


func test_next_id_is_preserved_across_save_and_load() -> void:
	# Loading a save must not restart id allocation, or new entities
	# would collide with saved ones.
	var _a: int = _s.spawn(1, Vector2.ZERO)
	var saved: int = _s.next_id()
	var fresh: EntityStore = EntityStore.new()
	fresh.set_next_id(saved)
	assert_eq(fresh.spawn(1, Vector2.ZERO), saved)
GD
```

- [x] **Step 2: Run the test to verify it fails**

Run: `./tools/run_tests.sh`
Expected: FAIL — `Identifier "EntityStore" not declared in the current scope`.

- [x] **Step 3: Implement EntityStore**

```bash
cat > src/core/entity_store.gd <<'GD'
class_name EntityStore
extends RefCounted
## Per-zone entity storage, struct-of-arrays.
##
## Mirrors the Chunk column layout so there is one serialisation pattern in
## the codebase rather than two. Entities belong to a zone rather than a
## chunk, so crossing a chunk boundary is a position update and nothing more.

const INVALID_ID: int = 0

const FLAG_ACTIVE: int = 1 << 0
const FLAG_PERSISTED: int = 1 << 1

var _id: PackedInt32Array = PackedInt32Array()
var _type_id: PackedInt32Array = PackedInt32Array()
var _x: PackedFloat32Array = PackedFloat32Array()
var _y: PackedFloat32Array = PackedFloat32Array()
var _facing: PackedByteArray = PackedByteArray()
var _flags: PackedByteArray = PackedByteArray()
## Offset into a side buffer for variable-length per-entity state.
## Unused in Stage 1, present so the save format does not change later.
var _blob_offset: PackedInt32Array = PackedInt32Array()

var _free_slots: PackedInt32Array = PackedInt32Array()
var _slot_by_id: Dictionary = {}
var _next_id: int = 1


func next_id() -> int:
	return _next_id


func set_next_id(value: int) -> void:
	_next_id = value


func count() -> int:
	return _slot_by_id.size()


func row_count() -> int:
	return _id.size()


func has(id: int) -> bool:
	return _slot_by_id.has(id)


func spawn(
	type_id: int,
	pos: Vector2,
	entity_flags: int = FLAG_ACTIVE | FLAG_PERSISTED
) -> int:
	var id: int = _next_id
	_next_id += 1

	var slot: int
	if _free_slots.is_empty():
		slot = _id.size()
		_id.append(id)
		_type_id.append(type_id)
		_x.append(pos.x)
		_y.append(pos.y)
		_facing.append(0)
		_flags.append(entity_flags)
		_blob_offset.append(0)
	else:
		slot = _free_slots[_free_slots.size() - 1]
		_free_slots.remove_at(_free_slots.size() - 1)
		_id[slot] = id
		_type_id[slot] = type_id
		_x[slot] = pos.x
		_y[slot] = pos.y
		_facing[slot] = 0
		_flags[slot] = entity_flags
		_blob_offset[slot] = 0

	_slot_by_id[id] = slot
	return id


func despawn(id: int) -> bool:
	if not _slot_by_id.has(id):
		return false
	var slot: int = _slot_by_id[id]
	_id[slot] = INVALID_ID
	_flags[slot] = 0
	_free_slots.append(slot)
	_slot_by_id.erase(id)
	return true


func ids() -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	for slot: int in range(_id.size()):
		if _id[slot] != INVALID_ID:
			out.append(_id[slot])
	return out


func get_type_id(id: int) -> int:
	return _type_id[_slot_by_id[id]]


func get_position(id: int) -> Vector2:
	var slot: int = _slot_by_id[id]
	return Vector2(_x[slot], _y[slot])


func set_position(id: int, pos: Vector2) -> void:
	var slot: int = _slot_by_id[id]
	_x[slot] = pos.x
	_y[slot] = pos.y


func get_facing(id: int) -> int:
	return _facing[_slot_by_id[id]]


func set_facing(id: int, facing: int) -> void:
	_facing[_slot_by_id[id]] = facing


func get_entity_flags(id: int) -> int:
	return _flags[_slot_by_id[id]]


## Codec support: rebuild a row verbatim during load.
func restore_row(
	id: int, type_id: int, pos: Vector2, facing: int, entity_flags: int, blob_offset: int
) -> void:
	var slot: int = _id.size()
	_id.append(id)
	_type_id.append(type_id)
	_x.append(pos.x)
	_y.append(pos.y)
	_facing.append(facing)
	_flags.append(entity_flags)
	_blob_offset.append(blob_offset)
	_slot_by_id[id] = slot
GD
```

- [x] **Step 4: Run the tests to verify they pass**

Run: `./tools/run_tests.sh`
Expected: PASS, 12 entity-store tests green.

- [x] **Step 5: Commit**

```bash
git add src/core/entity_store.gd tests/test_entity_store.gd
git commit -m "feat: add EntityStore with stable ids and slot recycling

Ids are never reused within a save so a stale reference fails loudly
rather than aliasing a different entity."
```

- [x] **Step 6: Mark the task complete**

Tick this task's checkboxes and commit the progress, so the plan file itself
records what has been done:

```bash
python3 tools/mark_task_done.py 6
git add docs/superpowers/plans/2026-08-23-rp1-phase0-2-foundation-data-persistence.md
git commit -m "docs: mark Task 6 (Entity store) complete"
```


---

## Task 7: Content schema validator

**Files:**
- Create: `src/core/schema_validator.gd`
- Create: `tests/test_schema_validator.gd`

**Interfaces:**
- Consumes: nothing
- Produces: `class_name SchemaValidator extends RefCounted` with `static validate(def: Dictionary, schema: Dictionary) -> PackedStringArray` returning one message per problem, empty when valid.

Schema shape (a plain JSON dictionary):

```json
{
  "category": "object",
  "required": { "id": "String", "category": "String", "display_name": "String", "sprite": "String" },
  "optional": { "blocks_movement": "bool", "tags": "Array", "y_offset": "int" }
}
```

This is what makes bulk agent-generated content safe to accept: without it, "add 20 furniture types" produces twenty files with three subtly different shapes, discovered only at runtime.

- [x] **Step 1: Write the failing test**

```bash
cat > tests/test_schema_validator.gd <<'GD'
extends GutTest

const SCHEMA: Dictionary = {
	"category": "object",
	"required": {"id": "String", "category": "String", "display_name": "String"},
	"optional": {"blocks_movement": "bool", "tags": "Array", "y_offset": "int"},
}


func _valid_def() -> Dictionary:
	return {"id": "oak_tree", "category": "object", "display_name": "Oak Tree"}


func test_valid_definition_has_no_errors() -> void:
	assert_eq(SchemaValidator.validate(_valid_def(), SCHEMA).size(), 0)


func test_valid_definition_with_optionals() -> void:
	var d: Dictionary = _valid_def()
	d["blocks_movement"] = true
	d["tags"] = ["natural", "tree"]
	d["y_offset"] = -16
	assert_eq(SchemaValidator.validate(d, SCHEMA).size(), 0)


func test_missing_required_field_is_an_error() -> void:
	var d: Dictionary = _valid_def()
	d.erase("display_name")
	var errs: PackedStringArray = SchemaValidator.validate(d, SCHEMA)
	assert_eq(errs.size(), 1)
	assert_string_contains(errs[0], "display_name")


func test_wrong_required_type_is_an_error() -> void:
	var d: Dictionary = _valid_def()
	d["display_name"] = 42
	var errs: PackedStringArray = SchemaValidator.validate(d, SCHEMA)
	assert_eq(errs.size(), 1)
	assert_string_contains(errs[0], "display_name")


func test_wrong_optional_type_is_an_error() -> void:
	var d: Dictionary = _valid_def()
	d["blocks_movement"] = "yes"
	assert_eq(SchemaValidator.validate(d, SCHEMA).size(), 1)


func test_unknown_field_is_an_error() -> void:
	# Catches typos like "block_movement", which would otherwise be
	# silently ignored and produce a walkable tree.
	var d: Dictionary = _valid_def()
	d["block_movement"] = true
	var errs: PackedStringArray = SchemaValidator.validate(d, SCHEMA)
	assert_eq(errs.size(), 1)
	assert_string_contains(errs[0], "block_movement")


func test_category_mismatch_is_an_error() -> void:
	var d: Dictionary = _valid_def()
	d["category"] = "creature"
	var errs: PackedStringArray = SchemaValidator.validate(d, SCHEMA)
	assert_eq(errs.size(), 1)
	assert_string_contains(errs[0], "category")


func test_json_numbers_parsed_as_float_satisfy_int_fields() -> void:
	# JSON.parse_string produces floats for every number. An int field
	# must accept 16.0 but reject 16.5.
	var d: Dictionary = _valid_def()
	d["y_offset"] = -16.0
	assert_eq(SchemaValidator.validate(d, SCHEMA).size(), 0, "-16.0 is a valid int")
	d["y_offset"] = -16.5
	assert_eq(SchemaValidator.validate(d, SCHEMA).size(), 1, "-16.5 is not an int")


func test_all_problems_are_reported_at_once() -> void:
	var d: Dictionary = {"id": "x", "category": "wrong", "bogus": 1}
	assert_eq(SchemaValidator.validate(d, SCHEMA).size(), 3, "missing, mismatch, unknown")
GD
```

- [x] **Step 2: Run the test to verify it fails**

Run: `./tools/run_tests.sh`
Expected: FAIL — `Identifier "SchemaValidator" not declared in the current scope`.

- [x] **Step 3: Implement SchemaValidator**

```bash
cat > src/core/schema_validator.gd <<'GD'
class_name SchemaValidator
extends RefCounted
## Validates a content definition against a category schema.
##
## Godot has no JSON Schema support, and the project does not need one: the
## rules that matter are required fields, field types, unknown fields, and a
## category match.

static func _type_matches(value: Variant, expected: String) -> bool:
	match expected:
		"String":
			return value is String
		"bool":
			return value is bool
		"int":
			# JSON.parse_string yields floats for every number, so an
			# integral float is a valid int; 16.5 is not.
			if value is int:
				return true
			return value is float and is_equal_approx(value, roundf(value))
		"float":
			return value is float or value is int
		"Array":
			return value is Array
		"Dictionary":
			return value is Dictionary
		_:
			return false


static func validate(def: Dictionary, schema: Dictionary) -> PackedStringArray:
	var errors: PackedStringArray = []
	var required: Dictionary = schema.get("required", {})
	var optional: Dictionary = schema.get("optional", {})
	var def_id: String = str(def.get("id", "<no id>"))

	for field: String in required:
		if not def.has(field):
			errors.append("%s: missing required field '%s'" % [def_id, field])
		elif not _type_matches(def[field], required[field]):
			errors.append(
				"%s: field '%s' must be %s" % [def_id, field, required[field]]
			)

	for field: String in optional:
		if def.has(field) and not _type_matches(def[field], optional[field]):
			errors.append("%s: field '%s' must be %s" % [def_id, field, optional[field]])

	for field: String in def:
		if not required.has(field) and not optional.has(field):
			errors.append("%s: unknown field '%s'" % [def_id, field])

	if schema.has("category") and def.get("category", "") != schema["category"]:
		errors.append(
			"%s: category must be '%s', got '%s'"
			% [def_id, schema["category"], str(def.get("category", ""))]
		)

	return errors
GD
```

- [x] **Step 4: Run the tests to verify they pass**

Run: `./tools/run_tests.sh`
Expected: PASS, 9 validator tests green.

- [x] **Step 5: Commit**

```bash
git add src/core/schema_validator.gd tests/test_schema_validator.gd
git commit -m "feat: add content schema validator

Rejects unknown fields, which is what catches typos like
'block_movement' that would otherwise silently produce a walkable tree."
```

- [x] **Step 6: Mark the task complete**

Tick this task's checkboxes and commit the progress, so the plan file itself
records what has been done:

```bash
python3 tools/mark_task_done.py 7
git add docs/superpowers/plans/2026-08-23-rp1-phase0-2-foundation-data-persistence.md
git commit -m "docs: mark Task 7 (Content schema validator) complete"
```


---

## Task 8: Content registry

**Files:**
- Create: `src/core/content_registry.gd`
- Create: `data/schema/terrain.json`, `data/schema/object.json`, `data/schema/creature.json`
- Create: `data/terrain/grass.json`, `data/terrain/water.json`, `data/object/oak_tree.json`, `data/creature/rabbit.json`
- Create: `tests/test_content_registry.gd`

**Interfaces:**
- Consumes: `SchemaValidator.validate`
- Produces: `class_name ContentRegistry extends RefCounted`.
  - `ID_UNKNOWN: int = 0` — reserved, never assigned to real content.
  - `load_from_dir(root: String) -> PackedStringArray` — loads every `data/<category>/*.json`, validating against `data/schema/<category>.json`; returns errors, empty on success.
  - `register(def: Dictionary) -> int`; `numeric_of(string_id: String) -> int` (returns `ID_UNKNOWN` if absent); `string_of(numeric_id: int) -> String`; `has_string(string_id: String) -> bool`; `def_of(numeric_id: int) -> Dictionary`; `all_string_ids() -> PackedStringArray`.
  - `register_placeholder(string_id: String) -> int` — allocates an id for content that no longer exists, retaining the original string. Used by the Task 12 unknown-id policy.
  - `is_placeholder(numeric_id: int) -> bool`.

Numeric ids are assigned in **sorted string order** so a given set of content always produces the same mapping, which makes tests deterministic.

- [x] **Step 1: Create the schemas and seed content**

```bash
mkdir -p data/schema data/terrain data/object data/creature

cat > data/schema/terrain.json <<'JSON'
{
  "category": "terrain",
  "required": {"id": "String", "category": "String", "display_name": "String", "sprite": "String"},
  "optional": {"walkable": "bool", "tags": "Array"}
}
JSON

cat > data/schema/object.json <<'JSON'
{
  "category": "object",
  "required": {"id": "String", "category": "String", "display_name": "String", "sprite": "String"},
  "optional": {
    "sprite_rect": "Array", "y_offset": "int", "blocks_movement": "bool",
    "blocks_light": "bool", "harvestable": "Dictionary", "tags": "Array"
  }
}
JSON

cat > data/schema/creature.json <<'JSON'
{
  "category": "creature",
  "required": {"id": "String", "category": "String", "display_name": "String", "sprite": "String"},
  "optional": {"wander_radius": "int", "flees_player": "bool", "tags": "Array"}
}
JSON

cat > data/terrain/grass.json <<'JSON'
{"id": "grass", "category": "terrain", "display_name": "Grass",
 "sprite": "res://assets/tiles/grass.png", "walkable": true, "tags": ["natural"]}
JSON

cat > data/terrain/water.json <<'JSON'
{"id": "water", "category": "terrain", "display_name": "Water",
 "sprite": "res://assets/tiles/water.png", "walkable": false, "tags": ["natural", "liquid"]}
JSON

cat > data/object/oak_tree.json <<'JSON'
{"id": "oak_tree", "category": "object", "display_name": "Oak Tree",
 "sprite": "res://assets/objects/oak_tree.png", "sprite_rect": [0, 0, 32, 48],
 "y_offset": -16, "blocks_movement": true, "blocks_light": true,
 "harvestable": {"item": "wood", "amount": [2, 4]}, "tags": ["natural", "flammable", "tree"]}
JSON

cat > data/creature/rabbit.json <<'JSON'
{"id": "rabbit", "category": "creature", "display_name": "Rabbit",
 "sprite": "res://assets/characters/rabbit.png", "wander_radius": 6,
 "flees_player": true, "tags": ["animal", "prey"]}
JSON
```

- [x] **Step 2: Write the failing test**

```bash
cat > tests/test_content_registry.gd <<'GD'
extends GutTest

var _r: ContentRegistry


func before_each() -> void:
	_r = ContentRegistry.new()


func test_loads_the_repository_data_directory_without_errors() -> void:
	var errs: PackedStringArray = _r.load_from_dir("res://data")
	assert_eq(errs.size(), 0, "shipped content validates: %s" % ", ".join(errs))
	assert_true(_r.has_string("grass"))
	assert_true(_r.has_string("oak_tree"))
	assert_true(_r.has_string("rabbit"))


func test_zero_is_reserved_for_unknown() -> void:
	var _e: PackedStringArray = _r.load_from_dir("res://data")
	for sid: String in _r.all_string_ids():
		assert_ne(_r.numeric_of(sid), ContentRegistry.ID_UNKNOWN,
			"real content never gets id 0")


func test_string_and_numeric_lookup_are_inverse() -> void:
	var _e: PackedStringArray = _r.load_from_dir("res://data")
	for sid: String in _r.all_string_ids():
		assert_eq(_r.string_of(_r.numeric_of(sid)), sid)


func test_unknown_string_maps_to_id_unknown() -> void:
	var _e: PackedStringArray = _r.load_from_dir("res://data")
	assert_eq(_r.numeric_of("no_such_thing"), ContentRegistry.ID_UNKNOWN)
	assert_false(_r.has_string("no_such_thing"))


func test_assignment_is_deterministic_across_loads() -> void:
	# Two registries built from the same data must agree, or a save
	# written by one would be misread by the other.
	var a: ContentRegistry = ContentRegistry.new()
	var b: ContentRegistry = ContentRegistry.new()
	var _e1: PackedStringArray = a.load_from_dir("res://data")
	var _e2: PackedStringArray = b.load_from_dir("res://data")
	for sid: String in a.all_string_ids():
		assert_eq(a.numeric_of(sid), b.numeric_of(sid), "id for %s is stable" % sid)


func test_definition_is_retrievable() -> void:
	var _e: PackedStringArray = _r.load_from_dir("res://data")
	var d: Dictionary = _r.def_of(_r.numeric_of("oak_tree"))
	assert_eq(d["display_name"], "Oak Tree")
	assert_true(d["blocks_movement"])


func test_malformed_json_is_reported_not_crashed() -> void:
	var dir: String = "user://bad_content"
	DirAccess.make_dir_recursive_absolute(dir.path_join("terrain"))
	DirAccess.make_dir_recursive_absolute(dir.path_join("schema"))
	var s: FileAccess = FileAccess.open(dir.path_join("schema/terrain.json"), FileAccess.WRITE)
	s.store_string('{"category":"terrain","required":{"id":"String","category":"String"},"optional":{}}')
	s.close()
	var f: FileAccess = FileAccess.open(dir.path_join("terrain/broken.json"), FileAccess.WRITE)
	f.store_string("{ this is not json")
	f.close()

	var errs: PackedStringArray = _r.load_from_dir(dir)
	assert_gt(errs.size(), 0, "malformed JSON produces an error rather than a crash")
	assert_string_contains(errs[0], "broken.json")


func test_schema_violation_is_reported() -> void:
	var dir: String = "user://bad_schema"
	DirAccess.make_dir_recursive_absolute(dir.path_join("terrain"))
	DirAccess.make_dir_recursive_absolute(dir.path_join("schema"))
	var s: FileAccess = FileAccess.open(dir.path_join("schema/terrain.json"), FileAccess.WRITE)
	s.store_string('{"category":"terrain","required":{"id":"String","category":"String","display_name":"String"},"optional":{}}')
	s.close()
	var f: FileAccess = FileAccess.open(dir.path_join("terrain/nodisplay.json"), FileAccess.WRITE)
	f.store_string('{"id":"x","category":"terrain"}')
	f.close()

	var errs: PackedStringArray = _r.load_from_dir(dir)
	assert_gt(errs.size(), 0)
	assert_string_contains(errs[0], "display_name")


func test_placeholder_retains_its_original_string() -> void:
	var _e: PackedStringArray = _r.load_from_dir("res://data")
	var id: int = _r.register_placeholder("removed_content")
	assert_ne(id, ContentRegistry.ID_UNKNOWN)
	assert_true(_r.is_placeholder(id))
	assert_eq(_r.string_of(id), "removed_content", "the original string survives")


func test_registering_the_same_placeholder_twice_returns_the_same_id() -> void:
	var _e: PackedStringArray = _r.load_from_dir("res://data")
	assert_eq(_r.register_placeholder("gone"), _r.register_placeholder("gone"))


func test_real_content_is_not_a_placeholder() -> void:
	var _e: PackedStringArray = _r.load_from_dir("res://data")
	assert_false(_r.is_placeholder(_r.numeric_of("grass")))
GD
```

- [x] **Step 3: Run the test to verify it fails**

Run: `./tools/run_tests.sh`
Expected: FAIL — `Identifier "ContentRegistry" not declared in the current scope`.

- [x] **Step 4: Implement ContentRegistry**

```bash
cat > src/core/content_registry.gd <<'GD'
class_name ContentRegistry
extends RefCounted
## Loads all game content from JSON and assigns numeric runtime ids.
##
## Numeric ids are assigned in sorted string order so the same content always
## produces the same mapping. Saves persist the string ids, not these
## numbers -- see IdMap.

const ID_UNKNOWN: int = 0
const CATEGORIES: PackedStringArray = ["terrain", "object", "creature"]

var _defs: Dictionary = {}          ## numeric_id -> Dictionary
var _numeric_by_string: Dictionary = {}
var _string_by_numeric: Dictionary = {}
var _placeholders: Dictionary = {}  ## numeric_id -> true
var _next_numeric: int = 1


func all_string_ids() -> PackedStringArray:
	var out: PackedStringArray = []
	for sid: String in _numeric_by_string:
		out.append(sid)
	out.sort()
	return out


func has_string(string_id: String) -> bool:
	return _numeric_by_string.has(string_id)


func numeric_of(string_id: String) -> int:
	return _numeric_by_string.get(string_id, ID_UNKNOWN)


func string_of(numeric_id: int) -> String:
	return _string_by_numeric.get(numeric_id, "")


func def_of(numeric_id: int) -> Dictionary:
	return _defs.get(numeric_id, {})


func is_placeholder(numeric_id: int) -> bool:
	return _placeholders.has(numeric_id)


func register(def: Dictionary) -> int:
	var string_id: String = str(def["id"])
	if _numeric_by_string.has(string_id):
		return _numeric_by_string[string_id]
	var numeric: int = _next_numeric
	_next_numeric += 1
	_numeric_by_string[string_id] = numeric
	_string_by_numeric[numeric] = string_id
	_defs[numeric] = def
	return numeric


## Allocates an id for content named in a save but absent from this build.
## The original string is retained so the save round-trips losslessly.
func register_placeholder(string_id: String) -> int:
	if _numeric_by_string.has(string_id):
		return _numeric_by_string[string_id]
	var numeric: int = register({
		"id": string_id,
		"category": "unknown",
		"display_name": "Unknown (%s)" % string_id,
		"sprite": "",
	})
	_placeholders[numeric] = true
	return numeric


func _read_json(path: String, errors: PackedStringArray) -> Variant:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		errors.append("%s: cannot open" % path)
		return null
	var text: String = f.get_as_text()
	f.close()
	# JSON.new().parse() rather than the static JSON.parse_string(): the
	# static helper pushes an engine-level error on malformed input, which
	# is noise in the log and fails the test that deliberately feeds it bad
	# JSON. The instance API returns an error code quietly and carries the
	# message and line number, which makes a better report anyway.
	var json: JSON = JSON.new()
	var err: int = json.parse(text)
	if err != OK:
		errors.append(
			"%s: malformed JSON at line %d: %s"
			% [path, json.get_error_line(), json.get_error_message()]
		)
		return null
	return json.data


func load_from_dir(root: String) -> PackedStringArray:
	var errors: PackedStringArray = []

	for category: String in CATEGORIES:
		var cat_dir: String = root.path_join(category)
		if not DirAccess.dir_exists_absolute(cat_dir):
			continue

		var schema_path: String = root.path_join("schema").path_join("%s.json" % category)
		var schema: Variant = _read_json(schema_path, errors)
		if not (schema is Dictionary):
			errors.append("%s: missing or invalid schema" % schema_path)
			continue

		# Sorted so numeric assignment is deterministic.
		var files: PackedStringArray = DirAccess.get_files_at(cat_dir)
		files.sort()
		for file_name: String in files:
			if not file_name.ends_with(".json"):
				continue
			var path: String = cat_dir.path_join(file_name)
			var def: Variant = _read_json(path, errors)
			if not (def is Dictionary):
				continue
			var problems: PackedStringArray = SchemaValidator.validate(def, schema)
			if problems.size() > 0:
				for p: String in problems:
					errors.append("%s: %s" % [path, p])
				continue
			var _numeric: int = register(def)

	return errors
GD
```

- [x] **Step 5: Run the tests to verify they pass**

Run: `./tools/run_tests.sh`
Expected: PASS, 11 registry tests green.

- [x] **Step 6: Commit**

```bash
git add src/core/content_registry.gd data tests/test_content_registry.gd
git commit -m "feat: add ContentRegistry with schema-validated JSON loading

Numeric ids are assigned in sorted string order so two registries built
from the same data always agree."
```

- [x] **Step 7: Mark the task complete**

Tick this task's checkboxes and commit the progress, so the plan file itself
records what has been done:

```bash
python3 tools/mark_task_done.py 8
git add docs/superpowers/plans/2026-08-23-rp1-phase0-2-foundation-data-persistence.md
git commit -m "docs: mark Task 8 (Content registry) complete"
```


---

## Task 9: Zone

**Files:**
- Create: `src/core/zone.gd`
- Create: `tests/test_zone.gd`

**Interfaces:**
- Consumes: `Coords`, `Chunk`, `EntityStore`
- Produces: `class_name Zone extends RefCounted`.
  - Properties: `id: String`, `display_name: String`, `size_tiles: Vector2i`, `biome: String`, `generation_seed: int`, `entities: EntityStore`.
  - `_init(p_id: String = "", p_size: Vector2i = Vector2i(128, 128))`.
  - `get_chunk(c: Vector2i, create: bool = false) -> Chunk` (null when absent and `create` is false).
  - `chunk_coords() -> Array[Vector2i]` sorted for determinism.
  - Tile access by **absolute world coordinate**: `get_terrain(w) -> int`, `set_terrain(w, v) -> void`, and the same for `floor`, `object`, `height`, `flags`; `is_walkable(w: Vector2i) -> bool`.
  - `in_bounds(w: Vector2i) -> bool`.
  - `dirty_chunk_coords() -> Array[Vector2i]`; `clear_dirty() -> void`.

- [x] **Step 1: Write the failing test**

```bash
cat > tests/test_zone.gd <<'GD'
extends GutTest

var _z: Zone


func before_each() -> void:
	_z = Zone.new("home", Vector2i(128, 128))


func test_metadata_is_stored() -> void:
	assert_eq(_z.id, "home")
	assert_eq(_z.size_tiles, Vector2i(128, 128))
	assert_not_null(_z.entities)


func test_chunks_are_created_lazily() -> void:
	assert_null(_z.get_chunk(Vector2i(0, 0)), "no chunk until asked to create one")
	assert_not_null(_z.get_chunk(Vector2i(0, 0), true))
	assert_not_null(_z.get_chunk(Vector2i(0, 0)), "created chunk is retained")


func test_writing_a_tile_creates_its_chunk() -> void:
	_z.set_terrain(Vector2i(100, 100), 5)
	assert_not_null(_z.get_chunk(Vector2i(3, 3)), "tile 100,100 lives in chunk 3,3")


func test_tile_access_by_world_coordinate() -> void:
	_z.set_terrain(Vector2i(40, 70), 9)
	assert_eq(_z.get_terrain(Vector2i(40, 70)), 9)


func test_reading_an_unwritten_tile_returns_zero_without_allocating() -> void:
	assert_eq(_z.get_terrain(Vector2i(64, 64)), 0)
	assert_null(_z.get_chunk(Vector2i(2, 2)), "reads must not allocate chunks")


func test_tiles_across_a_chunk_boundary_are_distinct() -> void:
	# The classic off-by-one: 31 and 32 are adjacent tiles in different chunks.
	_z.set_terrain(Vector2i(31, 0), 111)
	_z.set_terrain(Vector2i(32, 0), 222)
	assert_eq(_z.get_terrain(Vector2i(31, 0)), 111)
	assert_eq(_z.get_terrain(Vector2i(32, 0)), 222)
	assert_eq(_z.get_chunk(Vector2i(0, 0)).get_terrain(Vector2i(31, 0)), 111)
	assert_eq(_z.get_chunk(Vector2i(1, 0)).get_terrain(Vector2i(0, 0)), 222)


func test_negative_world_coordinates_work() -> void:
	_z.set_terrain(Vector2i(-1, -1), 77)
	assert_eq(_z.get_terrain(Vector2i(-1, -1)), 77)
	assert_eq(_z.get_chunk(Vector2i(-1, -1)).get_terrain(Vector2i(31, 31)), 77)


func test_all_five_columns_are_addressable_by_world_coordinate() -> void:
	var w: Vector2i = Vector2i(45, 45)
	_z.set_terrain(w, 1)
	_z.set_floor(w, 2)
	_z.set_object(w, 3)
	_z.set_height(w, 4)
	_z.set_flags(w, Chunk.FLAG_WALKABLE)
	assert_eq(_z.get_terrain(w), 1)
	assert_eq(_z.get_floor(w), 2)
	assert_eq(_z.get_object(w), 3)
	assert_eq(_z.get_height(w), 4)
	assert_true(_z.is_walkable(w))


func test_in_bounds() -> void:
	assert_true(_z.in_bounds(Vector2i(0, 0)))
	assert_true(_z.in_bounds(Vector2i(127, 127)))
	assert_false(_z.in_bounds(Vector2i(128, 0)))
	assert_false(_z.in_bounds(Vector2i(-1, 0)))


func test_dirty_tracking() -> void:
	assert_eq(_z.dirty_chunk_coords().size(), 0)
	_z.set_terrain(Vector2i(0, 0), 1)
	_z.set_terrain(Vector2i(64, 0), 1)
	assert_eq(_z.dirty_chunk_coords().size(), 2, "two chunks touched")
	_z.clear_dirty()
	assert_eq(_z.dirty_chunk_coords().size(), 0)


func test_chunk_coords_are_sorted_for_determinism() -> void:
	var _a: Chunk = _z.get_chunk(Vector2i(2, 1), true)
	var _b: Chunk = _z.get_chunk(Vector2i(0, 0), true)
	var _c: Chunk = _z.get_chunk(Vector2i(1, 0), true)
	assert_eq(
		_z.chunk_coords(),
		[Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 1)] as Array[Vector2i]
	)


func test_fifty_thousand_writes_read_back_correctly() -> void:
	# Scale check for the persistence round-trip in Task 13.
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 12345
	var expected: Dictionary = {}
	for i: int in range(50000):
		var w: Vector2i = Vector2i(rng.randi_range(0, 127), rng.randi_range(0, 127))
		var v: int = rng.randi_range(0, 65535)
		_z.set_terrain(w, v)
		expected[w] = v
	for w: Vector2i in expected:
		assert_eq(_z.get_terrain(w), expected[w])
GD
```

- [x] **Step 2: Run the test to verify it fails**

Run: `./tools/run_tests.sh`
Expected: FAIL — `Identifier "Zone" not declared in the current scope`.

- [x] **Step 3: Implement Zone**

```bash
cat > src/core/zone.gd <<'GD'
class_name Zone
extends RefCounted
## A bounded map: chunks of tiles plus the entities standing on them.
##
## Tile access is by absolute world coordinate; the zone resolves the chunk.
## Reads never allocate, so probing an empty region cannot balloon memory.

var id: String
var display_name: String
var size_tiles: Vector2i
var biome: String = "temperate"
var generation_seed: int = 0
var entities: EntityStore

var _chunks: Dictionary = {}  ## Vector2i -> Chunk


func _init(p_id: String = "", p_size: Vector2i = Vector2i(128, 128)) -> void:
	id = p_id
	display_name = p_id
	size_tiles = p_size
	entities = EntityStore.new()


func get_chunk(c: Vector2i, create: bool = false) -> Chunk:
	if _chunks.has(c):
		return _chunks[c]
	if not create:
		return null
	var chunk: Chunk = Chunk.new(c)
	_chunks[c] = chunk
	return chunk


func chunk_coords() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for c: Vector2i in _chunks:
		out.append(c)
	out.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.y < b.y if a.y != b.y else a.x < b.x)
	return out


func in_bounds(w: Vector2i) -> bool:
	return w.x >= 0 and w.y >= 0 and w.x < size_tiles.x and w.y < size_tiles.y


func dirty_chunk_coords() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for c: Vector2i in chunk_coords():
		if (_chunks[c] as Chunk).dirty:
			out.append(c)
	return out


func clear_dirty() -> void:
	for c: Vector2i in _chunks:
		(_chunks[c] as Chunk).dirty = false


func get_terrain(w: Vector2i) -> int:
	var c: Chunk = get_chunk(Coords.world_to_chunk(w))
	return 0 if c == null else c.get_terrain(Coords.world_to_local(w))


func set_terrain(w: Vector2i, value: int) -> void:
	get_chunk(Coords.world_to_chunk(w), true).set_terrain(Coords.world_to_local(w), value)


func get_floor(w: Vector2i) -> int:
	var c: Chunk = get_chunk(Coords.world_to_chunk(w))
	return 0 if c == null else c.get_floor(Coords.world_to_local(w))


func set_floor(w: Vector2i, value: int) -> void:
	get_chunk(Coords.world_to_chunk(w), true).set_floor(Coords.world_to_local(w), value)


func get_object(w: Vector2i) -> int:
	var c: Chunk = get_chunk(Coords.world_to_chunk(w))
	return 0 if c == null else c.get_object(Coords.world_to_local(w))


func set_object(w: Vector2i, value: int) -> void:
	get_chunk(Coords.world_to_chunk(w), true).set_object(Coords.world_to_local(w), value)


func get_height(w: Vector2i) -> int:
	var c: Chunk = get_chunk(Coords.world_to_chunk(w))
	return 0 if c == null else c.get_height(Coords.world_to_local(w))


func set_height(w: Vector2i, value: int) -> void:
	get_chunk(Coords.world_to_chunk(w), true).set_height(Coords.world_to_local(w), value)


func get_flags(w: Vector2i) -> int:
	var c: Chunk = get_chunk(Coords.world_to_chunk(w))
	return 0 if c == null else c.get_flags(Coords.world_to_local(w))


func set_flags(w: Vector2i, value: int) -> void:
	get_chunk(Coords.world_to_chunk(w), true).set_flags(Coords.world_to_local(w), value)


func is_walkable(w: Vector2i) -> bool:
	var c: Chunk = get_chunk(Coords.world_to_chunk(w))
	return false if c == null else c.is_walkable(Coords.world_to_local(w))
GD
```

- [x] **Step 4: Run the tests to verify they pass**

Run: `./tools/run_tests.sh`
Expected: PASS, 13 zone tests green.

- [x] **Step 5: Commit**

```bash
git add src/core/zone.gd tests/test_zone.gd
git commit -m "feat: add Zone with world-coordinate tile access and dirty tracking"
```

- [x] **Step 6: Mark the task complete**

Tick this task's checkboxes and commit the progress, so the plan file itself
records what has been done:

```bash
python3 tools/mark_task_done.py 9
git add docs/superpowers/plans/2026-08-23-rp1-phase0-2-foundation-data-persistence.md
git commit -m "docs: mark Task 9 (Zone) complete"
```


---

## Task 10: Chunk codec

**Files:**
- Create: `src/core/save/decode_result.gd`
- Create: `src/core/save/chunk_codec.gd`
- Create: `tests/test_chunk_codec.gd`

**Interfaces:**
- Consumes: `Chunk`
- Produces:
  - `class_name DecodeResult extends RefCounted` with `ok: bool`, `error: String`, `value: Variant`, and statics `success(v: Variant) -> DecodeResult`, `failure(msg: String) -> DecodeResult`.
  - `class_name ChunkCodec extends RefCounted` with `FORMAT_VERSION: int = 1`, `HEADER_BYTES: int = 24`, `COMPRESSION_NONE: int = 0`, `COMPRESSION_ZSTD: int = 1`; `static encode(chunk: Chunk) -> PackedByteArray`; `static decode(bytes: PackedByteArray) -> DecodeResult` (`value` is a `Chunk`); `static peek_version(bytes: PackedByteArray) -> int` (`-1` on bad magic).

Header layout, all little-endian, **outside** the compressed region:

| Offset | Field | Size |
|---|---|---|
| 0 | magic `RP1C` | 4 |
| 4 | `format_version` u32 | 4 |
| 8 | `chunk_x` s32 | 4 |
| 12 | `chunk_y` s32 | 4 |
| 16 | `payload_size` u32 (uncompressed) | 4 |
| 20 | `compression` u8 | 1 |
| 21 | reserved | 3 |
| 24 | payload | rest |

Keeping the header plaintext is what lets a loader read the version and decide how to parse **before** decompressing. `FileAccess.open_compressed()` would bury it inside the compressed stream.

- [x] **Step 1: Write the failing test**

```bash
cat > tests/test_chunk_codec.gd <<'GD'
extends GutTest


func _sample_chunk() -> Chunk:
	var c: Chunk = Chunk.new(Vector2i(-3, 7))
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 99
	for y: int in range(32):
		for x: int in range(32):
			var l: Vector2i = Vector2i(x, y)
			c.set_terrain(l, rng.randi_range(0, 65535))
			c.set_object(l, rng.randi_range(0, 300))
			c.set_height(l, rng.randi_range(0, 255))
			c.set_flags(l, rng.randi_range(0, 3))
	return c


func test_header_is_readable_without_decompressing() -> void:
	# The entire reason the header sits outside the compressed payload.
	var bytes: PackedByteArray = ChunkCodec.encode(_sample_chunk())
	assert_eq(bytes.decode_u8(0), 0x52, "R")
	assert_eq(bytes.decode_u8(1), 0x50, "P")
	assert_eq(bytes.decode_u8(2), 0x31, "1")
	assert_eq(bytes.decode_u8(3), 0x43, "C")
	assert_eq(bytes.decode_u32(4), ChunkCodec.FORMAT_VERSION)
	assert_eq(bytes.decode_s32(8), -3, "negative chunk x survives")
	assert_eq(bytes.decode_s32(12), 7)
	assert_eq(bytes.decode_u32(16), Chunk.PAYLOAD_BYTES)


func test_peek_version_does_not_decompress() -> void:
	var bytes: PackedByteArray = ChunkCodec.encode(_sample_chunk())
	assert_eq(ChunkCodec.peek_version(bytes), ChunkCodec.FORMAT_VERSION)


func test_round_trip_preserves_every_tile() -> void:
	var original: Chunk = _sample_chunk()
	var result: DecodeResult = ChunkCodec.decode(ChunkCodec.encode(original))
	assert_true(result.ok, "decode succeeded: %s" % result.error)
	var back: Chunk = result.value
	assert_eq(back.coord, original.coord)
	for y: int in range(32):
		for x: int in range(32):
			var l: Vector2i = Vector2i(x, y)
			assert_eq(back.get_terrain(l), original.get_terrain(l))
			assert_eq(back.get_object(l), original.get_object(l))
			assert_eq(back.get_height(l), original.get_height(l))
			assert_eq(back.get_flags(l), original.get_flags(l))


func test_columns_round_trip_byte_identical() -> void:
	var original: Chunk = _sample_chunk()
	var back: Chunk = ChunkCodec.decode(ChunkCodec.encode(original)).value
	assert_eq(back.terrain_id, original.terrain_id)
	assert_eq(back.floor_id, original.floor_id)
	assert_eq(back.object_id, original.object_id)
	assert_eq(back.height, original.height)
	assert_eq(back.flags, original.flags)


func test_decoded_chunk_is_not_dirty() -> void:
	# A chunk just read from disk matches disk, so saving it again is waste.
	var back: Chunk = ChunkCodec.decode(ChunkCodec.encode(_sample_chunk())).value
	assert_false(back.dirty)


func test_compression_actually_shrinks_repetitive_data() -> void:
	var c: Chunk = Chunk.new(Vector2i.ZERO)
	for y: int in range(32):
		for x: int in range(32):
			c.set_terrain(Vector2i(x, y), 1)
	var bytes: PackedByteArray = ChunkCodec.encode(c)
	assert_lt(bytes.size(), 1024, "a uniform chunk compresses far below 8 KB")


func test_bad_magic_is_rejected() -> void:
	var bytes: PackedByteArray = ChunkCodec.encode(_sample_chunk())
	bytes.encode_u8(0, 0x00)
	var result: DecodeResult = ChunkCodec.decode(bytes)
	assert_false(result.ok)
	assert_string_contains(result.error, "magic")
	assert_eq(ChunkCodec.peek_version(bytes), -1)


func test_truncated_file_fails_gracefully() -> void:
	# Power loss mid-write must produce an error, never a crash or a
	# silently half-populated chunk.
	var bytes: PackedByteArray = ChunkCodec.encode(_sample_chunk())
	var truncated: PackedByteArray = bytes.slice(0, bytes.size() / 2)
	var result: DecodeResult = ChunkCodec.decode(truncated)
	assert_false(result.ok, "truncated payload is rejected")
	assert_ne(result.error, "")


func test_header_only_file_fails_gracefully() -> void:
	var bytes: PackedByteArray = ChunkCodec.encode(_sample_chunk())
	assert_false(ChunkCodec.decode(bytes.slice(0, 24)).ok)


func test_empty_buffer_fails_gracefully() -> void:
	assert_false(ChunkCodec.decode(PackedByteArray()).ok)


func test_future_version_is_rejected_with_a_clear_message() -> void:
	var bytes: PackedByteArray = ChunkCodec.encode(_sample_chunk())
	bytes.encode_u32(4, 999)
	var result: DecodeResult = ChunkCodec.decode(bytes)
	assert_false(result.ok)
	assert_string_contains(result.error, "version")
GD
```

- [x] **Step 2: Run the test to verify it fails**

Run: `./tools/run_tests.sh`
Expected: FAIL — `Identifier "ChunkCodec" not declared in the current scope`.

- [x] **Step 3: Implement DecodeResult and ChunkCodec**

```bash
mkdir -p src/core/save

cat > src/core/save/decode_result.gd <<'GD'
class_name DecodeResult
extends RefCounted
## Typed success/failure for codecs. Decoding untrusted bytes must never
## crash, so every codec returns one of these rather than pushing an error.

var ok: bool = false
var error: String = ""
var value: Variant = null


static func success(v: Variant) -> DecodeResult:
	var r: DecodeResult = DecodeResult.new()
	r.ok = true
	r.value = v
	return r


static func failure(msg: String) -> DecodeResult:
	var r: DecodeResult = DecodeResult.new()
	r.ok = false
	r.error = msg
	return r
GD

cat > src/core/save/chunk_codec.gd <<'GD'
class_name ChunkCodec
extends RefCounted
## Chunk <-> bytes.
##
## The header is plaintext and sits OUTSIDE the compressed payload, so the
## format version can be read before choosing a parse strategy.
## FileAccess.open_compressed() would bury the version inside the compressed
## stream, making it unreadable until after a guess had already been made.

const FORMAT_VERSION: int = 1
const HEADER_BYTES: int = 24

const COMPRESSION_NONE: int = 0
const COMPRESSION_ZSTD: int = 1

const MAGIC_0: int = 0x52  # R
const MAGIC_1: int = 0x50  # P
const MAGIC_2: int = 0x31  # 1
const MAGIC_3: int = 0x43  # C

const OFF_VERSION: int = 4
const OFF_CHUNK_X: int = 8
const OFF_CHUNK_Y: int = 12
const OFF_PAYLOAD_SIZE: int = 16
const OFF_COMPRESSION: int = 20


static func _has_magic(bytes: PackedByteArray) -> bool:
	if bytes.size() < HEADER_BYTES:
		return false
	return (
		bytes.decode_u8(0) == MAGIC_0
		and bytes.decode_u8(1) == MAGIC_1
		and bytes.decode_u8(2) == MAGIC_2
		and bytes.decode_u8(3) == MAGIC_3
	)


static func peek_version(bytes: PackedByteArray) -> int:
	return bytes.decode_u32(OFF_VERSION) if _has_magic(bytes) else -1


static func encode(chunk: Chunk) -> PackedByteArray:
	var payload: PackedByteArray = PackedByteArray()
	payload.append_array(chunk.terrain_id)
	payload.append_array(chunk.floor_id)
	payload.append_array(chunk.object_id)
	payload.append_array(chunk.height)
	payload.append_array(chunk.flags)

	var compressed: PackedByteArray = payload.compress(FileAccess.COMPRESSION_ZSTD)

	var out: PackedByteArray = PackedByteArray()
	out.resize(HEADER_BYTES)
	out.fill(0)
	out.encode_u8(0, MAGIC_0)
	out.encode_u8(1, MAGIC_1)
	out.encode_u8(2, MAGIC_2)
	out.encode_u8(3, MAGIC_3)
	out.encode_u32(OFF_VERSION, FORMAT_VERSION)
	out.encode_s32(OFF_CHUNK_X, chunk.coord.x)
	out.encode_s32(OFF_CHUNK_Y, chunk.coord.y)
	out.encode_u32(OFF_PAYLOAD_SIZE, payload.size())
	out.encode_u8(OFF_COMPRESSION, COMPRESSION_ZSTD)
	out.append_array(compressed)
	return out


static func decode(bytes: PackedByteArray) -> DecodeResult:
	if bytes.size() < HEADER_BYTES:
		return DecodeResult.failure("chunk: file shorter than header (%d bytes)" % bytes.size())
	if not _has_magic(bytes):
		return DecodeResult.failure("chunk: bad magic, not an RP1C file")

	var version: int = bytes.decode_u32(OFF_VERSION)
	if version > FORMAT_VERSION:
		return DecodeResult.failure(
			"chunk: format version %d is newer than supported version %d"
			% [version, FORMAT_VERSION]
		)

	var payload_size: int = bytes.decode_u32(OFF_PAYLOAD_SIZE)
	if payload_size != Chunk.PAYLOAD_BYTES:
		return DecodeResult.failure(
			"chunk: payload size %d, expected %d" % [payload_size, Chunk.PAYLOAD_BYTES]
		)

	var body: PackedByteArray = bytes.slice(HEADER_BYTES)
	if body.is_empty():
		# decompress() pushes an engine error on a zero-length buffer, and a
		# header with no payload is detectably corrupt without asking it.
		return DecodeResult.failure("chunk: header present but payload is empty (truncated?)")

	var payload: PackedByteArray
	match bytes.decode_u8(OFF_COMPRESSION):
		COMPRESSION_NONE:
			payload = body
		COMPRESSION_ZSTD:
			payload = body.decompress(payload_size, FileAccess.COMPRESSION_ZSTD)
		_:
			return DecodeResult.failure("chunk: unknown compression mode")

	if payload.size() != payload_size:
		# decompress() returns an empty array on a truncated stream.
		return DecodeResult.failure(
			"chunk: payload decompressed to %d bytes, expected %d (file truncated?)"
			% [payload.size(), payload_size]
		)

	var chunk: Chunk = Chunk.new(
		Vector2i(bytes.decode_s32(OFF_CHUNK_X), bytes.decode_s32(OFF_CHUNK_Y))
	)
	var u16: int = Chunk.U16_COLUMN_BYTES
	var u8: int = Chunk.U8_COLUMN_BYTES
	var o: int = 0
	chunk.terrain_id = payload.slice(o, o + u16); o += u16
	chunk.floor_id = payload.slice(o, o + u16); o += u16
	chunk.object_id = payload.slice(o, o + u16); o += u16
	chunk.height = payload.slice(o, o + u8); o += u8
	chunk.flags = payload.slice(o, o + u8)
	# Freshly loaded data matches disk, so it is not pending a write.
	chunk.dirty = false
	return DecodeResult.success(chunk)
GD
```

- [x] **Step 4: Run the tests to verify they pass**

Run: `./tools/run_tests.sh`
Expected: PASS, 11 chunk-codec tests green.

- [x] **Step 5: Commit**

```bash
git add src/core/save/decode_result.gd src/core/save/chunk_codec.gd tests/test_chunk_codec.gd
git commit -m "feat: add chunk codec with plaintext header and ZSTD payload

The header sits outside the compressed region so the format version is
readable before a parse strategy is chosen. open_compressed() would
bury it inside the stream."
```

- [x] **Step 6: Mark the task complete**

Tick this task's checkboxes and commit the progress, so the plan file itself
records what has been done:

```bash
python3 tools/mark_task_done.py 10
git add docs/superpowers/plans/2026-08-23-rp1-phase0-2-foundation-data-persistence.md
git commit -m "docs: mark Task 10 (Chunk codec) complete"
```


---

## Task 11: Entity codec

**Files:**
- Create: `src/core/save/entity_codec.gd`
- Create: `tests/test_entity_codec.gd`

**Interfaces:**
- Consumes: `EntityStore`, `DecodeResult`
- Produces: `class_name EntityCodec extends RefCounted` with `FORMAT_VERSION: int = 1`, `HEADER_BYTES: int = 24`, `ROW_BYTES: int = 18`; `static encode(store: EntityStore) -> PackedByteArray`; `static decode(bytes: PackedByteArray) -> DecodeResult` (`value` is an `EntityStore`).

Header uses magic `RP1E`; offset 8 holds `entity_count` u32 and offset 12 holds `next_id` u32. Each row is 18 bytes: `id` u32, `type_id` u16, `x` f32, `y` f32, `facing` u8, `flags` u8, `blob_offset` u16.

Only live rows are written, so despawned slots do not accumulate in save files.

- [x] **Step 1: Write the failing test**

```bash
cat > tests/test_entity_codec.gd <<'GD'
extends GutTest


func _sample_store() -> EntityStore:
	var s: EntityStore = EntityStore.new()
	var a: int = s.spawn(3, Vector2(10.5, -20.25))
	s.set_facing(a, 4)
	var b: int = s.spawn(9, Vector2(0.0, 127.75))
	s.set_facing(b, 1)
	return s


func test_header_is_readable_without_decompressing() -> void:
	var bytes: PackedByteArray = EntityCodec.encode(_sample_store())
	assert_eq(bytes.decode_u8(0), 0x52)
	assert_eq(bytes.decode_u8(3), 0x45, "E for entities")
	assert_eq(bytes.decode_u32(4), EntityCodec.FORMAT_VERSION)
	assert_eq(bytes.decode_u32(8), 2, "entity count")


func test_round_trip_preserves_entities() -> void:
	var original: EntityStore = _sample_store()
	var result: DecodeResult = EntityCodec.decode(EntityCodec.encode(original))
	assert_true(result.ok, "decode succeeded: %s" % result.error)
	var back: EntityStore = result.value
	assert_eq(back.count(), original.count())
	for id: int in original.ids():
		assert_true(back.has(id), "entity %d survived" % id)
		assert_eq(back.get_type_id(id), original.get_type_id(id))
		assert_eq(back.get_facing(id), original.get_facing(id))
		assert_almost_eq(back.get_position(id).x, original.get_position(id).x, 0.001)
		assert_almost_eq(back.get_position(id).y, original.get_position(id).y, 0.001)


func test_next_id_survives_the_round_trip() -> void:
	# Without this, a reloaded world reissues ids that saved entities hold.
	var original: EntityStore = _sample_store()
	var back: EntityStore = EntityCodec.decode(EntityCodec.encode(original)).value
	assert_eq(back.next_id(), original.next_id())
	assert_ne(back.spawn(1, Vector2.ZERO), original.ids()[0])


func test_despawned_entities_are_not_written() -> void:
	var s: EntityStore = _sample_store()
	assert_true(s.despawn(s.ids()[0]))
	var bytes: PackedByteArray = EntityCodec.encode(s)
	assert_eq(bytes.decode_u32(8), 1, "only the live entity is written")
	assert_eq((EntityCodec.decode(bytes).value as EntityStore).count(), 1)


func test_empty_store_round_trips() -> void:
	var result: DecodeResult = EntityCodec.decode(EntityCodec.encode(EntityStore.new()))
	assert_true(result.ok)
	assert_eq((result.value as EntityStore).count(), 0)


func test_bad_magic_is_rejected() -> void:
	var bytes: PackedByteArray = EntityCodec.encode(_sample_store())
	bytes.encode_u8(3, 0x43)  # "C" -- a chunk file, not an entity file
	var result: DecodeResult = EntityCodec.decode(bytes)
	assert_false(result.ok)
	assert_string_contains(result.error, "magic")


func test_truncated_file_fails_gracefully() -> void:
	var bytes: PackedByteArray = EntityCodec.encode(_sample_store())
	assert_false(EntityCodec.decode(bytes.slice(0, bytes.size() - 5)).ok)


func test_count_larger_than_payload_is_rejected() -> void:
	# A corrupted count must not cause an out-of-bounds read.
	var bytes: PackedByteArray = EntityCodec.encode(_sample_store())
	bytes.encode_u32(8, 100000)
	assert_false(EntityCodec.decode(bytes).ok)
GD
```

- [x] **Step 2: Run the test to verify it fails**

Run: `./tools/run_tests.sh`
Expected: FAIL — `Identifier "EntityCodec" not declared in the current scope`.

- [x] **Step 3: Implement EntityCodec**

```bash
cat > src/core/save/entity_codec.gd <<'GD'
class_name EntityCodec
extends RefCounted
## EntityStore <-> bytes, using the same plaintext-header pattern as
## ChunkCodec. Only live rows are written, so despawned slots do not
## accumulate in save files.

const FORMAT_VERSION: int = 1
const HEADER_BYTES: int = 24
const ROW_BYTES: int = 18

const MAGIC_0: int = 0x52  # R
const MAGIC_1: int = 0x50  # P
const MAGIC_2: int = 0x31  # 1
const MAGIC_3: int = 0x45  # E

const OFF_VERSION: int = 4
const OFF_COUNT: int = 8
const OFF_NEXT_ID: int = 12


static func _has_magic(bytes: PackedByteArray) -> bool:
	if bytes.size() < HEADER_BYTES:
		return false
	return (
		bytes.decode_u8(0) == MAGIC_0
		and bytes.decode_u8(1) == MAGIC_1
		and bytes.decode_u8(2) == MAGIC_2
		and bytes.decode_u8(3) == MAGIC_3
	)


static func encode(store: EntityStore) -> PackedByteArray:
	var live: PackedInt32Array = store.ids()

	var rows: PackedByteArray = PackedByteArray()
	rows.resize(live.size() * ROW_BYTES)
	rows.fill(0)
	var o: int = 0
	for id: int in live:
		rows.encode_u32(o, id)
		rows.encode_u16(o + 4, store.get_type_id(id))
		rows.encode_float(o + 6, store.get_position(id).x)
		rows.encode_float(o + 10, store.get_position(id).y)
		rows.encode_u8(o + 14, store.get_facing(id))
		rows.encode_u8(o + 15, store.get_entity_flags(id))
		rows.encode_u16(o + 16, 0)  # blob_offset, reserved
		o += ROW_BYTES

	var out: PackedByteArray = PackedByteArray()
	out.resize(HEADER_BYTES)
	out.fill(0)
	out.encode_u8(0, MAGIC_0)
	out.encode_u8(1, MAGIC_1)
	out.encode_u8(2, MAGIC_2)
	out.encode_u8(3, MAGIC_3)
	out.encode_u32(OFF_VERSION, FORMAT_VERSION)
	out.encode_u32(OFF_COUNT, live.size())
	out.encode_u32(OFF_NEXT_ID, store.next_id())
	out.append_array(rows)
	return out


static func decode(bytes: PackedByteArray) -> DecodeResult:
	if bytes.size() < HEADER_BYTES:
		return DecodeResult.failure("entities: file shorter than header")
	if not _has_magic(bytes):
		return DecodeResult.failure("entities: bad magic, not an RP1E file")

	var version: int = bytes.decode_u32(OFF_VERSION)
	if version > FORMAT_VERSION:
		return DecodeResult.failure(
			"entities: format version %d is newer than supported version %d"
			% [version, FORMAT_VERSION]
		)

	var count: int = bytes.decode_u32(OFF_COUNT)
	var expected: int = HEADER_BYTES + count * ROW_BYTES
	if bytes.size() != expected:
		return DecodeResult.failure(
			"entities: file is %d bytes, expected %d for %d entities (truncated or corrupt count?)"
			% [bytes.size(), expected, count]
		)

	var store: EntityStore = EntityStore.new()
	var o: int = HEADER_BYTES
	for i: int in range(count):
		store.restore_row(
			bytes.decode_u32(o),
			bytes.decode_u16(o + 4),
			Vector2(bytes.decode_float(o + 6), bytes.decode_float(o + 10)),
			bytes.decode_u8(o + 14),
			bytes.decode_u8(o + 15),
			bytes.decode_u16(o + 16),
		)
		o += ROW_BYTES

	store.set_next_id(bytes.decode_u32(OFF_NEXT_ID))
	return DecodeResult.success(store)
GD
```

- [x] **Step 4: Run the tests to verify they pass**

Run: `./tools/run_tests.sh`
Expected: PASS, 8 entity-codec tests green.

- [x] **Step 5: Commit**

```bash
git add src/core/save/entity_codec.gd tests/test_entity_codec.gd
git commit -m "feat: add entity codec preserving next_id across save and load"
```

- [x] **Step 6: Mark the task complete**

Tick this task's checkboxes and commit the progress, so the plan file itself
records what has been done:

```bash
python3 tools/mark_task_done.py 11
git add docs/superpowers/plans/2026-08-23-rp1-phase0-2-foundation-data-persistence.md
git commit -m "docs: mark Task 11 (Entity codec) complete"
```


---

## Task 12: Id map and the unknown-content policy

**Files:**
- Create: `src/core/save/id_map.gd`
- Create: `tests/test_id_map.gd`

**Interfaces:**
- Consumes: `ContentRegistry`, `DecodeResult`
- Produces: `class_name IdMap extends RefCounted`.
  - `static from_registry(registry: ContentRegistry) -> IdMap`.
  - `to_json_string() -> String`; `static from_json_string(text: String) -> DecodeResult` (`value` is an `IdMap`).
  - `build_translation(registry: ContentRegistry) -> PackedInt32Array` — index is the **saved** numeric id, value is the **current** numeric id. Strings absent from the registry are registered as placeholders, so their original names survive a resave.
  - `entries() -> Dictionary` (string -> saved numeric).

This is the highest-value rule in the whole design: without it, inserting one new tile type renumbers the registry and corrupts every existing world.

- [x] **Step 1: Write the failing test**

```bash
cat > tests/test_id_map.gd <<'GD'
extends GutTest


func _registry() -> ContentRegistry:
	var r: ContentRegistry = ContentRegistry.new()
	var errs: PackedStringArray = r.load_from_dir("res://data")
	assert_eq(errs.size(), 0, "fixture registry loaded")
	return r


func test_map_covers_every_registered_string() -> void:
	var r: ContentRegistry = _registry()
	var m: IdMap = IdMap.from_registry(r)
	for sid: String in r.all_string_ids():
		assert_true(m.entries().has(sid), "%s is in the id map" % sid)


func test_json_round_trip() -> void:
	var m: IdMap = IdMap.from_registry(_registry())
	var result: DecodeResult = IdMap.from_json_string(m.to_json_string())
	assert_true(result.ok, result.error)
	assert_eq((result.value as IdMap).entries(), m.entries())


func test_malformed_json_is_rejected() -> void:
	assert_false(IdMap.from_json_string("{not json").ok)


func test_identical_registries_translate_to_identity() -> void:
	var r: ContentRegistry = _registry()
	var m: IdMap = IdMap.from_registry(r)
	var t: PackedInt32Array = m.build_translation(r)
	for sid: String in r.all_string_ids():
		var n: int = r.numeric_of(sid)
		assert_eq(t[n], n, "%s is unchanged when nothing was added" % sid)


func test_inserting_new_content_does_not_corrupt_old_saves() -> void:
	# The scenario the whole string-id scheme exists to survive: content is
	# added, every numeric id shifts, and an old save must still resolve.
	var old_registry: ContentRegistry = _registry()
	var saved_map: IdMap = IdMap.from_registry(old_registry)
	var saved_grass_id: int = old_registry.numeric_of("grass")

	var new_registry: ContentRegistry = _registry()
	# "aaa_new_thing" sorts before "grass", so grass shifts by one.
	var _n: int = new_registry.register(
		{"id": "aaa_new_thing", "category": "terrain", "display_name": "New",
		 "sprite": "res://assets/tiles/new.png"}
	)

	var t: PackedInt32Array = saved_map.build_translation(new_registry)
	assert_eq(
		new_registry.string_of(t[saved_grass_id]), "grass",
		"the old numeric id still resolves to grass after renumbering"
	)


func test_removed_content_becomes_a_placeholder_retaining_its_string() -> void:
	var registry: ContentRegistry = _registry()
	var m: IdMap = IdMap.new()
	m.set_entry("ghost_tile", 500)

	var t: PackedInt32Array = m.build_translation(registry)
	var mapped: int = t[500]
	assert_ne(mapped, ContentRegistry.ID_UNKNOWN, "removed content is not silently zeroed")
	assert_true(registry.is_placeholder(mapped))
	assert_eq(registry.string_of(mapped), "ghost_tile", "the original string survives")


func test_translation_table_covers_the_highest_saved_id() -> void:
	var m: IdMap = IdMap.new()
	m.set_entry("ghost", 900)
	var t: PackedInt32Array = m.build_translation(_registry())
	assert_eq(t.size(), 901, "table is indexable up to the largest saved id")


func test_id_zero_always_translates_to_unknown() -> void:
	var t: PackedInt32Array = IdMap.from_registry(_registry()).build_translation(_registry())
	assert_eq(t[0], ContentRegistry.ID_UNKNOWN, "empty tiles stay empty")
GD
```

- [x] **Step 2: Run the test to verify it fails**

Run: `./tools/run_tests.sh`
Expected: FAIL — `Identifier "IdMap" not declared in the current scope`.

- [x] **Step 3: Implement IdMap**

```bash
cat > src/core/save/id_map.gd <<'GD'
class_name IdMap
extends RefCounted
## The string_id -> numeric_id mapping in force when a save was written.
##
## Saves store string ids because numeric ids are assigned at boot and shift
## whenever content is added. On load this map is turned into a translation
## table from saved numeric ids to current ones. Without it, adding a single
## tile type would corrupt every existing world.

var _entries: Dictionary = {}  ## String -> int


func entries() -> Dictionary:
	return _entries.duplicate()


func set_entry(string_id: String, numeric_id: int) -> void:
	_entries[string_id] = numeric_id


static func from_registry(registry: ContentRegistry) -> IdMap:
	var m: IdMap = IdMap.new()
	for sid: String in registry.all_string_ids():
		m.set_entry(sid, registry.numeric_of(sid))
	return m


func to_json_string() -> String:
	return JSON.stringify(_entries, "  ", true)


static func from_json_string(text: String) -> DecodeResult:
	# Instance API, not JSON.parse_string() -- see the note in
	# ContentRegistry._read_json. The static helper pushes an engine error
	# that GUT counts as a test failure.
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		return DecodeResult.failure(
			"id_map: malformed JSON at line %d: %s"
			% [json.get_error_line(), json.get_error_message()]
		)
	var parsed: Variant = json.data
	if not (parsed is Dictionary):
		return DecodeResult.failure("id_map: malformed JSON")
	var m: IdMap = IdMap.new()
	for sid: Variant in parsed:
		# JSON numbers arrive as floats.
		m.set_entry(str(sid), int(parsed[sid]))
	return DecodeResult.success(m)


## Builds a lookup where index = saved numeric id, value = current numeric id.
## Content the current build no longer defines is registered as a placeholder
## so the original string survives a resave.
func build_translation(registry: ContentRegistry) -> PackedInt32Array:
	var highest: int = 0
	for sid: String in _entries:
		highest = maxi(highest, _entries[sid])

	var table: PackedInt32Array = PackedInt32Array()
	table.resize(highest + 1)
	table.fill(ContentRegistry.ID_UNKNOWN)

	for sid: String in _entries:
		var saved: int = _entries[sid]
		if registry.has_string(sid):
			table[saved] = registry.numeric_of(sid)
		else:
			table[saved] = registry.register_placeholder(sid)

	table[0] = ContentRegistry.ID_UNKNOWN
	return table
GD
```

- [x] **Step 4: Run the tests to verify they pass**

Run: `./tools/run_tests.sh`
Expected: PASS, 8 id-map tests green.

- [x] **Step 5: Commit**

```bash
git add src/core/save/id_map.gd tests/test_id_map.gd
git commit -m "feat: add IdMap so adding content cannot corrupt existing saves

Removed content becomes a placeholder that retains its original string,
so saves round-trip losslessly rather than being silently zeroed."
```

- [x] **Step 6: Mark the task complete**

Tick this task's checkboxes and commit the progress, so the plan file itself
records what has been done:

```bash
python3 tools/mark_task_done.py 12
git add docs/superpowers/plans/2026-08-23-rp1-phase0-2-foundation-data-persistence.md
git commit -m "docs: mark Task 12 (Id map and the unknown-content policy) complete"
```


---

## Task 13: Save manager

**Files:**
- Create: `src/core/save/save_manager.gd`
- Create: `tests/test_save_manager.gd`

**Interfaces:**
- Consumes: `Zone`, `Chunk`, `ChunkCodec`, `EntityCodec`, `IdMap`, `ContentRegistry`, `DecodeResult`
- Produces: `class_name SaveManager extends RefCounted`.
  - `SAVE_VERSION: int = 1`.
  - `static atomic_write(path: String, bytes: PackedByteArray) -> String` — writes `path + ".tmp"`, flushes, closes, renames. Returns `""` on success, an error message otherwise.
  - `static save_zone(save_root: String, zone: Zone, registry: ContentRegistry, all_chunks: bool = false) -> PackedStringArray` — writes `id_map.json`, `zone_meta.json`, dirty chunks (or all), and `entities.dat`; clears dirty flags on success. Returns errors, empty on success.
  - `static load_zone(save_root: String, zone_id: String, registry: ContentRegistry) -> DecodeResult` (`value` is a `Zone`), applying id translation to the three id columns and to entity types.

- [x] **Step 1: Write the failing test**

```bash
cat > tests/test_save_manager.gd <<'GD'
extends GutTest

var _root: String = "user://test_saves/w1"
var _registry: ContentRegistry


func before_each() -> void:
	_registry = ContentRegistry.new()
	var errs: PackedStringArray = _registry.load_from_dir("res://data")
	assert_eq(errs.size(), 0)
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


func _zone() -> Zone:
	var z: Zone = Zone.new("home", Vector2i(128, 128))
	z.generation_seed = 4242
	var grass: int = _registry.numeric_of("grass")
	var tree: int = _registry.numeric_of("oak_tree")
	for y: int in range(128):
		for x: int in range(128):
			z.set_terrain(Vector2i(x, y), grass)
			z.set_flags(Vector2i(x, y), Chunk.FLAG_WALKABLE)
	z.set_object(Vector2i(10, 10), tree)
	z.set_height(Vector2i(10, 10), 3)
	var rabbit: int = z.entities.spawn(_registry.numeric_of("rabbit"), Vector2(64.5, 64.5))
	z.entities.set_facing(rabbit, 2)
	return z


func test_atomic_write_leaves_no_temp_file() -> void:
	var path: String = _root.path_join("x.bin")
	assert_eq(SaveManager.atomic_write(path, PackedByteArray([1, 2, 3])), "")
	assert_true(FileAccess.file_exists(path))
	assert_false(FileAccess.file_exists(path + ".tmp"), "temp file was renamed away")


func test_atomic_write_overwrites_existing_content() -> void:
	var path: String = _root.path_join("x.bin")
	var _a: String = SaveManager.atomic_write(path, PackedByteArray([1, 2, 3, 4]))
	var _b: String = SaveManager.atomic_write(path, PackedByteArray([9]))
	assert_eq(FileAccess.get_file_as_bytes(path), PackedByteArray([9]))


func test_save_writes_the_expected_layout() -> void:
	var errs: PackedStringArray = SaveManager.save_zone(_root, _zone(), _registry, true)
	assert_eq(errs.size(), 0, "save produced no errors: %s" % ", ".join(errs))
	assert_true(FileAccess.file_exists(_root.path_join("id_map.json")))
	assert_true(FileAccess.file_exists(_root.path_join("zones/home/zone_meta.json")))
	assert_true(FileAccess.file_exists(_root.path_join("zones/home/entities.dat")))
	assert_true(FileAccess.file_exists(_root.path_join("zones/home/chunks/0_0.chunk")))
	assert_eq(DirAccess.get_files_at(_root.path_join("zones/home/chunks")).size(), 16,
		"a 128x128 zone is 4x4 chunks")


func test_round_trip_preserves_the_whole_zone() -> void:
	var original: Zone = _zone()
	var _e: PackedStringArray = SaveManager.save_zone(_root, original, _registry, true)

	var result: DecodeResult = SaveManager.load_zone(_root, "home", _registry)
	assert_true(result.ok, "load succeeded: %s" % result.error)
	var back: Zone = result.value

	assert_eq(back.id, "home")
	assert_eq(back.size_tiles, Vector2i(128, 128))
	assert_eq(back.generation_seed, 4242)
	assert_eq(back.get_object(Vector2i(10, 10)), _registry.numeric_of("oak_tree"))
	assert_eq(back.get_height(Vector2i(10, 10)), 3)
	assert_true(back.is_walkable(Vector2i(0, 0)))
	assert_eq(back.entities.count(), 1)


func test_chunk_payloads_round_trip_byte_identical() -> void:
	var original: Zone = _zone()
	var _e: PackedStringArray = SaveManager.save_zone(_root, original, _registry, true)
	var back: Zone = SaveManager.load_zone(_root, "home", _registry).value
	for c: Vector2i in original.chunk_coords():
		var a: Chunk = original.get_chunk(c)
		var b: Chunk = back.get_chunk(c)
		assert_not_null(b, "chunk %s survived" % c)
		assert_eq(b.terrain_id, a.terrain_id, "terrain column identical at %s" % c)
		assert_eq(b.object_id, a.object_id)
		assert_eq(b.height, a.height)
		assert_eq(b.flags, a.flags)


func test_save_completes_within_the_budget() -> void:
	var z: Zone = _zone()
	var start: int = Time.get_ticks_msec()
	var _e: PackedStringArray = SaveManager.save_zone(_root, z, _registry, true)
	var elapsed: int = Time.get_ticks_msec() - start
	assert_lt(elapsed, 100, "full zone save took %d ms, budget is 100 ms" % elapsed)


func test_only_dirty_chunks_are_rewritten() -> void:
	var z: Zone = _zone()
	var _e: PackedStringArray = SaveManager.save_zone(_root, z, _registry, true)
	assert_eq(z.dirty_chunk_coords().size(), 0, "saving clears dirty flags")

	# Deleting the file and asserting it is NOT recreated is deterministic.
	# A modified-time comparison would not be: mtime has one-second
	# granularity, so a rewrite within the same second looks unchanged.
	var untouched: String = _root.path_join("zones/home/chunks/3_3.chunk")
	DirAccess.remove_absolute(untouched)

	z.set_terrain(Vector2i(0, 0), _registry.numeric_of("water"))
	assert_eq(z.dirty_chunk_coords(), [Vector2i(0, 0)] as Array[Vector2i])

	var _e2: PackedStringArray = SaveManager.save_zone(_root, z, _registry)
	assert_false(FileAccess.file_exists(untouched), "clean chunk was not rewritten")
	assert_true(
		FileAccess.file_exists(_root.path_join("zones/home/chunks/0_0.chunk")),
		"the dirty chunk was written"
	)


func test_old_save_still_loads_after_new_content_is_added() -> void:
	# The acceptance criterion the string-id scheme exists to satisfy.
	var original: Zone = _zone()
	var _e: PackedStringArray = SaveManager.save_zone(_root, original, _registry, true)

	var extended: ContentRegistry = ContentRegistry.new()
	var _errs: PackedStringArray = extended.load_from_dir("res://data")
	# Sorts before "grass", so every subsequent numeric id shifts.
	var _n: int = extended.register(
		{"id": "aaa_ash", "category": "terrain", "display_name": "Ash",
		 "sprite": "res://assets/tiles/ash.png"}
	)

	var result: DecodeResult = SaveManager.load_zone(_root, "home", extended)
	assert_true(result.ok, result.error)
	var back: Zone = result.value
	assert_eq(
		extended.string_of(back.get_terrain(Vector2i(0, 0))), "grass",
		"tiles still resolve to grass after renumbering"
	)
	assert_eq(extended.string_of(back.get_object(Vector2i(10, 10))), "oak_tree")


func test_save_referencing_removed_content_loads_as_a_placeholder() -> void:
	var z: Zone = _zone()
	var _e: PackedStringArray = SaveManager.save_zone(_root, z, _registry, true)

	# Rewrite id_map.json as though the save had used a tile this build lacks.
	var map_path: String = _root.path_join("id_map.json")
	var m: IdMap = IdMap.from_json_string(FileAccess.get_file_as_string(map_path)).value
	m.set_entry("mystery_moss", _registry.numeric_of("grass"))
	var _w: String = SaveManager.atomic_write(map_path, m.to_json_string().to_utf8_buffer())

	var fresh: ContentRegistry = ContentRegistry.new()
	var _errs: PackedStringArray = fresh.load_from_dir("res://data")
	var result: DecodeResult = SaveManager.load_zone(_root, "home", fresh)
	assert_true(result.ok, result.error)
	assert_true(fresh.has_string("mystery_moss"), "the unknown string was retained")
	assert_true(fresh.is_placeholder(fresh.numeric_of("mystery_moss")))


func test_loading_a_missing_zone_fails_cleanly() -> void:
	var result: DecodeResult = SaveManager.load_zone(_root, "nowhere", _registry)
	assert_false(result.ok)
	assert_ne(result.error, "")


func test_loading_a_corrupt_chunk_fails_cleanly() -> void:
	var _e: PackedStringArray = SaveManager.save_zone(_root, _zone(), _registry, true)
	var _w: String = SaveManager.atomic_write(
		_root.path_join("zones/home/chunks/0_0.chunk"), PackedByteArray([0, 1, 2, 3])
	)
	var result: DecodeResult = SaveManager.load_zone(_root, "home", _registry)
	assert_false(result.ok, "a corrupt chunk is reported, not silently skipped")
GD
```

- [x] **Step 2: Run the test to verify it fails**

Run: `./tools/run_tests.sh`
Expected: FAIL — `Identifier "SaveManager" not declared in the current scope`.

- [x] **Step 3: Implement SaveManager**

```bash
cat > src/core/save/save_manager.gd <<'GD'
class_name SaveManager
extends RefCounted
## Orchestrates zone persistence.
##
## Metadata is JSON because it is small, cold, and worth reading with `cat`.
## Bulk tile and entity data is binary. Every write is atomic: a crash
## mid-save must never leave a half-written world.

const SAVE_VERSION: int = 1


static func atomic_write(path: String, bytes: PackedByteArray) -> String:
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

	var err: int = DirAccess.rename_absolute(tmp, path)
	if err != OK:
		return "cannot rename %s -> %s (error %d)" % [tmp, path, err]
	return ""


static func _zone_dir(save_root: String, zone_id: String) -> String:
	return save_root.path_join("zones").path_join(zone_id)


static func save_zone(
	save_root: String, zone: Zone, registry: ContentRegistry, all_chunks: bool = false
) -> PackedStringArray:
	var errors: PackedStringArray = []
	var zdir: String = _zone_dir(save_root, zone.id)

	var map_err: String = atomic_write(
		save_root.path_join("id_map.json"),
		IdMap.from_registry(registry).to_json_string().to_utf8_buffer()
	)
	if map_err != "":
		errors.append(map_err)

	var meta: Dictionary = {
		"save_version": SAVE_VERSION,
		"id": zone.id,
		"display_name": zone.display_name,
		"size_x": zone.size_tiles.x,
		"size_y": zone.size_tiles.y,
		"biome": zone.biome,
		"generation_seed": zone.generation_seed,
	}
	var meta_err: String = atomic_write(
		zdir.path_join("zone_meta.json"),
		JSON.stringify(meta, "  ", true).to_utf8_buffer()
	)
	if meta_err != "":
		errors.append(meta_err)

	var targets: Array[Vector2i] = zone.chunk_coords() if all_chunks else zone.dirty_chunk_coords()
	for c: Vector2i in targets:
		var chunk: Chunk = zone.get_chunk(c)
		var err: String = atomic_write(
			zdir.path_join("chunks").path_join("%d_%d.chunk" % [c.x, c.y]),
			ChunkCodec.encode(chunk)
		)
		if err != "":
			errors.append(err)

	var ent_err: String = atomic_write(
		zdir.path_join("entities.dat"), EntityCodec.encode(zone.entities)
	)
	if ent_err != "":
		errors.append(ent_err)

	if errors.is_empty():
		zone.clear_dirty()
	return errors


## Rewrites a u16 id column through the translation table in place.
static func _translate_column(column: PackedByteArray, table: PackedInt32Array) -> void:
	for i: int in range(Coords.TILES_PER_CHUNK):
		var saved: int = column.decode_u16(i * 2)
		if saved < table.size():
			column.encode_u16(i * 2, table[saved])
		else:
			column.encode_u16(i * 2, ContentRegistry.ID_UNKNOWN)


static func load_zone(
	save_root: String, zone_id: String, registry: ContentRegistry
) -> DecodeResult:
	var zdir: String = _zone_dir(save_root, zone_id)
	var meta_path: String = zdir.path_join("zone_meta.json")
	if not FileAccess.file_exists(meta_path):
		return DecodeResult.failure("zone '%s': no zone_meta.json at %s" % [zone_id, zdir])

	var meta_json: JSON = JSON.new()
	if meta_json.parse(FileAccess.get_file_as_string(meta_path)) != OK:
		return DecodeResult.failure("zone '%s': malformed zone_meta.json" % zone_id)
	var meta: Variant = meta_json.data
	if not (meta is Dictionary):
		return DecodeResult.failure("zone '%s': malformed zone_meta.json" % zone_id)

	var map_path: String = save_root.path_join("id_map.json")
	if not FileAccess.file_exists(map_path):
		return DecodeResult.failure("save: no id_map.json; cannot resolve content ids")
	var map_result: DecodeResult = IdMap.from_json_string(FileAccess.get_file_as_string(map_path))
	if not map_result.ok:
		return map_result
	var table: PackedInt32Array = (map_result.value as IdMap).build_translation(registry)

	var zone: Zone = Zone.new(
		str(meta.get("id", zone_id)),
		Vector2i(int(meta.get("size_x", 128)), int(meta.get("size_y", 128)))
	)
	zone.display_name = str(meta.get("display_name", zone.id))
	zone.biome = str(meta.get("biome", "temperate"))
	zone.generation_seed = int(meta.get("generation_seed", 0))

	var chunk_dir: String = zdir.path_join("chunks")
	for file_name: String in DirAccess.get_files_at(chunk_dir):
		if not file_name.ends_with(".chunk"):
			continue
		var bytes: PackedByteArray = FileAccess.get_file_as_bytes(chunk_dir.path_join(file_name))
		var decoded: DecodeResult = ChunkCodec.decode(bytes)
		if not decoded.ok:
			return DecodeResult.failure("%s: %s" % [file_name, decoded.error])
		var chunk: Chunk = decoded.value
		_translate_column(chunk.terrain_id, table)
		_translate_column(chunk.floor_id, table)
		_translate_column(chunk.object_id, table)
		chunk.dirty = false
		zone.install_chunk(chunk)

	var ent_path: String = zdir.path_join("entities.dat")
	if FileAccess.file_exists(ent_path):
		var ent: DecodeResult = EntityCodec.decode(FileAccess.get_file_as_bytes(ent_path))
		if not ent.ok:
			return DecodeResult.failure("entities.dat: %s" % ent.error)
		zone.entities = ent.value

	return DecodeResult.success(zone)
GD
```

Note: loading installs pre-built chunks rather than creating empty ones, so it uses `Zone.install_chunk()` (added in Task 9) rather than reaching into the private `_chunks` dictionary or widening `get_chunk`.

- [x] **Step 4: Run the tests to verify they pass**

Run: `./tools/run_tests.sh`
Expected: PASS, 11 save-manager tests green.

- [x] **Step 5: Commit**

```bash
git add src/core/save/save_manager.gd tests/test_save_manager.gd
git commit -m "feat: add SaveManager with atomic writes and dirty-chunk saving

Covers the acceptance criterion that an old save still loads after new
content shifts every numeric id."
```

- [x] **Step 6: Mark the task complete**

Tick this task's checkboxes and commit the progress, so the plan file itself
records what has been done:

```bash
python3 tools/mark_task_done.py 13
git add docs/superpowers/plans/2026-08-23-rp1-phase0-2-foundation-data-persistence.md
git commit -m "docs: mark Task 13 (Save manager) complete"
```


---

## Task 14: Migration skeleton and a version fixture

**Files:**
- Create: `src/core/save/migrations.gd`
- Create: `tests/fixtures/v1_chunk.chunk` (generated, committed)
- Create: `tests/test_migrations.gd`
- Create: `tools/make_fixture.gd`

**Interfaces:**
- Consumes: `ChunkCodec`, `DecodeResult`
- Produces: `class_name Migrations extends RefCounted` with `CURRENT_CHUNK_VERSION: int = ChunkCodec.FORMAT_VERSION`; `static needs_migration(version: int) -> bool`; `static migrate_chunk(version: int, chunk: Chunk) -> DecodeResult`.

The migration function does nothing today and that is the point — the skeleton and its test exist before they are needed, because retrofitting versioning onto a live save format is what kills hobby projects. The committed fixture is the real asset: when format version 2 arrives, this test proves version 1 files still load.

- [x] **Step 1: Write the fixture generator and generate the fixture**

```bash
cat > tools/make_fixture.gd <<'GD'
extends SceneTree
## Writes a chunk fixture at the CURRENT format version.
## Run once per format-version bump, then commit the output:
##   ./tools/godot.sh --headless --path . -s tools/make_fixture.gd

func _init() -> void:
	var c: Chunk = Chunk.new(Vector2i(1, 2))
	for y: int in range(32):
		for x: int in range(32):
			var l: Vector2i = Vector2i(x, y)
			c.set_terrain(l, (x * 31 + y * 17) % 65536)
			c.set_height(l, (x + y) % 256)
			c.set_flags(l, Chunk.FLAG_WALKABLE if (x + y) % 2 == 0 else 0)

	var path: String = "res://tests/fixtures/v%d_chunk.chunk" % ChunkCodec.FORMAT_VERSION
	DirAccess.make_dir_recursive_absolute("res://tests/fixtures")
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(ChunkCodec.encode(c))
	f.close()
	print("wrote ", path)
	quit(0)
GD

mkdir -p tests/fixtures
./tools/godot.sh --headless --path . -s tools/make_fixture.gd
ls -la tests/fixtures/
```

Expected: `wrote res://tests/fixtures/v1_chunk.chunk` and the file exists.

- [x] **Step 2: Write the failing test**

```bash
cat > tests/test_migrations.gd <<'GD'
extends GutTest


func test_current_version_needs_no_migration() -> void:
	assert_false(Migrations.needs_migration(ChunkCodec.FORMAT_VERSION))


func test_older_version_needs_migration() -> void:
	assert_true(Migrations.needs_migration(ChunkCodec.FORMAT_VERSION - 1))


func test_migrating_the_current_version_is_a_no_op() -> void:
	var c: Chunk = Chunk.new(Vector2i(0, 0))
	c.set_terrain(Vector2i(1, 1), 42)
	var result: DecodeResult = Migrations.migrate_chunk(ChunkCodec.FORMAT_VERSION, c)
	assert_true(result.ok, result.error)
	assert_eq((result.value as Chunk).get_terrain(Vector2i(1, 1)), 42)


func test_unknown_older_version_reports_a_clear_error() -> void:
	var result: DecodeResult = Migrations.migrate_chunk(0, Chunk.new(Vector2i.ZERO))
	assert_false(result.ok)
	assert_string_contains(result.error, "0")


func test_committed_v1_fixture_still_loads() -> void:
	# The regression guard. When FORMAT_VERSION becomes 2, this test proves
	# version 1 files written by shipped builds still open.
	var path: String = "res://tests/fixtures/v1_chunk.chunk"
	assert_true(FileAccess.file_exists(path), "fixture is committed")

	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
	assert_eq(ChunkCodec.peek_version(bytes), 1, "fixture is a version 1 file")

	var decoded: DecodeResult = ChunkCodec.decode(bytes)
	assert_true(decoded.ok, "v1 fixture decodes: %s" % decoded.error)

	var c: Chunk = decoded.value
	assert_eq(c.coord, Vector2i(1, 2))
	for y: int in range(32):
		for x: int in range(32):
			var l: Vector2i = Vector2i(x, y)
			assert_eq(c.get_terrain(l), (x * 31 + y * 17) % 65536)
			assert_eq(c.get_height(l), (x + y) % 256)
GD
```

- [x] **Step 3: Run the test to verify it fails**

Run: `./tools/run_tests.sh`
Expected: FAIL — `Identifier "Migrations" not declared in the current scope`.

- [x] **Step 4: Implement Migrations**

```bash
cat > src/core/save/migrations.gd <<'GD'
class_name Migrations
extends RefCounted
## Save-format upgrade path.
##
## Deliberately empty today. The skeleton and its test exist before they are
## needed because retrofitting versioning onto a live save format is the kind
## of problem that kills hobby projects.
##
## To add version 2:
##   1. bump ChunkCodec.FORMAT_VERSION to 2
##   2. add a `_migrate_1_to_2(chunk)` function below and dispatch to it
##   3. run tools/make_fixture.gd and commit tests/fixtures/v2_chunk.chunk
##   4. leave the v1 fixture test in place -- it is the regression guard

const CURRENT_CHUNK_VERSION: int = ChunkCodec.FORMAT_VERSION


static func needs_migration(version: int) -> bool:
	return version < CURRENT_CHUNK_VERSION


static func migrate_chunk(version: int, chunk: Chunk) -> DecodeResult:
	if version == CURRENT_CHUNK_VERSION:
		return DecodeResult.success(chunk)
	if version > CURRENT_CHUNK_VERSION:
		return DecodeResult.failure(
			"chunk version %d is newer than this build supports (%d)"
			% [version, CURRENT_CHUNK_VERSION]
		)
	return DecodeResult.failure(
		"chunk version %d has no migration path to %d" % [version, CURRENT_CHUNK_VERSION]
	)
GD
```

- [x] **Step 5: Run the tests to verify they pass**

Run: `./tools/run_tests.sh`
Expected: PASS, 5 migration tests green.

- [x] **Step 6: Commit**

```bash
git add src/core/save/migrations.gd tools/make_fixture.gd tests/test_migrations.gd tests/fixtures
git commit -m "feat: add migration skeleton and committed v1 chunk fixture

The fixture is the asset here: when FORMAT_VERSION becomes 2, this test
proves version 1 saves from shipped builds still open."
```

- [x] **Step 7: Mark the task complete**

Tick this task's checkboxes and commit the progress, so the plan file itself
records what has been done:

```bash
python3 tools/mark_task_done.py 14
git add docs/superpowers/plans/2026-08-23-rp1-phase0-2-foundation-data-persistence.md
git commit -m "docs: mark Task 14 (Migration skeleton and a version fixture) complete"
```


---

## Task 15: Smoke test and screenshot tooling

**Files:**
- Create: `tools/smoke.gd`
- Create: `tools/screenshot.gd`
- Create: `scenes/main.tscn`
- Create: `src/presentation/main.gd`

**Interfaces:**
- Consumes: everything in `src/core/`
- Produces: `tools/smoke.gd` — a `SceneTree` script that exercises the data layer end to end, runs 300 iterations, and exits non-zero on any failure. `tools/screenshot.gd` — writes a PNG to a path given by `--screenshot-out`.

**A correction to the spec.** Spec task 0.8 says the screenshot script "produces a PNG from a headless run". It cannot: `--headless` uses a dummy rendering driver with no framebuffer, so `get_texture().get_image()` returns nothing usable. The screenshot tool therefore runs with a **real display driver** — natively on the dev machine, and under `xvfb-run` in Linux CI. The smoke test stays genuinely headless.

- [x] **Step 1: Write the smoke test**

```bash
cat > tools/smoke.gd <<'GD'
extends SceneTree
## Boot check: exercises the data layer end to end and exits non-zero on any
## failure. Runs genuinely headless -- no rendering involved.

const ITERATIONS: int = 300

var _failures: PackedStringArray = []


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _init() -> void:
	var registry: ContentRegistry = ContentRegistry.new()
	var errs: PackedStringArray = registry.load_from_dir("res://data")
	_check(errs.is_empty(), "content failed to load: %s" % ", ".join(errs))

	var zone: Zone = Zone.new("smoke", Vector2i(128, 128))
	var grass: int = registry.numeric_of("grass")
	_check(grass != ContentRegistry.ID_UNKNOWN, "grass is registered")

	for i: int in range(ITERATIONS):
		var w: Vector2i = Vector2i(i % 128, (i * 7) % 128)
		zone.set_terrain(w, grass)
		zone.set_flags(w, Chunk.FLAG_WALKABLE)
		_check(zone.get_terrain(w) == grass, "tile %s round-trips in memory" % w)

	var id: int = zone.entities.spawn(registry.numeric_of("rabbit"), Vector2(1.0, 2.0))
	_check(zone.entities.has(id), "entity spawned")

	var root: String = "user://smoke_save"
	var save_errs: PackedStringArray = SaveManager.save_zone(root, zone, registry, true)
	_check(save_errs.is_empty(), "save failed: %s" % ", ".join(save_errs))

	var loaded: DecodeResult = SaveManager.load_zone(root, "smoke", registry)
	_check(loaded.ok, "load failed: %s" % loaded.error)
	if loaded.ok:
		var back: Zone = loaded.value
		_check(back.get_terrain(Vector2i(0, 0)) == grass, "tile survived the round trip")
		_check(back.entities.count() == 1, "entity survived the round trip")

	for f: String in _failures:
		printerr("SMOKE FAILURE: ", f)
	if _failures.is_empty():
		print("Smoke test: OK (%d iterations)" % ITERATIONS)
		quit(0)
	else:
		printerr("Smoke test: %d failure(s)" % _failures.size())
		quit(1)
GD
```

- [x] **Step 2: Run the smoke test and verify it passes**

Run: `./tools/godot.sh --headless --path . -s tools/smoke.gd; echo "exit=$?"`
Expected: `Smoke test: OK (300 iterations)` and `exit=0`.

- [x] **Step 3: Verify the smoke test can fail**

A gate that cannot go red is not a gate.

```bash
sed -i.bak 's|_check(grass != ContentRegistry.ID_UNKNOWN, "grass is registered")|_check(false, "deliberate failure")|' tools/smoke.gd
./tools/godot.sh --headless --path . -s tools/smoke.gd; echo "exit=$?"
mv tools/smoke.gd.bak tools/smoke.gd
```

Expected: `SMOKE FAILURE: deliberate failure` and `exit=1`.

- [x] **Step 4: Create a minimal main scene**

```bash
mkdir -p scenes src/presentation

cat > src/presentation/main.gd <<'GD'
extends Node2D
## Placeholder entry point. Phase 3 replaces this with ZoneRenderer.
## Lives in presentation/ because it is a Godot node.

func _ready() -> void:
	var registry: ContentRegistry = ContentRegistry.new()
	var errs: PackedStringArray = registry.load_from_dir("res://data")
	if not errs.is_empty():
		push_error("content failed to load: %s" % ", ".join(errs))
	print("RP1 booted with %d content definitions" % registry.all_string_ids().size())
GD

cat > scenes/main.tscn <<'TSCN'
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://src/presentation/main.gd" id="1"]

[node name="Main" type="Node2D"]
script = ExtResource("1")
TSCN
```

Register it as the main scene:

```bash
printf '\n[application]\n\nrun/main_scene="res://scenes/main.tscn"\n' >> project.godot
```

Verify the merge did not duplicate the `[application]` section; if it did, hand-edit `project.godot` so `run/main_scene` sits inside the existing one.

- [x] **Step 5: Write the screenshot tool**

```bash
cat > tools/screenshot.gd <<'GD'
extends SceneTree
## Captures a PNG of the main scene.
##
## Requires a real rendering driver: --headless uses a dummy driver with no
## framebuffer, so this must run windowed (or under xvfb-run on Linux CI).
##
##   ./tools/godot.sh --path . -s tools/screenshot.gd -- --out=shot.png

const DEFAULT_OUT: String = "user://screenshot.png"
const WARMUP_FRAMES: int = 10

var _frames: int = 0
var _out: String = DEFAULT_OUT


func _init() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.substr(6)
	var scene: PackedScene = load("res://scenes/main.tscn")
	root.add_child(scene.instantiate())


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < WARMUP_FRAMES:
		return false

	var image: Image = root.get_texture().get_image()
	if image == null:
		printerr("screenshot: no framebuffer. Are you running --headless?")
		quit(1)
		return true

	var err: int = image.save_png(_out)
	if err != OK:
		printerr("screenshot: save_png failed (error %d)" % err)
		quit(1)
		return true

	print("wrote ", _out)
	quit(0)
	return true
GD
```

- [x] **Step 6: Verify the screenshot tool produces a PNG**

Run: `./tools/godot.sh --path . -s tools/screenshot.gd -- --out=/tmp/rp1_shot.png`
Expected: a window flashes, `wrote /tmp/rp1_shot.png`, exit 0.

Confirm with: `file /tmp/rp1_shot.png` showing `PNG image data, 1280 x 720`.

Then confirm the headless failure path is explicit rather than silent:

Run: `./tools/godot.sh --headless --path . -s tools/screenshot.gd -- --out=/tmp/x.png; echo "exit=$?"`
Expected: `screenshot: no framebuffer` and `exit=1`.

- [x] **Step 7: Commit**

```bash
git add tools/smoke.gd tools/screenshot.gd scenes/main.tscn src/presentation/main.gd project.godot
git commit -m "feat: add smoke test and screenshot tooling

Screenshots need a real rendering driver; --headless has no framebuffer.
The smoke test stays genuinely headless."
```

- [x] **Step 8: Mark the task complete**

Tick this task's checkboxes and commit the progress, so the plan file itself
records what has been done:

```bash
python3 tools/mark_task_done.py 15
git add docs/superpowers/plans/2026-08-23-rp1-phase0-2-foundation-data-persistence.md
git commit -m "docs: mark Task 15 (Smoke test and screenshot tooling) complete"
```


---

## Task 16: CI with five gates

**Files:**
- Create: `.github/workflows/ci.yml`
- Create: `tools/check_asset_licences.sh`
- Create: `assets/CREDITS.md`
- Create: `assets/tiles/LICENSE.txt`

**Interfaces:**
- Consumes: `tools/run_tests.sh`, `tools/guard.gd`, `tools/smoke.gd`
- Produces: a GitHub Actions workflow running all five spec gates on every push and pull request.

- [x] **Step 1: Write the asset licence checker**

```bash
mkdir -p assets/tiles

cat > tools/check_asset_licences.sh <<'SH'
#!/usr/bin/env bash
# Every folder under assets/ must declare its licence. Reconstructing this
# before a Steam launch with 60 packs and no records is a miserable week.
set -euo pipefail
cd "$(dirname "$0")/.."

[[ -d assets ]] || { echo "No assets/ directory yet; nothing to check."; exit 0; }

missing=0
while IFS= read -r dir; do
  [[ "$dir" == "assets" ]] && continue
  if [[ ! -f "$dir/LICENSE.txt" ]]; then
    echo "MISSING LICENCE: $dir/LICENSE.txt" >&2
    missing=1
  fi
done < <(find assets -mindepth 1 -maxdepth 1 -type d)

if [[ $missing -eq 1 ]]; then
  echo "Every folder under assets/ needs a LICENSE.txt naming source, author, licence." >&2
  exit 1
fi
echo "Asset licences: OK"
SH
chmod +x tools/check_asset_licences.sh

cat > assets/tiles/LICENSE.txt <<'TXT'
Source: (none yet -- placeholder folder)
Author: n/a
Licence: n/a

Replace this file when the first tileset is imported. Record the pack
name, download URL, author, and exact licence.
TXT

cat > assets/CREDITS.md <<'MD'
# Asset credits

Every third-party asset pack used in RP1, with its source and licence.
Maintained from the very first import -- reconstructing it before a Steam
launch with 60 packs and no records is a genuinely miserable week.

## Licence policy

| Licence | Allowed | Notes |
|---|---|---|
| CC0 | Yes, preferred | Public domain, no attribution required |
| CC-BY | Yes | Credit required; it must be tracked in this file |
| CC-BY-SA | Flag before use | Derivative art must carry the same licence |
| CC-NC | **Never** | Non-commercial; excludes a Steam release |

## Packs

_None imported yet. Phase 3 adds the first Kenney tileset._

| Pack | Author | Source | Licence |
|---|---|---|---|
MD
```

- [x] **Step 2: Verify the licence gate works in both directions**

```bash
./tools/check_asset_licences.sh; echo "clean_exit=$?"
mkdir -p assets/unlicensed_thing
./tools/check_asset_licences.sh; echo "violation_exit=$?"
rmdir assets/unlicensed_thing
```

Expected: `Asset licences: OK` / `clean_exit=0`, then `MISSING LICENCE` / `violation_exit=1`.

- [x] **Step 3: Write the CI workflow**

```bash
mkdir -p .github/workflows

cat > .github/workflows/ci.yml <<'YML'
name: CI

on:
  push:
    branches: [main]
  pull_request:

env:
  GODOT_VERSION: 4.7.2

jobs:
  verify:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Cache Godot
        id: cache-godot
        uses: actions/cache@v4
        with:
          path: ~/godot-bin
          key: godot-${{ env.GODOT_VERSION }}-linux

      - name: Install Godot (standard build, not Mono)
        if: steps.cache-godot.outputs.cache-hit != 'true'
        run: |
          mkdir -p ~/godot-bin
          curl -sSLo /tmp/godot.zip \
            "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip"
          unzip -q /tmp/godot.zip -d ~/godot-bin
          mv ~/godot-bin/Godot_v${GODOT_VERSION}-stable_linux.x86_64 ~/godot-bin/godot
          chmod +x ~/godot-bin/godot

      - name: Expose Godot
        run: echo "GODOT_BIN=$HOME/godot-bin/godot" >> "$GITHUB_ENV"

      - name: Verify engine build
        run: |
          ./tools/godot.sh --version
          ./tools/godot.sh --version | grep -qv mono

      # Gate 1
      - name: Tests
        run: ./tools/run_tests.sh

      # Gate 2
      - name: Architecture guard
        run: ./tools/godot.sh --headless --path . -s tools/guard.gd

      # Gate 3
      - name: Smoke test
        run: ./tools/godot.sh --headless --path . -s tools/smoke.gd

      # Gate 4
      - name: Asset licences
        run: ./tools/check_asset_licences.sh

  export:
    runs-on: ubuntu-latest
    needs: verify
    steps:
      - uses: actions/checkout@v4

      - name: Install Godot and export templates
        run: |
          mkdir -p ~/godot-bin
          curl -sSLo /tmp/godot.zip \
            "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip"
          unzip -q /tmp/godot.zip -d ~/godot-bin
          mv ~/godot-bin/Godot_v${GODOT_VERSION}-stable_linux.x86_64 ~/godot-bin/godot
          chmod +x ~/godot-bin/godot
          curl -sSLo /tmp/templates.tpz \
            "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_export_templates.tpz"
          mkdir -p ~/.local/share/godot/export_templates
          unzip -q /tmp/templates.tpz -d /tmp/tpl
          mv /tmp/tpl/templates ~/.local/share/godot/export_templates/${GODOT_VERSION}.stable

      - name: Expose Godot
        run: echo "GODOT_BIN=$HOME/godot-bin/godot" >> "$GITHUB_ENV"

      # Gate 5
      - name: Export Linux and Windows
        run: |
          ./tools/godot.sh --headless --path . --import
          mkdir -p build/linux build/windows
          ./tools/godot.sh --headless --path . --export-release "Linux" build/linux/rp1.x86_64
          ./tools/godot.sh --headless --path . --export-release "Windows" build/windows/rp1.exe

      # Godot may treat data/*.json as importable resources, in which case
      # the exported PCK will not contain them as plain files and
      # ContentRegistry.load_from_dir finds nothing. The export gate only
      # BUILDS, so this would ship silently. Run the build and check.
      - name: Verify the exported build loads its content
        run: |
          chmod +x build/linux/rp1.x86_64
          OUT="$(xvfb-run -a ./build/linux/rp1.x86_64 --quit-after 30 2>&1 || true)"
          echo "$OUT"
          echo "$OUT" | grep -qE "RP1 booted with [1-9][0-9]* content definitions" \
            || { echo "Exported build loaded no content: data/ is not reaching the PCK." >&2
                 echo "Fix: Export preset -> Resources -> 'Filters to export non-resource files' -> add data/*" >&2
                 exit 1; }

      - uses: actions/upload-artifact@v4
        with:
          name: rp1-builds
          path: build/
YML
```

- [x] **Step 4: Commit `export_presets.cfg` rather than ignoring it**

The `.gitignore` written before Phase 0 excludes `export_presets.cfg`, which is the usual default because the file can hold signing paths and keystore passwords. CI cannot export without it. Commit the file and keep secrets in repository secrets instead.

```bash
sed -i.bak '/^export_presets.cfg$/d' .gitignore && rm -f .gitignore.bak
grep -c export_presets .gitignore || echo "no longer ignored"
```

The presets are committed as `export_presets.cfg` with names exactly `Linux` and `Windows`, matching the `--export-release` arguments above. They can also be regenerated from the editor via **Project → Export → Add…**.

Both presets set `include_filter="*.json"`. This is required, not cosmetic: Godot 4.7.2 does **not** import `.json` as a resource (verified — no `.import` files are produced for `data/**/*.json`), so `export_filter="all_resources"` alone would omit every content definition and the exported game would boot with an empty registry. The "Verify the exported build loads its content" CI step exists to catch exactly that.

Verify locally: `./tools/godot.sh --headless --path . --export-release "Linux" /tmp/rp1_test.x86_64`

- [x] **Step 5: Run every gate locally before pushing**

```bash
./tools/run_tests.sh                                        && echo "GATE 1 OK"
./tools/godot.sh --headless --path . -s tools/guard.gd      && echo "GATE 2 OK"
./tools/godot.sh --headless --path . -s tools/smoke.gd      && echo "GATE 3 OK"
./tools/check_asset_licences.sh                             && echo "GATE 4 OK"
```

Expected: all four print OK. Gate 5 runs in CI.

- [x] **Step 6: Commit and verify CI goes green, then red**

```bash
git add .github assets tools/check_asset_licences.sh .gitignore export_presets.cfg
git commit -m "ci: add five gates - tests, architecture, smoke, licences, export"
git push -u origin HEAD
```

Then prove the gates work by opening a throwaway branch that adds `extends Node2D` to `src/core/coords.gd`, confirming CI goes red on gate 2, and deleting the branch. A gate never observed failing is not known to work.

- [x] **Step 7: Mark the task complete**

Tick this task's checkboxes and commit the progress, so the plan file itself
records what has been done:

```bash
python3 tools/mark_task_done.py 16
git add docs/superpowers/plans/2026-08-23-rp1-phase0-2-foundation-data-persistence.md
git commit -m "docs: mark Task 16 (CI with five gates) complete"
```


---

## Definition of done for Phases 0-2

- [x] `./tools/run_tests.sh` passes with roughly 110 assertions across 13 test files
- [x] `tools/guard.gd` exits 0, and exits 1 when a node is introduced into `src/core/`
- [x] `tools/smoke.gd` exits 0, and exits 1 when a check is broken
- [x] `tools/check_asset_licences.sh` exits 0, and exits 1 for an unlicensed folder
- [ ] CI is green on `main` and observed going red for a deliberate violation  
      *(Not yet: CI is green on PR #1, but has not run on `main`, and no deliberate violation has been pushed to observe it go red.)*
- [x] A 128x128 zone's chunk payloads round-trip byte-identical
- [x] A full zone save completes in under 100 ms
- [x] `tests/fixtures/v1_chunk.chunk` is committed and loads
- [x] An old save still loads after new content shifts every numeric id
- [x] Content removed from `data/` loads as a placeholder retaining its string
- [x] No file in `src/core/` or `src/systems/` references a Godot node

**Not done in this plan, by design:** rendering, player movement, world authoring, animals with behaviour, menus, audio. Those are Phases 3-6 and get their own plan.
