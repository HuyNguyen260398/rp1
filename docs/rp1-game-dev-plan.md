# Game Development Plan
## Pixel-Art Open-World Sandbox — Godot 4

**Working title:** TBD
**Team:** 1 developer (DevOps background, first game project) + Claude Code + Codex
**Engine:** Godot 4.7 (GDScript)
**Target:** Windows + Linux (Steam Deck comes free), Steam release
**Reference points:** Elin (world model, 2.5D presentation, build mode), Minecraft (creative-building intent)

---

## 1. Design pillars

Three sentences that every future decision gets checked against:

1. **The player builds, and the world remembers.** Persistence is not a feature, it is the product.
2. **Everything is made of pixels, and the player controls them.** Building is placement of pixel-art tiles/objects, not voxel cubes.
3. **The world can always get bigger.** Both in-fiction (the player expands their territory) and technically (the codebase absorbs new content without refactoring).

Anything that doesn't serve one of these does not go in Stage 1.

---

## 2. The single most important design decision

**Copy Elin's world model, not Minecraft's.**

This distinction will save you months, so it's worth being precise about it.

Minecraft is a **seamless infinite world**: one continuous coordinate space, chunks streaming in and out around the player, no loading boundaries. This is a genuinely hard engineering problem — background thread generation, chunk lifecycle management, entity handoff across chunk borders, and constant frame-time pressure.

Elin is a **hub-and-zone world**: a world map of discrete locations, and each location is its own bounded map you enter and leave. Your home base is one zone. A dungeon is another. Travel is a transition, not a stream. Elin is described on Steam as an open-world sandbox RPG, and it *feels* open — but architecturally it's a set of finite maps plus a world map.

**Why the Elin model is right for you:**

| | Seamless (Minecraft) | Zone-based (Elin) |
|---|---|---|
| Chunk streaming while playing | Required | Not required |
| Load times | Must be zero | A 1s transition is fine |
| Save granularity | Complex, incremental | Save the whole zone at once |
| Testable headless | Hard | Easy — a zone is one data structure |
| Time to first playable | Months | Weeks |
| Expandable later | — | Yes, add zones forever |

Expandability comes from **adding zones**, not from growing one map to infinity. A player's home zone can also grow (Elin does exactly this — base level increases usable land). That satisfies your "expandable world" requirement without the streaming problem.

You can still add seamless streaming later. The architecture below keeps that door open by storing world data in chunks *inside* each zone — so the data layer is already chunked even though the loading layer isn't yet.

---

## 3. Technical architecture

### 3.1 The one rule that makes everything else work

**Separate world *data* from world *rendering*, completely.**

```
┌─────────────────────────────────────────────┐
│  Presentation      TileMapLayer nodes,      │  ← Godot nodes, no game logic
│                    Sprite2D, Camera2D       │
├─────────────────────────────────────────────┤
│  Simulation        systems that mutate      │  ← plain GDScript, no nodes
│                    world data               │
├─────────────────────────────────────────────┤
│  World data        Zone → Chunk → Tile      │  ← plain GDScript, no nodes
│                    (source of truth)        │
├─────────────────────────────────────────────┤
│  Persistence       binary chunk files       │
├─────────────────────────────────────────────┤
│  Content registry  JSON definitions         │  ← data, not code
└─────────────────────────────────────────────┘
```

The data and simulation layers must have **zero dependency on Godot nodes** — no `Node2D`, no `TileMapLayer`, no `get_tree()`. Pure `RefCounted` classes operating on arrays and dictionaries.

Three payoffs, all of which matter specifically to you:

- **Headless testing.** `godot --headless --script test_world.gd` can build a zone, place 10,000 tiles, save, reload, and assert equality — with no window, in under a second. Your agents get a real pass/fail signal instead of "looks right in the screenshot."
- **Renderer is swappable.** Going from top-down 2D to Elin-style 2.5D isometric later becomes a presentation-layer change, not a rewrite.
- **Performance escape hatch.** If GDScript becomes the bottleneck at scale, you port the data layer to GDExtension (C++/Rust) without touching gameplay. Nothing else in the codebase changes.

