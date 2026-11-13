# 敌人：朝目标追击，受击掉血并后仰，血量归零时发出 died 并自我销毁。
#
# 用 CharacterBody2D 而不是 Node2D：敌人之间靠物理层互相碰撞，被后面顶住就沿切线
# 滑开，自然挤成一道肉墙而不是叠成一坨。玩家不参与物理（仍是 Node2D），靠
# _keep_outside_target() 的软阻挡把敌人顶在身体外面 —— 硬阻挡会让玩家被怪卡死，
# 软阻挡则保证玩家永远推得动、也永远不会被穿模。
class_name Enemy
extends CharacterBody2D

## 血量归零时发出，携带自身引用供生成器从活跃列表中移除。
signal died(enemy: Enemy)

## 击退速度的衰减率（像素/秒²）。140 初速约 0.16 秒衰减干净，位移约 11 像素。
const KNOCKBACK_DECAY: float = 900.0
## 击退速度上限，防止密集命中把怪打飞出屏幕。
const KNOCKBACK_MAX: float = 420.0
## 「后面挤前面」的推力（像素/秒）。只单向施加，双向会变成两只怪互顶抖动。
const PUSH_SPEED: float = 900.0
const PUSH_MAX: float = 140.0
const PUSH_DECAY: float = 700.0
## 受击闪白时长。
const FLASH_TIME: float = 0.12

# ---------------------------------------------------------------- 邪物配色
#
# 主色来自 EnemyData.body_color（死亡粒子也用它），下面这些是各造型内部
# 固定用来点睛的颜色。整屏都是冷灰的尸青色，所以每个种类的辨识度都要靠
# 一小块高饱和的「记号色」：粽子的黄符、鸡冠蛇的红冠、海猴子的獠牙、
# 尸蟞的甲壳高光。没有这块记号色，两百只怪挤在一起就只剩一片灰。

const PAPER: Color = Color(0.93, 0.80, 0.34)      ## 黄符纸
const PAPER_INK: Color = Color(0.72, 0.22, 0.20)  ## 符上的朱砂
const EYE_RED: Color = Color(0.92, 0.26, 0.22)    ## 粽子的尸眼
const COMB: Color = Color(0.88, 0.20, 0.24)       ## 鸡冠蛇的冠
const EYE_YELLOW: Color = Color(1.0, 0.86, 0.34)  ## 蛇与海猴子的眼
const FANG: Color = Color(0.94, 0.92, 0.84)       ## 獠牙与爪
const SHADOW: Color = Color(0.0, 0.0, 0.0, 0.24)

@export var max_health: float = 10.0
@export var move_speed: float = 70.0
@export var contact_damage: float = 6.0
@export var radius: float = 13.0
@export var body_color: Color = Color(0.58, 0.66, 0.60)
@export var kind: EnemyData.Kind = EnemyData.Kind.ZOMBIE
@export var knockback_resist: float = 1.0

## 所属种类，供上层查询 id / 名称。
var data: EnemyData = null
## 场地边界，由生成器注入。为空矩形时不限制（单测场景）。
## 墙不是物理体（一整圈无限长的边，拼 StaticBody2D 要几十段），
## 所以撞墙靠每帧把坐标夹回来。
var arena_rect: Rect2 = Rect2()

var _health: float = 0.0
var _target: Node2D = null
var _knockback: Vector2 = Vector2.ZERO
var _push: Vector2 = Vector2.ZERO
var _flash: float = 0.0

# 未经难度缩放的原始数值。setup() 可能被调用多次，必须从基础值重算而不是自乘。
var _base_health: float = 10.0
var _base_speed: float = 70.0
var _base_damage: float = 6.0

var _shape_node: CollisionShape2D = null


func _ready() -> void:
	_health = max_health
	add_to_group("enemies")
	# 俯视视角：不受重力、不需要上下方向，各方向等速移动。
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	# 敌人既要彼此挤成肉墙，也要被墓室碎石挡住去路（障碍层）。
	collision_layer = PhysicsLayers.ENEMY
	collision_mask = PhysicsLayers.ENEMY | PhysicsLayers.OBSTACLE
	_build_collision()
	queue_redraw()


