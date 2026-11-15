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
  Vertex data: position, UV, colour. No normals: both shaders are unshaded and the
  per-face shade is baked into vertex colour. `daylight` is a shader uniform.
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
- A torch is a block with its own shape in `mesher.gd`. It is not solid and does
  not hide neighbour faces. It gives no light yet: there is no lighting system.
- A furnace can be crafted and placed. It does not smelt yet.

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
plays the game with simulated touches: joystick, look, jump, mining, item pickup,
placing, both crafting screens, tools, torch, swimming, music. It must end with
`SELFTEST ALL PASS`. It writes `PATH_crack.png`, `PATH_inventory.png`,
`PATH_workbench.png` and `PATH_torch.png`. Add a check there for every new mechanic.

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
