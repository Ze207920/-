# 全局音频服务（Autoload）。
#
# 为什么必须是 Autoload 而不是场景子节点：重开一局会重载整个场景，
# 挂在场景里的播放器会被销毁，音乐每次都要从头开始，还会有一声断点。
# 音频是典型的「跨场景服务」，适合放在 Autoload。
#
# 三条设计约束：
# 1) 限流。后期一秒十几发子弹、二十次击杀，不限流会叠成一片白噪音，
#    同时十几个 AudioStreamPlayer 并发也有开销。
# 2) 池化。只建固定数量的播放器反复复用，绝不为每次播放 new 一个节点 ——
#    音效是高频事件，节点创建/销毁比播放本身贵得多。
# 3) 音高抖动。同一段采样连播十几次会听出「电子表报时」的机械感，
#    每次随机浮动几个百分点就自然了。
extends Node

const BUS_SFX: String = "SFX"
const BUS_BGM: String = "BGM"
## 并发播放器数量。限流后单种音效最短 30ms 一次，14 个足够覆盖所有种类叠加。
const POOL_SIZE: int = 14

const STREAMS: Dictionary = {
	"shoot": preload("res://audio/sfx_shoot.wav"),
	"hit": preload("res://audio/sfx_hit.wav"),
	"kill": preload("res://audio/sfx_kill.wav"),
	"hurt": preload("res://audio/sfx_hurt.wav"),
	"pickup": preload("res://audio/sfx_pickup.wav"),
	"levelup": preload("res://audio/sfx_levelup.wav"),
	"gameover": preload("res://audio/sfx_gameover.wav"),
	"start": preload("res://audio/sfx_start.wav"),
	"click": preload("res://audio/sfx_click.wav"),
}

const BGM: AudioStream = preload("res://audio/bgm_loop.wav")

## 每种音效的最小触发间隔（秒）。数值来自「听感上不糊」而非数学推导：
## 射击 70ms 约等于手枪满级射速的间隔，再密就分不出单发；
## 击杀 55ms 让连杀听成「一阵」而不是「一片」。
const MIN_GAP: Dictionary = {
	"shoot": 0.070,
	"hit": 0.045,
	"kill": 0.055,
	"pickup": 0.040,
	"hurt": 0.130,
	"levelup": 0.200,
	"gameover": 0.500,
	"start": 0.200,
	"click": 0.030,
}

## 相对增益（分贝）。文件已经按各自的目标峰值归一化过，这里只调整彼此的
## 主次关系：受伤最突出（必须听见），射击最轻（最频繁），点击最弱。
const GAIN: Dictionary = {
	"shoot": -3.0,
	"hit": -1.0,
	"kill": -2.0,
	"pickup": -3.0,
	"hurt": 0.0,
	"levelup": 0.0,
	"gameover": 1.0,
	"start": 0.0,
	"click": -6.0,
}

## 随机音高浮动幅度（±比例）。0 表示不浮动。
const JITTER: Dictionary = {
	"shoot": 0.10,
	"hit": 0.09,
	"kill": 0.12,
	"pickup": 0.06,
}

var muted: bool = false:
	set(value):
		muted = value
		AudioServer.set_bus_mute(0, muted)

var _pool: Array[AudioStreamPlayer] = []
var _next: int = 0
var _bgm: AudioStreamPlayer = null
var _last_at: Dictionary = {}


func _ready() -> void:
	# 暂停是整棵树级的，音频服务必须无视它：否则暂停后按 M 没反应，
	# 结算界面播放的死亡音效也会被吞掉。
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_bus(BUS_SFX, 0.0)
	_ensure_bus(BUS_BGM, -2.0)
	_build_pool()
	_build_bgm()


func _ensure_bus(bus_name: String, volume_db: float) -> int:
	var index: int = AudioServer.get_bus_index(bus_name)
	if index == -1:
		AudioServer.add_bus()
		index = AudioServer.bus_count - 1
		AudioServer.set_bus_name(index, bus_name)
	# 必须在新建后显式指回 Master：新增总线的 send 默认是空字符串（直接进声卡），
	# 那样静音 Master 时音乐照响，音量控制也会失效。
	AudioServer.set_bus_send(index, "Master")
	AudioServer.set_bus_volume_db(index, volume_db)
	return index


func _build_pool() -> void:
	for i in POOL_SIZE:
		var player := AudioStreamPlayer.new()
		player.bus = BUS_SFX
		player.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(player)
		_pool.append(player)


