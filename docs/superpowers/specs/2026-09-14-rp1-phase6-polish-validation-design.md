# RP1 — Phase 6 Design: Polish and Validation

**Status:** accepted
**Date:** 2026-09-14
**Refines:** `docs/superpowers/specs/2026-08-23-rp1-stage0-stage1-design.md` §10 (Phase 6)
**Follows:** Phase 5 (game loop closure)

---

## 1. Purpose and scope

Phase 6 is the last phase of Stage 1. After it, the headline is met and the
stage is a finished deliverable in its own right: *the player walks around a
128x128 zone, quits, relaunches, and the world is exactly as they left it* —
now with sound, and proven on a machine that has never had Godot on it.

Three quite different kinds of work sit in this phase, and it is worth being
honest that only the first is engineering:

1. **Audio** — the first the project has ever had. A new subsystem, built to
   the same rules as every other: policy in `src/systems/`, playback in
   `src/presentation/`, content in `data/`.
2. **A small amount of in-world UI** and a volume control, which is the
   smallest settings surface that is not hostile to a player.
3. **Validation** — the play-and-fix pass and the clean-machine export test.
   These produce findings and fixes rather than features, and the discipline
   they need is a triage rule (§7), not an architecture.

### 1.1 In scope

- An ambient bed per zone, and footsteps that match the terrain underfoot
- `user://settings.json`: master volume, mute, and the controls-hint flag
- A master volume slider and a mute toggle on the existing pause menu
- Three pieces of in-world UI: a save indicator, a zone title card, and a
  first-run controls hint
- A 30-minute play-and-fix pass across several sittings, with every finding
  triaged (§7)
- The exported build run on a clean VM (§8)

### 1.2 Out of scope

Music. An ambient bed is not a soundtrack, and a composed one is a Stage 2+
commitment that would not be finished in this phase. Also out: positional or
3D audio, creature sounds, UI click sounds, an options screen, key rebinding,
a macOS export preset (§12), and everything already parked in `IDEAS.md`.

Phase 5's §1.2 listed "a settings screen, key rebinding, audio" as out of
scope *for Phase 5*. Audio and a two-control settings surface arrive here; a
settings **screen** does not.

---

## 2. Where audio sits

The same split as Phase 5's `GameSession`/`World`, for the same reason: every
rule that can be wrong should be testable without a window.

| File | Responsibility |
|---|---|
| `src/systems/audio_cue.gd` | One cue: `sound_id`, `variation`, `gain_db` |
| `src/systems/audio_director.gd` | Every rule: cadence, terrain selection, variation, bed, volume, mute |
| `src/presentation/audio_stage.gd` | Drains cues into `AudioStreamPlayer`s. Holds no rules |

### 2.1 AudioDirector interface

```gdscript
## Resolves sound ids against content. Called once per world.
func configure(registry: ContentRegistry) -> void

## Sets the bed for the zone being entered. "" is a valid ambient id and
## means silence, which is how a zone opts out rather than by omission.
## Idempotent: entering the zone already playing changes nothing, so a
## repeated call cannot restart the bed mid-breath.
func enter_zone(zone_id: String, ambient_sound_id: String) -> void

## The whole per-frame rule. `distance_moved` is what the player actually
## travelled after collision resolution; `terrain_id` is the tile under
## their feet. Returns the cues to play this frame, usually empty. At most
## one footstep per call, so a long frame cannot fire a burst.
func tick(distance_moved: float, terrain_id: int) -> Array[AudioCue]

func set_master_volume(v: float) -> void   ## 0.0-1.0
func set_muted(m: bool) -> void

## The bed that should be playing, as a cue, or null for silence.
func bed() -> AudioCue
```

**A cue carries its final level.** `variation` indexes into the sound's
`streams`, and `gain_db` is the sound's authored `gain_db` plus the master
volume converted to decibels. The director folds the two together so that
`AudioStage` never computes a level and there is exactly one place where the
mix can be wrong. The bed is a cue for this reason rather than a bare id:
otherwise master volume would have to be applied to it somewhere else.

