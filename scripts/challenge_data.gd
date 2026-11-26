# 挑战模式关卡数据：每关一套独立的难度曲线、邪物名单与通关目标。
#
# 为什么不用「全局难度曲线 + 关卡倍率」两级叠加：一关只有 1~3 分钟，
# 它的节奏必须自己写死 —— 第一关前 20 秒不该有海猴子，最后一关最后 10 秒
# 必须压到极限。倍率叠乘做不出这种形状，只会把整条曲线整体放大或缩小。
#
# 六条曲线用 Vector2 存起止值（x = 开局，y = 关卡结束），中间按 pow(t, 1.35)
# 插值：前段平缓给玩家熟悉操作的时间，后段才是真正的压力。
class_name ChallengeData
extends Resource

## 难度档位。只影响选关界面的标签与配色，不参与任何数值计算。
enum Tier {
	EASY,       ## 入门
	NORMAL,     ## 标准
	HARD,       ## 困难
	NIGHTMARE,  ## 噩梦
}

const TIER_NAMES: Array[String] = ["入门", "标准", "困难", "噩梦"]
const TIER_COLORS: Array[Color] = [
	Color(0.42, 0.86, 0.62),
	Color(0.36, 0.80, 1.00),
	Color(1.00, 0.72, 0.32),
	Color(1.00, 0.38, 0.44),
]

## 最后这一段时间的「墓主追击」。每关必出一只，从最远的角落入场，全程锁定玩家。
## 用固定 30 秒而不是关卡时长的百分比：短关卡也必须留出足够长的逃命时间，
## 长关卡则不能把 boss 拖成半场马拉松。
const BOSS_WINDOW: float = 30.0
## 每关一只，名字跟着墓室主题走。选关详情与 HUD 都从这里读，避免两处写出不同名字。
const BOSS_NAMES: Array[String] = [
	"鲁殇王", "积尸地母", "鸡冠蛇王", "禁婆",
	"天宫守将", "青铜树魈", "西王母尸", "万奴王",
]
## 每关主色：从尸变暗红一路走到风雪里的苍白金，和八张地面贴图各自呼应。
const BOSS_COLORS: Array[Color] = [
	Color(0.72, 0.30, 0.28),
	Color(0.66, 0.42, 0.24),
	Color(0.32, 0.56, 0.38),
	Color(0.34, 0.52, 0.72),
	Color(0.52, 0.68, 0.78),
	Color(0.62, 0.48, 0.26),
	Color(0.76, 0.32, 0.42),
	Color(0.86, 0.78, 0.62),
]

@export var id: String = "ch1"
@export var display_name: String = "关卡"
@export var subtitle: String = ""
## 选关界面底部的关卡特性说明，一句话讲清「这关和别关差在哪」。
@export var blurb: String = ""
@export var tier: Tier = Tier.EASY
## 关卡时间轴长度。通关要同时满足「击败本关墓主」与「存活到这个时间结束」，
## 二者缺一不可（见 Game._physics_process）。它还决定难度曲线走到哪儿、
## 场地收缩到哪儿、墓主何时苏醒。时间走完而墓主还活着 → 不限时决战，
## 一直打到墓主倒下为止；墓主提前倒下 → 继续守到时间结束。
@export var duration: float = 60.0

## 以下六条曲线的起止值：x = 开局，y = 结束。
@export var hp_span: Vector2 = Vector2(1.0, 2.0)
@export var speed_span: Vector2 = Vector2(1.0, 1.5)
@export var interval_span: Vector2 = Vector2(1.0, 0.4)
@export var cap_span: Vector2 = Vector2(38.0, 80.0)
@export var pack_span: Vector2 = Vector2(1.0, 3.0)
@export var damage_span: Vector2 = Vector2(1.0, 1.5)

## 邪物名单。每项是 [种类 id, 出场秒数]，用显式的出场时间而不是复用
## EnemyData.min_elapsed —— 「蛇沼鬼城」这一关的蛇必须从第 0 秒就在场，
## 而「云顶天宫」的海猴子要等到中段，两种需求不能共用一套时间表。
@export var kinds: Array = []

## 刷怪落点翻到玩家前进方向的概率。越高的关卡越难靠「一直往前跑」摆脱追兵。
@export var front_bias: float = 0.55

