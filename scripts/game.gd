# 主场景：生成玩家与敌人、接触伤害、经验宝石、升级三选一、HUD 与全屏界面。
# 攻击与命中已下沉到 Weapon / Projectile，本类只做编排与状态机。
class_name Game
extends Node2D

## 经验宝石：靠近玩家后加速飞向玩家，接触即结算经验。
## 即使暂时在磁吸范围外，也会以较低速度缓慢向玩家靠拢 —— 否则走位型玩家
## 一边逃跑一边击杀，宝石全留在原地，越跑越捡不到，升级完全停滞（实测 120 秒
## 只有 4 级），「躲避」变成纯负收益玩法。
class XpGem extends Node2D:
	signal collected(amount: int)

	## 磁吸范围外的靠拢速度（像素/秒）。
	## 必须明显高于玩家移速（190），否则玩家一旦持续移动，身后掉落的宝石
	## 就永远追不上——「跑得快」会变成纯负收益，等级卡死、越跑越打不动。
	const DRIFT_SPEED: float = 250.0
	## 存活上限：漂移让宝石长期存在，需要兜底防止无限堆积。
	const MAX_LIFE: float = 60.0

	var amount: int = 1
	var _target: Player = null
	var _fly_speed: float = 70.0
	var _life: float = 0.0

	func setup(target: Player, value: int) -> void:
		_target = target
		amount = value
		_fly_speed = DRIFT_SPEED
		_life = 0.0

	func _physics_process(delta: float) -> void:
		if not is_instance_valid(_target):
			return
		_life += delta
		if _life >= MAX_LIFE:
			queue_free()
			return
		var to_target: Vector2 = _target.global_position - global_position
		var distance: float = to_target.length()
		if distance <= 15.0:
			collected.emit(amount)
			queue_free()
			return
		if distance > _target.pickup_radius:
			# 范围外：持续追踪，保证逃跑中的玩家仍能吃到很久以前掉落的宝石
			global_position += to_target.normalized() * DRIFT_SPEED * delta
			return
		# 进圈后不能从 DRIFT_SPEED 掉回 70 起速，否则会「越吸越慢」
		_fly_speed = maxf(_fly_speed, DRIFT_SPEED)
		_fly_speed = minf(560.0, _fly_speed + 1000.0 * delta)
		global_position += to_target.normalized() * _fly_speed * delta

	func _draw() -> void:
		draw_circle(Vector2.ZERO, 5.0, Color(0.42, 0.90, 0.95))
		draw_circle(Vector2.ZERO, 2.0, Color(0.90, 1.0, 1.0, 0.85))


## 击杀特效：一圈迅速扩散并淡出的光环。
## 用纯 _draw 而不是粒子系统：一次只活 0.26 秒、同屏上限几十个，
## 粒子节点本身的创建与材质切换开销反而更大。
class DeathBurst extends Node2D:
	const DURATION: float = 0.26

	var color: Color = Color(1.0, 1.0, 1.0)
	var start_radius: float = 6.0
	var end_radius: float = 26.0

	var _life: float = 0.0

	func _process(delta: float) -> void:
		_life += delta
		if _life >= DURATION:
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		var t: float = clampf(_life / DURATION, 0.0, 1.0)
		var radius: float = lerpf(start_radius, end_radius, t)
		var ring: Color = color
		ring.a = (1.0 - t) * 0.7
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 18, ring, 2.0, true)


## 场景状态。暂停、开始界面、结算界面都靠它切换，而不是散落的布尔量。
enum State {
	TITLE,
	PLAYING,
	PAUSED,
	OVER,
}

## 玩法模式。挑战模式在生存模式之上叠一层「关卡目标」：活到指定秒数即通关。
enum Mode {
	ENDLESS,
	CHALLENGE,
}

## 当前模式与关卡索引。用静态变量而不是场景字段，是因为重开一局走的是
## reload_current_scene —— 场景会整个重建，实例字段一律归零，而「我在打第几关」
## 必须跨过这次重建。
static var mode: int = Mode.ENDLESS
static var challenge_index: int = 0
## 重载后是否直接开打（跳过标题页）。重开、下一关都为 true，返回标题为 false。
static var auto_start: bool = false
## 重载后是否直接弹出选关界面。结算页的「返回选关」用它。
static var open_select_on_load: bool = false

## 同屏敌人硬上限，防止极端情况下把帧率拖垮；真正生效的上限由难度曲线决定。
@export var max_enemies: int = 400
## 刷怪位置的最小距离。候选点落在「视野外一圈」的矩形边界上（见
## _random_spawn_point），这个值只是场地被墙夹小之后的兜底，防止怪贴脸生成。
@export var spawn_distance: float = 380.0
## 刷怪边界相对屏幕的外扩比例：1.0 就是紧贴屏幕边缘再外推 48 像素。
@export var spawn_margin: float = 1.0
@export var upgrade_choices: int = 3

## 难度曲线关键帧，段内线性插值。调平衡只改这张表。
## 列：[秒数, 血量倍率, 移速倍率, 刷怪间隔(秒), 同屏上限, 每批数量, 接触伤害倍率]
## 配平基准：
## 1) 击杀速率必须始终略高于刷怪速率，否则敌人堆积成墙、玩家捡不到宝石，
##    会陷入「打不动 → 升不了级 → 更打不动」的死循环。
## 2) 移速倍率必须最终追上玩家（190 × 1.0），否则「一直往一个方向跑」是永久无解策略。
##    70 基础移速 × 2.9 ≈ 203，约 275 秒反超玩家；之后只能靠「轻装疾行」维持机动。
## 3) 同屏上限必须压在 220 以内：敌人是 CharacterBody2D，每个物理帧都要做碰撞查询，
##    实测 200 只时约 56 FPS、270 只时掉到 48 FPS。
## 4) 前中期的血量与接触伤害刻意压低：开局只有一把手枪，若这 3 分钟清不动场，
##    就凑不出经验滚雪球，会卡在 10 级左右被怪墙围死。
## 5) 被围时「贴身 7 只 × 单只伤害」每 0.4 秒结算一次，倍率给高了就是 1 秒内秒杀，
##    玩家根本来不及突围 —— 这是本作最容易失衡的地方。
## 6) 这张表只有在「敌人真的能不断贴到玩家」时才生效。早先没有远处回收机制，
##    玩家一直跑就能把整屏怪吊在身后、占满同屏上限，刷怪器随即停工：实测
##    240 秒只有 73 击杀、8 级、满血，曲线形同虚设。回收机制上线后同一局
##    变成 366 击杀、15 级、81 血。
## 注意：这张表是按「无限地图」配平的，改成封闭墓室（ARENA_SIZE）之后整体下调过一档 ——
## 有墙时邪物不需要追得上玩家也能形成合围，被逼到墙角就无路可退，同屏密度的体感
## 比原来高得多。同屏上限 −18%、晚期移速 −15%、刷怪间隔 ×1.15，才是同一个难度。
const DIFFICULTY_KEYS: Array = [
	[0.0, 1.0, 1.00, 1.00, 32, 1, 1.00],
	[60.0, 1.7, 1.22, 0.52, 58, 2, 1.00],
	[120.0, 2.7, 1.45, 0.30, 84, 3, 1.10],
	[180.0, 4.0, 1.72, 0.21, 108, 4, 1.25],
	[240.0, 6.3, 2.10, 0.16, 128, 5, 1.45],
	[300.0, 8.6, 2.45, 0.127, 145, 5, 1.70],
	[420.0, 13.2, 2.75, 0.092, 162, 6, 2.10],
	[600.0, 20.5, 3.05, 0.070, 178, 7, 2.60],
]