**Muting emits nothing.** `tick()` returns an empty array and `bed()` returns
`null`, rather than everything playing at -80 dB. Silence is then a policy
decision a test can assert, and a muted game does no audio work at all.

**The bed belongs to the world, not to the session.** `AudioStage` is a child
of `World` and is freed with it, so returning to the main menu stops the
ambience and Continue starts it again. The router must therefore reset the
director on the way out (`enter_zone("", "")`), or the next Continue takes the
idempotent path and hands the new stage no bed at all. Idempotence guards
against a repeated `enter_zone`; the reset guards against a stale one.

### 2.2 AudioStage

A `Node` under `World`. It keeps a small pool of `AudioStreamPlayer`s for cues
and one more for the bed, and resolves `sound_id` to an `AudioStream` through
the registry, guarding with `ResourceLoader.exists()` before `load()` and
caching the result in a `Dictionary` — the pattern already used by
`entity_renderer.gd:_texture_for` and `tileset_builder.gd`. `load()` on an
authored `res://` asset is not what the persistence rules forbid; those govern
save data.

`World` calls `tick()` from the `_physics_process` that already moves the
player, and hands the cues to `AudioStage`. That is the entire wiring.

---

## 3. Footsteps are driven by distance, not by a timer

`player.gd` already computes `moved`, the *resolved position* after
`MovementSystem` has applied collision — so the distance actually travelled is
`pos.distance_to(moved)`, one line at a call site that already exists. The
director accumulates that and emits a step every `STEP_DISTANCE` tiles.

**Start at 1.6 tiles**, then tune by ear in §7. The arithmetic matters more
than the figure: the player's `speed` is 4.5 tiles per second, so 1.6 tiles is
a step every 0.36 s — a jog, at about 2.8 steps a second. A more intuitive
0.9 would give five steps a second, which is a sprint bordering on a drum
roll. Any retune should be done against this sum rather than by taste alone.

Every case a timer gets wrong falls out of this for free:

- diagonals are already normalized, so they do not step faster
- sliding along a wall steps more slowly, because less ground was covered
- walking into a tree steps not at all
- standing still is silent with no special case

The terrain id under the player selects the sound. A terrain with no
`footstep` field is **silent** — so water, and any content added later, is
quiet by default rather than by an omission bug.

**A variation is never played twice in a row.** The same sample repeating is
the most audible flaw in cheap footstep audio, and it costs one stored index
to avoid.

---

## 4. The audio data model

### 4.1 A fourth content category

`sound` is appended to `ContentRegistry.CATEGORIES`. Appended, not inserted:
the loop assigns numeric ids in category order, so adding to the end leaves
terrain, object and creature ids undisturbed. (Saves persist strings and
translate through `id_map.json`, so this would be survivable either way — but
there is no reason to shift them.)

```json
{"id": "step_grass", "category": "sound", "display_name": "Grass footstep",
 "streams": ["res://assets/audio/step_grass_1.ogg",
             "res://assets/audio/step_grass_2.ogg",
             "res://assets/audio/step_grass_3.ogg"],
 "gain_db": -6.0, "loop": false}
```

`streams` is a list so a sound can have variations without a schema change per
sound. `gain_db` is where the mix lives: relative levels between the bed and
footsteps are data, not code. `loop` is true for beds and false for one-shots.

### 4.2 Schema changes

New: `data/schema/sound.json`, with a matching `tests/test_sound_schema.gd`,
as the content rules require for a new type.

Additive and optional, so every existing JSON file stays valid unchanged:

- `terrain` gains `footstep: String` — a sound id
- `zone` gains `ambient: String` — a sound id

The schema validator rejects unknown fields, so these two must be declared
before any content file uses them.

### 4.3 Assets and licensing

