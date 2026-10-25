# eye-weapons — drop-in gun system for "eye"

Written by neko chan 🐾 — copy this `core/` folder into your Godot project
(merge with your existing `core/` if you have one), then do the 4 wiring steps.

> ⚠️ **CLASS_NAME COLLISION WARNING.** This pack defines `class_name
> WeaponResource` (plus `Health` and `Projectile`). Your `neonruins/` prototype
> already has `class_name WeaponResource`. **Never copy both into one project**
> — Godot will refuse to load with duplicate global class names. Pick ONE
> weapon resource (see `eye-merge-plan.md` → "The landmine in my drop-in zip"),
> and delete/rename the other's file before merging. Same for `Health` vs
> `HealthComponent` — keep the component model.
>
> Also eye-specific: this pack reads `Input` directly, but eye's convention is
> the `PlayerInput` snapshot. See `eye-merge-plan.md` → "Exact integration
> recipe for eye" for the 10-minute adaptation (extend PlayerInput, add the
> recoil accumulator to player.gd).

## What's inside

```
core/
├── weapons/
│   ├── weapon_resource.gd   # gun DATA (one .tres per gun, no code per gun)
│   ├── weapon_manager.gd    # attach to Player — owns state/ammo/input
│   ├── weapon_behavior.gd   # base class for fire effects
│   ├── hitscan_behavior.gd  # pistol / AR / shotgun (raycast + tracer)
│   ├── projectile_behavior.gd + projectile.gd  # rocket / plasma
│   ├── melee_behavior.gd    # combo melee with swept hit detection
│   └── guns/
│       ├── pistol.tres
│       ├── ar.tres
│       └── shotgun.tres
└── combat/
    └── health.gd            # add as child "Health" node to anything damageable
```

## Wiring (4 steps)

**1. Player scene:** add a `WeaponManager` node as a child of your Player
(under the Camera3D works well). In the inspector:
- `camera` → your Camera3D
- `muzzle` → a Marker3D at the gun tip (create one under the camera)
- `weapons` → add the three .tres files (pistol, ar, shotgun)
- optional for melee: a Marker3D named `BladeTip` as a child of WeaponManager

**2. player.gd — add exactly this** (the ONLY change to your movement code):
```gdscript
var recoil_pitch := 0.0
func add_camera_pitch(rad: float) -> void:
    recoil_pitch += rad
```
Then in your camera code each frame: apply `recoil_pitch` to the camera's
x-rotation and decay it toward 0 (e.g. `recoil_pitch = lerpf(recoil_pitch, 0.0, delta * 10.0)`).

**3. Input actions** (Project Settings → Input Map):
`shoot` (mouse left), `reload` (R), `weapon_1`, `weapon_2`, `weapon_3` (keys 1/2/3).

**4. Enemies:** add a `Health` node as a child (named exactly "Health"),
put enemies on physics layer 2. Player stays on layer 1, world on 4.

## HUD hooks

Connect to the WeaponManager's signals:
- `ammo_changed(mag, reserve)` → ammo counter
- `weapon_changed(weapon_name)` → weapon name display

## Tuning

All gun feel lives in the `.tres` files: damage, fire_interval, spread_deg,
bloom_per_shot, recoil_kick_deg, pellets, reload_time. New gun = duplicate a
.tres, tweak numbers, add to the manager's `weapons` array. No code changes.

## The Chimera (multi-mode gun)

`chimera_behavior.gd` + `chimera_resource.gd` + `guns/chimera.tres` implement
tejasvin's spec as a single weapon:

- **RMB** = scope (always). **LMB tap scoped** = sniper projectile.
  **LMB hold scoped** = charge: release mid = sniper hitscan, release full =
  hitscan + ricochet chains.
- **LMB tap unscoped** = pistol (weak hitscan). **LMB hold, release** =
  grenade launcher — charge scales damage + blast radius.
- Mode switches are procedural: viewmodel pose lerps, charge shake, tier
  chimes, scope overlay. All SFX via the `Sfx` autoload (see `core/sfx.gd`
  and `core/weapons/SOUNDS.md`).

Extra setup for the Chimera:
1. Input action `scope` (mouse right).
2. `Sfx` autoload: Project Settings → Autoload, add `core/sfx.gd` as `Sfx`.
3. Scope overlay: in your HUD, add a CanvasLayer → full-rect ColorRect with
   `core/weapons/scope_overlay.gdshader`, connect the behavior's
   `scope_changed(scoped)` signal to its `visible`.
4. Charge bar (optional): connect `charge_changed(frac, tier)` to a ProgressBar.
5. Player additions (eye's player.gd):
   ```gdscript
   var scope_zoom := 1.0  # weapon lerps this; 1.0 = hip, 0.25 = scoped
   ```
   In `_unhandled_input` mouse motion, multiply sensitivity by `scope_zoom`.
   In `_update_feel`, multiply the FOV target by `scope_zoom` before lerping.
   Extend `player_input.gd` snapshot: `shoot_pressed`, `shoot_just_pressed`,
   `shoot_just_released`, `scope_pressed`, `scope_just_pressed`,
   `scope_just_released` (the Chimera prefers the snapshot, falls back to
   `Input` if the player has no `input` node).
6. Grenade/sniper projectiles: make a scene from `projectile.gd`
   (Area3D + CollisionShape3D + script + mesh) and assign it to the chimera
   resource's `projectile_scene`.

## For opencode (paste this)

> In this repo there's a folder `eye-weapons/` with a drop-in Godot 4 gun
> system (see `eye-weapons/README.md`). Copy its `core/` into `res://core/`,
> then follow the README's 4 wiring steps to attach the WeaponManager to the
> existing player scene in `eye`. Do not modify player movement code except
> adding the `add_camera_pitch` accumulator. Report what you changed and how
> to test.
