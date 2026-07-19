extends Area3D

# ============================================================
#  チェイス（コタの帽子）- 完全オリジナル
#  青い帽子＋黄色い星マーク。Eで前方へ投げると、少し飛んで空中で
#  一瞬ホバリングし、ブーメランのようにコタへ戻ってくる。
#  当たり判定（Area3D）を持ち、コタムーンに当たると回収できる（機能4で接続）。
#  ※オデッセイの帽子の“仕組み”だけを参考にしたオリジナル。任天堂の
#    キャラ・名称・デザインは一切使っていない。
# ============================================================

@export var throw_speed: float = 16.0    # 投げ出しの速さ
@export var out_time: float = 0.35        # 前方へ飛ぶ時間（秒）
@export var hover_time: float = 0.25      # 空中でホバリングする時間（秒）
@export var return_speed: float = 18.0    # コタへ戻る速さ
@export var catch_distance: float = 1.0   # この距離まで戻ったら“キャッチ”して消える
@export var spin_speed: float = 25.0      # くるくる回る見た目の速さ

enum Phase { OUT, HOVER, RETURN }
var phase: int = Phase.OUT
var phase_timer: float = 0.0
var dir: Vector3 = Vector3.FORWARD
var kota: Node3D = null                    # 戻る先（コタ本体）
var active: bool = false


func _ready() -> void:
	_add_star()                            # 黄色い星マークを付ける


# プレイヤーから呼ばれる：投げ開始
func throw(start_pos: Vector3, direction: Vector3, owner_kota: Node3D) -> void:
	global_position = start_pos
	dir = direction.normalized()
	kota = owner_kota
	phase = Phase.OUT
	phase_timer = out_time
	active = true


func _physics_process(delta: float) -> void:
	if not active:
		return

	rotate_y(spin_speed * delta)           # くるくる回る

	match phase:
		Phase.OUT:
			global_position += dir * throw_speed * delta
			phase_timer -= delta
			if phase_timer <= 0.0:
				phase = Phase.HOVER
				phase_timer = hover_time
		Phase.HOVER:
			phase_timer -= delta            # 空中で一瞬止まる
			if phase_timer <= 0.0:
				phase = Phase.RETURN
		Phase.RETURN:
			if kota == null or not is_instance_valid(kota):
				queue_free()
				return
			var target: Vector3 = kota.global_position + Vector3(0.0, 1.0, 0.0)
			var to_kota: Vector3 = target - global_position
			if to_kota.length() <= catch_distance:
				queue_free()                # コタに戻ってきたら消える
				return
			global_position += to_kota.normalized() * return_speed * delta


# 黄色い5つの星マークを手続きで作って帽子に貼る（外部素材を使わないオリジナル）
func _add_star() -> void:
	var pts: int = 5
	var outer: float = 0.18
	var inner: float = 0.08
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rim: Array = []
	for i in range(pts * 2):
		var r: float = outer if i % 2 == 0 else inner
		var ang: float = PI / 2.0 + float(i) * PI / float(pts)   # 上向きの1点から
		rim.append(Vector3(cos(ang) * r, sin(ang) * r, 0.0))
	for i in range(pts * 2):
		st.add_vertex(Vector3.ZERO)
		st.add_vertex(rim[i])
		st.add_vertex(rim[(i + 1) % (pts * 2)])
	var star_mesh: ArrayMesh = st.commit()

	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.mesh = star_mesh
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.85, 0.1)                      # 黄色い星
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED       # 常にはっきり黄色
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED                  # 裏からも見える
	mi.material_override = mat
	mi.position = Vector3(0.0, 0.18, 0.32)                        # 帽子の前面あたり
	add_child(mi)
