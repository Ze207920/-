# 敌人数据：描述一种邪物的外形、数值与出场规则，纯数据不含逻辑。
# 与 WeaponData 同样使用静态工厂而非 .tres，克隆工程后无需额外资源导入即可运行。
class_name EnemyData
extends Resource

## 邪物种类。取自《盗墓笔记》，每种沿用原来四种几何形状的数值骨架 ——
## 玩法定位不变，只把外形换成本书里的东西：
## 数量多 / 快 / 硬 / 成群，玩家必须靠轮廓和颜色在一瞬间分清威胁等级。
enum Kind {
	ZOMBIE,   ## 粽子：尸变的尸体。各项数值的基准，出现最早
	SNAKE,    ## 鸡冠蛇：剧毒且快，血薄，追得上玩家
	APE,      ## 海猴子：力大无穷，血厚得离谱、正面推不动
	BEETLE,   ## 尸蟞：成群爬行的小虫，单体极脆
}

@export var id: String = "zombie"
@export var display_name: String = "粽子"
@export var kind: Kind = Kind.ZOMBIE
@export var max_health: float = 10.0
@export var move_speed: float = 70.0
@export var contact_damage: float = 6.0
@export var radius: float = 13.0
@export var body_color: Color = Color(0.58, 0.66, 0.60)
## 击退倍率：1.0 是基准，越重的怪取越小的值，同样的冲击推不动它。
@export var knockback_resist: float = 1.0
## 进入刷怪池的时间点（秒）。种类按时段解锁，避免开局就四种怪糊脸。
@export var min_elapsed: float = 0.0
## 随机权重，只在该种类已解锁后参与抽签。
@export var weight: float = 100.0
## 一次生成几只。尸蟞成群出现，单只很弱但一窝很难缠。
@export var pack_size: int = 1

## 预设缓存。返回的是共享实例，调用方只读，不要就地改数值。
static var _presets: Array[EnemyData] = []


## 全部预设。首次调用时构建，之后复用。
static func presets() -> Array[EnemyData]:
	if _presets.is_empty():
		_presets.append(_zombie())
		_presets.append(_snake())
		_presets.append(_ape())
		_presets.append(_beetle())
	return _presets


## 按已解锁种类加权随机抽一种；全部未解锁（理论上不会）时退回粽子。
static func pick(elapsed: float) -> EnemyData:
	var candidates: Array[EnemyData] = []
	var total: float = 0.0
	for preset: EnemyData in presets():
		if elapsed < preset.min_elapsed:
			continue
		candidates.append(preset)
		total += preset.weight
	if candidates.is_empty() or total <= 0.0:
		return presets()[0]

	var roll: float = randf() * total
	for preset: EnemyData in candidates:
		roll -= preset.weight
		if roll <= 0.0:
			return preset
	return candidates[candidates.size() - 1]


## 按 id 取共享预设，未知 id 返回 null。挑战模式的关卡名单用字符串写，
## 名字打错时应该能被发现，而不是悄悄退化成粽子。
static func by_id(enemy_id: String) -> EnemyData:
	for preset: EnemyData in presets():
		if preset.id == enemy_id:
			return preset
	return null


## 挑战模式专用：从「[id, 出场秒数]」名单里加权抽一种。
## 与 pick() 的区别是不用 EnemyData.min_elapsed —— 关卡自己决定谁什么时候出场，
## 同一只怪在不同关卡里的解锁时间可以完全不同。
static func pick_pool(pool: Array, elapsed: float) -> EnemyData:
	var candidates: Array[EnemyData] = []
	var total: float = 0.0
	for entry: Array in pool:
		if entry.size() < 1:
			continue
		if entry.size() >= 2 and elapsed < float(entry[1]):
			continue
		var preset: EnemyData = by_id(String(entry[0]))
		if preset == null:
			push_warning("EnemyData: 关卡名单里的未知邪物「%s」" % String(entry[0]))
			continue
		candidates.append(preset)
		total += preset.weight
	if candidates.is_empty() or total <= 0.0:
		return presets()[0]

	var roll: float = randf() * total
	for preset: EnemyData in candidates:
		roll -= preset.weight
		if roll <= 0.0:
			return preset
	return candidates[candidates.size() - 1]


## 粽子：基准怪。血、速、伤害都是 1.0，其余种类相对它调参。
## 颜色是发灰的尸青 —— 比纯绿更「陈旧」，也让它在深蓝地板上不至于太跳。
static func _zombie() -> EnemyData:
	var data := EnemyData.new()
	data.id = "zombie"
	data.display_name = "粽子"
	data.kind = Kind.ZOMBIE
	data.max_health = 10.0
	data.move_speed = 70.0
	data.contact_damage = 6.0
	data.radius = 13.0
	data.body_color = Color(0.58, 0.66, 0.60)
	data.knockback_resist = 1.0
	data.min_elapsed = 0.0
	data.weight = 100.0
	return data


## 鸡冠蛇：血薄一半、速度快三成。追得上玩家，逼玩家不能只往一个方向跑。
## 冷青绿让它在粽子堆里单独挑得出来 —— 它的威胁比外表大得多。
static func _snake() -> EnemyData:
	var data := EnemyData.new()
	data.id = "snake"
	data.display_name = "鸡冠蛇"
	data.kind = Kind.SNAKE
	data.max_health = 6.5
	data.move_speed = 88.0
	data.contact_damage = 4.5
	data.radius = 10.0
	data.body_color = Color(0.28, 0.64, 0.52)
	data.knockback_resist = 1.5
	data.min_elapsed = 25.0
	data.weight = 45.0
	return data


## 海猴子：血厚四倍、慢得像墙。它的作用是堵路和扛伤害，不是追人。
## 击退倍率压到 0.45，正面连射也推不动几步，必须靠火力硬压。
static func _ape() -> EnemyData:
	var data := EnemyData.new()
	data.id = "ape"
	data.display_name = "海猴子"
	data.kind = Kind.APE
	data.max_health = 30.0
	data.move_speed = 44.0
	data.contact_damage = 13.0
	data.radius = 22.0
	data.body_color = Color(0.44, 0.55, 0.64)
	data.knockback_resist = 0.45
	data.min_elapsed = 70.0
	data.weight = 30.0
	return data


## 尸蟞：单体极脆、伤害低，但一次来两只且推力弱，容易糊住走位。
## 用暖橙褐 —— 满地爬的暖色小点在一屏冷色里非常好认，也最容易招人烦。
static func _beetle() -> EnemyData:
	var data := EnemyData.new()
	data.id = "beetle"
	data.display_name = "尸蟞"
	data.kind = Kind.BEETLE
	data.max_health = 3.6
	data.move_speed = 82.0
	data.contact_damage = 3.0
	data.radius = 8.0
	data.body_color = Color(0.72, 0.46, 0.22)
	data.knockback_resist = 1.8
	data.min_elapsed = 120.0
	data.weight = 40.0
	data.pack_size = 2
	return data
