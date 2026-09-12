# RP1 — Phase 5 Design: Game Loop Closure

**Status:** draft
**Date:** 2026-09-12
**Refines:** `docs/superpowers/specs/2026-08-23-rp1-stage0-stage1-design.md` §10 (Phase 5)
**Follows:** Phase 4b (living world)

---

## 1. Purpose and scope

Phase 2 built a save layer and tested it thoroughly. Nothing has ever called
it. `grep -rn 'SaveManager' src/presentation scenes` returns nothing: the game
boots into a world, and quitting throws that world away.

Phase 5 closes the loop. A main menu in front of the world, a pause menu
inside it, autosave behind it, and — because this is the first time a save
round-trips through the real game rather than through a test — four defects in
the existing save layer that only a real round trip exposes (§2).

This is the phase that satisfies the Stage 1 headline: *walk around a zone,
quit, come back, the world is exactly as you left it.*

### 1.1 In scope

- Main menu: New World / Continue / Quit, with Continue disabled when no save
  exists and New World confirming before it overwrites one
- Pause menu: Resume / Quit to Menu / Quit to Desktop, both quit paths saving
- Autosave: every 5 minutes, on quit, on focus loss, one `.bak` rotation
- Player position and facing persisted; animals persisted with positions and
  their home anchors
- `meta.json` at the save root, and the four save-layer fixes in §2
- One `Theme` built from the Apollo palette so the menus are not default grey

### 1.2 Out of scope

Multiple worlds and world naming (the `<world_id>` directory level exists on
disk, but Stage 1 always uses `home`). A settings screen, key rebinding, audio,
save thumbnails, threaded saves. Stage 1 has one zone, so "save on zone
transition" has nothing to trigger it.

---

## 2. Four defects the wiring exposes

These are not new work invented for this phase. They are pre-existing faults
that no test could have caught, because every existing test drives the save
layer directly rather than through the game.

### 2.1 The first save of a world writes no chunks

`SaveManager.save_zone` takes `all_chunks: bool = false` and otherwise saves
only `zone.dirty_chunk_coords()`. This is correct policy — rule 5 of the plan
doc's save rules — but nothing in Stage 1 mutates a tile. Building and
harvesting are out of scope, and animal movement writes an entity row, not a
tile. The dirty set is therefore *always empty*, so:

> New World → save → `zones/home/chunks/` is empty → Continue loads a zone with
> zero chunks and paints a black screen.

The first save of a world passes `all_chunks: true`. Every later save keeps the
dirty-only default, which in Stage 1 means it writes `entities.dat` and
`meta.json` and nothing else — a few hundred bytes, comfortably inside the
100 ms budget.

### 2.2 Entity type ids are saved as raw runtime integers

`EntityCodec.encode` writes `store.get_type_id(id)` — the numeric id assigned
by `ContentRegistry` at boot, which shifts whenever content is added.
`SaveManager.load_zone` runs `_translate_column` over `terrain_id`, `floor_id`
and `object_id`, and does nothing whatever to entity rows.

So adding one creature JSON between a save and a load silently reinterprets
every entity in the world. The rabbits become whatever now holds their old
number; the player can become a rabbit.

This is precisely the failure that `CLAUDE.md`'s *"Saves persist string ids,
never runtime numeric ids"* rule exists to prevent. It has survived because
`tests/test_entity_codec.gd` encodes and decodes under one registry, and
`tests/test_save_manager.gd` exercises the remap on tile columns only.

The fix is three lines: `load_zone` already builds the translation table for
the tile columns, and applies it to each restored entity row's `type_id`. A
type id past the end of the table becomes `ContentRegistry.ID_UNKNOWN`, which
is the same placeholder policy the tile columns already use.

**A test must fail before the fix lands:** save under a registry, load under a
registry with an extra creature definition, assert the rabbit is still a
rabbit. Without that test the bug returns the moment someone refactors.

### 2.3 Walkability is not recomputed on load

