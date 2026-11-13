# 2D 物理层的集中定义。层号写死成整数会在多处引用时对不上，
# 统一在这里改，project.godot 的 [layer_names] 只是给编辑器看的名字。
class_name PhysicsLayers
extends RefCounted

## 玩家身体所在的层（当前只有「软阻挡」用到，敌人不与之物理碰撞）。
const PLAYER: int = 1 << 0
## 敌人所在的层：敌人之间互相碰撞，形成肉墙。
const ENEMY: int = 1 << 1
## 障碍层：墓室碎石 / 石墩。敌人(物理体)靠 move_and_slide 自然绕开，
## 玩家(纯 Node2D)由 Game 手动把坐标推出障碍圆。投射物只查 ENEMY 层，飞过碎石不受影响。
const OBSTACLE: int = 1 << 2
