# eye

A first-person prototype: a wide-FOV **Panini screen-space lens**, a data-driven
config layer, a node-based movement state machine, and a small clarity post-fx
pass. Built to be easy to extend without breaking what already works.

> Entry scene: `world/scenes/world.tscn`. Most tuning lives in
> `core/config/*.tres`. See `misc/docs/ARCHITECTURE.md` for the full picture.

---

## Quick start

```bash
godot --editor          # open the editor (imports assets on first run)
godot                   # run the game
```

Controls: **WASD** move · **Mouse** look · **Space** jump · **Shift** sprint ·
**C** slide · **Q** dash · **Esc** release cursor.

---

## Where do I change…?

Almost every "I want to tweak X" is a config resource. Edit the `.tres` (or in
the editor, select the resource), not the scripts.

| I want to change… | Edit |
| --- | --- |
| FOV (camera *and* lens) | `core/config/player_config.tres` → `base_fov` |
| Panini strength / fill / mode | `core/config/projection_profile.tres` |
| Chromatic aberration, vignette, sampling | `core/config/projection_profile.tres` |
| Lens render resolution / FSR2 vs supersample | `core/config/projection_profile.tres` → `upscale`, `supersample_amount` |
| Post-lens sharpening / grain | `core/config/post_fx_profile.tres` |
| Walk / sprint / accel / friction | `core/config/player_config.tres` |
| Jump, coyote time, var. jump height | `core/config/player_config.tres` |
| Slide / wall-run / dash tuning | `core/config/player_config.tres` |
| Head-bob, tilt, footsteps, mouse sens. | `core/config/player_config.tres` |
| Movement *behaviour* | `player/states/*.gd` |
| HUD contents | `core/ui/hud.gd` + `Hud` in `world/scenes/world.tscn` |

### Adding a system

1. **A new tunable group** → add a `*_profile.gd` (extends `ConfigResource`) +
   `.tres` in `core/config/`, and a small controller in `core/` that calls
   `profile.apply_to(node)` on `_ready()` and on `resource.changed`.
2. **A new movement behaviour** → add one state script under `player/states/`
   and one child node under `States` in `player.tscn`. See
   `misc/docs/ARCHITECTURE.md`.
3. **A new lens effect** → the vendored addon stays untouched; add your own pass
   next to `addons/eye_postfx/`.

---

## Project layout (short version)

```
addons/    third-party (screenspace_projection) + our post-fx + game assets
core/      config resources, controllers, HUD  ("engine-side" glue)
player/    player scene, scripts and movement states
world/     world scene + test map
misc/      docs, tests, backups, tools
```

`addons/screenspace_projection/` is **vendored and read-only**: all its settings
are applied from game code, so it can be updated from upstream safely.

---

## Tests

Headless, no renderer required; both exit non-zero on failure.

```bash
godot --headless --import
godot --headless --script res://misc/tests/smoke_test.gd     # config wiring
godot --headless --script res://misc/tests/movement_test.gd  # physics + states
```

---

## Backups (no VCS in this folder)

This project is not a git repo. Before a risky change, snapshot the source:

```bash
misc/tools/backup.sh before-foo
```

Snapshots land in `misc/backup/NNNN_before-foo/` (plain copies of code, scenes,
config, docs and tests). Godot ignores that folder via `misc/backup/.gdignore`.
To revert a file, copy it back from the snapshot. See `misc/README.md`.
