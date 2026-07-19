extends CharacterBody3D

# ============================================================
#  コタオデッセイ - プレイヤー操作
#  2段・3段ジャンプ（オデッセイ風）:
#    着地後の受付時間（combo_time）内に跳ぶと段が上がる。
#    1段 → 2段（高い）→ 3段（もっと高い＋前方宙返り）。
#
#  ★重要な直し（着地が検出できなかったバグ）:
#    was_on_floor を「move_and_slide の前」に記録し、
#    着地判定を「move_and_slide の後」で行う。
#    以前は move_and_slide の後に was_on_floor を記録していたため、
#    次フレーム冒頭では is_on_floor() と was_on_floor が常に一致し、
#    「着地した瞬間（is_on_floor and not was_on_floor）」が
#    2フレーム目以降ずっと成立せず、コンボ受付が二度と開かなかった。
# ============================================================

# ── 動きの数値 ──
@export var walk_speed: float = 5.0
@export var dash_speed: float = 8.0
@export var jump_velocity: float = 8.0
@export var gravity: float = 20.0
@export var accel: float = 40.0
@export var air_control: float = 0.3
@export var turn_speed: float = 12.0

# ── 2段・3段ジャンプ ──
@export var jump2_mult: float = 1.3        # 2段目の高さ倍率
@export var jump3_mult: float = 1.6        # 3段目の高さ倍率
@export var combo_time: float = 0.6        # 着地後、次の段を受け付ける時間（秒）
@export var flip_time: float = 0.5         # 3段目の1回転にかかる時間（秒）

# ── ゆとり時間 ──
@export var coyote_time: float = 0.1
@export var jump_buffer_time: float = 0.15

# ── ヒップドロップ（Ctrl）──
@export var hip_freeze_time: float = 0.12   # 発動後、空中でピタッと止まる時間（秒）
@export var hip_drop_speed: float = 30.0    # 真下への落下速度（大きいほど速い）
@export var hip_land_time: float = 0.25     # 着地でドンと止まる硬直の時間（秒）

# ── ダイブ（左クリック）──
@export var dive_speed: float = 12.0        # 前方へ飛び込む速さ
@export var dive_up: float = 4.0            # 飛び込むときに少し上へ跳ねる量
@export var dive_slide_friction: float = 18.0  # 着地後、滑って止まる強さ（大きいほど早く止まる）
@export var dive_getup_time: float = 0.45   # 着地→滑って起き上がるまでの時間（秒）
@export var dive_pitch: float = 80.0        # 飛び込み姿勢の前傾（度）

# ── デバッグ ──
@export var debug_jump: bool = true        # 実機でログを見たいとき true

# ── カメラ ──
@export var mouse_sensitivity: float = 0.003

@onready var camera_pivot: Node3D = $CameraPivot
@onready var mesh: MeshInstance3D = $MeshInstance3D

# ── 内部変数 ──
var coyote_timer: float = 0.0
var jump_buffer_timer: float = 0.0
var jump_phase: int = 0
var combo_timer: float = 0.0
var flip_timer: float = 0.0

# ── ヒップドロップの状態 ──
# NONE=通常 / FREEZE=空中で静止中 / FALL=高速落下中 / LAND=着地硬直中
enum HipState { NONE, FREEZE, FALL, LAND }
var hip_state: int = HipState.NONE
var hip_timer: float = 0.0

# ── ダイブの状態 ──
# NONE=通常 / DIVE=飛び込み中（空中）/ SLIDE=着地して滑って起き上がり中
enum DiveState { NONE, DIVE, SLIDE }
var dive_state: int = DiveState.NONE
var dive_timer: float = 0.0
var dive_requested: bool = false            # 左クリックされたフレームに立てる


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		camera_pivot.rotation.y -= event.relative.x * mouse_sensitivity
		camera_pivot.rotation.x -= event.relative.y * mouse_sensitivity
		camera_pivot.rotation.x = clamp(camera_pivot.rotation.x, deg_to_rad(-60), deg_to_rad(30))
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return
	# 左クリックの役割を状況で分ける：
	#   マウス解放中（メニュー等）→ 画面に復帰（キャプチャ）※このクリックはダイブしない
	#   マウスキャプチャ中（プレイ中）→ ダイブ要求
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		elif Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			dive_requested = true