## 应用种类预设。必须在 add_child() 之前调用，否则碰撞半径会按默认值建立。
func apply_data(source: EnemyData) -> void:
	if source == null:
		return
	data = source
	kind = source.kind
	body_color = source.body_color
	radius = source.radius
	knockback_resist = source.knockback_resist
	_base_health = source.max_health
	_base_speed = source.move_speed
	_base_damage = source.contact_damage
	max_health = _base_health
	move_speed = _base_speed
	contact_damage = _base_damage
	_health = _base_health
	# 已入树（重复应用）时就地更新碰撞半径，避免碰撞与外观对不上。
	if _shape_node != null and _shape_node.shape is CircleShape2D:
		(_shape_node.shape as CircleShape2D).radius = radius


## 由生成器在 add_child 之后调用，注入追击目标与难度成长倍率。
## 接触伤害也随难度成长，否则后期只有血量在涨、威胁感不变。
func setup(target: Node2D, health_scale: float, speed_scale: float, damage_scale: float = 1.0) -> void:
	_target = target
	max_health = _base_health * health_scale
	move_speed = _base_speed * speed_scale
	contact_damage = _base_damage * damage_scale
	_health = max_health


func _build_collision() -> void:
	var circle := CircleShape2D.new()
	circle.radius = radius
	_shape_node = CollisionShape2D.new()
	_shape_node.shape = circle
	add_child(_shape_node)


func _physics_process(delta: float) -> void:
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta)
		# 用 modulate 而不是「改颜色 + queue_redraw」来表现闪白：
		# 上百只怪同时挨打时，每帧逐个重绘是纯粹的浪费，而 modulate 只在
		# 渲染阶段乘一下，不触发任何重绘。
		if _flash > 0.0:
			var t: float = _flash / FLASH_TIME
			modulate = Color(1.0 + 0.9 * t, 1.0 + 0.7 * t, 1.0 + 0.7 * t)
		else:
			modulate = Color.WHITE

	var chase: Vector2 = Vector2.ZERO
	if is_instance_valid(_target):
		var to_target: Vector2 = _target.global_position - global_position
		if to_target.length_squared() > 1.0:
			chase = to_target.normalized() * move_speed
	# 刻意不做朝向旋转：这四种邪物都是正面朝镜头的站姿，转过身后血条会
	# 跟着歪，玩家反而读不出剩余血量。方向感交给眼睛和身形倾斜。

	velocity = chase + _knockback + _push
	move_and_slide()

	if is_instance_valid(_target):
		_push_front_enemies(delta)
		_keep_outside_target()

	_confine_to_arena()

	_knockback = _knockback.move_toward(Vector2.ZERO, KNOCKBACK_DECAY * delta)
	_push = _push.move_toward(Vector2.ZERO, PUSH_DECAY * delta)


## 夹进场地。放在所有位移之后：_keep_outside_target 会把自己从玩家身上推开，
## 玩家贴着墙时那一下足以把怪推进墙里。
func _confine_to_arena() -> void:
	if arena_rect.size.x <= 0.0 or arena_rect.size.y <= 0.0:
		return
	var margin := Vector2(radius, radius)
	global_position = global_position.clamp(arena_rect.position + margin, arena_rect.end - margin)


## 被击退：方向为「从攻击点指向自己」。
## knockback_resist 是倍率而非除数：越重的怪倍率越小，同样的冲击推不动它。
## （早期版本写成 force / resist，结果巨盾兵的抗性 0.32 变成了「被推 3 倍远」，
## 和「重甲推不动」的设定完全相反。）
func apply_knockback(direction: Vector2, force: float) -> void:
	if _health <= 0.0 or force <= 0.0:
		return
	if direction.length_squared() < 0.0001:
		return
	var resist: float = clampf(knockback_resist, 0.0, 3.0)
	_knockback += direction.normalized() * (force * resist)
	if _knockback.length() > KNOCKBACK_MAX:
		_knockback = _knockback.normalized() * KNOCKBACK_MAX


## 被后面的同伴顶一下。仅内部使用 —— 由物理碰撞结果驱动，不对外暴露成攻击。
func add_push(impulse: Vector2) -> void:
	_push += impulse
	if _push.length() > PUSH_MAX:
		_push = _push.normalized() * PUSH_MAX


func take_damage(amount: float) -> void:
	if _health <= 0.0:
		return
	_health -= amount
	_flash = FLASH_TIME
	queue_redraw()
	if _health <= 0.0:
		died.emit(self)
		queue_free()


func get_health_ratio() -> float:
	return clampf(_health / maxf(max_health, 1.0), 0.0, 1.0)