### 3.2 World data model

```
World
 └── Zone (a map: home base, forest, cave, town)
      ├── metadata: id, name, size, biome, generation seed
      └── Chunk[] keyed by Vector2i        (32×32 tiles each)
           └── per tile:
                terrain_id   : u16   (grass, dirt, stone, water)
                floor_id     : u16   (player-placed flooring)
                object_id    : u16   (wall, tree, furniture, machine)
                height       : u8    (elevation — Elin-style)
                flags        : u8    (walkable, blocks light, ...)
```

Store each field as a **separate flat `PackedInt32Array` per chunk**, not as an array of tile objects. 32×32 = 1024 entries per array. Indexing is `y * 32 + x`. This is dramatically faster in GDScript than per-tile objects and serializes trivially.

**Include the `height` field from day one even though Stage 1 renders flat.** Elin's whole visual identity comes from tile elevation. Adding a field to a save format later is painful; carrying an unused byte costs nothing.

### 3.3 Content registry — the expandability lever

Every tile, object, item, and creature is defined in **JSON data files**, never in GDScript enums or hardcoded match statements.

```json
{
  "id": "oak_tree",
  "category": "object",
  "display_name": "Oak Tree",
  "sprite": "res://art/objects/oak_tree.png",
  "sprite_rect": [0, 0, 32, 48],
  "y_offset": -16,
  "blocks_movement": true,
  "blocks_light": true,
  "harvestable": { "item": "wood", "amount": [2, 4] },
  "tags": ["natural", "flammable", "tree"]
}
```

A `ContentRegistry` autoload loads all JSON at boot, assigns numeric runtime IDs, and exposes lookup by string ID.

Three reasons this matters more than it looks:

- **Adding content becomes a data edit, not a code change.** "Add 20 furniture types" is a task Claude Code can complete in one pass and you can validate with a schema test.
- **It is mod support for free.** Elin has a Steam Workshop. Scanning a `mods/` folder for additional JSON gets you most of the way there.
- **String IDs survive save-format changes.** Which brings us to the next section.

### 3.4 Save system

This is the part you asked about specifically, and the part most first projects get wrong.

**Layout:**

```
user://saves/<world_id>/
    meta.json                 save_version, created, playtime, seed, format
    id_map.json               string_id → numeric_id mapping for THIS save
    player.dat
    zones/
        home/
            zone_meta.dat
            chunks/
                0_0.chunk
                0_1.chunk
                ...
            entities.dat
        forest_01/
            ...
```

**Rules, in priority order:**

1. **Version every file.** First 4 bytes of every binary file, and a `save_version` in `meta.json`. Write the migration function skeleton in week one, even when it does nothing. Retrofitting versioning onto an unversioned save format is the kind of problem that kills hobby projects.

2. **Persist string IDs, not runtime integers.** Save `id_map.json` mapping `"oak_tree" → 47` alongside the world. When the player loads a save made before you added 12 new tile types, you remap through the string IDs. Without this, inserting one new tile type corrupts every existing world. This is the single highest-value item on this list.

3. **Never use `load()`, `ResourceLoader`, or `.tres`/`.res` for save data.** Godot resource files can contain script paths, which means loading one executes code. A save file downloaded from a friend or a cloud sync becomes an arbitrary code execution vector. Use `FileAccess` with explicit typed reads/writes, or `store_var(value, false)` — the `false` disables object deserialization and is not optional.

4. **Atomic writes, always.** Write to `chunk.tmp`, `flush()`, `close()`, then `DirAccess.rename_absolute()`. A crash or power loss mid-save must never leave a half-written world. You know this pattern already from infrastructure work; it applies identically here.