## 障碍（墓室碎石）参数。仅挑战模式生效，用来限制玩家与邪物的走位。
## 各关递进：越后面的关，碎石越密、越大、刷新越快、存活越短 —— 走位空间被持续压缩。
@export var obstacle_interval: float = 4.0   ## 每隔多少秒刷一批
@export var obstacle_batch: int = 2           ## 每批刷几块
@export var obstacle_radius: float = 46.0     ## 单块半径基准（实际 ±25% 抖动）
@export var obstacle_lifetime: float = 22.0   ## 单块存活秒数，到点淡出
@export var obstacle_max: int = 16            ## 同屏上限，超出回收最老的一块

## 该关的墓室尺寸。空间本身就是难度：越靠后的关越窄，绕不开就只能硬顶。
@export var arena_size: Vector2 = Vector2(2100.0, 1450.0)
## 墓室随时间收缩的终点比例：0.70 表示边长只剩七成（面积约一半）。
## 由 _apply_arena_balance() 按关卡序号插值写入，第一关留得多、终章收得最狠。
@export var arena_final_scale: float = 0.76
## 收缩从进度 8% 起，开局留一点时间让玩家认清场地；超时决战阶段不再继续收缩。
const ARENA_SHRINK_START: float = 0.08

## 最后 BOSS_WINDOW 秒登场的墓主。数值由 _apply_boss_balance() 按关卡序号插值写入，
## 关卡表本身不重复写八组数字 —— 和场地尺寸一个道理。
@export var boss_name: String = ""
@export var boss_health: float = 0.0
@export var boss_speed: float = 0.0
@export var boss_damage: float = 0.0
@export var boss_radius: float = 0.0
@export var boss_color: Color = Color(0.72, 0.30, 0.28)

## 墓主技能。等级 1 = 只会「血影突进」，2 = 再加「墓气震荡」，3 = 两招都更快更疼。
## 由 _apply_boss_balance() 按关卡序号写入，选关界面与 Enemy 都只读。
@export var boss_skill_level: int = 1
@export var boss_skill_interval: float = 6.0
@export var boss_skill_damage: float = 10.0
@export var boss_skill_radius: float = 190.0

static var _levels: Array[ChallengeData] = []
static var _hell: ChallengeData = null

## 地狱模式的墓主登场时刻。八关墓主全部登场：开局一位，此后每 30 秒一位，
## 最后 30 秒剩余三位一起苏醒 —— 否则 3 分钟只够刷六位，凑不齐八关墓主。
## 时间到而墓主未全部伏诛时进入不限时决战，不会在最后一秒强行判负。
const HELL_BOSS_TIMES: Array[float] = [
	0.0, 30.0, 60.0, 90.0, 120.0, 150.0, 150.0, 150.0,
]


## 全部关卡，按难度从低到高排列。首次调用时构建。
static func levels() -> Array[ChallengeData]:
	if _levels.is_empty():
		_build()
	return _levels


static func count() -> int:
	return levels().size()


## 地狱模式：独立的一张 3 分钟数据表，不进 levels() 的八关列表，
## 所以选关界面、解锁进度、下一关逻辑都不会被它污染。
## 数值在终章之上再抬一档：血量、密度、伤害、收缩全都更狠；
## 场地比终章还窄，碎石更密，给八位墓主留出的走位空间极小。
static func hell() -> ChallengeData:
	if _hell == null:
		_hell = _make(
				"hell", "地狱模式", "终局 · 八墓主", Tier.NIGHTMARE, 180.0,
				Vector2(1.55, 8.60), Vector2(1.22, 2.72), Vector2(0.68, 0.12),
				Vector2(58.0, 186.0), Vector2(2.0, 6.0), Vector2(1.22, 2.00),
				[["zombie", 0.0], ["snake", 0.0], ["ape", 8.0], ["beetle", 18.0]], 0.74,
				"三分钟，八位墓主轮番苏醒。杂兵不停，场地持续收缩，活到最后才算赢。",
				2.2, 3, 52.0, 15.0, 24)
		_hell.arena_size = Vector2(1760.0, 1220.0)
		_hell.arena_final_scale = 0.62
	return _hell


## 取第 index 关，越界时钳到最后一关 —— 选关界面和存档都可能给出脏数据。
static func at(index: int) -> ChallengeData:
	var all: Array[ChallengeData] = levels()
	if all.is_empty():
		return null
	return all[clampi(index, 0, all.size() - 1)]


static func tier_name(value: int) -> String:
	return TIER_NAMES[clampi(value, 0, TIER_NAMES.size() - 1)]


static func tier_color(value: int) -> Color:
	return TIER_COLORS[clampi(value, 0, TIER_COLORS.size() - 1)]


