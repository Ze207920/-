# 虚拟摇杆：移动端触屏控制玩家移动。
#
# 设计要点：
# 1) 浮动式 —— 在左半屏任意位置按下即生成基准圆，手指拖动产生移动向量。
#    比固定摇杆更跟手，也不要求拇指必须落在某个固定点上。
# 2) 只响应 InputEventScreenTouch / ScreenDrag（真·触摸），桌面鼠标不会触发，
#    因此桌面端键盘玩法完全不受影响；且只在「设备支持触摸」时启用。
# 3) 只在游戏进行中（未暂停）生效。升级面板、暂停、结算界面期间整棵树是暂停的，
#    本节点靠 process_mode=ALWAYS 仍能自我隐藏并忽略触摸，绝不会吞掉那些界面
#    上按钮的点击（按钮走的是被模拟出来的鼠标事件，落点也不在左半屏）。
# 4) 一旦接管一次触摸，就 set_input_as_handled()，避免同一次触摸再被别处当成点击。
class_name TouchJoystick
extends Control

const BASE_R: float = 58.0
const THUMB_R: float = 26.0
## 拇指离基准圆圆心的最大距离。大于此值就把向量限幅到 1.0，避免「拖到屏幕外」时
## 速度方向正确但幅度被错误缩放。
const MAX_REACH: float = 64.0
## 未激活时左下角的提示环半径。
const HINT_R: float = 46.0
## 左半屏激活区：屏幕宽度的这个比例以内按下才起摇杆，右侧留给暂停按钮等。
const LEFT_RATIO: float = 0.55

var _enabled: bool = false
var _active: bool = false
var _touch_index: int = -1
var _base: Vector2 = Vector2.ZERO
var _thumb: Vector2 = Vector2.ZERO
var _vector: Vector2 = Vector2.ZERO

var _pulse: float = 0.0


func _ready() -> void:
	# 暂停时本节点仍需自我隐藏，所以无视暂停。
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# 不拦截 GUI 点击：鼠标过滤设为忽略，触摸事件交给下面自己的 _input 处理。
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


## 由 Game 在启动时调用一次：触摸设备才启用，桌面端保持隐藏、只用键盘。
func set_enabled(on: bool) -> void:
	_enabled = on
	if not on:
		_reset()


func is_active() -> bool:
	return _active


func is_enabled() -> bool:
	return _enabled


## 归一化后的移动向量（长度 0~1）。玩家直接拿它加到键盘方向上。
func get_vector() -> Vector2:
	return _vector


func _reset() -> void:
	_active = false
	_touch_index = -1
	_vector = Vector2.ZERO
	queue_redraw()


func _input(event: InputEvent) -> void:
	if get_tree() == null or get_tree().paused:
		return
	var touch := event as InputEventScreenTouch
	# 懒启用：设备特性没报告触屏（桌面模拟器、触屏笔记本）时，第一次真实触摸
	# 才临时开启。手机在启动时已由 set_enabled(true) 开好，这一分支不会命中。
	if not _enabled and touch != null and touch.pressed:
		_enabled = true
	if not _enabled:
		return

	if touch != null and touch.pressed and _touch_index < 0:
		if touch.position.x <= get_viewport_rect().size.x * LEFT_RATIO:
			_active = true
			_touch_index = touch.index
			_base = touch.position
			_thumb = _base
			_vector = Vector2.ZERO
			get_viewport().set_input_as_handled()
			queue_redraw()
		return

	var drag := event as InputEventScreenDrag
	if drag != null and drag.index == _touch_index:
		var offset: Vector2 = (drag.position - _base).limit_length(MAX_REACH)
		_thumb = _base + offset
		_vector = offset / MAX_REACH
		get_viewport().set_input_as_handled()
		queue_redraw()
		return

	if touch != null and not touch.pressed and touch.index == _touch_index:
		_reset()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	var want_visible: bool = _enabled and is_instance_valid(get_tree()) and not get_tree().paused
	if want_visible != visible:
		visible = want_visible
		if not want_visible:
			_reset()
	if visible:
		_pulse += delta
		queue_redraw()


func _draw() -> void:
	if not visible:
		return
	if _active:
		_draw_base(_base, BASE_R, 0.18)
		_draw_thumb(_thumb, THUMB_R)
	else:
		# 未激活时在左下角画一个呼吸的提示环，告诉玩家「这里可以拖动移动」。
		var hint_pos := Vector2(HINT_R + 30.0, get_viewport_rect().size.y - HINT_R - 30.0)
		var alpha: float = 0.10 + 0.06 * sin(_pulse * 3.0)
		_draw_base(hint_pos, HINT_R, alpha)


func _draw_base(center: Vector2, radius: float, alpha: float) -> void:
	draw_circle(center, radius, Color(0.16, 0.22, 0.30, alpha))
	draw_arc(center, radius, 0.0, TAU, 40, Color(0.36, 0.80, 1.00, alpha + 0.14), 2.0, true)


func _draw_thumb(center: Vector2, radius: float) -> void:
	draw_circle(center, radius, Color(0.36, 0.80, 1.00, 0.30))
	draw_arc(center, radius, 0.0, TAU, 32, Color(0.60, 0.92, 1.0, 0.90), 2.5, true)
