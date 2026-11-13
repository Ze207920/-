# 游戏内 HUD：血条、经验条、计时、击杀数、武器栏。
#
# 用 _draw 自绘而不是拼 Label/ProgressBar：一屏里只有几个矩形和几行字，
# 自绘省掉十几个 Control 的布局计算，也更容易做出统一的视觉风格。
# 每帧重绘一次（单个 Control），开销可以忽略。
class_name Hud
extends Control

const MARGIN: float = 22.0
const HP_BAR: Vector2 = Vector2(252.0, 20.0)
const XP_HEIGHT: float = 5.0

var level: int = 1
var health: float = 100.0
var max_health: float = 100.0
var xp: int = 0
var xp_next: int = 5
var kills: int = 0
var elapsed: float = 0.0
var enemy_count: int = 0
var weapon_lines: Array[String] = []
## 挑战模式关卡名；空串表示生存模式，顶部不会多画那一行。
var challenge_name: String = ""
## 距离通关还剩多少秒。-1 表示当前不在挑战模式。
var challenge_remaining: float = -1.0
## 关卡进度 0~1。-1 表示不在挑战模式。
var challenge_progress: float = -1.0
## 当前角色名。空串表示不显示。
var character_name: String = ""
## 技能栏：每个已解锁技能一格，各自显示冷却。手机上交给一排实体按钮，
## 这里不画（否则窄屏会和右下角按钮打架）。
var skill_slots: Array[Dictionary] = []
## 三个技能集齐后的强化层数，0 表示还没开始强化。
var skill_mastery: int = 0
var show_skill_chips: bool = true
## 升级解锁 / 强化时的横幅提示。
var toast_text: String = ""
var toast_time: float = 0.0

var _hurt_flash: float = 0.0
var _pulse: float = 0.0


func _ready() -> void:
	# 暂停时血条仍要可见可读，否则玩家在暂停界面里看不到自己剩多少血。
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = UiStyle.theme()


func _process(delta: float) -> void:
	if not visible:
		return
	_pulse += delta
	_hurt_flash = maxf(0.0, _hurt_flash - delta * 3.4)
	if toast_time > 0.0:
		toast_time = maxf(0.0, toast_time - delta)
	queue_redraw()


## 弹一条短横幅。升 5 的倍数级时由 Game 调用。
func show_toast(text: String, seconds: float = 2.8) -> void:
	toast_text = text
	toast_time = seconds
	queue_redraw()


## 受击时调一次，触发全屏红闪。
func flash_hurt() -> void:
	_hurt_flash = 1.0


func _draw() -> void:
	var view: Vector2 = size
	if view.x <= 1.0 or view.y <= 1.0:
		view = get_viewport_rect().size
	_draw_vignette(view)
	_draw_xp_bar(view)
	_draw_health()
	_draw_timer(view)
	_draw_challenge(view)
	_draw_stats(view)
	_draw_audio_state(view)
	_draw_skill(view)
	_draw_toast(view)
	_draw_weapons(view)


func _draw_xp_bar(view: Vector2) -> void:
	var ratio: float = clampf(float(xp) / maxf(1.0, float(xp_next)), 0.0, 1.0)
	draw_rect(Rect2(0.0, 0.0, view.x, XP_HEIGHT), Color(0.10, 0.12, 0.16, 0.92))
	if ratio > 0.0:
		draw_rect(Rect2(0.0, 0.0, view.x * ratio, XP_HEIGHT), UiStyle.XP)
		# 顶部一条更亮的细线，让进度条有"发光"的观感，几乎零成本。
		draw_rect(Rect2(0.0, 0.0, view.x * ratio, 1.5), Color(1.0, 1.0, 1.0, 0.55))


