# 玩家：WASD/方向键移动、生命、经验等级，并作为武器的挂载点。
# 攻击由子节点 Weapon 自行驱动，玩家本身不索敌、不生成子弹。
class_name Player
extends Node2D

## 血量变化时发出，UI 监听此信号而不是轮询。
signal health_changed(current: float, maximum: float)

## 血量归零时发出一次。
signal died

## 经验值或升级所需经验变化时发出，UI 监听此信号刷新显示。
signal xp_changed(current: int, needed: int)

## 每升一级发出一次；连续升多级会连续发出，由上层决定如何排队处理。
signal leveled_up(level: int)

## 装备新武器时发出，供 UI 刷新武器栏。
signal weapon_added(weapon: Weapon)

## 武器升级时发出。
signal weapon_upgraded(weapon: Weapon)

## 主动技能成功释放时发出。主场景用它做震屏、音效与额外的场面反馈。
signal skill_used(kind: int, at: Vector2)

## 升到 5 的倍数级时解锁新技能后发出，主场景用来弹提示条。
signal skill_unlocked(skill_name: String, level: int)

## 三个技能都解锁之后，再每 5 级改为整体强化一次，同样弹提示条。
signal skill_mastered(tier: int, level: int)

## 实际掉血时发出（治疗不触发）。UI 用它做震屏与红闪，
## 而不是监听 health_changed —— 后者在治疗时也会发，会导致加血反而像受击。
signal hurt(amount: float)

@export var move_speed: float = 190.0
@export var max_health: float = 100.0
@export var radius: float = 15.0
@export var invuln_time: float = 0.55
## 接触伤害的结算间隔（秒）。被多个敌人贴身时伤害叠加，但每按此间隔只结算一次，
## 避免「一次涌入 20 只怪」瞬间秒杀。
@export var contact_interval: float = 0.4
## 经验宝石的磁吸范围，可通过强化提升。
@export var pickup_radius: float = 110.0
## 开局自带的武器 id，留空则不自动装备。
@export var starting_weapon: String = "pistol"
## 武器槽上限：满了以后不再提供「解锁武器」选项。
## 当前武器库只有手枪 / 回旋刀 / 圣光三把，槽位与武器数保持一致，
## 否则第四个槽位永远空着，玩家会以为还有未解锁的内容。
@export var max_weapons: int = 3

# ---------------------------------------------------------------- 角色与技能
#
# 四个角色的差异全部通过这组字段落到同一个 Player 上：
# 「属性 → 数值倍率」「外观 → 绘制参数」「技能 → cast_skill 的分支」。
# 这样新加角色只需要往 CharacterData 里加一条数据，不必碰这个文件。

## 当前角色的数据来源。Game 在玩家入树前注入，标题页换人时也会重新注入。
var character: CharacterData = null
## 技能剩余冷却（秒）。0 表示随时可放。
var skill_cooldown_left: float = 0.0
## 技能总冷却。HUD 用它算进度条比例，换角色时一起更新。
var skill_cooldown_total: float = 12.0
## 武器伤害倍率（角色固有）。
var damage_multiplier: float = 1.0
## 武器冷却倍率（角色固有），小于 1 表示更快。
var cooldown_multiplier: float = 1.0
## 受到伤害的倍率，小于 1 表示更抗打（王胖子）。
var damage_taken_scale: float = 1.0
## 技能带来的临时攻速倍率。必须和 cooldown_multiplier 分开存：
## 增益到期时只还原这一项，角色自带的攻速差异不会被顺手抹掉。
var skill_cooldown_scale: float = 1.0

## 技能增益的剩余时间与加成。速度与攻速各存一份，同一套计时器管两种增益。
var _buff_timer: float = 0.0
var _buff_speed: float = 1.0
var _buff_cooldown: float = 1.0
## 技能特效的闪光计时，纯表现。
var _skill_flash: float = 0.0

## 预览模式：选人界面会把 Player 当"立绘"用，只保留绘制与呼吸动画。
## 这种实例不该建碰撞体、不该装武器、也不该跑物理逻辑。
var preview: bool = false

## 单类强化的最大层数。没有上限的强化会被无限叠加，
## 玩家 DPS 会指数级甩开敌人曲线，难度设计随之失效。
const UPGRADE_CAPS: Dictionary = {
	"damage": 8,
	"fire_rate": 8,
	"range": 5,
	"max_hp": 6,
	"move_speed": 5,
	"magnet": 4,
}

# ---------------------------------------------------------------- 外观参数
#
# Q 版造型：一头身、大眼睛、齐刘海、腮红。全部用 _draw() 程序化绘制。
#
# 为什么不用贴图：这个角色随时要改颜色（受击闪白、无敌闪烁）和改形状
# （走路摆腿、呼吸起伏、眨眼）。贴图方案得预先烘出十几套序列帧，
# 内存和制作成本都更高，而程序化绘制每帧只有几十个图元 —— 而且全球只有
# 一个主角，这点开销在 60fps 下是噪声级。敌人那种上百实例的量级才必须
# 走「画一次 + modulate」的路子，两边不冲突。
#
# 尺寸约束：原点沿用碰撞圆心，所以视觉轮廓要贴着 radius=15 的判定圆。
# 脚底落在 +15 附近、头顶落在 -22 附近，玩家看到的体型才和实际受击范围
# 对得上；视觉明显大于判定会出现「没碰到却掉血」的憋屈感。

## 头部半径。Q 版的核心是头身比，这个值不能被身体尺寸牵着走。
const HEAD_R: float = 9.8
## 头心相对原点的纵向位置。负数向上。
const HEAD_Y: float = -11.4
## 脚底中心线，同时作为落地阴影的基准。
const FOOT_Y: float = 12.6

const SKIN: Color = Color(1.0, 0.855, 0.755)
const HAIR: Color = Color(0.19, 0.235, 0.345)
const HAIR_HI: Color = Color(0.52, 0.61, 0.82, 0.50)
const CLOTH: Color = Color(0.36, 0.74, 1.0)
## 短裤。只比上衣深一档：差太多会让下半身和鞋子糊成一整块暗色。
const CLOTH_DEEP: Color = Color(0.22, 0.45, 0.76)
## 袖口。必须比短裤更暗，否则手臂顶端那截会看着像"手里握着东西"。
const SLEEVE: Color = Color(0.14, 0.30, 0.52)
const TRIM: Color = Color(0.95, 0.97, 1.0)
const SHOE: Color = Color(0.22, 0.28, 0.40)
const OUTLINE: Color = Color(0.06, 0.08, 0.12, 0.85)
const EYE: Color = Color(0.12, 0.16, 0.25)
const BLUSH: Color = Color(1.0, 0.52, 0.55, 0.40)
const MOUTH: Color = Color(0.45, 0.22, 0.22, 0.85)

