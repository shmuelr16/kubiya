# Kubiya

Original 3D block sandbox game. Godot 4.7, GDScript, GL Compatibility renderer.
Targets: macOS, Windows, Android, iOS, web. Public repository, MIT license.

## Hard rules

- No Mojang or Minecraft assets, names, code, sounds or music. Everything is original.
- Textures and audio are generated in code or made by us. Do not add third-party art.
- No Electron. Godot exports native apps.
- Use the GL Compatibility renderer only, so that web and old phones keep working.
- Scripts reference each other with `preload`, not `class_name`, so that a clean
  clone runs from the command line without an editor import.

## Structure

| Path | Purpose |
|------|---------|
| `project.godot` | Engine configuration |
| `scenes/main.tscn` | The only scene. One node with `main.gd` |
| `scripts/main.gd` | Entry point. Builds sky, fog, world, player, HUD. Test arguments |
| `scripts/blocks.gd` | Block ids, face-to-tile table, procedural texture atlas |
| `scripts/terrain.gd` | Terrain generator: height, caves, ores, trees. Thread-safe |
| `scripts/mesher.gd` | Chunk to render arrays, hidden faces removed. Thread-safe |
| `scripts/world.gd` | Chunk manager: worker threads, mesh upload, load and unload |
| `scripts/player.gd` | First-person player: walk, jump, gravity, swim, block collision |
| `scripts/interaction.gd` | Ray through blocks, outline, long-press mining with crack, placing |
| `scripts/items.gd` | Item ids, tool rules, drops, mining time, icon drawing |
| `scripts/inventory.gd` | 36 slots: id, count, tool durability. Slots 0-8 are the hotbar |
| `scripts/crafting.gd` | Shaped recipes, matched anywhere in the grid and mirrored |
| `scripts/inventory_ui.gd` | Inventory and crafting screen, 2x2 and 3x3, mouse and touch |
| `scripts/drops.gd` | Items lying in the world: fall, fly to the player, get collected |
| `scripts/hotbar.gd` | Shows inventory slots 0-8: keys 1-9, wheel, tap |
| `scripts/touch_ui.gd` | Virtual joystick, jump / mine / place / bag buttons, drag to look |
| `scripts/audio.gd` | Synthesised sound effects and generative music |
| `scripts/daynight.gd` | Clock, sky dome shader (sun, moon, stars), global `daylight`, fog colour |
| `scripts/mobs.gd` | The four creatures: models, movement, AI, spawning, combat |
| `scripts/status_hud.gd` | Hearts, hunger, damage flash, defeat message |
| `scripts/selftest.gd` | Automated play test through simulated touch events |
| `docs/` | Screenshot now. Later the GitHub Pages site |

The scene tree is built in code. Keep `.tscn` files minimal.

## World

- Chunk: 16 x 16 x 128 blocks, one byte each, in a `PackedByteArray`.
  Index: `((x + z * 16) << 7) + y`. Neighbours: y is +-1, x is +-128, z is +-2048.
- `terrain.gd` is a pure function of seed and position. A chunk never needs its
  neighbours to generate. Trees use a per-column hash and a 2-block margin, so
  canopies cross chunk borders. Keep new generation features pure in the same way.
- Sea level is 62. Caves are where two 3D noises are both near zero. Columns at or
  near sea level keep a 5-block cap, so water never touches a cave. Water does not flow.
- A chunk is meshed only when its 4 side neighbours have data. A face is drawn when
  the neighbour is air, or water next to a solid block. Leaves are opaque.
- One `ArrayMesh` per chunk: surface for solids, surface for water.
  Vertex data: position, UV, colour. No normals: both shaders are unshaded.
  Vertex colour holds R = face shade, G = sky light, B = block light.
- Quad winding: `FACE_DEFS` holds `u` and `v` with `u x v = normal`, and corners
  go `o, o+v, o+u+v, o+u`. That order is clockwise from outside, which Godot draws
  as the front face.
- Terrain has no physics shapes. `player.gd` tests its box against blocks through
  `world.is_solid()`. Chunks that are not loaded count as solid.
