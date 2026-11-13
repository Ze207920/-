# 选人界面：一屏列出四个可操控角色，选完立刻生效。
#
# 和选关一样用 _draw 自绘卡片，而不是拼四个 Button —— 每张卡要同时画主题色
# 边框、属性表、技能说明和一个会呼吸的小人立绘，Button 反而更绕。
#
# 立绘不是贴图，而是真的 Player 节点（preview 模式）：这样「选人界面看到的」
# 和「进游戏操控的」永远是同一套绘制代码，不可能出现选了胖子却长出小哥的情况。
class_name CharacterSelect
extends Control

signal character_chosen(id: String)
signal closed

const CARD: Vector2 = Vector2(250.0, 368.0)
const GAP: float = 16.0
const HEADER: float = 74.0
## 立绘缩放。Player 本体约 40 像素高，2.3 倍后在卡片里占 90 像素左右，
## 既看得清头发/墨镜/肚子这些辨识点，又不会顶到名字。
const PREVIEW_SCALE: float = 2.3

var _selected: int = 0
var _hover: int = -1
var _previews: Array[Player] = []

var _style_normal: StyleBoxFlat = null
var _style_active: StyleBoxFlat = null


func _ready() -> void:
	# 选人期间整棵树是暂停的，这一层必须继续跑，否则既不重绘也不收键。
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = UiStyle.theme()
	_build_styles()
	_build_previews()
	visible = false


func _build_styles() -> void:
	_style_normal = UiStyle.button_style(Color(0.08, 0.10, 0.14, 0.97), UiStyle.BORDER)
	_style_normal.set_corner_radius_all(12)
	_style_active = UiStyle.button_style(Color(0.12, 0.17, 0.23, 0.99), UiStyle.ACCENT, 2)
	_style_active.set_corner_radius_all(12)


## 每个角色一个预览实例。它们只负责画，不参与任何玩法逻辑。
func _build_previews() -> void:
	for data: CharacterData in CharacterData.all():
		var preview := Player.new()
		preview.preview = true
		preview.apply_character(data)
		preview.scale = Vector2(PREVIEW_SCALE, PREVIEW_SCALE)
		add_child(preview)
		_previews.append(preview)


func open() -> void:
	visible = true
	var current: CharacterData = CharacterData.selected()
	_selected = maxi(0, CharacterData.index_of(current.id))
	_hover = -1
	_place_previews()
	queue_redraw()


func close() -> void:
	visible = false


func _process(delta: float) -> void:
	if not visible:
		return
	_hover = _index_at(get_viewport().get_mouse_position())
	_place_previews()
	queue_redraw()


# ---------------------------------------------------------------- 布局

func _view_size() -> Vector2:
	return get_viewport_rect().size


func _layout() -> Dictionary:
	var view: Vector2 = _view_size()
	var count: int = maxi(1, CharacterData.count())
	var grid := Vector2(
		CARD.x * float(count) + GAP * float(count - 1),
		CARD.y)
	var block: float = HEADER + grid.y + 46.0
	# 窗口被拖得很矮时宁可贴顶，也不要把标题算到屏幕外。
	var top: float = maxf(16.0, (view.y - block) * 0.5)
	return {
		"view": view,
		"grid_origin": Vector2((view.x - grid.x) * 0.5, top + HEADER),
		"grid": grid,
		"top": top,
		"hint_y": top + block - 14.0,
	}


func _card_rect(index: int) -> Rect2:
	var data: Dictionary = _layout()
	var origin: Vector2 = data["grid_origin"]
	return Rect2(origin + Vector2(float(index) * (CARD.x + GAP), 0.0), CARD)


func _index_at(pos: Vector2) -> int:
	for i in CharacterData.count():
		if _card_rect(i).has_point(pos):
			return i
	return -1


func _place_previews() -> void:
	for i in _previews.size():
		var preview: Player = _previews[i]
		if not is_instance_valid(preview):
			continue
		var rect: Rect2 = _card_rect(i)
		preview.position = rect.position + Vector2(rect.size.x * 0.5, 148.0)


# ---------------------------------------------------------------- 绘制

func _draw() -> void:
	var data: Dictionary = _layout()
	var view: Vector2 = data["view"]
	draw_rect(Rect2(Vector2.ZERO, view), Color(0.03, 0.04, 0.06, 0.92))

	var top: float = data["top"]
	UiStyle.draw_label(self, Vector2(view.x * 0.5 - 240.0, top + 32.0), "选择角色", 34,
			UiStyle.TEXT, HORIZONTAL_ALIGNMENT_CENTER, 480.0)
	UiStyle.draw_label(self, Vector2(view.x * 0.5 - 240.0, top + 54.0), "CHARACTERS", 12,
			UiStyle.ACCENT, HORIZONTAL_ALIGNMENT_CENTER, 480.0)

	for i in CharacterData.count():
		_draw_card(i, _card_rect(i))

	var hint: String = "A / D 选择    Enter 确认    ESC 返回"
	if OS.has_feature("touchscreen"):
		hint = "点击角色确认    ESC 返回"
	UiStyle.draw_label(self, Vector2(view.x * 0.5 - 260.0, data["hint_y"]), hint, 12,
			UiStyle.DIM, HORIZONTAL_ALIGNMENT_CENTER, 520.0)


