class_name CameraRig
extends Node3D
## WoW-style third-person camera.
## Left drag orbits the camera, right drag also steers the character,
## mouse wheel zooms. A short click (no drag) emits `clicked` for targeting.

signal clicked(button: int, screen_position: Vector2)

const MOUSE_SENSITIVITY := 0.0045
const MIN_PITCH := -1.45
const MAX_PITCH := 0.9
const DRAG_THRESHOLD := 4.0
const PIVOT_HEIGHT := 1.7
const FOLLOW_SPEED := 3.0

@export var min_zoom := 1.5
@export var max_zoom := 30.0
@export var zoom_step := 1.6
@export var start_zoom := 9.0

var yaw := 0.0
var pitch := -0.32

var _character: Player
var _zoom := 9.0
var _left := false
var _right := false
var _dragging := false
var _press_position := Vector2.ZERO

@onready var spring_arm: SpringArm3D = $SpringArm3D
@onready var camera: Camera3D = $SpringArm3D/Camera3D


func _ready() -> void:
	# Follows the character manually so it does not inherit its rotation.
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_character = get_parent() as Player
	_zoom = start_zoom
	spring_arm.spring_length = _zoom
	spring_arm.collision_mask = Unit.LAYER_WORLD
	var probe := SphereShape3D.new()
	probe.radius = 0.25
	spring_arm.shape = probe


func snap_behind() -> void:
	yaw = _character.rotation.y
	_update_transform()


## Sets the view directly (used by tools and cutscenes).
func set_view(new_yaw: float, new_pitch: float, distance: float) -> void:
	yaw = new_yaw
	pitch = new_pitch
	_zoom = distance
	spring_arm.spring_length = distance
	_update_transform()


func is_steering() -> bool:
	return _right


func both_buttons_held() -> bool:
	return _left and _right


func follow_character_turn(amount: float) -> void:
	if not _left:
		yaw += amount


func _process(delta: float) -> void:
	# Recover if a button was released outside the window.
	if _left and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_release(MOUSE_BUTTON_LEFT, false)
	if _right and not Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		_release(MOUSE_BUTTON_RIGHT, false)
	# While running, swing the camera back behind the character.
	if not _left and not _right and _character.forward_input != 0.0:
		yaw = lerp_angle(yaw, _character.rotation.y, 1.0 - exp(-FOLLOW_SPEED * delta))
	spring_arm.spring_length = lerpf(spring_arm.spring_length, _zoom, 1.0 - exp(-12.0 * delta))
	_update_transform()


func _update_transform() -> void:
	global_position = _character.get_global_transform_interpolated().origin + Vector3.UP * PIVOT_HEIGHT
	rotation = Vector3(pitch, yaw, 0.0)


func _unhandled_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button:
		match button.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if button.pressed:
					_zoom = clampf(_zoom - zoom_step, min_zoom, max_zoom)
			MOUSE_BUTTON_WHEEL_DOWN:
				if button.pressed:
					_zoom = clampf(_zoom + zoom_step, min_zoom, max_zoom)
			MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT:
				if button.pressed:
					_press(button.button_index, button.position)
				else:
					_release(button.button_index, true)
		return
	var motion := event as InputEventMouseMotion
	if motion and (_left or _right):
		if not _dragging:
			if motion.position.distance_to(_press_position) < DRAG_THRESHOLD:
				return
			_dragging = true
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			return
		yaw -= motion.relative.x * MOUSE_SENSITIVITY
		pitch = clampf(pitch - motion.relative.y * MOUSE_SENSITIVITY, MIN_PITCH, MAX_PITCH)
		if _right:
			_steer()


func _press(button: int, at: Vector2) -> void:
	if not _left and not _right:
		_press_position = at
		_dragging = false
	if button == MOUSE_BUTTON_LEFT:
		_left = true
	else:
		_right = true
		_steer()


func _release(button: int, emit_click: bool) -> void:
	if button == MOUSE_BUTTON_LEFT:
		if not _left:
			return
		_left = false
	else:
		if not _right:
			return
		_right = false
	if emit_click and not _dragging:
		clicked.emit(button, _press_position)
	if not _left and not _right and _dragging:
		_dragging = false
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		get_viewport().warp_mouse(_press_position)


## Right mouse held: the character turns to face where the camera looks.
func _steer() -> void:
	if not _character.is_dead:
		_character.rotation.y = yaw
