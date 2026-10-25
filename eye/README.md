# eye

A first-person prototype: a wide-FOV **Panini screen-space lens**, **one** data-driven
config resource, a node-based movement state machine with **Titanfall-style wall
running, grappling, slamming and sliding**, **health / stamina / overhealth**
combat, **modular weapons** (magazine pistol, sticky grenade, charged sniper,
sword + parry), moving enemy cubes driven by a time-sliced AI director, a
peripheral-vision threat highlight system, and a small clarity post-fx pass.

> Entry scene: `world/scenes/world.tscn`. Every tunable lives in
> `core/config/game_config.tres`. See `misc/docs/ARCHITECTURE.md` for the full
> picture and `misc/docs/AUDIT.md` for the robustness pass and known limits.

---

## Quick start

```bash
godot --editor          # open the editor (imports assets on first run)
godot                   # run the game
```

Controls: **WASD** move (always at run speed) · **Mouse** look ·
**Space** jump / double jump — hold on the ground for extra height, hold after an
air jump to **slam → slide** · **Shift** dash (ground and air; costs stamina) ·
**E** grapple (attach costs stamina) · **LMB** tap = pistol · **hold LMB** = sticky
grenade · **RMB** scope · **LMB while scoped** = charge sniper (instant shot =
quickscope) · **V** quick-switch to the sword and back · **LMB** sword strike ·
**RMB** timed parry · **F** reload · **Q** overhealth stagger burst ·
**F1** toggle enemy AI · **R** reset · **Esc** release cursor. **Slides have no
button**: land fast (easier on ramps) or chain a slam into the floor. There is no
manual crouch.

---

## Where do I change…?

Everything is in **one file**: `core/config/game_config.tres`. Open it in the
inspector (or edit the text), and the sections are grouped exactly like the table
below. No per-system config files.

| I want to change… | Group | Fields |
| --- | --- | --- |
| FOV (camera *and* lens) | Camera | `base_fov` |
| Run / accel / friction | Locomotion | `walk_speed`, `sprint_speed`, `ground_accel`, `air_accel`, `friction` |
| Player health, stamina, regen | Player Vitals | `player_max_health`, `player_max_stamina`, `player_stamina_regen_*`, `player_respawn_delay` |
| Overhealth and stagger burst | Overhealth | `player_max_overhealth`, `overhealth_*`, `burst_*` |
| Jump, double jump, hold height, coyote time | Jump | `jump_velocity`, `jump_hold_*`, `coyote_time`, `jump_buffer_time`, `jump_cut_multiplier`, `air_jumps` |
| Slam / slam-slide chain | Slam | `slam_*` |
| Slide / wall-run / dash | Slide, Wall run, Dash | `slide_*` (incl. slide pose), `wall_*`, `dash_*` |
| Grapple range, reel, pull, swing steering, attach cost | Grapple | `grapple_*` |
| Scope FOV, sensitivity, overlay | Camera, Scope Overlay | `scope_*` |
| Pistol damage / magazine / reload / stamina | Weapons / Pistol | `pistol_*` |
| Sticky grenade hold, throw, fuse, blast, stamina | Weapons / Grenade | `grenade_*` |
| Sniper charge, drop, quickscope, magazine | Weapons / Sniper | `sniper_*` |
| Sword strike, parry window/arc, quickswitch | Weapons / Sword | `sword_*`, `quickswitch_reload_factor` |
| Enemy health, movement, shooting, AI budget | Combat, Enemy AI | `enemy_*` |
| Head-bob, tilt, footsteps, mouse sens. | Camera, Feel | `mouse_sensitivity`, `headbob_*`, `strafe_tilt_degrees`, `step_interval`, `footstep_volume_db` |
| Panini strength / fill / mode | Lens | `projection_mode`, `lens_strength`, `lens_fill` |
| Chromatic aberration, vignette, sampling | Chromatic Aberration, Vignette, Lens Sampling | `ca_*`, `vignette_*`, `lens_max_*` |
| Lens render resolution / FSR2 vs supersample | Lens Resolution | `lens_upscale`, `lens_supersample` |
| Post-lens sharpening / grain | Post FX | `post_fx_enabled`, `sharpen_amount`, `grain_amount` |
| Peripheral threat zones / range / fade | Threat * | `forward_half_angle_deg`, `peripheral_*`, `*_distance`, `highlight_color`, `min_alpha`, `max_alpha` |
| Movement *behaviour* | — | `player/states/*.gd` |
| Weapon *behaviour* | — | `player/weapons/*.gd` + child nodes under `Abilities/Weapons` |
| HUD / scope overlay | — | `core/ui/hud.gd`, `core/ui/scope_overlay.gdshader` |

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
3. **A new optional ability** → extend `PlayerAbility`, add a node under
   `Abilities`, and give it a unique `ability_id`. The player never hard-codes
   the node path.
