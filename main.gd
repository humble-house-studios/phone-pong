extends Node2D
## Vertical Pong built for a phone held upright.
## You are the yellow paddle at the bottom: drag anywhere to move it.
## Arrow keys also work on a computer. First to 7 wins.

const W := 720.0
const H := 1280.0
const PADDLE_SIZE := Vector2(160, 24)
const PLAYER_Y := H - 110.0
const AI_Y := 110.0
const BALL_R := 14.0
const START_SPEED := 620.0
const SPEED_UP := 1.06
const MAX_SPEED := 1500.0
const AI_SPEED := 520.0
const KEY_SPEED := 900.0
const FOLLOW_SPEED := 2400.0
const MAX_BOUNCE_ANGLE := 60.0
const WIN_SCORE := 7

const COLOR_PLAYER := Color("#ffd166")
const COLOR_AI := Color("#ef476f")
const COLOR_DIM := Color(1, 1, 1, 0.18)

var player_x := W / 2.0
var ai_x := W / 2.0
var ball_pos := Vector2(W / 2.0, H / 2.0)
var ball_vel := Vector2.ZERO
var serve_dir := 1.0
var serve_timer := 1.2
var score_player := 0
var score_ai := 0
var game_over := false
var touch_target := -1.0
var has_touched := false


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		var local_event := make_input_local(event)
		if event is InputEventScreenTouch and event.pressed:
			has_touched = true
			if game_over:
				_restart()
				return
		touch_target = local_event.position.x


func _process(delta: float) -> void:
	_move_player(delta)
	_move_ai(delta)

	if game_over:
		queue_redraw()
		return

	if serve_timer > 0.0:
		serve_timer -= delta
		if serve_timer <= 0.0:
			_launch()
		queue_redraw()
		return

	ball_pos += ball_vel * delta

	# Side walls
	if ball_pos.x < BALL_R:
		ball_pos.x = BALL_R
		ball_vel.x = absf(ball_vel.x)
	elif ball_pos.x > W - BALL_R:
		ball_pos.x = W - BALL_R
		ball_vel.x = -absf(ball_vel.x)

	# Paddles
	if ball_vel.y > 0.0 and _ball_touches(player_x, PLAYER_Y):
		_bounce(player_x, PLAYER_Y, -1.0)
	elif ball_vel.y < 0.0 and _ball_touches(ai_x, AI_Y):
		_bounce(ai_x, AI_Y, 1.0)

	# Scoring
	if ball_pos.y > H + BALL_R:
		score_ai += 1
		_after_point(1.0)
	elif ball_pos.y < -BALL_R:
		score_player += 1
		_after_point(-1.0)

	queue_redraw()


func _move_player(delta: float) -> void:
	if Input.is_action_pressed("ui_left"):
		touch_target = -1.0
		player_x -= KEY_SPEED * delta
	elif Input.is_action_pressed("ui_right"):
		touch_target = -1.0
		player_x += KEY_SPEED * delta
	elif touch_target >= 0.0:
		player_x = move_toward(player_x, touch_target, FOLLOW_SPEED * delta)
	player_x = clampf(player_x, PADDLE_SIZE.x / 2.0, W - PADDLE_SIZE.x / 2.0)


func _move_ai(delta: float) -> void:
	# Chase the ball only when it is heading up toward the AI; otherwise drift home.
	var goal := W / 2.0
	if ball_vel.y < 0.0:
		goal = ball_pos.x
	ai_x = move_toward(ai_x, goal, AI_SPEED * delta)
	ai_x = clampf(ai_x, PADDLE_SIZE.x / 2.0, W - PADDLE_SIZE.x / 2.0)


func _ball_touches(paddle_x: float, paddle_y: float) -> bool:
	return absf(ball_pos.y - paddle_y) <= PADDLE_SIZE.y / 2.0 + BALL_R \
		and absf(ball_pos.x - paddle_x) <= PADDLE_SIZE.x / 2.0 + BALL_R


func _bounce(paddle_x: float, paddle_y: float, dir: float) -> void:
	# Where the ball hits the paddle decides the angle: edges send it wide.
	var offset := clampf((ball_pos.x - paddle_x) / (PADDLE_SIZE.x / 2.0), -1.0, 1.0)
	var angle := deg_to_rad(MAX_BOUNCE_ANGLE) * offset
	var speed := minf(ball_vel.length() * SPEED_UP, MAX_SPEED)
	ball_vel = Vector2(sin(angle), cos(angle) * dir) * speed
	ball_pos.y = paddle_y + dir * (PADDLE_SIZE.y / 2.0 + BALL_R)
	Input.vibrate_handheld(15)


func _launch() -> void:
	var angle := randf_range(-0.5, 0.5)
	ball_vel = Vector2(sin(angle), cos(angle) * serve_dir) * START_SPEED


func _after_point(next_serve_dir: float) -> void:
	ball_pos = Vector2(W / 2.0, H / 2.0)
	ball_vel = Vector2.ZERO
	serve_dir = next_serve_dir
	serve_timer = 0.8
	if score_player >= WIN_SCORE or score_ai >= WIN_SCORE:
		game_over = true


func _restart() -> void:
	score_player = 0
	score_ai = 0
	game_over = false
	_after_point(1.0)
	serve_timer = 1.0


func _draw() -> void:
	draw_rect(Rect2(0, 0, W, H), Color("#101418"))

	# Center line
	var x := 0.0
	while x < W:
		draw_rect(Rect2(x, H / 2.0 - 3.0, 24.0, 6.0), COLOR_DIM)
		x += 48.0

	# Scores
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(0, H / 2.0 - 50.0), str(score_ai),
		HORIZONTAL_ALIGNMENT_CENTER, W, 96, Color(COLOR_AI, 0.5))
	draw_string(font, Vector2(0, H / 2.0 + 120.0), str(score_player),
		HORIZONTAL_ALIGNMENT_CENTER, W, 96, Color(COLOR_PLAYER, 0.5))

	# Paddles and ball
	draw_rect(Rect2(Vector2(ai_x, AI_Y) - PADDLE_SIZE / 2.0, PADDLE_SIZE), COLOR_AI)
	draw_rect(Rect2(Vector2(player_x, PLAYER_Y) - PADDLE_SIZE / 2.0, PADDLE_SIZE), COLOR_PLAYER)
	if not game_over:
		draw_circle(ball_pos, BALL_R, Color.WHITE)

	# Messages
	if game_over:
		var msg := "YOU WIN!" if score_player > score_ai else "CPU WINS"
		draw_string(font, Vector2(0, H / 2.0 - 200.0), msg,
			HORIZONTAL_ALIGNMENT_CENTER, W, 72, Color.WHITE)
		draw_string(font, Vector2(0, H / 2.0 + 260.0), "Tap to play again",
			HORIZONTAL_ALIGNMENT_CENTER, W, 40, COLOR_DIM * 3.0)
	elif not has_touched:
		draw_string(font, Vector2(0, H - 220.0), "Drag to move",
			HORIZONTAL_ALIGNMENT_CENTER, W, 40, COLOR_DIM * 3.0)
