extends Node
## Every sound in the game. Effects play where they happen from a pool of 3D players: each
## sound is a few takes in res://audio/<set>/ (tools/art/audio_pack.py), one picked at
## random with its pitch varied a little; interface sounds play flat. Units are heard
## through their own signals (swings, bites, casts, cries, deaths, aggro) and the game's
## (hits, coins, quests, level ups, errors); models report their footsteps (Footsteps).
## The zone's ambience (wind and birds) loops softly; campfires crackle on their own.
## Music plays like WoW's: a piece, then a minute or two of quiet, then another (MUSIC,
## shuffled); a boss with its own music (EnemyData.music) brings it in while it fights the
## player. Buses: Effects, Ambience, Interface and Music under Master; their volumes are
## kept in SETTINGS (the game menu's Sound window).

const ROOT := "res://audio/"
const BUSES := ["Effects", "Ambience", "Interface", "Music"]
const POOL := 32
## How far (m) from the camera sounds are played at all.
const HEARING := 45.0
## What each kind of unit sounds like (sound sets); missing keys stay silent. "crystal"
## beasts ring when struck; "steps" is their own footfall layered over the ground's.
const VOICES := {
	"wolf": {"aggro": "wolf_aggro", "attack": "wolf_bite", "hurt": "wolf_hurt", "death": "wolf_death",
			"crystal": true, "step_volume": -22.0},
	"bear": {"aggro": "bear_aggro", "attack": "bear_attack", "hurt": "bear_hurt", "death": "bear_death",
			"crystal": true, "steps": "paw_heavy", "step_volume": -10.0},
	"scavenger": {"aggro": "human_aggro", "attack": "swing", "hurt": "human_hurt", "death": "human_death"},
	"person": {"attack": "swing", "death": "human_death"},
}
## The sound a finished cast lets go with, by ability id (others: spell_cast).
const RELEASES := {"aether_shard": "spell_shard", "storm_surge": "spell_storm", "storm_nova": "spell_storm",
		"crystal_mending": "spell_heal", "crystal_roar": "bear_roar"}
## Seconds a unit stays quiet after crying out in pain, and after its aggro call.
const HURT_PAUSE := 2.5
const AGGRO_PAUSE := 10.0
const AMBIENCE := "res://audio/ambience/birds_wind.ogg"
const AMBIENCE_VOLUME := -14.0
const MUSIC := ["res://audio/music/treasure_hunter.mp3", "res://audio/music/once_upon_a_time.mp3",
		"res://audio/music/forest_whisper.ogg", "res://audio/music/orchestra_loop.ogg"]
const MUSIC_VOLUME := -6.0
## Quiet (s) before the first piece, between pieces, and after a boss fight.
const FIRST_PIECE := 6.0
const MUSIC_PAUSE := Vector2(60.0, 150.0)
const AFTER_BOSS := 20.0
## Seconds music takes to come in or fade away.
const FADE := 3.0
const SETTINGS := "user://settings.cfg"
const DEFAULT_VOLUMES := {"Master": 1.0, "Music": 0.7, "Effects": 1.0, "Ambience": 0.8, "Interface": 0.8}

## How many times each sound set has played (the smoke test listens for them).
var played := {}
var _sets := {}
var _players: Array[AudioStreamPlayer3D] = []
var _next := 0
var _flat: Array[AudioStreamPlayer] = []
var _next_flat := 0
var _ambience := AudioStreamPlayer.new()
var _music := AudioStreamPlayer.new()
var _boss_music := AudioStreamPlayer.new()
var _playlist: Array[String] = []
var _last_piece := ""
var _clock := 0.0
var _next_piece := INF
var _boss: Enemy
var _boss_check := 0.0
var _volumes := {}
## per unit (instance id): the ability it is casting, when it last let a spell go, cried
## out, or called its kin
var _casts := {}
var _released := {}
var _hurt := {}
var _aggro := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for bus_name: String in BUSES:
		if AudioServer.get_bus_index(bus_name) < 0:
			AudioServer.add_bus()
			var index := AudioServer.bus_count - 1
			AudioServer.set_bus_name(index, bus_name)
			AudioServer.set_bus_send(index, "Master")
	for i in POOL:
		var player := AudioStreamPlayer3D.new()
		player.bus = "Effects"
		player.unit_size = 6.0
		player.max_distance = HEARING
		player.attenuation_filter_cutoff_hz = 12000.0
		add_child(player)
		_players.append(player)
	for i in 6:
		var player := AudioStreamPlayer.new()
		player.bus = "Interface"
		add_child(player)
		_flat.append(player)
	_ambience.bus = "Ambience"
	_ambience.volume_db = AMBIENCE_VOLUME
	add_child(_ambience)
	for player: AudioStreamPlayer in [_music, _boss_music]:
		player.bus = "Music"
		add_child(player)
	_music.finished.connect(func() -> void: _next_piece = _clock + randf_range(MUSIC_PAUSE.x, MUSIC_PAUSE.y))
	_load_volumes()
	get_tree().node_added.connect(_on_node_added)
	Game.zone_ready.connect(_on_zone_ready)
	Game.unit_damaged.connect(_on_unit_damaged)
	Game.error_message.connect(func(_text: String) -> void: ui("ui_error", -8.0))
	Game.loot_opened.connect(func(_enemy: Enemy) -> void: ui("loot", -6.0))


