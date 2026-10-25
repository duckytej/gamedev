# Architecture

A first-person prototype with a wide-FOV Panini ("screen-space projection") lens,
**one** data-driven config resource, a node-based movement state machine, modular
abilities/weapons, health/stamina/overhealth, and a time-sliced enemy AI director.
The goal is that **every tunable lives in one file** and **every behaviour is one
small drop-in node**, so adding or removing systems does not require editing
existing ones.

---

## Folder map

```
eye/
├── addons/
│   ├── assets/                  game art + audio (imported by Godot)
│   ├── eye_postfx/              our post-lens clarity pass (shader)
│   └── screenspace_projection/  VENDORED addon — treat as read-only
├── core/
│   ├── config/
│   │   ├── game_config.gd       THE config class + validate()
│   │   └── game_config.tres     THE config values (single source of truth)
│   ├── combat/
│   │   ├── damage.gd            central health lookup + damage routing
│   │   └── health_component.gd  reusable health for enemies/future actors
│   ├── peripheral/
│   │   └── threat.gd            one detected threat (data only)
│   ├── physics_layers.gd        named World/Player/Enemy/Projectile layers
│   ├── projection_controller.gd pushes lens fields into the addon
│   ├── post_fx_controller.gd    pushes post-fx fields into the material
│   ├── threat_detector.gd       scans, classifies, raycasts LOS
│   ├── threat_highlighter.gd    draws folded red silhouettes
│   └── ui/
│       ├── hud.gd               stats, vitals, crosshair, scope, weapon status
│       └── scope_overlay.gdshader
├── combat/
│   └── projectiles/             reusable Projectile, grenade, sniper scenes
├── enemies/
│   ├── enemy_cube.tscn/.gd      moving/shooting target + health/stagger
│   └── enemy_director.gd        time-sliced AI scheduler + F1 toggle
├── misc/
│   ├── backup/                  timestamped source snapshots (Godot ignores these)
│   ├── docs/                    this document
│   ├── tests/                   headless tests + run_all.sh
│   └── tools/backup.sh          snapshot helper
├── player/
│   ├── scenes/player.tscn       CharacterBody3D + States + Abilities + weapons
│   ├── scripts/                 player.gd (context), player_input.gd, player_vitals.gd
│   ├── states/                  one script per movement state (no crouch/Walk)
│   ├── abilities/               optional PlayerAbility nodes + overhealth burst
│   └── weapons/                 WeaponController + GunWeapon/SwordWeapon children
└── world/
    ├── world.gd                 entry-scene health check + self-healing
    └── scenes/                  world.tscn (entry), test_map.tscn
```

Three rules keep this clean:

1. **The vendored addon is never edited.** All lens settings are applied from game
   code (`ProjectionController`) through duck-typed `Object.set()`, so upstream
   updates can be dropped in.
2. **Settings live in `core/config/game_config.tres`, not in scripts or scenes.**
   Scripts read the resource directly; there are no duplicate runtime fields.
3. **Systems find each other by group, not by hard-coded node paths.** This is
   what lets scenes be re-saved or reorganised without silently breaking.

---

## Config layer

`GameConfig` (`core/config/game_config.gd`) is a single `Resource` with
`@export_group` sections matching the systems:

| Section | Read by | Controls |
| --- | --- | --- |
| Locomotion / Jump / Slide / Wall run / Dash / Grapple | `EyePlayer` + states + abilities | movement, slide pose, rope and traversal tuning |
| Player Vitals / Overhealth | `PlayerVitals`, `Damage`, `OverhealthBurst` | health, stamina, regen, damage buffer, burst |
| Camera / Scope Overlay | `EyePlayer` + HUD | FOV, mouse, scope zoom, overlay lens |
| Feel | `EyePlayer` + weapons | head-bob, recoil, tracers, muzzle flash, hit marker |
| Weapons / Pistol / Grenade / Sniper / Sword | `WeaponController` + weapon children | damage, cadence, magazines, reloads, charge, quickscope, parry, drop, hit radius |
| Combat / Enemy AI | `HealthComponent`, `EnemyCube`, `EnemyDirector` | enemy health, movement, shooting, stagger, scheduling budget |
| Lens / Lens Resolution / Lens Sampling / Chromatic Aberration / Vignette | `ProjectionController` → lens addon | projection mode, Panini strength/fill, CA, vignette, resolution |
| Post FX | `PostFxController` → post-fx material | CAS sharpening, optional grain |
| Threat Zones / Threat Range / Threat Detection / Threat Highlight | `ThreatDetector` → `ThreatHighlighter` | peripheral zones, range, detection interval, LOS mask, highlight colour/fade |