func _draw_health() -> void:
	var ratio: float = clampf(health / maxf(1.0, max_health), 0.0, 1.0)
	var low: bool = ratio <= 0.32
	var bar := Rect2(MARGIN, MARGIN, HP_BAR.x, HP_BAR.y)

	draw_rect(Rect2(bar.position - Vector2(1.0, 1.0), bar.size + Vector2(2.0, 2.0)),
			Color(0.0, 0.0, 0.0, 0.55))
	draw_rect(bar, Color(0.13, 0.10, 0.12, 0.95))

	var fill: Color = UiStyle.HP
	if low:
		# 低血时血条自身脉动，比单纯变红更容易被余光捕捉到。
		var breathe: float = 0.5 + 0.5 * sin(_pulse * 7.0)
		fill = UiStyle.HP_LOW.lerp(Color(1.0, 0.72, 0.35), breathe * 0.55)
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * ratio, bar.size.y)), fill)
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * ratio, 3.0)), Color(1.0, 1.0, 1.0, 0.28))

	UiStyle.draw_label(self, bar.position + Vector2(10.0, bar.size.y - 5.0),
			"HP  %d / %d" % [int(ceil(health)), int(max_health)], 13, Color(1.0, 1.0, 1.0, 0.96))
	UiStyle.draw_label(self, bar.position + Vector2(bar.size.x + 12.0, bar.size.y - 3.0),
			"LV %d" % level, 15, UiStyle.ACCENT)
	if character_name != "":
		UiStyle.draw_label(self, bar.position + Vector2(bar.size.x + 68.0, bar.size.y - 3.0),
				character_name, 14, UiStyle.DIM)


func _draw_timer(view: Vector2) -> void:
	var text: String = "%02d:%02d" % [int(elapsed) / 60, int(elapsed) % 60]
	UiStyle.draw_label(self, Vector2(view.x * 0.5 - 70.0, 46.0), text, 26,
			UiStyle.TEXT, HORIZONTAL_ALIGNMENT_CENTER, 140.0)


## 挑战模式专属：关卡名 + 剩余秒数 + 一条进度条。
## 只给正计时不够 —— 这一局的目标是「活到 X 秒」，玩家真正关心的是还差多少，
## 每次都要用总时长减一遍是不必要的脑力开销。
func _draw_challenge(view: Vector2) -> void:
	if challenge_progress < 0.0:
		return
	var remaining: String = "%02d:%02d" % [int(challenge_remaining) / 60, int(challenge_remaining) % 60]
	UiStyle.draw_label(self, Vector2(view.x * 0.5 - 170.0, 66.0),
			"%s    剩余 %s" % [challenge_name, remaining], 12,
			UiStyle.ACCENT, HORIZONTAL_ALIGNMENT_CENTER, 340.0)

	var bar := Rect2(view.x * 0.5 - 120.0, 72.0, 240.0, 4.0)
	draw_rect(Rect2(bar.position - Vector2(1.0, 1.0), bar.size + Vector2(2.0, 2.0)),
			Color(0.0, 0.0, 0.0, 0.45))
	draw_rect(bar, Color(0.13, 0.17, 0.23, 0.92))
	var filled: float = clampf(challenge_progress, 0.0, 1.0)
	if filled > 0.0:
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * filled, bar.size.y)), UiStyle.ACCENT)


func _draw_stats(view: Vector2) -> void:
	UiStyle.draw_label(self, Vector2(view.x - MARGIN - 190.0, 36.0), "击杀 %d" % kills, 17,
			UiStyle.TEXT, HORIZONTAL_ALIGNMENT_RIGHT, 190.0)
	UiStyle.draw_label(self, Vector2(view.x - MARGIN - 190.0, 58.0), "同屏 %d" % enemy_count, 12,
			UiStyle.DIM, HORIZONTAL_ALIGNMENT_RIGHT, 190.0)


## 静音提示。只在静音时出现 —— 常驻一个喇叭图标等于噪声。
## 玩家按 M 后必须能立刻看到反馈，否则会以为按键没生效而反复按。
func _draw_audio_state(view: Vector2) -> void:
	if not AudioManager.muted:
		return
	UiStyle.draw_label(self, Vector2(view.x - MARGIN - 190.0, 84.0), "M  已静音", 12,
			Color(0.95, 0.56, 0.46), HORIZONTAL_ALIGNMENT_RIGHT, 190.0)


func _draw_weapons(view: Vector2) -> void:
	if weapon_lines.is_empty():
		return
	var line_height: float = 20.0
	var top: float = view.y - MARGIN - line_height * float(weapon_lines.size() - 1)
	for i in weapon_lines.size():
		var y: float = top + line_height * float(i)
		draw_circle(Vector2(MARGIN + 3.0, y - 5.0), 3.0, UiStyle.ACCENT)
		UiStyle.draw_label(self, Vector2(MARGIN + 12.0, y), weapon_lines[i], 13, UiStyle.DIM)