## 场地（墓室）尺寸，可走区域就是这个矩形，四壁之外是黑的。
## 之前是无限地面：只要一直朝一个方向跑，整屏邪物都会被吊在身后，
## 「跑得远」成了万能解 —— 地图没有边界，走位就没有真正的位置压力。
## 现在改成封闭墓室：撞墙会停、被逼进墙角只能靠火力顶开，
## 玩法从「跑得远」变成「绕得开」。2100×1450 约 2.4 个屏幕，
## 横向跑一趟十秒上下 —— 够绕圈，来不及跑没。
const ARENA_SIZE: Vector2 = Vector2(2100.0, 1450.0)
## 墙带厚度（纯视觉）。可走区域的边界就是 ARENA，墙画在它外侧。
const WALL_THICKNESS: float = 72.0
## 相机允许越过场地的余量。必须大于墙厚：站在墙边时要把整条墙带看全，
## 否则玩家会以为「跑着跑着画面就卡住了」。
const CAMERA_MARGIN: float = 150.0

const MAX_BURSTS: int = 56

## 离玩家超过这个距离的敌人会被「回收」到屏幕边缘重新投放。
## 没有回收时，玩家只要一直跑，整屏敌人都会远远吊在后面：同屏上限被这批
## 永远追不上的怪占满，刷怪器随即停工，屏幕空了、经验也没了，越跑越无聊。
## 回收是瞬移，但起点和终点都在屏幕外，玩家看不到任何破绽。
const RECYCLE_DISTANCE: float = 1400.0
const RECYCLE_INTERVAL: float = 0.4

## 底面贴图按关卡取自 ArenaTheme（八张主题图 + 原始墓室图，见 arena_theme.gd）。
## 贴图缩放。原始石板约 140 像素宽，比角色大一个数量级，铺上去像「巨型方砖」；
## 0.68 之后单块约 95 像素，和原本 64 像素的地面网格尺度接近，观感才协调。
const FLOOR_SCALE: float = 0.68

var player: Player = null
var enemies: Array[Enemy] = []
var gems: Array[XpGem] = []
var level_panel: LevelUpPanel = null
var hud: Hud = null
var overlay: GameOverlay = null
var select_panel: ChallengeSelect = null
## 选人界面。挂在挑战选关更难盖的一层（layer 32），两者不会同时打开。
var character_panel: CharacterSelect = null
## 触屏摇杆（移动端）。桌面端禁用、保持隐藏，键盘玩法不受影响。
var joystick: TouchJoystick = null
## 右下角暂停按钮。手机无 ESC 键，必须有可点的暂停入口；桌面端也一并显示，更直观。
var pause_button: Button = null
## 升 5 的倍数级时攒下的提示。升级面板打开期间先存着，收起后再一起弹。
var _pending_toasts: Array[String] = []
## 每个已解锁技能一个按钮（最多 3 个）。桌面也留着，手机端是主要入口。
var skill_buttons: Array[Button] = []
## 按钮所在的层。技能随等级解锁，按钮要动态往这一层里加。
var _action_layer: CanvasLayer = null
## 挑战模式的随机障碍（墓室碎石）。仅在该模式下生成，列表随场景重载清空。
var _obstacles: Array[Obstacle] = []
var _obstacle_timer: float = 0.0
var kills: int = 0

## 当前关卡；生存模式下为 null，所有分支都用它区分两种玩法。
var _level: ChallengeData = null
## 刷怪落点翻到玩家前进方向的概率，挑战模式下由关卡决定。
var _front_bias: float = 0.55

var _state: State = State.TITLE
var _spawn_timer: float = 0.0
var _elapsed: float = 0.0
var _hud_timer: float = 0.0
var _is_leveling: bool = false
var _paused_by_level_up: bool = false
var _pending_level_ups: int = 0
var _camera: Camera2D = null
var _shake: float = 0.0
var _recycle_timer: float = 0.0
var _floor: Sprite2D = null
## 可走区域。所有「能不能站在这儿」的判断都走它：玩家夹制、邪物夹制、刷怪落点。
var _arena: Rect2 = Rect2()
## 本关主题（地面贴图 / 四壁 / 氛围 / 碎石材质）。生存模式是默认墓室。
var _theme: ArenaTheme = null
## 四壁的绘制节点。纯视觉，约束逻辑不在这里。
var _walls: ArenaWalls = null


func _ready() -> void:
	# 先按静态变量还原本局是哪种玩法：_spawn_player 之后的所有逻辑都依赖它。
	_level = ChallengeData.at(challenge_index) if mode == Mode.CHALLENGE else null
	_front_bias = _level.front_bias if _level != null else 0.55

	# 场地必须最先定下来：底面尺寸、相机限制、玩家夹制、刷怪落点全都依赖它。
	_build_arena()

	# 底面必须在玩家之后创建：它要按玩家位置摆位，否则标题界面会停在原点，
	# 只在右下角露出一块地面（暂停时不跑 _process，没人去纠正它）。
	_spawn_player()
	_build_floor()
	_build_ui()
	_build_level_panel()
	if auto_start:
		_enter_play()
	else:
		_enter_title()
		if open_select_on_load:
			open_select_on_load = false
			_open_challenge_select()


func _process(delta: float) -> void:
	_tick_shake(delta)
	_update_pause_button()
	_update_skill_buttons()
	# 技能冷却每帧都在变，HUD 却只按 0.15 秒刷新一次 —— 直接推给 HUD 自己算，
	# 否则技能条的填充会一格一格地跳。
	if hud != null and is_instance_valid(player):
		hud.skill_slots = player.skill_ui()
		hud.skill_mastery = player.skill_mastery


## 底面就是「一整块铺满墓室的石板」，不再跟着相机滚动。
## 无限地图时代必须跟着相机滚，否则跑出固定矩形就露底；现在场地有边界，
## 底面的范围天然就是 ARENA，边缘正好和墙带对齐 —— 反而简单了，
## 也顺带省掉每帧的对齐计算。
func _build_floor() -> void:
	_floor = Sprite2D.new()
	_floor.name = "Floor"
	# 贴图来自关卡主题：同一间墓室，八关八种地貌。
	_floor.texture = _theme.floor_texture
	# region 比纹理大，靠 repeat 铺满整间墓室。region 的单位是「贴图像素」，
	# 所以要按世界尺寸除以缩放换算。
	_floor.centered = false
	_floor.region_enabled = true
	_floor.region_rect = Rect2(Vector2.ZERO, _arena.size / FLOOR_SCALE)
	_floor.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	# 开了 mipmap：贴图被缩到 0.68 倍显示，不做 mip 采样会把砖缝抖成噪点。
	_floor.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_floor.scale = Vector2(FLOOR_SCALE, FLOOR_SCALE)
	_floor.z_index = -100
	add_child(_floor)
	_floor.global_position = _arena.position


