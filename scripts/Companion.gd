extends Node2D

const CompanionFSM = preload("res://scripts/CompanionFSM.gd")
const EmotionState = preload("res://scripts/EmotionState.gd")
const BehaviorSelector = preload("res://scripts/BehaviorSelector.gd")

const WALK_SPEED = 60.0
const MOUSE_NEAR_DISTANCE = 50.0
const PASSTHROUGH_HALF := Vector2(48, 58)
const SPRITE_SCALE := Vector2(5.0, 5.0)
const EDGE_LEAN_THRESHOLD = 35.0
const CURSOR_LEAN_DISTANCE = 120.0
const CURSOR_LEAN_MAX = 3.0

const STATE_COLORS = {
	"idle":  Color(1.0, 0.85, 0.2),
	"walk":  Color(0.3, 0.6, 1.0),
	"sleep": Color(0.5, 0.3, 0.8),
	"react": Color(1.0, 0.5, 0.1),
}

var fsm
var emotion
var behavior

var _walk_direction: Vector2 = Vector2.RIGHT
var _screen_rect: Rect2
var _idle_micro_timer: float = 0.0
var _next_idle_micro: float = 0.0

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D

func _ready() -> void:
	fsm = CompanionFSM.new()
	add_child(fsm)

	emotion = EmotionState.new()

	behavior = BehaviorSelector.new()
	add_child(behavior)

	fsm.state_entered.connect(_on_state_entered)

	_screen_rect = Rect2(Vector2.ZERO, get_viewport_rect().size)
	position = _screen_rect.get_center()
	_pick_walk_direction()
	_next_idle_micro = randf_range(6.0, 12.0)

	sprite.sprite_frames = _build_placeholder_frames()
	sprite.play("idle")

func _process(delta: float) -> void:
	emotion.tick(delta)
	fsm.tick(delta)

	var mouse_pos := get_viewport().get_mouse_position()
	var mouse_near := position.distance_to(mouse_pos) < MOUSE_NEAR_DISTANCE

	var next: int = behavior.select(fsm, emotion, mouse_near)
	if next != fsm.current_state:
		fsm.transition_to(next)

	_process_state(delta, mouse_pos)
	_process_idle_micro(delta)
	_update_cursor_lean(delta, mouse_pos)
	_update_edge_lean(delta)
	_update_passthrough()

func _update_passthrough() -> void:
	var tl := position - PASSTHROUGH_HALF
	var br := position + PASSTHROUGH_HALF
	DisplayServer.window_set_mouse_passthrough(PackedVector2Array([
		tl,
		Vector2(br.x, tl.y),
		br,
		Vector2(tl.x, br.y),
	]))

func _process_state(delta: float, mouse_pos: Vector2) -> void:
	match fsm.current_state:
		CompanionFSM.State.WALK:
			_do_walk(delta)
		CompanionFSM.State.REACT:
			_do_react(mouse_pos)

func _do_walk(delta: float) -> void:
	position += _walk_direction * WALK_SPEED * delta

	if position.x < 16 or position.x > _screen_rect.size.x - 16:
		_walk_direction.x *= -1
		sprite.flip_h = _walk_direction.x < 0
	if position.y < 16 or position.y > _screen_rect.size.y - 16:
		_walk_direction.y *= -1

	position = position.clamp(Vector2(16, 16), _screen_rect.size - Vector2(16, 16))

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
			emotion.on_click()
			EventBus.companion_clicked.emit()
			_do_bounce()

func _pick_walk_direction() -> void:
	var angle := randf_range(0.0, TAU)
	_walk_direction = Vector2(cos(angle), sin(angle))
	sprite.flip_h = _walk_direction.x < 0

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

func _do_yawn() -> void:
	var tween := create_tween()
	tween.tween_property(sprite, "scale", Vector2(5.8, 4.2), 0.35)
	tween.tween_property(sprite, "scale", Vector2(4.6, 5.6), 0.2)
	tween.tween_property(sprite, "scale", SPRITE_SCALE, 0.35)

func _do_bounce() -> void:
	var tween := create_tween()
	tween.tween_property(sprite, "position:y", -10.0, 0.1)
	tween.tween_property(sprite, "position:y", 0.0, 0.18)

func _update_cursor_lean(delta: float, mouse_pos: Vector2) -> void:
	var target_offset := Vector2.ZERO
	var state: int = fsm.current_state
	if state == CompanionFSM.State.IDLE or state == CompanionFSM.State.REACT:
		var diff := mouse_pos - position
		var dist := diff.length()
		if dist > 0.0 and dist < CURSOR_LEAN_DISTANCE:
			var strength := 1.0 - dist / CURSOR_LEAN_DISTANCE
			target_offset = diff.normalized() * CURSOR_LEAN_MAX * strength
	sprite.offset = sprite.offset.lerp(target_offset, 5.0 * delta)

func _update_edge_lean(delta: float) -> void:
	var target_rotation := 0.0
	if fsm.current_state == CompanionFSM.State.IDLE:
		if position.x < EDGE_LEAN_THRESHOLD:
			target_rotation = -0.18
		elif position.x > _screen_rect.size.x - EDGE_LEAN_THRESHOLD:
			target_rotation = 0.18
	sprite.rotation = lerp(sprite.rotation, target_rotation, 4.0 * delta)

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
