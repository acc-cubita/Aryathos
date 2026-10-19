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
## A hero's look (character creation): which hair and beard meshes show, by the MakeHuman
## asset they were made from (tools/art/blender/arkanor_game.py HERO_VARIANTS), the face
## (a blend shape made from MakeHuman's face sliders, arkanor_mh.py "faces"; the first face
## is the model as built), and the hair, skin and eye colours. Options are [shown name, parts].
## outfits: the parts each class wears (ClassData.outfit) over what every hero wears.
const LOOKS := {
	"male": {"path": ARKANOR_MALE, "shoulders_forward": 12.0,
		"hair": [["Ponytail", ["ponytail01"]], ["Short", ["short02"]], ["Long", ["long01"]], ["Braid", ["braid01"]]],
		"beard": [["Scruffy", ["elvs_scruffy_beard1", "rehmanpolanski_moustache_viking"]], ["Full", ["grinsegold_full_beard"]],
				["Braided", ["rehmanpolanski_beard_viking"]], ["None", []]],
		"face": [["Weathered", ""], ["Noble", "face_noble"], ["Stern", "face_stern"], ["Hawk", "face_hawk"]],
		"outfits": {"runeknight": ["rehmanpolanski_viking_tunic", "rehmanpolanski_viking_pants"],
				"aethermancer": ["donitz_monk_robe", "donitz_monk_robe_hood_off"]}},
	"female": {"path": ARKANOR_FEMALE, "grip_roll": 13.0,
		"hair": [["Braided Bun", ["elvs_braid_bun"]], ["Long", ["long01"]], ["Braid", ["braid01"]], ["Short", ["short03"]]],
		"beard": [["None", []]],
		"face": [["Determined", ""], ["Noble", "face_noble"], ["Fierce", "face_fierce"], ["Gentle", "face_gentle"]],
		"outfits": {"runeknight": ["culturalibre_heroine_boots_1"],
				"aethermancer": ["donitz_monk_robe", "donitz_monk_robe_hood_off", "toigo_ankle_boots_female"]}},
}
## (grip_roll: degrees the weapon turns about the fingers in that model's fist; the female
## wrist rests rolled 13 degrees further in, which would tip the axe across her body.
## shoulders_forward: degrees the collarbones turn forward, SpineUpright.shoulders_forward.)
## Arkanor are silver-haired even in youth: the hero hair is silvered bright and tinted down.
const HAIR_COLORS := [["White", Color(1, 1, 1)], ["Silver", Color(0.78, 0.79, 0.82)], ["Ash", Color(0.66, 0.62, 0.56)],
		["Steel", Color(0.55, 0.62, 0.74)], ["Smoke", Color(0.42, 0.42, 0.44)]]
const SKIN_TONES := [["Fair", Color(1, 1, 1)], ["Light", Color(0.94, 0.86, 0.78)], ["Tan", Color(0.82, 0.68, 0.56)],
		["Bronze", Color(0.66, 0.52, 0.42)]]
## MakeHuman's eye textures (CC0), art/characters/arkanor/eyes/<file>.png.
const EYE_COLORS := [["Ice", "ice"], ["Pale Blue", "lightblue"], ["Blue", "blue"], ["Deep Blue", "deepblue"],
		["Blue-Green", "bluegreen"], ["Green", "green"], ["Grey", "grey"], ["Amber", "brownlight"], ["Brown", "brown"]]