## 建场地：矩形边界 + 四壁绘制。挑战模式每关可以有自己的尺寸（越往后越窄），
## 生存模式用 ARENA_SIZE。主题跟着关卡走：挑战模式用本关的地面与四壁，
## 生存模式永远是最初那间青灰墓室。
func _build_arena() -> void:
	var size: Vector2 = _level.arena_size if _level != null else ARENA_SIZE
	_arena = Rect2(-size * 0.5, size)
	_theme = ArenaTheme.for_level(_level)
	_walls = ArenaWalls.new()
	_walls.name = "ArenaWalls"
	_walls.setup(_arena, WALL_THICKNESS, _theme)
	add_child(_walls)


## 把坐标夹进可走区域。radius 是实体半径，保证身体不压进墙里。
## 场地为空（Rect2()）时原样返回 —— 单测/预览场景没有场地也能跑。
func confine_to_arena(pos: Vector2, radius: float) -> Vector2:
	if _arena.size.x <= 0.0 or _arena.size.y <= 0.0:
		return pos
	var margin := Vector2(radius, radius)
	return pos.clamp(_arena.position + margin, _arena.end - margin)


func _physics_process(delta: float) -> void:
	if _state != State.PLAYING or not is_instance_valid(player):
		return
	_elapsed += delta
	# 通关判定放在刷怪之前：到点的那一帧不该再往场上丢一批新怪，
	# 否则玩家会在胜利瞬间被刚出生的怪撞掉血，甚至判成失败。
	if _level != null and _elapsed >= _level.duration:
		_finish(true)
		return
	_tick_spawning(delta)
	_tick_recycle(delta)
	_tick_obstacles(delta)
	_tick_contact_damage()
	_prune_gems()

	_hud_timer += delta
	if _hud_timer >= 0.15:
		_hud_timer = 0.0
		_refresh_hud()


# ---------------------------------------------------------------- 状态切换

func _enter_title() -> void:
	_state = State.TITLE
	if hud != null:
		hud.visible = false
	overlay.show_title(Records.load_best(), _challenge_progress(), _character_brief())
	AudioManager.play_bgm()
	get_tree().paused = true
	_update_pause_button()
	_update_skill_buttons()


## 标题页要显示"你现在用的是谁"，把角色数据压成一份小字典传过去。
func _character_brief() -> Dictionary:
	var data: CharacterData = CharacterData.selected()
	if data == null:
		return {}
	return {
		"name": data.display_name,
		"role": data.role,
		"skill": data.skill_name,
		"skills": data.skill_ladder.size(),
	}


## 统计已通关的关卡数，标题页用来显示挑战进度。
## 逐关读存档（最多八次小文件读），只在标题页发生一次，不值得为它加缓存层。
func _challenge_progress() -> Dictionary:
	var cleared: int = 0
	for level: ChallengeData in ChallengeData.levels():
		if Records.challenge_cleared(level.id):
			cleared += 1
	return {"cleared": cleared, "total": ChallengeData.count()}


func _enter_play() -> void:
	_state = State.PLAYING
	get_tree().paused = false
	if hud != null:
		hud.visible = true
	overlay.hide_overlay()
	AudioManager.play_bgm()
	AudioManager.play("start")
	_refresh_hud()
	_update_pause_button()
	_update_skill_buttons()


func _enter_pause() -> void:
	if _state != State.PLAYING:
		return
	_state = State.PAUSED
	overlay.show_pause()
	get_tree().paused = true
	_update_pause_button()
	_update_skill_buttons()


func _enter_resume() -> void:
	if _state != State.PAUSED:
		return
	_state = State.PLAYING
	get_tree().paused = false
	overlay.hide_overlay()


## 暂停按钮只在「进行中且未暂停」时可见，并贴着右下角摆放。
## 升级面板、暂停、结算期间（整棵树暂停）一律隐藏，避免盖住面板按钮或引发误触。
func _update_pause_button() -> void:
	if pause_button == null or get_tree() == null:
		return
	var want_visible: bool = (_state == State.PLAYING) and not get_tree().paused
	pause_button.visible = want_visible
	if want_visible:
		var view := get_viewport_rect().size
		pause_button.position = Vector2(view.x - 60.0 - 14.0, view.y - 44.0 - 14.0)


## 技能按钮：随解锁动态增加（最多 3 个），横排贴在右下角、暂停按钮上方。
## 和暂停按钮一样，只在对局进行中且未暂停时出现 —— 升级三选一、暂停、结算
## 期间整棵树都暂停，按钮留在屏幕上只会挡住面板。
func _update_skill_buttons() -> void:
	if _action_layer == null or get_tree() == null or not is_instance_valid(player):
		return
	var want_visible: bool = (_state == State.PLAYING) and not get_tree().paused
	var slots: Array[Dictionary] = player.skill_ui()
	# 解锁到几个技能就有几个按钮。按钮建出来就不再销毁，只切可见性。
	while skill_buttons.size() < slots.size():
		_make_skill_button(skill_buttons.size())
	for i in skill_buttons.size():
		var button: Button = skill_buttons[i]
		button.visible = want_visible and i < slots.size()
		if not button.visible:
			continue
		var slot: Dictionary = slots[i]
		var left: float = float(slot.get("remaining", 0.0))
		var state: String = "就绪" if left <= 0.0 else "%.1fs" % left
		button.text = "%d  %s\n%s" % [int(slot.get("key", i + 1)),
				String(slot.get("name", "")), state]
		# 冷却中禁用：既拦住误触，也让"灰掉"本身成为一种进度提示。
		button.disabled = left > 0.0
	if not want_visible or slots.is_empty():
		return
	var view: Vector2 = get_viewport_rect().size
	var width: float = 96.0
	var gap: float = 6.0
	var total_w: float = width * float(slots.size()) + gap * float(slots.size() - 1)
	var x0: float = view.x - total_w - 14.0
	var y: float = view.y - 44.0 - 14.0 - 56.0
	for i in slots.size():
		skill_buttons[i].position = Vector2(x0 + float(i) * (width + gap), y)