**Why one file?** The old layout had one class + one `.tres` per system, plus
duplicated runtime fields on each consumer and a dictionary-based `apply_to()`
step. Adding one setting meant editing the profile class, the `.tres`, the
consumer, and the mapping dictionary; a typo only produced a runtime warning.
Now adding a setting is one `@export`, and consumers read it directly.

`GameConfig.validate()` returns a list of human-readable problems (bad FOV,
inverted distance range, `near >= far`, impossible alpha range, …). The world
root logs them on startup and the smoke test fails on them.

**Camera FOV has exactly one owner:** `GameConfig.base_fov`. `EyePlayer` writes
it to its `Camera3D`; the lens reads the camera back every frame.

---

## World root

`world/world.gd` runs on the entry scene and does two things:

1. **Self-heals missing scene wiring.** If `world.tscn` loses its map or player
   child (easy to do when a scene is re-saved by a tool), it instantiates the
   exported fallback scenes and logs a warning instead of running an empty game.
2. **Validates the setup.** [method EyeWorld.validate] checks the config and the
   presence of the map, player, vitals, director, lens, post-fx, HUD and threat
   systems. The smoke test calls the same method, so scene regressions fail CI.

`test_map.tscn` is **pure content**: geometry, lights and highlightable props. The
player and the threat systems live in `world.tscn` under the lens `SubViewport`,
so dropping in a different map cannot accidentally remove the player.

---

## Render pipeline

```
Player/Camera3D ─► ProjectionInput (SubViewport)     3D world at FOV 140
                        │
                        ▼
                 screenspace_projection                Panini lens, CA, vignette
                        │
                        ▼
                   root viewport                       (3D pass)
                        │
        PostFx/Screen (CanvasLayer 0)                  CAS sharpening
                        │
        Hud (CanvasLayer 1)                            crosshair, scope, stats, status
          (display only: every Control uses MOUSE_FILTER_IGNORE)
```

The HUD sits **above** the post-fx pass, so UI text is never sharpened or
vignetted. The post-fx pass is hidden entirely when disabled, costing nothing.

---

## Player / movement framework

`player.gd` is the **context**: it owns the config reference, the input snapshot,
the shared motion math, and the single `move_and_slide()` per tick. Movement
*behaviour* lives in **state nodes**.

```
Player (CharacterBody3D)          player.gd  — context + physics + feel
├── CollisionShape3D
├── Neck/Camera3D                            — head-bob, tilt, dip, FOV kick
├── Input                          player_input.gd  — per-tick input snapshot
├── Health                         player_vitals.gd — health/stamina/overhealth
├── States                         state_machine.gd
│   ├── Idle ┐
│   ├── Run  ├─ extend GroundedState (shared grounded transitions/movement)
│   ├── Slide┘
│   ├── Jump  ┐
│   ├── Fall  │
│   ├── Slam  │
│   ├── Land  ├─ extend PlayerState
│   ├── WallRun│
│   ├── Grapple│
│   └── Dash  ┘
├── Abilities                      ability_host.gd (Node3D, optional discovery)
│   ├── WallSense                  yaw-aligned left/right probes
│   ├── Grapple                    targeting + rope presentation
│   ├── OverhealthBurst            stagger burst + magazine refill
│   └── Weapons                    WeaponController
│       ├── Pistol                 magazine hit-scan tap
│       ├── Grenade                held-throw / area damage
│       ├── Sniper                 charged projectile → hit-scan/quickscope
│       └── Sword                  swept-sphere strike + timed parry
├── StairProbe/{StepAhead,FloorBelow}        — stair stepping raycasts
└── FootstepPlayer
```

Flow per physics tick:

```
input.update()                # one deterministic snapshot
abilities.pre_move_update()   # wall probes / cooldowns / burst need this tick
timers (coyote, jump buffer/hold, air jumps, dash, slide, wall-run)
accel_dir = camera-yaw-relative wish direction
slide pose target reset; state_machine.physics_update(delta)
slide pose + body height update + horizontal speed clamp
stair up-snap  ─┐
                ├─ else move_and_slide() + stair down-snap
_post_move(): feel (head-bob, dip, tilt, FOV, recoil) + footsteps
abilities.post_move_update()   # weapon input, previews, rope visuals
```