const EYES := "res://art/characters/arkanor/eyes/%s.png"
const DEFAULT_LOOK := {"gender": "male", "face": 0, "hair": 0, "hair_color": 1, "skin": 0, "eyes": 1, "beard": 0}
const LIBRARIES := {
	"ual1": "res://art/animations/ual1.glb",
	"ual2": "res://art/animations/ual2.glb",
	# our own, keyed in Blender (tools/art/blender/hero_moves.py)
	"moves": "res://art/animations/hero_moves.glb",
}
## state -> clip
const CLIPS := {
	"idle_loop": "ual1/Idle", "walk_loop": "ual1/Walk", "jog_loop": "moves/Run", "run_loop": "ual1/Sprint",
	"back_loop": "ual1/Jog_Fwd", "cast_loop": "ual1/Spell_Simple_Idle", "death": "ual1/Death01",
	"hit": "ual1/Hit_Chest", "spell": "ual1/Spell_Simple_Shoot",
	"jump_start": "ual1/Jump_Start", "fall_loop": "ual1/Jump", "land": "ual1/Jump_Land",
}
## An armed character's weapon hand keeps this clip's closed fist whatever else it does.
const ARMED_IDLE := "ual1/Sword_Idle"
const SWINGS := ["ual2/Sword_Regular_A", "ual2/Sword_Regular_B", "ual2/Sword_Regular_C", "ual1/Sword_Attack"]
## Ground speeds (m/s) of the clips on the library's mannequin, measured on the libraries'
## root-motion versions; strides scale with the character's leg length (MANNEQUIN_HIPS).
const WALK_SPEED := 0.97
const RUN_SPEED := 8.25 ## the sprint
## the backwards walk/jog mix (BACK_JOG), from the two clips' strides over BACK_CYCLE
const BACK_SPEED := (0.97 * 1.333 * (1.0 - BACK_JOG) + 5.36 * 0.933 * BACK_JOG) / BACK_CYCLE
const MANNEQUIN_HIPS := 0.917
## the hero's run (hero_moves.py RUN), as that script measures it on the mannequin
const JOG_SPEED := 5.0
const RUN_FROM := 2.8 ## m/s where walking turns into a jog
## m/s where the run turns into a sprint. A hero's run (6.4 m/s, WoW's 7 yards) is our
## own run cycle (hero_moves.py), keyed from a study of a reference run.
const SPRINT_FROM := 7.6
## How fast (1/s) the body turns toward the way it moves (a strafe, a diagonal).
const STRAFE_TURN := 10.0
## Turning on the spot faster than this (rad/s) shuffles the feet round.
const SHUFFLE_TURN := 1.0
## How long (s) a standing landing plays before the character stands again.
const LANDING := 0.45
## Backing off (WoW's backpedal): a slow, measured walk backwards with long steps, made of
## the walk with BACK_JOG of the jog mixed in, both played backwards on a common
## BACK_CYCLE-second step cycle (both start with the left foot ahead).
const BACK_JOG := 0.3
const BACK_CYCLE := 1.15
## Hands closed into loose fists (FIST of the boxing clip's fingers), not hanging open;
## they open to cast.
const FIST_CLIP := "ual1/Punch_Jab"
const FIST := 0.75
## A hero puts the weapon away on the back this long (s) after the fight, like WoW.
const SHEATHE_AFTER := 4.0
const PAINTED := preload("res://units/shaders/character.gdshader")
## What a character can hold in its right fist. In weapon space +Y runs along the haft from
## the fist and -Z points the way the edge faces; root -> edge is where the swing's glow arc
## runs. "painted" weapons use the hand-painted character shader, the others their own
## scanned materials. "hold": the weapon arm keeps that clip's pose while the weapon is out
## (held ready, not swung about by the run); "channel": its pose while channelling a spell;
## "middle": how far up the haft from the grip the weapon's middle is (it sits mid-back
## when sheathed).
const WEAPONS := {
	"rune_axe": {"path": "res://art/weapons/rune_axe.glb", "painted": true,
			"root": Vector3(0, 0.82, -0.06), "edge": Vector3(0, 0.82, -0.44), "hold": ARMED_IDLE, "middle": 0.28},
	"pick": {"path": "res://art/weapons/pick.glb", "painted": false,  # tools/art/blender/scavenger.py
			"root": Vector3(0, 0.77, 0), "edge": Vector3(0, 0.78, -0.24), "hold": ARMED_IDLE, "middle": 0.28},
	"crystal_staff": {"path": "res://art/weapons/crystal_staff.glb", "painted": false,  # tools/art/blender/staff.py
			"root": Vector3(0, 0.6, 0), "edge": Vector3(0, 1.12, 0), "channel": "ual1/Idle_Torch", "middle": 0.22},
}
const UPPER_BODY := ["Spine", "Chest", "UpperChest", "Neck", "Head", "LeftShoulder", "LeftUpperArm",
		"LeftLowerArm", "LeftHand", "RightShoulder", "RightUpperArm", "RightLowerArm", "RightHand"]
