# 投射物：直线飞行，用物理宽相查询命中敌人，命中后立即销毁。
# 不用遍历 enemies 分组：同屏敌人上百时，每颗子弹每帧扫一遍全表是纯浪费，
# 而物理服务器已经维护好了空间索引，直接问「我这一小块里有什么」快得多。
class_name Projectile
extends Node2D

var velocity: Vector2 = Vector2.ZERO
var damage: float = 1.0
var knockback: float = 0.0
var life: float = 1.6
var color: Color = Color(0.99, 0.93, 0.45)
var hit_radius: float = 5.0:
	set(value):
		hit_radius = value
		if _shape != null:
			_shape.radius = value

var _shape: CircleShape2D = null
var _query: PhysicsShapeQueryParameters2D = null


func _ready() -> void:
	_shape = CircleShape2D.new()
	_shape.radius = hit_radius
	_query = PhysicsShapeQueryParameters2D.new()
	_query.shape = _shape
	_query.collision_mask = PhysicsLayers.ENEMY
	_query.collide_with_bodies = true
	_query.collide_with_areas = false


func _physics_process(delta: float) -> void:
	global_position += velocity * delta
	life -= delta
	if life <= 0.0:
		queue_free()
		return

	var enemy: Enemy = _hit_enemy()
	if enemy == null:
		return
	# 先记下飞行方向：命中后本节点立刻销毁，之后再想取 velocity 就来不及了。
	var impact_direction: Vector2 = velocity.normalized()
	enemy.take_damage(damage)
	enemy.apply_knockback(impact_direction, knockback)
	AudioManager.play("hit")
	queue_free()


func _hit_enemy() -> Enemy:
	if _query == null:
		return null
	_query.transform = Transform2D(0.0, global_position)
	var hits: Array[Dictionary] = get_world_2d().direct_space_state.intersect_shape(_query, 4)
	for hit: Dictionary in hits:
		var enemy := hit.get("collider") as Enemy
		if enemy != null and is_instance_valid(enemy) and not enemy.is_queued_for_deletion():
			return enemy
	return null


func _draw() -> void:
	draw_circle(Vector2.ZERO, hit_radius, color)
