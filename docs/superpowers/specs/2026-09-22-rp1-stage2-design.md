# RP1 — Stage 2 Design: Building

**Status:** draft
**Date:** 2026-09-22
**Refines:** `docs/rp1-game-dev-plan.md` §8, "Stage 2 — Building"
**Builds on:** `docs/superpowers/specs/2026-08-23-rp1-stage0-stage1-design.md`

Stage 1 closed on 2026-09-22. The player can walk a persistent, hand-authored
zone that saves, reloads and makes noise. Stage 2 lets them change it.

---

## 1. Purpose and scope

The roadmap calls this "the Minecraft pillar". The loop it names is
**chop tree → wood → place wall**, and that loop is the whole of Stage 2.

### 1.1 In scope

- Build mode, entered and left deliberately, with a mouse-driven tile cursor
- Placing and removing floors, walls and objects
- An inventory of bulk resource counts
- A resource economy: harvesting yields items, placing spends them
- Greedy-meshed chunk colliders, replacing Stage 1's row merge

### 1.2 Out of scope

Parked to `IDEAS.md`, not forgotten:

- **Undo/redo.** The draft plan argues it is "much easier to add now than
  later" and it is right, which is why §3.2 makes every edit a command
  object. The stack itself is Stage 3 or later.
- **Blueprint save/load.**
- **A controller path for the build cursor.** §3.5 takes on a debt here.
- Everything already parked by Stage 1: elevation rendering, multiple zones,
  procedural generation, NPCs, farming, day/night.

### 1.3 The decision this stage turns on

Stage 1 never mutated a tile during play. Every system that reads world data
was written under that assumption, and two of them quietly depend on it.
Stage 2's first job is not a feature; it is making mutation safe. §3.1.

---

## 2. What Stage 1 already built for this

Three hooks exist, placed deliberately:

| Hook | State at end of Stage 1 |
|---|---|
| `Chunk.floor_id`, `Chunk.flags` | Columns exist, are encoded, decoded and id-translated. **No gameplay consumer.** Floors are this stage's column. |
| `CollisionBuilder.rects_for_chunk()` | Header reads: "Stage 2 replaces the body with greedy meshing behind the same signature." |
| `harvestable` on content | `oak_tree.json` already declares `{"item": "wood", "amount": [2, 4]}`. The ids resolve to nothing today, exactly as sound ids did before Phase 6. |

`data/object/` already holds `wall_stone`, `wall_wood`, `door`, `window`,
`roof_shingle` and `roof_thatch`. The content for building is authored. Only
the interaction is missing.

---

## 3. Architecture

### 3.1 The mutation spine, and the race it removes

`Zone` already exposes the full write API — `set_terrain`, `set_floor`,
`set_object`, `set_height`, `set_flags` — and marks the touched chunk dirty.
The flag is the problem. **Two components clear it today:**

```
src/presentation/zone_renderer.gd:125   p_zone.clear_dirty()
src/core/save/save_manager.gd:100,190   zone.clear_dirty()
```

Under Stage 1 this is harmless: nothing mutates tiles during play, so the
channel is always empty and the first save writes all chunks unconditionally.
The moment building writes a tile it becomes data loss:

> player places a wall → chunk marked dirty → renderer repaints and clears →
> autosave fires, sees nothing dirty → **the wall is never written to disk**

`CollisionBuilder`'s header predicted this and assigned it to "Phase 4", which
never came — Phase 4 moved entities, not tiles. Stage 2 adds a third consumer,
so it is fixed now.

**The fix.** `Chunk.dirty: bool` becomes `Chunk.version: int`, incremented by
every write. Each consumer keeps its own `Dictionary` of chunk coord →
last-seen version and compares. `Zone.clear_dirty()` is deleted.

No consumer can starve another, because none of them clears shared state. The
race is removed structurally rather than sequenced around, and there is no
registration step — which is what `CollisionBuilder`'s header objected to when
it rejected a subscription model.