## 建一个技能按钮。位置由 _update_skill_buttons 每帧摆，这里只管外观与回调。
func _make_skill_button(index: int) -> void:
	var button := Button.new()
	button.name = "SkillButton%d" % index
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.add_theme_font_size_override("font_size", 12)
	button.add_theme_color_override("font_color", UiStyle.TEXT)
	button.add_theme_stylebox_override("normal",
			UiStyle.button_style(Color(0.10, 0.13, 0.18), UiStyle.BORDER))
	button.add_theme_stylebox_override("hover",
			UiStyle.button_style(Color(0.15, 0.21, 0.28), UiStyle.ACCENT))
	button.add_theme_stylebox_override("pressed",
			UiStyle.button_style(Color(0.19, 0.27, 0.35), UiStyle.ACCENT, 2))
	button.add_theme_stylebox_override("disabled",
			UiStyle.button_style(Color(0.07, 0.08, 0.11), Color(0.20, 0.23, 0.28)))
	button.custom_minimum_size = Vector2(96.0, 48.0)
	button.visible = false
	button.pressed.connect(_on_skill_button_pressed.bind(index))
	_action_layer.add_child(button)
	skill_buttons.append(button)


## 键盘（E / 空格）+ 手机按钮共用的入口。
## index < 0 放出全部已就绪技能；否则只放指定槽位（数字键 / 分键按钮）。
func _cast_skill(index: int = -1) -> void:
	if _state != State.PLAYING or not is_instance_valid(player):
		return
	if not player.cast_skill(index):
		return
	# 技能没有专属音效，借用升级的那声清亮铃音：它够短、够亮，
	# 和"我手上多了一个能用的东西"这件事在情绪上是对的。
	AudioManager.play("levelup")
	_shake = clampf(_shake + 0.45, 0.0, 0.9)


## 技能真的放出去之后的场面反馈。具体伤害由玩家自己结算，这里只管镜头。
func _on_skill_used(kind: int, _at: Vector2) -> void:	if kind == SkillDef.Effect.BOMB:
		_shake = clampf(_shake + 0.55, 0.0, 1.0)


## 升到 Lv5 / Lv10 时解锁新技能。
func _on_skill_unlocked(skill_name: String, _level: int) -> void:
	_queue_toast("新技能解锁 · %s" % skill_name)
	AudioManager.play("levelup")
	_refresh_hud()
	_update_skill_buttons()


## 三个技能齐了之后，每 5 级改为强化已有技能。
func _on_skill_mastered(tier: int, _level: int) -> void:
	_queue_toast("技能强化 ×%d   冷却更短 · 威力更强" % tier)
	AudioManager.play("levelup")
	_refresh_hud()


## 升级面板开着时把提示排队，否则立刻弹。连升多级会把几条合并在一条横幅里。
func _queue_toast(text: String) -> void:
	if _is_leveling or (level_panel != null and level_panel.is_open()):
		_pending_toasts.append(text)
	elif hud != null:
		hud.show_toast(text)


func _on_skill_button_pressed(index: int) -> void:
	_cast_skill(index)


func _on_pause_pressed() -> void:
	_enter_pause()


## 一局的终点。通关与阵亡走同一条收尾流程，只有标题文案、按钮和存档字段不同。
func _finish(cleared: bool) -> void:
	if _state == State.OVER:
		return
	_state = State.OVER
	_pending_level_ups = 0
	_is_leveling = false
	# 通关用上升音而不是死亡音；BGM 同样骤停 —— 和阵亡走一样的收尾节奏，
	# 只是换成「结束得漂亮」的那一个音。
	if cleared:
		AudioManager.stop_bgm()
		AudioManager.play("levelup")
	if level_panel != null:
		level_panel.close()
	_refresh_hud()

	var is_record: bool = false
	var best_time: float = _elapsed
	var has_next: bool = false
	if _level != null:
		is_record = Records.submit_challenge(_level.id, cleared, _elapsed, kills)
		best_time = maxf(float(Records.challenge_record(_level.id)["time"]), _elapsed)
		has_next = cleared and challenge_index + 1 < ChallengeData.count()
	else:
		var previous: Dictionary = Records.load_best()
		is_record = Records.submit(_elapsed, kills, player.level)
		best_time = _elapsed if is_record else float(previous["time"])

	overlay.show_over({
		"time_text": _time_text(),
		"level": player.level,
		"kills": kills,
		"weapon_text": player.weapon_names(),
		"record": is_record,
		"best_time": best_time,
		"cleared": cleared,
		"challenge": _level != null,
		"level_index": challenge_index,
		"level_name": _level.display_name if _level != null else "",
		"has_next": has_next,
	})
	get_tree().paused = true
	_update_pause_button()
	_update_skill_buttons()


func _time_text() -> String:
	return "%02d:%02d" % [int(_elapsed) / 60, int(_elapsed) % 60]


## 重开：先解除暂停再重载场景。暂停状态下重载，新场景的 _ready 会拿不到输入。
## 挑战模式下重开的是同一关，mode 与 challenge_index 是静态变量，会原样带过去。
func _restart() -> void:
	auto_start = true
	get_tree().paused = false
	get_tree().call_deferred("reload_current_scene")


func _back_to_title() -> void:
	auto_start = false
	mode = Mode.ENDLESS
	challenge_index = 0
	get_tree().paused = false
	get_tree().call_deferred("reload_current_scene")


## 结算页的「返回选关」：重载后直接停在选关界面，不再让玩家从标题页多点一次。
func _back_to_select() -> void:
	auto_start = false
	open_select_on_load = true
	challenge_index = 0
	get_tree().paused = false
	get_tree().call_deferred("reload_current_scene")


## 通关后的「下一关」。不改 mode：它本来就该是 CHALLENGE。
func _next_challenge() -> void:
	challenge_index = mini(challenge_index + 1, ChallengeData.count() - 1)
	auto_start = true
	get_tree().paused = false
	get_tree().call_deferred("reload_current_scene")


# ---------------------------------------------------------------- 挑战模式

func _open_challenge_select() -> void:
	if select_panel == null:
		return
	overlay.hide_overlay()
	if hud != null:
		hud.visible = false
	select_panel.open()
	get_tree().paused = true
	_update_pause_button()
	_update_skill_buttons()


## 选关界面确认。不重载场景：此时场上一个敌人、一颗宝石都没有，
## 玩家也是满血满级的新实例，直接把状态机推进到 PLAYING 即可。
func _on_level_chosen(index: int) -> void:
	if select_panel != null:
		select_panel.close()
	_level = ChallengeData.at(index)
	if _level == null:
		return
	mode = Mode.CHALLENGE
	challenge_index = index
	_front_bias = _level.front_bias
	auto_start = true
	_enter_play()
	_refresh_hud()


func _on_select_closed() -> void:
	if select_panel != null:
		select_panel.close()
	_enter_title()


# ---------------------------------------------------------------- 选人

func _open_character_select() -> void:
	if character_panel == null:
		return
	overlay.hide_overlay()
	if hud != null:
		hud.visible = false
	character_panel.open()
	get_tree().paused = true
	_update_pause_button()
	_update_skill_buttons()


## 确认角色。只换人、不重开场景 —— 标题页的玩家实例本来就是满血满级的新实例，
## 直接给它换上新的属性与起手武器即可，避免一次多余的黑屏重载。
func _on_character_chosen(character_id: String) -> void:
	CharacterData.set_current(character_id)
	if is_instance_valid(player):
		player.reset_for_character(CharacterData.selected())
	if character_panel != null:
		character_panel.close()
	_enter_title()