# 下面是"可被角色覆盖"的绘制参数。默认值等于上面那套原始配色，
# 所以不注入角色时（例如预览、旧存档）画面和以前完全一致。
var hair_color: Color = HAIR
var cloth_color: Color = CLOTH
var cloth_deep_color: Color = CLOTH_DEEP
var sleeve_color: Color = SLEEVE
var trim_color: Color = TRIM
## 体型横向缩放。Q 版靠宽窄区分胖瘦，比改身高有效得多。
var body_girth: float = 1.0
## 脑后长发（小哥）。
var hair_long: bool = false
## 墨镜（黑瞎子）。
var wear_glasses: bool = false
## 肚子（王胖子）。
var belly: bool = false

var health: float = 0.0
var level: int = 1
var xp: int = 0
var xp_to_next: int = 5
var weapons: Array[Weapon] = []
## 已获取的强化层数，键为强化 id。
var upgrade_levels: Dictionary = {}

# 全局武器加成：由「锐化弹头 / 快速装填 / 射程校准」累计，新解锁的武器同样享受。
# 早期版本直接把加成写进已有武器的 data.damage，结果「先解锁武器再拿强化」和
# 「先拿强化再解锁武器」得到的最终 DPS 不一样，解锁顺序变成了隐藏强度差。
var global_damage_bonus: float = 0.0
var global_cooldown_scale: float = 1.0
var global_range_bonus: float = 0.0

var _invuln_timer: float = 0.0
var _contact_timer: float = 0.0
var _last_position: Vector2 = Vector2.ZERO
## 最近一次的移动方向。刷怪器用它把一部分敌人放到玩家前方，
## 否则「一直往一个方向跑」会把整屏怪都甩在身后，越跑越没内容可打。
var facing: Vector2 = Vector2.RIGHT
## 接触判定用的检测体。用 Area2D 而不是每帧遍历全部敌人做距离比较：
## 敌人上百时逐对求距离是纯浪费，物理宽相只回报告真正重叠的那几只。
var _hurtbox: Area2D = null
## 触屏摇杆（移动端）。桌面端为 null，键盘输入完全不受影响。
## 由 Game 在构建 UI 时注入；玩家只管读取它的方向向量。
var joystick: TouchJoystick = null
## 障碍解算：由 Game 注入。传入「期望位置」与自身半径，返回被障碍推开后的位置。
## 玩家是纯 Node2D（没有物理体），走位限制必须手动解算；敌人才是物理体，会自动绕开。
var obstacle_query: Callable = Callable()
## 场地边界：由 Game 注入。为空矩形时不限制（预览 / 单测场景）。
## 和障碍一样，玩家没有物理体，撞墙只能靠坐标夹制。
var arena_rect: Rect2 = Rect2()

# 动画状态：全部是纯表现量，不参与任何玩法计算。
var _anim_time: float = 0.0
var _walk_phase: float = 0.0
## 走路幅度 0~1，起停时平滑过渡，避免站着不动时腿还在原地抖。
var _walk_amp: float = 0.0
## 眨眼进度 1→0；为 0 时眼睛全睁。
var _blink: float = 0.0
var _blink_wait: float = 2.2
## 受击闪白强度 1→0，单独一层而不是复用无敌状态：
## 无敌有 0.55 秒，闪白只该有 0.15 秒，否则角色整段无敌都在发白光。
var _hit_flash: float = 0.0
## 是否移动过。开局朝向还没被真实位移覆盖，外观要默认"面对镜头"。
var _ever_moved: bool = false


func _ready() -> void:
	health = max_health
	health_changed.emit(health, max_health)
	xp_changed.emit(xp, xp_to_next)
	_blink_wait = randf_range(1.0, 3.4)
	if preview:
		# 选人界面的立绘：只要会呼吸、会眨眼的一张小人，不需要任何玩法对象。
		set_physics_process(false)
		queue_redraw()
		return
	_build_hurtbox()
	var starter: WeaponData = WeaponData.by_id(starting_weapon)
	if starter != null:
		add_weapon(starter)
	queue_redraw()


## 预览模式专用的呼吸/眨眼驱动。正常游玩时这段逻辑在 _physics_process 里，
## 但预览实例关掉了物理帧 —— 一张静态立绘不该每帧跑移动与碰撞结算。
func _process(delta: float) -> void:
	if not preview:
		return
	_update_anim(delta, 0.0)
	queue_redraw()


## 检测半径取 radius + 3：敌人被 Enemy._keep_outside_target() 顶在
## 「两半径之和」的边缘上，留 3 像素余量保证贴脸的怪稳定算作接触，
## 否则浮点边界会让同一只怪在「碰到 / 碰到」之间反复跳动。
func _build_hurtbox() -> void:
	_hurtbox = Area2D.new()
	_hurtbox.name = "Hurtbox"
	_hurtbox.collision_layer = 0
	_hurtbox.collision_mask = PhysicsLayers.ENEMY
	_hurtbox.monitoring = true
	_hurtbox.monitorable = false
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = radius + 3.0
	shape.shape = circle
	_hurtbox.add_child(shape)
	add_child(_hurtbox)


## 当前贴在身上的敌人。已排队释放的不返回，避免死亡瞬间重复结算。
func get_contact_enemies() -> Array[Enemy]:
	var result: Array[Enemy] = []
	if _hurtbox == null:
		return result
	for body: Node2D in _hurtbox.get_overlapping_bodies():
		var enemy := body as Enemy
		if enemy == null or enemy.is_queued_for_deletion():
			continue
		result.append(enemy)
	return result


func _physics_process(delta: float) -> void:
	var direction: Vector2 = _read_move_input()
	if direction != Vector2.ZERO:
		# 先算出「想去的」位置，再交给障碍解算把坐标推出碎石圆 —— 否则玩家会直接
		# 穿进石头里，和「限制走位」的初衷完全相反。敌人因为是物理体，不需要这一步。
		var intended: Vector2 = global_position + direction * current_speed() * delta
		if obstacle_query.is_valid():
			intended = obstacle_query.call(intended, radius)
		# 障碍解算可能把玩家推进墙里（碎石可以贴着墙），所以边界要放在最后一步夹。
		global_position = confine_to_arena(intended)

	# 朝向按「跨帧真实位移」更新，而不是按输入：脚本或外部系统直接改坐标时
	# （例如自动化测试里的机器人），朝向也必须跟着变，否则刷怪器的「前方」
	# 会一直停在初始的 RIGHT，怪全刷到右边去了。
	var moved: Vector2 = global_position - _last_position
	_last_position = global_position
	if moved.length_squared() > 0.0001:
		facing = moved.normalized()
		_ever_moved = true

	_invuln_timer = maxf(0.0, _invuln_timer - delta)
	_contact_timer = maxf(0.0, _contact_timer - delta)
	_tick_skill(delta)

	var actual_speed: float = moved.length() / maxf(delta, 0.0001)
	_update_anim(delta, clampf(actual_speed / maxf(current_speed(), 1.0), 0.0, 1.0))
	# 呼吸、眨眼、闪烁每一帧都在变，整帧重绘是最省事也最省心的做法。
	queue_redraw()