## 某一时刻的难度档位，与 Game.difficulty_at 的输出格式完全一致：
## [血量倍率, 移速倍率, 刷怪间隔, 同屏上限, 每批数量, 接触伤害倍率]。
func curve_at(elapsed: float) -> PackedFloat32Array:
	var t: float = clampf(elapsed / maxf(1.0, duration), 0.0, 1.0)
	# pow 的指数大于 1：曲线前段被压低、后段被抬高。指数 1.0 是纯线性，
	# 那样第 1 秒和第 59 秒的压迫感差别不够，中段又太紧。
	var w: float = pow(t, 1.35)
	return PackedFloat32Array([
		lerpf(hp_span.x, hp_span.y, w),
		lerpf(speed_span.x, speed_span.y, w),
		lerpf(interval_span.x, interval_span.y, w),
		lerpf(cap_span.x, cap_span.y, w),
		maxf(1.0, floorf(lerpf(pack_span.x, pack_span.y, w) + 0.001)),
		lerpf(damage_span.x, damage_span.y, w),
	])


func objective_text() -> String:
	# 通关要两件事都做到：打倒墓主 + 活到时间结束。卡片上必须写清楚，
	# 否则玩家会以为只做其中一件就赢了。
	return "击败墓主并存活 · %d秒" % int(duration)


## 用实心/空心星表示档位，比纯文字标签更容易一眼扫过去。
func star_text() -> String:
	return "★".repeat(int(tier) + 1) + "☆".repeat(3 - int(tier))


## 该关卡在某一时刻已出场的邪物数量，选关界面用来显示「敌人 x 种」。
func active_kind_count(elapsed: float) -> int:
	var total: int = 0
	for entry: Array in kinds:
		if entry.size() >= 2 and elapsed >= float(entry[1]):
			total += 1
	return total


# ---------------------------------------------------------------- 关卡表
#
# 配平基准：把每一关的「终点难度」对齐到生存曲线（DIFFICULTY_KEYS）上某个时间点。
# 生存模式实测人类玩家的存活区间是 150~240 秒，所以：
#   入门关的终点 ≈ 生存 90~100 秒的强度   → 稳稳能过
#   噩梦关的终点 ≈ 生存 270~300 秒的强度  → 需要成型构筑 + 全程走位
# 直接凭感觉给数字必然翻车：第一版第 8 关的收尾血量给到 9.5 倍，相当于生存模式
# 420 秒以后，那个强度在生存模式里都没人活着见过，关卡自然无解。
#
# 另外每关的「敌人名单」本身就是难度的一部分：只出粽子的一关，同样的血量倍率
# 打起来要轻松得多，所以入门关的数值可以给得比生存曲线同时段更高一点。

