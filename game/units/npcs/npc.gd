class_name Npc
extends Unit
## A friendly character the player can talk to (right-click it, or target it and press F).
## Shows WoW quest markers: yellow ! = quest available, yellow ? = ready to hand in,
## grey ? = quest in progress.

const QUEST_YELLOW := Color(1.0, 0.82, 0.0)

@export var npc_id: StringName
## Shown under the name in tooltips, e.g. "Keeper of the Wardstone".
@export var title := ""
@export_multiline var greeting := "Greetings, traveler."
@export var quests: Array[QuestData] = []
## The faction this NPC belongs to; its merchants give discounts by your standing.
@export var reputation_faction: FactionData
## Professions this NPC teaches; any NPC with some is a trainer.
@export var teaches: Array[ProfessionData] = []
## Items this NPC sells; any NPC with stock is a merchant.
@export var vendor_items: Array[ItemData] = []
@export var armor_color := Color(0.5, 0.45, 0.4)
@export var glow_color := Color(0.3, 0.7, 1.0)
## A rigged character scene (CharacterModel.ARKANOR_*); empty keeps the placeholder.
@export_file("*.glb") var model_scene := ""

var _marker := Label3D.new()


func _ready() -> void:
	faction = Faction.FRIENDLY
	level = 10
	max_health = 600
	health = max_health
	super()
	add_to_group("npcs")
	if model_scene != "":
		model = CharacterModel.create(model_scene, glow_color, "")
	else:
		model = PlaceholderModel.humanoid(armor_color, glow_color)
	add_child(model)
	_marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_marker.font_size = 160
	_marker.pixel_size = 0.008
	_marker.outline_size = 28
	_marker.layers = PlaceholderModel.RENDER_LAYER
	_marker.position.y = body_height + 1.9
	add_child(_marker)


func interact(_player: Player) -> void:
	Game.npc_interacted.emit(self)


func _think(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	# Turn to face the player when they come close.
	var player := Game.player
	if player and global_position.distance_to(player.global_position) < 8.0:
		_face(player.global_position, delta)
	move_and_slide()


func _process(_delta: float) -> void:
	var waiting := false
	_marker.text = quest_marker_text()
	if _marker.text == "":
		waiting = not Game.player.quest_log.turn_ins_for(npc_id).is_empty()
		_marker.text = "?" if waiting else ""
	_marker.modulate = Color(0.6, 0.6, 0.6) if waiting else QUEST_YELLOW


## Yellow marker: "?" when a quest is ready to hand in here, "!" when one is on offer.
func quest_marker_text() -> String:
	var quest_log := Game.player.quest_log
	for quest in quest_log.turn_ins_for(npc_id):
		if quest_log.state(quest) == QuestLog.State.READY:
			return "?"
	for quest in quests:
		if quest_log.state(quest) == QuestLog.State.AVAILABLE:
			return "!"
	return ""