`Chunk.dirty` is runtime-only. `chunk_codec` never encodes it — it only
assigns it on decode (`chunk_codec.gd:122`, "freshly loaded data matches
disk"), which becomes a version assignment and is the one codec line Phase 7
touches. **The spine therefore needs no save-format change and no
migration.**

*Consequence to handle:* after a load, chunks and consumers both sit at
version 0, so nothing reads as changed. `install_chunk` already declines to
mark loaded chunks dirty and the renderer already has a separate full paint at
zone open. The collider gets the same shape: build-all on open, incremental
after.

### 3.2 Edits are commands

```
BuildCommand   value object: tile, layer, content id, place|remove
BuildSystem    apply(cmd, zone, inventory, registry) -> BuildResult
```

`BuildSystem` is the single place that answers *may this edit happen*: in
bounds, target legal for that layer, affordable, not under the player or an
animal. One rule set, one test file, no rule duplicated in presentation.

Both are `RefCounted` under `src/systems/`, so every rule is testable headless
— the constraint `tools/guard.gd` enforces and the reason Stage 1's systems
are all provable without a scene tree.

Undo/redo is out of scope, but a command object is a handful of lines more
than a direct setter call, and it is what makes the parked feature a stack
rather than a retrofit. This is the one piece of Stage 3 affordance Stage 2
pays for up front, deliberately.

### 3.3 Items, the fifth content category

`ContentRegistry.CATEGORIES` gains `"item"`, with `data/schema/item.json` and
`data/item/wood.json`, `data/item/stone.json`. This is the same one-line
change that added `"sound"` in Phase 6, and the same rule applies: never
`match` over categories, look them up.

*Amended 2026-10-05.* Stage 1 left the `floor_id` column with no content to
put in it: no category, no definition, no sprite. Phase 10b adds `"floor"` as
a **sixth** category, with `data/schema/floor.json`, a schema validation test
and its first definitions. Floors are cosmetic — walkability still comes from
terrain and objects alone, so `Walkability`'s rule does not change.

Placeable content gains an optional `cost`:

```json
{"id": "wall_wood", "category": "object", ...,
 "cost": {"wood": 2}}
```

The economy is authored in `data/`, not written in GDScript. Retuning what a
wall costs is a JSON edit, exactly as retuning the audio mix was.

### 3.4 Inventory and its persistence

`Inventory` in `src/core/`: a string-keyed `Dictionary` of item id → count,
with `add`, `remove`, `can_afford`, `count_of`. No slots, no stack limits —
§1.1. Counts are bulk because a building sandbox spends resources in bulk.

It persists as **its own `inventory.json`**, beside `meta.json` in the save
root, written atomically like every other save file. It does not touch
`chunk_codec` (v1) or `entity_codec` (v2).

That choice earns its keep twice over:

- **A save with no `inventory.json` loads as an empty inventory.** Every
  Stage 1 save opens without a binary migration.
- String keys satisfy the save rule that ids persist as strings, never as
  runtime numerics, with no translation table.

It still gets a committed fixture — a Stage 1 save directory — and a test
proving it opens clean. "No migration needed" is a claim that must fail
loudly if it stops being true.

### 3.5 Build mode and the cursor

`BuildCursor` in `src/presentation/` maps mouse position to a tile. The
project renders at 1280×720 with `stretch/scale_mode="integer"` and 32px
tiles, so screen → tile is a division, not a projection. The cursor
highlights the target and tints by whether `BuildSystem` would accept the
command — the rule is asked, never re-implemented.

`main.gd` routes cursor signals to `BuildSystem`, as Phase 5 established for
menus: presentation emits, the router decides. Presentation stays read-only
over world data, per the architecture rule.

**The debt this takes on.** This is the project's first mouse gameplay input;
`src/` contains none today, only `move_*` and `pause` through `InputMap`. The
draft plan's claim that Stage 6 controller support is "already mostly free if
you used `InputMap` throughout" stops being true for build mode. Recorded
here and in `IDEAS.md` as a known Stage 6 cost, accepted knowingly.

---

## 4. Delivery phases

Five phases (the fourth later split in two), in the shape Stage 1 used: spine, then content, then the loop,
then polish.

### Phase 7 — The mutation spine, and one tile that stays

Version channel replacing `dirty`; per-consumer version maps in renderer,
collider and save; collider incremental rebuild. One hardcoded debug action
places a wall on the tile the player faces. No UI, no mouse, no inventory.

*Done when:* place a wall, quit, relaunch, Continue — the wall is there, it
blocks movement, and the renderer, collider and save all saw it.

### Phase 8 — Items, and an inventory that persists

Fifth content category, schema, `data/item/`. `Inventory` in core.
`inventory.json` with atomic write and the missing-file path. A debug way to
grant wood.

*Done when:* inventory survives relaunch, New World resets it, and a committed
Stage 1 save opens with an empty one.

### Phase 9 — Harvesting: the world into the inventory

`harvestable` resolves. Interacting with a tree removes the object through the
Phase 7 spine and credits wood.

*Done when:* chop a tree, relaunch — the tree is still gone and the wood is
still counted.

### Phase 10 — Build mode: mouse, cursor, palette, cost

Mouse → tile, mode toggle, a palette of placeable content, place and remove
across floor/wall/object layers, `cost` deducted on place and refunded on
remove.

*Amended 2026-10-05.* Split in two, as Phases 3 and 4 were:

- **Phase 10a — build rules and the cursor.** `cost` on content,
  `BuildCommand`/`BuildSystem`, the mode toggle, the mouse cursor, place and
  remove on the object layer, a one-line status readout. Both debug keys go.
- **Phase 10b — palette, inventory display, floors.** A clickable palette
  replacing 10a's wheel selection, a visible inventory, and the `floor`
  category of §3.3 with place and remove on the floor layer.

*Done when (10a):* chop a tree with `E`, then place and remove a wall with
the mouse, and both survive a relaunch.

*Done when (10b):* the same loop, choosing what to build from the palette,
with a floor laid under it.

Chopping stays on `E`. The original line read "entirely with the mouse";
what it meant, and what is built, is that *building* needs only the mouse
once build mode is on.

### Phase 11 — Greedy meshing, and closing Stage 2

`rects_for_chunk()` gets greedy meshing behind its existing signature, tested
against the current row-merge output. Perf pass on a large built structure,
playtest, triage, close.

*Done when:* the acceptance criteria below hold.

---

## 5. Acceptance criteria

- [ ] Place a wall, quit, relaunch, Continue — it is there
- [ ] Remove a placed wall — it is gone, and stays gone across a relaunch
- [ ] Chop a tree, and it does not come back
- [ ] A placed wall blocks movement; removing it unblocks
- [ ] Colliders rebuild incrementally, never fully per edit
- [ ] **No edit is lost when the renderer and an autosave consume changes in
      the same frame**
- [ ] A Stage 1 save opens with an empty inventory and no error
- [ ] Inventory survives relaunch, and New World resets it
- [ ] 1000 placed tiles still hold 60 FPS
- [ ] All seven CI gates green
- [ ] **Adding a new placeable — a new wall with its own cost — is one JSON
      file and one manifest slice, with no code change**

Criterion 6 is §3.1's bug written as something a test can fail on. Criterion
11 extends the Stage 1 claim that the dead tree proved in `abac715`: it now
has to hold for content that participates in an economy, not just content that
renders.

---

## 6. Testing

TDD throughout. Every new file under `core/` and `systems/` gets a matching
test, per the project rules. The load-bearing cases:

| Area | What must be proved |
|---|---|
| `Chunk` | Version increments on write, never decreases |
| `Zone` | Two consumers read changes independently; neither starves the other |
| `BuildSystem` | Every rejection reason, and that a rejected command mutates nothing |
| `Inventory` | Arithmetic, refusal to go negative, `can_afford` boundaries |
| Inventory codec | Round trip; **missing file yields an empty inventory**; a committed Stage 1 fixture opens |
| `CollisionBuilder` | Greedy meshing covers exactly the tiles row merge covered |
| The race | Consume as renderer, then as save; assert both observed the edit |

New content types require a schema validation test — so `item` gets one, as
`sound` did.

---

## 7. Risks

| Risk | Severity | Response |
|---|---|---|
| The dirty-channel change touches renderer, collider and save at once | High | It is Phase 7, alone, with nothing else in it. Its acceptance test is the race itself. |
| Mouse input breaks the InputMap-only property | Medium | Accepted knowingly, §3.5. Recorded in `IDEAS.md` as a Stage 6 cost rather than discovered there. |
| Greedy meshing is the one perf-sensitive algorithm in the stage | Medium | Deferred to Phase 11 behind an unchanged signature. Phases 7–10 run on Stage 1's row merge, which is correct if not optimal. |
| `inventory.json` as a separate file could drift from the world it belongs to | Low | It lives inside the world's save directory, is written by the same atomic path, and is deleted with the world. |
| Scope creep from "while we're in here" building features | Medium | §1.2 is the scope line. `IDEAS.md` is where good ideas wait. |

---

## 8. Corrections to earlier specs

**Stage 1 design §3.2, module boundaries.** Presentation is described as
read-only over world data. That holds, and Stage 2 does not weaken it: the
build cursor emits intent, and `main.gd` routes it to `BuildSystem`. No
presentation node writes to a `Zone`.

**Stage 1 design §11.** Its clean-machine criterion is struck and deferred,
not met — see the Phase 6 plan's Definition of done. Stage 2 inherits that
debt; the VM run remains the last item before a release.

**`CollisionBuilder` header.** It assigns the multi-consumer dirty channel to
"Phase 4". That was wrong — Phase 4 introduced entity movement, not tile
mutation — and the comment should be corrected to name Phase 7 when Phase 7
lands.
