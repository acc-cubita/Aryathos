class_name WeaponTrail
extends MeshInstance3D
## A glowing ribbon left behind by a blade. Two points on the weapon (`base` and `tip`,
## in the weapon's space) are sampled every frame while a swing is on, and drawn as a
## strip that fades out over `fade` seconds; it only shows where the blade moves fast,
## so wind-ups and follow-throughs leave nothing. Add as a child of the weapon; it draws
## in world space, so the arc stays where the blade went even while the wielder runs.

## Inner end of the ribbon (on the weapon, near the haft).
@export var base := Vector3.ZERO
## Outer end of the ribbon (the blade's edge).
@export var tip := Vector3(0, 1, 0)
## Seconds a stretch of ribbon takes to fade.
@export var fade := 0.24
@export var tint := Color(0.4, 0.85, 1.0)
## Blade speeds (m/s) between which the ribbon fades in.
@export var speed_range := Vector2(3.0, 9.0)

const SUBSTEPS := 4  # smoothing points between two sampled frames

var _samples: Array[PackedVector3Array] = []  # [base, tip] per frame
var _ages: PackedFloat32Array = []
var _strengths: PackedFloat32Array = []
var _last_tip := Vector3.INF
var _on_from := INF
var _on_until := -INF
var _clock := 0.0
var _strip := ImmediateMesh.new()


func _ready() -> void:
	top_level = true
	transform = Transform3D.IDENTITY
	mesh = _strip
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	material_override = Vfx.glow_material(tint, null, 0, 4.0)
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


## Leave a trail from `delay` to `delay + duration` seconds from now.
func swing(delay: float, duration: float) -> void:
	_on_from = _clock + delay
	_on_until = _clock + delay + duration


func _process(delta: float) -> void:
	_clock += delta
	for i in _ages.size():
		_ages[i] += delta
	while _ages.size() > 0 and _ages[0] > fade:
		_ages.remove_at(0)
		_strengths.remove_at(0)
		_samples.pop_front()
	var xf := (get_parent() as Node3D).get_global_transform_interpolated()
	var edge := xf * tip
	if _clock >= _on_from and _clock <= _on_until and _last_tip != Vector3.INF and delta > 0.0:
		var speed := edge.distance_to(_last_tip) / delta
		_samples.append(PackedVector3Array([xf * base, edge]))
		_ages.append(0.0)
		_strengths.append(smoothstep(speed_range.x, speed_range.y, speed))
	_last_tip = edge
	_draw()


func _draw() -> void:
	_strip.clear_surfaces()
	var count := _samples.size()
	if count < 2:
		return
	_strip.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in count - 1:
		for s in SUBSTEPS:
			var t := float(s) / SUBSTEPS
			_vertex_pair(i, t)
	_vertex_pair(count - 2, 1.0)
	_strip.surface_end()


## One cross-section of the ribbon, Catmull-Rom smoothed between samples i and i + 1.
func _vertex_pair(i: int, t: float) -> void:
	var count := _samples.size()
	var p0 := _samples[maxi(i - 1, 0)]
	var p1 := _samples[i]
	var p2 := _samples[i + 1]
	var p3 := _samples[mini(i + 2, count - 1)]
	var age := lerpf(_ages[i], _ages[i + 1], t)
	var life := clampf(1.0 - age / fade, 0.0, 1.0) * lerpf(_strengths[i], _strengths[i + 1], t)
	for k in 2:
		var point := _catmull(p0[k], p1[k], p2[k], p3[k], t)
		# dim toward the haft, bright along the edge, fading with age
		_strip.surface_set_color(Color(1, 1, 1, life * (0.15 if k == 0 else 1.0)))
		_strip.surface_add_vertex(point)


static func _catmull(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((2.0 * p1) + (p2 - p0) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (3.0 * p1 - p0 - 3.0 * p2 + p3) * t3)