## 把坐标夹进场地。留出自身半径，身体不压进墙里。
## 场地为空时原样返回 —— 选人界面的立绘、单测都跑在没有场地的场景里。
func confine_to_arena(pos: Vector2) -> Vector2:
	if arena_rect.size.x <= 0.0 or arena_rect.size.y <= 0.0:
		return pos
	var margin := Vector2(radius, radius)
	return pos.clamp(arena_rect.position + margin, arena_rect.end - margin)


## 推进纯表现用的计时器。传入的 moving 是「实际速度 / 最高速度」，0~1。
func _update_anim(delta: float, moving: float) -> void:
	_anim_time += delta
	_walk_amp = move_toward(_walk_amp, moving, delta * 7.0)
	_walk_phase += delta * 10.5 * _walk_amp
	# 长时间游玩后相位会涨到上万弧度，float32 精度开始丢小数位，
	# 摆腿会从平滑变成一格一格。按整周期回绕不影响视觉。
	if _walk_phase > TAU * 64.0:
		_walk_phase -= TAU * 64.0

	_blink_wait -= delta
	if _blink_wait <= 0.0:
		_blink = 1.0
		_blink_wait = randf_range(2.0, 5.4)
	elif _blink > 0.0:
		_blink = maxf(0.0, _blink - delta * 7.0)

	_hit_flash = maxf(0.0, _hit_flash - delta * 6.5)


# ---------------------------------------------------------------- 角色注入

## 把角色数据落到这个实例上。必须在入树（_ready）之前调用：
## _ready 会按 max_health 初始化血量、按 starting_weapon 装武器，晚了就会用默认值。
func apply_character(data: CharacterData) -> void:
	if data == null:
		return
	character = data
	move_speed = data.move_speed
	max_health = data.max_health
	health = max_health
	pickup_radius = data.pickup_radius
	starting_weapon = data.starting_weapon
	damage_multiplier = data.damage_scale
	cooldown_multiplier = data.cooldown_scale
	damage_taken_scale = data.damage_taken_scale
	global_range_bonus = data.range_bonus
	skill_cooldown_total = data.skill_cooldown
	skill_cooldown_left = 0.0
	skill_cooldown_scale = 1.0
	_buff_timer = 0.0
	_buff_speed = 1.0
	_buff_cooldown = 1.0
	# 换角色等于换一套技能表：旧角色的技能槽、冷却与强化层数必须全部清掉，
	# 否则标题页换人后再开局会带着上一个人的解锁进度。
	skills.clear()
	skill_cd.clear()
	skill_mastery = 0
	_cast_gate = 0.0
	_ward_timer = 0.0
	_ward_scale = 1.0
	_refresh_skills(false)

	hair_color = data.hair_color
	cloth_color = data.cloth_color
	cloth_deep_color = data.cloth_deep_color
	sleeve_color = data.sleeve_color
	trim_color = data.trim_color
	body_girth = data.body_girth
	hair_long = data.hair_long
	wear_glasses = data.wear_glasses
	belly = data.belly

	health_changed.emit(health, max_health)
	queue_redraw()


## 标题页换人时用：除了换数值，还要把武器换成新角色的起手武器。
## 只在这里做武器替换 —— 正常开局走的是 _ready，它能一次性把武器配好。
func reset_for_character(data: CharacterData) -> void:
	if data == null:
		return
	for weapon: Weapon in weapons:
		if is_instance_valid(weapon):
			weapon.queue_free()
	weapons.clear()
	# 标题页换人是把同一个 Player 复用为新一局：等级与强化也要归零，
	# 否则上一局打到 20 级的人，一换角色就白拿三个技能和两层强化。
	level = 1
	xp = 0
	xp_to_next = 5
	upgrade_levels.clear()
	global_damage_bonus = 0.0
	global_cooldown_scale = 1.0
	global_range_bonus = 0.0
	apply_character(data)
	var starter: WeaponData = WeaponData.by_id(starting_weapon)
	if starter != null:
		add_weapon(starter)


## 当前实际移速：角色基础值 × 技能增益。
func current_speed() -> float:
	if _buff_timer > 0.0:
		return move_speed * _buff_speed
	return move_speed


# ---------------------------------------------------------------- 主动技能

## 已解锁的技能与它们各自的剩余冷却。两个数组下标一一对应，且只追加不重排，
## 所以数字键 / 手机按钮可以一直按同一个下标定位到同一个技能。
var skills: Array[SkillDef] = []
var skill_cd: Array[float] = []
## 三个技能集齐后，每再升 5 级累积一层强化：冷却更短、威力更强。
var skill_mastery: int = 0
## 所有技能共用一道短闸门：连点数字键也不能把三个技能在同一帧全砸出去。
const CAST_GATE: float = 0.55
var _cast_gate: float = 0.0
## WARD 类技能的临时减伤倍率。
var _ward_timer: float = 0.0
var _ward_scale: float = 1.0


## 至少有一个技能就绪且不处于公共闸门 / 死亡状态。
func can_cast_skill() -> bool:
	if character == null or health <= 0.0 or _cast_gate > 0.0:
		return false
	for cd: float in skill_cd:
		if cd <= 0.0:
			return true
	return false


## 给 HUD 与按钮用的每帧快照：名字、总冷却、剩余、是否就绪、键位序号。
## 总冷却已经是「强化后」的值，进度条才不会和实际释放节奏对不上。
func skill_ui() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if character == null:
		return out
	for i in skills.size():
		var def: SkillDef = skills[i]
		var total: float = maxf(0.01, _cooldown_of(def))
		var left: float = skill_cd[i] if i < skill_cd.size() else 0.0
		out.append({
			"name": def.name,
			"total": total,
			"remaining": left,
			"ready": left <= 0.0,
			"key": i + 1,
			"color": character.accent,
		})
	return out


## 升级后同步技能表：先解锁（最多 3 个），三个齐了再叠强化层数。
## announce 只在真正升级时为 true —— apply_character 建槽时不该弹提示。
func _refresh_skills(announce: bool) -> void:
	if character == null:
		return
	var wanted: Array[SkillDef] = character.skills_at(level)
	for def: SkillDef in wanted:
		if skills.has(def):
			continue
		skills.append(def)
		skill_cd.append(0.0)
		if announce:
			skill_unlocked.emit(def.name, level)
	if not skills.is_empty():
		skill_cooldown_total = _cooldown_of(skills[0])

	var tier: int = CharacterData.mastery_at(level)
	if tier > skill_mastery and announce:
		skill_mastered.emit(tier, level)
	# 直接赋值而不是只在变大时更新：换人 / 重开一局时等级会归零，
	# 强化层数也必须跟着归零，不能留着上一局的增长。
	skill_mastery = tier