const FINGERS := ["Thumb", "Index", "Middle", "Ring", "Little"]
const LOOPS := ["idle_loop", "walk_loop", "jog_loop", "run_loop", "back_loop", "cast_loop", "fall_loop"]
## The states that play once: a leap off the ground (then the fall loop), a standing landing.
const ONCE := ["jump_start", "land"]
## Neck and head turn toward what the character fights (share of the turn each takes);
## past these angles (deg: sideways, up/down) they stop turning.
const LOOK := {"Neck": 0.5, "Head": 0.9}
const LOOK_LIMITS := Vector2(70.0, 30.0)
## Most a runner leans into a turn (rad), and how much per (rad/s of turn x m/s of speed):
## a touch only (WoW's runners hardly lean).
const MAX_LEAN := 0.035
const LEAN := 0.012
## Parts of the MakeHuman meshes (by material name) drawn as alpha-tested strands.
const STRANDS := ["beard", "moustache", "ponytail", "braid", "bun", "hair", "eyebrow", "eyelash", "short0", "long0", "bob0", "afro"]
## Loose cloth seen from inside too (into a hood, up a sleeve).
const DOUBLE_SIDED := ["hood", "robe", "cloak", "cape"]
## While a swing may leave a glow arc (seconds after it starts, how long); the arc itself
## appears where the weapon's head moves fast (WeaponTrail.speed_range).
const SWING_ARC := Vector2(0.1, 0.75)

## The WEAPONS key held ("" empty hands).
var weapon_key := ""

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
var _upright: SpineUpright
var _steady: HeadSteady
var _fists: Fists
var _weapon: Node3D
var _in_hand: Transform3D  # the weapon's place in the fist
var _on_back: Transform3D  # and across the back
var _hand_mount: BoneAttachment3D
var _back_mount: BoneAttachment3D
var _sheathes := false  # a hero's weapon goes on the back out of a fight
var _drawn := true
var _drawn_until := -1.0
var _heading := 0.0  # radians the body is turned from the unit's facing (_turn_to_motion)
var _backwards := false
var _turn_rate := 0.0
var _air_time := 0.0
var _landed_at := -1.0
var _skeleton: Skeleton3D
var _steps: Footsteps
var _last_yaw := 0.0
var _lean := 0.0


## path: a character scene (ARKANOR_*, the scavenger...). weapon: a WEAPONS key, or empty
## for empty hands. glow tints the swing arcs (and the placeholder axe's rune).
static func create(path: String, glow := Color(0.4, 0.85, 1.0), weapon := "rune_axe", look := {}) -> CharacterModel:
	var model := CharacterModel.new()
	model.name = "Model"
	model._armed = weapon != ""
	model.weapon_key = weapon
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
		for gender: String in LOOKS:
			if LOOKS[gender].path == path:
				axe.transform = axe.transform.rotated_local(Vector3.FORWARD, deg_to_rad(LOOKS[gender].get("grip_roll", 0.0)))
		hand.add_child(axe)
		model._weapon = axe
		model._in_hand = axe.transform
		model._on_back = _sheath(skeleton, spec.get("middle", 0.4))
		model._hand_mount = hand
		model._back_mount = BoneAttachment3D.new()
		model._back_mount.bone_name = "UpperChest"
		skeleton.add_child(model._back_mount)
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
	model._upright = SpineUpright.new()  # first: the head turns from the straightened torso
	model._upright.name = "SpineUpright"
	skeleton.add_child(model._upright)
	model._look_target.top_level = true
	model.add_child(model._look_target)
	for bone_name: String in LOOK:
		var aim := LookAtModifier3D.new()
		aim.name = bone_name + "Look"
		aim.bone_name = bone_name
		aim.forward_axis = SkeletonModifier3D.BONE_AXIS_PLUS_Z  # the rig faces +Z
		aim.primary_rotation_axis = Vector3.AXIS_Y
		aim.use_angle_limitation = true
		aim.symmetry_limitation = true
		aim.primary_limit_angle = deg_to_rad(LOOK_LIMITS.x)
		aim.secondary_limit_angle = deg_to_rad(LOOK_LIMITS.y)
		aim.duration = 0.4
		aim.transition_type = Tween.TRANS_SINE
		aim.influence = LOOK[bone_name]
		skeleton.add_child(aim)
		aim.target_node = aim.get_path_to(model._look_target)
	model._fists = Fists.new()
	model._fists.name = "Fists"
	skeleton.add_child(model._fists)
	model._steady = HeadSteady.new()  # after the look-at: the head calm and level
	model._steady.name = "HeadSteady"
	skeleton.add_child(model._steady)
	model._skeleton = skeleton
	model._steps = Footsteps.new(skeleton, ["LeftFoot", "RightFoot"])
	model._planter = FootPlanter.new()
	model._planter.name = "FootPlanter"
	skeleton.add_child(model._planter)
	model._build_tree(scene, skeleton)
	for gender: String in LOOKS:
		if LOOKS[gender].path == path:  # a hero: one hair style, one beard, its tints
			var full := DEFAULT_LOOK.duplicate()
			full.merge(look, true)
			full["gender"] = gender
			model.apply_look(full)
			model._upright.shoulders_forward = deg_to_rad(LOOKS[gender].get("shoulders_forward", 0.0))
	return model


