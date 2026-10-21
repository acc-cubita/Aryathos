class_name BeastModel
extends Node3D
## A four-legged creature (glTF made by tools/art/blender/beasts.py from Sketchfab models:
## the wolf and the bear, clips under plain names) animated from its Unit: idle / walk /
## trot / run by ground speed, each paced to how fast its paws travel; attacks and the
## death play on the whole body, hits on the front half only (the legs keep running).
## A long cast rears the beast up on its hind legs until the cast ends (the bear's roar),
## then it slams down. Glowing crystals grow from its back, and the body leans with the
## slope under it. Faces -Z like every unit model.

## Per beast: scene, size (model units are metres), gaits as [clip, ground speed (m/s at
## size 1), speed from which it is used], clips, the bones a hit shakes (name prefixes),
## and the crystals: [bone, spot beside its head (scene space, m: x sideways, y forward),
## lean (deg: x back/forward, z sideways), radius, height]; each grows from the coat
## right above its spot.
const WOLF_FRONT := ["Brust", "Hals", "Kopf", "Unterkiefer", "Ohr", "Mau", "MundW", "Bauch.003"]
const WOLF_PAWS := ["Vorderpfote_L_Wolf_Skeleton", "Vorderpfote_R_Wolf_Skeleton", "Pfote2_L_Wolf_Skeleton",
		"Pfote2_R_Wolf_Skeleton"]
const WOLF := {
	"path": "res://art/creatures/wolf.glb", "size": 1.45,
	"gaits": [["walk", 0.40, 0.0], ["run", 3.57, 2.2]],
	"attacks": ["bite"], "hit": "hit", "death": "death",
	"front": WOLF_FRONT,
	"fur": Color(0.55, 0.52, 0.5),
	"paws": WOLF_PAWS,
	"crystals": [
		["Brust_Wolf_Skeleton", Vector2(0.0, 0.0), Vector3(-25, 0, 10), 0.03, 0.2],
		["Brust_Wolf_Skeleton", Vector2(0.025, -0.05), Vector3(-35, 0, -25), 0.022, 0.14],
		["Bauch.001_Wolf_Skeleton", Vector2(-0.02, 0.0), Vector3(-30, 0, 20), 0.024, 0.15],
		["Bauch_Wolf_Skeleton", Vector2(0.01, 0.0), Vector3(-40, 0, -15), 0.018, 0.1],
	],
}
const BEAR := {
	"path": "res://art/creatures/bear.glb", "size": 1.0,
	"gaits": [["walk", 1.05, 0.0], ["trot", 4.92, 2.4], ["run", 8.2, 6.6]],
	"attacks": ["swipe", "swipe2", "lunge"], "hit": "hit", "death": "death",
	"combat_idle": "angry", "rear": "rear", "rear_hold": "rear_hold", "slam": "swipe",
	"paws": ["RigLFLegDigit11_018", "RigRFLegDigit11_033", "RigLBLegDigit11_06", "RigRBLegDigit11_010"],
	"front": ["RigChest", "RigNeck", "RigHead", "RigJaw", "RigTongue", "RigLEyelid", "RigREyelid", "RigRigLEar", "RigRigREar"],
	"crystals": [
		["RigChest_013", Vector2(0.0, 0.0), Vector3(-15, 0, 8), 0.09, 0.62],
		["RigChest_013", Vector2(0.14, -0.1), Vector3(-25, 0, -30), 0.07, 0.42],
		["RigChest_013", Vector2(-0.14, 0.06), Vector3(-20, 0, 32), 0.065, 0.38],
		["RigSpine2_012", Vector2(0.04, 0.0), Vector3(-30, 0, -12), 0.075, 0.5],
		["RigSpine2_012", Vector2(-0.12, -0.12), Vector3(-35, 0, 28), 0.055, 0.32],
		["RigSpine1_011", Vector2(0.07, 0.05), Vector3(-40, 0, -18), 0.05, 0.3],
	],
}
## The canyons' dust coyote: the wolf, smaller, short-coated (no fur cards: no ruff), its
## coat (`coat` tints the body's skin) the canyon's sandy tan, no crystals.
const COYOTE := {
	"path": "res://art/creatures/wolf.glb", "size": 1.1,
	"gaits": [["walk", 0.40, 0.0], ["run", 3.57, 2.2]],
	"attacks": ["bite"], "hit": "hit", "death": "death",
	"front": WOLF_FRONT,
	"fur": Color.TRANSPARENT,
	"coat": Color(1.55, 1.2, 0.82),
	"paws": WOLF_PAWS,
	"crystals": [],
	"voice": "wolf",
}
const BEASTS := {"wolf": WOLF, "bear": BEAR, "coyote": COYOTE}
## Below this ground speed (m/s) the beast stands.
const MOVING := 0.3
## How far (m, at size 1) ahead of and behind its middle the beast feels the ground's slope.
const REACH := 0.5