## 强化后的实际冷却。层数封顶在数据表里，不会趋近于零。
func _cooldown_of(def: SkillDef) -> float:
	return def.cooldown * pow(CharacterData.MASTERY_CD_SCALE, float(skill_mastery))


## 强化后的威力倍率：伤害与治疗都吃这个加成。
func _power_scale() -> float:
	return 1.0 + CharacterData.MASTERY_POWER_SCALE * float(skill_mastery)


func _knock_of(def: SkillDef) -> float:
	return def.knockback * (1.0 + 0.06 * float(skill_mastery))


## 释放技能。index < 0 表示「一次放出所有已就绪的技能」（E / 空格 / 主按钮），
## 否则只放第 index 个（数字键 / 手机分键）。返回是否真的放出了至少一个。
func cast_skill(index: int = -1) -> bool:
	if character == null or health <= 0.0 or _cast_gate > 0.0:
		return false
	if index >= skills.size():
		return false
	if index >= 0:
		if skill_cd[index] > 0.0:
			return false
		_fire(index)
		_cast_gate = CAST_GATE
		return true
	var fired: bool = false
	for i in skills.size():
		if skill_cd[i] <= 0.0:
			_fire(i)
			fired = true
	if fired:
		_cast_gate = CAST_GATE
	return fired


## 单个技能生效：进冷却、执行效果、通知上层做镜头与音效反馈。
func _fire(index: int) -> void:
	var def: SkillDef = skills[index]
	skill_cd[index] = _cooldown_of(def)
	_skill_flash = 1.0
	_execute(def)
	skill_used.emit(int(def.effect), global_position)
	queue_redraw()
	if not skill_cd.is_empty():
		skill_cooldown_left = skill_cd[0]


## 通用效果执行器：只认八种效果类型，角色差异全部在 SkillDef 的参数里。
func _execute(def: SkillDef) -> void:
	match def.effect:
		SkillDef.Effect.BURST:
			_damage_area(global_position, def.radius, def.power * _power_scale() * damage_multiplier,
					_knock_of(def))
			_apply_buff(def)
		SkillDef.Effect.DASH:
			_dash(def)
			_apply_buff(def)
		SkillDef.Effect.BOMB:
			_drop_bomb(def)
		SkillDef.Effect.BUFF:
			_apply_buff(def)
		SkillDef.Effect.HEAL:
			heal(def.heal_amount * _power_scale())
			_invuln_timer = maxf(_invuln_timer, def.invuln)
		SkillDef.Effect.WARD:
			_ward_timer = maxf(_ward_timer, def.duration)
			# 强化也会让减伤更硬一点，但留一个下限，不能变成完全无敌。
			_ward_scale = maxf(0.25, def.reduction - 0.02 * float(skill_mastery))
			_apply_buff(def)
		SkillDef.Effect.RING:
			_damage_ring(global_position, def.inner_radius, def.radius,
					def.power * _power_scale() * damage_multiplier, _knock_of(def))
		SkillDef.Effect.VOLLEY:
			_volley(def)


## 增益：只覆盖配置里显式给过的项。否则一个纯加速技能会把正在生效的
## 「狂风连射」攻速加成顺手抹掉，玩家会莫名其妙掉一截 DPS。
func _apply_buff(def: SkillDef) -> void:
	if def.duration <= 0.0:
		return
	_buff_timer = maxf(_buff_timer, def.duration * (1.0 + 0.05 * float(skill_mastery)))
	if def.speed_scale != 1.0:
		_buff_speed = def.speed_scale
	if def.cooldown_scale != 1.0:
		_buff_cooldown = def.cooldown_scale
		skill_cooldown_scale = _buff_cooldown
		recalc_weapons()


## 每帧推进：公共闸门、每个技能的独立冷却、强化增益、护盾计时。
func _tick_skill(delta: float) -> void:
	_cast_gate = maxf(0.0, _cast_gate - delta)
	_skill_flash = maxf(0.0, _skill_flash - delta * 2.2)
	for i in skill_cd.size():
		skill_cd[i] = maxf(0.0, skill_cd[i] - delta)
	if not skill_cd.is_empty():
		skill_cooldown_left = skill_cd[0]
	if _ward_timer > 0.0:
		_ward_timer = maxf(0.0, _ward_timer - delta)
		if _ward_timer <= 0.0:
			_ward_scale = 1.0
	if _buff_timer <= 0.0:
		return
	_buff_timer = maxf(0.0, _buff_timer - delta)
	if _buff_timer > 0.0:
		return
	_buff_speed = 1.0
	_buff_cooldown = 1.0
	if skill_cooldown_scale != 1.0:
		skill_cooldown_scale = 1.0
		recalc_weapons()


## 突进斩：沿路径逐点收集目标，而不是只结算终点圆 —— 后者会漏掉中途穿过的怪。
func _dash(def: SkillDef) -> void:
	var direction: Vector2 = facing.normalized() if facing.length_squared() > 0.0001 \
			else Vector2.RIGHT
	var from: Vector2 = global_position
	var to: Vector2 = from + direction * def.distance
	if obstacle_query.is_valid():
		to = obstacle_query.call(to, radius)

	_invuln_timer = maxf(_invuln_timer, def.invuln)
	var hit: Dictionary = {}
	var steps: int = 8
	for i in steps + 1:
		var point: Vector2 = from.lerp(to, float(i) / float(steps))
		for node: Node in get_tree().get_nodes_in_group("enemies"):
			var enemy := node as Enemy
			if enemy == null or not is_instance_valid(enemy) or enemy.is_queued_for_deletion():
				continue
			if hit.has(enemy):
				continue
			var reach: float = 46.0 + enemy.radius
			if point.distance_squared_to(enemy.global_position) <= reach * reach:
				hit[enemy] = true
	for key: Variant in hit.keys():
		var enemy := key as Enemy
		if enemy == null or not is_instance_valid(enemy):
			continue
		enemy.take_damage(def.power * _power_scale() * damage_multiplier)
		enemy.apply_knockback(enemy.global_position - from, _knock_of(def))
	# 突进也要受墙限制：几百像素足够从场地中间一路顶到墙上。
	global_position = confine_to_arena(to)


## 延迟引信炸药。留在原地，玩家得提前把怪引进圈里。
func _drop_bomb(def: SkillDef) -> void:
	var direction: Vector2 = facing.normalized() if facing.length_squared() > 0.0001 \
			else Vector2.RIGHT
	var bomb := Bomb.new()
	bomb.owner_player = self
	bomb.blast_radius = def.radius * (1.0 + 0.03 * float(skill_mastery))
	bomb.blast_damage = def.power * _power_scale() * damage_multiplier
	bomb.band_color = character.accent if character != null else Color(1.0, 0.62, 0.28)
	_world().add_child(bomb)
	bomb.global_position = global_position + direction * 96.0