static func _build() -> void:
	# 障碍参数随难度递增：越后面的关，碎石越密、越大、刷新越快、存活越短。
	_levels.append(_make(
			"ch1", "七星鲁王宫", "第一关 · 试胆", Tier.EASY, 60.0,
			Vector2(0.90, 2.10), Vector2(0.95, 1.25), Vector2(1.20, 0.50),
			Vector2(30.0, 72.0), Vector2(1.0, 2.0), Vector2(0.85, 1.05),
			[["zombie", 0.0]], 0.55,
			"只有尸变的粽子。慢、笨、数量多 —— 先把手感和走位找回来。",
			5.0, 1, 44.0, 24.0, 10))

	_levels.append(_make(
			"ch2", "积尸地", "第二关 · 虫潮", Tier.EASY, 75.0,
			Vector2(0.90, 2.30), Vector2(0.95, 1.28), Vector2(1.15, 0.46),
			Vector2(34.0, 74.0), Vector2(1.0, 3.0), Vector2(0.85, 1.08),
			[["zombie", 0.0], ["beetle", 15.0]], 0.55,
			"尸蟞成群从石缝里涌出，一次两只。它们不疼，但它们糊住你的脚步。",
			4.5, 1, 46.0, 22.0, 12))

	_levels.append(_make(
			"ch3", "蛇沼鬼城", "第三关 · 疾行", Tier.NORMAL, 90.0,
			Vector2(1.00, 2.70), Vector2(1.00, 1.50), Vector2(1.05, 0.42),
			Vector2(38.0, 88.0), Vector2(1.0, 3.0), Vector2(0.90, 1.13),
			[["zombie", 0.0], ["snake", 0.0]], 0.58,
			"鸡冠蛇比玩家跑得快，而且从第一秒就在场。一直往前跑不再管用。",
			4.0, 2, 46.0, 22.0, 14))

	_levels.append(_make(
			"ch4", "西沙海底墓", "第四关 · 群围", Tier.NORMAL, 105.0,
			Vector2(1.05, 3.30), Vector2(1.00, 1.60), Vector2(0.95, 0.34),
			Vector2(42.0, 102.0), Vector2(1.0, 3.0), Vector2(0.95, 1.20),
			[["zombie", 0.0], ["snake", 15.0], ["ape", 30.0]], 0.58,
			"守墓的海猴子醒了。它血厚如墙、正面推不动，只能靠火力硬压。",
			3.8, 2, 48.0, 20.0, 15))

	_levels.append(_make(
			"ch5", "云顶天宫", "第五关 · 尸墙", Tier.HARD, 120.0,
			Vector2(1.15, 3.90), Vector2(1.05, 1.75), Vector2(0.88, 0.28),
			Vector2(46.0, 112.0), Vector2(1.0, 4.0), Vector2(1.00, 1.30),
			[["zombie", 0.0], ["snake", 10.0], ["ape", 20.0], ["beetle", 25.0]], 0.62,
			"四种邪物一起上。屏幕会变成一堵会动的尸墙 —— 一停就没了。",
			3.4, 2, 48.0, 20.0, 16))

	_levels.append(_make(
			"ch6", "青铜神树", "第六关 · 巨物", Tier.HARD, 135.0,
			Vector2(1.30, 4.60), Vector2(1.10, 1.90), Vector2(0.80, 0.24),
			Vector2(50.0, 122.0), Vector2(1.0, 4.0), Vector2(1.05, 1.40),
			[["zombie", 0.0], ["ape", 5.0], ["snake", 15.0], ["beetle", 30.0]], 0.64,
			"青铜树下的东西只记得重量。海猴子成群而来，火力必须够硬。",
			3.2, 2, 50.0, 18.0, 17))

	_levels.append(_make(
			"ch7", "西王母宫", "第七关 · 绝境", Tier.NIGHTMARE, 150.0,
			Vector2(1.30, 5.40), Vector2(1.15, 2.10), Vector2(0.78, 0.21),
			Vector2(54.0, 134.0), Vector2(1.0, 5.0), Vector2(1.05, 1.55),
			[["zombie", 0.0], ["snake", 5.0], ["ape", 20.0], ["beetle", 30.0]], 0.68,
			"西王母宫的深处没有退路。速度、厚度、数量，全部拉满。",
			2.8, 3, 48.0, 18.0, 18))

	_levels.append(_make(
			"ch8", "长白山", "终章 · 无归", Tier.NIGHTMARE, 180.0,
			Vector2(1.35, 7.20), Vector2(1.15, 2.50), Vector2(0.85, 0.16),
			Vector2(52.0, 160.0), Vector2(1.0, 6.0), Vector2(1.05, 1.85),
			[["zombie", 0.0], ["snake", 6.0], ["ape", 22.0], ["beetle", 34.0]], 0.72,
			"活到最后。这一关只问一件事：你到底练了多久。",
			2.6, 3, 50.0, 16.0, 20))

	_apply_arena_balance()
	_apply_boss_balance()


## 收窄场地之后的难度补偿 + 整体提难（第三次上调）。
##
## 原来的数值是给无限地图配的：邪物追不上玩家就永远追不上，只要一直跑就很难
## 被围住。改成封闭墓室之后，同屏的怪不需要「跑得比玩家快」也能合围，
## 被逼到墙角更是无路可退 —— 同样的同屏上限，真正压在身上的怪多得多。
##
## 提难时刻意只动「统一补偿系数」，不逐关改八组数字：关卡之间的递进曲线
## 形状完全保留，整条曲线只是平稳上抬一档，不会把某一关单独抬成断崖。
## 相对上一版（0.95 / 0.99 / 0.98 / 1.13 / 1.09），这一版：
##   同屏上限 ×1.00（+5%）、刷怪间隔 ×0.96（快 4%）、晚期移速 ×0.97（+3%）、
##   血量 ×1.18、接触伤害 ×1.13。
## 这一版通关条件又严了一档（击破墓主后还得活到时间结束），所以杂兵只小幅抬，
## 重量放在 boss 数值上（见 _apply_boss_balance），避免把决战压成无解。
## 每批数量上限仍 −1：最后 30 秒还有大 boss 压场，再放开批量刷怪会直接糊屏。
##
## 场地尺寸与收缩终点也在这里定：用插值而不是逐关写死，改关卡总数时不用重调八个数字。
static func _apply_arena_balance() -> void:
	const CAP_SCALE: float = 1.00
	const INTERVAL_SCALE: float = 0.96
	const SPEED_SCALE: float = 0.97
	const HP_SCALE: float = 1.18
	const DAMAGE_SCALE: float = 1.13
	for i in _levels.size():
		var level: ChallengeData = _levels[i]
		level.cap_span *= CAP_SCALE
		level.interval_span *= INTERVAL_SCALE
		level.speed_span.y *= SPEED_SCALE
		level.hp_span *= HP_SCALE
		level.damage_span *= DAMAGE_SCALE
		level.pack_span.y = maxf(level.pack_span.x, level.pack_span.y - 1.0)
		level.obstacle_max = maxi(6, level.obstacle_max - 1)
		# 第一关最宽敞（留出熟悉操作的空间），终章最窄（墙角最要命）。
		var t: float = float(i) / float(maxi(1, _levels.size() - 1))
		level.arena_size = Vector2(
			lerpf(2150.0, 1800.0, t),
			lerpf(1500.0, 1250.0, t))
		# 收缩也一样前松后紧：第一关只收到 82%，终章收到 70%。
		level.arena_final_scale = lerpf(0.82, 0.70, t)