## 把挡在前面的同伴往前挤：只推「比自己更靠近玩家」的那只。
## 双向施加会让两只怪互相顶住原地抖动，单向传导才会形成往前涌的挤压感。
func _push_front_enemies(delta: float) -> void:
	if get_slide_collision_count() <= 0:
		return
	var my_distance: float = global_position.distance_squared_to(_target.global_position)
	for i in get_slide_collision_count():
		var collision: KinematicCollision2D = get_slide_collision(i)
		if collision == null:
			continue
		var other := collision.get_collider() as Enemy
		if other == null or other == self or not is_instance_valid(other):
			continue
		if other.global_position.distance_squared_to(_target.global_position) >= my_distance:
			continue
		var direction: Vector2 = -collision.get_normal()
		if direction.length_squared() < 0.0001:
			continue
		other.add_push(direction.normalized() * PUSH_SPEED * delta)


## 软阻挡：不允许敌人圆心进入「自身半径 + 玩家半径」之内。
## 玩家不是物理体，所以这里只做几何修正，不用物理引擎推 —— 否则玩家高速位移
## 会把重叠的敌人弹飞。推到边界而不是插值，玩家冲刺时才不会拖着怪走。
func _keep_outside_target() -> void:
	if not is_instance_valid(_target):
		return
	var target_radius: float = 15.0
	var player := _target as Player
	if player != null:
		target_radius = player.radius
	var offset: Vector2 = global_position - _target.global_position
	var min_distance: float = radius + target_radius
	if offset.length_squared() >= min_distance * min_distance:
		return
	if offset.length_squared() < 0.0001:
		offset = Vector2.RIGHT
	global_position = _target.global_position + offset.normalized() * min_distance


# ---------------------------------------------------------------- 绘制
#
# 造型全部程序化绘制，理由和玩家一样：受击闪白走 modulate（不触发重绘），
# 只有掉血才 queue_redraw，所以每个敌人的绘制指令只在出生和掉血时重建一次，
# 每帧只是把这批指令重放出去。同屏两百只时真正贵的是 item 数量，不是
# 单个 item 里的图元数量，所以这里可以放心画十几笔。
#
# 所有坐标都以 radius 为单位（见 _v()），调半径时整套造型等比缩放，
# 不会出现「换了体型，眼睛还留在原处」的错位。
#
# 造型的第一目标是「轮廓可分」而不是「细节可信」：这四种怪在屏幕上只有
# 16~55 像素，玩家根本没机会看清爪子和鳞片。所以刻意把四种轮廓做成
# 瘦长人形 / 盘曲细颈 / 宽胖壮汉 / 扁圆甲虫，让剪影本身就互不相似。

func _draw() -> void:
	# 小体型的两只（蛇 r=10、尸蟞 r=8）在实机里只剩一个色点，造型全糊。
	# 视觉上放大两成不改碰撞半径：判定保持原样，纯粹让它们更容易被看见。
	var s: float = _art_scale()
	if not is_equal_approx(s, 1.0):
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(s, s))
	match kind:
		EnemyData.Kind.SNAKE:
			_draw_snake()
		EnemyData.Kind.APE:
			_draw_ape()
		EnemyData.Kind.BEETLE:
			_draw_beetle()
		_:
			_draw_zombie()
	_draw_health_ring()
	if not is_equal_approx(s, 1.0):
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 视觉放大系数。只为可读性服务，不参与任何物理计算。
func _art_scale() -> float:
	match kind:
		EnemyData.Kind.SNAKE:
			return 1.20
		EnemyData.Kind.BEETLE:
			return 1.24
		_:
			return 1.0