func _on_character_closed() -> void:
	if character_panel != null:
		character_panel.close()
	_enter_title()


# ---------------------------------------------------------------- 刷怪

func _tick_spawning(delta: float) -> void:
	var curve: PackedFloat32Array = difficulty_at(_elapsed)
	var cap: int = mini(int(curve[3]), max_enemies)
	if enemies.size() >= cap:
		return
	_spawn_timer += delta
	if _spawn_timer < curve[2]:
		return
	_spawn_timer = 0.0
	for i in int(curve[4]):
		if enemies.size() >= cap:
			return
		_spawn_enemy(curve[0], curve[1], curve[5], cap)


## 把跑得太远的敌人「回收」到场地内重新投放。
## 同屏上限是稀缺资源，不能被「一直在远处晃」的那批怪白占 —— 否则刷怪器停工，
## 玩家面前空了，压力全堆在身后。回收的起点终点都在视野外，玩家看不到位移。
## 场地收窄后这种情况少了很多（跑不掉），但这套机制仍然负责「把压力送回脸上」。
func _tick_recycle(delta: float) -> void:
	_recycle_timer += delta
	if _recycle_timer < RECYCLE_INTERVAL:
		return
	_recycle_timer = 0.0
	var limit: float = RECYCLE_DISTANCE * RECYCLE_DISTANCE
	for enemy: Enemy in enemies:
		if not is_instance_valid(enemy) or enemy.is_queued_for_deletion():
			continue
		if enemy.global_position.distance_squared_to(player.global_position) <= limit:
			continue
		enemy.global_position = _random_spawn_point()


## 返回该时刻的难度档位：[血量倍率, 移速倍率, 刷怪间隔, 同屏上限, 每批数量, 接触伤害倍率]。
## 挑战模式改由关卡自己的曲线决定，生存模式仍然查 DIFFICULTY_KEYS。
func difficulty_at(seconds: float) -> PackedFloat32Array:
	if _level != null:
		return _level.curve_at(seconds)
	if seconds <= float(DIFFICULTY_KEYS[0][0]):
		return _curve_row(0)
	for i in range(1, DIFFICULTY_KEYS.size()):
		var previous: Array = DIFFICULTY_KEYS[i - 1]
		var current: Array = DIFFICULTY_KEYS[i]
		if seconds > float(current[0]):
			continue
		var span: float = maxf(0.001, float(current[0]) - float(previous[0]))
		var weight: float = (seconds - float(previous[0])) / span
		var result: PackedFloat32Array = PackedFloat32Array()
		for column in range(1, current.size()):
			result.append(lerpf(float(previous[column]), float(current[column]), weight))
		return result
	return _curve_row(DIFFICULTY_KEYS.size() - 1)


func _curve_row(index: int) -> PackedFloat32Array:
	var row: Array = DIFFICULTY_KEYS[index]
	var result: PackedFloat32Array = PackedFloat32Array()
	for column in range(1, row.size()):
		result.append(float(row[column]))
	return result


## 生成一批敌人。具体种类按当前时间加权抽取，抽到什么就整批刷什么 ——
## 每只都独立抽会让屏幕上四种怪均匀混杂，看不出「这一波是蜂群」的层次感。
## cap 是本帧同屏上限，成窝刷的蜂群也要受它约束。
func _spawn_enemy(health_scale: float, speed_scale: float, damage_scale: float, cap: int) -> void:
	var preset: EnemyData = _pick_preset()
	for i in maxi(1, preset.pack_size):
		if enemies.size() >= cap:
			return
		_spawn_one(preset, health_scale, speed_scale, damage_scale)


## 抽一种邪物。两种模式的「谁能出场」规则不同：
## 生存模式按 EnemyData.min_elapsed 随时间解锁，挑战模式由关卡名单写死。
func _pick_preset() -> EnemyData:
	if _level != null:
		return EnemyData.pick_pool(_level.kinds, _elapsed)
	return EnemyData.pick(_elapsed)


func _spawn_one(preset: EnemyData, health_scale: float, speed_scale: float, damage_scale: float) -> void:
	var enemy := Enemy.new()
	# 种类必须在入树前应用：_ready() 会按 radius 建碰撞体，晚了就会用默认半径。
	enemy.apply_data(preset)
	enemy.setup(player, health_scale, speed_scale, damage_scale)
	enemy.arena_rect = _arena
	# 位置必须在入树之前写好。碰撞体是在 _ready() 里建的，先 add_child 再挪位置的话，
	# 物理体有一步会停在原点 —— 而玩家开局就站在原点，这一步会被判成「贴身」，
	# 结果就是站着不动也每两秒掉一次血（实测：开局 16 秒凭空掉光 100 点）。
	var spawn_point: Vector2 = _random_spawn_point()
	enemy.position = spawn_point
	add_child(enemy)
	# 入树后再写一次 global_position：万一主场景本身被移动过，也不会整体偏移。
	enemy.global_position = spawn_point
	enemy.died.connect(_on_enemy_died)
	enemies.append(enemy)


## 取一个合法的刷怪落点（世界坐标）。
## 无限地图时代落点只要在「屏幕外一圈」就行，有了墙之后必须落在场地内 ——
## 否则邪物会站在墙外，或者一出生就被墙夹住。
## 做法：先按边长在视野外一圈取点（和老逻辑一样，保证分布均匀），再夹进场地；
## 评分偏好「没被墙夹过（真的在视野外）> 距离接近视野边缘 > 玩家前方」。
## 场地窄时硬要屏幕外是不可能的，宁可让它在视野边缘冒出来，
## 也绝不能刷在玩家脸上。
func _random_spawn_point() -> Vector2:
	if not is_instance_valid(player):
		return _arena.get_center()
	var target: Vector2 = player.global_position
	# 留出最大那只怪（海猴子半径 22）的身位，别让落点压进墙里。
	var inner: Rect2 = _arena.grow(-26.0)
	var bound := get_viewport_rect().size * 0.5 * spawn_margin + Vector2(48.0, 48.0)
	# 场地越小，能要求的「最小间距」也越小，否则在小场地里会一个合格点都采不到。
	var min_distance: float = minf(spawn_distance, minf(inner.size.x, inner.size.y) * 0.5)
	var ideal_distance: float = bound.length() * 0.85

	var best := Vector2.INF
	var best_score: float = -1.0e9
	var farthest: Vector2 = inner.get_center()
	var farthest_distance: float = -1.0
	for attempt in 24:
		var offset: Vector2 = _edge_offset(bound)
		var raw: Vector2 = target + offset
		var point: Vector2 = raw.clamp(inner.position, inner.end)
		var distance: float = point.distance_to(target)
		if distance > farthest_distance:
			farthest_distance = distance
			farthest = point
		if distance < min_distance:
			continue
		var score: float = 0.0
		# 没被墙夹过 = 真的落在视野外，玩家看不到它凭空出现。
		if point.is_equal_approx(raw):
			score += 2.0
		# 太远会让场上节奏断档（怪从另一头慢慢走过来），太近会当着玩家的面冒出来。
		score -= absf(distance - ideal_distance) / 400.0
		if offset.dot(player.facing) > 0.0:
			score += _front_bias
		if score > best_score:
			best_score = score
			best = point
	# 24 次采样全落在玩家附近（场地极小）时，退而取最远的那一点。
	return farthest if best == Vector2.INF else best


