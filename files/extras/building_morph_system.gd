class_name BuildingMorphSystem
extends Node

# Makes building columns grow/shrink at runtime. Morph AMPLITUDE scales
# continuously with proximity to city center -- there is no hard boundary
# between "static city" and "morphing arena". Near the wall, amplitude is
# ~0 and buildings read as static. Near center, amplitude is pronounced.
#
# Cost control: only a subset of columns is re-evaluated per tick (spread
# across frames), because touching thousands of columns every frame would
# thrash chunk remeshing. Tune `columns_per_tick` against your target
# column count and frame budget.

@export var world: VoxelWorld
@export var generator: CityVoxelGenerator
@export var tick_interval: float = 0.15
@export var columns_per_tick: int = 40
@export var max_height_delta: int = 12       # max layers a column can grow/shrink from its base
@export var morph_speed: float = 1.0          # layers changed per tick per active column

var _noise := FastNoiseLite.new()
var _time := 0.0
var _tick_timer := 0.0
var _column_keys: Array = []
var _cursor := 0

# current_height is tracked separately from base_height (the generator's
# original placement) so morph never permanently destroys the generator's
# intended structure -- it oscillates around it.
var _current_heights: Dictionary = {}  # Vector2i -> int


func _ready() -> void:
	_noise.seed = randi()
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_noise.frequency = 0.05


func begin() -> void:
	assert(generator != null and world != null)
	_column_keys = generator.columns.keys()
	for key in _column_keys:
		_current_heights[key] = generator.columns[key]["base_height"]


func _process(delta: float) -> void:
	if _column_keys.is_empty():
		return
	_time += delta
	_tick_timer += delta
	if _tick_timer < tick_interval:
		return
	_tick_timer = 0.0
	_step_batch()


func _step_batch() -> void:
	var n := _column_keys.size()
	if n == 0:
		return
	for _i in range(min(columns_per_tick, n)):
		var key: Vector2i = _column_keys[_cursor]
		_cursor = (_cursor + 1) % n
		_morph_column(key)


func _morph_column(key: Vector2i) -> void:
	var col: Dictionary = generator.columns[key]
	var dist_factor: float = col["dist_factor"]  # 0 at wall, 1 at center
	var amplitude: float = _falloff(dist_factor) * max_height_delta
	if amplitude < 0.5:
		return  # not worth touching, keeps outer city fully static/cheap

	var base: int = col["base_height"]
	var current: int = _current_heights[key]

	var n := _noise.get_noise_3d(key.x, key.y, _time * 0.3)
	var target := base + roundi(n * amplitude)
	target = max(target, 1)

	if target == current:
		return

	var step := sign(target - current) * max(1, roundi(morph_speed))
	var new_height: int = clampi(current + step, current - abs(step), current + abs(step))
	new_height = current + (1 if target > current else -1)
	_apply_column_height(key, current, new_height, col.get("tilted", false))
	_current_heights[key] = new_height


func _falloff(dist_factor: float) -> float:
	# Eased, not linear -- keeps the outer ~40% of the radius essentially
	# static, then ramps up toward center. Adjust exponent to taste.
	return pow(clampf(dist_factor, 0.0, 1.0), 2.0)


func _apply_column_height(key: Vector2i, old_height: int, new_height: int, tilted: bool) -> void:
	var x := key.x
	var z := key.y
	if new_height > old_height:
		for y in range(old_height + 1, new_height + 1):
			world.set_voxel_at(x, y, z, VoxelTypes.Type.CONCRETE_DARK)
	elif new_height < old_height:
		for y in range(new_height + 1, old_height + 1):
			world.set_voxel_at(x, y, z, VoxelTypes.Type.AIR)
	# Note: tilt shear from generation is NOT reapplied here on purpose --
	# morph growth/shrink happens as straight vertical layers even on
	# tilted columns. Full tilted-growth support is a good opencode task
	# once the base system is verified working (see handoff notes).
