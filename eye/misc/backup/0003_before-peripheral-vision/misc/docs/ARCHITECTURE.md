# Architecture

A first-person prototype with a wide-FOV Panini ("screen-space projection") lens,
a data-driven config layer, and a node-based movement state machine. The goal is
that **every tunable lives in one resource** and **every behaviour is one small
file**, so adding systems does not require touching existing ones.

---

## Folder map

```
eye/
├── addons/
│   ├── assets/                  game art + audio (imported by Godot)
│   ├── eye_postfx/              our post-lens clarity pass (shader)
│   └── screenspace_projection/  VENDORED addon — treat as read-only
├── core/
│   ├── config/                  CONFIG RESOURCES — the single sources of truth
│   │   ├── config_resource.gd     base class + apply_values()
│   │   ├── projection_profile.gd + .tres   lens look
│   │   ├── post_fx_profile.gd + .tres      post-lens effects
│   │   └── player_config.gd + .tres        movement / camera / feel
│   ├── projection_controller.gd  pushes ProjectionProfile into the lens addon
│   ├── post_fx_controller.gd     pushes PostFxProfile into the post-fx material
│   └── ui/hud.gd                 top-corner position / state / FPS readout
├── enemies/                     reserved
├── misc/
│   ├── backup/                  timestamped source snapshots (Godot ignores these)
│   ├── docs/                    this document
│   ├── tests/                   headless smoke + movement tests
│   └── tools/backup.sh          snapshot helper
├── player/
│   ├── scenes/player.tscn       CharacterBody3D + States + probes + audio
│   ├── scripts/                 player.gd (context), player_input.gd (snapshot)
│   └── states/                  one script per movement state
└── world/
    └── scenes/                  world.tscn (entry scene), test_map.tscn
```

Two rules keep this clean:

1. **The vendored addon is never edited.** All lens settings are applied from game
   code (`ProjectionController`) through duck-typed `Object.set()`, so upstream
   updates can be dropped in.
2. **Settings live in `core/config/*.tres`, not in scripts or scenes.** Scripts
   and scenes read the resources at runtime.

---

## Config layer

`ConfigResource` (`core/config/config_resource.gd`) is a tiny base class:

```gdscript
func apply_values(target: Object, values: Dictionary) -> void:
    for key in values:
        target.set(key, values[key])
```

Each profile is a `Resource` that lists its editable fields as `@export`s and
implements `apply_to(target)`. Because it only uses `Object.set()`, a profile
never depends on the node it configures (that is what keeps the game decoupled
from the addon).

| Resource | Read by | Controls |
| --- | --- | --- |
| `projection_profile.tres` | `ProjectionController` → the lens addon | projection mode, Panini strength/fill, sampling, chromatic aberration, vignette, resolution |
| `post_fx_profile.tres` | `PostFxController` → the post-fx material | CAS sharpening, optional grain |
| `player_config.tres` | `EyePlayer` | speeds, accel/friction, jump/slide/wall-run/dash, camera + feel |

**Camera FOV has exactly one owner:** `PlayerConfig.base_fov`. The lens reads the
active `Camera3D.fov` back every frame, so changing that one value moves the
camera and the lens together.

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

`player.gd` is the **context**: it owns config values, the input snapshot, the
shared motion math, and the single `move_and_slide()` per tick. Movement
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
`enter()` / `exit()` / `physics_update()`. It reads `player.input`, mutates
`player.velocity`, and calls `machine.transition_to(&"Name")`. It never calls
`move_and_slide()` itself.

### Adding a state

1. Add `player/states/dive.gd` with `class_name PlayerDiveState extends PlayerState`.
2. Add a `Dive` child node to `States` in `player.tscn` and attach the script.
3. Transition to it with `machine.transition_to(&"Dive")` from whichever state
   should start it.

Nothing else changes. The node name **is** the state name.

### Game-feel features already wired

Coyote time, jump buffering, variable jump height, Quake-style ground/air
acceleration, head-bob, landing dip, strafe tilt, sprint FOV kick, distance-based
footsteps, stair stepping, crouch-slide, wall-run + wall-jump, and an air dash.

---

## Post-lens effects

`addons/eye_postfx/eye_postfx.gdshader` is a single full-screen pass:

- **CAS** (contrast-adaptive sharpening) recovers detail lost to FSR2 temporal
  upscaling and the wide-anchor lens, without the ringing of a plain unsharp mask.
- **Grain** (off by default) can mask temporal shimmer at very high FOV.

Effects are intentionally limited to one cheap pass: clarity is cheaper to buy
with sharpening than with more supersampling. `upscale` / `supersample_amount` in
the projection profile remain the "spend performance for sharpness" knobs.

---

## Tests, backups, conventions

```bash
godot --headless --import                                  # reimport / check parse errors
godot --headless --script res://misc/tests/smoke_test.gd    # config wiring
godot --headless --script res://misc/tests/movement_test.gd # physics + state machine
misc/tools/backup.sh before-some-change                     # snapshot the source
```

See `misc/README.md` for the backup workflow and `README.md` for change recipes.
