# Architecture

A first-person prototype with a wide-FOV Panini ("screen-space projection") lens,
**one** data-driven config resource, and a node-based movement state machine. The
goal is that **every tunable lives in one file** and **every behaviour is one
small file**, so adding systems does not require touching existing ones.

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
│   ├── peripheral/
│   │   └── threat.gd            one detected threat (data only)
│   ├── projection_controller.gd pushes lens fields into the addon
│   ├── post_fx_controller.gd    pushes post-fx fields into the material
│   ├── threat_detector.gd       scans, classifies, raycasts LOS
│   ├── threat_highlighter.gd    draws folded red silhouettes
│   └── ui/hud.gd                top-corner position / state / FPS readout
├── misc/
│   ├── backup/                  timestamped source snapshots (Godot ignores these)
│   ├── docs/                    this document
│   ├── tests/                   headless tests + run_all.sh
│   └── tools/backup.sh          snapshot helper
├── player/
│   ├── scenes/player.tscn       CharacterBody3D + States + probes + audio
│   ├── scripts/                 player.gd (context), player_input.gd (snapshot)
│   └── states/                  one script per movement state
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
| Locomotion / Jump / Slide / Wall run / Dash | `EyePlayer` + states | movement tuning |
| Camera / Feel | `EyePlayer` | FOV, mouse, head-bob, footsteps |
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
   presence of the map, player, lens, post-fx, HUD and threat systems. The smoke
   test calls the same method, so scene regressions fail CI.

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
        Hud (CanvasLayer 1)                            crosshair, stats, hint
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
├── States                         state_machine.gd
│   ├── Idle ┐
│   ├── Walk ├─ extend GroundedState (shared grounded transitions/movement)
│   ├── Run  │
│   ├── Slide┘
│   ├── Jump  ┐
│   ├── Fall  │
│   ├── Land  ├─ extend PlayerState
│   ├── WallRun│
│   └── Dash  ┘
├── StairProbe/{StepAhead,FloorBelow}        — stair stepping raycasts
└── FootstepPlayer
```

Flow per physics tick:

```
input.update()                # one deterministic snapshot
timers (coyote, jump buffer, dash, wall-run)
accel_dir = camera-yaw-relative wish direction
state_machine.physics_update(delta)   # the active state sets velocity / transitions
stair up-snap  ─┐
                ├─ else move_and_slide() + stair down-snap
feel (head-bob, dip, tilt, FOV) + footsteps
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

Coyote time, jump buffering, variable jump height, Quake-style ground/air
acceleration, head-bob, landing dip, strafe tilt, sprint FOV kick,
distance-based footsteps, stair stepping, crouch-slide, wall-run + wall-jump, and
an air dash.

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
godot --headless --script res://misc/tests/smoke_test.gd    # config + scene wiring
godot --headless --script res://misc/tests/movement_test.gd # physics + state machine
godot --headless --script res://misc/tests/threat_test.gd   # zones, fold, highlighters
godot --headless --script res://misc/tests/world_test.gd    # self-healing + health check
misc/tools/backup.sh before-some-change                     # snapshot the source
```

The test runner treats `SCRIPT ERROR:` / `ERROR:` in the output as a failure,
because Godot otherwise exits 0 when a script aborts.

See `misc/README.md` for the backup workflow and `README.md` for change recipes.
