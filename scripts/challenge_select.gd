# 挑战模式选关界面：一屏列出全部关卡，按难度由低到高排列。
#
# 整层用 _draw 自绘而不是拼 Button + Container：
# 1) 每张卡要同时画徽章、双行标题、星级、达标状态和右侧目标，用 Button 得
#    自己接管子节点布局，反而更绕；
# 2) 键盘（WASD / 方向键）与鼠标要共用同一套「当前选中项」，自绘时选中态就是
#    一个整数，比让焦点在十几个 Button 之间跳转可控得多。
#
# 输入走 _input 而不是 _gui_input：_gui_input 依赖 Control 的 size 正确，
# 而这一层是直接挂在 CanvasLayer 下的，size 由视口决定、在拉伸模式下不一定
# 立刻可靠。_input 拿到的事件坐标已经在视口坐标系里，正好就是绘制坐标系。
class_name ChallengeSelect
extends Control

signal level_chosen(index: int)
signal closed

const CARD: Vector2 = Vector2(296.0, 92.0)
const GAP: float = 14.0
const COLUMNS: int = 2
## 顶部标题区高度。
const HEADER: float = 62.0
const DETAIL_HEIGHT: float = 108.0

var _selected: int = 0
var _hover: int = -1
## 点击未解锁关卡后的红框闪烁计时。
var _deny: float = 0.0
## 存档缓存：id -> {cleared, time, kills}。
## 每张卡每帧都要读通关状态，若直接查存档就是每秒几百次小文件读；
## 打开界面时读一次、整个界面生命周期内复用。
var _records: Dictionary = {}

var _style_normal: StyleBoxFlat = null
var _style_active: StyleBoxFlat = null
var _style_locked: StyleBoxFlat = null
var _style_locked_focus: StyleBoxFlat = null
var _style_detail: StyleBoxFlat = null


func _ready() -> void:
	# 选关期间整棵树是暂停的，这一层必须继续跑，否则既不重绘也不收键。
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = UiStyle.theme()
	_build_styles()
	visible = false


func _build_styles() -> void:
	_style_normal = UiStyle.button_style(Color(0.09, 0.11, 0.15, 0.96), UiStyle.BORDER)
	_style_normal.set_corner_radius_all(10)
	_style_active = UiStyle.button_style(Color(0.14, 0.20, 0.27, 0.98), UiStyle.ACCENT, 2)
	_style_active.set_corner_radius_all(10)
	_style_locked = UiStyle.button_style(Color(0.06, 0.07, 0.10, 0.92), Color(0.17, 0.20, 0.26))
	_style_locked.set_corner_radius_all(10)
	# 未解锁卡片的选中/悬停态刻意做得很弱：用亮蓝边框会和「可挑战」的选中态
	# 撞在一起，玩家会以为自己点得进去。
	_style_locked_focus = UiStyle.button_style(Color(0.10, 0.11, 0.15, 0.95),
			Color(0.34, 0.38, 0.45))
	_style_locked_focus.set_corner_radius_all(10)
	_style_detail = UiStyle.panel_style()


func open() -> void:
	visible = true
	_refresh_records()
	_selected = _default_selection()
	_hover = -1
	_deny = 0.0
	queue_redraw()


func close() -> void:
	visible = false


func _refresh_records() -> void:
	_records.clear()
	for level: ChallengeData in ChallengeData.levels():
		_records[level.id] = Records.challenge_record(level.id)


func _record_of(level_id: String) -> Dictionary:
	var empty: Dictionary = {"cleared": false, "time": 0.0, "kills": 0}
	return _records.get(level_id, empty)


func _process(delta: float) -> void:
	if not visible:
		return
	_deny = maxf(0.0, _deny - delta)
	if _deny > 0.0:
		queue_redraw()
	_hover = _index_at(get_viewport().get_mouse_position())
	queue_redraw()


# ---------------------------------------------------------------- 布局

func _view_size() -> Vector2:
	return get_viewport_rect().size


func _layout() -> Dictionary:
	var view: Vector2 = _view_size()
	var rows: int = int(ceil(float(ChallengeData.count()) / float(COLUMNS)))
	var grid := Vector2(
		CARD.x * float(COLUMNS) + GAP * float(COLUMNS - 1),
		CARD.y * float(rows) + GAP * float(rows - 1))
	var block: float = HEADER + grid.y + 18.0 + DETAIL_HEIGHT + 16.0 + 18.0
	# 视口很矮时（窗口被拖小）宁可贴顶也不要算成负数把标题推到屏幕外。
	var top: float = maxf(16.0, (view.y - block) * 0.5)
	return {
		"view": view,
		"grid_origin": Vector2((view.x - grid.x) * 0.5, top + HEADER),
		"grid": grid,
		"top": top,
		"detail_y": top + HEADER + grid.y + 18.0,
		"hint_y": top + block - 4.0,
	}