## 在「视野外一圈」的矩形边界上取一个相对玩家的偏移。
## 按边长均匀取点，而不是按角度：按角度取点会让大量怪落在左右两条长边上
## （640 像素外），怪要走十几秒才到；按边长取点，上下两边（388 像素外）
## 会分到相称的比例，玩家跑动时马上就会遭遇。
func _edge_offset(bound: Vector2) -> Vector2:
	var width: float = bound.x * 2.0
	var height: float = bound.y * 2.0
	var roll: float = randf() * (width + height) * 2.0
	if roll < width:
		return Vector2(randf_range(-bound.x, bound.x), -bound.y)      # 上
	if roll < width * 2.0:
		return Vector2(randf_range(-bound.x, bound.x), bound.y)       # 下
	if roll < width * 2.0 + height:
		return Vector2(-bound.x, randf_range(-bound.y, bound.y))      # 左
	return Vector2(bound.x, randf_range(-bound.y, bound.y))           # 右


# ---------------------------------------------------------------- 障碍（仅挑战模式）

## 墓室碎石的周期性生成与回收，只在挑战模式（_level != null）下生效。
## 障碍围绕玩家在屏幕范围内随机隆起，存活一段时间后淡出，避免玩家一路走下去
## 把整个世界堆满石头；同屏上限由关卡决定，超出就回收最老的一块。
func _tick_obstacles(delta: float) -> void:
	if _level == null:
		return
	# 先剔除已销毁的（淡出 self-free 或被越界回收）。
	for i in range(_obstacles.size() - 1, -1, -1):
		if not is_instance_valid(_obstacles[i]):
			_obstacles.remove_at(i)
	_obstacle_timer += delta
	if _obstacle_timer < _level.obstacle_interval:
		return
	_obstacle_timer = 0.0
	for n in _level.obstacle_batch:
		_spawn_obstacle()
	while _obstacles.size() > _level.obstacle_max:
		var oldest := _obstacles[0]
		_obstacles.remove_at(0)
		if is_instance_valid(oldest):
			oldest.queue_free()


## 在玩家周围一圈随机取点生成一块碎石，避开玩家与已有碎石的重叠。
## 取点环 [280, 560] 像素：小于视口半高，基本落在屏内，玩家「看得到才绕得开」；
## 又远大于玩家自身，不会一出生就把人卡死。
func _spawn_obstacle() -> void:
	if not is_instance_valid(player):
		return
	var center: Vector2 = player.global_position
	var radius: float = _level.obstacle_radius * randf_range(0.75, 1.25)
	for attempt in 10:
		var angle: float = randf() * TAU
		var dist: float = randf_range(280.0, 560.0)
		var pos := center + Vector2(cos(angle), sin(angle)) * dist
		# 墙边不放石头：一半的落点会被挡在场地外，剩下的也会紧贴墙根，
		# 变成「墙角 + 碎石」的死角 —— 玩家被逼进去就真的出不来了。
		if not _arena.grow(-(radius + 14.0)).has_point(pos):
			continue
		if _obstacle_overlaps(pos, radius):
			continue
		var obstacle := Obstacle.new()
		obstacle.setup(radius, _level.obstacle_lifetime, randf())
		# 碎石材质跟关走：冰关是冰块、铜关是铜片 —— 障碍物也是场景的一部分。
		obstacle.set_palette(_theme.rock_base, _theme.rock_light, _theme.rock_dark)
		obstacle.global_position = pos
		add_child(obstacle)
		_obstacles.append(obstacle)
		return


## 候选点是否与现有碎石重叠（含一点余量，避免两块贴成一块）。
func _obstacle_overlaps(pos: Vector2, radius: float) -> bool:
	for existing: Obstacle in _obstacles:
		if not is_instance_valid(existing):
			continue
		if pos.distance_to(existing.global_position) < radius + existing.radius + 10.0:
			return true
	return false


## 把玩家的「期望位置」推出所有障碍圆，作为走位限制的解算入口。
## 多趟迭代：单次推出可能又落进另一块石头，两趟基本能解干净。
func _resolve_obstacle_collision(pos: Vector2, body_radius: float) -> Vector2:
	if _obstacles.is_empty():
		return pos
	var out := pos
	for p in 2:
		for obstacle: Obstacle in _obstacles:
			if not is_instance_valid(obstacle):
				continue
			var offset: Vector2 = out - obstacle.global_position
			var min_distance: float = obstacle.radius + body_radius
			var d2: float = offset.length_squared()
			if d2 >= min_distance * min_distance:
				continue
			if d2 < 0.0001:
				# 完全同心（极少见）：朝远离玩家的方向顶开。
				offset = (out - player.global_position).normalized()
				if offset.length_squared() < 0.0001:
					offset = Vector2.RIGHT
			out = obstacle.global_position + offset.normalized() * min_distance
	return out


# ---------------------------------------------------------------- 战斗结算

func _tick_contact_damage() -> void:
	# 累加所有贴身敌人的伤害后再结算一次：被 10 只围住就该掉 10 份血。
	# 早期版本命中一只就 return，等于「围殴」永远只算 1 份伤害，
	# 站桩不动反而比走位更安全，难度曲线因此完全失效。
	# 重叠检测交给玩家的 Area2D，敌人数量上百时不再逐对求距离。
	var damage: float = 0.0
	var contacts: Array[Enemy] = player.get_contact_enemies()
	for enemy: Enemy in contacts:
		damage += enemy.contact_damage
	if damage > 0.0:
		player.take_contact_damage(damage)


func _prune_gems() -> void:
	for i in range(gems.size() - 1, -1, -1):
		if not is_instance_valid(gems[i]):
			gems.remove_at(i)


func _on_enemy_died(enemy: Enemy) -> void:
	enemies.erase(enemy)
	kills += 1
	AudioManager.play("kill")
	_spawn_burst(enemy.global_position, enemy.body_color, enemy.radius)
	# 宝石价值跟随敌人血量：血越厚的怪给的经验越多，保证「击杀耗时 ↑」时
	# 单位时间经验产出大致不变。用对数而不是线性——线性会让后期经验爆炸。
	# 基准：10 血 = 1 经验，50 血 = 1，200 血 = 3，1000 血 = 5。
	var gem_value: int = maxi(1, int(roundf(log(1.0 + enemy.max_health / 30.0) / log(2.0))))
	_drop_gem(enemy.global_position, gem_value)