func _draw_card(index: int, rect: Rect2) -> void:
	var data: CharacterData = CharacterData.at(index)
	if data == null:
		return
	var active: bool = index == _selected
	var hovered: bool = index == _hover
	var style: StyleBoxFlat = _style_active if (active or hovered) else _style_normal
	draw_style_box(style, rect)

	# 顶部一条主题色横条：四张卡并排时，颜色是比文字更快的识别入口。
	draw_rect(Rect2(rect.position, Vector2(rect.size.x, 3.0)),
			Color(data.accent.r, data.accent.g, data.accent.b, 0.85 if active else 0.45))

	# 立绘背后一圈淡色光，免得深色衣服贴在深色卡片上看不出轮廓。
	var halo: Vector2 = rect.position + Vector2(rect.size.x * 0.5, 132.0)
	draw_circle(halo, 54.0, Color(data.accent.r, data.accent.g, data.accent.b, 0.10))

	UiStyle.draw_label(self, rect.position + Vector2(16.0, 34.0), data.display_name, 21,
			UiStyle.TEXT)
	UiStyle.draw_label(self, rect.position + Vector2(16.0, 54.0), data.role, 12,
			data.accent)

	draw_line(rect.position + Vector2(16.0, 194.0),
			rect.position + Vector2(rect.size.x - 16.0, 194.0),
			Color(0.24, 0.28, 0.35, 0.9), 1.0)

	_draw_stats(rect, data)

	UiStyle.draw_label(self, rect.position + Vector2(16.0, 262.0),
			"技能阶梯   每 5 级一阶", 11, UiStyle.DIM)
	for i in data.skill_ladder.size():
		var def: SkillDef = data.skill_ladder[i]
		var row_y: float = 284.0 + float(i) * 21.0
		UiStyle.draw_label(self, rect.position + Vector2(16.0, row_y),
				def.tier_text(), 12, data.accent if i == 0 else UiStyle.TEXT)
		UiStyle.draw_label(self, rect.position + Vector2(rect.size.x - 74.0, row_y),
				"%ds" % int(def.cooldown), 10, UiStyle.DIM,
				HORIZONTAL_ALIGNMENT_RIGHT, 58.0)
	UiStyle.draw_label(self, rect.position + Vector2(16.0, 352.0),
			"三招之后每 5 级  技能强化", 10, UiStyle.DIM)

	if active:
		UiStyle.draw_label(self, rect.position + Vector2(rect.size.x - 92.0, 34.0),
				"使用中", 11, data.accent, HORIZONTAL_ALIGNMENT_RIGHT, 76.0)


## 属性表：两列四行。数值本身比"高/中/低"更好判断，尤其是玩家开始比较角色时。
func _draw_stats(rect: Rect2, data: CharacterData) -> void:
	var left: float = rect.position.x + 16.0
	var right: float = rect.position.x + rect.size.x * 0.5 + 6.0
	var y: float = rect.position.y
	var color: Color = Color(0.80, 0.85, 0.92)

	UiStyle.draw_label(self, Vector2(left, y + 216.0), "生命 %d" % int(data.max_health), 12, color)
	UiStyle.draw_label(self, Vector2(right, y + 216.0), "移速 %d" % int(data.move_speed), 12, color)
	UiStyle.draw_label(self, Vector2(left, y + 236.0), "伤害 x%.2f" % data.damage_scale, 12, color)
	UiStyle.draw_label(self, Vector2(right, y + 236.0), "拾取 %d" % int(data.pickup_radius), 12, color)


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
				_move(-1)
			KEY_DOWN, KEY_S:
				_consume()
				_move(1)
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


## 四个角色在一行里，左右移动就够了。做环绕而不是停边：只有四个选项，
## 从最右按右键回到最左符合"一排卡片"的直觉，也让键盘操作少按几次。
func _move(step: int) -> void:
	var count: int = CharacterData.count()
	if count <= 0:
		return
	_selected = (_selected + step + count) % count
	AudioManager.play("click")


func _confirm() -> void:
	var data: CharacterData = CharacterData.at(_selected)
	if data == null:
		return
	AudioManager.play("start")
	character_chosen.emit(data.id)