Recorded as Phase 5's debt at Stage 1 design line 313: `SaveManager.load_zone`
returns the `flags` column verbatim from disk. `flags` is *derived* data —
`terrain.walkable AND NOT object.blocks_movement` — and `ZoneLoader` already
knows not to trust an authored value for it.

A save written before a content change carries stale flags, and the player
walks through a tree or is blocked by open grass. `load_zone` calls
`Walkability.recompute_zone(zone, registry)` after installing chunks, for the
same reason `ZoneLoader` does.

### 2.4 There is no root `meta.json`

`SaveManager` writes `id_map.json` at the save root and `zone_meta.json` per
zone. The Stage 1 design §3.4 specifies a root `meta.json` holding
`save_version`, creation time and playtime, and nothing writes it. Continue
needs *something* to test for existence and to report; §4 defines it.

---

## 3. Where the system sits

```
  MainMenu / PauseMenu        ui/           Control nodes, no logic
           |                                (dumb: emit signals)
           v
        main.gd               presentation/ router: registry, theme,
           |                                UI layer, one World child
    +------+------+
    |             |
    v             v
 GameSession   World          systems/ | presentation/
  (policy)    (the game)
    |
    v
 SaveManager / ZoneLoader     core/
```

The split follows the rule the project has held since Phase 1: everything that
can be decided without a node is decided without one. `GameSession` holds all
the policy — whether a save exists, what New World means, when autosave fires,
how the backup rotates, how playtime accumulates — and is a `RefCounted`, so
every rule in this phase is testable headless in milliseconds. The menus hold
no logic at all; they emit signals and the router calls the session. That is
why not testing the menus costs nothing.

### 3.1 GameSession interface

```gdscript
class_name GameSession
extends RefCounted

const AUTOSAVE_INTERVAL: float = 300.0
## Alt-tabbing repeatedly must not mean saving repeatedly.
const MIN_SAVE_GAP: float = 5.0

var save_root: String = "user://saves/home"  ## injected; tests use a temp dir
var zone: Zone = null                        ## null until a world is open
var player_entity_id: int = 0
var playtime: float = 0.0

func has_save() -> bool
func has_backup() -> bool

## Loads the authored zone from data/ and writes the first save with
## all_chunks = true. Overwrites any existing save: the caller confirms.
func open_new(zone_dir: String, registry: ContentRegistry) -> SessionOpenResult

## Loads from save_root. `use_backup` reads the .bak files instead.
func open_saved(registry: ContentRegistry, use_backup: bool = false) -> SessionOpenResult

## Advances playtime and the autosave clock. Returns true if it saved.
func tick(delta: float, registry: ContentRegistry) -> bool

func save_now(registry: ContentRegistry, reason: String) -> PackedStringArray
func close() -> void
```

`SessionOpenResult` is a small `RefCounted` carrying `ok`, `error`, `zone`,
`player_entity_id`, `player_spawn` and `is_new`, matching the existing
`ZoneLoadResult` / `DecodeResult` / `TilesetBuildResult` pattern. Two entry
points returning two different result types would otherwise force the router to
branch on shape before it can branch on outcome.

### 3.2 The router

`main.tscn` stays the boot scene. `main.gd` shrinks to a router that owns:

- the `ContentRegistry`, built once at boot and reused for the process lifetime
- the `Theme` (§6)
- a UI `CanvasLayer` with `process_mode = WHEN_PAUSED`
- a `World` child, present only while playing

Building the registry and the `TileSet` once — rather than per scene change —
is the reason this phase does not use `change_scene_to_file`. Returning to the
menu frees the `World`; it does not re-parse `data/*.json` or rebuild the atlas.

The router handles three notifications:

| Notification | Action |
|---|---|
| `NOTIFICATION_WM_CLOSE_REQUEST` | save, then quit (§7) |
| `NOTIFICATION_APPLICATION_FOCUS_OUT` | `save_now("focus_lost")`, subject to `MIN_SAVE_GAP` |
| `pause` action pressed | toggle the pause menu |

