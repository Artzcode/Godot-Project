extends CharacterBody3D

# 🧠 Nós
@onready var Head = $Head
@onready var standing_collision_shape = $standing_collision_shape
@onready var crouching_collision_shape = $crouching_collision_shape
@onready var ray_cast_3d = $RayCast3D
@onready var visuals: Node3D = $visuals
@onready var camera: Camera3D = $Head/Camera3D

# Sons de passos
@onready var WalkStep: AudioStreamPlayer3D = $SFX/WalkStep
@onready var RunStep: AudioStreamPlayer3D = $SFX/RunStep

# Sons de respiração
@onready var RespireidleStep: AudioStreamPlayer3D = $SFX/RespireidleStep
@onready var RespiredLowStep: AudioStreamPlayer3D = $SFX/RespiredLowStep

# Animações
@onready var animation_tree: AnimationTree = $AnimationTree
@onready var animation_player: AnimationPlayer = $visuals/Rick/BASE/Skeleton3D/AnimationPlayer
var animation_state: AnimationNodeStateMachinePlayback

# 🎮 Movimento
var current_speed = 5.0
const walking_speed = 2.5
const sprinting_speed = 8.0
const crouching_speed = 2.0
const jump_velocity = 4.5

# 📐 Sensibilidade e interpolação
const mouse_sens = 0.003
var direction = Vector3.ZERO

# ↧ Agachar
var crouching_depth = -0.5
var base_head_height = 1.8

# 🔽 Inclinação máxima para ser considerado chão
const FLOOR_ANGLE := 50.0

# 👟 Head bobbing
var bob_timer = 0.0

# 🫁 Respiração
var breath_timer = 0.0
var breath_amplitude = 0.015
var breath_speed = 1.5

# Respiração intensa
var intense_breath_amplitude = 0.015
var run_timer = 0.0
const RUN_THRESHOLD = 5.0
const INTENSE_MAX_AMPLITUDE = 0.04
const INTENSE_DECAY_RATE = 0.5

# Controle de respiração corrida
const RUN_BREATH_DELAY = 8.0
var run_breath_started = false

# 🎥 Tilt lateral ao correr
var tilt_timer = 0.0
var camera_tilt_z = 0.0
const max_tilt_angle = deg_to_rad(10)
const tilt_smooth_speed = 8.0

# 📐 Controle de rotação da câmera
var yaw := 0.0
var pitch := 0.5

# FOV cinematográfico
var default_fov = 70.0
var run_fov = 90.0
var fov_lerp_speed = 6.0

# Fade de áudio
const FADE_TIME = 0.3

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	floor_max_angle = deg_to_rad(FLOOR_ANGLE)

	animation_tree.active = true
	animation_state = animation_tree.get("parameters/playback")
	animation_player.root_motion_track = NodePath("")

	RespireidleStep.volume_db = -80
	RespireidleStep.play()
	RespiredLowStep.volume_db = -80
	RespiredLowStep.play()

	camera.fov = default_fov


func _input(event):
	if event is InputEventMouseMotion:
		yaw -= event.relative.x * mouse_sens
		pitch -= event.relative.y * mouse_sens
		pitch = clamp(pitch, deg_to_rad(-85), deg_to_rad(60))

		rotation.y = yaw
		Head.rotation.x = pitch

		var target_tilt = clamp(-event.relative.x * 0.03, -max_tilt_angle, max_tilt_angle)
		camera_tilt_z = lerp(camera_tilt_z, target_tilt, get_process_delta_time() * tilt_smooth_speed)