## Where each beast's crystals grow (see _place_crystals), worked out once per beast.
static var _placements := {}

var _unit: Unit
var _spec: Dictionary
var _size := 1.0
var _tree: AnimationTree
var _playback: AnimationNodeStateMachinePlayback
var _state := ""
var _attack_clip: AnimationNodeAnimation
var _attack := 0
var _tilt := Vector2.ZERO
var _skeleton: Skeleton3D
var _steps: Footsteps


## beast: a BEASTS key. glow colours the crystals; scale multiplies the beast's own size.
static func create(beast: String, glow: Color, scale_by := 1.0) -> BeastModel:
	var model := BeastModel.new()
	model.name = "Model"
	model._spec = BEASTS[beast]
	model._size = model._spec.size * scale_by
	var scene := (load(model._spec.path) as PackedScene).instantiate() as Node3D
	scene.rotation.y = PI  # glTF faces +Z, units face -Z
	scene.scale = Vector3.ONE * model._size
	model.add_child(scene)
	_dress(scene, model._spec.get("fur", Color.WHITE), model._spec.get("coat", Color.WHITE))
	var skeleton := scene.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	_grow_crystals(beast, scene, skeleton, glow)
	model._skeleton = skeleton
	model._steps = Footsteps.new(skeleton, model._spec.paws)
	model._build_tree(scene)
	return model


## Fur cards are alpha-tested strands seen from both sides, tinted by `fur` to blend into
## the coat (a transparent `fur`: none), which `coat` tints (not eyes, teeth or claws);
## every mesh joins the units layer.
static func _dress(root: Node3D, fur: Color, coat: Color) -> void:
	for mesh: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		mesh.layers = PlaceholderModel.RENDER_LAYER
		for surface in mesh.mesh.get_surface_count():
			var imported := mesh.mesh.surface_get_material(surface) as StandardMaterial3D
			if imported == null:
				continue
			if imported.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED:
				var part := imported.resource_name.to_lower()
				if coat != Color.WHITE and not ["eye", "teeth", "claw"].any(func(skip: String) -> bool: return skip in part):
					var skin := imported.duplicate() as StandardMaterial3D
					skin.albedo_color *= coat
					mesh.set_surface_override_material(surface, skin)
				continue
			var material := imported.duplicate() as StandardMaterial3D
			material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
			material.alpha_scissor_threshold = 0.4
			material.alpha_antialiasing_mode = BaseMaterial3D.ALPHA_ANTIALIASING_ALPHA_TO_COVERAGE
			material.cull_mode = BaseMaterial3D.CULL_DISABLED
			material.albedo_color *= fur
			mesh.set_surface_override_material(surface, material)
			mesh.visible = fur.a > 0.0


## Glowing shards on the back, carried by the spine bones.
static func _grow_crystals(beast: String, scene: Node3D, skeleton: Skeleton3D, glow: Color) -> void:
	if not _placements.has(beast):
		_placements[beast] = _place_crystals(scene, skeleton, BEASTS[beast].crystals)
	var material := StandardMaterial3D.new()
	material.albedo_color = glow
	material.roughness = 0.25
	material.emission_enabled = true
	material.emission = glow
	material.emission_energy_multiplier = 2.2
	var attachments := {}
	for placement: Array in _placements[beast]:
		var bone_name: String = placement[0]
		if not attachments.has(bone_name):
			var attachment := BoneAttachment3D.new()
			attachment.bone_name = bone_name
			skeleton.add_child(attachment)
			attachments[bone_name] = attachment
		var shard := MeshInstance3D.new()
		shard.mesh = placement[2]
		shard.material_override = material
		shard.layers = PlaceholderModel.RENDER_LAYER
		shard.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		shard.transform = placement[1]
		(attachments[bone_name] as Node3D).add_child(shard)


