class_name AtmosphereManager
extends Node

## Manages discrete atmosphere presets with smooth transitions.
## Picks a random base state at match start, then cycles through new
## random targets on a timer. Fog density oscillates gently on top
## of the preset value but is clamped to never get oppressive.

# ---------------------------------------------------------------------------
# Node references -- wired in _ready via get_parent()
# ---------------------------------------------------------------------------
var _world_env: WorldEnvironment
var _key_light: DirectionalLight3D
var _fill_light: DirectionalLight3D
var _omni_blue: OmniLight3D
var _omni_magenta: OmniLight3D
var _omni_orange: OmniLight3D
var _env: Environment
var _sky_mat: ProceduralSkyMaterial

# ---------------------------------------------------------------------------
# Tunables
# ---------------------------------------------------------------------------
@export var transition_duration: float = 300.0   ## seconds for a full lerp
@export var hold_duration: float = 300.0         ## seconds to stay in a state
@export var fog_density_floor: float = 0.003     ## never below this
@export var fog_density_ceiling: float = 0.04    ## never above this
@export var fog_pulse_speed: float = 0.08        ## oscillation speed (rads/s)
@export var fog_pulse_amplitude: float = 0.006   ## how much fog drifts

# ---------------------------------------------------------------------------
# Preset data
# ---------------------------------------------------------------------------
var _presets: Dictionary = {
	"dark_neon_night": {
		"sky_top":        Color(0.04, 0.04, 0.08),
		"sky_horizon":    Color(0.1, 0.08, 0.12),
		"ground_bottom":  Color(0.05, 0.04, 0.06),
		"ground_horizon": Color(0.1, 0.08, 0.12),
		"ambient_color":  Color(0.08, 0.07, 0.1),
		"ambient_energy": 0.35,
		"fog_color":      Color(0.08, 0.06, 0.1),
		"fog_density":    0.008,
		"sun_color":      Color(1.0, 0.95, 0.85),
		"sun_energy":     0.7,
		"sun_pitch":      45.0,
		"fill_color":     Color(0.25, 0.3, 0.55),
		"fill_energy":    0.22,
		"omni_energy":    0.5,
	},
	"evening": {
		"sky_top":        Color(0.07, 0.03, 0.12),
		"sky_horizon":    Color(0.28, 0.12, 0.06),
		"ground_bottom":  Color(0.05, 0.03, 0.06),
		"ground_horizon": Color(0.22, 0.1, 0.06),
		"ambient_color":  Color(0.14, 0.07, 0.08),
		"ambient_energy": 0.42,
		"fog_color":      Color(0.2, 0.09, 0.06),
		"fog_density":    0.014,
		"sun_color":      Color(1.0, 0.62, 0.32),
		"sun_energy":     0.55,
		"sun_pitch":      22.0,
		"fill_color":     Color(0.3, 0.12, 0.25),
		"fill_energy":    0.25,
		"omni_energy":    0.45,
	},
	"cloudy_grey": {
		"sky_top":        Color(0.1, 0.11, 0.14),
		"sky_horizon":    Color(0.17, 0.18, 0.22),
		"ground_bottom":  Color(0.07, 0.07, 0.09),
		"ground_horizon": Color(0.15, 0.15, 0.18),
		"ambient_color":  Color(0.13, 0.13, 0.16),
		"ambient_energy": 0.52,
		"fog_color":      Color(0.14, 0.14, 0.17),
		"fog_density":    0.028,
		"sun_color":      Color(0.62, 0.65, 0.75),
		"sun_energy":     0.32,
		"sun_pitch":      58.0,
		"fill_color":     Color(0.18, 0.18, 0.25),
		"fill_energy":    0.3,
		"omni_energy":    0.35,
	},
	"toxic_green": {
		"sky_top":        Color(0.03, 0.06, 0.04),
		"sky_horizon":    Color(0.08, 0.14, 0.08),
		"ground_bottom":  Color(0.03, 0.05, 0.03),
		"ground_horizon": Color(0.06, 0.1, 0.06),
		"ambient_color":  Color(0.06, 0.1, 0.06),
		"ambient_energy": 0.38,
		"fog_color":      Color(0.06, 0.1, 0.06),
		"fog_density":    0.018,
		"sun_color":      Color(0.7, 1.0, 0.6),
		"sun_energy":     0.45,
		"sun_pitch":      35.0,
		"fill_color":     Color(0.1, 0.3, 0.15),
		"fill_energy":    0.3,
		"omni_energy":    0.4,
	},
	"blood_moon": {
		"sky_top":        Color(0.06, 0.02, 0.02),
		"sky_horizon":    Color(0.2, 0.05, 0.04),
		"ground_bottom":  Color(0.04, 0.02, 0.02),
		"ground_horizon": Color(0.15, 0.04, 0.03),
		"ambient_color":  Color(0.12, 0.04, 0.04),
		"ambient_energy": 0.4,
		"fog_color":      Color(0.15, 0.04, 0.04),
		"fog_density":    0.012,
		"sun_color":      Color(1.0, 0.4, 0.3),
		"sun_energy":     0.6,
		"sun_pitch":      18.0,
		"fill_color":     Color(0.4, 0.08, 0.1),
		"fill_energy":    0.28,
		"omni_energy":    0.5,
	},
	"cold_blue": {
		"sky_top":        Color(0.02, 0.04, 0.1),
		"sky_horizon":    Color(0.06, 0.1, 0.2),
		"ground_bottom":  Color(0.02, 0.03, 0.07),
		"ground_horizon": Color(0.05, 0.08, 0.15),
		"ambient_color":  Color(0.05, 0.08, 0.15),
		"ambient_energy": 0.38,
		"fog_color":      Color(0.04, 0.06, 0.12),
		"fog_density":    0.01,
		"sun_color":      Color(0.6, 0.75, 1.0),
		"sun_energy":     0.5,
		"sun_pitch":      50.0,
		"fill_color":     Color(0.15, 0.2, 0.5),
		"fill_energy":    0.25,
		"omni_energy":    0.45,
	},
	"burning_orange": {
		"sky_top":        Color(0.08, 0.03, 0.01),
		"sky_horizon":    Color(0.3, 0.12, 0.03),
		"ground_bottom":  Color(0.05, 0.02, 0.01),
		"ground_horizon": Color(0.2, 0.08, 0.02),
		"ambient_color":  Color(0.15, 0.07, 0.03),
		"ambient_energy": 0.45,
		"fog_color":      Color(0.2, 0.08, 0.02),
		"fog_density":    0.016,
		"sun_color":      Color(1.0, 0.7, 0.3),
		"sun_energy":     0.65,
		"sun_pitch":      15.0,
		"fill_color":     Color(0.4, 0.15, 0.05),
		"fill_energy":    0.3,
		"omni_energy":    0.55,
	},
	"void_purple": {
		"sky_top":        Color(0.03, 0.02, 0.06),
		"sky_horizon":    Color(0.08, 0.05, 0.15),
		"ground_bottom":  Color(0.02, 0.01, 0.04),
		"ground_horizon": Color(0.06, 0.04, 0.1),
		"ambient_color":  Color(0.06, 0.04, 0.1),
		"ambient_energy": 0.32,
		"fog_color":      Color(0.05, 0.03, 0.08),
		"fog_density":    0.022,
		"sun_color":      Color(0.8, 0.5, 1.0),
		"sun_energy":     0.4,
		"sun_pitch":      40.0,
		"fill_color":     Color(0.2, 0.1, 0.4),
		"fill_energy":    0.2,
		"omni_energy":    0.4,
	},
}