`assets/audio/`, with a `LICENSE.txt` naming source, author and licence, and a
`CREDITS.md` entry written **at import time**. `check_asset_licences.sh`
already enforces the first of those.

**CC0 or CC-BY only.** The CC-NC ban is absolute — it excludes a Steam release.
CC-BY-SA is to be flagged before a pack is committed to, exactly as for art.
Audio is not palette-quantized and is not walked by `check_palette.sh`, which
only reads PNGs.

---

## 5. The UI frame

`§10`'s "basic UI frame" is made concrete as three pieces, all in `src/ui/`,
all read-only, all themed by the existing `UiTheme`:

| Piece | Behaviour | Why it earns its place |
|---|---|---|
| Save indicator | A "Saved" label fading in and out when `GameSession` reports a save | The only one carrying information the player cannot get any other way. Autosave is otherwise invisible, and invisible autosave is not trusted |
| Zone title card | The zone's `display_name` fading in on entry, out after a few seconds | "Home Valley" is authored and persisted in `zone_meta.json`. It gives the place a name at the moment the player arrives |
| Controls hint | WASD / Esc, shown once, gated on `controls_hint_shown` | On the clean VM there is nobody to ask which keys move |

None hold rules, so none are tested (§9) — the same reasoning that left the
Phase 5 menus untested.

---

## 6. Settings

`src/core/settings.gd` and `tests/test_settings.gd`, mirroring `world_meta.gd`:

```json
{"version": 1, "master_volume": 0.8, "muted": false, "controls_hint_shown": false}
```

Plaintext JSON, written through the existing `SaveManager.atomic_write`, read
through a decode guard that falls back to defaults on anything malformed —
a corrupt settings file must never block the game from starting.

**It lives at the `user://` root, not under `saves/home/`.** Settings must
survive New World, and a world that has to be deleted must not cost the player
their volume. This is a second persistence surface and is deliberately the
smallest one that can exist.

The pause menu gains a slider and a mute toggle. The menu emits signals; the
router calls the director and writes the file. No logic in the menu, as in
Phase 5.

**No extra audio buses.** With only a master volume exposed, Music/SFX buses
buy nothing that per-sound `gain_db` does not already give, and they would
need either a `default_bus_layout.tres` or runtime `AudioServer` wiring for no
benefit. Master only.

---

## 7. The play-and-fix pass

Thirty minutes across several sittings, per `§10`. The output is a findings
list in `docs/playtests/`, following the Phase 5 script's convention.

**Every finding is triaged into exactly one of three buckets:**

| Bucket | Test |
|---|---|
| **Fix now** | It annoys, it is in Stage 1 scope, and it is cheap |
| **`IDEAS.md`** | It is Stage 2 wearing a disguise |
| **Won't fix** | With the reason written down |

The phase does not close while a finding is unclassified. This bullet is the
one in the whole stage with no natural limit — "fix what actually annoys" can
absorb a year — so the triage rule *is* the limit, and "it annoys me" is not
by itself sufficient to make something Stage 1 work.

---

## 8. The clean-machine test

A fresh Ubuntu or Windows VM that has never had Godot or its export templates
installed. The artifact under test is **the zip CI produced**, not a local
export — a local build shares the developer machine's import cache, which is
exactly the difference that hides export bugs.

Walk the Stage 1 headline on it: New World, walk around, quit, relaunch,
Continue. Specifically checked, because these are the failures that only ever
appear in an exported build:

- audio actually plays (a missing or mis-imported `.ogg` is the classic one)
- the window opens at a sane size on a display that is not this Mac's
- the save lands in the OS's real user-data directory and survives relaunch
- no console spam, and no missing-resource errors

---

## 9. Testing

Headless, in `tests/`:

- **`test_audio_director.gd`** — cadence accumulates distance and emits at the
  threshold; no movement emits nothing; a terrain without a `footstep` is
  silent; the sound follows the terrain under the player; a variation never
  repeats consecutively; mute silences both cues and bed; `enter_zone` on the
  zone already playing leaves the bed untouched; master volume is folded into
  every cue's `gain_db`