## Where each crystal grows: [bone, transform in the bone's space, mesh]. The base sits a
## little under the coat right above the crystal's spot (the opaque meshes in their bind
## pose, which the bones carry).
static func _place_crystals(scene: Node3D, skeleton: Skeleton3D, crystals: Array) -> Array:
	var surface := PackedVector3Array()
	var skeleton_to_scene := _to_scene(skeleton, scene)
	for mesh: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
		var mesh_to_scene := _to_scene(mesh, scene)
		var skin := mesh.skin
		if skin != null and skin.get_bind_count() > 0:
			# a skinned mesh's vertices live in its bind space, whatever its node says
			var bind_bone := skin.get_bind_bone(0)
			if bind_bone < 0:
				bind_bone = skeleton.find_bone(skin.get_bind_name(0))
			mesh_to_scene = skeleton_to_scene * skeleton.get_bone_global_rest(bind_bone) * skin.get_bind_pose(0)
		for index in mesh.mesh.get_surface_count():
			var material := mesh.mesh.surface_get_material(index) as BaseMaterial3D
			if material != null and material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
				continue  # fur cards
			for vertex: Vector3 in mesh.mesh.surface_get_arrays(index)[Mesh.ARRAY_VERTEX]:
				surface.append(mesh_to_scene * vertex)
	var to_scene := _to_scene(skeleton, scene)
	var out := []
	for crystal: Array in crystals:
		var bone := skeleton.find_bone(crystal[0])
		if bone < 0:
			continue
		var rest := to_scene * skeleton.get_bone_global_rest(bone)
		var offset: Vector2 = crystal[1]
		var radius: float = crystal[3]
		var height: float = crystal[4]
		var spot := rest.origin + Vector3(offset.x, 0.0, offset.y)
		var reach := maxf(radius * 2.0, 0.05)
		var top := rest.origin.y
		for point in surface:
			if absf(point.x - spot.x) < reach and absf(point.z - spot.z) < reach:
				top = maxf(top, point.y)
		spot.y = top - radius * 0.6
		var lean: Vector3 = crystal[2]
		var place := Transform3D(Basis.from_euler(Vector3(deg_to_rad(lean.x), 0.0, deg_to_rad(lean.z))), spot)
		# the cone's middle is its origin: half its height up puts the base on the spot
		out.append([String(crystal[0]), rest.affine_inverse() * place * Transform3D(Basis.IDENTITY, Vector3(0, height * 0.5, 0)),
				PlaceholderModel._crystal(radius, height)])
	return out


## A node's transform in the space of its ancestor `root`.
static func _to_scene(node: Node3D, root: Node3D) -> Transform3D:
	var out := Transform3D.IDENTITY
	var at: Node = node
	while at != root:
		out = (at as Node3D).transform * out
		at = at.get_parent()
	return out


func _build_tree(scene: Node3D) -> void:
	var player := scene.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	var loops: Array[String] = ["idle"]
	for gait: Array in _spec.gaits:
		loops.append(gait[0])
	for key in ["combat_idle", "rear_hold"]:
		if _spec.has(key):
			loops.append(_spec[key])
	for clip in loops:
		player.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	var states := AnimationNodeStateMachine.new()
	var names: Array[String] = loops.duplicate()
	names.append(_spec.death)
	if _spec.has("rear"):
		names.append(_spec.rear)
	for clip in names:
		var node := AnimationNodeAnimation.new()
		node.animation = clip
		states.add_node(clip, node)
	for a in names:
		for b in names:
			if a != b:
				var t := AnimationNodeStateMachineTransition.new()
				t.xfade_time = 0.15 if b == _spec.death else 0.3
				states.add_transition(a, b, t)
	if _spec.has("rear"):
		# rearing up leads into holding it
		states.remove_transition(_spec.rear, _spec.rear_hold)
		var hold := AnimationNodeStateMachineTransition.new()
		hold.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_AT_END
		hold.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO
		hold.xfade_time = 0.2
		states.add_transition(_spec.rear, _spec.rear_hold, hold)
	var start := AnimationNodeStateMachineTransition.new()
	start.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO
	states.add_transition("Start", "idle", start)

	var blend := AnimationNodeBlendTree.new()
	blend.add_node("states", states)
	blend.add_node("pace", AnimationNodeTimeScale.new())
	blend.connect_node("pace", 0, "states")
	# the attack moves the whole beast; a hit only shakes its front half
	var hit := AnimationNodeOneShot.new()
	hit.fadein_time = 0.06
	hit.fadeout_time = 0.2
	hit.filter_enabled = true
	var hit_anim := player.get_animation(_spec.hit)
	for track in hit_anim.get_track_count():
		var path := hit_anim.track_get_path(track)
		var bone := String(path.get_concatenated_subnames())
		if (_spec.front as Array).any(func(prefix: String) -> bool: return bone.begins_with(prefix)):
			hit.set_filter_path(path, true)
	var hit_clip := AnimationNodeAnimation.new()
	hit_clip.animation = _spec.hit
	blend.add_node("hit_shot", hit)
	blend.add_node("hit_clip", hit_clip)
	blend.connect_node("hit_shot", 0, "pace")
	blend.connect_node("hit_shot", 1, "hit_clip")
	var attack := AnimationNodeOneShot.new()
	attack.fadein_time = 0.1
	attack.fadeout_time = 0.3
	_attack_clip = AnimationNodeAnimation.new()
	_attack_clip.animation = _spec.attacks[0]
	blend.add_node("attack_shot", attack)
	blend.add_node("attack_clip", _attack_clip)
	blend.connect_node("attack_shot", 0, "hit_shot")
	blend.connect_node("attack_shot", 1, "attack_clip")
	blend.connect_node("output", 0, "attack_shot")

	_tree = AnimationTree.new()
	_tree.name = "AnimationTree"
	scene.add_child(_tree)
	_tree.anim_player = _tree.get_path_to(player)
	_tree.tree_root = blend
	_tree.active = true


