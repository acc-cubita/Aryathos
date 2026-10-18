class_name CharacterModel
extends Node3D
## A rigged character (glTF made by tools/art/blender/arkanor_mh.py + arkanor_game.py:
## MakeHuman body on a Godot humanoid skeleton) animated from its Unit with clips from the
## Quaternius Universal Animation Libraries (art/animations, retargeted onto the humanoid
## profile at import): idle / walk / jog / sprint by ground speed (backpedal when moving
## backwards), a channel pose while casting, death and revive. Swings, spell releases and
## hits play on the upper body only, so the legs keep running. On top of the clips the neck
## and head turn toward the target, the feet are planted on uneven ground (FootPlanter) and
## a runner leans into turns. Swings leave a glowing arc behind the weapon's head; casting
## lights the hands and a rune circle. Faces -Z like every unit model.

const ARKANOR_MALE := "res://art/characters/arkanor/arkanor_male.glb"
const ARKANOR_FEMALE := "res://art/characters/arkanor/arkanor_female.glb"
const LIBRARIES := {
	"ual1": "res://art/animations/ual1.glb",
	"ual2": "res://art/animations/ual2.glb",
}
## state -> clip
const CLIPS := {
	"idle_loop": "ual1/Idle", "walk_loop": "ual1/Walk", "jog_loop": "ual1/Jog_Fwd", "run_loop": "ual1/Sprint",
	"back_loop": "ual1/Jog_Fwd", "cast_loop": "ual1/Spell_Simple_Idle", "death": "ual1/Death01",
	"hit": "ual1/Hit_Chest", "spell": "ual1/Spell_Simple_Shoot",
}
## An armed character's weapon hand keeps this clip's closed fist whatever else it does.
const ARMED_IDLE := "ual1/Sword_Idle"
const SWINGS := ["ual2/Sword_Regular_A", "ual2/Sword_Regular_B", "ual2/Sword_Regular_C", "ual1/Sword_Attack"]
## Ground speeds (m/s) of the clips on the library's mannequin, measured on the libraries'
## root-motion versions; strides scale with the character's leg length (MANNEQUIN_HIPS).
const WALK_SPEED := 0.97
const RUN_SPEED := 8.25 ## the sprint
const BACK_SPEED := 5.36 ## the jog, played backwards
const MANNEQUIN_HIPS := 0.917
const JOG_SPEED := 5.36
const RUN_FROM := 2.8 ## m/s where walking turns into a jog
const SPRINT_FROM := 6.0 ## m/s where the jog turns into a sprint
const PAINTED := preload("res://units/shaders/character.gdshader")
## What a character can hold in its right fist. In weapon space +Y runs along the haft from
## the fist and -Z points the way the edge faces; root -> edge is where the swing's glow arc
## runs. "painted" weapons use the hand-painted character shader, the others their own
## scanned materials.
const WEAPONS := {
	"rune_axe": {"path": "res://art/weapons/rune_axe.glb", "painted": true,
			"root": Vector3(0, 0.82, -0.06), "edge": Vector3(0, 0.82, -0.44)},
	"pick": {"path": "res://art/weapons/pick.glb", "painted": false,  # tools/art/blender/scavenger.py
			"root": Vector3(0, 0.77, 0), "edge": Vector3(0, 0.78, -0.24)},
}
const UPPER_BODY := ["Spine", "Chest", "UpperChest", "Neck", "Head", "LeftShoulder", "LeftUpperArm",
		"LeftLowerArm", "LeftHand", "RightShoulder", "RightUpperArm", "RightLowerArm", "RightHand"]