5. **Dirty flags, save only what changed.** Each chunk carries a `dirty: bool`. Autosave walks loaded chunks and writes only dirty ones. A player who spent 20 minutes decorating one room shouldn't trigger a full-world write.

6. **Compress chunk payloads.** `FileAccess.open_compressed()` with `COMPRESSION_ZSTD`. Tile arrays are extremely repetitive; expect 10–20× reduction.

7. **Autosave triggers:** zone transition, every 5 minutes, on quit, and on window focus loss. Keep the previous autosave as `.bak` — one rotation is enough.

8. **Separate "what the generator made" from "what the player changed"** *if* you later add procedural zones. Storing a seed plus a diff is far smaller than storing every tile. Not needed for Stage 1 (hand-authored zone), but design the chunk format so a "generated / modified" flag can be added.

**Steam Cloud:** point it at `user://saves/`. Configure in Steamworks once the app exists. Free feature, and players expect it.

### 3.5 Known Godot pitfalls for this specific genre

Be aware of these now; they shape the architecture.

- **`TileMapLayer` issues a redraw when tiles change.** For a building game where tiles change constantly, calling `set_cell()` in a tight loop is slow. Mitigation: batch changes within a frame, mark the affected chunk dirty, and apply once in `_process`. Never call `set_cell` from a loop over thousands of tiles without deferring.
- **Per-tile collision shapes are expensive.** A 32×32 chunk of solid tiles is 1024 colliders. Mitigation: generate merged rectangle colliders per chunk from the data layer (greedy meshing over the walkable flags), rather than using TileMap physics layers. Do this in Stage 2 when you have walls; don't pre-optimize in Stage 1.
- **`set_cell_terrain_connect()` is notably slow in bulk.** Fine for player placement one tile at a time, unusable for generating a whole zone. For bulk fills, compute autotile connections yourself in the data layer.
- **Y-sorting cost.** Turn `y_sort_enabled` on only for the object layer, never for terrain.

None of these are dealbreakers. They're the reason the data/render split in 3.1 is non-negotiable.

---

## 4. Art direction and pipeline

### 4.1 2D vs 2.5D — the decision

**Stage 1: top-down 2D with Y-sorting. Data model carries elevation from the start.**

Elin's look is 2.5D — sprites in a pseudo-isometric space where terrain height creates depth. It's beautiful and it's also a meaningful complexity multiplier: depth sorting with height, occlusion of tall objects, cursor-to-tile picking with elevation, and camera framing all get harder.

Because you keep `height` in the tile data from day one, moving to 2.5D later is a renderer change plus a picking-math change. That's a contained Stage 3 project, not a rewrite. Ship flat first.

### 4.2 Non-negotiable art constants

Decide these once, write them into `CLAUDE.md`, never revisit:

| Constant | Value | Why |
|---|---|---|
| Tile size | **32×32** | Enough room for readable furniture and building detail; 16×16 gets cramped fast for a building game |
| Palette | One fixed palette from Lospec | Mixing palettes is the #1 reason hobby pixel art looks incoherent |
| Character height | 2 tiles (32×64) | Standard for top-down RPG readability |
| Outline style | Pick one (dark outline / selective / none) and enforce it | Mixed outline styles clash worse than mixed colors |
| Texture filter | `Nearest` | Project setting, day one |

### 4.3 Pixel art tools

**Pixelorama — free, and the strongest fit for your specific workflow.** It's an open-source editor **built in Godot itself**, with a full animation timeline with onion skinning and frame tags, tilemap support for rectangular, isometric, and hexagonal grids **with export directly to Godot TileSet resources**, non-destructive layer effects, and a **command-line mode for bulk exports**. It runs on Windows, Mac, Linux, and in the browser — free on itch.io, or $7 on Steam to support the team. One 2026 review put it plainly: if you want a free desktop tool and you're a Godot developer, it isn't even close.

