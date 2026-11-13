# 开发期截图工具：跑一段真实战斗并抓帧，用来确认玩家在实际画面里的辨识度。
# 用法：godot --path . art/shoot_gameplay.tscn
extends Node

const OUT_PATH: String = "res://art/preview/gameplay_player.png"
const RUN_TIME: float = 8.0

var _game: Game = null
var _t: float = 0.0
var _done: bool = false


func _ready() -> void:
	RenderingServer.set_default_clear_color(Color(0.05, 0.06, 0.08))
	var scene: PackedScene = load("res://game.tscn")
	_game = scene.instantiate() as Game
	add_child(_game)
	await get_tree().process_frame
	_game._enter_play()
	# 关掉升级：等级面板会暂停整个游戏并盖住画面，截出来看不到任何东西。
	if is_instance_valid(_game.player):
		_game.player.xp_to_next = 999999


func _process(delta: float) -> void:
	if _done or _game == null or not is_instance_valid(_game.player):
		return
	_t += delta
	if _t < RUN_TIME:
		# 一直斜着跑：既让走路动画动起来，也逼刷怪器在四周铺开敌人。
		_game.player.global_position += Vector2(0.88, 0.48) * 190.0 * delta
		return

	_done = true
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var err: int = img.save_png(OUT_PATH)
	print("gameplay shot saved: ", OUT_PATH, "  err=", err,
			"  fps=", Engine.get_frames_per_second(),
			"  objects=", Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	get_tree().quit()