func _process(delta: float) -> void:
	_clock += delta
	if Game.zone == null or not is_instance_valid(Game.player):
		return
	_boss_check -= delta
	if _boss_check <= 0.0:
		_boss_check = 0.5
		_follow_bosses()
	if _boss == null and not _music.playing and _clock >= _next_piece:
		_play_piece()


## A bus's volume (0..1, as the Sound window shows it).
func get_volume(bus_name: String) -> float:
	return _volumes.get(bus_name, DEFAULT_VOLUMES.get(bus_name, 1.0))


func set_volume(bus_name: String, volume: float) -> void:
	_volumes[bus_name] = clampf(volume, 0.0, 1.0)
	_apply_volume(bus_name)
	var config := ConfigFile.new()
	config.load(SETTINGS)
	for each: String in _volumes:
		config.set_value("volume", each, _volumes[each])
	config.save(SETTINGS)


func _load_volumes() -> void:
	var config := ConfigFile.new()
	config.load(SETTINGS)
	for bus_name: String in DEFAULT_VOLUMES:
		_volumes[bus_name] = float(config.get_value("volume", bus_name, DEFAULT_VOLUMES[bus_name]))
		_apply_volume(bus_name)


func _apply_volume(bus_name: String) -> void:
	var index := AudioServer.get_bus_index(bus_name)
	if index >= 0:
		var volume := get_volume(bus_name)
		AudioServer.set_bus_volume_db(index, linear_to_db(maxf(volume, 0.0001)))
		AudioServer.set_bus_mute(index, volume <= 0.0)


## The next zone piece (shuffled, never the same twice in a row), faded in.
func _play_piece() -> void:
	if _playlist.is_empty():
		_playlist.assign(MUSIC.duplicate())
		_playlist.shuffle()
		if _playlist[0] == _last_piece and _playlist.size() > 1:
			_playlist.reverse()
	_last_piece = _playlist.pop_front()
	_music.stream = load(_last_piece)
	_fade_in(_music, MUSIC_VOLUME)
	_next_piece = INF
	played["music"] = played.get("music", 0) + 1


## A boss with music fighting the player brings its music in over the zone's; when the
## fight ends (it dies, gives up, or the player dies) it fades and the zone's comes back.
func _follow_bosses() -> void:
	var player := Game.player
	if _boss != null:
		if not is_instance_valid(_boss) or _boss.is_dead or _boss.state != Enemy.State.CHASE or player.is_dead:
			_boss = null
			_fade_out(_boss_music)
			_next_piece = _clock + AFTER_BOSS
		return
	if player.is_dead:
		return
	for node in get_tree().get_nodes_in_group("enemies"):
		var enemy := node as Enemy
		if enemy.data.music != "" and not enemy.is_dead and enemy.state == Enemy.State.CHASE and enemy.target == player:
			_boss = enemy
			if _music.playing:
				_fade_out(_music)
			_boss_music.stream = load(enemy.data.music)
			_fade_in(_boss_music, MUSIC_VOLUME + 2.0)
			played["boss_music"] = played.get("boss_music", 0) + 1
			return


func _fade_in(player: AudioStreamPlayer, volume_db: float) -> void:
	player.volume_db = -40.0
	player.play()
	create_tween().tween_property(player, "volume_db", volume_db, FADE)


func _fade_out(player: AudioStreamPlayer) -> void:
	var tween := create_tween()
	tween.tween_property(player, "volume_db", -40.0, FADE)
	tween.tween_callback(player.stop)


## One take of `set_name` at `at` (world), unless the camera is too far away to hear it.
func play(set_name: String, at: Vector3, volume_db := 0.0, pitch_spread := 0.08) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera != null and camera.global_position.distance_to(at) > HEARING:
		return
	var stream := _pick(set_name)
	if stream == null:
		return
	var player := _players[_next]
	_next = (_next + 1) % _players.size()
	player.stream = stream
	player.global_position = at
	player.volume_db = volume_db
	player.pitch_scale = 1.0 + randf_range(-pitch_spread, pitch_spread)
	player.play()
	played[set_name] = played.get(set_name, 0) + 1


## One take of `set_name` heard flat (the interface, the player's own coins and quests).
func ui(set_name: String, volume_db := 0.0) -> void:
	var stream := _pick(set_name)
	if stream == null:
		return
	var player := _flat[_next_flat]
	_next_flat = (_next_flat + 1) % _flat.size()
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = 1.0 + randf_range(-0.03, 0.03)
	player.play()
	played[set_name] = played.get(set_name, 0) + 1