func _spawn_burst(at: Vector2, color: Color, radius: float) -> void:
	# 击杀密集时无上限地生成会瞬间堆出上百个短命节点，直接掐掉帧。
	if get_tree().get_nodes_in_group("death_bursts").size() >= MAX_BURSTS:
		return
	var burst := DeathBurst.new()
	burst.color = color
	burst.start_radius = radius * 0.7
	burst.end_radius = radius * 2.2
	burst.position = at
	burst.add_to_group("death_bursts")
	add_child(burst)


func _drop_gem(at: Vector2, value: int) -> void:
	var gem := XpGem.new()
	gem.position = at
	add_child(gem)
	gem.setup(player, value)
	gem.collected.connect(_on_gem_collected)
	gems.append(gem)


func _on_gem_collected(amount: int) -> void:
	# 拾取声限流 40ms：一次连捡十几颗宝石时，逐个播会糊成一片「哔」。
	AudioManager.play("pickup")
	if is_instance_valid(player):
		player.add_xp(amount)


# ---------------------------------------------------------------- 玩家与 UI

func _spawn_player() -> void:
	player = Player.new()
	# 角色必须在入树之前注入：_ready() 会按 max_health 初始化血量、
	# 按 starting_weapon 装配起手武器，晚一步就会用默认值。
	player.apply_character(CharacterData.selected())
	player.position = Vector2.ZERO
	add_child(player)
	# 注入障碍解算：玩家是纯 Node2D，没有物理体，走位限制靠 Game 手动把坐标推出碎石圆。
	player.obstacle_query = _resolve_obstacle_collision
	# 场地边界同理：玩家没有物理体，撞墙只能靠坐标夹制。
	player.arena_rect = _arena
	player.health_changed.connect(_on_health_changed)
	player.xp_changed.connect(_on_xp_changed)
	player.leveled_up.connect(_on_player_leveled_up)
	player.weapon_added.connect(_on_weapon_added)
	player.weapon_upgraded.connect(_on_weapon_added)
	player.hurt.connect(_on_player_hurt)
	player.skill_used.connect(_on_skill_used)
	player.skill_unlocked.connect(_on_skill_unlocked)
	player.skill_mastered.connect(_on_skill_mastered)
	player.died.connect(_on_player_died)

	_camera = Camera2D.new()
	_camera.position_smoothing_enabled = true
	_camera.position_smoothing_speed = 8.0
	# 相机被夹在场地外一圈：越界的这点余量刚好够把墙带露出来，再多就是黑洞。
	# 没有这一步的话，相机跟着玩家一路飘到墙外，玩家会以为游戏卡住了。
	_camera.limit_left = int(_arena.position.x - CAMERA_MARGIN)
	_camera.limit_top = int(_arena.position.y - CAMERA_MARGIN)
	_camera.limit_right = int(_arena.end.x + CAMERA_MARGIN)
	_camera.limit_bottom = int(_arena.end.y + CAMERA_MARGIN)
	player.add_child(_camera)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	hud = Hud.new()
	layer.add_child(hud)

	overlay = GameOverlay.new()
	add_child(overlay)
	overlay.start_requested.connect(_enter_play)
	overlay.resume_requested.connect(_enter_resume)
	overlay.restart_requested.connect(_restart)
	overlay.title_requested.connect(_back_to_title)
	overlay.challenge_requested.connect(_open_challenge_select)
	overlay.characters_requested.connect(_open_character_select)
	overlay.next_requested.connect(_next_challenge)
	overlay.select_requested.connect(_back_to_select)

	# 选关界面单独一层 CanvasLayer：它必须盖住 HUD 与结算面板，
	# 而 GameOverlay 自己就是 CanvasLayer，挂不到它下面。
	var select_layer := CanvasLayer.new()
	select_layer.layer = 30
	add_child(select_layer)
	select_panel = ChallengeSelect.new()
	select_layer.add_child(select_panel)
	select_panel.level_chosen.connect(_on_level_chosen)
	select_panel.closed.connect(_on_select_closed)

	# 选人界面比选关更高一层：从标题页进来时可能正停在选关界面上（返回过一局），
	# 两层同时可见会互相盖字，所以固定从上面压住。
	var character_layer := CanvasLayer.new()
	character_layer.layer = 32
	add_child(character_layer)
	character_panel = CharacterSelect.new()
	character_layer.add_child(character_panel)
	character_panel.character_chosen.connect(_on_character_chosen)
	character_panel.closed.connect(_on_character_closed)

	# 触屏摇杆：独立一层（layer 6），盖在 HUD 之上、覆盖层之下。
	# 只在触摸设备启用 —— 桌面端禁用后保持隐藏，纯键盘玩法不受影响。
	var joy_layer := CanvasLayer.new()
	joy_layer.layer = 6
	add_child(joy_layer)
	joystick = TouchJoystick.new()
	joy_layer.add_child(joystick)
	joystick.set_enabled(OS.has_feature("touchscreen"))
	if player != null:
		player.joystick = joystick

	# 右下角暂停按钮。桌面端也会显示，作为 ESC 的可见替代；移动端则是唯一入口。
	var pause_layer := CanvasLayer.new()
	pause_layer.layer = 7
	add_child(pause_layer)
	# 技能按钮会随等级解锁动态加进来，得留住这一层的引用。
	_action_layer = pause_layer
	var pause_btn := Button.new()
	pause_btn.name = "PauseButton"
	pause_btn.text = "暂停"
	pause_btn.focus_mode = Control.FOCUS_NONE
	pause_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	pause_btn.add_theme_font_size_override("font_size", 16)
	pause_btn.add_theme_color_override("font_color", UiStyle.TEXT)
	pause_btn.add_theme_stylebox_override("normal",
			UiStyle.button_style(Color(0.11, 0.14, 0.19), UiStyle.BORDER))
	pause_btn.add_theme_stylebox_override("hover",
			UiStyle.button_style(Color(0.15, 0.21, 0.28), UiStyle.ACCENT))
	pause_btn.add_theme_stylebox_override("pressed",
			UiStyle.button_style(Color(0.19, 0.27, 0.35), UiStyle.ACCENT, 2))
	pause_btn.custom_minimum_size = Vector2(60.0, 44.0)
	pause_btn.visible = false
	pause_btn.pressed.connect(_on_pause_pressed)
	pause_layer.add_child(pause_btn)
	pause_button = pause_btn


func _build_level_panel() -> void:
	level_panel = LevelUpPanel.new()
	add_child(level_panel)
	level_panel.upgrade_chosen.connect(_on_upgrade_chosen)


