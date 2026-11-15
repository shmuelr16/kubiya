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
| `scripts/main.gd` | Entry point. Builds sky, sun, world, player, HUD. Screenshot hook |
| `scripts/blocks.gd` | Block ids, face-to-tile table, procedural texture atlas |
| `scripts/world.gd` | Block data, terrain generation, chunk meshing and collision |
| `scripts/player.gd` | First-person controller |
| `docs/` | Screenshot now. Later the GitHub Pages site |

The scene tree is built in code. Keep `.tscn` files minimal.

World data is one `PackedByteArray`, index `x + SX * (z + SZ * y)`.
Each 16x16 column chunk is one `ArrayMesh` plus one trimesh collision shape.
Quad winding: `FACE_DEFS` holds `u` and `v` with `u x v = normal`, and corners
go `o, o+v, o+u+v, o+u`. That order is clockwise from outside, which Godot draws
as the front face.

## Run and verify

Godot is at `/Applications/Godot.app/Contents/MacOS/Godot` on the development Mac.

```sh
G=/Applications/Godot.app/Contents/MacOS/Godot
$G --headless --path . --import          # after a clean clone or new assets
$G --path .                              # play
$G --path . -- --shot=/tmp/kubiya.png    # render 90 frames, save a PNG, quit
```

After every change run the `--shot` command, check that it prints no script errors,
and look at the PNG. The line it prints includes `on_floor=true` when collision works.

## Build

Not set up yet. Stage 6 adds `export_presets.cfg`, export templates and a release
workflow. The macOS build must ship as a `.app` inside a `.dmg`.
Update this section when that lands.

## Update flow

Work in stages. The roadmap table is in `README.md`.
At the end of each stage: run and verify, update both README language sections and
this file, commit, push, then report what was done.
