extends Node
## The game's sound: music only (sound effects are left out by choice). Music plays like
## WoW's: a piece, then a minute or two of quiet, then another (MUSIC, shuffled); a boss
## with its own music (EnemyData.music) brings it in while it fights the player. The Music
## bus sits under Master; their volumes are kept in SETTINGS (the game menu's Sound window).

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
const DEFAULT_VOLUMES := {"Master": 1.0, "Music": 0.7}

## How many times each piece kind ("music", "boss_music") has started (the smoke test listens).
var played := {}
var _music := AudioStreamPlayer.new()
var _boss_music := AudioStreamPlayer.new()
var _playlist: Array[String] = []
var _last_piece := ""
var _clock := 0.0
var _next_piece := INF
var _boss: Enemy
var _boss_check := 0.0
var _volumes := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if AudioServer.get_bus_index("Music") < 0:
		AudioServer.add_bus()
		var index := AudioServer.bus_count - 1
		AudioServer.set_bus_name(index, "Music")
		AudioServer.set_bus_send(index, "Master")
	for player: AudioStreamPlayer in [_music, _boss_music]:
		player.bus = "Music"
		add_child(player)
	_music.finished.connect(func() -> void: _next_piece = _clock + randf_range(MUSIC_PAUSE.x, MUSIC_PAUSE.y))
	_load_volumes()
	Game.zone_ready.connect(_on_zone_ready)


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


func _on_zone_ready() -> void:
	_boss = null
	_music.stop()
	_boss_music.stop()
	_next_piece = _clock + FIRST_PIECE