`get_tree().auto_accept_quit = false` in `_ready`, or the window closes before
the save runs.

### 3.3 World

`presentation/world.gd` is today's `main.gd` almost verbatim — renderer,
entity renderer, collision builder, animal system, player, camera — with one
change: it is handed a `Zone` rather than always loading one from `data/`.

```gdscript
func build(registry: ContentRegistry, result: SessionOpenResult) -> void
```

For a new world it spawns the player at `result.player_spawn`, exactly as
today. For a loaded world the player row already exists; `World` adopts
`result.player_entity_id` instead of spawning a second one. It also seeds
`AnimalSystem` with each animal's restored home anchor (§5).

---

## 4. The save root

```
user://saves/home/
    meta.json            save_version, created, last_played, playtime,
                         zone_id, player_entity_id
    meta.json.bak
    id_map.json
    zones/home/
        zone_meta.json
        chunks/0_0.chunk ... 3_3.chunk      (16 files, written once)
        entities.dat
        entities.dat.bak
```

`player_entity_id` lives in `meta.json` so the router finds the player in O(1)
rather than scanning entity rows for one whose type is `player`. Scanning would
also silently pick the first of two player rows if a bug ever produced two;
naming the id makes that state detectable instead.

**Backup rotation.** `SaveManager.atomic_write` gains an opt-in
`keep_backup: bool`. When set, the sequence is: write `path.tmp`, rename any
existing `path` to `path.bak`, rename `path.tmp` to `path`. A crash in the
one-rename-wide window leaves `path` missing and `path.bak` intact, which is
recoverable and is what `open_saved(use_backup = true)` is for. Defining the
rotation per-file rather than per-directory means it keeps working in Stage 2,
when chunks start changing too — a directory-level rotation would have to copy
the whole world on every autosave.

---

## 5. The animal home anchor, and a correction to Phase 4b

Phase 4b §4.4 decided that no animal state is saved, reasoning that
*"persisting a wander target would mean a format change, a migration and a
fixture test for something the player cannot perceive."* That reasoning is
sound and it still holds — for `target`, `timer` and `mode`. Nobody can tell
that a rabbit forgot it was mid-flee.

`home` is different, and the difference is that it is **authored data**.

`home` is captured lazily from wherever the system first sees the animal
standing. On load the state dictionary is empty, so every rabbit re-anchors to
its current position. Save while a rabbit is fleeing you and its home moves
permanently to wherever it stopped. Repeat across sessions and the eight
rabbits placed in `data/zone/home/zone.json` random-walk away from the spots
they were placed in. That is not an imperceptible detail; it is the authored
world quietly eroding, and it becomes a migration to fix once players own
saves.

So `home` is persisted and the rest of the state is not. Phase 4b §4.4's
conclusion narrows; its reasoning is unchanged.

### 5.1 Entity format v2

| | v1 | v2 |
|---|---|---|
| Row | 18 bytes | 26 bytes |
| Added | — | `home_x: f32`, `home_y: f32` |

Fixed-width columns rather than the reserved `blob_offset`, which Phase 4b
named as the natural home for this. The blob machinery does not exist yet:
`blob_offset` is written as a literal `0` and read back unused. Two floats per
row keeps decode a single fixed stride, and eight rabbits cost 64 bytes.
Building a variable-length blob region to save 64 bytes is the wrong trade.

**Migration.** `Migrations` gains an entity path alongside the chunk path, and
`_migrate_entities_1_to_2` defaults each row's home to its saved **position** —
which is exactly the lazy capture that happens today. A v1 save therefore loads
and behaves identically to the current build, which is the property that makes
the migration safe to trust.

`tests/fixtures/v1_entities.dat` is committed alongside the existing
`v1_chunk.chunk`, generated by extending `tools/make_fixture.gd`. This is the
first time the migration machinery written in Phase 2 actually migrates
anything — worth doing now, while the only save that exists is one a developer
can delete.

---

## 6. Menus and theme

Three `Control` scenes under `src/ui/`, all built in code from a shared theme:

- **`main_menu.gd`** — New World / Continue / Quit. Continue is disabled and
  dimmed when `has_save()` is false, and shows the world's playtime and
  last-played date from `meta.json` when it is true.
- **`pause_menu.gd`** — Resume / Quit to Menu / Quit to Desktop.
- **`confirm_panel.gd`** — an in-scene panel, used for "overwrite the existing
  world?" and for reporting a failed load. Deliberately **not** Godot's
  `ConfirmationDialog`, which spawns a native OS window that behaves badly
  fullscreen and cannot be captured by `tools/screenshot.gd`.

**Theme.** `ui/ui_theme.gd` builds one `Theme` from `StyleBoxFlat`s in eight
Apollo colours, with Godot's built-in font, antialiasing off, at an integer
size. No files land under `assets/`, so no `LICENSE.txt` and no `CREDITS.md`
entry — this phase adds no third-party art.

`tools/check_palette.sh` scans `assets/**.png` and cannot see a `Color` literal
in GDScript, so the palette rule needs its own enforcement here:
`tests/test_ui_theme.gd` loads `tools/palette/apollo.json` and asserts every
colour the theme declares is one of the 46. Same guarantee as the gate, one
test instead of a new CI stage.

Phase 6 replaces the theme's internals — a real pixel font, 9-slice panels —
without touching a menu script.

**Input.** A new `pause` action bound to Escape and gamepad Start, rather than
reading Escape directly. Controller support in Stage 6 is close to free if
everything goes through `InputMap`, and is a rewrite if it does not. Menu
buttons use normal `Control` focus so keyboard and gamepad navigation work
without extra code.

**Pausing** is `get_tree().paused = true`. `World` keeps the default
`PAUSABLE`, so `_physics_process` stops and the animals stop with it; the UI
layer is `WHEN_PAUSED`.

---

## 7. Autosave, quit and failure

| Trigger | Behaviour |
|---|---|
| Every 300 s of unpaused play | `tick()` fires a save |
| Focus lost | Save, unless one ran within `MIN_SAVE_GAP` |
| Quit to Menu | Save, free the `World`, show the main menu |
| Quit to Desktop / window close | Save, then quit |

**A failed save must not be silent, and must not be fatal.** Every save path
returns `PackedStringArray` errors. On a failure the router logs with
`push_error` and shows the message on screen. On the *quit* path a failure
cancels the quit the first time, so the player can act — free some disk, close
the file lock — and a second quit exits regardless. Holding the process hostage
over a full disk is worse than losing the session.

**A failed load must not black-screen.** `Continue` on a failed load stays on
the menu, reports the error, and offers the `.bak` when one exists. The decode
path already distinguishes bad magic, truncation and a too-new version, so the
message can say which.

**An unknown string id** stays a placeholder retaining its original string, per
the existing rule. Nothing in this phase changes that, and §2.2's fix extends
it to entity rows for the first time.

---

## 8. Testing

New: `tests/test_game_session.gd`, `tests/test_ui_theme.gd`.
Extended: `test_entity_codec`, `test_migrations`, `test_save_manager`,
`tools/make_fixture.gd`, `tools/smoke.gd`.

| Test | Asserts |
|---|---|
| `has_save` on an empty root | false, and Continue would be disabled |
| `open_new` writes chunks | 16 `.chunk` files exist — the §2.1 regression guard |
| Autosave clock | fires once at 300 s, not at 299, not twice at 600 |
| `MIN_SAVE_GAP` | two focus-loss saves 1 s apart produce one write |
| Backup rotation | a second save leaves a `.bak`; `open_saved(use_backup)` reads it |
| Playtime | accumulates across a close and reopen |
| Entity v2 | home round-trips; row is 26 bytes |
| v1 fixture | decodes, and home defaults to position |
| **Type id remap** | save under registry A, load under registry B with an extra creature, rabbit is still a rabbit — the §2.2 regression guard |
| Walkability on load | a save with deliberately wrong flags loads with correct ones |
| Theme colours | every declared colour is in `apollo.json` |
| Full-zone save | completes in under 100 ms |
| Chunk payloads | byte-identical through save and load (decompressed, not raw) |