const FINGERS := ["Thumb", "Index", "Middle", "Ring", "Little"]
const LOOPS := ["idle_loop", "walk_loop", "jog_loop", "run_loop", "back_loop", "cast_loop"]
## Neck and head turn toward what the character fights (share of the turn each takes);
## past these angles (deg: sideways, up/down) they stop turning.
const LOOK := {"Neck": 0.4, "Head": 0.65}
const LOOK_LIMITS := Vector2(70.0, 30.0)
## Most a runner leans into a turn (rad), and how much per (rad/s of turn x m/s of speed).
const MAX_LEAN := 0.14
const LEAN := 0.012
## Parts of the MakeHuman meshes (by material name) drawn as alpha-tested strands.
const STRANDS := ["beard", "moustache", "ponytail", "braid", "bun", "hair", "eyebrow", "eyelash", "short0", "long0", "bob0", "afro"]
## Loose cloth seen from inside too (into a hood, up a sleeve).
const DOUBLE_SIDED := ["hood", "robe", "cloak", "cape"]
## While a swing may leave a glow arc (seconds after it starts, how long); the arc itself
## appears where the weapon's head moves fast (WeaponTrail.speed_range).
const SWING_ARC := Vector2(0.1, 0.75)

var _unit: Unit
var _tree: AnimationTree
var _playback: AnimationNodeStateMachinePlayback
var _state := ""
var _cast_finished_at := -1.0
var _attack_clip: AnimationNodeAnimation
var _swing := 0
var _trail: WeaponTrail
var _hand_glows: Array[GPUParticles3D] = []
var _armed := false
## the character's leg length against the mannequin's
var _stride := 1.0
## where the neck and head look (world space, moved every frame)
var _look_target := Marker3D.new()
var _planter: FootPlanter
var _skeleton: Skeleton3D
var _steps: Footsteps
var _last_yaw := 0.0
var _lean := 0.0


## path: a character scene (ARKANOR_*, the scavenger...). weapon: a WEAPONS key, or empty
## for empty hands. glow tints the swing arcs (and the placeholder axe's rune).
static func create(path: String, glow := Color(0.4, 0.85, 1.0), weapon := "rune_axe") -> CharacterModel:
	var model := CharacterModel.new()
	model.name = "Model"
	model._armed = weapon != ""
	var scene := (load(path) as PackedScene).instantiate() as Node3D
	scene.rotation.y = PI  # glTF faces +Z, units face -Z
	model.add_child(scene)
	_dress(scene)
	var skeleton := scene.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	if model._armed:
		var spec: Dictionary = WEAPONS[weapon]
		var hand := BoneAttachment3D.new()
		hand.bone_name = "RightHand"
		skeleton.add_child(hand)
		var axe: Node3D
		if ResourceLoader.exists(spec.path):
			axe = (load(spec.path) as PackedScene).instantiate() as Node3D
			axe.name = "Weapon"
			if spec.painted:
				_paint(axe)
			else:
				_dress(axe)
		else:
			axe = PlaceholderModel.axe(glow)
		axe.transform = _grip(skeleton)
		hand.add_child(axe)
		model._trail = WeaponTrail.new()
		model._trail.base = spec.root
		model._trail.tip = spec.edge
		model._trail.tint = glow
		axe.add_child(model._trail)
	for bone_name: String in ["LeftHand", "RightHand"]:
		var palm := BoneAttachment3D.new()
		palm.bone_name = bone_name
		skeleton.add_child(palm)
		var glow_particles := Vfx.hand_glow()
		glow_particles.position = Vector3(0, 0.09, 0)  # toward the fingers
		palm.add_child(glow_particles)
		model._hand_glows.append(glow_particles)
	model._look_target.top_level = true
	model.add_child(model._look_target)
	for bone_name: String in LOOK:
		var look := LookAtModifier3D.new()
		look.name = bone_name + "Look"
		look.bone_name = bone_name
		look.forward_axis = SkeletonModifier3D.BONE_AXIS_PLUS_Z  # the rig faces +Z
		look.primary_rotation_axis = Vector3.AXIS_Y
		look.use_angle_limitation = true
		look.symmetry_limitation = true
		look.primary_limit_angle = deg_to_rad(LOOK_LIMITS.x)
		look.secondary_limit_angle = deg_to_rad(LOOK_LIMITS.y)
		look.duration = 0.4
		look.transition_type = Tween.TRANS_SINE
		look.influence = LOOK[bone_name]
		skeleton.add_child(look)
		look.target_node = look.get_path_to(model._look_target)
	model._skeleton = skeleton
	model._steps = Footsteps.new(skeleton, ["LeftFoot", "RightFoot"])
	model._planter = FootPlanter.new()
	model._planter.name = "FootPlanter"
	skeleton.add_child(model._planter)
	model._build_tree(scene, skeleton)
	return model