4. **A new weapon** → extend `WeaponBase`, add one child under
   `Abilities/Weapons`, and implement its input callbacks. Removing that node
   removes the weapon from the loadout.
5. **A new lens effect** → the vendored addon stays untouched; add your own pass
   next to `addons/eye_postfx/`.
6. **A new threat marker style** → replace the ghost material in
   `core/threat_highlighter.gd`; detection and angles stay untouched.

### Combat and traversal in one minute

- **Wall run** uses proactive left/right chest+knee probes, so it starts before
  capsule contact. Entry adds a large tangent-speed burst and a small vault;
  gravity then ramps from nearly zero to normal while the tangent speed bleeds,
  so the player visibly slides down the wall. A wall jump pushes away and boosts
  the tangent speed again.
- **Grapple** is a camera-ray target plus a slow winch. It adds pull toward the
  anchor but never cancels the player's radial/tangential motion, and it gives
  stronger air steering so the player can rotate around the anchor. It does not
  auto-detach when it reels close; release or jump preserves momentum.
- **Slide** has no button. Landing above the engagement speed starts it (the
  threshold drops on downhill ramps), and a slam always chains into one with a
  guaranteed burst even from a straight-down drop. Entry is a large burst, after
  which friction bleeds the slide below sprint speed; downhill ramps add speed
  back. Jump, dash or grapple out at any time.
- **Player vitals**: health and stamina start at 100. Running, jumping, sliding
  and wall-running are free; dashing, grapple attachment, firing and throwing
  spend stamina. Damaging an enemy fills a 50-point **overhealth** buffer, which
  absorbs incoming damage before health. Once the buffer is more than half full,
  **Q** spends all of it on a radial stagger burst that also instantly refills
  every magazine.
- **Pistol** is a low-damage hit-scan tap with a magazine and reload.
  **Grenade** replaces the tap after a short hold, charges throw speed, sticks to
  the first surface it hits, then applies radial falloff damage with a world-only
  line-of-sight check. **Sniper** charges while scoped: low charge is a slow
  projectile with a growing hit sphere; full charge becomes swept-sphere
  hit-scan. A shot in the first fraction of a second after scoping is a
  **quickscope**: an exact camera ray with no drop, spread or velocity
  inheritance. Every normal projectile shot combines **both** the player's
  movement inheritance and gravity (bullet drop). The green scope dot predicts
  from the same origin with the same velocity helper, gravity and speed; the
  full-charge preview uses the same swept-sphere query as the shot.
- **Sword** quick-switches on **V**. **LMB** is a short swept-sphere strike;
  **RMB** opens a timed parry window. A parried enemy shot is negated and the
  shooter is staggered. Switching back halves any reload still in progress.
- **Enemy AI** moves, strafes, checks line of sight and fires at the player.
  `EnemyDirector` round-robins at most one brain per physics tick by default, so
  no two enemies think on the same tick and the cost stays flat as the enemy
  count grows. **F1** toggles all AI without removing bodies or collisions; with
  no director (as in the weapon tests) enemies stay static.
- Optional systems are **drop-in/drop-out nodes**. Deleting `Grapple`,
  `WallSense`, a weapon child, or `EnemyDirector` leaves the rest of the
  player/world running.

---

## Project layout (short version)

```
addons/    third-party (screenspace_projection) + our post-fx + game assets
core/      one config resource, controllers, combat primitives, HUD
player/    player scene, input/context, movement states, abilities, weapons
combat/    reusable hit-scan/ballistic projectiles (sniper, grenade)
enemies/   moving/shooting enemy scene + time-sliced AI director
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
godot --headless --script res://misc/tests/traversal_test.gd # wall-run, wall-jump, grapple
godot --headless --script res://misc/tests/combat_test.gd    # four weapons, reloads, quickscope, parry
godot --headless --script res://misc/tests/threat_test.gd    # peripheral zones + highlighters
godot --headless --script res://misc/tests/world_test.gd     # self-healing + scene health check
godot --headless --script res://misc/tests/vitals_test.gd    # health, stamina, overhealth, burst
godot --headless --script res://misc/tests/enemy_ai_test.gd  # scheduling, movement, shooting, F1
```

---

## Backups (independent of the surrounding checkout)

The `eye` folder is not its own git repo. Before a risky change, snapshot the
source:

```bash
misc/tools/backup.sh before-foo
```

Snapshots land in `misc/backup/NNNN_before-foo/` (plain copies of code, scenes,
config, docs and tests). Godot ignores that folder via `misc/backup/.gdignore`.
To revert a file, copy it back from the snapshot. See `misc/README.md`.