## 技能栏：每个已解锁技能一格，冷却用填充表达，一眼能看出"走了多少"。
## 最多 3 格（Lv1 / Lv5 / Lv10），之后升级只加"强化 ×N"，不再撑宽这一排。
func _draw_skill(view: Vector2) -> void:
	if not show_skill_chips or skill_slots.is_empty():
		return
	var n: int = skill_slots.size()
	var gap: float = 6.0
	var max_total: float = minf(420.0, view.x - 40.0)
	var cell_w: float = minf(130.0, (max_total - gap * float(n - 1)) / float(n))
	var cell_h: float = 34.0
	var total_w: float = cell_w * float(n) + gap * float(n - 1)
	var x0: float = view.x * 0.5 - total_w * 0.5
	var y: float = view.y - 62.0

	if skill_mastery > 0:
		UiStyle.draw_label(self, Vector2(x0, y - 17.0),
				"技能强化 ×%d   冷却更短 · 威力更强" % skill_mastery, 11,
				UiStyle.ACCENT)

	for i in n:
		var slot: Dictionary = skill_slots[i]
		var total: float = maxf(0.01, float(slot.get("total", 1.0)))
		var left: float = float(slot.get("remaining", 0.0))
		var ready: bool = left <= 0.0
		var accent: Color = slot.get("color", UiStyle.ACCENT)
		var bar := Rect2(x0 + float(i) * (cell_w + gap), y, cell_w, cell_h)

		draw_rect(Rect2(bar.position - Vector2(1.0, 1.0), bar.size + Vector2(2.0, 2.0)),
				Color(0.0, 0.0, 0.0, 0.55))
		draw_rect(bar, Color(0.08, 0.10, 0.14, 0.88))
		var ratio: float = 1.0 - clampf(left / total, 0.0, 1.0)
		if ratio > 0.0:
			draw_rect(Rect2(bar.position, Vector2(bar.size.x * ratio, bar.size.y)),
					Color(accent.r, accent.g, accent.b, 0.20))
			draw_rect(Rect2(bar.position, Vector2(bar.size.x * ratio, 2.0)),
					Color(accent.r, accent.g, accent.b, 0.85))
		draw_rect(bar, accent if ready else Color(0.26, 0.30, 0.36), false, 1.2)

		var name_text: String = "%d  %s" % [int(slot.get("key", i + 1)),
				String(slot.get("name", ""))]
		UiStyle.draw_label(self, bar.position + Vector2(8.0, 16.0), name_text, 12,
				UiStyle.TEXT if ready else UiStyle.DIM, HORIZONTAL_ALIGNMENT_LEFT,
				cell_w - 16.0)
		var state: String = "就绪" if ready else "%.1fs" % left
		UiStyle.draw_label(self, bar.position + Vector2(8.0, 30.0), state, 10,
				accent if ready else UiStyle.DIM)


## 解锁 / 强化的横幅：放在屏幕偏上，避开底部技能栏与右下角按钮。
func _draw_toast(view: Vector2) -> void:
	if toast_time <= 0.0 or toast_text == "":
		return
	var width: float = minf(420.0, view.x - 40.0)
	var height: float = 42.0
	var box := Rect2(view.x * 0.5 - width * 0.5, view.y * 0.28, width, height)
	var alpha: float = clampf(toast_time / 0.5, 0.0, 1.0)
	draw_rect(box, Color(0.06, 0.09, 0.14, 0.88 * alpha))
	draw_rect(box, Color(UiStyle.ACCENT.r, UiStyle.ACCENT.g, UiStyle.ACCENT.b,
			0.75 * alpha), false, 1.5)
	UiStyle.draw_label(self, Vector2(box.position.x, box.position.y + 27.0),
			toast_text, 16, UiStyle.TEXT, HORIZONTAL_ALIGNMENT_CENTER, width)


## 低血边缘告警 + 受击红闪。两块都用半透明纯色矩形拼，
## 比做一张渐变贴图省资源，也避免引入图片依赖。
func _draw_vignette(view: Vector2) -> void:
	var ratio: float = health / maxf(1.0, max_health)
	if ratio < 0.35:
		var strength: float = clampf((0.35 - ratio) / 0.35, 0.0, 1.0)
		var breathe: float = 0.55 + 0.45 * sin(_pulse * 6.0)
		var alpha: float = strength * breathe * 0.20
		var edge: float = 64.0
		var tint := Color(0.80, 0.05, 0.10, alpha)
		draw_rect(Rect2(0.0, 0.0, view.x, edge), tint)
		draw_rect(Rect2(0.0, view.y - edge, view.x, edge), tint)
		draw_rect(Rect2(0.0, 0.0, edge, view.y), tint)
		draw_rect(Rect2(view.x - edge, 0.0, edge, view.y), tint)

	if _hurt_flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, view),
				Color(0.85, 0.06, 0.10, 0.16 * _hurt_flash))