var _preset_keys: Array = _presets.keys()

# Current / transition state
var _current: Dictionary = {}
var _from: Dictionary = {}
var _to: Dictionary = {}
var _transition_t: float = 0.0
var _hold_timer: float = 0.0
var _is_transitioning: bool = false
var _rng := RandomNumberGenerator.new()
var _fog_time: float = 0.0


func _ready() -> void:
	_wire_nodes()
	_apply_initial_state()


func _process(delta: float) -> void:
	if _is_transitioning:
		_transition_t += delta
		var raw := clampf(_transition_t / transition_duration, 0.0, 1.0)
		var t := raw * raw * (3.0 - 2.0 * raw)
		_current = _lerp_presets(_from, _to, t)
		_apply(_current)
		if _transition_t >= transition_duration:
			_is_transitioning = false
			_hold_timer = hold_duration
	else:
		_hold_timer -= delta
		if _hold_timer <= 0.0:
			_begin_transition()

	# Dynamic fog oscillation
	_fog_time += delta
	if _env != null:
		var base_fd: float = _current.get("fog_density", 0.01)
		var pulse := sin(_fog_time * fog_pulse_speed) * fog_pulse_amplitude
		_env.fog_density = clampf(base_fd + pulse, fog_density_floor, fog_density_ceiling)

	# Slowly rotate the fill lights so lighting doesn't feel frozen
	# in one direction.
	_rotate_fill_lights(delta)


