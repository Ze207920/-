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

@export var id: String = "ch1"
@export var display_name: String = "关卡"
@export var subtitle: String = ""
## 选关界面底部的关卡特性说明，一句话讲清「这关和别关差在哪」。
@export var blurb: String = ""
@export var tier: Tier = Tier.EASY
## 通关所需存活秒数。
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

static var _levels: Array[ChallengeData] = []


## 全部关卡，按难度从低到高排列。首次调用时构建。
static func levels() -> Array[ChallengeData]:
	if _levels.is_empty():
		_build()
	return _levels


static func count() -> int:
	return levels().size()


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
	return "存活 %d 秒" % int(duration)


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


## 收窄场地之后的难度补偿。
##
## 原来的数值是给无限地图配的：邪物追不上玩家就永远追不上，只要一直跑就很难
## 被围住。改成封闭墓室之后，同屏的怪不需要「跑得比玩家快」也能合围，
## 被逼到墙角更是无路可退 —— 同样的同屏上限，真正压在身上的怪多得多。
## 所以按统一比例把「同时能压上来多少」调回去：
##   同屏上限 ×0.82、刷怪间隔 ×1.12、每批数量上限 −1、晚期移速 ×0.92、碎石 −2。
## 关卡之间的递进关系不变，整条曲线只是整体下移一档。
##
## 场地尺寸也在这里定：用插值而不是逐关写死，改关卡总数时不用重新调八个数字。
static func _apply_arena_balance() -> void:
	const CAP_SCALE: float = 0.82
	const INTERVAL_SCALE: float = 1.12
	const SPEED_SCALE: float = 0.92
	for i in _levels.size():
		var level: ChallengeData = _levels[i]
		level.cap_span *= CAP_SCALE
		level.interval_span *= INTERVAL_SCALE
		level.speed_span.y *= SPEED_SCALE
		level.pack_span.y = maxf(level.pack_span.x, level.pack_span.y - 1.0)
		level.obstacle_max = maxi(6, level.obstacle_max - 2)
		# 第一关最宽敞（留出熟悉操作的空间），终章最窄（墙角最要命）。
		var t: float = float(i) / float(maxi(1, _levels.size() - 1))
		level.arena_size = Vector2(
			lerpf(2150.0, 1800.0, t),
			lerpf(1500.0, 1250.0, t))


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
