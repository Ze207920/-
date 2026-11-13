# 性能压测：一次性塞 200 只敌人，看新造型（每只十几个图元）会不会拖垮帧率。
# 用法：godot --path . art/stress_enemies.tscn
# 这是最坏情况对照 —— 正常游玩同屏上限 215，但不会一开始就全挤在镜头里。
extends Node

const COUNT: int = 200
const WARMUP: float = 2.0
const MEASURE: float = 6.0

var _game: Game = null
var _t: float = 0.0
var _spawned: bool = false
var _done: bool = false
var _samples: Array[float] = []


func _ready() -> void:
	var scene: PackedScene = load("res://game.tscn")
	_game = scene.instantiate() as Game
	add_child(_game)
	await get_tree().process_frame
	_game._enter_play()
	if is_instance_valid(_game.player):
		# 压测只想看渲染开销，所以把玩家做成打不死的靶子。
		_game.player.xp_to_next = 999999
		_game.player.max_health = 999999.0
		_game.player.health = 999999.0
		_game.player._contact_timer = 1e9


func _process(delta: float) -> void:
	if _done or _game == null or not is_instance_valid(_game.player):
		return
	_t += delta
	if _t < 0.8:
		return
	if not _spawned:
		_spawned = true
		_spawn_wave()
		return
	if _t > WARMUP:
		_samples.append(Engine.get_frames_per_second())
	if _t > WARMUP + MEASURE:
		_done = true
		var total: float = 0.0
		for s: float in _samples:
			total += s
		var avg: float = total / maxf(1.0, float(_samples.size()))
		print("stress: enemies=", COUNT,
				"  avg_fps=", snappedf(avg, 0.1),
				"  min_fps=", snappedf(_samples.min(), 0.1),
				"  nodes=", Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
		get_tree().quit()


## 不登记进 game.enemies：那样会被「超距回收」搬回屏幕外圈，
## 压测就测不到「两百只全挤在镜头里」这个最坏情况了。
func _spawn_wave() -> void:
	var presets: Array[EnemyData] = EnemyData.presets()
	var center: Vector2 = _game.player.global_position
	for i in COUNT:
		var enemy := Enemy.new()
		enemy.apply_data(presets[i % presets.size()])
		_game.add_child(enemy)
		var angle: float = TAU * float(i) / float(COUNT)
		var distance: float = 220.0 + randf() * 620.0
		enemy.global_position = center + Vector2(cos(angle), sin(angle)) * distance
		enemy.setup(_game.player, 1.0, 1.0, 1.0)
