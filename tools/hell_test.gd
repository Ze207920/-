# 地狱模式逻辑冒烟：用无界面引擎直接推进时间表，验证八位墓主全部登场、
# 数值单调递增、通关条件在「全灭 + 时间到」时才成立。
# 以场景方式运行，Autoload（AudioManager）才会被正常注册。
extends Node

var failures: int = 0


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  [OK] ", label)
	else:
		failures += 1
		printerr("  [FAIL] ", label)


func _ready() -> void:
	# 不能在父节点 _ready 期间直接 add_child，Godot 会拒绝；延后一帧再建局。
	call_deferred("_run")


func _run() -> void:
	print("[step] start")
	Records.enabled = false
	var level: ChallengeData = ChallengeData.hell()
	_check(level != null, "地狱关卡数据存在")
	_check(is_equal_approx(level.duration, 180.0), "时长 180 秒")
	_check(ChallengeData.HELL_BOSS_TIMES.size() == 8, "八位墓主时间表")
	_check(is_equal_approx(ChallengeData.HELL_BOSS_TIMES[1], 30.0), "每 30 秒一位")

	var first: EnemyData = EnemyData.boss_for_hell(0)
	var last: EnemyData = EnemyData.boss_for_hell(7)
	_check(last.max_health > first.max_health, "末位墓主血量更高")
	_check(last.move_speed > first.move_speed, "末位墓主移速更高")
	_check(last.boss_skill_interval < first.boss_skill_interval, "末位墓主技能更快")
	_check(first.boss_skill_level == 3 and last.boss_skill_level == 3, "全部会用两招")
	print("  血量区间  %d -> %d" % [int(first.max_health), int(last.max_health)])
	print("  同屏上限  %d (终章 %d)" % [
		int(level.curve_at(180.0)[3]), int(ChallengeData.at(7).curve_at(180.0)[3])])

	Game.mode = Game.Mode.HELL
	Game.auto_start = true
	Game.open_select_on_load = false
	print("[step] loading scene")
	var game: Node = load("res://game.tscn").instantiate()
	print("[step] adding scene")
	get_tree().root.add_child(game)
	print("[step] scene ready")
	_check(game._level != null and game._level.id == "hell", "场景按地狱模式初始化")

	for t: float in [0.0, 15.0, 30.0, 75.0, 90.0, 125.0, 150.0, 179.0]:
		game._elapsed = t
		game._tick_boss()
	print("  墓主登场计数  %d / 8" % game._boss_spawn_index)
	_check(game._boss_spawn_index == 8, "八位墓主全部登场")
	_check(game._bosses.size() == 8, "八只同时在场")

	# 时间到但没打完：必须留在决战，不能通关。
	game._elapsed = 181.0
	game._state = Game.State.PLAYING
	game._physics_process(0.02)
	_check(game._state != Game.State.OVER, "未全灭时时间到不通关")
	_check(game._in_showdown, "未全灭时进入决战")

	# 全部打倒后再推进一帧：通关。
	for enemy: Enemy in game._bosses.duplicate():
		game._on_enemy_died(enemy)
	game._physics_process(0.02)
	_check(game._bosses_defeated == 8, "八位墓主全部计入击破")
	_check(game._state == Game.State.OVER, "全灭且时间到通关")

	if failures > 0:
		printerr("地狱模式测试失败：%d 项" % failures)
	else:
		print("地狱模式测试全部通过")
	get_tree().quit(1 if failures > 0 else 0)
