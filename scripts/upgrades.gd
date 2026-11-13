# 强化池：分「数值强化」与「武器」两类，按 id 分发效果。
#
# 武器项是动态生成的：未解锁 → 提供解锁；已解锁未满级 → 提供升一级；满级 → 不再出现。
# 早期版本会把已拥有的武器直接过滤掉，等于玩家越到后期能选的东西越少，
# 重复抽到同一把武器只能白白浪费一个选项位。
class_name Upgrades
extends RefCounted

## 数值强化池。id 必须与 Player.UPGRADE_CAPS 的键保持一致。
const POOL: Array[Dictionary] = [
	{
		"id": "damage",
		"title": "锐化弹头  +2 伤害",
		"desc": "所有武器伤害提升，之后解锁的武器同样生效",
	},
	{
		"id": "fire_rate",
		"title": "快速装填  -15% 冷却",
		"desc": "所有武器攻击间隔缩短",
	},
	{
		"id": "max_hp",
		"title": "强健体魄  +20 生命上限",
		"desc": "上限提升并立即回复 20 点生命",
	},
	{
		"id": "move_speed",
		"title": "轻装疾行  +25 移速",
		"desc": "跑得更快，更容易拉开包围圈",
	},
	{
		"id": "range",
		"title": "射程校准  +70 射程",
		"desc": "投射物打得更远，范围武器的圈也更大",
	},
	{
		"id": "magnet",
		"title": "经验磁场  +45 拾取范围",
		"desc": "更远的经验宝石会被吸过来",
	},
]


## 随机抽取 count 个可选强化：已满层的数值强化、已满级的武器会被过滤掉。
static func pick_random(count: int, target: Player) -> Array[Dictionary]:
	var available: Array[Dictionary] = []
	for option: Dictionary in POOL:
		var option_id: String = String(option["id"])
		if target != null and not target.can_upgrade(option_id):
			continue
		var entry: Dictionary = option.duplicate()
		entry["detail"] = detail_for(option_id, target) + _level_suffix(option_id, target)
		available.append(entry)

	var has_locked_weapon: bool = false
	if target != null:
		for weapon_id: String in WeaponData.ALL_IDS:
			var prototype: WeaponData = WeaponData.by_id(weapon_id)
			if prototype == null:
				continue
			var owned: Weapon = target.find_weapon(weapon_id)
			if owned != null:
				if owned.can_level_up():
					available.append(_weapon_option(prototype, owned.level + 1, target))
			elif target.weapons.size() < target.max_weapons:
				has_locked_weapon = true
				available.append(_weapon_option(prototype, 1, target))

	available.shuffle()
	var picked: Array[Dictionary] = []
	for i in mini(count, available.size()):
		picked.append(available[i])

	# 保底只补「未解锁的武器」，不补「武器升级」：升级是锦上添花，解锁新武器
	# 才是 DPS 台阶。纯随机下连抽数值强化，只有手枪的玩家一分钟内就会被围死。
	if has_locked_weapon and not picked.is_empty():
		var unlock: Dictionary = {}
		for entry: Dictionary in available:
			if int(entry.get("next_level", 0)) == 1:
				unlock = entry
				break
		if not unlock.is_empty():
			var already_offered: bool = false
			for entry: Dictionary in picked:
				if String(entry["id"]) == String(unlock["id"]):
					already_offered = true
					break
			if not already_offered:
				# 顶到第一位：保底选项必须显眼，放在末尾等于没保底。
				picked.remove_at(picked.size() - 1)
				picked.insert(0, unlock)
	return picked


## 构造一条武器选项。next_level 为 1 表示解锁，否则表示升到该级。
static func _weapon_option(prototype: WeaponData, next_level: int, target: Player) -> Dictionary:
	var owned: Weapon = target.find_weapon(prototype.id)
	var title: String = ""
	if owned == null:
		title = "解锁武器 · %s" % prototype.display_name
	else:
		title = "%s  Lv%d → Lv%d" % [prototype.display_name, owned.level, next_level]
	return {
		"id": "weapon_" + prototype.id,
		"title": title,
		"desc": prototype.blurb,
		"detail": _weapon_detail(prototype, next_level, target, owned),
		"weapon_id": prototype.id,
		"next_level": next_level,
	}