## Hand-painted look for every mesh of an imported scene (the rune axe): the baked colour
## and glow maps go into the character shader; meshes join the "units" render layer.
static func _paint(root: Node3D) -> void:
	for mesh: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		mesh.layers = PlaceholderModel.RENDER_LAYER
		var imported := mesh.mesh.surface_get_material(0) as StandardMaterial3D
		if imported:
			var painted := ShaderMaterial.new()
			painted.shader = PAINTED
			painted.set_shader_parameter("paint", imported.albedo_texture)
			painted.set_shader_parameter("glow", imported.emission_texture)
			mesh.material_override = painted


## The scanned MakeHuman materials as imported, tuned per part: hair, beard, brows and
## lashes are alpha-tested strands seen from both sides, skin scatters light under its
## surface, the eyes' cornea is cut out of their texture; cloth stays opaque (hoods and
## robes show their inside).
static func _dress(root: Node3D) -> void:
	for mesh: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		mesh.layers = PlaceholderModel.RENDER_LAYER
		for surface in mesh.mesh.get_surface_count():
			var imported := mesh.mesh.surface_get_material(surface) as StandardMaterial3D
			if imported == null:
				continue
			var material := imported.duplicate() as StandardMaterial3D
			var part := imported.resource_name.to_lower()
			if STRANDS.any(func(word: String) -> bool: return word in part):
				material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
				material.alpha_scissor_threshold = 0.35
				material.alpha_antialiasing_mode = BaseMaterial3D.ALPHA_ANTIALIASING_ALPHA_TO_COVERAGE
				material.cull_mode = BaseMaterial3D.CULL_DISABLED
			elif part.begins_with("high-poly"):
				material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
				material.alpha_scissor_threshold = 0.5
			elif part.begins_with("body"):
				material.subsurf_scatter_enabled = true
				material.subsurf_scatter_strength = 0.25
				material.subsurf_scatter_skin_mode = true
			else:
				material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
				if DOUBLE_SIDED.any(func(word: String) -> bool: return word in part):
					material.cull_mode = BaseMaterial3D.CULL_DISABLED
			mesh.set_surface_override_material(surface, material)


## Weapon transform in the right hand's space: the handle runs through the closed
## fist along the RightGrip -> RightGripTip marker bones (toward the thumb), the
## edge faces down the fingers. Solved in skeleton space, so it does not
## depend on the bones' axis conventions.
static func _grip(skeleton: Skeleton3D) -> Transform3D:
	var hand := skeleton.get_bone_global_rest(skeleton.find_bone("RightHand"))
	var grip := skeleton.get_bone_global_rest(skeleton.find_bone("RightGrip")).origin
	var tip := skeleton.get_bone_global_rest(skeleton.find_bone("RightGripTip")).origin
	var fingers := skeleton.get_bone_global_rest(skeleton.find_bone("RightMiddleProximal")).origin - hand.origin
	var handle := (tip - grip).normalized()
	var blade := (fingers - handle * fingers.dot(handle)).normalized()
	var axe := Basis(handle.cross(-blade), handle, -blade)  # axe: +Y handle, -Z blade
	return hand.affine_inverse() * Transform3D(axe, grip)