That CLI mode is the part that matters for you. It means asset export can live in your CI pipeline alongside everything else.

**Aseprite ($19.99) — the industry standard, and worth the money.** It remains the professional standard, with an animation workflow, indexed color support, and scripting that are excellent. Critically for agentic work: **Aseprite's Lua API edits sprite frames, layers, and pixels deterministically**, which supports repeatable transformation pipelines. Claude Code can write Lua scripts that batch-process your sprite sheets — recolor a palette across 200 sprites, generate all 8 directional variants, auto-export with consistent naming.

**Recommendation:** start with **Pixelorama** (free, Godot-native TileSet export, CLI). Buy Aseprite when you're doing enough character animation to feel the friction — the Lua scripting is the reason to switch, not the drawing tools.

**Others worth knowing:** LibreSprite (free GPL fork of old Aseprite, lags in features), Piskel (browser, fastest way to draw your first sprite), Krita (good if you already know it), Pixel Studio / Dotpict (mobile/tablet).

**Also install:** [Lospec](https://lospec.com) — palette library and pixel art tutorials. Pick your palette here before you draw anything.

### 4.4 Free asset sources — and the licensing that matters

You will not draw the Stage 1 assets yourself. Use packs, ship a prototype, replace art later once you know what the game needs.

**Tier 1 — CC0, no attribution, zero legal risk:**

- **[Kenney](https://kenney.nl)** — one-person operation, **40,000+ assets, all CC0, no sign-up**. The style is clean and consistent *across packs*, so you can combine a tileset, a UI pack, and input prompts without the art clashing. The **Tiny series (Tiny Town, Tiny Farm, Tiny Dungeon)** and the **Roguelike/RPG pack (1,700+ tiles)** are the relevant ones for you. This is your single best starting point.
  **Not used, in the end.** Every Kenney top-down pixel pack is 16×16 and this project settled on 32×32 (`CLAUDE.md`). The reasoning above is still sound; the size mismatch is the single thing that ruled it out. Phase 3c imported Slates (Ivan Voirol) and Bukket Games' character templates from OpenGameArt instead — both CC-BY, both genuinely 32×32. See `assets/CREDITS.md`.
- **[itch.io CC0 asset filter](https://itch.io/game-assets/assets-cc0)** — 2,700+ packs. Notable CC0 creators: **Pixel Frog**, **Ansimuz**, **0x72** (DungeonTileset II), **Cainos** (top-down RPG tiles).
- **[OpenGameArt](https://opengameart.org)** — the decade-old community archive. Dated UI, variable quality, enormous depth. Filter by license.

**Tier 2 — attribution required, still fine commercially:**

- **[Game-Icons.net](https://game-icons.net)** — thousands of UI and inventory icons, CC-BY 3.0, credit required.
- **Liberated Pixel Cup (LPC)** collection on OpenGameArt — large coherent character/tile set, but **CC-BY-SA: derivative art must carry the same license**. Read that clause carefully before building your character system on it.

**Licensing rules to enforce from day one:**

- **CC0** — public domain, use freely, no attribution. Prefer this for everything.
- **CC-BY** — free commercially, credit required. Fine, but you must track it.
- **CC-BY-SA** — credit required *and* your derivatives must be share-alike. Risky for a commercial game's art.
- **CC-NC** — non-commercial. **Never use.** Excludes a Steam release.

**Maintain `assets/CREDITS.md` from the very first asset import**, with source URL, author, and license per pack. Reconstructing this before a Steam launch when you have 60 packs and no records is a genuinely miserable week. Add a CI check that fails if a new folder under `assets/` lacks a `LICENSE.txt`.

**Communities worth joining:** r/PixelArt and r/gamedev, the official Godot Discord (`#2d` and `#help` channels), Lospec's Discord, and the Pixelorama community.

---

## 5. Repository layout

```
project/
├── CLAUDE.md                   ← agent rules; the highest-leverage file
├── AGENTS.md                   ← same content for Codex
├── project.godot
├── export_presets.cfg
├── data/                       ← content registry JSON (the expandability layer)
│   ├── terrain/
│   ├── objects/
│   ├── items/
│   └── creatures/
├── src/
│   ├── core/                   ← NO Godot nodes allowed in this folder
│   │   ├── world_data.gd
│   │   ├── zone.gd
│   │   ├── chunk.gd
│   │   ├── content_registry.gd
│   │   └── save_manager.gd
│   ├── systems/                ← NO Godot nodes allowed either
│   │   ├── building_system.gd
│   │   ├── inventory.gd
│   │   └── time_system.gd
│   ├── presentation/           ← Godot nodes live here and only here
│   │   ├── zone_renderer.gd
│   │   ├── player.gd
│   │   └── camera.gd
│   └── ui/
├── scenes/
├── assets/
│   ├── CREDITS.md
│   ├── tiles/
│   ├── objects/
│   ├── characters/
│   └── ui/
├── tests/                      ← GUT tests, run headless in CI
└── tools/                      ← export scripts, asset validators, world dumpers
```

The `core/` and `systems/` node-free rule should be **enforced by a CI test**, not just documented. A simple script that greps those folders for `extends Node` and fails the build. Agents drift toward node-based solutions because most Godot tutorials are node-based; a failing test corrects the drift automatically.

---

## 6. Stage 0 — Foundation (Week 1)

No gameplay. Build the machine that builds the game.

| # | Task | Done when |
|---|---|---|
| 0.1 | Godot 4.7 installed, project created, git repo initialized | `git log` has a first commit |
| 0.2 | Project settings: `Nearest` filter, `canvas_items` stretch, integer scaling, window 1280×720 | A test sprite renders crisp at 2× and 3× |
| 0.3 | `CLAUDE.md` + `AGENTS.md` written (see §9) | Both agents follow the conventions unprompted |
| 0.4 | GUT installed, one trivial test passing headless | `godot --headless -s addons/gut/gut_cmdln.gd` exits 0 |
| 0.5 | CI: GitHub Actions runs tests + export on push | Green check on a PR |
| 0.6 | Smoke test: boots headless, runs 300 frames, non-zero exit on any error | Deliberately break something, CI goes red |
| 0.7 | Architecture guard test (`core/` and `systems/` contain no nodes) | Add `extends Node2D` to a core file, CI fails |
| 0.8 | Screenshot capture script (`tools/screenshot.gd`) | Produces a PNG from a headless run |

**0.8 is easy to skip and shouldn't be.** It's the only channel through which your agents get visual feedback. Being able to run the game headless, capture a frame, and paste it back into the conversation closes the loop on the one thing text-based agents can't otherwise see.

---

## 7. Stage 1 — Playable world slice (Weeks 2–7)

**Goal:** walk around a hand-authored zone with trees, houses, and animals; quit; come back; the world is exactly as you left it.

**Explicitly out of scope:** building, crafting, combat, inventory, procedural generation, multiple zones, elevation rendering, NPCs with schedules, day/night.

### Week 2 — Data layer

Pure GDScript, no visuals. This week is entirely testable headless, which makes it the best possible week to calibrate how you work with your agents.

- `Chunk` class with the five parallel arrays
- `Zone` class holding a chunk dictionary keyed by `Vector2i`
- `ContentRegistry` loading JSON from `data/`
- Coordinate helpers: world ↔ chunk ↔ local, with tests for negative coordinates (this is where off-by-one bugs live)
- **Tests:** set/get tiles across chunk boundaries; negative coordinates; registry loads every JSON file and rejects malformed ones

### Week 3 — Persistence

Still headless. Save/load before rendering — reversing this order is how projects end up retrofitting persistence into a system that resists it.

- Binary chunk serialization with version header
- `id_map.json` write/read and remapping on load
- Atomic write via temp + rename
- ZSTD compression
- **Tests:** round-trip a zone with 50,000 random tiles and assert equality; load a save written with an artificially older version; simulate a truncated file and confirm graceful failure; add a new tile type to `data/` and confirm an old save still loads correctly

### Week 4 — Rendering and movement

First time you see anything.

- `ZoneRenderer` reading zone data into `TileMapLayer` nodes (terrain, floor, object layers)
- `CharacterBody2D` player, 8-direction movement, Y-sorted against objects
- `Camera2D` following with pixel snapping and zone-bounds limits
- A 32×32 tileset imported and re-quantized onto the palette, `CREDITS.md` started

### Week 5 — World content

- Hand-author a **128×128 tile** zone (4×4 chunks). Big enough to feel like a place, small enough to finish. Author it as a JSON/PNG-heightmap the game reads, *not* in the Godot editor — that keeps world data in the layer your agents can manipulate.
- Trees, rocks, water, paths, three placed houses (exterior only)
- Collision from the walkable flags in the data layer
- Simple animals: wander within a radius, flee the player. Deliberately dumb — this validates the entity system, not AI.

### Week 6 — Game loop closure

- Main menu: New World / Continue / Quit
- Save on quit, load on continue, autosave every 5 minutes
- Player position and facing persisted
- Animals persisted with their positions
- Pause menu

### Week 7 — Polish and validation

- Ambient audio, footsteps, basic UI frame
- Play it for 30 minutes across several sessions and fix what actually annoys you
- Export Windows and Linux builds via CI
- **Test on a machine that has never had Godot installed** — exported builds break in ways the editor never shows

### Stage 1 acceptance criteria

- [ ] Walk from any corner of the zone to any other, no collision bugs
- [ ] Quit and relaunch: world, player position, and animal positions all restored
- [ ] Save file under 5 MB
- [ ] Zone loads in under 1 second
- [ ] 60 FPS with all chunks loaded
- [ ] Full test suite green in CI
- [ ] Exported build runs on a clean machine
- [ ] Adding a new tree type = adding one JSON file + one PNG, no code change

That last one is the real test of whether the architecture worked.

---

## 8. Stages 2+ — Roadmap

Rough sizing assumes part-time solo work with heavy agent assistance. Treat these as ordering, not deadlines.

### Stage 2 — Building (2–3 months)
The Minecraft pillar. Build mode with a tile cursor, place/remove terrain, floors, walls, and objects. Inventory and a resource economy (chop tree → wood → place wall). Merged chunk colliders replacing per-tile collision. Undo/redo — surprisingly essential for a building game, and much easier to add now than later. Blueprint save/load so players can copy structures.

### Stage 3 — Elevation and 2.5D (1–2 months)
Activate the `height` field. Terraforming tools, height-aware depth sorting, cliff and slope autotiling, elevation-aware picking, roof fade-out when the player is indoors. This is the stage that makes it *look* like Elin.

### Stage 4 — Zones and world expansion (2 months)
World map, multiple zones, transitions, per-zone persistence, one procedurally generated zone type (this is where a generation seed + player-diff save format earns its keep). Base expansion: the player's home zone grows.

### Stage 5 — Simulation depth (3+ months)
The thing that turns a sandbox into a game. Options, pick one or two: NPC residents with needs and schedules, farming and livestock, day/night and seasons, crafting stations, visitors and trade. Elin's depth comes from many small systems interacting; you get there by adding them one at a time, each fully working.

### Stage 6 — Release (2–3 months)
Steamworks integration via GodotSteam, achievements, Steam Cloud pointed at `user://saves/`. Steam page live **early** — wishlists accumulate over months, not weeks. Controller support (already mostly free if you used `InputMap` throughout). Settings, key rebinding, localization scaffolding. Demo build for Next Fest. Then Early Access, which suits this genre — Elin is in Early Access and has been for its whole commercial life.

**A realistic note:** Elin followed Elona, which its developer worked on for roughly 17 years. Cassette Beasts, the flagship Godot open-world pixel RPG, was a funded team. BLASTRONAUT was a solo developer with two years of full-time work who also drew all his own pixel art. Stage 1 is achievable in six weeks. Stages 2–6 are a multi-year project if you go all the way. That's fine — but know which one you're signing up for at each decision point, and treat Stage 1 as a complete deliverable in its own right.

---

## 9. CLAUDE.md starter rules

These belong in the repo root on day one. Agents default to patterns from tutorials, and most Godot tutorials are outdated or node-heavy; explicit rules are how you correct that once instead of every session.

```markdown
# Project conventions

## Engine
- Godot 4.7, GDScript only. No C#.
- Use `TileMapLayer`, never the deprecated `TileMap` node.
- Use `@export` for inspector-facing values; never hardcode `res://` paths in logic.
- Static typing everywhere: `var x: int = 0`, `func f(a: Vector2i) -> void:`.

## Architecture
- `src/core/` and `src/systems/` MUST NOT reference Godot nodes.
  No `extends Node`, no `get_tree()`, no `await get_tree().process_frame`.
  These folders extend `RefCounted` only. This is enforced by a CI test.
- All game content is defined in `data/*.json`. Never hardcode content in
  GDScript. Never write `match tile_type:` over content — look it up in
  ContentRegistry.
- Presentation reads from world data. World data never reads from presentation.

## Persistence
- Never use `load()`, `ResourceLoader`, or `.tres` for save data.
- `store_var()` must always pass `false` for the object parameter.
- Every save file starts with a 4-byte version header.
- All writes are atomic: temp file, then rename.
- Any change to the save format requires a migration function and a test
  that loads a fixture from the previous version.

## Art
- Tile size is 32x32. Character sprites are 32x64.
- Texture filter is Nearest, project-wide. Never override per-texture.
- Palette is fixed — see docs/palette.md. Do not introduce new colors.

## Testing
- Every file in core/ and systems/ has a matching test in tests/.
- Tests must pass headless: `godot --headless -s addons/gut/gut_cmdln.gd`
- New content types require a schema validation test.

## Assets
- Every folder under assets/ has a LICENSE.txt naming source, author, license.
- Never add a CC-NC asset. Flag CC-BY-SA before use.
```

---

## 10. Risks

| Risk | Severity | Mitigation |
|---|---|---|
| **Scope creep into "make Elin"** | Very high | Stage 1 scope is fixed. Keep an `IDEAS.md` and put everything there instead of building it. |
| Building systems forever, never a game | High | Every stage must end in something playable. If a stage has no playable output, it's mis-scoped. |
| Save format churn breaking worlds | High | String IDs + versioning + migration tests, from week 3. Non-negotiable. |
| Art incoherence from mixed packs | Medium | One palette, one tile size, one outline style, all three enforced in CI. Every imported pack is re-quantized onto the palette rather than used as-authored. |
| GDScript performance at scale | Medium | Data/render split means the fix is a contained GDExtension port, not a rewrite. Don't optimize before Stage 2. |
| Agent-generated code drifting from architecture | Medium | CI tests as the enforcement mechanism, not documentation. Tests correct drift automatically; docs don't. |
| Motivation loss around month 3 | High | This is the real killer of solo projects. Ship Stage 1 publicly (itch.io, free) and get a handful of people to play it. External feedback is fuel. |

---

## 11. First three actions

1. Install Godot 4.7 and Pixelorama.
2. Create the repo, and do all of Stage 0 before writing any gameplay code.
3. Pick a palette on Lospec, then a 32×32 tileset that matches it. Check the tile size before downloading — most well-known CC0 top-down packs are 16×16.

Then start Week 2 with the data layer — headless, tested, no visuals. It's the least exciting week and the one that determines whether everything after it is easy or hard.
