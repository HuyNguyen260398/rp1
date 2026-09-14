# Phase 5 playtest — session script

**Closes:** Task 18 Step 3 and the Definition of done in
`docs/superpowers/plans/2026-09-12-rp1-phase5-game-loop.md`.
**Rule from Task 18 Step 2, which applies here too:** anything that fails is a
bug fixed *in Phase 5*, not a note carried into Phase 6.

Four sessions, about 45 minutes total. Sessions A-C are scripted and quick;
session D is the twenty minutes of actual play that the tests cannot stand in
for.

Run the game with:

```bash
./tools/godot.sh --path .
```

The save root on this machine:

```bash
SAVE=~/"Library/Application Support/Godot/app_userdata/RP1/saves/home"
```

Several steps below need to see inside the save, because **facing is persisted
but nothing on screen renders it** — `EntityRenderer` draws one texture per
type, with no flip and no directional frames, so a player facing north and one
facing west look identical. Same for a rabbit's home anchor: invisible until it
wanders. `tools/dump_save.gd` prints both, read-only:

```bash
./tools/godot.sh --headless --path . -s tools/dump_save.gd
```

```
zone 'home'  playtime 33.3s  backup present: true
player #9 at (34.03, 13.99) facing N
  #1 rabbit at (32.32, 69.22)  home (30.5, 70.5)
```

---

## 0. Back up the world that is already there — do this first

`$SAVE` already holds a world (16 chunks, `entities.dat`, both `.bak` files).
Session C deliberately truncates a save file, and session B deliberately starts
over the top of one. Copy it somewhere neither can reach:

```bash
cp -R "$SAVE" /tmp/rp1-save-backup-$(date +%s)
```

Restore at any point with `rm -rf "$SAVE" && cp -R /tmp/rp1-save-backup-<stamp> "$SAVE"`.

---

## 1. Verified mechanically on 2026-09-14 — do not re-do by hand

All six local gates exit 0 and CI run `34698936595` is green on `main`, which
is the seventh (export) gate. Suite: **330/330 passing, 34 scripts.**

| Definition-of-done line | Covered by | Result |
|---|---|---|
| A v1 `entities.dat` fixture loads through the migration | `tests/test_migrations.gd:47,66` against `tests/fixtures/v1_entities.dat` | pass |
| A full zone save completes in under 100 ms | `tests/test_save_manager.gd:109`; `tools/smoke.gd` also reported **6 ms** today | pass |
| The first save of a world writes all 16 chunks | `tests/test_save_manager.gd:74` | pass |
| A save under a registry missing a creature still loads, rabbit still a rabbit | `tests/test_save_manager.gd:162`, `tests/test_id_map.gd:59` | pass |
| No menu colour outside the Apollo palette | `tests/test_ui_theme.gd:24` + `./tools/check_palette.sh` | pass |
| No test writes to `user://saves/` | only mention in `tests/` is a path-string assertion in `test_world_meta.gd:6`; nothing opens it | pass |
| All seven CI gates green | `run_tests`, `guard`, `smoke`, `asset_licences`, `palette`, `zone`, export job | pass |

Three of those stay on the manual list below anyway — **missing creature**,
**truncated file**, **16 chunks** — because what the unit tests prove is the
codec, and what sessions B and C prove is that the menu, the router and the
session are wired to it. Different claim, same sentence.

---

## 2. Session A — the round trip (~5 min)

Start from no world at all:

```bash
rm -rf "$SAVE"          # the backup from §0 exists; check that first
```

1. Launch. **Continue is dimmed and does nothing.** → DoD "Continue is disabled
   and dimmed when no save exists"
2. New World. The world opens at the authored spawn, tile `(64.5, 60.5)`.
3. Without leaving the menu-to-world transition, check the first save landed:

   ```bash
   ls "$SAVE/zones/home/chunks" | wc -l   # expect 16
   ```
   → DoD "The first save of a world writes all 16 chunks"
4. Walk somewhere distinctive and far from spawn — a house corner, the pond
   edge. Stop by **walking west and releasing the key**, so the stored facing is
   W and not the S every new player starts on.
5. Close the window with the X. Not the pause menu, not Cmd-Q. The X is the
   path that has no confirmation step in front of it.
6. Before relaunching, record what the save holds:

   ```bash
   ./tools/godot.sh --headless --path . -s tools/dump_save.gd
   ```
   Expect the player's position to match where you stopped, and `facing W`.
7. Relaunch. Continue. The player stands in that spot, and a second run of
   `dump_save.gd` reports the same position and the same facing.
   - → DoD "New World, walk, close the window with the X, relaunch, Continue"
   - Facing is checked here rather than on screen for the reason given above.
     If you would rather see it, that is a Phase 6 art item: directional
     sprites, not a Phase 5 bug.