- Load order is nearest first. Data radius is view distance + 1, unload at + 3.
  View distance: 8 chunks on desktop, 5 on mobile and web.

## Player, input, audio

- Input reaches the game in two ways. Keyboard and mouse are read in `player.gd`,
  `interaction.gd` and `hotbar.gd`. Touch goes only through `touch_ui.gd`, which
  exposes `move`, `jump`, `mine`, `place` and `take_look()`. New actions need both.
- `emulate_mouse_from_touch` is off. Touches never arrive as mouse events.
- `world.set_block()` is the only way to edit blocks. It copies the chunk array
  (a worker may still read the old one), keeps edited chunks in memory after unload,
  and queues an urgent re-mesh of the chunk and of the neighbour across a border.
- Add a block: extend the enum and every per-block table in `blocks.gd` (`TILE_OF`,
  `HARDNESS`, `TOOL`, `MIN_TIER`, `SOLID`, `SEE_THROUGH`, `PITCH`), and paint its
  tiles in `make_atlas()`. The atlas is 8 x 8 tiles: 0-31 block faces, 32+ item icons.
- A torch is a block with its own shape in `mesher.gd`. It is not solid, does
  not hide neighbour faces, and emits block light 13.
- A furnace can be crafted and placed. It does not smelt yet.

## Light, day and night

- Light is baked per face in `mesher.gd`, on the worker thread, and never stored.
  The shader does `max(sky * daylight, block)`. `daylight` is a global shader
  value set by `daynight.gd`, so the day cycle costs no re-meshing. Every shader
  that should darken at night declares `global uniform float daylight;`.
  `main.gd` registers that value before anything else: keep it first in `_ready`.
- Sky light: 15 in cells that see the sky, flood-filled inside the chunk, minus 1
  per block, minus 2 per water block straight down. Neighbour chunks feed light in
  only through their open-sky cells. Known limit: light that travelled through a
  neighbour's cave does not continue, so caves that cross a chunk border near an
  entrance can show a seam.
- Block light: flood-filled from torches on a grid padded by 13 blocks, reading
  the 4 side neighbours. Diagonal neighbours count as solid. `world.gd` tracks
  torch cells per chunk and hands the mesher the torches of the 3x3 chunks.
- An edit re-meshes neighbours by reach: 1 block for geometry, 4 when the block's
  transparency changed, 6 when torches are near, 13 when a torch changed.
- Creatures and drops have no baked light. Creatures test for open sky twice a second.
- Minimum brightness is 0.07 in the block shaders. Night daylight is 0.18.
- The sky is one dome mesh that follows the camera. Its shader draws everything.
  The environment has no Sky resource: background and fog take the horizon colour.

## Survival and creatures

- Health and hunger live in `player.gd`: `hurt()`, `eat()`, `stats_step()`.
  Fall damage is the fall height above 3 blocks. Death respawns at `spawn_point`
  with the inventory kept.
- Creatures are our own designs: Mokki, Dundle (passive), Gloomer, Skitter (hostile).
  Do not add creatures that resemble those of any existing game.
  Each is a set of coloured boxes merged into one mesh; alpha 0 marks glowing parts.
  One material per creature, for its light level and hit flash.
- A new creature needs: an enum entry and a row in every per-type table in
  `mobs.gd`, a model in `_mesh_for()`, and a row in both README tables.
- Hostile creatures spawn at night on any solid ground 16 to 30 blocks away, up
  to 8, and dissolve by day. Passive ones spawn by day on grass, up to 6.
- Attacks go through `mobs.pick()` from `interaction.gd`: a creature closer than
  the targeted block takes the hit and the block is not mined.

## Items and crafting

- Item ids below 100 are blocks, with the same id. Ids from 100 are `items.gd` items.
  Add an item: a constant, an icon pattern painted at tile `ICON_BASE + id - 100`,
  and a recipe in `crafting.gd`.
- Do not name a static function `is_tool`: `Script.is_tool()` shadows it when
  called through a preloaded script constant.