func _ready() -> void:
	_unit = get_parent() as Unit
	if _unit == null:
		return
	_unit.attacked.connect(_on_attacked)
	_unit.damaged.connect(func(_amount: int, _source: Unit) -> void: _fire("hit"))
	_unit.cast_ended.connect(func(success: bool) -> void:
		if success and _spec.has("slam"):
			_attack_clip.animation = _spec.slam
			_fire("attack"))
	_unit.died.connect(func(_killer: Unit) -> void:
		_tree.set("parameters/attack_shot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT)
		_go(_spec.death))
	_unit.revived.connect(func() -> void:
		_state = ""
		_states().start("idle"))
	Vfx.follow_casts(_unit)


func _process(delta: float) -> void:
	if _unit == null:
		return
	_lean_with_ground(delta)
	if _unit.is_dead:
		return
	_steps.update(_skeleton, _unit, delta)
	var speed := Vector2(_unit.velocity.x, _unit.velocity.z).length()
	var pace := 1.0
	if _unit.casting != null and _spec.has("rear") and _unit.casting.cast_time > 0.0:
		_go(_spec.rear)  # and on into rear_hold by itself
	elif speed > MOVING:
		# the fastest gait this speed reaches, as fast as its paws travel
		var gait: Array = _spec.gaits[0]
		for each: Array in _spec.gaits:
			if speed >= each[2]:
				gait = each
		_go(gait[0])
		pace = clampf(speed / (gait[1] * _size), 0.5, 1.8)
	elif _spec.has("combat_idle") and _unit.in_combat():
		_go(_spec.combat_idle)
	else:
		_go("idle")
	_tree.set("parameters/pace/scale", pace)


## The body pitches and rolls with the ground under it (felt ahead/behind and to the sides).
func _lean_with_ground(delta: float) -> void:
	var terrain: Terrain = Game.zone.terrain if Game.zone else null
	var want := Vector2.ZERO
	if terrain != null and not _unit.is_dead:
		var reach := REACH * _size
		var basis := _unit.global_transform.basis
		var ahead := -basis.z * reach
		var side := basis.x * reach * 0.5
		var at := _unit.global_position
		var front := terrain.get_height(at.x + ahead.x, at.z + ahead.z)
		var back := terrain.get_height(at.x - ahead.x, at.z - ahead.z)
		var right := terrain.get_height(at.x + side.x, at.z + side.z)
		var left := terrain.get_height(at.x - side.x, at.z - side.z)
		want = Vector2(atan2(front - back, 2.0 * reach), atan2(right - left, reach)).clampf(-0.45, 0.45)
	_tilt = _tilt.lerp(want, 1.0 - exp(-8.0 * delta))
	rotation = Vector3(_tilt.x, 0.0, _tilt.y)


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
	if _unit.casting != null:
		return  # the rear-up holds; its end slams
	var attacks: Array = _spec.attacks
	_attack = (_attack + 1) % attacks.size()
	_attack_clip.animation = attacks[_attack]
	_fire("attack")
