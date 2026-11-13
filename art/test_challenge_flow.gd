# 挑战模式流程测试：用真实的输入事件走一遍「打开选关 → 进关 → 通关 → 下一关 →
# 暂停/恢复 → 阵亡 → 返回选关」，验证跨场景重载时 mode / challenge_index 的携带，
# 以及每个界面的状态切换。自动截图工具只能看静态画面，流程是否接通必须这样测。
#
# 用法：godot --path . art/test_challenge_flow.tscn
#
# 关键做法：不把 game.tscn 当子节点挂进测试场景，而是把它设成 current_scene ——
# 只有这样 Game 里的 reload_current_scene 才会重载游戏本身，而测试节点作为
# root 的另一个子节点存活下来，才能继续断言重载之后的状态。
extends Node

var _game: Game = null
var _failures: int = 0
var _checks: int = 0


func _ready() -> void:
	var scene: PackedScene = load("res://game.tscn")
	_game = scene.instantiate() as Game
	# _ready 阶段 root 还在装配子节点，直接 add_child 会失败，必须延后一帧。
	# 延后之后 Game 才真正挂在 root 下，才能被设为 current_scene。
	get_tree().root.add_child.call_deferred(_game)
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().current_scene = _game
	await get_tree().process_frame
	await _run()
	print("---- flow test: %d checks, %d failures ----" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _run() -> void:
	await _wait(0.3)
	_check(_game._state == Game.State.TITLE, "启动后停在标题页")

	# 标题页按 C 打开挑战关卡选择
	await _key(KEY_C)
	await _wait(0.3)
	_check(_game.select_panel != null and _game.select_panel.visible, "C 打开选关界面")
	_check(_game.select_panel._selected == 0, "默认选中第一关（未通关，索引 %d）"
			% _game.select_panel._selected)

	# 未解锁的关卡不该放行
	_game.select_panel._selected = 3
	_game.select_panel._confirm()
	await _wait(0.15)
	_check(_game._state == Game.State.TITLE, "点未解锁关卡不会开局")
	_check(_game.select_panel.visible, "被拒绝后仍停在选关界面")

	# 进第一关
	_game.select_panel._selected = 0
	await _key(KEY_ENTER)
	await _wait(0.6)
	_check(_game._state == Game.State.PLAYING, "Enter 进入第一关")
	_check(_game._level != null and _game._level.id == "ch1",
			"关卡数据已载入：%s" % (_game._level.id if _game._level != null else "null"))
	_check(_game.hud.challenge_name == "七星鲁王宫",
			"HUD 显示关卡名：%s" % _game.hud.challenge_name)
	_check(_game.hud.challenge_remaining > 50.0 and _game.hud.challenge_remaining <= 60.0,
			"HUD 剩余时间约 60 秒：%.1f" % _game.hud.challenge_remaining)
	_check(_game.select_panel.visible == false, "开局后选关界面已关闭")

	# 通关
	_game._elapsed = _game._level.duration - 0.02
	await _wait(0.4)
	_check(_game._state == Game.State.OVER, "到达关底时间即通关")
	_check(Records.challenge_cleared("ch1"), "通关记录已写入存档")
	_check(_game.overlay._primary_action == "next", "通关结算的首个按钮是「下一关」")
	_check(_game.overlay._secondary_action == "select", "通关结算的 ESC 动作是「返回选关」")

	# 空格 = 下一关（走 reload_current_scene）
	var before: int = Game.challenge_index
	await _key(KEY_SPACE)
	await _wait(1.4)
	_game = get_tree().current_scene as Game
	_check(_game != null and _game._level != null and _game._level.id == "ch2",
			"空格切到下一关（索引 %d → %d，关卡 %s）" % [
				before, Game.challenge_index,
				_game._level.id if _game != null and _game._level != null else "null"])
	_check(_game._state == Game.State.PLAYING, "下一关直接开打，不回到标题")
	_check(_game.hud.challenge_name == "积尸地",
			"HUD 换成第二关名称：%s" % _game.hud.challenge_name)

	# 暂停 / 恢复
	await _key(KEY_ESCAPE)
	await _wait(0.25)
	_check(_game._state == Game.State.PAUSED, "ESC 暂停")
	await _key(KEY_ESCAPE)
	await _wait(0.25)
	_check(_game._state == Game.State.PLAYING, "再按 ESC 恢复")

	# 阵亡 → 结算 → ESC 返回选关
	_game.player._invuln_timer = 0.0
	_game.player.take_contact_damage(9999.0)
	await _wait(0.35)
	_check(_game._state == Game.State.OVER, "血量清空后进入结算")
	_check(_game.overlay._primary_action == "restart", "阵亡结算的首个按钮是「再来一局」")
	_check(_game.overlay._secondary_action == "select", "阵亡结算的 ESC 动作是「返回选关」")

	await _key(KEY_ESCAPE)
	await _wait(1.4)
	_game = get_tree().current_scene as Game
	_check(_game != null and _game.select_panel.visible, "ESC 返回后直接停在选关界面")
	_check(_game._state == Game.State.TITLE, "返回选关时状态机回到 TITLE")
	_check(Game.challenge_index == 0, "返回选关会重置关卡索引")


# ---------------------------------------------------------------- 工具

func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
	print(("[PASS] " if ok else "[FAIL] ") + message)


func _wait(seconds: float) -> void:
	# create_timer 默认 process_always，暂停状态下也能正常计时。
	await get_tree().create_timer(seconds).timeout


func _key(code: int) -> void:
	var down := InputEventKey.new()
	down.keycode = code
	down.physical_keycode = code
	down.pressed = true
	get_viewport().push_input(down)
	await get_tree().process_frame
	var up := InputEventKey.new()
	up.keycode = code
	up.physical_keycode = code
	up.pressed = false
	get_viewport().push_input(up)
	await get_tree().process_frame
