# 敌人实机对照：先跑一小段真实战斗，再把四种邪物摆到玩家周围截一张，
# 用来确认它们在真实尺寸（而不是图鉴的 3 倍放大）下能不能一眼分清。
# 用法：godot --path . art/shoot_enemies.tscn
extends Node

const OUT_PATH: String = "res://art/preview/gameplay_enemies.png"

var _game: Game = null
var _t: float = 0.0
var _placed: bool = false
var _done: bool = false


func _ready() -> void:
	RenderingServer.set_default_clear_color(Color(0.05, 0.06, 0.08))
	var scene: PackedScene = load("res://game.tscn")
	_game = scene.instantiate() as Game
	add_child(_game)
	await get_tree().process_frame
	_game._enter_play()
	if is_instance_valid(_game.player):
		# 关掉升级面板（它会暂停并盖住画面），也顺手把接触伤害计时器拉长，
		# 免得截图瞬间被红闪染成一片暗红。
		_game.player.xp_to_next = 999999
		_game.player._contact_timer = 999.0


func _process(delta: float) -> void:
	if _done or _game == null or not is_instance_valid(_game.player):
		return
	_t += delta
	if _t < 3.0:
		return
	if not _placed:
		_placed = true
		_place_demo()
		return
	if _t < 3.6:
		return

	_done = true
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var err: int = img.save_png(OUT_PATH)
	print("enemy shot saved: ", OUT_PATH, "  err=", err,
			"  fps=", Engine.get_frames_per_second(),
			"  nodes=", Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	get_tree().quit()


## 把四种邪物按「小到大」的方位摆在镜头里。位置刻意错开，避免互相遮挡。
func _place_demo() -> void:
	var center: Vector2 = _game.player.global_position
	var layout: Array = [
		[EnemyData.presets()[3], Vector2(-120.0, 92.0)],   # 尸蟞
		[EnemyData.presets()[0], Vector2(118.0, 82.0)],    # 粽子
		[EnemyData.presets()[1], Vector2(-108.0, -104.0)], # 鸡冠蛇
		[EnemyData.presets()[2], Vector2(124.0, -86.0)],   # 海猴子
	]
	for item: Array in layout:
		var enemy := Enemy.new()
		enemy.apply_data(item[0] as EnemyData)
		_game.add_child(enemy)
		enemy.global_position = center + (item[1] as Vector2)
		enemy.setup(_game.player, 1.0, 1.0, 1.0)
		# 冻住：这一张是「静态对照图」，怪一走动就会叠到玩家身上看不清。
		enemy.set_physics_process(false)
