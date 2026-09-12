# RP1 — Phase 4b Design: Living World

**Status:** draft
**Date:** 2026-09-12
**Refines:** `docs/superpowers/specs/2026-08-23-rp1-stage0-stage1-design.md` §10 (Phase 4)
**Follows:** Phase 4a (zone authoring)

---

## 1. Purpose and scope

Phase 4a left a world that is correct and completely still. Eight rabbits stand
in `data/zone/home/zone.json` exactly where they were authored and will stand
there forever. The Stage 1 deliverable is stated as *"a 128x128-tile zone
containing trees, rocks, water, paths, three houses and **wandering
animals**"*, and the animals are the only word in that sentence still unmet.

**The deliverable, stated as a single sentence:** `AnimalSystem` gives every
creature with a wander radius somewhere to go and a reason to run, headlessly
and deterministically, so that "animals wander" is a CI test rather than a
play session somebody performs.

The behaviour is deliberately dumb. This phase validates the entity pipeline
end to end — authored spawn, simulation tick, collision, render — not AI.
Anything cleverer is Stage 5's NPC work and belongs in `IDEAS.md`.

### 1.1 In scope

- `src/systems/animal_system.gd`: wander, flee, return
- Behaviour parameters authored in `data/creature/*.json`, validated by the
  existing schema
- A `_physics_process` in `main.gd` that ticks the system
- Tests, including a per-tick budget test

### 1.2 Out of scope

- **The multi-consumer dirty channel.** See §2.
- Animal persistence. Positions are already entity rows and Phase 5 saves
  them; wander state deliberately is not persisted (§4.4).
- Hunger, sleep, schedules, flocking, predator/prey, pathfinding around
  obstacles. All Stage 5 or later.
- Any change to `MovementSystem` or `CollisionBuilder`.

---

## 2. The dirty channel is cut, and why

The Stage 1 design assigns Phase 4b "a multi-consumer dirty channel, so the
collision cache and `ZoneRenderer` can both react to zone mutation."
`collision_builder.gd:17` explains the problem it solves: `refresh_dirty()`
consumes and clears the zone's dirty flags, so a second subscriber would race
it and whichever ran second would see nothing to do.

**It is cut from this phase, because in Stage 1 nothing produces the event.**

Building, crafting and harvesting are all out of Stage 1 scope. The loader
writes tiles once, at boot, before the first frame — which is why
`ZoneLoader` calls `zone.clear_dirty()` on its way out. Animals move, and
movement is an entity row, not a tile: §3 of the Stage 1 design is explicit
that an animal crossing a chunk boundary is a position update and nothing
else. After this phase, no code path in the shipped game mutates a tile during
play.

Building the channel now would mean a subsystem whose only caller is its own
test suite, carrying a design decision — how subscribers register, whether
they are polled or pushed to, what happens to an event with no subscriber —
made a whole stage before the code that would answer it. `CollisionBuilder`'s
explicit `invalidate()` stays exactly as it is.

This is recorded in the Stage 1 design §10 rather than silently dropped. The
channel moves to Stage 2, beside the building mode that first needs it.

---

## 3. Where the system sits

```
main.gd (_physics_process)            presentation, drives the tick
  └── AnimalSystem.tick(...)          systems/, node-free
        ├── ContentRegistry           reads behaviour from content
        ├── CollisionBuilder          solids_near(), the player's own call
        ├── MovementSystem.move()     one collision implementation
        └── EntityStore               reads and writes positions
```

`AnimalSystem` is a `RefCounted` in `src/systems/`, so the architecture guard
covers it. Every dependency is already node-free.

It is an **instance rather than a set of statics**, for the same reason
`CollisionBuilder` is: it caches per-animal state that would otherwise have to
live in the caller. `MovementSystem`'s purity is the right shape for a
function that resolves one move; it is the wrong shape for something that
remembers where a rabbit was going. The alternative — presentation holding the
dictionary — puts simulation state in the layer that is supposed to hold the
least.

A brain object per animal was rejected: object-per-entity is what §3.4's
struct-of-arrays doctrine and its "no `Node2D` per animal" warning exist to
prevent.

### 3.1 Interface

```gdscript
class_name AnimalSystem
extends RefCounted

var rng: RandomNumberGenerator      ## Injected; a test sets the seed.

## Advances every animal by `delta`. Returns the number that moved.
func tick(
    zone: Zone,
    registry: ContentRegistry,
    collision: CollisionBuilder,
    player_pos: Vector2,
    delta: float
) -> int
```