static func _weapon_detail(prototype: WeaponData, next_level: int, target: Player,
		owned: Weapon) -> String:
	var damage_now: float = prototype.damage_at(next_level) + target.global_damage_bonus
	var cooldown_now: float = prototype.cooldown_at(next_level) * target.global_cooldown_scale
	var text: String = ""
	if owned == null:
		text = "伤害 %.1f    冷却 %.2fs" % [damage_now, cooldown_now]
	else:
		text = "伤害 %.1f → %.1f    冷却 %.2fs → %.2fs" % [
			owned.damage, damage_now, owned.cooldown, cooldown_now]

	match prototype.kind:
		WeaponData.Kind.PROJECTILE:
			var shots: int = prototype.count_at(prototype.projectiles_per_shot, next_level)
			if shots > 1:
				text += "    弹数 %d" % shots
		WeaponData.Kind.ORBIT:
			text += "    刀数 %d" % prototype.count_at(prototype.blade_count, next_level)
		WeaponData.Kind.AURA:
			text += "    半径 %d    目标 %d" % [
				int(prototype.area_radius_at(next_level)), prototype.max_targets_at(next_level)]
	return text


## 显示"这是第几层"，让玩家知道某项强化快满层了。
static func _level_suffix(option_id: String, target: Player) -> String:
	if target == null or not is_instance_valid(target):
		return ""
	if not Player.UPGRADE_CAPS.has(option_id):
		return ""
	var next_level: int = target.upgrade_level(option_id) + 1
	return "    第 %d/%d 层" % [next_level, int(Player.UPGRADE_CAPS[option_id])]


## 生成"当前值 → 选择后"的差异说明，让玩家能直观判断选项价值。
static func detail_for(option_id: String, target: Player) -> String:
	if target == null or not is_instance_valid(target):
		return ""
	var weapon: Weapon = null
	if not target.weapons.is_empty():
		weapon = target.weapons[0]

	match option_id:
		"damage":
			if weapon != null:
				# +2 是基础值加成，最终伤害还要过一遍角色倍率 —— 张起灵看到的是
				# +2.36 而不是 +2，这里不按倍率显示就等于给了个假数字。
				var gain: float = 2.0 * target.damage_multiplier
				return "主武器伤害 %.1f → %.1f（新武器同享）" % [weapon.damage, weapon.damage + gain]
		"fire_rate":
			if weapon != null:
				var now: float = weapon.cooldown
				return "攻击间隔 %.2fs → %.2fs" % [now, maxf(0.08, now * 0.85)]
		"range":
			if weapon != null:
				return "射程 %.0f → %.0f" % [weapon.reach, weapon.reach + 70.0]
		"max_hp":
			return "生命上限 %d → %d" % [int(target.max_health), int(target.max_health) + 20]
		"move_speed":
			return "移动速度 %d → %d" % [int(target.move_speed), int(target.move_speed) + 25]
		"magnet":
			return "拾取范围 %d → %d" % [int(target.pickup_radius), int(target.pickup_radius) + 45]
	return ""


## 按 id 施加强化；未知 id 只警告，不中断游戏。
static func apply(id: String, target: Player) -> void:
	if target == null or not is_instance_valid(target):
		return

	# 武器项用 "weapon_<id>" 前缀区分，与数值强化的 id 空间互不重叠。
	if id.begins_with("weapon_"):
		var weapon_id: String = id.trim_prefix("weapon_")
		if target.find_weapon(weapon_id) != null:
			if not target.upgrade_weapon(weapon_id):
				push_warning("Upgrades: 武器「%s」已满级，升级被忽略" % weapon_id)
		else:
			target.add_weapon(WeaponData.by_id(weapon_id))
		return

	# 数值强化记一层，满层后自动从选项池消失；武器解锁不占层数。
	if Player.UPGRADE_CAPS.has(id):
		target.record_upgrade(id)
	match id:
		"damage":
			# 写进玩家的全局加成而不是直接改武器数值：新解锁的武器也要吃到，
			# 否则「先解锁后强化」会比「先强化后解锁」明显更强。
			target.global_damage_bonus += 2.0
			target.recalc_weapons()
		"fire_rate":
			# 0.2 是乘算下限：八层之后仍有 20% 冷却，不至于变成每帧结算。
			target.global_cooldown_scale = maxf(0.2, target.global_cooldown_scale * 0.85)
			target.recalc_weapons()
		"range":
			target.global_range_bonus += 70.0
			target.recalc_weapons()
		"max_hp":
			target.max_health += 20.0
			target.heal(20.0)
		"move_speed":
			target.move_speed += 25.0
		"magnet":
			target.pickup_radius += 45.0
		_:
			push_warning("Upgrades: 未知强化 id「%s」" % id)