## A hero (an Arkanor of either gender) dressed in `look` (see LOOKS; DEFAULT_LOOK's keys).
static func create_hero(look: Dictionary, glow := Color(0.4, 0.85, 1.0), weapon := "rune_axe") -> CharacterModel:
	var gender: String = look.get("gender", "male")
	return create(LOOKS.get(gender, LOOKS.male).path, glow, weapon, look)


## Shows the chosen hair and beard and the class's outfit (look.outfit; hides the others),
## shapes the chosen face (on the body and every part fitted to it) and colours hair, brows,
## skin and eyes.
func apply_look(look: Dictionary) -> void:
	var spec: Dictionary = LOOKS.get(look.get("gender", "male"), LOOKS.male)
	var hair: Array = spec.hair[clampi(int(look.get("hair", 0)), 0, spec.hair.size() - 1)][1]
	var beard: Array = spec.beard[clampi(int(look.get("beard", 0)), 0, spec.beard.size() - 1)][1]
	var face: String = spec.face[clampi(int(look.get("face", 0)), 0, spec.face.size() - 1)][1]
	var hair_tint: Color = HAIR_COLORS[clampi(int(look.get("hair_color", 1)), 0, HAIR_COLORS.size() - 1)][1]
	var skin_tint: Color = SKIN_TONES[clampi(int(look.get("skin", 0)), 0, SKIN_TONES.size() - 1)][1]
	var eyes := load(EYES % EYE_COLORS[clampi(int(look.get("eyes", 1)), 0, EYE_COLORS.size() - 1)][1]) as Texture2D
	var outfit: Array = spec.outfits.get(look.get("outfit", "runeknight"), [])
	var strands := []
	for option: Array in spec.hair + spec.beard:
		strands.append_array(option[1])
	var variants := strands.duplicate()
	for parts: Array in spec.outfits.values():
		variants.append_array(parts)
	for mesh: MeshInstance3D in find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh == null:
			continue  # the weapon's trail, before its first swing
		var part := ""
		for each: String in variants:
			if String(mesh.name).ends_with("_" + each):
				part = each
		if part != "":
			mesh.visible = part in hair or part in beard or part in outfit
		for option: Array in spec.face:
			var shape := mesh.find_blend_shape_by_name(option[1]) if option[1] != "" else -1
			if shape >= 0:
				mesh.set_blend_shape_value(shape, 1.0 if option[1] == face else 0.0)
		for surface in mesh.mesh.get_surface_count():
			var material := mesh.get_surface_override_material(surface) as StandardMaterial3D
			if material == null:
				continue
			var name := material.resource_name.to_lower()
			if part in strands or "eyebrow" in name:
				material.albedo_color = hair_tint
			elif name.begins_with("body"):
				material.albedo_color = skin_tint
			elif name.begins_with("high-poly"):
				material.albedo_texture = eyes


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
	for anim_name: String in LOOPS + ONCE + ["death"]:
		if anim_name == "back_loop":
			states.add_node(anim_name, _back_gait())
			continue
		var clip := AnimationNodeAnimation.new()
		clip.animation = clips[anim_name]
		states.add_node(anim_name, clip)
	for a: String in LOOPS + ONCE + ["death"]:
		for b: String in LOOPS + ONCE + ["death"]:
			if a != b:
				var t := AnimationNodeStateMachineTransition.new()
				t.xfade_time = 0.15 if b in ["death", "jump_start", "land"] else 0.2
				if [a, b] in [["jump_start", "fall_loop"], ["land", "idle_loop"]]:
					# a leap runs on into the fall; a landing ends standing
					t.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_AT_END
					t.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO
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
	var fists := _overlay(player, FIST_CLIP, func(bone: String) -> bool:
		return (bone.begins_with("Left") or bone.begins_with("Right")) and FINGERS.any(func(f: String) -> bool: return f in bone))
	blend.add_node("fists", fists[0])
	blend.add_node("fists_clip", fists[1])
	blend.connect_node("fists", 0, last)
	blend.connect_node("fists", 1, "fists_clip")
	last = "fists"
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
		var ready_clip: String = WEAPONS[weapon_key].get("hold", "")
		if ready_clip != "":
			# the weapon held ready at the side while it is out
			var ready := _arm_overlay(player, ready_clip)
			blend.add_node("ready", ready[0])
			blend.add_node("ready_clip", ready[1])
			blend.connect_node("ready", 0, last)
			blend.connect_node("ready", 1, "ready_clip")
			last = "ready"
		var carry_clip: String = WEAPONS[weapon_key].get("channel", "")
		if carry_clip != "":
			# a staff is held upright while channelling a spell: the weapon arm takes the
			# channel clip's pose (the release, which comes after, still takes it over)
			var carry := _arm_overlay(player, carry_clip)
			blend.add_node("carry", carry[0])
			blend.add_node("carried", carry[1])
			blend.connect_node("carry", 0, last)
			blend.connect_node("carry", 1, "carried")
			last = "carry"
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
		_tree.set("parameters/ready/blend_amount", 1.0)
	_tree.set("parameters/states/back_loop/mix/blend_amount", BACK_JOG)
	_tree.set("parameters/fists/blend_amount", FIST)


