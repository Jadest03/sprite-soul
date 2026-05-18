extends Node2D

signal reset_requested

const CompanionFSM = preload("res://scripts/CompanionFSM.gd")
const EmotionState = preload("res://scripts/EmotionState.gd")
const BehaviorSelector = preload("res://scripts/BehaviorSelector.gd")

const WALK_SPEED = 60.0
const MOUSE_NEAR_DISTANCE = 80.0
const EDGE_LEAN_THRESHOLD = 35.0

# 실제 스프라이트 vs placeholder에 따라 _ready에서 결정
var SPRITE_SCALE := Vector2(5.0, 5.0)
var SPRITE_HALF  := Vector2(40.0, 50.0)

const STATE_COLORS = {
	"idle":  Color(1.0, 0.85, 0.2),
	"walk":  Color(0.3, 0.6, 1.0),
	"sleep": Color(0.5, 0.3, 0.8),
	"react": Color(1.0, 0.5, 0.1),
}

var fsm
var emotion
var behavior

var _walk_dir_x: float = 1.0  # +1 오른쪽, -1 왼쪽
var _ground_y: float = 0.0
var _screen_rect: Rect2
var _idle_micro_timer: float = 0.0
var _next_idle_micro: float = 0.0
var _chat_locked := false
var _context_menu: PopupMenu
var _breath_time: float = 0.0
var _banzai_timer: float = 0.0
var _next_banzai: float = 0.0
var _no_interact_timer: float = 0.0
var _forced_sleep := false

const SLEEP_AFTER := 600.0  # 10분

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D

func _ready() -> void:
	fsm = CompanionFSM.new()
	add_child(fsm)

	emotion = EmotionState.new()

	behavior = BehaviorSelector.new()
	add_child(behavior)

	fsm.state_entered.connect(_on_state_entered)
	EventBus.chat_requested.connect(_on_chat_requested)
	EventBus.chat_response_received.connect(_on_chat_response_received)

	_context_menu = PopupMenu.new()
	_context_menu.add_item("새 캐릭터 만들기", 0)
	_context_menu.add_separator()
	_context_menu.add_item("종료", 1)
	_context_menu.id_pressed.connect(_on_context_menu_pressed)
	add_child(_context_menu)

	_screen_rect = Rect2(Vector2.ZERO, get_viewport_rect().size)

	var loaded := _load_sprite_frames()
	if loaded != null:
		sprite.sprite_frames = loaded
		SPRITE_SCALE = Vector2(1.5, 1.5)
		SPRITE_HALF  = Vector2(72.0, 80.0)
	else:
		sprite.sprite_frames = _build_placeholder_frames()
	sprite.scale = SPRITE_SCALE

	# SPRITE_HALF 확정 후 위치 계산
	_ground_y = _screen_rect.size.y - SPRITE_HALF.y - 55
	position = Vector2(_screen_rect.size.x * 0.5, _ground_y)
	_pick_walk_direction()
	_next_idle_micro = randf_range(6.0, 12.0)
	_next_banzai = randf_range(20.0, 40.0)
	sprite.play("idle")

func _process(delta: float) -> void:
	emotion.tick(delta)
	fsm.tick(delta)

	var mouse_pos := get_viewport().get_mouse_position()
	var mouse_near := position.distance_to(mouse_pos) < MOUSE_NEAR_DISTANCE

	if not _chat_locked:
		_no_interact_timer += delta
		if not _forced_sleep and _no_interact_timer >= SLEEP_AFTER:
			_forced_sleep = true
			fsm.transition_to(CompanionFSM.State.SLEEP)
		if not _forced_sleep:
			var next: int = behavior.select(fsm, emotion, mouse_near)
			if next != fsm.current_state:
				fsm.transition_to(next)

	_process_state(delta, mouse_pos)
	_process_idle_micro(delta)
	_process_banzai_micro(delta)
	_process_idle_breath(delta)
	_update_edge_lean(delta)
	_update_passthrough()

func _update_passthrough() -> void:
	pass  # mouse passthrough not supported on macOS OpenGL renderer