8. Look at the rabbits. Eight were authored, in pairs, around
   `(30,70) (34,74)`, `(72,44) (78,48)`, `(96,80) (100,86)`, `(50,104) (56,108)`.
   Each wanders within **6 tiles** of its own home anchor. Walk to one pair and
   confirm they orbit *there*, not around wherever you were standing when the
   save was written. `dump_save.gd` prints each rabbit's position next to its
   home, which makes the 6-tile claim checkable rather than eyeballed.
   → DoD "The rabbits are where they were left, and wander around the spots
   `zone.json` authored"

## 3. Session B — the menu rules (~5 min)

Continues from the world session A left behind.

1. From the world, press **Escape**. The pause menu appears. → session D watches
   this more carefully; here just get to it.
2. Quit to Menu. **Continue, without relaunching the process.** The world opens
   again, player intact. → DoD "Quit to Menu, then Continue, without relaunching"
3. Back at the menu, choose **New World** with that save in place. It must
   **ask first** — a confirm panel, not an immediate wipe. Dismiss it. The old
   world must still be there when you press Continue.
   → DoD "New World over an existing save asks first"
4. Now accept it once. A fresh world spawns at `(64.5, 60.5)` with all eight
   rabbits back at their authored pairs.

## 4. Session C — damage and recovery (~10 min)

The backup offer only appears when a `.bak` exists, and `.bak` files are
written from the **second** save onward. So: open the world, play for more than
five seconds (`MIN_SAVE_GAP`), quit to menu — that is save two.

```bash
ls "$SAVE/zones/home/entities.dat.bak"   # must exist before continuing
```

Then truncate the live file, leaving the backup alone:

```bash
python3 - <<'PY'
import os
p = os.path.expanduser("~/Library/Application Support/Godot/app_userdata/RP1/saves/home/zones/home/entities.dat")
with open(p, "r+b") as f:
    f.truncate(os.path.getsize(p) // 2)
PY
```

1. Launch. Press Continue.
   - It **reports the error on the menu** and offers "Load backup". It does not
     crash, and it does not drop you into a half-built world.
   - → DoD "A truncated `entities.dat` reports the error on the menu and offers
     the backup rather than crashing"
2. Dismiss the offer once. You should still be on a usable menu.
3. Press Continue again, accept **Load backup**. The world opens; the rabbits
   are back.

Then the missing-content case, which needs the rabbit taken out of the build
while a save still names it:

```bash
mv data/creature/rabbit.json /tmp/rabbit.json.hidden
```

4. Launch, Continue. The world loads. The rabbits are placeholders — expect
   them to render as whatever the missing-sprite path gives you, **but the save
   must still name them `rabbit`**. Quit to menu, then confirm the string
   survived: `dump_save.gd` prints `rabbit  (PLACEHOLDER — not in this build)`.
   Then put the file back:

   ```bash
   mv /tmp/rabbit.json.hidden data/creature/rabbit.json
   ```
5. Launch, Continue. They are rabbits again, with their sprite and their
   6-tile wander. If they came back as rabbits, the string id survived a resave
   under a registry that had never heard of them.
   → DoD "A save written under a registry missing a creature added since still
   loads, with the rabbit still a rabbit"

> While `rabbit.json` is moved out, `./tools/check_zone.sh` will fail — the
> authored zone references a creature that is not in the registry. That is the
> gate doing its job. Put the file back before running the gates or committing.

## 5. Session D — the twenty minutes (the part only a person can do)

Several sittings, quitting and continuing between them. Three things to watch,
from Task 18 Step 3:

- [ ] **No hitch when the five-minute autosave fires.** The clock is driven by
      accumulated unpaused delta, not the wall clock — sitting in the pause menu
      does not advance it. So: start a 5:00 timer when the world opens, keep
      playing, and watch the frame at 5:00. A save takes ~6 ms headless; if you
      can *feel* it, that is a bug.
- [ ] **The pause menu appears instantly, with the world frozen behind it.** No
      rabbit drifts a pixel while paused. Escape in, Escape out, repeatedly.
- [ ] **Rabbits stay clustered where they were authored**, not drifting toward
      wherever you tend to stand. This is the one a long session exposes and a
      short one does not — flee behaviour (5-tile radius) nudges them, and the
      question is whether they come home afterwards.

Also worth walking, from spec §11, since you are here anyway:

- [ ] Corner to corner across the 128x128 zone with no collision bugs
- [ ] 60 FPS with all 16 chunks loaded
- [ ] The zone opens in under a second from pressing Continue

## 6. Recording the result

Note anything that failed, fix it in Phase 5, then re-run the affected session.

When every box above holds:

```bash
python3 tools/mark_task_done.py 18 --plan docs/superpowers/plans/2026-09-12-rp1-phase5-game-loop.md
```

That ticks **Task 18's** boxes only. The Definition of done is a section
rather than a task, so it is ticked by heading:

```bash
python3 tools/mark_task_done.py --section "Definition of done" \
  --plan docs/superpowers/plans/2026-09-12-rp1-phase5-game-loop.md
```

Both commands tick the whole block at once, so run them only when every line
above has actually passed — not partway through.