## The weapon arm (right shoulder to fingers) in `clip`'s pose over whatever else plays:
## [the Blend2 that lays it on, the clip's node].
func _arm_overlay(player: AnimationPlayer, clip: String) -> Array:
	return _overlay(player, clip, func(bone: String) -> bool:
		return bone.begins_with("Right") and not ["Leg", "Foot", "Toes"].any(func(w: String) -> bool: return w in bone))


## The bones `wanted` picks in `clip`'s pose over whatever else plays: [the Blend2 that
## lays them on (input 1), the clip's node].
func _overlay(player: AnimationPlayer, clip: String, wanted: Callable) -> Array:
	var overlay := AnimationNodeBlend2.new()
	overlay.filter_enabled = true
	var anim := player.get_animation(clip)
	anim.loop_mode = Animation.LOOP_LINEAR
	for track in anim.get_track_count():
		if wanted.call(String(anim.track_get_path(track).get_concatenated_subnames())):
			overlay.set_filter_path(anim.track_get_path(track), true)
	var node := AnimationNodeAnimation.new()
	node.animation = clip
	return [overlay, node]


## Backing off: the walk and the jog, both backwards and stretched onto one step cycle so
## their feet go together, mixed by BACK_JOG (set once the tree runs).
func _back_gait() -> AnimationNodeBlendTree:
	var gait := AnimationNodeBlendTree.new()
	# [clip, where in its cycle the left foot is furthest ahead]
	for part: Array in [["walk", "ual1/Walk", 0.0], ["jog", "ual1/Jog_Fwd", 0.97 * 0.933]]:
		var clip := AnimationNodeAnimation.new()
		clip.animation = part[1]
		clip.play_mode = AnimationNodeAnimation.PLAY_MODE_BACKWARD
		clip.use_custom_timeline = true
		clip.timeline_length = BACK_CYCLE
		clip.stretch_time_scale = true
		clip.start_offset = part[2]
		clip.loop_mode = Animation.LOOP_LINEAR
		gait.add_node(part[0], clip)
	var mix := AnimationNodeBlend2.new()
	gait.add_node("mix", mix)
	gait.connect_node("mix", 0, "walk")
	gait.connect_node("mix", 1, "jog")
	gait.connect_node("output", 0, "mix")
	return gait

