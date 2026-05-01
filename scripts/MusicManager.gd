extends Node
# Persistent BGM manager — registered as autoload so it lives across all
# scene changes. Plays the global theme on launch, exposes fade_in/fade_out
# helpers, and auto-resets volume on scene transitions UNLESS the new scene
# is the boss room (which holds itself silent until the boss actually
# spawns and calls fade_in()).

const BGM_PATH := "res://assets/music/bgm.mp3"
const DEFAULT_VOLUME_DB := -10.0
const SILENT_DB := -60.0
const BOSS_ROOM_PATH := "res://scenes/room_4.tscn"

@export var enter_room_fade_duration: float = 2.0   # how long to fade out when entering boss room
@export var restore_fade_duration: float = 1.2      # how long to fade back in elsewhere
@export var boss_spawn_fade_duration: float = 1.5   # how long to fade back in when boss spawns

var _player: AudioStreamPlayer = null
var _fade_tween: Tween = null
var _last_scene_path: String = ""


func _ready() -> void:
	# Survive scene reloads + tween while paused.
	process_mode = Node.PROCESS_MODE_ALWAYS

	var stream := load(BGM_PATH)
	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
	_player = AudioStreamPlayer.new()
	_player.stream = stream
	_player.volume_db = DEFAULT_VOLUME_DB
	_player.bus = "Master"
	_player.autoplay = true
	add_child(_player)

	set_process(true)


func _process(_delta: float) -> void:
	# Cheap scene-change detection — react when the loaded scene's file path
	# differs from the previous frame's. Avoids needing every room to call
	# back into MusicManager manually.
	var scene := get_tree().current_scene
	if scene == null:
		return
	var path: String = scene.scene_file_path
	if path == _last_scene_path:
		return
	_last_scene_path = path
	_on_scene_entered(path)


func _on_scene_entered(path: String) -> void:
	if path == BOSS_ROOM_PATH:
		fade_out(enter_room_fade_duration)
	else:
		# Any non-boss scene: restore default volume so player who died in
		# room_4 (BGM faded down) doesn't return to a silent menu.
		if _player.volume_db < DEFAULT_VOLUME_DB - 0.5:
			fade_in(restore_fade_duration)


# ── Public API ───────────────────────────────────────────────────────────────

func fade_out(duration: float = 1.5) -> void:
	_kill_tween()
	_fade_tween = create_tween()
	_fade_tween.tween_property(_player, "volume_db", SILENT_DB, duration)


func fade_in(duration: float = 1.5, target_db: float = DEFAULT_VOLUME_DB) -> void:
	_kill_tween()
	if not _player.playing:
		_player.play()
	_fade_tween = create_tween()
	_fade_tween.tween_property(_player, "volume_db", target_db, duration)


func boss_spawn_fade_in() -> void:
	# Convenience wrapper for the boss to call. Slightly different default
	# duration so it can be tuned independently of generic fade_in.
	fade_in(boss_spawn_fade_duration)


# ── Internals ────────────────────────────────────────────────────────────────

func _kill_tween() -> void:
	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()