## 面朝方向的打击：用「前方偏移圆」近似扇形，简单但读起来就是一记朝前的挥击。
func _volley(def: SkillDef) -> void:
	var direction: Vector2 = facing.normalized() if facing.length_squared() > 0.0001 \
			else Vector2.RIGHT
	var center: Vector2 = global_position + direction * def.distance
	_damage_area(center, def.radius, def.power * _power_scale() * damage_multiplier,
			_knock_of(def))


## 环形冲击：只打中距离一圈。贴脸的怪反而漏掉，和 BURST 形成明确的用途差别。
func _damage_ring(center: Vector2, inner: float, outer: float, amount: float,
		force: float, limit: int = 72) -> int:
	var hits: int = 0
	for node: Node in get_tree().get_nodes_in_group("enemies"):
		var enemy := node as Enemy
		if enemy == null or not is_instance_valid(enemy) or enemy.is_queued_for_deletion():
			continue
		var d: float = center.distance_to(enemy.global_position)
		if d < inner - enemy.radius or d > outer + enemy.radius:
			continue
		enemy.take_damage(amount)
		enemy.apply_knockback(enemy.global_position - center, force)
		hits += 1
		if hits >= limit:
			break
	return hits


## 对一片圆形范围内的敌人结算一次伤害。技能与炸药共用这一份实现。
func _damage_area(center: Vector2, area: float, amount: float, force: float,
		limit: int = 72) -> int:
	var hits: int = 0
	for node: Node in get_tree().get_nodes_in_group("enemies"):
		var enemy := node as Enemy
		if enemy == null or not is_instance_valid(enemy) or enemy.is_queued_for_deletion():
			continue
		var reach: float = area + enemy.radius
		if center.distance_squared_to(enemy.global_position) > reach * reach:
			continue
		enemy.take_damage(amount)
		enemy.apply_knockback(enemy.global_position - center, force)
		hits += 1
		if hits >= limit:
			break
	return hits


## 场景根节点。炸药要留在原地，不能挂在玩家身上跟着跑。
func _world() -> Node:
	var node: Node = self
	while node.get_parent() != null and node.get_parent() != get_tree().root:
		node = node.get_parent()
	return node


## 王胖子的炸药。延迟引信 + 爆炸范围预示圈，让玩家能看清自己扔在哪。
class Bomb extends Node2D:
	const FUSE: float = 0.6

	var owner_player: Player = null
	var blast_radius: float = 250.0
	var blast_damage: float = 90.0
	var band_color: Color = Color(1.0, 0.62, 0.28)

	var _time: float = 0.0

	func _process(delta: float) -> void:
		_time += delta
		if _time >= FUSE:
			if is_instance_valid(owner_player):
				owner_player._damage_area(global_position, blast_radius, blast_damage, 620.0, 96)
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		var t: float = clampf(_time / FUSE, 0.0, 1.0)
		# 预示圈随时间收拢：圈缩到最小时正好炸开，读起来就是"引信在烧"。
		var ring: Color = band_color
		ring.a = 0.16 + 0.30 * t
		draw_arc(Vector2.ZERO, blast_radius * (1.0 - 0.35 * t), 0.0, TAU, 48, ring, 2.0, true)
		var blink: float = 0.5 + 0.5 * sin(_time * 34.0)
		draw_circle(Vector2.ZERO, 8.0, Color(0.14, 0.13, 0.12))
		var spark: Color = Color(1.0, 0.55, 0.18).lerp(Color(1.0, 0.98, 0.80), blink)
		draw_circle(Vector2.ZERO, 4.2, spark)
		draw_arc(Vector2.ZERO, 15.0, -PI * 0.5, -PI * 0.5 + TAU * (1.0 - t), 20,
				Color(band_color.r, band_color.g, band_color.b, 0.85), 2.0, true)


## 装备一把武器；已拥有同 id 武器或槽位已满时不重复装备。返回装备后的实例。
func add_weapon(data: WeaponData) -> Weapon:
	if data == null or has_weapon(data.id) or weapons.size() >= max_weapons:
		return null
	var weapon := Weapon.new()
	add_child(weapon)
	weapon.setup(data)
	weapons.append(weapon)
	weapon_added.emit(weapon)
	return weapon


func has_weapon(id: String) -> bool:
	return find_weapon(id) != null


func find_weapon(id: String) -> Weapon:
	for weapon: Weapon in weapons:
		if weapon.data != null and weapon.data.id == id:
			return weapon
	return null


## 把某把武器升一级。已满级或未持有时返回 false，交由上层决定是否降级处理。
func upgrade_weapon(id: String) -> bool:
	var weapon: Weapon = find_weapon(id)
	if weapon == null or not weapon.can_level_up():
		return false
	weapon.level += 1
	weapon.recalc()
	weapon_upgraded.emit(weapon)
	return true


## 全局加成变化后，让所有武器重算最终数值。
func recalc_weapons() -> void:
	for weapon: Weapon in weapons:
		weapon.recalc()


## 某类强化已经拿了几层。
func upgrade_level(id: String) -> int:
	return int(upgrade_levels.get(id, 0))


## 该强化是否还能再选；未登记上限的 id 视为无限。
func can_upgrade(id: String) -> bool:
	if not UPGRADE_CAPS.has(id):
		return true
	return upgrade_level(id) < int(UPGRADE_CAPS[id])


## 记录一层强化，满层后该类选项不再出现。
func record_upgrade(id: String) -> void:
	upgrade_levels[id] = upgrade_level(id) + 1


func weapon_names() -> String:
	var names: PackedStringArray = []
	for weapon: Weapon in weapons:
		names.append("%s Lv%d" % [weapon.display_name(), weapon.level])
	return " / ".join(names)


func take_damage(amount: float) -> void:
	if _invuln_timer > 0.0 or health <= 0.0:
		return
	_invuln_timer = invuln_time
	_hit_flash = 1.0
	var before: float = health
	health = maxf(0.0, health - amount * damage_taken_scale * _ward_scale)
	health_changed.emit(health, max_health)
	hurt.emit(before - health)
	queue_redraw()
	if health == 0.0:
		for weapon: Weapon in weapons:
			weapon.set_physics_process(false)
		died.emit()


## 被多个敌人同时贴身时的接触伤害：绕过单次无敌帧，但受「受伤间隔」节流。
## 原来的实现每帧只会结算一只敌人（命中即 return），导致被 15 只围住和只被
## 1 只围住伤害完全一样 —— 于是「站着不动」反而更安全，难度曲线被架空了。
func take_contact_damage(amount: float) -> void:
	if _contact_timer > 0.0 or health <= 0.0:
		return
	_contact_timer = contact_interval
	_hit_flash = maxf(_hit_flash, 0.85)
	var before: float = health
	health = maxf(0.0, health - amount * damage_taken_scale * _ward_scale)
	health_changed.emit(health, max_health)
	hurt.emit(before - health)
	queue_redraw()
	if health == 0.0:
		for weapon: Weapon in weapons:
			weapon.set_physics_process(false)
		died.emit()