func _ready() -> void:
	_unit = get_parent() as Unit
	_look_ahead()
	if _unit == null:
		return  # a preview (character window): just breathe
	_planter.unit = _unit
	_last_yaw = _unit.global_rotation.y
	if _weapon and _unit is Player:
		_sheathes = true
		_set_drawn(false)
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
		_upright.weight = 0.0
		_upright.sway_weight = 0.0
		_steady.weight = 0.0 if _unit else 1.0
		return
	_steady.weight = 1.0
	_steps.update(_skeleton, _unit, delta)
	var ground := Vector2(_unit.velocity.x, _unit.velocity.z)
	var speed := ground.length()
	_aim_look()
	_lean_into_turns(delta, speed)
	# a runner stands taller than the sprint clip (fades in from a jog to a run)
	_upright.weight = move_toward(_upright.weight, clampf((speed - RUN_FROM) / (SPRINT_FROM - RUN_FROM), 0.0, 1.0), delta * 4.0)
	_turn_to_motion(delta, speed)
	# a warrior's bearing on the move: no rocking from side to side
	# (not lost to a bump in the road: the body leaves the floor for a frame now and then)
	_upright.sway_weight = move_toward(_upright.sway_weight, 1.0 if speed > 0.3 and _air_time < 0.2 else 0.0, delta * 4.0)
	_planter.settle_weight = _upright.sway_weight
	if _sheathes:
		# out while auto-attacking and as long as the fight goes on; away a while after
		if _unit.auto_attacking or (_drawn and _unit.in_combat()):
			_drawn_until = Game.time + SHEATHE_AFTER
		if _drawn != (Game.time < _drawn_until):
			_set_drawn(not _drawn)
	var pace := 1.0
	if not _unit.is_on_floor():
		# a leap, then the fall (also off a ledge, once clearly in the air)
		_air_time += delta
		if _unit.velocity.y > 1.0 and _state not in ["jump_start", "fall_loop"]:
			_go("jump_start")
		elif _air_time > 0.2 and _state not in ["jump_start", "fall_loop"]:
			_go("fall_loop")
	else:
		_air_time = 0.0
		if _state in ["jump_start", "fall_loop"] and speed <= 0.3:
			_go("land")  # a runner lands running; one standing lands with bent knees
			_landed_at = Game.time
		elif _state == "land" and speed <= 0.3 and Game.time < _landed_at + LANDING:
			pass
		elif speed > 0.3:
			# each gait plays as fast as the feet travel, for this character's leg length
			if _backwards:
				_go("back_loop")
				pace = clampf(speed / (BACK_SPEED * _stride), 0.5, 1.6)
			elif speed >= SPRINT_FROM:
				_go("run_loop")
				pace = clampf(speed / (RUN_SPEED * _stride), 0.55, 1.4)
			elif speed >= RUN_FROM:
				_go("jog_loop")
				pace = clampf(speed / (JOG_SPEED * _stride), 0.5, 1.8)
			else:
				_go("walk_loop")
				pace = clampf(speed / (WALK_SPEED * _stride), 0.6, 1.8)
		elif absf(_turn_rate) > SHUFFLE_TURN and _unit.casting == null:
			_go("walk_loop")  # turning on the spot: the feet shuffle round
			pace = 0.9
		elif _unit.casting != null:
			_go("cast_loop")
		else:
			_go("idle_loop")
	_tree.set("parameters/pace/scale", pace)


