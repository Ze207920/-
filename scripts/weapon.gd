# 武器运行时：挂在玩家节点下，按 WeaponData 描述执行攻击。
# 索敌与命中都通过「enemies」分组完成，不需要主场景传入敌人列表。
#
# 数值分三层：WeaponData（基础值）→ level（等级成长）→ 玩家全局加成。
# 任何一层变化都调 recalc() 整体重算，绝不在旧值上累加 —— 否则升级顺序不同
# 会算出不同结果，同一个等级在两条路线上强度不一致。
class_name Weapon
extends Node2D

var data: WeaponData = null
var level: int = 1
var owner_player: Player = null

# 以下为 recalc() 算出的最终数值，攻击逻辑只读这些字段。
var damage: float = 0.0
var cooldown: float = 0.5
var reach: float = 420.0
var area_radius: float = 70.0
var max_targets: int = 4
var blade_count: int = 2
var projectiles: int = 1
var knockback: float = 0.0

var _timer: float = 0.0
var _orbit_angle: float = 0.0
var _blade_points: PackedVector2Array = []


func setup(weapon_data: WeaponData, start_level: int = 1) -> void:
	data = weapon_data
	level = clampi(start_level, 1, WeaponData.MAX_LEVEL)
	owner_player = get_parent() as Player
	recalc()
	# 装备即开火一次，避免刚解锁时要空等一个冷却
	_timer = cooldown
	queue_redraw()


## 整体重算最终数值。等级提升、玩家获得全局强化、装备新武器时都会调用。
func recalc() -> void:
	if data == null:
		return
	var bonus_damage: float = 0.0
	var cooldown_scale: float = 1.0
	var bonus_range: float = 0.0
	var damage_scale: float = 1.0
	if is_instance_valid(owner_player):
		bonus_damage = owner_player.global_damage_bonus
		# 角色固有的攻速差异与技能增益是两次独立的乘算：增益到期时只还原
		# skill_cooldown_scale，角色本身的快慢不会被顺手抹掉。
		cooldown_scale = owner_player.global_cooldown_scale \
				* owner_player.cooldown_multiplier * owner_player.skill_cooldown_scale
		bonus_range = owner_player.global_range_bonus
		damage_scale = owner_player.damage_multiplier

	damage = (data.damage_at(level) + bonus_damage) * damage_scale
	cooldown = maxf(0.08, data.cooldown_at(level) * cooldown_scale)
	reach = data.range_at(level) + bonus_range
	# 范围半径跟射程加成的比例是 18/70：射程强化对近身武器同样有效，
	# 但不能直接把 +70 像素的射程当成 +70 像素的圈，那样范围武器会膨胀得离谱。
	area_radius = data.area_radius_at(level) + bonus_range * (18.0 / 70.0)
	max_targets = data.max_targets_at(level)
	blade_count = data.count_at(data.blade_count, level)
	projectiles = data.count_at(data.projectiles_per_shot, level)
	knockback = data.knockback
	queue_redraw()


func can_level_up() -> bool:
	return data != null and level < WeaponData.MAX_LEVEL


func display_name() -> String:
	return data.display_name if data != null else "武器"


func _physics_process(delta: float) -> void:
	if data == null:
		return

	if data.kind == WeaponData.Kind.ORBIT:
		_orbit_angle += data.orbit_speed * delta
		_update_blades()
		queue_redraw()

	_timer += delta
	if _timer < cooldown:
		return
	_timer = 0.0

	match data.kind:
		WeaponData.Kind.PROJECTILE:
			_fire_projectiles()
		WeaponData.Kind.AURA:
			_damage_in_radius(global_position, area_radius)
		WeaponData.Kind.ORBIT:
			_damage_in_radius(global_position, area_radius + 14.0)


