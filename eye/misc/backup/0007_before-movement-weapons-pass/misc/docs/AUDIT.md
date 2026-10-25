# Audit and robustness pass

This document records the issues found while preparing the traversal/combat
update, and the guarantees the current structure is meant to preserve. It is a
short engineering history, not a second architecture guide.

---

## Fixed issues

| Issue | Why it mattered | Fix |
| --- | --- | --- |
| `PlayerAbility` extended `Node`, not `Node3D` | Ability nodes did not inherit the player's transform, so probe and muzzle positions were in the wrong space. | Abilities and the ability host are `Node3D`; probe origins are now explicit world-space points. |
| Ability setup relied on child `_ready()` order | `@onready` player references are not ready when a child's `_ready()` runs, so loadout setup could see nulls. | `EyePlayer._ready()` calls `AbilityHost.setup()` after its own references resolve. |
| Visual nodes were parented during `_ready()` | Adding a child to a busy scene parent can fail with “Parent node is busy setting up children.” | World-parent visuals are attached with `call_deferred()`; they remain optional and are cleaned up on removal. |
| Stale freed ability references | Entering a removed grapple state could cast a freed node and emit a script error. | Ability lookups use validity checks; optional abilities are never cast blindly. |
| Wall probes used world axes | Wall running only worked while facing `-Z`; turning the camera did not change “left” and “right”. | Probes are re-oriented around camera yaw every tick. A traversal test flips the view and verifies the sides swap. |
| Grapple auto-detached at minimum rope length | Reeling in could drop the player even though the rope was still attached. | The rope goes slack at minimum length; only release, jump or over-stretch detaches it. |
| Wall jumps were not using buffered jump input | A jump pressed just before touching a wall could be wasted. | Wall-run entry uses the buffered jump while airborne and restores tangent speed on wall jump. |
| Weapon removal left cached references | Deleting a weapon node could leave the input router calling a freed object. | `WeaponBase._exit_tree()` notifies the controller; cached refs and scope state are cleared immediately. |
| Pistol reported every hit as a kill | The shared hit marker always used the kill colour, even for the intentionally low-damage pistol. | The pistol now reports `health.is_alive()` like the other weapons. |
| Projectile visuals scaled with hit radius | A charged sniper hit sphere could render as a giant orb; grenade visuals were inconsistent with their collision size. | Hit radius and visual size are decoupled; the collision sphere grows, the mesh stays readable. |
| `HealthComponent.configure()` cleared invincibility | Reconfiguring health accidentally discarded a designer-set immunity window. | Configure resets current health/timer but preserves the configured `invincibility_time`. |
| Tests exited while footstep audio still played | Headless runs emitted leaked-instance warnings at shutdown. | Traversal tests settle before quitting, and `run_all.sh` treats engine errors as failures. |
| HUD controls could consume mouse motion | A centered crosshair label with the default mouse filter could make mouse-look feel frozen. | The HUD recursively sets every `Control` to `MOUSE_FILTER_IGNORE`; a smoke check guards it. |
| Grapple divided by zero at the anchor | Removing min-length auto-detach made the zero-distance case reachable. | Radial forces are skipped below 1 mm while the rope stays attached. |
| Sibling query nodes outlived their owner | Removing the weapons loadout left `SniperHitscan` in the world. | `WeaponController._exit_tree()` frees it; the combat test verifies the cleanup. |
| Dash fallback used body forward | With no stick input it dashed along world `-Z`, not where the camera looked. | The fallback now uses camera forward, like every other movement direction. |

---

## Structural guarantees

- **One config**: gameplay tuning is exported by `GameConfig`; the single
  `core/config/game_config.tres` resource is loaded by the player, world and
  tests.
- **One mover**: states set velocity; `EyePlayer` owns the single
  `move_and_slide()` call, stair handling and feel layer.
- **Drop-in systems**: abilities and weapons are child nodes with setup/update
  callbacks. Removing one must not break movement, and removal is covered by
  tests.
- **Deterministic input**: systems read `PlayerInput` snapshots, never polling
  `Input` directly. This is what keeps headless state tests stable.
- **Named layers**: world, player, enemy and projectile layers live in
  `core/physics_layers.gd` and `project.godot`; weapon queries use a single hit
  mask.
- **Config validation**: `GameConfig.validate()` and `EyeWorld.validate()` catch
  impossible ranges and broken scene wiring at startup.

---

## Verification

```bash
misc/tests/run_all.sh
```

The suite covers scene/config wiring, movement, wall-run/wall-jump/grapple,
loadout/pistol/grenade/sniper/preview, threat zones/highlighting, and world
self-healing. The runner fails on test failures, `SCRIPT ERROR:` or `ERROR:`.

## Known limitations

- Enemies are static shootable targets; there is no AI, navigation or player
  damage yet.
- Weapons have no ammo, reload, switching animation or audio; the controller is
  ready for those as additional `WeaponBase` nodes/fields.
- The sniper preview is sampled at physics-tick intervals, so extremely fast
  movement against a razor-thin edge can differ by a fraction of a tick.
- No network prediction or rollback; the input snapshot is locally
  deterministic.