func heal(amount: float) -> void:
	health = minf(max_health, health + amount)
	health_changed.emit(health, max_health)


## 增加经验，可一次连升多级；每升一级发出 leveled_up，由上层排队处理强化选择。
## 1.12 倍复利：原 1.35 倍会让升级需求指数爆炸，三分钟只能升 3 级，
## 玩家成长完全追不上敌人曲线。
func add_xp(amount: int) -> void:
	if amount <= 0:
		return
	xp += amount
	while xp >= xp_to_next:
		xp -= xp_to_next
		level += 1
		xp_to_next = int(roundf(float(xp_to_next) * 1.22))
		leveled_up.emit(level)
	# 连升多级时只同步一次：Lv5 / Lv10 解锁技能，Lv15 起每 5 级叠一层强化。
	_refresh_skills(true)
	xp_changed.emit(xp, xp_to_next)


## 直接读按键，省去配置 InputMap，工程开箱即用。
## 键盘与触屏摇杆的方向相加后再归一化：两者可并存（例如用键盘微调、摇杆主攻），
## 也不会出现「两个半速方向相加反而变成满速」之类的问题。
func _read_move_input() -> Vector2:
	var direction: Vector2 = Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		direction.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		direction.x += 1.0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		direction.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		direction.y += 1.0
	if joystick != null and joystick.is_active():
		direction += joystick.get_vector()
	if direction.length_squared() > 0.0001:
		return direction.normalized()
	return Vector2.ZERO


# ---------------------------------------------------------------- 绘制

func _draw() -> void:
	var step: float = sin(_walk_phase)
	var amp: float = _walk_amp
	# 呼吸只在静止时出现：跑动时身体本来就在颠，再叠呼吸会看着发抖。
	var breath: float = sin(_anim_time * 2.1) * 0.5 * (1.0 - amp)
	var bob: float = -absf(step) * 1.5 * amp + breath
	var look: Vector2 = _look_dir()
	# 头部左右微摆：跟着脚步晃一点，再按朝向偏一点。整体旋转会让相机和
	# 挂载的武器跟着转，所以只挪绘制坐标，不动节点 transform。
	var sway: float = step * 0.9 * amp + look.x * 1.1

	_draw_ground_ring()
	_draw_buff_ring()
	_draw_shadow()
	_draw_legs(step, amp, bob)
	_draw_body(bob)
	_draw_arms(step, amp, bob)
	_draw_head(Vector2(sway, bob), look)


## 瞳孔偏移用的朝向。开局还没动过时朝正下方（看镜头），
## 否则一进游戏角色就定定地看着右边，像是卡住了。
func _look_dir() -> Vector2:
	if not _ever_moved:
		return Vector2.DOWN
	if facing.length_squared() < 0.0001:
		return Vector2.ZERO
	return facing.normalized()


## 无敌期整体半透明闪烁。用透明度而不是继续变白：受击那一帧已经闪白，
## 整段无敌还发白光会让角色糊成一团，反而看不清自己站在哪。
func _alpha_scale() -> float:
	if _hit_flash > 0.0:
		return 1.0
	if _invuln_timer <= 0.0:
		return 1.0
	return 0.42 + 0.58 * absf(sin(_anim_time * 22.0))


## 统一上色入口：受击闪白 + 无敌闪烁都在这里叠加，绘制代码只管传固有色。
func _tint(color: Color) -> Color:
	var out: Color = color
	if _hit_flash > 0.0:
		out = out.lerp(Color(1.0, 1.0, 1.0, out.a), _hit_flash)
	out.a *= _alpha_scale()
	return out


## 脚下一圈极淡的青色光环。同屏上百只敌人时，纯靠体型找自己很费眼，
## 这圈光在满屏色块里是最快的定位线索，透明度压到不抢画面为止。
## 必须是扁椭圆：正圆会被读成"角色站在呼啦圈里"，压扁才像落在地面上的光斑。
## 颜色取角色主题色 —— 四人同屏（截图/录屏）时靠这圈光就能认人。
func _draw_ground_ring() -> void:
	var pulse: float = 0.5 + 0.5 * sin(_anim_time * 2.4)
	var alpha: float = (0.12 + pulse * 0.08) * _alpha_scale()
	var tint: Color = _accent()
	var ring: PackedVector2Array = _ellipse_points(Vector2(0.0, FOOT_Y + 1.2),
			Vector2(14.0, 6.0), 30)
	draw_polyline(_closed(ring), Color(tint.r, tint.g, tint.b, alpha), 1.8, true)


## 技能增益期间的环绕光环。没有这层反馈，玩家只能靠"打得快了一点"来推断
## 六秒的窗口还剩多久，根本没法据此决定是继续压还是先撤。
func _draw_buff_ring() -> void:
	if _buff_timer <= 0.0:
		return
	var tint: Color = _accent()
	var spin: float = _anim_time * 3.2
	var pulse: float = 0.6 + 0.4 * sin(_anim_time * 9.0)
	for i in 3:
		var start: float = spin + TAU * float(i) / 3.0
		draw_arc(Vector2.ZERO, 25.0, start, start + PI * 0.42, 12,
				Color(tint.r, tint.g, tint.b, 0.52 * pulse), 2.4, true)


## 主题色。未注入角色时退回原来的青色，保证预览/旧存档不会变黑。
func _accent() -> Color:
	if character != null:
		return character.accent
	return Color(0.42, 0.86, 1.0)


## 两层椭圆做伪渐变阴影，单层纯黑会像一块贴纸。
func _draw_shadow() -> void:
	var a: float = 0.30 * _alpha_scale()
	_draw_ellipse(Vector2(0.0, FOOT_Y + 1.4), Vector2(10.6, 3.7), Color(0.0, 0.0, 0.0, a))
	_draw_ellipse(Vector2(0.0, FOOT_Y + 1.4), Vector2(7.0, 2.4), Color(0.0, 0.0, 0.0, a * 0.75))


func _draw_legs(step: float, amp: float, bob: float) -> void:
	for i in 2:
		var side: float = -1.0 if i == 0 else 1.0
		# 两条腿反相：一条前送、一条后撤。俯视角里"抬脚"主要靠纵向收缩表现，
		# 让脚真的离地反而会看着像在飘。
		var phase: float = step * side * amp
		var dx: float = phase * 1.5
		var dy: float = -absf(phase) * 1.4
		var rect := Rect2(side * 4.2 * body_girth - 2.6 + dx, 9.6 + bob * 0.6 + dy, 5.2, 6.0)
		draw_colored_polygon(_rounded_points(rect, 2.6, 4), _tint(SHOE))