## 粽子：瘦长的人形尸体，额前一张黄符。
## 轮廓刻意做得窄而高 —— 海猴子是宽胖的，两者并排时剪影差得越远越好。
func _draw_zombie() -> void:
	var body: Color = body_color
	var cloth: Color = _shade(body, 0.90)
	var skin: Color = _shade(body, 1.14)
	var dark: Color = _shade(body, 0.52)

	_ground_shadow(0.56, 0.20, 1.00)

	# 两条僵直的腿
	draw_rect(Rect2(_v(-0.34, 0.54), _v(0.26, 0.46)), dark)
	draw_rect(Rect2(_v(0.08, 0.54), _v(0.26, 0.46)), dark)

	# 寿衣：窄长的圆角筒
	draw_colored_polygon(_rounded(_v(-0.42, -0.18), _v(0.84, 0.86), radius * 0.18), cloth)
	# 下摆压暗，把身体和腿分开
	draw_rect(Rect2(_v(-0.42, 0.50), _v(0.84, 0.12)), dark)

	# 双臂垂在体侧、略微外张。僵尸的僵直感全在这两条不弯的直臂上
	draw_colored_polygon(_rounded(_v(-0.62, -0.14), _v(0.22, 0.64), radius * 0.11), skin)
	draw_colored_polygon(_rounded(_v(0.40, -0.14), _v(0.22, 0.64), radius * 0.11), skin)

	# 头：比身体宽，Q 版比例
	draw_circle(_v(0.0, -0.72), radius * 0.62, skin)
	# 头发只盖住头顶那一小块弓形（PI*1.12 ~ PI*1.88），
	# 画成整半圆会把眼睛扣在头发里，看着像戴了顶黑帽子。
	draw_colored_polygon(
			_cap_points(_v(0.0, -0.72), radius * 0.63, PI * 1.12, PI * 1.88, 14),
			_shade(body, 0.38))

	# 黄符：竖着贴在额头上，从发际垂到眉眼之间
	draw_rect(Rect2(_v(-0.15, -1.24), _v(0.30, 0.40)), PAPER)
	draw_line(_v(-0.05, -1.16), _v(-0.05, -0.92), PAPER_INK, maxf(1.0, radius * 0.05))
	draw_line(_v(0.05, -1.16), _v(0.05, -0.92), PAPER_INK, maxf(1.0, radius * 0.05))

	# 尸眼：两点暗红，不画高光 —— 有高光就成活人了
	draw_circle(_v(-0.26, -0.72), radius * 0.10, EYE_RED)
	draw_circle(_v(0.26, -0.72), radius * 0.10, EYE_RED)
	draw_line(_v(-0.15, -0.48), _v(0.15, -0.48), dark, maxf(1.0, radius * 0.07))


## 鸡冠蛇：盘着身子、颈子竖直抬起来的警戒姿态。
## 红冠是记号色 —— 一片绿里那点红就是「这只有毒，别贴脸」的提示。
func _draw_snake() -> void:
	var body: Color = body_color
	var dark: Color = _shade(body, 0.62)
	var light: Color = _shade(body, 1.18)

	_ground_shadow(0.62, 0.18, 0.72)

	# 盘在底下的身躯
	_ellipse(_v(0.0, 0.34), radius * 0.72, radius * 0.34, body)
	# 两道腹纹，暗示蛇身是绕了几圈的
	draw_arc(_v(0.0, 0.34), radius * 0.50, 0.40, PI - 0.40, 10, dark,
			maxf(1.0, radius * 0.08), true)
	draw_arc(_v(0.0, 0.37), radius * 0.32, 0.55, PI - 0.55, 8, dark,
			maxf(1.0, radius * 0.07), true)

	# 竖起的颈。必须细 —— 颈一粗、头一小，整体就成了个绿花瓶。
	draw_colored_polygon(_poly([
		[-0.23, 0.18], [0.23, 0.18], [0.15, -0.52], [-0.15, -0.52],
	]), body)

	# 头：比颈宽出一倍，「头颈差」才是蛇的辨识点
	_ellipse(_v(0.0, -0.66), radius * 0.52, radius * 0.34, light)

	# 鸡冠：三根尖，中间最高
	draw_colored_polygon(_poly([
		[-0.36, -0.82], [-0.26, -1.12], [-0.11, -0.86],
		[0.02, -1.20], [0.14, -0.86], [0.27, -1.12], [0.36, -0.82],
	]), COMB)

	# 蛇眼：横向细长的黄点，比圆眼冷
	_ellipse(_v(-0.22, -0.70), radius * 0.10, radius * 0.07, EYE_YELLOW)
	_ellipse(_v(0.22, -0.70), radius * 0.10, radius * 0.07, EYE_YELLOW)
	draw_line(_v(-0.10, -0.50), _v(0.10, -0.50), dark, maxf(1.0, radius * 0.07))