func _card_rect(index: int) -> Rect2:
	var data: Dictionary = _layout()
	var origin: Vector2 = data["grid_origin"]
	var column: int = index % COLUMNS
	var row: int = index / COLUMNS
	return Rect2(origin + Vector2(
			float(column) * (CARD.x + GAP),
			float(row) * (CARD.y + GAP)), CARD)


func _index_at(pos: Vector2) -> int:
	for i in ChallengeData.count():
		if _card_rect(i).has_point(pos):
			return i
	return -1


# ---------------------------------------------------------------- 绘制

func _draw() -> void:
	var data: Dictionary = _layout()
	var view: Vector2 = data["view"]
	draw_rect(Rect2(Vector2.ZERO, view), Color(0.03, 0.04, 0.06, 0.90))

	var top: float = data["top"]
	UiStyle.draw_label(self, Vector2(view.x * 0.5 - 220.0, top + 30.0), "挑战模式", 34,
			UiStyle.TEXT, HORIZONTAL_ALIGNMENT_CENTER, 440.0)
	UiStyle.draw_label(self, Vector2(view.x * 0.5 - 220.0, top + 52.0), "CHALLENGE", 12,
			UiStyle.ACCENT, HORIZONTAL_ALIGNMENT_CENTER, 440.0)

	for i in ChallengeData.count():
		_draw_card(i, _card_rect(i))
	_draw_detail(data)

	var sel_hint: String = "WASD / 方向键 选择    Enter 进入关卡    ESC 返回"
	if OS.has_feature("touchscreen"):
		sel_hint = "点击关卡进入    ESC 返回"
	UiStyle.draw_label(self, Vector2(view.x * 0.5 - 260.0, data["hint_y"]),
			sel_hint, 12,
			UiStyle.DIM, HORIZONTAL_ALIGNMENT_CENTER, 520.0)


func _draw_card(index: int, rect: Rect2) -> void:
	var level: ChallengeData = ChallengeData.at(index)
	if level == null:
		return
	var unlocked: bool = is_unlocked(index)
	var record: Dictionary = _record_of(level.id)
	var cleared: bool = bool(record["cleared"])
	var active: bool = index == _selected
	var hovered: bool = index == _hover

	var style: StyleBoxFlat = _style_normal
	if not unlocked:
		style = _style_locked_focus if (active or hovered) else _style_locked
	elif active or hovered:
		style = _style_active
	draw_style_box(style, rect)
	if _deny > 0.0 and active and not unlocked:
		# 未解锁时的拒绝反馈：只闪边框不弹提示框，暂停状态下弹窗会打断整屏。
		var alpha: float = 0.55 * (_deny / 0.6)
		draw_rect(rect, Color(0.95, 0.32, 0.34, alpha * 0.22))
		draw_rect(rect, Color(0.95, 0.32, 0.34, alpha), false, 2.0)

	var tier_color: Color = ChallengeData.tier_color(int(level.tier))
	if not unlocked:
		tier_color = tier_color.darkened(0.55)

	# 左侧关卡编号徽章
	var badge: Vector2 = rect.position + Vector2(36.0, rect.size.y * 0.5)
	draw_circle(badge, 17.0, Color(tier_color.r, tier_color.g, tier_color.b, 0.16))
	draw_arc(badge, 17.0, 0.0, TAU, 24, tier_color, 1.6, true)
	UiStyle.draw_label(self, badge + Vector2(-17.0, 6.0), str(index + 1), 17, tier_color,
			HORIZONTAL_ALIGNMENT_CENTER, 34.0)

	var text_x: float = rect.position.x + 64.0
	var title_color: Color = UiStyle.TEXT if unlocked else UiStyle.DIM
	UiStyle.draw_label(self, Vector2(text_x, rect.position.y + 32.0),
			level.display_name, 19, title_color)
	UiStyle.draw_label(self, Vector2(text_x, rect.position.y + 52.0),
			level.subtitle, 11, UiStyle.DIM)

	var right: float = rect.position.x + rect.size.x - 158.0
	UiStyle.draw_label(self, Vector2(right, rect.position.y + 32.0), level.objective_text(), 12,
			UiStyle.ACCENT if unlocked else UiStyle.DIM, HORIZONTAL_ALIGNMENT_RIGHT, 142.0)
	UiStyle.draw_label(self, Vector2(right, rect.position.y + 52.0), level.star_text(), 12,
			tier_color, HORIZONTAL_ALIGNMENT_RIGHT, 142.0)

	var status: String = ""
	var status_color: Color = UiStyle.DIM
	if not unlocked:
		status = "未解锁 · 先通关上一关"
		status_color = Color(0.44, 0.50, 0.58)
	elif cleared:
		status = "已通关   最佳 %s · %d 击杀" % [
			GameOverlay.format_time(float(record["time"])), int(record["kills"])]
		status_color = Color(0.52, 0.88, 0.64)
	elif float(record["time"]) > 0.0:
		status = "未通关   最佳 %s" % GameOverlay.format_time(float(record["time"]))
	else:
		status = "未通关   尚无记录"
	UiStyle.draw_label(self, Vector2(text_x, rect.position.y + 76.0), status, 11, status_color)