func _draw_body(bob: float) -> void:
	# 身体明显窄于头：等宽会变成一个蓝色水桶，Q 版得让头"压"住肩膀。
	# 胖瘦只改横向宽度（body_girth），不改高度 —— Q 版里"变宽"立刻读成胖，
	# "变高"只会被读成换了个更高的角色。
	var half: float = 7.7 * body_girth
	var rect := Rect2(-half, -8.0 + bob, half * 2.0, 18.2)
	var pts: PackedVector2Array = _rounded_points(rect, 5.6, 6)
	draw_colored_polygon(pts, _tint(cloth_color))

	if belly:
		# 圆肚子：比躯干略宽一点点，才会在轮廓上鼓出来。凸得太多会像套了个球。
		var round := cloth_color.lightened(0.10)
		_draw_ellipse(Vector2(0.0, 1.6 + bob), Vector2(half + 0.9, 7.3), _tint(round))

	# 短裤用深一号的颜色盖住下半段。整块纯色在 40px 高的角色上会糊成一根
	# 色柱，分出上下装才有"穿着衣服的小人"的读感。
	var pants := Rect2(-half, 4.2 + bob, half * 2.0, 6.0)
	draw_colored_polygon(_skirt_points(pants, 5.6, 6), _tint(cloth_deep_color))
	# 一颗亮扣子。这么小的尺寸，靠这一粒亮色就能点出"这是衣服"。
	draw_circle(Vector2(0.0, 1.2 + bob), 1.1, _tint(trim_color))
	# 描边放在最后，一次性压住所有色块的接缝。
	draw_polyline(_closed(pts), _tint(OUTLINE), 1.3, true)


func _draw_arms(step: float, amp: float, bob: float) -> void:
	for i in 2:
		var side: float = -1.0 if i == 0 else 1.0
		# 手臂与同侧腿反相，走路才有左右摆动的节奏感。
		# 摆在身体前方而不是两侧：贴到身体边缘时只会露出一条 3px 宽的亮边，
		# 看着像衣服的高光，完全读不出是手臂。
		var swing: float = -step * side * amp
		var cx: float = side * 6.0 * body_girth
		var cy: float = 0.6 + bob + swing * 1.8
		var rect := Rect2(cx - 2.3, cy - 4.2, 4.6, 8.4)
		var pts: PackedVector2Array = _rounded_points(rect, 2.3, 4)
		draw_colored_polygon(pts, _tint(SKIN))
		draw_polyline(_closed(pts), _tint(OUTLINE), 1.1, true)
		# 短袖袖口，只在手臂顶端留一小截，太长会看成手里握着东西。
		var cuff := Rect2(cx - 2.5, cy - 4.4, 5.0, 2.8)
		draw_colored_polygon(_rounded_points(cuff, 1.4, 3), _tint(sleeve_color))


func _draw_head(offset: Vector2, look: Vector2) -> void:
	var c: Vector2 = Vector2(offset.x, HEAD_Y + offset.y)

	if hair_long:
		_draw_long_hair(c)

	_draw_ahoge(c)

	# 后发比脸大一圈：Q 版的头要"有厚度"，只画一个圆脸会像贴纸。
	_draw_ellipse(c, Vector2(HEAD_R + 1.2, HEAD_R + 1.2), _tint(hair_color))
	_draw_ellipse(c, Vector2(HEAD_R, HEAD_R - 0.15), _tint(SKIN))
	draw_arc(c, HEAD_R, 0.0, TAU, 30, _tint(OUTLINE), 1.3, true)

	draw_colored_polygon(_fringe_points(c), _tint(hair_color))
	# 头顶一条冷色反光，纯黑发在暗场景里会糊成剪影。
	draw_arc(c, HEAD_R - 2.4, PI * 1.12, PI * 1.46, 10, _tint(HAIR_HI), 1.8, true)

	_draw_eye(c + Vector2(-3.85, 1.2), look)
	_draw_eye(c + Vector2(3.85, 1.2), look)

	if wear_glasses:
		# 墨镜画在眼睛之后：整块盖住，只留腮红和嘴，才有"永远在笑"的味道。
		_draw_glasses(c)

	_draw_ellipse(c + Vector2(-6.9, 4.8), Vector2(2.6, 1.6), _tint(BLUSH))
	_draw_ellipse(c + Vector2(6.9, 4.8), Vector2(2.6, 1.6), _tint(BLUSH))

	# 嘴只画一道很浅的弧。无邪感不靠咧嘴笑，靠"表情克制"——
	# 嘴角一上扬过头就变成鬼脸，收着反而更干净。
	draw_arc(c + Vector2(0.0, 6.6), 1.7, 0.26, PI - 0.26, 10, _tint(MOUTH), 1.1, true)


## 脑后长发（小哥）。垂到肩膀为止、发尾走三个波浪 ——
## 平齐的下摆会像一块黑布，波浪边才读得成"头发"。
## 长度压在肩膀：再长就会把整件衣服盖住，人变成一团黑影。
func _draw_long_hair(c: Vector2) -> void:
	var half: float = HEAD_R + 1.0
	var top: float = c.y - HEAD_R * 0.2
	var bottom: float = c.y + 13.5
	var pts := PackedVector2Array()
	pts.append(Vector2(c.x - half, top))
	pts.append(Vector2(c.x + half, top))
	pts.append(Vector2(c.x + half * 0.92, bottom - 3.4))
	pts.append(Vector2(c.x + half * 0.55, bottom))
	pts.append(Vector2(c.x, bottom - 1.8))
	pts.append(Vector2(c.x - half * 0.55, bottom))
	pts.append(Vector2(c.x - half * 0.92, bottom - 3.4))
	draw_colored_polygon(pts, _tint(hair_color.darkened(0.12)))
	draw_polyline(_closed(pts), _tint(OUTLINE), 1.0, true)


## 墨镜（黑瞎子）。两片方镜 + 鼻梁 + 一道斜高光：
## 少了高光就只是两块黑斑，加上这一笔才读得出是"玻璃镜片"。
func _draw_glasses(c: Vector2) -> void:
	var lens: Color = Color(0.05, 0.06, 0.08, 0.95)
	var left := Rect2(c.x - 8.4, c.y - 0.4, 7.0, 4.6)
	var right := Rect2(c.x + 1.4, c.y - 0.4, 7.0, 4.6)
	draw_colored_polygon(_rounded_points(left, 1.6, 3), _tint(lens))
	draw_colored_polygon(_rounded_points(right, 1.6, 3), _tint(lens))
	draw_line(Vector2(c.x - 1.4, c.y + 1.4), Vector2(c.x + 1.4, c.y + 1.4), _tint(lens), 1.2)
	var shine: Color = _tint(Color(1.0, 1.0, 1.0, 0.55))
	for i in 2:
		var origin: Vector2 = left.position if i == 0 else right.position
		draw_line(origin + Vector2(1.6, 3.4), origin + Vector2(4.2, 1.0), shine, 1.1)