func _process_state(delta: float, mouse_pos: Vector2) -> void:
	position.y = _ground_y
	match fsm.current_state:
		CompanionFSM.State.WALK:
			_do_walk(delta)
		CompanionFSM.State.REACT:
			_do_react(mouse_pos)

func _do_walk(delta: float) -> void:
	position.x += _walk_dir_x * WALK_SPEED * delta
	position.y = _ground_y

	if position.x < SPRITE_HALF.x or position.x > _screen_rect.size.x - SPRITE_HALF.x:
		_walk_dir_x *= -1
		sprite.flip_h = _walk_dir_x < 0

	position.x = clampf(position.x, SPRITE_HALF.x, _screen_rect.size.x - SPRITE_HALF.x)

func _do_react(mouse_pos: Vector2) -> void:
	sprite.flip_h = mouse_pos.x < position.x

func _on_state_entered(state: int) -> void:
	match state:
		CompanionFSM.State.IDLE:  sprite.play("idle")
		CompanionFSM.State.WALK:
			_pick_walk_direction()
			sprite.play("walk")
		CompanionFSM.State.SLEEP: sprite.play("sleep")
		CompanionFSM.State.REACT: sprite.play("react")

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if position.distance_to(get_viewport().get_mouse_position()) < MOUSE_NEAR_DISTANCE:
			_reset_sleep_timer()
			if fsm.current_state == CompanionFSM.State.SLEEP:
				emotion.wake_up()
				fsm.transition_to(CompanionFSM.State.IDLE)
				return
			if event.button_index == MOUSE_BUTTON_LEFT:
				emotion.on_click()
				EventBus.companion_clicked.emit()
				_do_bounce()
			elif event.button_index == MOUSE_BUTTON_RIGHT:
				_context_menu.position = DisplayServer.mouse_get_position()
				_context_menu.popup()

func _on_context_menu_pressed(id: int) -> void:
	match id:
		0: reset_requested.emit()
		1:
			var body := '{"model":"qwen3-vl:8b-instruct","messages":[],"keep_alive":0}'
			OS.execute("/usr/bin/curl", ["-s", "-X", "POST", "http://localhost:11434/api/chat",
				"-H", "Content-Type: application/json", "-d", body])
			get_tree().quit()

func _on_chat_requested(_text: String) -> void:
	_reset_sleep_timer()
	_chat_locked = true
	fsm.transition_to(CompanionFSM.State.REACT)

func _on_chat_response_received(_text: String) -> void:
	_chat_locked = false
	fsm.transition_to(CompanionFSM.State.IDLE)

func _reset_sleep_timer() -> void:
	_no_interact_timer = 0.0
	_forced_sleep = false

func _pick_walk_direction() -> void:
	_walk_dir_x = 1.0 if randf() > 0.5 else -1.0
	sprite.flip_h = _walk_dir_x < 0

# --- Micro-interactions ---

func _process_idle_micro(delta: float) -> void:
	if fsm.current_state != CompanionFSM.State.IDLE:
		_idle_micro_timer = 0.0
		return
	_idle_micro_timer += delta
	if _idle_micro_timer >= _next_idle_micro:
		_idle_micro_timer = 0.0
		_next_idle_micro = randf_range(6.0, 12.0)
		_do_yawn()

func _process_banzai_micro(delta: float) -> void:
	if fsm.current_state != CompanionFSM.State.IDLE or _chat_locked:
		_banzai_timer = 0.0
		return
	_banzai_timer += delta
	if _banzai_timer >= _next_banzai:
		_banzai_timer = 0.0
		_next_banzai = randf_range(20.0, 40.0)
		_do_banzai()

func _do_banzai() -> void:
	sprite.play("react")
	get_tree().create_timer(1.2).timeout.connect(func():
		if fsm.current_state == CompanionFSM.State.IDLE:
			sprite.play("idle")
	)