A **state** extends `PlayerState` (or `GroundedState`) and implements
`enter()` / `exit()` / `physics_update()`. It reads `player.config` and
`player.input`, mutates `player.velocity`, and calls
`machine.transition_to(&"Name")`. It never calls `move_and_slide()` itself.

### Adding a state

1. Add `player/states/dive.gd` with `class_name PlayerDiveState extends PlayerState`.
2. Add a `Dive` child node to `States` in `player.tscn` and attach the script.
3. Transition to it with `machine.transition_to(&"Dive")` from whichever state
   should start it.

Nothing else changes. The node name **is** the state name.

### Game-feel features already wired

Coyote time, jump buffering, variable jump height, double jump, hold-to-jump-
higher, air slam, automatic high-speed/slam slides (with ramp-aware engagement),
Quake-style ground/air acceleration, head-bob, landing dip, strafe tilt, speed
FOV kick, distance-based footsteps, stair stepping, wall-run + wall-jump,
grapple, scope zoom, recoil, and a ground/air dash. There is no sprint button:
normal movement uses the sprint speed, and no slide button: land fast or slam.

The world uses four named physics layers (`core/physics_layers.gd`, mirrored in
`project.godot`):

| Layer | Name | Used by |
| --- | --- | --- |
| 1 | World | CSG map geometry, props, wall probes, grapple LOS |
| 2 | Player | the player body shape (weapons exclude it explicitly) |
| 3 | Enemy | shootable bodies |
| 4 | Projectile | grenade/sniper bodies (so they never hit the shooter) |

Weapon hit queries use `HIT_MASK = WORLD | ENEMY`.

---

## Abilities and traversal

`PlayerAbilityHost` (a `Node3D` under the player) discovers children by their
`ability_id`, so a system is added by dropping in a node and removed by deleting
it. It runs three phases: `pre_move_update` (sensing/cooldowns), the state
machine, and `post_move_update` (input routing/visuals). The `Node3D` base gives
each ability a stable world transform; `WallSense` drives its rays explicitly so
they can follow the camera yaw instead of the body's fixed orientation.

- **WallSense** owns four rays (chest/knee, left/right). Every tick it re-orients
  them around the camera yaw and forces an update, so "right" means screen-right
  even when the player turns. A wall is runnable only when its normal is steep
  enough (`wall_run_min_angle_deg`).
- **PlayerWallRunState** projects movement onto the wall tangent and adds a
  large entry speed burst. Gravity ramps from almost zero to normal over the run
  while the tangent target speed decays, so the player slides down and slows
  down like Titanfall. A stick force holds the capsule to the wall, the camera
  tilts, and the state ends on timeout, wall loss, low speed or landing. A wall
  jump uses the buffered jump (not coyote time), pushes along the wall normal,
  boosts the tangent speed and resets air jumps.
- **GrappleAbility** owns targeting/presentation; `PlayerGrappleState` owns the
  physics so the state machine remains the only place that moves the player. A
  ray from the camera picks the anchor. The rope reels in slowly and a spring
  adds pull toward the anchor, but no radial velocity is cancelled, so the
  player keeps their own movement direction and can steer to rotate around the
  anchor. Attaching spends stamina once; holding the rope does not drain it.
  It does not auto-detach when short. Deleting the ability removes the state's
  entry path and its rope nodes.
- **PlayerSlamState** is armed by a jump hold that began in mid-air. It plunges
  with increased gravity, keeps most horizontal momentum, and hands off to
  `Land` with `slam = true`; `Land` then starts `Slide` immediately.
- **PlayerSlideState** is entered from `Land` when the landing speed clears
  `slide_min_speed` (lower on downhill ramps) or from a slam. Entry applies a
  capped boost, and a slam guarantees a minimum forward burst even from a
  straight-down drop. Friction then bleeds speed below sprint while downhill
  slopes add some back. There is no slide input. The state sets the slide body
  pose; the player resizes the collision shape and lowers the eye height after
  the state machine runs, then restores the stand pose on exit.

## Vitals, overhealth and the burst