func _fire_projectiles() -> void:
	var target: Enemy = _nearest_enemy(reach)
	if target == null:
		return

	# 提前量预判：按目标当前速度往前瞄。
	# 不做预判时，敌人每秒横移 100 像素，子弹飞 0.8 秒就偏出 80 像素，
	# 而命中半径只有 5+13=18 —— 远距离射击几乎全空，DPS 全靠贴脸。
	var muzzle: Vector2 = global_position
	var bullet_speed: float = maxf(1.0, data.projectile_speed)
	var aim_point: Vector2 = target.global_position
	for i in 2:
		var flight: float = muzzle.distance_to(aim_point) / bullet_speed
		aim_point = target.global_position + target.velocity * flight
	var base_direction: Vector2 = (aim_point - muzzle).normalized()

	var count: int = maxi(1, projectiles)
	var spread: float = deg_to_rad(data.spread_degrees)

	for i in count:
		var offset: float = 0.0
		if count > 1:
			offset = spread * (float(i) / float(count - 1) - 0.5)
		var projectile := Projectile.new()
		projectile.velocity = base_direction.rotated(offset) * data.projectile_speed
		projectile.damage = damage
		projectile.knockback = knockback
		projectile.life = data.projectile_life
		projectile.color = data.color
		var world: Node = _world()
		world.add_child(projectile)
		projectile.global_position = muzzle
	# 有目标才响：射程内空无一物却听到开枪声会很假。
	AudioManager.play("shoot")


func _damage_in_radius(center: Vector2, radius: float) -> void:
	# 先收集范围内目标，按距离近的优先，只结算前 max_targets 个。
	# 不设上限时敌人越密 DPS 越高，等于奖励「被围」。
	var in_range: Array[Enemy] = []
	var distances: Array[float] = []
	for node: Node in get_tree().get_nodes_in_group("enemies"):
		var enemy := node as Enemy
		if enemy == null or not is_instance_valid(enemy) or enemy.is_queued_for_deletion():
			continue
		var hit_reach: float = radius + enemy.radius
		var distance: float = center.distance_squared_to(enemy.global_position)
		if distance <= hit_reach * hit_reach:
			in_range.append(enemy)
			distances.append(distance)

	var limit: int = mini(max_targets, in_range.size())
	if limit <= 0:
		return
	# 目标数通常只有个位数，插入排序比排序整个数组更省
	for i in range(1, in_range.size()):
		var key_enemy: Enemy = in_range[i]
		var key_distance: float = distances[i]
		var j: int = i - 1
		while j >= 0 and distances[j] > key_distance:
			in_range[j + 1] = in_range[j]
			distances[j + 1] = distances[j]
			j -= 1
		in_range[j + 1] = key_enemy
		distances[j + 1] = key_distance

	for i in limit:
		if is_instance_valid(in_range[i]):
			in_range[i].take_damage(damage)
			# 从爆点向外推。用命中的那一只自己的位置算方向，所以站在正中心的敌人
			# 方向为零向量（不推动），不会出现原地随机乱弹。
			in_range[i].apply_knockback(in_range[i].global_position - center, knockback)
	# 一次挥击/一次光环只响一声，而不是按命中数量叠加。范围武器每次挥出都打
	# 三到十个目标，逐个播会瞬间把音效池占满，还盖掉真正的命中层次。
	AudioManager.play("hit")


## 找射程内最近的、还活着的敌人。已排队释放的不算 —— 否则子弹会朝一具
## 本帧刚死、下一帧就消失的尸体飞过去，白白浪费一发。
func _nearest_enemy(max_range: float) -> Enemy:
	var best: Enemy = null
	var best_distance: float = max_range * max_range
	for node: Node in get_tree().get_nodes_in_group("enemies"):
		var enemy := node as Enemy
		if enemy == null or not is_instance_valid(enemy) or enemy.is_queued_for_deletion():
			continue
		var distance: float = global_position.distance_squared_to(enemy.global_position)
		if distance < best_distance:
			best_distance = distance
			best = enemy
	return best


func _update_blades() -> void:
	_blade_points.clear()
	var count: int = maxi(1, blade_count)
	for i in count:
		var angle: float = _orbit_angle + TAU * float(i) / float(count)
		_blade_points.append(Vector2(cos(angle), sin(angle)) * area_radius)


## 场景根节点：投射物要挂在世界层而不是玩家身上，否则会跟着玩家一起动。
func _world() -> Node:
	var node: Node = self
	while node.get_parent() != null and node.get_parent() != get_tree().root:
		node = node.get_parent()
	return node


func _draw() -> void:
	if data == null:
		return
	match data.kind:
		WeaponData.Kind.ORBIT:
			for point: Vector2 in _blade_points:
				draw_circle(point, 9.0, data.color)
				draw_circle(point, 4.0, Color(1.0, 1.0, 1.0, 0.75))
		WeaponData.Kind.AURA:
			var fill: Color = data.color
			fill.a = 0.08
			draw_circle(Vector2.ZERO, area_radius, fill)
			draw_arc(Vector2.ZERO, area_radius, 0.0, TAU, 48, data.color, 2.0, true)