- **`test_sound_schema.gd`** — a minimal valid sound validates; each required
  field is required; an unknown field is rejected; the wrong category is
  rejected
- **`test_settings.gd`** — round trip, defaults, malformed input, and that a
  missing file yields defaults rather than an error

`AudioStage` and the three UI pieces get no tests: they hold no rules. The
`Theme`, the menus and the renderers are already precedent for this.

---

## 10. Cost

| Piece | Size |
|---|---|
| `systems/audio_director.gd` + `audio_cue.gd` | ~150 lines |
| `presentation/audio_stage.gd` | ~90 lines |
| `core/settings.gd` | ~60 lines |
| `sound` category + schema + content files | ~40 lines, mostly JSON |
| `ui/` (indicator, title card, hint) + pause menu controls | ~180 lines |
| Tests | ~250 lines |
| Audio assets | Sourcing and licensing, not lines |

The engineering here is small. The phase's real cost is §7 and §8, which are
measured in sittings rather than lines.

---

## 11. Acceptance criteria

- [ ] Footsteps match the terrain underfoot, and change when the terrain does
- [ ] No footstep while standing still, none while walking into a solid, and
      no faster cadence on a diagonal
- [ ] The same footstep variation never plays twice in a row
- [ ] The ambient bed loops without an audible seam
- [ ] Mute is actually silent, and master volume moves the level
- [ ] Volume and mute survive a relaunch, and survive New World
- [ ] A malformed `settings.json` starts the game at defaults rather than
      failing to start
- [ ] The save indicator appears when autosave fires
- [ ] The zone title card shows the authored `display_name` on entry
- [ ] The controls hint appears on a first world and never again
- [ ] Every play-pass finding is triaged to fix-now, `IDEAS.md`, or won't-fix
- [ ] The CI-produced zip runs on a VM that has never had Godot, all the way
      through New World → walk → quit → relaunch → Continue
- [ ] All seven CI gates green
- [ ] Every Stage 1 acceptance criterion in the stage design §11 still holds

---

## 12. Risks and known limitations

| Risk | Severity | Mitigation |
|---|---|---|
| "Fix what annoys" absorbs unlimited time | **High** | §7's triage rule. Findings are classified, not merely collected |
| Audio asset sourcing stalls the phase | Medium | Only two kinds of sound are needed: one bed and a handful of footsteps. CC0 packs cover both. Licence rules are checked before import, not after |
| An export-only audio failure is found late | Medium | §8 tests the CI artifact specifically, and audio is the first thing checked there |
| Scope creep from a volume slider to an options screen | Medium | §1.2 and §6. Two controls, on a menu that already exists |
| Mixing by ear on one pair of headphones | Low | `gain_db` is data, so a remix is a JSON edit and not a code change |

**Known limitation, recorded rather than hidden:** `export_presets.cfg` has
Linux and Windows only, and no macOS preset is added here. The developer
machine is a Mac, so *no exported build can be run outside a VM at all*. Export
regressions are therefore invisible between VM sessions — CI proves the export
completes, not that it runs. Adding a macOS preset is the obvious fix and is
deliberately deferred; if export breakage recurs, revisit that decision first.

---

## 13. Corrections to earlier specs

**Stage 1 design §10, Phase 6.** "Basic UI frame" is made specific by §5 —
three named pieces, not a HUD. "Ambient audio, footsteps" is unchanged. "Export
Windows and Linux via CI" was delivered early, in Phase 5's `ci: teach the
export gate to open a world`; what remains of that bullet is §8.

**Phase 5 design §1.2.** Listed "a settings screen, key rebinding, audio" as
out of scope. Audio and a two-control settings surface land here; a settings
screen and key rebinding remain out of scope for Stage 1 entirely.
