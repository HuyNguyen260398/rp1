# Ideas

Where scope creep waits its turn.

Stage 1 scope is fixed. Anything that is not walking around a persistent
hand-authored zone goes here instead of into the code. Nothing on this list is
a commitment.

## Parked during Stage 1

- Building mode, inventory, crafting (Stage 2)
- Elevation rendering and 2.5D presentation (Stage 3)
- Multiple zones, world map, procedural generation (Stage 4)
- NPC residents, farming, day/night, seasons (Stage 5)
- Steam integration, achievements, controller support (Stage 6)

## Parked during Stage 2

- Undo/redo — edits are already `BuildCommand` objects; the stack is not built
- Blueprint save/load
- **A controller path for the build cursor.** Build mode is mouse-only and
  `build_mode` has no gamepad binding. This is a known Stage 6 cost, accepted
  in the Stage 2 design §3.5, not something to discover there.
- Drag to paint a run of tiles in build mode (10a is one click, one tile)
- Placeable roofs — they need elevation rendering to be anything but a wall
- Doors that open
- A partial refund, or a tool requirement, for removing built things
- A reach limit on building

## Unsorted
