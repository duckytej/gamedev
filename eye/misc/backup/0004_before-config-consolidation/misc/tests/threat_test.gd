extends SceneTree

## Headless test for the peripheral-vision threat detector, the azimuth fold and
## the silhouette highlighter. No renderer required; exits non-zero on failure.
##
##   godot --headless --script res://misc/tests/threat_test.gd
##
## It builds a tiny world (camera looking down -Z, a handful of highlightable
## probes and one occluder), runs a detection pass and verifies zoning, distance
## intensity, line-of-sight occlusion, the 70..110 -> 30..70 fold, and that one
## ghost silhouette is placed per eligible threat (and only for those).

var _checks := 0
var _failures := 0


func _initialize() -> void:
	_test_fold()
	await _test_detection()
	print("threat_test: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _check(label: String, condition: bool) -> void:
	_checks += 1
	if condition:
		print("  ok   ", label)
	else:
		_failures += 1
		printerr("  FAIL ", label)
		push_error("threat_test failed: " + label)


## The highlighter folds over-the-shoulder angles back onto the near band:
## 70 stays at the edge, 80/90/110 march toward the 30 deg centre boundary, and
## the middle +/-30 deg is never reached.
func _test_fold() -> void:
	var detector := ThreatDetector.new()

	for a in [70.0, 80.0, 90.0, 100.0, 110.0, -70.0, -90.0, -110.0]:
		var folded := detector.fold_deg(a)

		if absf(a) == 70.0:
			_check("fold %+.0f stays on the edge" % a, absf(absf(folded) - 70.0) < 1e-3)
		elif absf(a) == 110.0:
			_check("fold %+.0f reaches the 30 deg boundary" % a, absf(absf(folded) - 30.0) < 1e-3)
		else:
			_check("fold %+.0f lands inside 30..70" % a,
				absf(folded) >= 30.0 and absf(folded) <= 70.0)

	_check("fold keeps the side (positive stays right)", detector.fold_deg(90.0) > 0.0)
	_check("fold keeps the side (negative stays left)", detector.fold_deg(-90.0) < 0.0)
	_check("fold of a forward angle does not cross the centre",
		absf(detector.fold_deg(0.0)) < 1e-3)

	# Sweep the whole peripheral zone: the middle 60 deg must stay untouched.
	var centre_clear := true
	for deg in range(70, 111):
		if absf(detector.fold_deg(float(deg))) < 30.0 - 1e-6:
			centre_clear = false
	_check("no folded angle enters the middle 60 deg", centre_clear)

	detector.free()


func _test_detection() -> void:
	var world := Node3D.new()
	root.add_child(world)

	# Minimal player: a node in the "player" group with a camera under Neck,
	# matching what EyePlayer exposes. The camera looks down -Z by default.
	var player := Node3D.new()
	player.name = "Player"
	player.add_to_group(&"player")
	world.add_child(player)
	var neck := Node3D.new()
	neck.name = "Neck"
	player.add_child(neck)
	var camera := Camera3D.new()
	camera.name = "Camera3D"
	camera.fov = 140.0
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	neck.add_child(camera)

	var detector := ThreatDetector.new()
	detector.config = ThreatConfig.new()  # defaults: 70 / 110 / 4..22 / 30
	detector.detect_interval = 0.0
	world.add_child(detector)

	var highlighter := ThreatHighlighter.new()
	world.add_child(highlighter)

	var forward := _add_probe(world, Vector3(0, 0, -13), "Forward")
	var rear := _add_probe(world, Vector3(0, 0, 13), "Rear")
	var left := _add_probe(world, Vector3(-8, 0, 0), "LeftClear")
	var right := _add_probe(world, Vector3(13, 0, 0), "RightClear")
	var blocked := _add_probe(world, Vector3(-16, 0, 5), "LeftBlocked")

	# An occluder sitting on the ray to LeftBlocked only. Thin in Z so the
	# straight-left LeftClear ray slips past it.
	_add_occluder(world, Vector3(0.5, 4, 2), Vector3(-5, 0, 1.6))

	await physics_frame
	await physics_frame
	detector.refresh_now()

	var by_name := {}
	for threat in detector.threats:
		by_name[String(threat.target.name)] = threat

	_check("forward object is excluded", not by_name.has("Forward"))
	_check("rear object is excluded", not by_name.has("Rear"))
	_check("left peripheral object is detected", by_name.has("LeftClear"))
	_check("right peripheral object is detected", by_name.has("RightClear"))
	_check("occluded object is excluded", not by_name.has("LeftBlocked"))
	_check("exactly two eligible threats", detector.threats.size() == 2)

	if by_name.has("LeftClear"):
		var t: Threat = by_name["LeftClear"]
		_check("left object azimuth is ~-90", absf(t.azimuth_deg + 90.0) < 2.0)
		_check("left object is peripheral", t.zone == Threat.Zone.PERIPHERAL)
		_check("left object has LOS", t.los)
	if by_name.has("RightClear"):
		var t: Threat = by_name["RightClear"]
		_check("right object azimuth is ~+90", absf(t.azimuth_deg - 90.0) < 2.0)

	if by_name.has("LeftClear") and by_name.has("RightClear"):
		var near: Threat = by_name["LeftClear"]   # 8 m
		var far: Threat = by_name["RightClear"]   # 13 m
		_check("closer object is brighter", near.intensity > far.intensity)

	_check("classify 0 -> forward", detector.classify_deg(0.0) == Threat.Zone.FORWARD)
	_check("classify 69 -> forward", detector.classify_deg(69.0) == Threat.Zone.FORWARD)
	_check("classify 90 -> peripheral", detector.classify_deg(90.0) == Threat.Zone.PERIPHERAL)
	_check("classify -90 -> peripheral", detector.classify_deg(-90.0) == Threat.Zone.PERIPHERAL)
	_check("classify 150 -> rear", detector.classify_deg(150.0) == Threat.Zone.REAR)

	# --- Highlighter ---------------------------------------------------------
	_check("one ghost per eligible threat", highlighter._ghosts.size() == 2)
	_check("no ghost for forward/rear/occluded",
		not highlighter._ghosts.has(forward)
		and not highlighter._ghosts.has(rear)
		and not highlighter._ghosts.has(blocked))
	_check("ghosts are visible", _ghost_visible(highlighter, left)
		and _ghost_visible(highlighter, right))

	# A body at -90 must be redrawn at the folded -50 bearing, same distance.
	var left_ghost := _ghost(highlighter, left)
	if left_ghost != null:
		var offset := left_ghost.global_position - camera.global_position
		var az := rad_to_deg(atan2(offset.x, -offset.z))
		_check("left ghost folds to ~-50 deg", absf(az + 50.0) < 1.5)
		_check("left ghost keeps its distance", absf(offset.length() - 8.0) < 1e-3)

	var right_ghost := _ghost(highlighter, right)
	if right_ghost != null:
		var offset := right_ghost.global_position - camera.global_position
		var az := rad_to_deg(atan2(offset.x, -offset.z))
		_check("right ghost folds to ~+50 deg", absf(az - 50.0) < 1.5)
		_check("right ghost keeps its distance", absf(offset.length() - 13.0) < 1e-3)


func _ghost(highlighter: ThreatHighlighter, body: Node3D) -> Node3D:
	if highlighter._ghosts.has(body):
		return highlighter._ghosts[body]
	return null


func _ghost_visible(highlighter: ThreatHighlighter, body: Node3D) -> bool:
	var ghost := _ghost(highlighter, body)
	return ghost != null and ghost.visible


func _add_probe(parent: Node3D, at: Vector3, label: String) -> Node3D:
	var probe := Node3D.new()
	probe.name = label
	probe.position = at
	probe.add_to_group(&"highlightable")
	parent.add_child(probe)
	return probe


func _add_occluder(parent: Node3D, size: Vector3, at: Vector3) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.position = at
	parent.add_child(body)