## 海猴子：宽肩、长臂过膝的半人半兽。
## 体型本身就是威胁信息 —— 玩家隔老远就该决定绕开还是集火。
func _draw_ape() -> void:
	var body: Color = body_color
	var dark: Color = _shade(body, 0.66)
	var light: Color = _shade(body, 1.14)

	_ground_shadow(0.80, 0.26, 1.02)

	# 短粗腿
	draw_rect(Rect2(_v(-0.44, 0.52), _v(0.34, 0.50)), dark)
	draw_rect(Rect2(_v(0.10, 0.52), _v(0.34, 0.50)), dark)

	# 宽胖躯干：横向拉得比粽子宽一半，剪影一眼可分
	_ellipse(_v(0.0, -0.04), radius * 0.78, radius * 0.66, body)

	# 垂到地面的长臂
	draw_colored_polygon(_rounded(_v(-0.96, -0.44), _v(0.28, 1.04), radius * 0.13),
			_shade(body, 0.78))
	draw_colored_polygon(_rounded(_v(0.68, -0.44), _v(0.28, 1.04), radius * 0.13),
			_shade(body, 0.78))
	# 爪：每只手三根向下的尖
	for i in 2:
		var side: float = -1.0 if i == 0 else 1.0
		var hand: Vector2 = _v(0.82 * side, 0.58)
		for j in 3:
			var offset: float = (float(j) - 1.0) * radius * 0.11
			draw_colored_polygon(_poly_abs([
				hand + Vector2(offset - radius * 0.055, 0.0),
				hand + Vector2(offset + radius * 0.055, 0.0),
				hand + Vector2(offset, radius * 0.20),
			]), FANG)

	# 头：小而圆，直接压进宽肩里（海猴子没脖子），越显得凶
	draw_circle(_v(0.0, -0.92), radius * 0.50, light)
	draw_circle(_v(-0.17, -1.02), radius * 0.078, EYE_YELLOW)
	draw_circle(_v(0.17, -1.02), radius * 0.078, EYE_YELLOW)

	# 獠牙从嘴角往上翻。位置必须离开眼睛一段距离 ——
	# 早先贴着眉心画，两只獠牙正好戳在眼睛下面，像长了一对尖鼻子。
	draw_colored_polygon(_poly([[-0.16, -0.62], [-0.04, -0.62], [-0.11, -0.78]]), FANG)
	draw_colored_polygon(_poly([[0.04, -0.62], [0.16, -0.62], [0.11, -0.78]]), FANG)
	draw_line(_v(-0.17, -0.60), _v(0.17, -0.60), dark, maxf(1.0, radius * 0.06))


## 尸蟞：贴地爬的小甲虫。体型最小，靠数量压人。
## 六条外伸的腿是它在一堆怪里最容易被认出来的特征，所以画得比壳还长。
func _draw_beetle() -> void:
	var body: Color = body_color
	var dark: Color = _shade(body, 0.55)
	var light: Color = _shade(body, 1.24)

	_ground_shadow(0.72, 0.18, 0.66)

	# 六条腿先画，被甲壳压住根部才像「长在身上」而不是「粘在旁边」
	for i in 2:
		var side: float = -1.0 if i == 0 else 1.0
		for j in 3:
			var y: float = -0.34 + 0.32 * float(j)
			var tip_y: float = y * 1.45 + (0.14 if j == 2 else 0.0)
			draw_line(_v(0.40 * side, y), _v(0.96 * side, tip_y),
					dark, maxf(1.2, radius * 0.13))

	# 甲壳
	_ellipse(_v(0.0, -0.02), radius * 0.82, radius * 0.64, body)
	# 鞘翅中缝
	draw_line(_v(0.0, -0.58), _v(0.0, 0.30), dark, maxf(1.0, radius * 0.10))
	# 左上弧形高光，让壳有弧度
	draw_arc(_v(-0.08, -0.08), radius * 0.52, PI * 1.12, PI * 1.60, 8, light,
			maxf(1.0, radius * 0.09), true)
	# 头与触角
	_ellipse(_v(0.0, 0.56), radius * 0.30, radius * 0.22, dark)
	draw_line(_v(-0.12, 0.64), _v(-0.30, 0.90), dark, maxf(1.0, radius * 0.08))
	draw_line(_v(0.12, 0.64), _v(0.30, 0.90), dark, maxf(1.0, radius * 0.08))


## 血量环。只在掉血后出现，不画常驻底环：
## 有了具体造型之后，两百个黄圈会把满屏糊成一片噪点，还会和形体轮廓打架。
##
## 形状是椭圆而不是圆，半轴按各造型自己的高度取 —— 圆环半径统一用
## radius+3 的话，粽子（头顶 1.34r）和海猴子（头顶 1.42r）的环会直接
## 切进脑袋，看着像头上套了个铁框。
func _draw_health_ring() -> void:
	var ratio: float = get_health_ratio()
	if ratio >= 1.0:
		return
	var r: Vector2 = _ring_radii()
	_ellipse_arc(Vector2.ZERO, r, 0.0, TAU, Color(0.0, 0.0, 0.0, 0.22), 2.0)
	var start: float = -PI * 0.5
	_ellipse_arc(Vector2.ZERO, r, start, start + TAU * ratio, Color(0.45, 0.95, 0.55), 2.5)