func _build_tree(scene: Node3D, skeleton: Skeleton3D) -> void:
	var player := AnimationPlayer.new()
	player.name = "Animations"
	scene.add_child(player)  # its root, the scene, owns %GeneralSkeleton, which the clips drive
	for library: String in LIBRARIES:
		player.add_animation_library(library, load(LIBRARIES[library]))
	_stride = skeleton.motion_scale / MANNEQUIN_HIPS
	var clips := CLIPS.duplicate()
	for anim_name: String in LOOPS:
		player.get_animation(clips[anim_name]).loop_mode = Animation.LOOP_LINEAR
	var states := AnimationNodeStateMachine.new()
	for anim_name: String in LOOPS + ["death"]:
		var clip := AnimationNodeAnimation.new()
		clip.animation = clips[anim_name]
		if anim_name == "back_loop":
			clip.play_mode = AnimationNodeAnimation.PLAY_MODE_BACKWARD
		states.add_node(anim_name, clip)
	for a: String in LOOPS + ["death"]:
		for b: String in LOOPS + ["death"]:
			if a != b:
				var t := AnimationNodeStateMachineTransition.new()
				t.xfade_time = 0.15 if b == "death" else 0.25
				states.add_transition(a, b, t)
	var start := AnimationNodeStateMachineTransition.new()
	start.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO
	states.add_transition("Start", "idle_loop", start)

	var blend := AnimationNodeBlendTree.new()
	blend.add_node("states", states)
	var pace := AnimationNodeTimeScale.new()
	blend.add_node("pace", pace)
	blend.connect_node("pace", 0, "states")
	var last := "pace"
	if _armed:
		# the weapon hand stays closed round the haft whatever the body does
		var fist := AnimationNodeBlend2.new()
		fist.filter_enabled = true
		var grip := player.get_animation(ARMED_IDLE)
		for track in grip.get_track_count():
			var bone := String(grip.track_get_path(track).get_concatenated_subnames())
			if bone.begins_with("Right") and FINGERS.any(func(f: String) -> bool: return f in bone):
				fist.set_filter_path(grip.track_get_path(track), true)
		var hold := AnimationNodeAnimation.new()
		hold.animation = ARMED_IDLE
		blend.add_node("fist", fist)
		blend.add_node("hold", hold)
		blend.connect_node("fist", 0, last)
		blend.connect_node("fist", 1, "hold")
		last = "fist"
	for shot_name: String in ["hit", "spell", "attack"]:
		var shot := AnimationNodeOneShot.new()
		shot.fadein_time = 0.08
		shot.fadeout_time = 0.25
		shot.filter_enabled = true
		var clip := AnimationNodeAnimation.new()
		clip.animation = SWINGS[0] if shot_name == "attack" else clips[shot_name]
		var anim := player.get_animation(clip.animation)
		for track in anim.get_track_count():
			var path := anim.track_get_path(track)
			var bone := String(path.get_concatenated_subnames())
			if bone in UPPER_BODY or FINGERS.any(func(f: String) -> bool: return f in bone):
				shot.set_filter_path(path, true)
		blend.add_node(shot_name + "_shot", shot)
		blend.add_node(shot_name + "_clip", clip)
		if shot_name == "attack":
			_attack_clip = clip
		blend.connect_node(shot_name + "_shot", 0, last)
		blend.connect_node(shot_name + "_shot", 1, shot_name + "_clip")
		last = shot_name + "_shot"
	blend.connect_node("output", 0, last)

	_tree = AnimationTree.new()
	_tree.name = "AnimationTree"
	scene.add_child(_tree)
	_tree.anim_player = _tree.get_path_to(player)
	_tree.tree_root = blend
	_tree.active = true
	if _armed:
		_tree.set("parameters/fist/blend_amount", 1.0)