- `Items.mine_time()` and `Items.drop_for()` hold all tool rules: matching tool
  type is 3x (wood) or 5x (stone) faster; `MIN_TIER` is the pickaxe tier needed
  for a block to drop anything.
- Mining spawns a drop through `drops.gd`. Placing takes one item from the selected
  hotbar slot. Only block items can be placed.
- Inventory screen rules: tap picks up or puts down a stack; a tap on a crafting
  cell puts down one item; right-click puts down one or picks up half; a tap on the
  result crafts once into the inventory. Closing returns grid and hand to the inventory.
- While a menu is open: `player.ui_open` is true and `touch.enabled` is false.
- Audio is synthesised at startup on a thread, 22050 Hz mono. Music replays two
  instrument samples at different pitches from a sequencer. Do not add audio files.

## Performance rules

Target: 60 FPS on phones.

- Do not use `WorkerThreadPool` for chunk jobs. The engine shares that pool, and
  long jobs in it stalled the main thread for 400 to 850 ms. `world.gd` owns its threads.
- Worker code must not touch nodes or resources. Meshes are created on the main
  thread, inside a 3 ms per frame budget.
- Builds without thread support (web) run one job per frame on the main thread.
- No per-chunk collision meshes, no lit materials, no per-block nodes.
- Measure before and after any change to `mesher.gd`, `terrain.gd` or `world.gd`.

## Run and verify

Godot is at `/Applications/Godot.app/Contents/MacOS/Godot` on the development Mac.

```sh
G=/Applications/Godot.app/Contents/MacOS/Godot
$G --headless --path . --import          # after a clean clone or new assets
$G --path .                              # play
$G --path . -- --selftest=/tmp/kubiya                                   # play test, PASS/FAIL lines
$G --path . -- --shot=/tmp/a.png                                        # spawn and stand
$G --path . -- --shot=/tmp/f.png --pos=0,100,0 --look=-25,-90 --fly=20  # streaming
$G --path . -- --shot=/tmp/c.png --cave --look=0,-90                    # inside a cave
$G --path . -- --shot=/tmp/m.png --pos=0,100,0 --look=-25,-90 --fly=20 --dist=5 --nothreads  # phone-like
```

`--shot` opens a real window, turns off vsync and player input, waits for the world
to load, measures 5 seconds, saves a PNG, prints one `SHOT` line and quits.
`--selftest` checks the rule tables (recipes, drops, tool speed, stacking) and then
the light rules on hand-built chunks, and then plays the game with simulated
touches: joystick, look, jump, mining, item pickup, placing, both crafting screens,
tools, torch, swimming, music, day and night, fall damage, hunger, eating, death,
combat, creature AI and spawning. It must end with `SELFTEST ALL PASS`. It freezes
the clock at noon and turns natural spawning off except where it tests them.
It writes `PATH_crack.png`, `PATH_inventory.png`, `PATH_workbench.png`,
`PATH_torch.png`, `PATH_night.png`, `PATH_torchlight.png`, `PATH_sunrise.png` and `PATH_creatures.png`.
Add a check there for every new mechanic.

Check after every change: no script errors, `SELFTEST ALL PASS`, `floor=true` in
the first `--shot` command, the PNGs look right, and `run fps` and `worst frame`
did not get worse. FPS numbers swing a lot when the Mac is busy: compare against
the previous commit in the same minute before calling something a regression.
A run can hang if a script fails to load, so run tests with a timeout.

Reference on the development Mac (Intel Iris, 2560x1600), stage 2:
load about 3.5 s, 105 to 155 FPS, worst frame after load 14 to 25 ms.
One frame of 300 to 400 ms happens during startup; its cause is not confirmed.
No phone has been measured yet.

## Build

Not set up yet. Stage 6 adds `export_presets.cfg`, export templates and a release
workflow. The macOS build must ship as a `.app` inside a `.dmg`.
Update this section when that lands.

## Update flow

Work in stages. The roadmap table is in `README.md`.
At the end of each stage: run and verify, update both README language sections and
this file, commit, push, then report what was done.