func _process_idle_breath(delta: float) -> void:
	if fsm.current_state == CompanionFSM.State.IDLE:
		_breath_time += delta
		sprite.position.y = sin(_breath_time * TAU / 2.5) * 2.0
	else:
		_breath_time = 0.0
		sprite.position.y = lerp(sprite.position.y, 0.0, 8.0 * delta)

func _do_yawn() -> void:
	var tween := create_tween()
	tween.tween_property(sprite, "scale", SPRITE_SCALE * Vector2(1.16, 0.84), 0.35)
	tween.tween_property(sprite, "scale", SPRITE_SCALE * Vector2(0.92, 1.12), 0.2)
	tween.tween_property(sprite, "scale", SPRITE_SCALE, 0.35)

func _do_bounce() -> void:
	var tween := create_tween()
	tween.tween_property(sprite, "position:y", -10.0, 0.1)
	tween.tween_property(sprite, "position:y", 0.0, 0.18)

func _update_edge_lean(delta: float) -> void:
	var target_rotation := 0.0
	if fsm.current_state == CompanionFSM.State.IDLE:
		if position.x < EDGE_LEAN_THRESHOLD:
			target_rotation = -0.18
		elif position.x > _screen_rect.size.x - EDGE_LEAN_THRESHOLD:
			target_rotation = 0.18
	sprite.rotation = lerp(sprite.rotation, target_rotation, 4.0 * delta)

# --- Real sprite loading ---

func _load_sprite_frames() -> SpriteFrames:
	var dir := OS.get_user_data_dir() + "/sprites"
	if not FileAccess.file_exists(dir + "/idle_1.png"):
		return null

	var anim_files := {
		"idle":  ["idle_1.png"],
		"walk":  ["walk_1.png", "walk_2.png", "walk_3.png"],
		"sleep": ["sleep_1.png"],
		"react": ["react_1.png", "react_2.png"],
	}
	var frames := SpriteFrames.new()
	frames.remove_animation("default")

	for anim_name: String in anim_files:
		frames.add_animation(anim_name)
		frames.set_animation_loop(anim_name, true)
		frames.set_animation_speed(anim_name, 4.0)
		for filename: String in anim_files[anim_name]:
			var img := Image.load_from_file(dir + "/" + filename)
			if img:
				frames.add_frame(anim_name, ImageTexture.create_from_image(img))

	return frames

# --- Placeholder sprite generation ---

func _build_placeholder_frames() -> SpriteFrames:
	var frames := SpriteFrames.new()
	frames.remove_animation("default")

	for anim_name in STATE_COLORS:
		var color: Color = STATE_COLORS[anim_name]
		frames.add_animation(anim_name)
		frames.set_animation_loop(anim_name, true)
		frames.set_animation_speed(anim_name, 4.0)
		frames.add_frame(anim_name, _make_character_frame(color, false))
		frames.add_frame(anim_name, _make_character_frame(color, true))

	return frames

func _make_character_frame(color: Color, blink: bool) -> ImageTexture:
	var img := Image.create(16, 20, false, Image.FORMAT_RGBA8)
	var c := color.lightened(0.15) if blink else color
	var dark := c.darkened(0.3)

	_fill_rect(img, 5, 0, 6, 6, c)       # head
	if not blink:
		img.set_pixel(6, 2, Color.BLACK)
		img.set_pixel(9, 2, Color.BLACK)
	else:
		img.set_pixel(6, 3, dark)
		img.set_pixel(9, 3, dark)
	_fill_rect(img, 6, 6, 4, 6, c)       # body
	_fill_rect(img, 4, 6, 2, 5, dark)    # left arm
	_fill_rect(img, 10, 6, 2, 5, dark)   # right arm
	_fill_rect(img, 6, 12, 2, 5, dark)   # left leg
	_fill_rect(img, 9, 12, 2, 5, dark)   # right leg

	return ImageTexture.create_from_image(img)

func _fill_rect(img: Image, x: int, y: int, w: int, h: int, color: Color) -> void:
	for px in range(x, x + w):
		for py in range(y, y + h):
			if px < img.get_width() and py < img.get_height():
				img.set_pixel(px, py, color)
