# Voxel World Framework — Architecture & Handoff

## What this is
A voxel-based city generation + destruction + morphing framework, replacing
the two mesh-based prototypes. Four files:

- `voxel_types.gd` — single source of truth for voxel type IDs and materials.
- `voxel_chunk.gd` — one 16³ chunk: stores voxel data, builds its own mesh
  (face-culled, one merged mesh surface per material) and collision.
- `voxel_world.gd` — chunk manager. ALL cross-chunk voxel access goes
  through here (`get_voxel`, `set_voxel`, `remove_voxel`,
  `remove_voxels_in_sphere`). Batches dirty-chunk remeshing once per frame.
- `city_voxel_generator.gd` — fills a VoxelWorld with the city: roads,
  dense building columns (density instinct from your second prototype,
  overlap-safe placement from your first), rare tilted clusters, the great
  wall ring, and the arena floor.
- `building_morph_system.gd` — runtime growth/shrink of building columns,
  amplitude scaling continuously from ~0 near the wall to pronounced near
  center. No hard arena/city boundary, as you asked for.

## Why voxels solve three of your problems at once
1. **Destruction** = `remove_voxel` / `remove_voxels_in_sphere`. No separate
   rigidbody-swap hack, no baked mesh fracture system. A melee hit or
   explosion just deletes voxels and the affected chunks remesh.
2. **Morphing** = adding/removing voxel layers at the top of a column,
   already animatable by throttling how many columns change per tick.
3. **Density + non-overlap** = the generator iterates every column once,
   same as prototype B's density, but chunk-based voxel storage means
   "overlap" isn't even a concept — you're never placing two meshes in the
   same space, you're setting one value per grid cell.

## What is NOT done yet (opencode's job, in order)
1. **Wire the scene**: create a `VoxelWorld` node, a `CityVoxelGenerator`
   child with `world` assigned, call `generator.generate()`, then a
   `BuildingMorphSystem` with both refs assigned, call `.begin()`.
   Replace your old `world.gd`'s `_ready()` with this sequence.
2. **Hook `remove_voxels_in_sphere` into combat** — melee hits and
   explosions should call it at the impact point with a radius scaled to
   the hit. This is a one-line call from wherever damage is currently
   applied; don't let the agent redesign the damage system to do it.
3. **Greedy meshing** — right now `voxel_chunk.gd` emits one quad per
   exposed face (face-culled, but not merged). Fine for correctness and a
   first playtest; will get expensive at full city scale. Ask opencode to
   implement greedy meshing INSIDE `_emit_voxel_faces`/`rebuild_mesh` only
   — the public API (`get_voxel_local`, `set_voxel_local`, `rebuild_mesh`)
   must not change, since VoxelWorld depends on it.
4. **Threaded/deferred chunk generation** — `CityVoxelGenerator.generate()`
   currently runs synchronously and will hitch on a large city. Have
   opencode chunk the generation loop across frames (e.g. `await
   get_tree().process_frame` every N columns), not multithread yet —
   threading voxel writes safely is a bigger task, don't let the agent
   reach for threads by default.
5. **Tilted-column morph growth** — noted as a TODO in
   `building_morph_system.gd`. Currently tilted buildings morph as straight
   columns. Low priority, cosmetic only.
6. **Grapple-stamina-vs-wall-height tuning** — `wall_height = 140` in the
   generator is a placeholder. This number needs to come from YOUR
   grapple ability's stamina-cost curve, not be invented independently.
   Do this yourself, don't hand it to opencode blind.
7. **LOD / render distance** — not addressed at all. Only relevant once you
   confirm the base system runs at acceptable framerate; don't let opencode
   preemptively over-engineer this before you've profiled anything.

## What YOU must do (don't delegate)
- Decide and set real values for `city_radius`, `street_spacing`,
  `arena_radius`, `wall_height` based on playtesting feel, not defaults.
- Verify chunk rebuild cost is acceptable — put a frame-time print around
  `VoxelWorld._process`'s dirty-chunk flush loop and watch it while morphing
  is active near center. If it spikes, that's your signal to prioritize
  greedy meshing (item 3) before adding anything else.
- Review every opencode diff to these files against this document BEFORE
  merging. If a diff changes a public method signature listed above
  (`get_voxel`, `set_voxel`, `remove_voxel`, `remove_voxels_in_sphere`,
  `get_voxel_local`, `set_voxel_local`, `rebuild_mesh`), stop and check
  whether every caller was updated — this is exactly the kind of silent
  breakage that turns into slop.
- Decide whether roads/parkour elements/signage/atmosphere from your first
  prototype get ported into this system as voxel placements (roads already
  are) or stay as separate decorative mesh spawns layered on top. My
  recommendation: keep atmosphere/signage/billboards as regular
  MeshInstance3D spawns positioned by querying `columns` for tall buildings
  — they don't need to be destructible or voxelized, and doing so would
  bloat chunk data for no gameplay benefit. Tell opencode this explicitly
  so it doesn't try to voxelize everything.

## Prompting opencode for this handoff
Good first task: *"Using ARCHITECTURE.md as the spec, wire these four
scripts into a scene: VoxelWorld node with CityVoxelGenerator and
BuildingMorphSystem children, matching the wiring described in item 1.
Do not modify the public methods of VoxelChunk or VoxelWorld listed in the
'what YOU must do' review checklist. Ask me before changing any exported
variable's default value."*

Bad prompt: *"Here's my old city generator and this new voxel system, merge
them and make it work."* — too open-ended, invites silent redesign.
