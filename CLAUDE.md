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
| `scripts/player.gd` | First-person controller with its own block collision |
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
$G --path . -- --shot=/tmp/a.png                                        # spawn and stand
$G --path . -- --shot=/tmp/f.png --pos=0,100,0 --look=-25,-90 --fly=20  # streaming
$G --path . -- --shot=/tmp/c.png --cave --look=0,-90                    # inside a cave
$G --path . -- --shot=/tmp/m.png --pos=0,100,0 --look=-25,-90 --fly=20 --dist=5 --nothreads  # phone-like
```

`--shot` opens a real window, turns off vsync and player input, waits for the world
to load, measures 5 seconds, saves a PNG, prints one `SHOT` line and quits.
Check after every change: no script errors, `floor=true` in the first command,
the PNGs look right, and `run fps` and `worst frame` did not get worse.

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