One entry point. The player's position is passed in as a `Vector2` rather than
an entity id, so the system never has to know which row is the player, and a
test can move a threat around without spawning one.

### 3.2 Collision is the player's collision

Per animal, per tick: choose a desired velocity, then

```gdscript
var area: Rect2 = Rect2(pos - Vector2(2, 2), Vector2(4, 4))
var solids: Array[Rect2i] = collision.solids_near(zone, area)
pos = MovementSystem.move(pos, velocity, delta, body, solids, bounds)
```

This is the same call `Player._physics_process` makes, with the same slack.
Reusing it means an animal cannot walk through a wall the player cannot, wall
sliding comes free, and there is exactly one collision rule in the project.
Facing is set through `MovementSystem.facing_from()`, as the player does.

`body` is `Vector2(body_width, body_height)` from the creature definition
(§5), in tiles, anchored bottom-centre like every other body in the project.
`bounds` is the zone rectangle, so an animal cannot walk off the map edge.

The rejected alternative — testing `zone.is_walkable()` on the destination
tile — is a second, subtly different rule: it ignores body size, so an animal
would clip corners the player cannot, and the difference would surface as a
bug nobody can reproduce.

---

## 4. Behaviour

Three modes. Distance to the player selects between them; nothing else does.

### 4.1 Wander

The animal holds a target drawn uniformly from a disc of `wander_radius`
around its **home anchor**, walks to it at `wander_speed`, and stands still on
arrival until a timer expires, then draws another.

A target on an unwalkable tile is re-drawn, up to `MAX_TARGET_TRIES` (4). After
that the animal dwells. A rabbit enclosed by geometry stands still rather than
spinning through a thousand rejected draws every frame.

The dwell timer is `wander_interval` seconds ±50%, jittered from the same RNG,
so eight rabbits authored identically do not move in lockstep. One authored
number rather than a min/max pair.

### 4.2 Flee

An animal flees only if `flees_player` is true. For one whose value is false
or absent, `flee_radius` is never consulted and the player is scenery — it
wanders and nothing else, which is how a future cow differs from a rabbit
without a line of code.

For one that does flee, the player within `flee_radius` overrides everything:
desired velocity points directly away from the player, at `flee_speed`.

**Fleeing ignores the wander radius.** The alternative — a hard fence — means
a player walking into the radius pins the animal against an invisible wall,
which reads as broken in the first thirty seconds of play.

### 4.3 Return

Once the player is beyond the **calm distance** and the animal is outside its
wander radius, it walks home at `wander_speed` until it is back inside, then
resumes wandering.

Without this, fleeing animals migrate across the map over a long session and
the zone's authored composition quietly drifts.

The calm distance is `flee_radius * CALM_FACTOR` (1.5), derived rather than
authored. With a single threshold, an animal sitting exactly at `flee_radius`
flips mode every tick — visible as a rabbit vibrating in place. This has its
own test.

### 4.4 State, and why none of it is saved

Per animal: `home`, `target`, `timer`, `mode`. Held in a `Dictionary` keyed by
entity id, inside the system.

`home` is captured **lazily**, the first time the system sees an entity, from
wherever that entity currently stands. Animals restored by a Phase 5 load
therefore need no registration call and no load hook — they are simply seen on
the next tick and anchored where the save put them.

Entity ids absent from the store are pruned each tick, so despawning cannot
leak rows into the dictionary.

None of this reaches the save format. `EntityStore`'s `blob` column exists for
exactly this kind of state and stays unused: persisting a wander target would
mean a format change, a migration and a fixture test for something the player
cannot perceive. On reload an animal is where it was left and picks a fresh
target.

### 4.5 Blocked animals re-target

An animal that wanted to move but whose position changed by less than
`STUCK_EPSILON` (0.01 tiles) this tick is blocked by geometry. It draws a new
target immediately rather than pressing into the wall until its interval
expires.

---

## 5. Content

The creature schema **already reserves** `wander_radius` and `flees_player`,
added in 4a and unused. This phase fills them in and extends the same flat
shape:

```json
{
  "category": "creature",
  "required": {"id": "String", "category": "String",
               "display_name": "String", "sprite": "String"},
  "optional": {
    "wander_radius": "int", "wander_speed": "float",
    "wander_interval": "float", "flees_player": "bool",
    "flee_radius": "float", "flee_speed": "float",
    "body_width": "float", "body_height": "float",
    "tags": "Array"
  }
}
```