## 每关墓主的数值。用插值而不是逐关写死，关卡数变化时自动重新铺开。
##
## 速度是最要紧的一项：玩家基准速度 190。第一关 172（明显跑得掉，只是
## 一直被跟着，给新手留出「原来会被追」的印象），终章 198（比玩家快一点，
## 必须靠走位绕碎石、突进技能或清出一条路）。八关平滑过渡，不会突然无解。
##
## 血量沿用「厚」的设定：墓主是通关的一半条件，玩家必须在杂兵环绕里把火力
## 集中到它身上。时间走完还没打倒就进入决战、不再计时，所以不需要在
## 30 秒窗口内勉强凑够伤害 —— 打得慢只是多熬一会儿，不会直接判负。
## 但打倒后还得守到时间结束，所以血量不能厚到「打完时早就超时」，否则通关
## 全程变成决战、失去节奏；这一版血量上调约 30%，但仍在可击杀区间内。
##
## 速度：玩家基准速度 190。第一关 178（追得上但跑得掉），终章 204（比玩家快，
## 必须靠走位/突进/清路）。伤害、技能伤害与频率同步上调，后期墓主真的能杀人。
##
## 技能按三档递进：前两关只会突进（教会玩家「它会突然加速」），
## 3~5 关加一圈墓气震荡（必须开始躲技能），6~8 关冷却更短、伤害更高。
static func _apply_boss_balance() -> void:
	for i in _levels.size():
		var level: ChallengeData = _levels[i]
		var t: float = float(i) / float(maxi(1, _levels.size() - 1))
		level.boss_name = BOSS_NAMES[clampi(i, 0, BOSS_NAMES.size() - 1)]
		level.boss_color = BOSS_COLORS[clampi(i, 0, BOSS_COLORS.size() - 1)]
		level.boss_health = lerpf(280.0, 1420.0, t)
		level.boss_speed = lerpf(178.0, 204.0, t)
		level.boss_damage = lerpf(17.0, 32.0, t)
		level.boss_radius = lerpf(36.0, 48.0, t)
		level.boss_skill_level = 1 if i < 2 else (2 if i < 5 else 3)
		level.boss_skill_interval = lerpf(6.4, 3.6, t)
		level.boss_skill_damage = lerpf(11.0, 21.0, t)
		level.boss_skill_radius = lerpf(185.0, 250.0, t)


static func _make(id: String, display_name: String, subtitle: String, tier: Tier,
		duration: float, hp: Vector2, speed: Vector2, interval: Vector2,
		cap: Vector2, pack: Vector2, damage: Vector2, kinds: Array,
		front_bias: float, blurb: String,
		obstacle_interval: float, obstacle_batch: int, obstacle_radius: float,
		obstacle_lifetime: float, obstacle_max: int) -> ChallengeData:
	var data := ChallengeData.new()
	data.id = id
	data.display_name = display_name
	data.subtitle = subtitle
	data.tier = tier
	data.duration = duration
	data.hp_span = hp
	data.speed_span = speed
	data.interval_span = interval
	data.cap_span = cap
	data.pack_span = pack
	data.damage_span = damage
	data.kinds = kinds
	data.front_bias = front_bias
	data.blurb = blurb
	data.obstacle_interval = obstacle_interval
	data.obstacle_batch = obstacle_batch
	data.obstacle_radius = obstacle_radius
	data.obstacle_lifetime = obstacle_lifetime
	data.obstacle_max = obstacle_max
	return data