func _refresh_hud() -> void:
	if hud == null or not is_instance_valid(player):
		return
	hud.level = player.level
	hud.health = player.health
	hud.max_health = player.max_health
	hud.xp = player.xp
	hud.xp_next = player.xp_to_next
	hud.kills = kills
	hud.elapsed = _elapsed
	hud.enemy_count = enemies.size()
	# 挑战模式下 HUD 顶部多一行关卡名与倒计时，生存模式传空值让 HUD 跳过绘制。
	if _level != null:
		hud.challenge_name = _level.display_name
		hud.challenge_remaining = maxf(0.0, _level.duration - _elapsed)
		hud.challenge_progress = clampf(_elapsed / maxf(1.0, _level.duration), 0.0, 1.0)
	else:
		hud.challenge_name = ""
		hud.challenge_remaining = -1.0
		hud.challenge_progress = -1.0
	hud.weapon_lines.clear()
	for weapon: Weapon in player.weapons:
		hud.weapon_lines.append("%s   Lv%d" % [weapon.display_name(), weapon.level])

	# 角色信息：HUD 左下角的名字与技能栏都从这里取，避免 HUD 反向依赖玩家节点。
	if player.character != null:
		hud.character_name = player.character.display_name
	else:
		hud.character_name = ""
	hud.skill_slots = player.skill_ui()
	hud.skill_mastery = player.skill_mastery
	# 手机窄屏上，底部那一排实体技能按钮已经把冷却讲清楚了，
	# 再画一排居中的技能格只会和它挤在一起 —— 触屏设备只保留按钮。
	hud.show_skill_chips = not GameOverlay.is_touch_device()


func _on_health_changed(_current: float, _maximum: float) -> void:
	_refresh_hud()


func _on_xp_changed(_current: int, _needed: int) -> void:
	_refresh_hud()


func _on_weapon_added(_weapon: Weapon) -> void:
	_refresh_hud()


func _on_player_hurt(amount: float) -> void:
	# 震屏强度跟着单次伤害走：被蜂群蹭一下只轻微一晃，被巨盾兵撞一下明显一震。
	_shake = clampf(_shake + 0.18 + amount * 0.012, 0.0, 0.85)
	AudioManager.play("hurt")
	if hud != null:
		hud.flash_hurt()


func _tick_shake(delta: float) -> void:
	if _camera == null or not is_instance_valid(_camera):
		return
	if _shake > 0.0:
		_shake = maxf(0.0, _shake - delta * 2.4)
		var amount: float = _shake * _shake * 20.0
		_camera.offset = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * amount
	elif _camera.offset != Vector2.ZERO:
		# 平滑回零：直接把 offset 归零会在最后一帧留下可见的跳变。
		_camera.offset = _camera.offset.lerp(Vector2.ZERO, minf(1.0, 16.0 * delta))


func _on_player_leveled_up(_level: int) -> void:
	_pending_level_ups += 1
	if not _is_leveling:
		_show_next_level_up()


## 一次只弹一个面板；连升多级时排队，选定后继续弹下一个。
## 奖励池为空或玩家已死亡时丢弃队列并恢复时间流动，避免卡在暂停态。
func _show_next_level_up() -> void:
	if _state == State.OVER or _pending_level_ups <= 0 or not is_instance_valid(player):
		_pending_level_ups = 0
		return
	if _is_leveling or level_panel.is_open():
		return

	var options: Array[Dictionary] = Upgrades.pick_random(upgrade_choices, player)
	if options.is_empty():
		_pending_level_ups = 0
		_resume_from_level_up()
		return

	_pending_level_ups -= 1
	_is_leveling = true
	# 升级音效只在成功弹出面板时播放：奖励池为空直接跳过的分支不该响。
	AudioManager.play("levelup")
	if not get_tree().paused:
		_paused_by_level_up = true
		get_tree().paused = true
	# 面板一开，右下角的暂停 / 技能按钮就该收起来：整棵树暂停后
	# _process 不再跑，没人会自动把它们隐藏。
	_update_pause_button()
	_update_skill_buttons()
	level_panel.show_options(options)


## 选择回调。重复或延迟到达的调用会被 _is_leveling 拦下，奖励只发一次。
func _on_upgrade_chosen(id: String) -> void:
	if not _is_leveling:
		push_warning("Game: 收到非升级期的选择「%s」，已忽略" % id)
		return
	_is_leveling = false
	Upgrades.apply(id, player)

	if _pending_level_ups > 0 and _state != State.OVER:
		_show_next_level_up()
	else:
		_resume_from_level_up()
	_refresh_hud()


## 只解除自己造成的暂停，避免误清的其它系统暂停状态。
func _resume_from_level_up() -> void:
	if _paused_by_level_up:
		_paused_by_level_up = false
		if _state != State.OVER and _state != State.PAUSED:
			get_tree().paused = false
	# 解锁 / 强化提示正好发生在升级那一刻，此时三选一面板还开着。
	# 攒到面板收起后再弹，玩家才看得见，也不会盖住选项。
	if not _pending_toasts.is_empty() and hud != null:
		hud.show_toast("  ·  ".join(_pending_toasts), 3.2)
		_pending_toasts.clear()
	_update_skill_buttons()


## 场景销毁时兜底解除暂停，防止退出后残留 paused 状态。
## 注意不要在这里停 BGM：音乐归 Autoload 管，重开一局时场景会先销毁再重建，
## 在这里停会让每次重开都把音乐打回 0 秒，听感像"卡了一下"。
func _exit_tree() -> void:
	var tree: SceneTree = get_tree()
	if tree != null:
		tree.paused = false


func _on_player_died() -> void:
	# 死亡瞬间可能还压着升级面板的暂停，先把它收掉再进结算，
	# 否则暂停标志会残留，结算界面按什么都点不动。
	_paused_by_level_up = false
	if level_panel != null:
		level_panel.close()
	# 音乐直接停而不是淡出：淡出要靠 Tween，而紧接着 paused 就会把 Tween 冻住，
	# 结果停在半大声的音量上。骤停配合下降的死亡音效反而更有"结束"感。
	AudioManager.stop_bgm()
	AudioManager.play("gameover")
	_finish(false)


func _unhandled_input(event: InputEvent) -> void:
	if _state != State.PLAYING or get_tree().paused:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_enter_pause()
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	# E 与空格放「所有已就绪技能」：单键玩法不变，解锁了新技能自然一起放出去。
	# 数字键 1~3 则单独放指定技能，方便把回血 / 减伤留到关键时刻。
	if key.keycode == KEY_E or key.keycode == KEY_SPACE:
		get_viewport().set_input_as_handled()
		_cast_skill()
	elif key.keycode >= KEY_1 and key.keycode <= KEY_3:
		get_viewport().set_input_as_handled()
		_cast_skill(key.keycode - KEY_1)


## 只在贴图缺失时兜底画纯色网格，正常情况下底面由 Floor 精灵负责。
func _draw() -> void:
	if _floor != null:
		return
	var extent: float = 2400.0
	var step: float = 64.0
	draw_rect(Rect2(-extent, -extent, extent * 2.0, extent * 2.0), Color(0.09, 0.10, 0.14))
	var offset: float = -extent
	while offset <= extent:
		draw_line(Vector2(offset, -extent), Vector2(offset, extent), Color(0.15, 0.17, 0.22), 1.0)
		draw_line(Vector2(-extent, offset), Vector2(extent, offset), Color(0.15, 0.17, 0.22), 1.0)
		offset += step
