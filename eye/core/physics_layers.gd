class_name PhysicsLayers
extends RefCounted

## Named 3D physics layers used across the prototype.
##
## The same names are registered in `project.godot` under `[layer_names]`, so the
## editor inspector shows them. Keep the numeric values in sync with that file.
##
## Layer 1 is the world (CSG geometry, props). Layer 2 is the player. Layer 3 is
## enemies/damageable static bodies. Layer 4 is projectiles. Keeping projectiles
## and the player on their own layers is what stops a bullet from spawning inside
## and hitting its shooter.
const WORLD := 1 << 0
const PLAYER := 1 << 1
const ENEMY := 1 << 2
const PROJECTILE := 1 << 3

## Everything a weapon can hit.
const HIT_MASK := WORLD | ENEMY
