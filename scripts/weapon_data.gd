# 武器数据：描述一把武器怎么打、每一级怎么成长，纯数据不含逻辑。
# 最终数值由 Weapon.recalc() 按「基础值 → 等级成长 → 玩家全局加成」三层叠加算出，
# 因此这里只放基础值与成长率，不放任何已结算的数值。
class_name WeaponData
extends Resource

## 武器的攻击方式。
enum Kind {
	PROJECTILE, ## 朝最近的敌人射击
	ORBIT,      ## 环绕玩家的刀刃，周期性范围伤害
	AURA,       ## 以玩家为中心的周期性脉冲
}

## 等级上限。满级后该武器不再出现在升级选项里。
const MAX_LEVEL: int = 5

## 可解锁的全部武器，顺序即 UI 展示顺序。
const ALL_IDS: Array[String] = ["pistol", "blade", "aura"]

@export var id: String = "pistol"
@export var display_name: String = "武器"
## 一句话定位，显示在升级选项的说明行。
@export_multiline var blurb: String = ""
@export var kind: Kind = Kind.PROJECTILE
@export var color: Color = Color(0.99, 0.93, 0.45)

@export_group("等级 1 数值")
@export var damage: float = 5.0
@export var cooldown: float = 0.5
## 命中时施加的击退初速度（像素/秒）。敌人按自身体重打折，
## 所以同一个数值打到巨盾兵身上只能推动几步，打到蜂群身上会飞出去。
@export var knockback: float = 0.0
## 投射物的索敌距离。
@export var range: float = 420.0
## 范围武器的半径。
@export var area_radius: float = 70.0

@export_group("每级成长")
@export var damage_per_level: float = 1.2
## 每级冷却乘数，小于 1 表示越来越快。
@export var cooldown_per_level: float = 0.95
@export var range_per_level: float = 0.0
@export var radius_per_level: float = 0.0
## 每级增加的单次命中目标数，小数累加后取整。
@export var targets_per_level: float = 0.0
## 每几级多一发子弹 / 多一把刀；0 表示不增长。
@export var count_every: int = 0

@export_group("投射物")
@export var projectile_speed: float = 660.0
@export var projectile_life: float = 1.6
@export var projectiles_per_shot: int = 1
@export var spread_degrees: float = 0.0

@export_group("环绕 / 光环")
## 单次范围结算最多命中几个目标。必须设上限——否则敌人越密，范围武器的
## 实际 DPS 越高（一次打一片），会形成「怪越多我越强」的正反馈。
@export var max_targets: int = 4
@export var blade_count: int = 2
@export var orbit_speed: float = 2.6


func damage_at(level: int) -> float:
	return damage + damage_per_level * float(level - 1)


func cooldown_at(level: int) -> float:
	# 0.08 秒是硬下限：再快就变成每帧结算，画面和性能都会失控。
	return maxf(0.08, cooldown * pow(cooldown_per_level, float(level - 1)))


func range_at(level: int) -> float:
	return range + range_per_level * float(level - 1)


func area_radius_at(level: int) -> float:
	return area_radius + radius_per_level * float(level - 1)


func max_targets_at(level: int) -> int:
	return max_targets + int(floor(targets_per_level * float(level - 1)))


## 可增长数量（弹数 / 刀数）在指定等级下的值。
func count_at(base_count: int, level: int) -> int:
	if count_every <= 0:
		return base_count
	return base_count + (level - 1) / count_every


## 按 id 取共享原型。原型只读，运行期数值一律存在 Weapon 实例上。
static func by_id(weapon_id: String) -> WeaponData:
	match weapon_id:
		"pistol":
			return pistol()
		"blade":
			return blade()
		"aura":
			return aura()
	push_warning("WeaponData: 未知武器 id「%s」" % weapon_id)
	return null


## 初始武器：单发直线弹，自动瞄准最近的敌人。
## 成长偏「弹数」而不是纯伤害：3 级起双发，5 级三发，视觉变化比数字更明显。
static func pistol() -> WeaponData:
	var data := WeaponData.new()
	data.id = "pistol"
	data.display_name = "手枪"
	data.blurb = "自动瞄准最近敌人的直线弹，稳定且不挑站位"
	data.kind = Kind.PROJECTILE
	data.damage = 5.0
	data.damage_per_level = 1.4
	data.cooldown = 0.5
	data.cooldown_per_level = 0.94
	data.range = 420.0
	data.range_per_level = 22.0
	# 660 而不是 480：子弹太慢时，横向移动的敌人能轻易躲开，手感像在打空气。
	data.projectile_speed = 660.0
	data.projectiles_per_shot = 1
	data.count_every = 2
	data.spread_degrees = 11.0
	data.knockback = 130.0
	data.color = Color(0.99, 0.93, 0.45)
	return data


## 回旋刀：刀刃环绕玩家，周期性切割圈内敌人。
## 成长偏「刀数 + 目标数」，定位是清贴身怪，不跟圣光抢打群。
static func blade() -> WeaponData:
	var data := WeaponData.new()
	data.id = "blade"
	data.display_name = "回旋刀"
	data.blurb = "刀刃贴身环绕，专门清掉糊在脸上的怪"
	data.kind = Kind.ORBIT
	data.damage = 4.0
	data.damage_per_level = 1.1
	data.cooldown = 0.22
	data.cooldown_per_level = 0.97
	data.area_radius = 76.0
	data.radius_per_level = 6.0
	data.max_targets = 3
	data.targets_per_level = 0.5
	data.blade_count = 2
	data.count_every = 3
	data.orbit_speed = 3.0
	# 持续接触式输出，击退给大了会把怪弹出自己的刀刃范围，等于自己减 DPS。
	data.knockback = 55.0
	data.color = Color(0.86, 0.62, 1.0)
	return data


## 圣光：以玩家为圆心的脉冲，频率低但范围大、一次打一片。
static func aura() -> WeaponData:
	var data := WeaponData.new()
	data.id = "aura"
	data.display_name = "圣光"
	data.blurb = "周期性大范围脉冲，被围住时能一次撕开缺口"
	data.kind = Kind.AURA
	data.damage = 3.0
	data.damage_per_level = 1.3
	data.cooldown = 0.6
	data.cooldown_per_level = 0.96
	data.area_radius = 130.0
	data.radius_per_level = 13.0
	data.max_targets = 6
	data.targets_per_level = 1.0
	data.knockback = 40.0
	data.color = Color(0.55, 0.95, 0.85)
	return data