`PlayerVitals` extends `HealthComponent`, so the existing damage lookup and enemy
health path keep working. It adds three things:

- **Health** — 100 by default; at zero the player stops acting, hides the
  weapons, and respawns after `player_respawn_delay` with a full reset.
- **Stamina** — 100 by default. Running, jumping, sliding and wall-running never
  spend it; dash, grapple attach, firing, throwing and sword strikes do. After a
  short delay it regenerates at the configured rate.
- **Overhealth** — a 0..50 buffer. `Damage.apply` credits the player when the
  damage source is the player, using the amount the target's health actually
  removed (overkill is clipped). The buffer absorbs incoming damage before
  health. At more than half full, `OverhealthBurst` (Q) can spend the whole
  buffer: it staggers and damages visible enemies in a radius, then calls
  `WeaponController.refill_all_ammo()`. The burst deliberately passes no player
  source, so it cannot refill its own buffer.

There is no crouch state or crouch input. The only compressed body pose belongs
to the slide and is restored when the slide ends (or when there is headroom to
stand).

---

## Weapons, projectiles and damage

`WeaponController` is itself a `PlayerAbility`. It discovers `WeaponBase` children
and routes the per-tick input snapshot:

| Input | Unscoped | Scoped (RMB) |
| --- | --- | --- |
| LMB tap (release before hold) | pistol hit-scan | begin sniper charge |
| LMB hold past threshold | charge grenade, release to throw (no pistol shot) | keep charging |
| LMB release | throw charged grenade | fire sniper at current charge |
| F | reload the active gun | reload the sniper |
| V | toggle sword | toggle sword |
| Q | overhealth burst | overhealth burst |

While the sword is equipped, LMB is a melee strike and RMB opens the timed parry
window; the other gun inputs are suppressed. Returning from the sword halves any
reload still in progress (`quickswitch_reload_factor`). Weapons never poll
`Input`; this keeps them deterministic in tests. Deleting a weapon child calls
back into the controller, which drops its cached reference and exits scope if the
sniper disappeared.

- **GunWeapon** is the shared magazine/reload/stamina base. Reloading starts
  automatically at zero rounds, or manually with **F**; the burst instantly
  refills every magazine.
- **Pistol** is a camera ray with config-driven low damage and spread.
- **Grenade** is a sticky `CharacterBody3D` projectile with a fuse: its first
  collision fixes it to the surface (and follows a moving enemy until the fuse
  ends). Its explosion overlaps the enemy layer, applies distance falloff and
  checks line of sight against the world layer only. It spends stamina on throw.
- **Sniper** interpolates speed, damage and hit radius with charge. Below the
  hit-scan threshold it launches a swept projectile that combines **both**
  player-velocity inheritance (movement direction) and configurable gravity
  (bullet drop). At the threshold it becomes a swept-sphere hit-scan. A shot
  within `sniper_quickscope_window` of scoping uses an exact camera ray with no
  spread, drop or inheritance and at least `sniper_quickscope_damage`. While
  scoped, a green marker predicts the impact from the same camera origin using
  the shared `get_launch_velocity()` helper (so inheritance cannot drift from the
  real shot), the same gravity and speed; the full-charge preview uses the same
  swept-sphere query as the shot.
- **Sword** uses a swept-sphere strike and a timed parry. `EyePlayer.try_parry()`
  is called by enemies before applying a shot: it requires the sword equipped, a
  live parry window, and the attacker inside the horizontal parry cone. A
  successful parry negates the shot and staggers the attacker.

`Projectile` uses `move_and_collide()` so fast rounds cannot tunnel. `Damage`
finds a `HealthComponent` on the collider, its children or its parents, so future
damageable objects need no weapon changes. Hit feedback (tracers, muzzle flash,
impact spark, hit marker) is shared by the controller; the HUD only listens to
`hit_confirmed`.

---

## Enemy AI

`EnemyCube` is a `CharacterBody3D` that owns health, presentation, gravity and
movement integration. It does **not** run AI in its own `_physics_process`:
enemies register with an `EnemyDirector`, which owns the schedule.

- The director keeps a round-robin list and spends at most
  `enemy_ai_max_updates_per_tick` decisions per physics tick (default **one**).
  Each enemy accumulates real time and thinks every
  `enemy_ai_update_interval`; the accumulated delta is passed to `think()`, so
  cadence is stable even when the budget delays a turn.