func _physics_process(delta: float) -> void:
	# 🏃 Movimento e velocidade
	if Input.is_action_pressed("ui_Crounch"):
		current_speed = crouching_speed
		base_head_height = 1.8 + crouching_depth
		standing_collision_shape.disabled = true
		crouching_collision_shape.disabled = false
	else :
		if not ray_cast_3d.is_colliding():
			current_speed = walking_speed
			base_head_height = 1.8
			standing_collision_shape.disabled = false
			crouching_collision_shape.disabled = true

			if Input.is_action_pressed("ui_shift"):
				current_speed = sprinting_speed

	if not is_on_floor():
		velocity.y += get_gravity().y * delta

	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = jump_velocity

	# Entrada direcional
	var input_vec := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	direction = (transform.basis * Vector3(input_vec.x, 0, input_vec.y)).normalized()

	if direction.length() > 0:
		velocity.x = direction.x * current_speed
		velocity.z = direction.z * current_speed
	else:
		velocity.x = move_toward(velocity.x, 0, current_speed)
		velocity.z = move_toward(velocity.z, 0, current_speed)

	# 🟢 BlendSpace2D suave usando lerp para Vector2
	var blend_pos = input_vec
	if Input.is_action_pressed("ui_shift"):
		blend_pos *= 1.0
	else:
		blend_pos *= 0.5

	var current_blend: Vector2 = animation_tree.get("parameters/Moviments/blend_position")
	var new_blend = Vector2(
		lerp(current_blend.x, blend_pos.x, delta * 5.0),
		lerp(current_blend.y, blend_pos.y, delta * 5.0)
	)
	animation_tree.set("parameters/Moviments/blend_position", new_blend)

	# Só troca de estado se necessário
	if animation_state.get_current_node() != "Moviments":
		animation_state.travel("Moviments")

	# 🟢 FOV e corrida
	var is_running = Input.is_action_pressed("ui_shift") and direction.length() > 0.1 and is_on_floor()
	if is_running:
		camera.fov = lerp(camera.fov, run_fov, delta * fov_lerp_speed)
	else:
		camera.fov = lerp(camera.fov, default_fov, delta * fov_lerp_speed)

	# Respiração intensa
	if is_running:
		run_timer += delta
		if run_timer > RUN_THRESHOLD:
			intense_breath_amplitude = lerp(intense_breath_amplitude, INTENSE_MAX_AMPLITUDE, delta * 2.0)
	else:
		run_timer = 0.0
		intense_breath_amplitude = lerp(intense_breath_amplitude, breath_amplitude, delta * INTENSE_DECAY_RATE)

	if is_running and run_timer >= RUN_BREATH_DELAY:
		run_breath_started = true
	else:
		run_breath_started = false

	# 🎧 Sons de passos
	if is_on_floor() and direction.length() > 0.1:
		if is_running:
			if not RunStep.playing:
				RunStep.play()
			if WalkStep.playing:
				WalkStep.stop()
		else:
			if not WalkStep.playing:
				WalkStep.play()
			if RunStep.playing:
				RunStep.stop()
	else:
		if WalkStep.playing:
			WalkStep.stop()
		if RunStep.playing:
			RunStep.stop()

	# 🎧 Respiração
	if run_breath_started:
		_fade_audio(RespireidleStep, false, delta)
		_fade_audio(RespiredLowStep, true, delta)
	else:
		_fade_audio(RespireidleStep, true, delta)
		_fade_audio(RespiredLowStep, false, delta)

	# 👟 Bobbing e respiração
	if is_on_floor():
		if direction.length() > 0.1:
			var bob_amp = 0.0
			var bob_spd = 0.0
			var tilt_amp = 0.0

			if is_running:
				bob_amp = 0.05
				bob_spd = 9.0
				tilt_amp = 1.5
			else:
				bob_amp = 0.008
				bob_spd = 3.0
				tilt_amp = 0.3

			bob_timer += delta * bob_spd
			var offset = sin(bob_timer) * bob_amp
			Head.position.y = lerp(Head.position.y, base_head_height + offset, delta * 10.0)

			tilt_timer += delta * 10.0
			var tilt = sin(tilt_timer) * deg_to_rad(tilt_amp)
			Head.rotation.z = lerp(Head.rotation.z, tilt + camera_tilt_z, delta * 8.0)
		else:
			breath_timer += delta * breath_speed
			var offset = sin(breath_timer) * intense_breath_amplitude
			Head.position.y = lerp(Head.position.y, base_head_height + offset, delta * 5.0)
			Head.rotation.z = lerp(Head.rotation.z, camera_tilt_z, delta * 10.0)
	else:
		Head.position.y = lerp(Head.position.y, base_head_height, delta * 10.0)
		Head.rotation.z = lerp(Head.rotation.z, camera_tilt_z, delta * 10.0)

	move_and_slide()


# Função de fade de áudio
func _fade_audio(player: AudioStreamPlayer3D, fade_in: bool, delta: float) -> void:
	var volume_step = 80.0 / FADE_TIME * delta
	if fade_in:
		player.volume_db = clamp(player.volume_db + volume_step, -80, 0)
	else:
		player.volume_db = clamp(player.volume_db - volume_step, -80, 0)