## 当前眨眼开合度，1 全睁、0 全闭。用正弦做成"闭上再睁开"，
## 线性变化会让眼睛像被压扁的薄片，而不是眼睑合上。
func _eye_openness() -> float:
	if _blink <= 0.0:
		return 1.0
	return 1.0 - sin((1.0 - _blink) * PI) * 0.92


func _draw_eye(center: Vector2, look: Vector2) -> void:
	var openness: float = _eye_openness()
	if openness < 0.10:
		# 闭眼画成向下的弧，比一条横线更像在笑。
		draw_arc(center, 2.3, 0.25, PI - 0.25, 8, _tint(EYE), 1.2, true)
		return

	var ry: float = 3.0 * openness
	_draw_ellipse(center, Vector2(2.5, ry), _tint(Color(0.995, 0.995, 1.0)))
	# 瞳孔按朝向偏移。偏移量压得很小（1.2px）：幅度一大，两只眼珠会
	# 跑到眼白外面，Q 版的"呆萌"立刻变成惊悚。
	var pupil: Vector2 = center + Vector2(look.x * 1.5, 0.3 + look.y * 0.8)
	_draw_ellipse(pupil, Vector2(1.7, minf(1.9, ry * 0.78)), _tint(EYE))
	draw_circle(pupil + Vector2(-0.52, -0.72), 0.6, _tint(Color(1.0, 1.0, 1.0)))
	if ry > 2.0:
		draw_circle(pupil + Vector2(0.58, 0.68), 0.3, _tint(Color(1.0, 1.0, 1.0, 0.78)))


## 齐刘海：沿头顶弧从左鬓走到右鬓，下沿走三个小波浪。
## 刘海下沿压到眼睛上方 2px 左右，露出的额头越少越幼态。
## 两侧鬓角顺着脸圆收进去 —— 早先版本让鬓角在脸两侧往外挑，正面看
## 会变成两个黑色团块，像戴着耳机。
func _fringe_points(c: Vector2) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var steps: int = 16
	for i in steps + 1:
		var a: float = PI + PI * float(i) / float(steps)
		pts.append(c + Vector2(cos(a), sin(a)) * (HEAD_R + 0.7))
	# 右侧鬓角：贴着圆周往下再收进脸颊
	pts.append(c + Vector2(HEAD_R * 0.985, HEAD_R * 0.17))
	pts.append(c + Vector2(HEAD_R * 0.83, HEAD_R * 0.31))
	# 刘海下沿，从右到左
	pts.append(c + Vector2(6.6, -3.0))
	pts.append(c + Vector2(3.4, -4.9))
	pts.append(c + Vector2(0.0, -3.6))
	pts.append(c + Vector2(-3.4, -4.9))
	pts.append(c + Vector2(-6.6, -3.0))
	# 左侧鬓角镜像
	pts.append(c + Vector2(-HEAD_R * 0.83, HEAD_R * 0.31))
	pts.append(c + Vector2(-HEAD_R * 0.985, HEAD_R * 0.17))
	return pts


## 头顶呆毛。Q 版可爱度的便宜加分项：一根随呼吸轻摆的细线。
func _draw_ahoge(c: Vector2) -> void:
	var base: Vector2 = c + Vector2(0.2, -HEAD_R + 0.5)
	var mid: Vector2 = base + Vector2(-1.4, -3.1)
	var tip: Vector2 = base + Vector2(2.3 + sin(_anim_time * 3.4) * 0.9, -4.7)
	draw_polyline(PackedVector2Array([base, mid, tip]), _tint(hair_color), 1.5, true)


# ---------------------------------------------------------------- 绘制工具

## 椭圆。draw_circle 只能画正圆，用多边形手搓：等角采样在椭圆上分布均匀，
## 比 set_transform 缩放圆的做法更不容易出现压扁后的棱角。
func _draw_ellipse(center: Vector2, radii: Vector2, color: Color, segments: int = 24) -> void:
	if radii.x <= 0.01 or radii.y <= 0.01:
		return
	draw_colored_polygon(_ellipse_points(center, radii, segments), color)


func _ellipse_points(center: Vector2, radii: Vector2, segments: int = 24) -> PackedVector2Array:
	var pts := PackedVector2Array()
	pts.resize(segments)
	for i in segments:
		var a: float = TAU * float(i) / float(segments)
		pts[i] = center + Vector2(cos(a) * radii.x, sin(a) * radii.y)
	return pts


## 圆角矩形的轮廓点，顺时针，y 轴向下。
## 手臂、腿、身体都是这个形状，统一生成比各画一遍圆+方块好维护。
func _rounded_points(rect: Rect2, corner: float, steps: int = 5) -> PackedVector2Array:
	var r: float = minf(corner, minf(rect.size.x, rect.size.y) * 0.5)
	var centers: Array[Vector2] = [
		rect.position + Vector2(rect.size.x - r, rect.size.y - r),
		rect.position + Vector2(r, rect.size.y - r),
		rect.position + Vector2(r, r),
		rect.position + Vector2(rect.size.x - r, r),
	]
	var starts: Array[float] = [0.0, PI * 0.5, PI, PI * 1.5]
	var pts := PackedVector2Array()
	for ci in 4:
		for i in steps + 1:
			var a: float = starts[ci] + (PI * 0.5) * float(i) / float(steps)
			pts.append(centers[ci] + Vector2(cos(a), sin(a)) * r)
	return pts


## 上边平直、下边带圆角的形状，专供上下装分段：
## 两段拼接时接缝必须是一条直线，四角都圆会在分界处凹出两个缺口。
func _skirt_points(rect: Rect2, corner: float, steps: int = 6) -> PackedVector2Array:
	var r: float = minf(corner, minf(rect.size.x, rect.size.y) * 0.5)
	var pts := PackedVector2Array()
	pts.append(rect.position)
	pts.append(rect.position + Vector2(rect.size.x, 0.0))
	var rb: Vector2 = rect.position + Vector2(rect.size.x - r, rect.size.y - r)
	for i in steps + 1:
		var a: float = PI * 0.5 * float(i) / float(steps)
		pts.append(rb + Vector2(cos(a), sin(a)) * r)
	var lb: Vector2 = rect.position + Vector2(r, rect.size.y - r)
	for i in steps + 1:
		var a: float = PI * 0.5 + PI * 0.5 * float(i) / float(steps)
		pts.append(lb + Vector2(cos(a), sin(a)) * r)
	return pts


## 把顶点数组首尾连起来，供 draw_polyline 画闭合轮廓。
func _closed(points: PackedVector2Array) -> PackedVector2Array:
	var out: PackedVector2Array = points.duplicate()
	if out.size() > 0:
		out.append(out[0])
	return out