## Like WoW, the body turns the way it moves: a quarter round for a diagonal, sideways for
## a strafe; backing off diagonally, its back turns toward the motion. The head keeps
## looking ahead or at the target (_aim_look), as far as the neck turns.
func _turn_to_motion(delta: float, speed: float) -> void:
	var want := 0.0
	_backwards = false
	if speed > 0.3:
		var local := _unit.global_transform.basis.inverse() * _unit.velocity
		var angle := atan2(local.x, -local.z)  # 0 ahead, +PI/2 to the right
		_backwards = absf(angle) > deg_to_rad(100.0)
		want = wrapf(angle + PI, -PI, PI) if _backwards else clampf(angle, -PI * 0.5, PI * 0.5)
	_heading = lerp_angle(_heading, want, 1.0 - exp(-STRAFE_TURN * delta))
	rotation.y = -_heading


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
	# ahead of the unit, not of the body (which turns toward a strafe)
	var facing := (_unit.global_transform.basis.z if _unit else global_transform.basis.z)
	_look_target.global_position = global_position + Vector3.UP * 1.55 - facing * 6.0


## A runner leans into a turn: the faster the turn and the run, the more.
func _lean_into_turns(delta: float, speed: float) -> void:
	var yaw := _unit.global_rotation.y  # the unit's own turning, not a strafe's
	var turn := wrapf(yaw - _last_yaw, -PI, PI) / maxf(delta, 0.001)
	_last_yaw = yaw
	_turn_rate = turn
	var want := clampf(turn * speed * LEAN, -MAX_LEAN, MAX_LEAN)
	_lean = lerpf(_lean, want, 1.0 - exp(-6.0 * delta))
	rotation.z = _lean


func _go(state: String) -> void:
	if state != _state:
		_state = state
		_states().travel(state)
		if (_tree.tree_root as AnimationNodeBlendTree).has_node("carry"):
			create_tween().tween_property(_tree, "parameters/carry/blend_amount", 1.0 if state == "cast_loop" else 0.0, 0.25)
		# the hands open to channel a spell
		create_tween().tween_property(_tree, "parameters/fists/blend_amount", 0.0 if state == "cast_loop" else FIST, 0.25)


func _states() -> AnimationNodeStateMachinePlayback:
	if _playback == null:
		_playback = _tree.get("parameters/states/playback")
	return _playback


func _fire(shot: String) -> void:
	if _unit != null and _unit.is_dead:
		return
	_tree.set("parameters/%s_shot/request" % shot, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


## The weapon in the hand (held ready) or across the back (hands free to swing as the
## character runs), like WoW's drawn and sheathed weapons.
func _set_drawn(drawn: bool) -> void:
	_drawn = drawn
	if drawn:
		_weapon.reparent(_hand_mount, false)
		_weapon.transform = _in_hand
	else:
		_weapon.reparent(_back_mount, false)
		_weapon.transform = _on_back
	var tree_root := _tree.tree_root as AnimationNodeBlendTree
	for overlay: String in ["fist", "ready"]:
		if tree_root.has_node(overlay):
			_tree.set("parameters/%s/blend_amount" % overlay, 1.0 if drawn else 0.0)


## Where a sheathed weapon rides, in the UpperChest bone's frame: its middle (`middle` m up
## the haft from the grip) at the middle of the back, the haft slanting up toward the left
## shoulder, the head above it, the edge looking out to the left, flat to the back. (The
## rig faces +Z; its right is -X.)
static func _sheath(skeleton: Skeleton3D, middle: float) -> Transform3D:
	var chest := skeleton.get_bone_global_rest(skeleton.find_bone("UpperChest"))
	var haft := Vector3(0.6, 1.0, 0.0).normalized()
	var grip := Vector3(0.0, chest.origin.y - 0.08, chest.origin.z - 0.21) - haft * middle
	var edge := Vector3.RIGHT - haft * haft.x
	edge = edge.normalized()
	return chest.affine_inverse() * Transform3D(Basis(haft.cross(-edge), haft, -edge), grip)


func _on_attacked() -> void:
	# a spell that just finished its cast is released by the spell clip, not an axe swing
	if absf(Game.time - _cast_finished_at) > 0.05:
		if _sheathes and not _drawn:  # a swing brings the weapon out
			_drawn_until = Game.time + SHEATHE_AFTER
			_set_drawn(true)
		_swing = (_swing + 1) % SWINGS.size()
		_attack_clip.animation = SWINGS[_swing]
		_fire("attack")
		if _trail:
			_trail.swing(SWING_ARC.x, SWING_ARC.y)