func _physics_process(delta: float) -> void:
	# ★ 前フレームの接地状態を、move_and_slide の前に記録しておく。
	#   （is_on_floor() は最後の move_and_slide の結果を返すので、
	#    ここでは「1フレーム前の着地状態」が入る。）
	var was_on_floor: bool = is_on_floor()

	# ── ヒップドロップ：発動（空中で Ctrl を押したときだけ。地上では出ない）──
	if Input.is_action_just_pressed("hip_drop") and hip_state == HipState.NONE \
			and dive_state == DiveState.NONE and not is_on_floor():
		hip_state = HipState.FREEZE
		hip_timer = hip_freeze_time
		velocity = Vector3.ZERO         # いったん空中でピタッと止める
		jump_phase = 0                  # ジャンプの段はリセット
		flip_timer = 0.0
		mesh.rotation.x = 0.0
		if debug_jump:
			print("▼ヒップドロップ：空中で静止…")

	# ── ヒップドロップ：状態を進める ──
	var hip_active: bool = hip_state != HipState.NONE
	if hip_state == HipState.FREEZE:
		velocity = Vector3.ZERO         # 止まっている間は完全静止（横も縦も）
		hip_timer -= delta
		if hip_timer <= 0.0:
			hip_state = HipState.FALL
			if debug_jump:
				print("▼高速落下！")
	elif hip_state == HipState.FALL:
		velocity.x = 0.0                # 落下中は横移動不可
		velocity.z = 0.0
		velocity.y = -hip_drop_speed    # 真下へ高速落下
	elif hip_state == HipState.LAND:
		velocity.x = 0.0                # 着地硬直中も横移動不可
		velocity.z = 0.0
		hip_timer -= delta
		if hip_timer <= 0.0:
			hip_state = HipState.NONE
			if debug_jump:
				print("▼ヒップドロップ終わり（動けます）")

	# 1) 重力（ヒップドロップ中は velocity.y を自前で制御するので切る）
	if not is_on_floor() and not hip_active:
		velocity.y -= gravity * delta

	# 2) コヨーテタイム
	if is_on_floor():
		coyote_timer = coyote_time
	else:
		coyote_timer -= delta

	# 3) 先行入力（ジャンプバッファ）
	if Input.is_action_just_pressed("jump"):
		jump_buffer_timer = jump_buffer_time
	else:
		jump_buffer_timer -= delta

	# 4) コンボ受付を減らす。地上で切れたら段数リセット
	combo_timer -= delta
	if is_on_floor() and combo_timer <= 0.0 and jump_phase != 0:
		jump_phase = 0
		if debug_jump:
			print("××× 受付時間切れ：段が 0 に戻りました（次のジャンプは1段目）")

	# 5) ジャンプ成立（ヒップドロップ中・ダイブ中は跳べない）
	if not hip_active and dive_state == DiveState.NONE and jump_buffer_timer > 0.0 and coyote_timer > 0.0:
		var combo_alive: float = combo_timer   # 判定に使った受付残り（ログ用）
		# 段アップ条件：着地後の受付が生きていて、まだ3段目でない
		if combo_timer > 0.0 and jump_phase >= 1 and jump_phase < 3:
			jump_phase += 1
		else:
			jump_phase = 1
		var vy: float = jump_velocity
		if jump_phase == 2:
			vy = jump_velocity * jump2_mult
		elif jump_phase == 3:
			vy = jump_velocity * jump3_mult
			flip_timer = flip_time
		velocity.y = vy
		jump_buffer_timer = 0.0
		coyote_timer = 0.0
		combo_timer = 0.0   # 使ったら受付を閉じる（同じ着地で二重に上がらない）
		if debug_jump:
			print("★ジャンプ！ 段=", jump_phase, "  強さ=", snappedf(vy, 0.1),
				"  （跳んだ時の受付残り=", snappedf(combo_alive, 0.01), "）")

	# 6) 入力方向をカメラ基準に変換
	var input_dir: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction: Vector3 = camera_pivot.global_transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)
	direction.y = 0.0
	if direction.length() > 0.01:
		direction = direction.normalized()
	else:
		direction = Vector3.ZERO

	# ── ダイブ：発動（左クリック。地上でも空中でもOK）──
	if dive_requested:
		dive_requested = false
		if dive_state == DiveState.NONE and hip_state == HipState.NONE:
			# 飛び込む向き：移動入力があればその方向、無ければ今カプセルが向いている方向
			var dive_dir: Vector3 = direction
			if dive_dir == Vector3.ZERO:
				dive_dir = Vector3(-sin(mesh.rotation.y), 0.0, -cos(mesh.rotation.y))
			dive_state = DiveState.DIVE
			velocity.x = dive_dir.x * dive_speed
			velocity.z = dive_dir.z * dive_speed
			velocity.y = dive_up
			mesh.rotation.y = atan2(-dive_dir.x, -dive_dir.z)
			mesh.rotation.x = deg_to_rad(-dive_pitch)   # 前傾（飛び込み姿勢）
			flip_timer = 0.0
			jump_phase = 0
			if debug_jump:
				print("→ダイブ！ 前方へ飛び込み")

	var dive_active: bool = dive_state != DiveState.NONE

	# 7) 速度（Shiftでダッシュ）
	var speed: float = dash_speed if Input.is_action_pressed("dash") else walk_speed
	var target: Vector3 = direction * speed

	# 8) 加速（状況で横移動の扱いを分ける）
	if hip_active:
		pass                                  # ヒップドロップ中は横移動しない（別処理済み）
	elif dive_state == DiveState.DIVE:
		pass                                  # ダイブ中は勢いを保つ（入力で曲げない）
	elif dive_state == DiveState.SLIDE:
		# 着地後：摩擦で滑って止まり、時間で起き上がる
		velocity.x = move_toward(velocity.x, 0.0, dive_slide_friction * delta)
		velocity.z = move_toward(velocity.z, 0.0, dive_slide_friction * delta)
		dive_timer -= delta
		if dive_timer <= 0.0:
			dive_state = DiveState.NONE
			mesh.rotation.x = 0.0             # 起き上がる
			if debug_jump:
				print("→起き上がり（動けます）")
	else:
		var a: float = accel * (1.0 if is_on_floor() else air_control)
		velocity.x = move_toward(velocity.x, target.x, a * delta)
		velocity.z = move_toward(velocity.z, target.z, a * delta)

	# 9) 見た目のカプセルを進行方向へ向ける（ヒップドロップ中・ダイブ中は向きを変えない）
	if direction != Vector3.ZERO and not hip_active and not dive_active:
		var target_angle: float = atan2(-direction.x, -direction.z)
		mesh.rotation.y = lerp_angle(mesh.rotation.y, target_angle, turn_speed * delta)

	# 10) 3段ジャンプの1回転
	if flip_timer > 0.0:
		flip_timer -= delta
		var t: float = 1.0 - max(flip_timer, 0.0) / flip_time
		mesh.rotation.x = -TAU * t
		if flip_timer <= 0.0:
			mesh.rotation.x = 0.0

	# 11) 動かす
	move_and_slide()

	# 12) ★ 着地した瞬間（move_and_slide の後で判定）→ コンボ受付を開く
	#     ここで was_on_floor（前フレーム）と、いまの is_on_floor()（今フレーム）を
	#     比べることで、「今フレームで着地した」立ち上がりを正しく取れる。
	if is_on_floor() and not was_on_floor:
		combo_timer = combo_time
		flip_timer = 0.0
		mesh.rotation.x = 0.0
		if debug_jump:
			print("--- 着地：ここから ", combo_time, " 秒以内に跳べば段アップ（今の段=", jump_phase, "）")
		# ヒップドロップの落下から着地したら「ドン」と硬直に入る
		if hip_state == HipState.FALL:
			hip_state = HipState.LAND
			hip_timer = hip_land_time
			velocity = Vector3.ZERO
			if debug_jump:
				print("▼ドン！着地硬直 ", hip_land_time, " 秒（この間は横移動できない）")
		# ダイブの飛び込みから着地したら「滑って起き上がる」に入る
		if dive_state == DiveState.DIVE:
			dive_state = DiveState.SLIDE
			dive_timer = dive_getup_time
			mesh.rotation.x = deg_to_rad(-dive_pitch)   # 滑っている間は前傾のまま
			if debug_jump:
				print("→着地して滑る…（", dive_getup_time, " 秒で起き上がる）")