- With no director, no `think()` call ever happens and enemies remain static.
  That is what keeps weapon tests deterministic.
- `think()` moves toward the player, switches to a strafe around
  `enemy_stop_distance`, checks LOS against the world mask, and fires on its own
  cooldown. Shots call `EyePlayer.try_parry()` first, then `Damage.apply`.
- Stagger zeroes horizontal movement and delays the next shot. This is shared by
  sword parries and the overhealth burst.
- **F1** toggles the director master switch without removing bodies, collisions
  or the group registration. The HUD shows the current AI state.

---

## Post-lens effects

`addons/eye_postfx/eye_postfx.gdshader` is a single full-screen pass:

- **CAS** (contrast-adaptive sharpening) recovers detail lost to FSR2 temporal
  upscaling and the wide-anchor lens, without the ringing of a plain unsharp mask.
- **Grain** (off by default) can mask temporal shimmer at very high FOV.

Effects are intentionally limited to one cheap pass: clarity is cheaper to buy
with sharpening than with more supersampling. `lens_upscale` /
`lens_supersample` remain the "spend performance for sharpness" knobs.

---

## Peripheral threat highlights

Vision is split into three horizontal zones, in degrees from forward:

```
        rear blindspot                 forward view                 rear blindspot
   <--------- 110 ---------|---- 70 ---- 0 ---- 70 ----|--------- 110 --------->
                            \___ peripheral ___/ \___ peripheral ___/
```

- **Forward** (`|a| <= 70`) — already on screen, drawn with its normal material.
- **Peripheral** (`70 < |a| <= 110`) — out of frame but detectable; highlighted.
- **Rear** (`|a| > 110`) — blindspot, never highlighted.

`ThreatDetector` scans the `highlightable` group on an interval, classifies each
object, raycasts line of sight against the world layer, and emits a `Threat`
(angle, distance, LOS, 0..1 distance intensity). It reuses one ray query, so a
pass allocates nothing.

`ThreatHighlighter` renders the eligible threats. Because 70..110° is outside the
rendered frustum, it cannot draw them where they are. Instead of adding extra
cameras/SubViewports, each threat gets a **ghost**: a copy of its meshes rotated
rigidly about the camera's vertical axis to a folded azimuth,

```
display = sign(a) * (2 * 70 - |a|)        // 70 -> 70, 80 -> 60, 110 -> 30
```

so the real Panini lens draws the ghost's exact silhouette inside the 30..70°
side bands — **70° at the screen edge, 110° nearest the centre, always on the
same side**, and the middle 60° never covered. The ghost keeps the object's
distance and orientation, so silhouette, size and fade are exact; it uses an
unshaded, depth-test-disabled red material, so the object itself is never tinted
and the overlay floats over the scene. A rigid rotation about the camera also
avoids any second render pass, which is cheaper than the extra-camera approach.

Distance drives brightness and opacity (`near_distance`..`far_distance`): closer
objects are more saturated and more opaque. Blocked objects are dropped before a
ghost is built, so occluded threats never show an overlay.

---

## Tests, backups, conventions

```bash
misc/tests/run_all.sh                                      # all suites + error gate
godot --headless --import                                  # reimport / check parse errors
godot --headless --script res://misc/tests/smoke_test.gd     # config + scene wiring
godot --headless --script res://misc/tests/movement_test.gd  # physics + state machine
godot --headless --script res://misc/tests/traversal_test.gd # wall-run, wall-jump, grapple
godot --headless --script res://misc/tests/combat_test.gd    # four weapons, reloads, quickscope, parry
godot --headless --script res://misc/tests/threat_test.gd    # zones, fold, highlighters
godot --headless --script res://misc/tests/world_test.gd     # self-healing + health check
godot --headless --script res://misc/tests/vitals_test.gd    # health, stamina, overhealth, burst
godot --headless --script res://misc/tests/enemy_ai_test.gd  # scheduling, movement, shooting, F1
misc/tools/backup.sh before-some-change                     # snapshot the source
```

The test runner treats `SCRIPT ERROR:` / `ERROR:` in the output as a failure,
because Godot otherwise exits 0 when a script aborts.

See `misc/README.md` for the backup workflow, `misc/docs/AUDIT.md` for the robustness audit and `README.md` for change recipes.