# ---------------------------------------------------------------------------
# Wiring
# ---------------------------------------------------------------------------

func _wire_nodes() -> void:
	var main := get_parent() as Node3D
	if main == null:
		return
	_world_env = main.get_node_or_null("WorldEnvironment") as WorldEnvironment
	_key_light = main.get_node_or_null("Sun") as DirectionalLight3D
	_fill_light = main.get_node_or_null("FillLight") as DirectionalLight3D
	_omni_blue = main.get_node_or_null("FillBlue") as OmniLight3D
	_omni_magenta = main.get_node_or_null("FillMagenta") as OmniLight3D
	_omni_orange = main.get_node_or_null("FillOrange") as OmniLight3D
	if _world_env != null:
		_env = _world_env.environment
		if _env.sky != null:
			_sky_mat = _env.sky.sky_material as ProceduralSkyMaterial


func _apply_initial_state() -> void:
	var key: String = _preset_keys[_rng.randi() % _preset_keys.size()]
	_current = _presets[key].duplicate()
	_apply(_current)


func _begin_transition() -> void:
	_from = _current.duplicate()
	var key: String = _preset_keys[_rng.randi() % _preset_keys.size()]
	_to = _presets[key].duplicate()
	_transition_t = 0.0
	_is_transitioning = true


# ---------------------------------------------------------------------------
# Preset lerp
# ---------------------------------------------------------------------------

func _lerp_presets(a: Dictionary, b: Dictionary, t: float) -> Dictionary:
	var out := {}
	for k in a:
		var va = a[k]
		var vb = b[k]
		if va is Color:
			out[k] = va.lerp(vb, t)
		elif va is float:
			out[k] = lerpf(va, vb, t)
		else:
			out[k] = va
	return out


# ---------------------------------------------------------------------------
# Apply to scene
# ---------------------------------------------------------------------------

func _apply(v: Dictionary) -> void:
	# Sky
	if _sky_mat != null:
		_sky_mat.sky_top_color = v["sky_top"]
		_sky_mat.sky_horizon_color = v["sky_horizon"]
		_sky_mat.ground_bottom_color = v["ground_bottom"]
		_sky_mat.ground_horizon_color = v["ground_horizon"]

	# Ambient
	if _env != null:
		_env.ambient_light_color = v["ambient_color"]
		_env.ambient_light_energy = v["ambient_energy"]

	# Fog (base value; dynamic pulse is applied in _process)
	if _env != null:
		_env.fog_light_color = v["fog_color"]
		_env.fog_density = v["fog_density"]

	# Key light (Sun)
	if _key_light != null:
		_key_light.light_color = v["sun_color"]
		_key_light.light_energy = v["sun_energy"]
		var pitch_deg: float = v["sun_pitch"]
		_key_light.rotation.x = -deg_to_rad(pitch_deg)

	# Fill light (directional)
	if _fill_light != null:
		_fill_light.light_color = v["fill_color"]
		_fill_light.light_energy = v["fill_energy"]

	# Omni fill lights -- base energy from preset, colors stay fixed
	var oe: float = v.get("omni_energy", 0.5)
	if _omni_blue != null:
		_omni_blue.light_energy = oe
	if _omni_magenta != null:
		_omni_magenta.light_energy = oe * 0.8
	if _omni_orange != null:
		_omni_orange.light_energy = oe * 0.65


# ---------------------------------------------------------------------------
# Fill light rotation -- slowly orbit so lighting shifts over time
# ---------------------------------------------------------------------------

func _rotate_fill_lights(delta: float) -> void:
	var rot_speed := 0.02  # radians per second
	if _omni_blue != null:
		_omni_blue.position.x = -80.0 * cos(_fog_time * rot_speed)
		_omni_blue.position.z = -80.0 * sin(_fog_time * rot_speed)
	if _omni_magenta != null:
		_omni_magenta.position.x = 80.0 * cos(_fog_time * rot_speed + TAU / 3.0)
		_omni_magenta.position.z = 80.0 * sin(_fog_time * rot_speed + TAU / 3.0)
	if _omni_orange != null:
		_omni_orange.position.x = 40.0 * cos(_fog_time * rot_speed + TAU * 2.0 / 3.0)
		_omni_orange.position.z = 40.0 * sin(_fog_time * rot_speed + TAU * 2.0 / 3.0)
