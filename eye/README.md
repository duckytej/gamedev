# eye

A first-person prototype: a wide-FOV **Panini screen-space lens**, **one** data-driven
config resource, a node-based movement state machine, a peripheral-vision threat
highlight system, and a small clarity post-fx pass.

> Entry scene: `world/scenes/world.tscn`. Every tunable lives in
> `core/config/game_config.tres`. See `misc/docs/ARCHITECTURE.md` for the full
> picture.

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

Everything is in **one file**: `core/config/game_config.tres`. Open it in the
inspector (or edit the text), and the sections are grouped exactly like the table
below. No per-system config files.

| I want to change… | Group | Fields |
| --- | --- | --- |
| FOV (camera *and* lens) | Camera | `base_fov` |
| Walk / sprint / accel / friction | Locomotion | `walk_speed`, `sprint_speed`, `ground_accel`, `air_accel`, `friction` |
| Jump, coyote time, variable height | Jump | `jump_velocity`, `coyote_time`, `jump_buffer_time`, `jump_cut_multiplier` |
| Slide / wall-run / dash | Slide, Wall run, Dash | `slide_*`, `wall_*`, `dash_*` |
| Head-bob, tilt, footsteps, mouse sens. | Camera, Feel | `mouse_sensitivity`, `headbob_*`, `strafe_tilt_degrees`, `step_interval`, `footstep_volume_db` |
| Panini strength / fill / mode | Lens | `projection_mode`, `lens_strength`, `lens_fill` |
| Chromatic aberration, vignette, sampling | Chromatic Aberration, Vignette, Lens Sampling | `ca_*`, `vignette_*`, `lens_max_*` |
| Lens render resolution / FSR2 vs supersample | Lens Resolution | `lens_upscale`, `lens_supersample` |
| Post-lens sharpening / grain | Post FX | `post_fx_enabled`, `sharpen_amount`, `grain_amount` |
| Peripheral threat zones / range / fade | Threat * | `forward_half_angle_deg`, `peripheral_*`, `*_distance`, `highlight_color`, `min_alpha`, `max_alpha` |
| Movement *behaviour* | — | `player/states/*.gd` |
| HUD contents | — | `core/ui/hud.gd` + `Hud` in `world/scenes/world.tscn` |

`GameConfig.validate()` checks impossible combinations (e.g. `near_distance >
far_distance`, `base_fov` out of range). The world root logs problems on startup
and the smoke test fails on them.

### Adding a system

1. **A new tunable** → add one `@export` to `core/config/game_config.gd` in the
   right `@export_group`, then read it where it is needed. Add a rule to
   `validate()` if invalid values would be confusing. Do **not** create another
   `.tres` file or copy the value into a runtime field.
2. **A new movement behaviour** → add one state script under `player/states/`
   and one child node under `States` in `player.tscn`. See
   `misc/docs/ARCHITECTURE.md`.
3. **A new lens effect** → the vendored addon stays untouched; add your own pass
   next to `addons/eye_postfx/`.
4. **A new threat marker style** → replace the ghost material in
   `core/threat_highlighter.gd`; detection and angles stay untouched.

---

## Project layout (short version)

```
addons/    third-party (screenspace_projection) + our post-fx + game assets
core/      one config resource, controllers, threat detection, HUD
player/    player scene, scripts and movement states
world/     entry scene, map, and the world root health check
misc/      docs, tests, backups, tools
```

`addons/screenspace_projection/` is **vendored and read-only**: all its settings
are applied from game code, so it can be updated from upstream safely.

---

## Tests

Headless, no renderer required. The runner fails on test failures **and** on
GDScript/engine errors, which Godot itself would otherwise report with exit 0.

```bash
misc/tests/run_all.sh
```

Run one suite directly:

```bash
godot --headless --script res://misc/tests/smoke_test.gd     # config + scene wiring
godot --headless --script res://misc/tests/movement_test.gd  # physics + states
godot --headless --script res://misc/tests/threat_test.gd    # peripheral zones + highlighters
godot --headless --script res://misc/tests/world_test.gd     # self-healing + scene health check
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