**Tests never touch the real save.** Every test injects
`save_root = "user://test_saves/<unique>"` and removes it afterwards. A test
that wrote to `user://saves/home` would destroy the developer's world on every
run.

`tools/smoke.gd` gains a session round trip: open a new world, move the player,
save, reopen, assert the player is where it was left. The existing smoke test
already round-trips the data layer; this adds the layer above it. **No CI gate
8** — seven gates cover the machine-checkable rules, and the smoke test is
already the thing that catches "it exports but does not run".

The menus are not tested. They emit signals and hold no logic; the logic they
call is covered above.

---

## 9. Cost

| Piece | Size |
|---|---|
| `systems/game_session.gd` + `session_open_result.gd` | ~180 lines |
| `core/save/world_meta.gd` | ~60 lines |
| Save-layer fixes (§2.1–2.4) | ~30 lines across 3 files |
| Entity v2 + migration | ~60 lines |
| `presentation/world.gd` | ~120 lines, nearly all moved from `main.gd` |
| `presentation/main.gd` (router) | ~120 lines |
| `ui/` (3 menus + theme) | ~350 lines |
| Tests | ~450 lines |

The largest single item is UI, which is also the least risky. The riskiest item
is §2.2, which is three lines.

---

## 10. Acceptance criteria

- [ ] New World, walk, quit via the window's X, relaunch, Continue: the player
      is standing where they were left, facing the same way
- [ ] The rabbits are where they were left, and still wander around the spots
      they were authored at rather than around wherever the last save caught them
- [ ] Continue is disabled and dimmed when no save exists
- [ ] New World over an existing save asks first
- [ ] Quit to Menu, then Continue, without relaunching the process
- [ ] A save written under a registry missing a creature added since still
      loads, with the rabbit still a rabbit
- [ ] A truncated `entities.dat` reports an error on the menu and offers the
      backup, rather than crashing or black-screening
- [ ] A full zone save completes in under 100 ms
- [ ] A v1 `entities.dat` fixture loads through the migration
- [ ] All seven CI gates green
- [ ] No menu colour outside the Apollo palette

---

## 11. Risks

| Risk | Severity | Mitigation |
|---|---|---|
| The quit-path save is the one thing not testable headless | Medium | The router's handler is three lines delegating to a tested `save_now`. The wiring itself is covered by the manual play pass and by smoke. |
| `.bak` rotation's two-rename window | Low | A crash inside it leaves the `.bak` intact and `open_saved(use_backup)` recovers. The alternative — copying the save directory per autosave — is worse at Stage 2 scale. |
| A test writes to the real save root | Medium | Injected `save_root` on every session; no default is used in tests. Called out explicitly because the failure is silent and destroys developer worlds. |
| Entity v2 lands before any player owns a save | Low | This is the argument *for* doing it now rather than in Stage 2. |
| Menu scope creeping toward a settings screen | Medium | §1.2. Settings, audio and rebinding are Phase 6. Ideas go in `IDEAS.md`. |

---

## 12. Corrections to earlier specs

**Stage 1 design §10, Phase 5.** Unchanged in substance. The entry gains the
four save-layer defects in §2, which are Phase 5 work because Phase 5 is what
exposes them.

**Stage 1 design line 313.** "Recomputing on load is Phase 5's concern, once
save wiring lands" is discharged by §2.3.

**Phase 4b design §4.4** ("State, and why none of it is saved"). Narrowed:
`home` is persisted, `target`, `timer` and `mode` are not. The section's
reasoning about imperceptible state is unchanged and still governs the other
three. See §5.

**Phase 4b design §4.4** also names `EntityStore`'s `blob` column as the
natural place for persisted animal state. Phase 5 uses fixed columns instead,
for the reason in §5.1; the blob column remains unused and unbuilt.
