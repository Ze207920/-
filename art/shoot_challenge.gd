# 开发期截图工具：验证挑战模式的三个关键画面 ——
# 选关界面、关卡内 HUD、通关结算。顺便断言「关卡名单限制敌人种类」生效。
#
# 用法：godot --path . art/shoot_challenge.tscn
#
# 注意：这个工具会真的写 user://records.cfg（通关会落一条记录），
# 所以要验证存档链路就必须真的写。跑之前外部脚本会把旧存档备份走，跑完还原。
extends Node

const TITLE_PATH: String = "res://art/preview/challenge_title.png"
const SELECT_PATH: String = "res://art/preview/challenge_select.png"
const PLAY_PATH: String = "res://art/preview/challenge_play.png"
const CLEAR_PATH: String = "res://art/preview/challenge_clear.png"
const PLAY_TIME: float = 9.0
const LEVEL_INDEX: int = 2

var _game: Game = null
var _t: float = 0.0
var _stage: int = 0


func _ready() -> void:
	RenderingServer.set_default_clear_color(Color(0.05, 0.06, 0.08))
	var scene: PackedScene = load("res://game.tscn")
	_game = scene.instantiate() as Game
	add_child(_game)
	await get_tree().process_frame
	await _shot(TITLE_PATH)

	_game._open_challenge_select()
	await get_tree().process_frame
	# 伪造前两关的通关记录：一张全是「未解锁」的截图看不出界面真正长什么样，
	# 只有同时出现「已通关 / 可挑战 / 未解锁」三种状态才值得看。
	_game.select_panel._records["ch1"] = {"cleared": true, "time": 61.2, "kills": 184}
	_game.select_panel._records["ch2"] = {"cleared": true, "time": 80.4, "kills": 268}
	_game.select_panel._selected = LEVEL_INDEX
	_game.select_panel.queue_redraw()
	await _shot(SELECT_PATH)

	_game._on_level_chosen(LEVEL_INDEX)
	# 关掉升级：等级面板会暂停并盖住画面，截出来什么都看不到。
	if is_instance_valid(_game.player):
		_game.player.xp_to_next = 999999


func _process(delta: float) -> void:
	if _game == null or not is_instance_valid(_game.player):
		return
	if _stage == 0:
		_t += delta
		if _t < PLAY_TIME:
			# 斜向奔跑：让走位动画与刷怪同时发生，画面里才有真实战斗的样子。
			_game.player.global_position += Vector2(0.86, 0.50) * 190.0 * delta
			return
		_stage = 1
		_report_enemies()
		await _shot(PLAY_PATH)
		# 直接把时钟推到终点，省掉真跑 90 秒。通关判定本身仍在 _physics_process 里。
		_game._elapsed = _game._level.duration - 0.02
		await get_tree().create_timer(0.35).timeout
		var cleared: bool = Records.challenge_cleared(_game._level.id)
		var unlocked_next: bool = _game.select_panel.is_unlocked(LEVEL_INDEX + 1)
		print("clear check: level=", _game._level.id,
				"  state_over=", _game._state == Game.State.OVER,
				"  record_cleared=", cleared,
				"  next_unlocked=", unlocked_next)
		await _shot(CLEAR_PATH)
		get_tree().quit()


## 统计场上敌人种类，确认关卡名单真的把别种怪挡在外面。
func _report_enemies() -> void:
	var counts: Dictionary = {}
	for enemy: Enemy in _game.enemies:
		if not is_instance_valid(enemy):
			continue
		var key: String = String(EnemyData.Kind.keys()[int(enemy.kind)])
		counts[key] = int(counts.get(key, 0)) + 1
	print("enemy mix after %.1fs on %s: %s  (fps=%.1f)" % [
		PLAY_TIME, _game._level.display_name, str(counts), Engine.get_frames_per_second()])


func _shot(path: String) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var err: int = img.save_png(path)
	print("shot saved: ", path, "  err=", err)