**Flat fields rather than a nested `wander` block.** `SchemaValidator` checks
the top level only, so a typo inside a nested block — `"radus": 6.0` — would
be silently ignored, which is the exact failure the unknown-field rule exists
to prevent. Flat fields are covered by the validator the project already has,
and the alternative (a sub-schema plus a validation pass inside
`AnimalSystem`) is a subsystem bought to replace a rule we already own.

`data/creature/rabbit.json` gains the new numbers. `data/creature/player.json`
gains nothing.

**Which entities animate is a data question.** `AnimalSystem` animates any
creature whose `wander_radius` is greater than zero. There is no check against
`"rabbit"` anywhere, per the "never `match` over content types" rule: a second
animal is one JSON file plus one PNG, with no code change.

Absent optional fields fall back to constants in `AnimalSystem`. That is
engine behaviour rather than content — the same treatment `ZoneLoader` gives
`biome` and `generation_seed` — and it keeps a half-authored creature moving
rather than motionless with no error.

---

## 6. Testing

Every test is headless and seeded. The Stage 1 claim "animals wander" becomes
something CI can fail.

| Test | Asserts |
|---|---|
| `AnimalSystem` never moves a creature with no `wander_radius` | The player is inert, by data |
| A wanderer stays inside its radius over 600 ticks | Wander is bounded |
| No animal ever ends a tick inside a solid rect | Collision is real |
| An approaching player strictly increases separation | Flee works |
| A fleeing animal may leave its radius | Flee beats the fence |
| It returns inside the radius within a bounded time | Return works |
| Mode does not flicker for an animal held at `flee_radius` | Hysteresis |
| A blocked animal draws a new target | §4.5 |
| An enclosed animal dwells rather than spinning | The retry cap |
| Same seed reproduces identical positions; a different seed does not | Determinism |
| Despawned ids are pruned from the state dictionary | No leak |
| 64 animals tick well inside one frame | §7 |

The budget test follows `test_zone_load_budget.gd`: it builds its own
population rather than using the shipped eight, so the number keeps meaning
something when the zone grows.

No new CI gate. The content is validated by the existing registry tests, and
the behaviour by the suite above.

---

## 7. Cost

Eight animals, each calling `solids_near()` once per physics tick against a
per-chunk cache, is a handful of dictionary lookups and a small array build
per frame. The budget test asserts 64 animals — eight times the shipped
population — stay well inside a 16 ms frame, so the headroom is measured
rather than assumed.

---

## 8. Acceptance criteria

- [ ] Animals visibly move: a before/after screenshot pair with animals in
      different places
- [ ] `./tools/run_tests.sh` green, including every test in §6
- [ ] `tools/guard.gd`, `tools/smoke.gd`, `check_asset_licences.sh`,
      `check_palette.sh` and `check_zone.sh` green
- [ ] 64 animals tick inside the frame budget
- [ ] **Adding a second animal is one JSON file, one PNG and one line in a
      zone's `entities` list, with no code change** — the Stage 1 criterion,
      restated for creatures
- [ ] The Stage 1 design §10 records the dirty channel's move to Stage 2

---

## 9. Risks

- **A one-tick-stale player position.** Animals read the player's position
  from the entity store, and `Player` and `AnimalSystem` both run in
  `_physics_process`, so node order decides whether an animal sees this tick's
  position or last tick's. At 4 tiles/second that is under 7 cm of apparent
  lag. Recorded rather than fixed; fixing it means an ordering contract
  between two nodes for no visible gain.
- **`Player.body` stays an `@export` while an animal's comes from data.** The
  inconsistency is real. Unifying it means touching movement code that Phase
  3b already verified against a real framebuffer, so it waits for a phase that
  has a reason to be in there.
- **Deliberately dumb behaviour may read as broken.** An animal that walks
  into a tree and re-targets looks less intelligent than one that walks
  around it. Pathfinding is explicitly out of scope; if it reads badly in
  play, the answer is a smaller body or a larger retry cap, not A*.

---

## 10. Corrections to the Stage 1 design

§10 currently assigns the multi-consumer dirty channel to Phase 4b. It moves
to Stage 2, for the reasons in §2. The Phase 4b entry becomes `AnimalSystem`
alone.