## 各类造型的包围半轴（含 2px 余量），用来贴住血条。
func _ring_radii() -> Vector2:
	match kind:
		EnemyData.Kind.SNAKE:
			return Vector2(0.86, 1.30) * radius
		EnemyData.Kind.APE:
			return Vector2(1.06, 1.50) * radius
		EnemyData.Kind.BEETLE:
			return Vector2(1.12, 1.04) * radius
		_:
			return Vector2(0.80, 1.44) * radius


# ---------------------------------------------------------------- 绘制工具

## 按半径缩放的坐标。所有造型数值都写成 radius 的倍数。
func _v(x: float, y: float) -> Vector2:
	return Vector2(x * radius, y * radius)


## 明暗派生。乘到 1 以上时必须夹住，否则超过 1 的通道会烧成纯白。
func _shade(color: Color, factor: float) -> Color:
	return Color(
		clampf(color.r * factor, 0.0, 1.0),
		clampf(color.g * factor, 0.0, 1.0),
		clampf(color.b * factor, 0.0, 1.0),
		color.a)


func _poly(points: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p: Array in points:
		out.append(_v(float(p[0]), float(p[1])))
	return out


func _poly_abs(points: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p: Vector2 in points:
		out.append(p)
	return out


## 椭圆。draw_circle 只能画正圆，甲壳和蛇头都要压扁。
func _ellipse(center: Vector2, rx: float, ry: float, color: Color, segments: int = 18) -> void:
	var pts := PackedVector2Array()
	pts.resize(segments)
	for i in segments:
		var a: float = TAU * float(i) / float(segments)
		pts[i] = center + Vector2(cos(a) * rx, sin(a) * ry)
	draw_colored_polygon(pts, color)


## 圆角矩形。躯干和四肢都用它，比直角方块柔和，也比逐处手搓多边形好维护。
## 四个圆角必须按顺时针依次拼：漏掉上面两个角会变成「上直下圆」，
## 顺序写反（先到底部再回右侧）会让多边形自交，填充直接花掉。
func _rounded(pos: Vector2, size: Vector2, corner: float, steps: int = 4) -> PackedVector2Array:
	var r: float = maxf(0.0, minf(corner, minf(size.x, size.y) * 0.5))
	var pts := PackedVector2Array()
	if r <= 0.01:
		pts.append(pos)
		pts.append(pos + Vector2(size.x, 0.0))
		pts.append(pos + Vector2(size.x, size.y))
		pts.append(pos + Vector2(0.0, size.y))
		return pts

	var lt: Vector2 = pos + Vector2(r, r)
	var rt: Vector2 = pos + Vector2(size.x - r, r)
	var rb: Vector2 = pos + Vector2(size.x - r, size.y - r)
	var lb: Vector2 = pos + Vector2(r, size.y - r)
	var corners: Array[Vector2] = [lt, rt, rb, lb]
	var starts: Array[float] = [PI, PI * 1.5, 0.0, PI * 0.5]
	for ci in 4:
		for i in steps + 1:
			var a: float = starts[ci] + (PI * 0.5) * float(i) / float(steps)
			pts.append(corners[ci] + Vector2(cos(a), sin(a)) * r)
	return pts


## 圆弧上的点，填充后是一个「弓形」。给粽子的头发用。
func _cap_points(center: Vector2, r: float, from: float, to: float, segments: int = 12) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in segments + 1:
		var a: float = from + (to - from) * float(i) / float(segments)
		pts.append(center + Vector2(cos(a), sin(a)) * r)
	return pts


## 椭圆弧。draw_arc 只能画正圆，而血条得贴着高瘦或矮胖的造型走。
func _ellipse_arc(center: Vector2, radii: Vector2, from: float, to: float,
		color: Color, width: float, segments: int = 28) -> void:
	var n: int = maxi(3, int(ceil(segments * absf(to - from) / TAU)))
	var pts := PackedVector2Array()
	pts.resize(n + 1)
	for i in n + 1:
		var a: float = from + (to - from) * float(i) / float(n)
		pts[i] = center + Vector2(cos(a) * radii.x, sin(a) * radii.y)
	draw_polyline(pts, color, width, true)


## 落在地上的软阴影。压扁的椭圆 + 低透明度，不画会让怪像浮在半空。
func _ground_shadow(rx: float, ry: float, y: float) -> void:
	_ellipse(_v(0.0, y), radius * rx, radius * ry, SHADOW)