func _draw_detail(data: Dictionary) -> void:
	var view: Vector2 = data["view"]
	var level: ChallengeData = ChallengeData.at(_selected)
	if level == null:
		return
	var width: float = data["grid"].x
	var rect := Rect2(Vector2((view.x - width) * 0.5, data["detail_y"]), Vector2(width, DETAIL_HEIGHT))
	draw_style_box(_style_detail, rect)

	UiStyle.draw_label(self, rect.position + Vector2(20.0, 28.0),
			"%d. %s    %s" % [_selected + 1, level.display_name, level.subtitle], 15, UiStyle.TEXT)
	UiStyle.draw_label(self, rect.position + Vector2(width - 176.0, 28.0),
			"难度 %s  %s" % [ChallengeData.tier_name(int(level.tier)), level.star_text()], 12,
			ChallengeData.tier_color(int(level.tier)), HORIZONTAL_ALIGNMENT_RIGHT, 156.0)
	UiStyle.draw_paragraph(self, rect.position + Vector2(20.0, 52.0),
			level.blurb + "\n墓室碎石会随机隆起，挡住你与邪物的去路。", 12,
			Color(0.78, 0.83, 0.90), width - 40.0, 3)


# ---------------------------------------------------------------- 输入

func _input(event: InputEvent) -> void:
	if not visible:
		return

	var key := event as InputEventKey
	if key != null:
		if not key.pressed or key.echo:
			return
		match key.keycode:
			KEY_LEFT, KEY_A:
				_consume()
				_move(-1)
			KEY_RIGHT, KEY_D:
				_consume()
				_move(1)
			KEY_UP, KEY_W:
				_consume()
				_move(-COLUMNS)
			KEY_DOWN, KEY_S:
				_consume()
				_move(COLUMNS)
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
				_consume()
				_confirm()
			KEY_ESCAPE:
				_consume()
				AudioManager.play("click")
				closed.emit()
		return

	var click := event as InputEventMouseButton
	if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		var index: int = _index_at(click.position)
		if index >= 0:
			_selected = index
			_confirm()


func _consume() -> void:
	get_viewport().set_input_as_handled()


## 只移动不环绕：上下来回扫到底时停在边界，比跳回对角更符合「列表」的心理模型。
func _move(step: int) -> void:
	var target: int = _selected + step
	if target < 0 or target >= ChallengeData.count():
		return
	_selected = target
	_deny = 0.0
	AudioManager.play("click")


func _confirm() -> void:
	if not is_unlocked(_selected):
		_deny = 0.6
		return
	AudioManager.play("start")
	level_chosen.emit(_selected)


## 第 i 关是否已解锁：第一关永远开放，其余要求上一关「通关过」而不是「打过」。
func is_unlocked(index: int) -> bool:
	if index <= 0:
		return true
	var previous: ChallengeData = ChallengeData.at(index - 1)
	if previous == null:
		return true
	return bool(_record_of(previous.id)["cleared"])


## 打开时默认停在「第一个已解锁且没通关」的关卡上 —— 玩家每次进来想找的
## 基本就是它，省掉一次手动翻找。
func _default_selection() -> int:
	for i in ChallengeData.count():
		if is_unlocked(i) and not bool(_record_of(ChallengeData.at(i).id)["cleared"]):
			return i
	return 0