func _build_bgm() -> void:
	_bgm = AudioStreamPlayer.new()
	_bgm.bus = BUS_BGM
	_bgm.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_bgm)

	var stream := BGM as AudioStreamWAV
	if stream == null:
		push_warning("AudioManager: bgm_loop.wav 未按 AudioStreamWAV 导入，无法设置循环")
		return
	# 循环点在运行时设置，不依赖 .import 里的 edit/loop_mode：重新导入会覆盖
	# 导入参数，而运行时设置永远以代码为准。
	# 32 秒的素材由「整数周期」的正弦构成，循环点相位连续，不需要交叉淡化。
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	# loop_end 必须以「样本数」为单位。这里不能无脑按 data.size()/2 算：
	# Godot 4.4 起 WAV 默认按 QOA 有损压缩导入（compress/mode=2），
	# 那种情况下 data 是压缩后的字节流，换算出来的长度只有真实值的五分之一，
	# 循环会在一秒内跳回开头。工程里的 .import 已强制 compress/mode=0（PCM），
	# 但代码仍然按 format 判断一次，避免以后有人把导入设置改回去又踩同一个坑。
	match stream.format:
		AudioStreamWAV.FORMAT_16_BITS:
			stream.loop_end = int(stream.data.size() / 2.0)
		AudioStreamWAV.FORMAT_8_BITS:
			stream.loop_end = stream.data.size()
		_:
			# IMA-ADPCM / QOA 无法从字节数反推样本数，保留 .import 的 -1（到结尾），
			# 让引擎自己决定循环终点，而不是给一个错得离谱的数字。
			push_warning("AudioManager: BGM 不是 PCM 格式，循环终点交由导入设置决定")
	_bgm.stream = stream


## 播放一次音效。id 必须存在于 STREAMS，未知 id 静默忽略（不做任何兜底音）。
func play(id: String, pitch_jitter: float = -1.0) -> void:
	if muted:
		return
	var stream: AudioStream = STREAMS.get(id, null)
	if stream == null:
		push_warning("AudioManager: 未知音效「%s」" % id)
		return

	var now: int = Time.get_ticks_msec()
	var gap_ms: int = int(float(MIN_GAP.get(id, 0.0)) * 1000.0)
	if now - int(_last_at.get(id, -1000000)) < gap_ms:
		return
	_last_at[id] = now

	var player: AudioStreamPlayer = _take_player()
	if player == null:
		return
	var jitter: float = pitch_jitter if pitch_jitter >= 0.0 else float(JITTER.get(id, 0.0))
	player.stream = stream
	player.bus = BUS_SFX
	player.volume_db = float(GAIN.get(id, 0.0))
	player.pitch_scale = 1.0 + randf_range(-jitter, jitter) if jitter > 0.0 else 1.0
	player.play()


## 优先用空闲播放器；全满时按轮转抢占最早分配的那个。
## 抢占会截断一个正在响的音效，但这只在极端密集时发生，比丢弃新音效更自然。
func _take_player() -> AudioStreamPlayer:
	if _pool.is_empty():
		return null
	for i in POOL_SIZE:
		var index: int = (_next + i) % POOL_SIZE
		if not _pool[index].playing:
			_next = (index + 1) % POOL_SIZE
			return _pool[index]
	var taken: AudioStreamPlayer = _pool[_next]
	_next = (_next + 1) % POOL_SIZE
	return taken


## 退出时主动断开流引用。
## AudioStreamPlayer 被销毁时，音频服务器仍可能在混音列表里持有它的 playback。
## 真实声卡驱动下播放线程会在退出前回收干净（实测零警告）；但 headless 的
## Dummy 驱动没有混音线程，进程结束时 playbacks 还挂在列表上，会打印
## 「AudioStreamPlaybackWAV leaked」。这条清理把能断的引用都断掉，
## 剩下的属于测试环境特有的时序问题，不是游戏本身的缺陷。
func _exit_tree() -> void:
	for player: AudioStreamPlayer in _pool:
		if is_instance_valid(player):
			player.stop()
			player.stream = null
	if _bgm != null and is_instance_valid(_bgm):
		_bgm.stop()
		_bgm.stream = null


func play_bgm() -> void:
	# 不要因为 muted 就跳过播放。静音是 Master 总线级的，流应该照常走 ——
	# 否则「标题页按 M 静音 → 开始游戏 → 再按 M 取消静音」之后音乐会永远不响，
	# 因为那时 play_bgm 已经被静音状态挡掉了，没有第二次调用机会。
	if _bgm == null or _bgm.playing:
		return
	_bgm.play()


func stop_bgm() -> void:
	if _bgm != null and _bgm.playing:
		_bgm.stop()


func is_bgm_playing() -> bool:
	return _bgm != null and _bgm.playing


## M 键静音。放在 Autoload 里是为了在标题、暂停、结算界面都能按 ——
## 这几个界面分别处于暂停状态，场景内的输入节点不一定收得到事件。
func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == KEY_M:
		muted = not muted
		get_viewport().set_input_as_handled()
