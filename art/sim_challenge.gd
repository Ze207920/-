# 挑战模式平衡探针：用一个「会走位、会自动选强化」的机器人把指定关卡跑一遍，
# 输出通关与否、存活时长、击杀与残血。关卡数值是否成立不能靠读表判断 ——
# 要真跑，才能知道这一关是「随便就过」还是「根本过不去」。
#
# 机器人策略：向「周围敌人的反方向」逃，并叠一点切线分量。这比绕圈更接近真人，
# 也比站桩更能反映走位型玩家的实际表现。
#
# 用法：godot --headless --path . --fixed-fps 60 art/sim_challenge.tscn
#       --fixed-fps 让引擎按固定步长全速推进，90 秒的一关几秒就能跑完。
extends Node

const LEVELS: Array[int] = [0]
const MAX_TIME: float = 200.0
## 逃跑时考虑的敌人距离。太小会贴着怪绕，太大等于永远在逃同样的方向。
const AWARE: float = 300.0

var _game: Game = null
var _results: Array[String] = []


func _ready() -> void:
	# 升级面板会暂停整棵树，本节点必须 ALWAYS 才能继续帮机器人做选择。
	process_mode = Node.PROCESS_MODE_ALWAYS
	seed(20261107)
	for index: int in LEVELS:
		await _run_level(index)
	print("=== CHALLENGE SIM ===")
	for line: String in _results:
		print(line)
	get_tree().quit()


func _run_level(index: int) -> void:
	# index < 0 用来跑生存模式做对照：同一套机器人策略下，如果生存模式也活不过
	# 60 秒，那说明是机器人太笨，而不是关卡数值有问题。
	Game.mode = Game.Mode.ENDLESS if index < 0 else Game.Mode.CHALLENGE
	Game.challenge_index = maxi(0, index)
	Game.auto_start = true
	var scene: PackedScene = load("res://game.tscn")
	_game = scene.instantiate() as Game
	get_tree().root.add_child.call_deferred(_game)
	await get_tree().process_frame
	await get_tree().process_frame

	var level: ChallengeData = _game._level
	var limit: float = level.duration if level != null else 120.0
	var start_time: int = Time.get_ticks_msec()
	while _game._state == Game.State.PLAYING and _game._elapsed < MAX_TIME:
		await get_tree().process_frame
	var real_ms: int = Time.get_ticks_msec() - start_time

	var cleared: bool = level != null and _game._elapsed >= level.duration - 0.01
	_results.append("%-5s %-12s  %s  存活 %5.1f/%3d 秒  等级 %2d  击杀 %3d  残血 %3d  (实耗 %.1fs)" % [
		String(level.id) if level != null else "无尽",
		level.display_name if level != null else "生存模式",
		"通关" if cleared else ("阵亡" if level != null else "    "),
		_game._elapsed, int(limit),
		_game.player.level, _game.kills, int(_game.player.health),
		float(real_ms) / 1000.0])
	_game.queue_free()
	Game.auto_start = false
	await get_tree().process_frame


func _process(delta: float) -> void:
	if _game == null or not is_instance_valid(_game):
		return
	# 升级面板弹出时游戏是暂停的，这里替机器人选第一个选项（列表本身是随机的）。
	if _game.level_panel != null and _game.level_panel.is_open():
		if not _game.level_panel._ids.is_empty():
			_game._on_upgrade_chosen(_game.level_panel._ids[0])
		return
	if _game._state != Game.State.PLAYING or not is_instance_valid(_game.player):
		return

	var player: Player = _game.player
	var flee := Vector2.ZERO
	for enemy: Enemy in _game.enemies:
		if not is_instance_valid(enemy):
			continue
		var offset: Vector2 = player.global_position - enemy.global_position
		var distance: float = offset.length()
		if distance <= 0.01 or distance > AWARE:
			continue
		flee += offset / distance * (1.0 - distance / AWARE)
	if flee.length_squared() < 0.0001:
		flee = Vector2.RIGHT
	# 离原点太远时往回拉一把。不加这一项，机器人会一直朝一个方向逃，
	# 而刷怪有 55% 概率落在玩家前进方向的屏幕外 —— 等于每次逃跑都是朝刷新点撞。
	# 真人被逼到边上也会绕回来，这一项就是在模拟那个行为。
	var pos: Vector2 = player.global_position
	if pos.length() > 520.0:
		flee += -pos.normalized() * 0.55 * ((pos.length() - 520.0) / 520.0)
	var direction: Vector2 = flee.normalized()
	# 切线分量：只沿逃离方向直线后退，会被两侧的怪越夹越死。
	direction = (direction + direction.orthogonal() * 0.5).normalized()
	player.global_position += direction * player.move_speed * delta