func _ready() -> void:
	_unit = get_parent() as Unit
	_look_ahead()
	if _unit == null:
		return  # a preview (character window): just breathe
	_planter.unit = _unit
	_last_yaw = global_rotation.y
	_unit.attacked.connect(_on_attacked)
	_unit.cast_started.connect(func(ability: AbilityData) -> void:
		for particles in _hand_glows:
			Vfx.set_tint(particles, ability.color)
			particles.emitting = true)
	_unit.cast_ended.connect(func(_success: bool) -> void:
		for particles in _hand_glows:
			particles.emitting = false)
	Vfx.follow_casts(_unit)
	_unit.damaged.connect(func(_amount: int, _source: Unit) -> void: _fire("hit"))
	_unit.cast_ended.connect(func(success: bool) -> void:
		if success:
			_cast_finished_at = Game.time
			_fire("spell"))
	_unit.died.connect(func(_killer: Unit) -> void: _go("death"))
	_unit.revived.connect(func() -> void:
		_state = ""
		_states().start("idle_loop"))


func _process(delta: float) -> void:
	if _unit == null or _unit.is_dead:
		return
	_steps.update(_skeleton, _unit, delta)
	var ground := Vector2(_unit.velocity.x, _unit.velocity.z)
	var speed := ground.length()
	var facing := -_unit.global_transform.basis.z
	_aim_look()
	_lean_into_turns(delta, speed)
	var pace := 1.0
	if speed > 0.3:
		# each gait plays as fast as the feet travel, for this character's leg length
		if ground.dot(Vector2(facing.x, facing.z)) < -0.5 * speed:
			_go("back_loop")
			pace = clampf(speed / (BACK_SPEED * _stride), 0.5, 1.6)
		elif speed >= SPRINT_FROM:
			_go("run_loop")
			pace = clampf(speed / (RUN_SPEED * _stride), 0.55, 1.4)
		elif speed >= RUN_FROM:
			_go("jog_loop")
			pace = clampf(speed / (JOG_SPEED * _stride), 0.5, 1.4)
		else:
			_go("walk_loop")
			pace = clampf(speed / (WALK_SPEED * _stride), 0.6, 1.8)
	elif _unit.casting != null:
		_go("cast_loop")
	else:
		_go("idle_loop")
	_tree.set("parameters/pace/scale", pace)


## Neck and head turn toward the unit's target while it is alive and near; otherwise ahead.
func _aim_look() -> void:
	var target := _unit.target
	if target != null and is_instance_valid(target) and target != _unit and not target.is_dead:
		var at := target.global_position + Vector3.UP * 1.1
		if at.distance_to(global_position) < 25.0:
			_look_target.global_position = at
			return
	_look_ahead()


func _look_ahead() -> void:
	_look_target.global_position = global_position + Vector3.UP * 1.55 - global_transform.basis.z * 6.0


## A runner leans into a turn: the faster the turn and the run, the more.
func _lean_into_turns(delta: float, speed: float) -> void:
	var yaw := global_rotation.y
	var turn := wrapf(yaw - _last_yaw, -PI, PI) / maxf(delta, 0.001)
	_last_yaw = yaw
	var want := clampf(turn * speed * LEAN, -MAX_LEAN, MAX_LEAN)
	_lean = lerpf(_lean, want, 1.0 - exp(-6.0 * delta))
	rotation.z = _lean


func _go(state: String) -> void:
	if state != _state:
		_state = state
		_states().travel(state)


func _states() -> AnimationNodeStateMachinePlayback:
	if _playback == null:
		_playback = _tree.get("parameters/states/playback")
	return _playback


func _fire(shot: String) -> void:
	if _unit != null and _unit.is_dead:
		return
	_tree.set("parameters/%s_shot/request" % shot, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


func _on_attacked() -> void:
	# a spell that just finished its cast is released by the spell clip, not an axe swing
	if absf(Game.time - _cast_finished_at) > 0.05:
		_swing = (_swing + 1) % SWINGS.size()
		_attack_clip.animation = SWINGS[_swing]
		_fire("attack")
		if _trail:
			_trail.swing(SWING_ARC.x, SWING_ARC.y)