## A footfall of `unit` at `at`: the ground's own sound (grass, dirt, rock, snow, sand),
## louder the faster it moves, plus the beast's own thud.
func step(unit: Unit, at: Vector3) -> void:
	if Game.zone == null:
		return
	var voice: Dictionary = VOICES.get(voice_of(unit), {})
	var speed := Vector2(unit.velocity.x, unit.velocity.z).length()
	var volume: float = voice.get("step_volume", -14.0) + clampf((speed - 1.5) * 1.2, 0.0, 6.0)
	play("step_" + Game.zone.terrain.surface_at(at.x, at.z), at, volume, 0.1)
	if voice.has("steps"):
		play(voice.steps, at, volume, 0.1)


## What kind of unit this is, for its sounds (a VOICES key).
func voice_of(unit: Unit) -> String:
	var enemy := unit as Enemy
	if enemy != null:
		if enemy.data.beast != "":
			return enemy.data.beast
		if enemy.data.character != "":
			return "scavenger"
	return "person"


func _pick(set_name: String) -> AudioStream:
	if not _sets.has(set_name):
		var takes: Array[AudioStream] = []
		var folder := ROOT + set_name
		if DirAccess.dir_exists_absolute(folder):
			for file in ResourceLoader.list_directory(folder):
				if file.get_extension() in ["ogg", "wav"]:
					takes.append(load(folder.path_join(file)))
		_sets[set_name] = takes
	var takes: Array = _sets[set_name]
	return takes.pick_random() if not takes.is_empty() else null


func _voice(unit: Unit, key: String, volume_db := 0.0) -> void:
	var voice: Dictionary = VOICES.get(voice_of(unit), {})
	if voice.has(key):
		play(voice[key], unit.global_position + Vector3.UP * unit.body_height * 0.6, volume_db)


func _on_zone_ready() -> void:
	_ambience.stream = load(AMBIENCE)
	_ambience.play()
	_boss = null
	_music.stop()
	_boss_music.stop()
	_next_piece = _clock + FIRST_PIECE
	for unit in get_tree().get_nodes_in_group("units"):
		_listen(unit as Unit)  # those made before this autoload was listening
	var player := Game.player
	player.money_looted.connect(func(_amount: int) -> void: ui("coins", -4.0))
	player.leveled_up.connect(func(_level: int) -> void: ui("ui_level", -4.0))
	player.gathered.connect(func(_item: ItemData, _count: int) -> void: ui("gather", -6.0))
	player.quest_log.quest_completed.connect(func(_quest: QuestData) -> void: ui("ui_quest", -6.0))
	player.achievements.earned.connect(func(_achievement: AchievementData) -> void: ui("ui_achievement", -6.0))


func _on_node_added(node: Node) -> void:
	if node is Unit:
		_listen(node as Unit)
	elif node is GameWindow:
		var window := node as GameWindow
		window.visibility_changed.connect(func() -> void: ui("ui_open" if window.visible else "ui_close", -10.0))
	elif node is Button:
		(node as Button).pressed.connect(func() -> void: ui("ui_click", -12.0))


func _listen(unit: Unit) -> void:
	var id := unit.get_instance_id()
	if unit.has_meta(&"heard"):
		return
	unit.set_meta(&"heard", true)
	unit.cast_started.connect(func(ability: AbilityData) -> void:
		_casts[id] = ability
		play("spell_cast", unit.global_position + Vector3.UP, -10.0))
	unit.cast_ended.connect(func(success: bool) -> void:
		var ability: AbilityData = _casts.get(id)
		_casts.erase(id)
		if success and ability != null:
			_released[id] = Game.time
			play(RELEASES.get(ability.id, "spell_cast"), unit.global_position + Vector3.UP, -4.0 if ability.id == "crystal_roar" else -6.0))
	unit.attacked.connect(func() -> void:
		# the swing that follows a finished cast is the spell going off, already heard
		if Game.time - float(_released.get(id, -1.0)) > 0.05:
			_voice(unit, "attack", -6.0))
	unit.died.connect(func(_killer: Unit) -> void: _voice(unit, "death", -3.0))
	if unit is Enemy:
		unit.target_changed.connect(func(new_target: Unit) -> void:
			if new_target != null and not unit.is_dead and Game.time - float(_aggro.get(id, -INF)) > AGGRO_PAUSE:
				_aggro[id] = Game.time
				_voice(unit, "aggro", -4.0))
	unit.tree_exiting.connect(func() -> void:
		for table: Dictionary in [_casts, _released, _hurt, _aggro]:
			table.erase(id))


func _on_unit_damaged(target: Unit, _source: Unit, _amount: int, crit: bool, color: Color) -> void:
	var at := target.global_position + Vector3.UP * target.body_height * 0.6
	if color.is_equal_approx(Color.WHITE):
		play("hit_crit" if crit else "hit", at, -3.0 if crit else -6.0)
	else:
		play("hit_crystal", at, -6.0)  # a spell landing
	var voice: Dictionary = VOICES.get(voice_of(target), {})
	if voice.get("crystal", false):
		play("hit_crystal", at, -12.0)
	var id := target.get_instance_id()
	if not target.is_dead and Game.time - float(_hurt.get(id, -INF)) > HURT_PAUSE and randf() < 0.5:
		_hurt[id] = Game.time
		_voice(target, "hurt", -6.0)
