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

const MUSIC_FRAMES := 302400  # printed by tools/make_audio.py
const MUSIC_VOLUME_DB := -6.0
const SFX_NAMES := ["hit_player", "hit_cpu", "wall", "score_player", "score_cpu", "win", "lose"]
const MUTE_RECT := Rect2(W - 230.0, 0.0, 230.0, 70.0)

const COLOR_PLAYER := Color("#ffd166")
const COLOR_AI := Color("#ef476f")
const COLOR_DIM := Color(1, 1, 1, 0.18)

# --- 8-bit art ---------------------------------------------------------------
const PX := 8.0  # one "pixel" of art, in screen pixels
const OUTLINE := Color(0, 0, 0, 0.85)
const TRAIL_LEN := 10
const BALL_SHAPE := [".##.", "####", "####", ".##."]
# 3x5 pixel digits for the scores.
const DIGITS := [
	["###", "#.#", "#.#", "#.#", "###"], [".#.", "##.", ".#.", ".#.", "###"],
	["###", "..#", "###", "#..", "###"], ["###", "..#", "###", "..#", "###"],
	["#.#", "#.#", "###", "..#", "..#"], ["###", "#..", "###", "..#", "###"],
	["###", "#..", "###", "#.#", "###"], ["###", "..#", ".#.", ".#.", ".#."],
	["###", "#.#", "###", "#.#", "###"], ["###", "#.#", "###", "..#", "###"],
]

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
var rally := 0

var sfx := {}
var music_player: AudioStreamPlayer
var music_on := true
var music_started := false

var backdrop: ColorRect
var art_time := 0.0
var pulse := 0.0
var hue_shift := 0.0
var shake := 0.0
var trail: Array[Vector2] = []
var sparks := []


func _ready() -> void:
	# Swirling pixel plasma drawn behind everything else.
	var mat := ShaderMaterial.new()
	mat.shader = load("res://psychedelic.gdshader")
	backdrop = ColorRect.new()
	backdrop.size = Vector2(W, H)
	backdrop.material = mat
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop.show_behind_parent = true
	add_child(backdrop)

	for key in SFX_NAMES:
		var player := AudioStreamPlayer.new()
		player.stream = load("res://audio/%s.wav" % key)
		add_child(player)
		sfx[key] = player

	var music := load("res://audio/music.wav") as AudioStreamWAV
	music.loop_mode = AudioStreamWAV.LOOP_FORWARD
	music.loop_begin = 0
	music.loop_end = MUSIC_FRAMES
	music_player = AudioStreamPlayer.new()
	music_player.stream = music
	music_player.volume_db = MUSIC_VOLUME_DB
	add_child(music_player)
	# Safety net in case a platform ignores the loop points.
	music_player.finished.connect(_on_music_finished)


func _input(event: InputEvent) -> void:
	# Browsers only allow sound after the player touches the screen or presses a key.
	if (event is InputEventScreenTouch and event.pressed) or event is InputEventKey:
		_start_music_once()

	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		var local_event := make_input_local(event)
		if event is InputEventScreenTouch and event.pressed:
			if MUTE_RECT.has_point(local_event.position):
				_toggle_music()
				return
			has_touched = true
			if game_over:
				_restart()
				return
		touch_target = local_event.position.x


func _process(delta: float) -> void:
	_update_art(delta)
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
		_play("wall")
	elif ball_pos.x > W - BALL_R:
		ball_pos.x = W - BALL_R
		ball_vel.x = -absf(ball_vel.x)
		_play("wall")

	# Paddles
	if ball_vel.y > 0.0 and _ball_touches(player_x, PLAYER_Y):
		_bounce(player_x, PLAYER_Y, -1.0)
		_burst(ball_pos, COLOR_PLAYER, 14)
		_play("hit_player", _rally_pitch())
	elif ball_vel.y < 0.0 and _ball_touches(ai_x, AI_Y):
		_bounce(ai_x, AI_Y, 1.0)
		_burst(ball_pos, COLOR_AI, 14)
		_play("hit_cpu", _rally_pitch())

	# Scoring
	if ball_pos.y > H + BALL_R:
		_burst(Vector2(ball_pos.x, H - 10.0), COLOR_AI, 40)
		score_ai += 1
		_after_point(1.0)
		_play("lose" if game_over else "score_cpu")
	elif ball_pos.y < -BALL_R:
		_burst(Vector2(ball_pos.x, 10.0), COLOR_PLAYER, 40)
		score_player += 1
		_after_point(-1.0)
		_play("win" if game_over else "score_player")

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
	rally += 1
	pulse = minf(pulse + 0.5, 1.0)
	hue_shift += 0.04
	Input.vibrate_handheld(15)


func _launch() -> void:
	var angle := randf_range(-0.5, 0.5)
	ball_vel = Vector2(sin(angle), cos(angle) * serve_dir) * START_SPEED


func _after_point(next_serve_dir: float) -> void:
	ball_pos = Vector2(W / 2.0, H / 2.0)
	ball_vel = Vector2.ZERO
	serve_dir = next_serve_dir
	serve_timer = 0.8
	rally = 0
	trail.clear()
	shake = 0.25
	pulse = 1.0
	hue_shift += 0.17
	if score_player >= WIN_SCORE or score_ai >= WIN_SCORE:
		game_over = true
		_set_music_volume(MUSIC_VOLUME_DB - 14.0)


func _restart() -> void:
	score_player = 0
	score_ai = 0
	game_over = false
	_after_point(1.0)
	serve_timer = 1.0
	_set_music_volume(MUSIC_VOLUME_DB)


# --- Audio -----------------------------------------------------------------

func _play(key: String, pitch: float = 1.0) -> void:
	var player: AudioStreamPlayer = sfx[key]
	player.pitch_scale = pitch
	player.play()


func _rally_pitch() -> float:
	# Each hit in a long rally sounds a little higher: builds tension.
	return minf(1.0 + rally * 0.04, 1.6)


func _start_music_once() -> void:
	if music_started:
		return
	music_started = true
	if music_on:
		music_player.play()


func _toggle_music() -> void:
	music_on = not music_on
	if music_on:
		music_player.play()
	else:
		music_player.stop()


func _set_music_volume(db: float) -> void:
	create_tween().tween_property(music_player, "volume_db", db, 0.6)


func _on_music_finished() -> void:
	if music_on:
		music_player.play()


# --- Art -------------------------------------------------------------------

func _update_art(delta: float) -> void:
	art_time += delta
	pulse = move_toward(pulse, 0.0, delta * 1.5)
	shake = maxf(shake - delta, 0.0)
	var mat := backdrop.material as ShaderMaterial
	mat.set_shader_parameter("pulse", pulse)
	mat.set_shader_parameter("hue_shift", hue_shift)

	if ball_vel != Vector2.ZERO:
		trail.push_front(_snap(ball_pos))
		if trail.size() > TRAIL_LEN:
			trail.pop_back()

	for spark in sparks:
		spark.pos += spark.vel * delta
		spark.vel *= 0.92
		spark.life -= delta
	sparks = sparks.filter(func(spark): return spark.life > 0.0)


func _burst(at: Vector2, color: Color, count: int) -> void:
	for i in count:
		var dir := Vector2.from_angle(randf() * TAU)
		sparks.append({
			"pos": at, "vel": dir * randf_range(200.0, 700.0),
			"life": randf_range(0.3, 0.7),
			"color": color if i % 2 == 0 else _rainbow(randf()),
		})


func _rainbow(offset: float) -> Color:
	return Color.from_hsv(fposmod(art_time * 0.6 + offset, 1.0), 0.75, 1.0)


func _snap(v: Vector2) -> Vector2:
	return (v / PX).floor() * PX


func _draw_block(rect: Rect2, color: Color) -> void:
	# A chunky sprite block with a black outline, like old console art.
	draw_rect(rect.grow(PX / 2.0), OUTLINE)
	draw_rect(rect, color)


func _draw_paddle(x: float, y: float, color: Color) -> void:
	var rect := Rect2(_snap(Vector2(x, y) - PADDLE_SIZE / 2.0), PADDLE_SIZE)
	_draw_block(rect, color)
	draw_rect(Rect2(rect.position, Vector2(rect.size.x, PX)), color.lightened(0.45))
	draw_rect(Rect2(rect.position + Vector2(0, rect.size.y - PX), Vector2(rect.size.x, PX)),
		color.darkened(0.35))
	# A rainbow glint that slides along the paddle.
	var cells := int(rect.size.x / PX)
	var glint := int(art_time * 18.0) % (cells + 8)
	for i in 3:
		var c := glint - i
		if c >= 0 and c < cells:
			draw_rect(Rect2(rect.position + Vector2(c * PX, PX), Vector2(PX, PX)), _rainbow(i * 0.1))


func _draw_ball(center: Vector2, color: Color, outline: bool) -> void:
	var origin := _snap(center) - Vector2(2, 2) * PX
	for row in BALL_SHAPE.size():
		for col in BALL_SHAPE[row].length():
			if BALL_SHAPE[row][col] == "#":
				var cell := Rect2(origin + Vector2(col, row) * PX, Vector2(PX, PX))
				if outline:
					draw_rect(cell.grow(PX / 2.0), OUTLINE)
				else:
					draw_rect(cell, color)


func _draw_number(value: int, center: Vector2, cell: float, color: Color) -> void:
	var text := str(value)
	var width := text.length() * 4.0 * cell - cell
	var x := center.x - width / 2.0
	for ch in text:
		var glyph: Array = DIGITS[ch.to_int()]
		for row in 5:
			for col in 3:
				if glyph[row][col] == "#":
					var r := Rect2(Vector2(x + col * cell, center.y + (row - 2.5) * cell), Vector2(cell, cell))
					draw_rect(r.grow(cell * 0.2), OUTLINE)
					draw_rect(r, color)
		x += 4.0 * cell


func _draw_label(text: String, y: float, size: int, color: Color) -> void:
	# Dark band behind text so it stays readable over the plasma.
	var font := ThemeDB.fallback_font
	draw_rect(Rect2(0, y - size * 1.05, W, size * 1.45), Color(0, 0, 0, 0.6))
	draw_string(font, Vector2(0, y), text, HORIZONTAL_ALIGNMENT_CENTER, W, size, color)


func _draw() -> void:
	if shake > 0.0:
		var amount := shake * 40.0
		draw_set_transform(_snap(Vector2(randf_range(-amount, amount), randf_range(-amount, amount))))

	# Center line
	var x := 0.0
	while x < W:
		_draw_block(Rect2(x + 8.0, H / 2.0 - PX / 2.0, 24.0, PX), Color(1, 1, 1, 0.7))
		x += 48.0

	# Scores
	_draw_number(score_ai, Vector2(W / 2.0, H / 2.0 - 110.0), 16.0, COLOR_AI)
	_draw_number(score_player, Vector2(W / 2.0, H / 2.0 + 110.0), 16.0, COLOR_PLAYER)

	# Paddles, sparks and ball
	_draw_paddle(ai_x, AI_Y, COLOR_AI)
	_draw_paddle(player_x, PLAYER_Y, COLOR_PLAYER)
	for spark in sparks:
		var size := PX * clampf(spark.life * 2.0, 0.5, 1.0)
		draw_rect(Rect2(_snap(spark.pos), Vector2(size, size)), spark.color)
	if not game_over:
		for i in range(trail.size() - 1, 0, -1):
			var fade := 1.0 - float(i) / TRAIL_LEN
			draw_rect(Rect2(trail[i] - Vector2(PX, PX), Vector2(PX, PX) * 2.0),
				Color(_rainbow(i * 0.08), fade * 0.8))
		_draw_ball(ball_pos, Color.WHITE, true)
		_draw_ball(ball_pos, _rainbow(0.0).lightened(0.6), false)

	draw_set_transform(Vector2.ZERO)

	# Music toggle (top-right corner)
	var font := ThemeDB.fallback_font
	draw_rect(Rect2(MUTE_RECT.position + Vector2(20, 14), Vector2(MUTE_RECT.size.x - 30, 50)),
		Color(0, 0, 0, 0.55))
	draw_string(font, Vector2(MUTE_RECT.position.x, 50.0),
		"MUSIC: ON" if music_on else "MUSIC: OFF",
		HORIZONTAL_ALIGNMENT_CENTER, MUTE_RECT.size.x, 28, Color(1, 1, 1, 0.8))

	# Messages
	if game_over:
		var msg := "YOU WIN!" if score_player > score_ai else "CPU WINS"
		_draw_label(msg, H / 2.0 - 230.0, 72, _rainbow(0.0).lightened(0.3))
		_draw_label("Tap to play again", H / 2.0 + 280.0, 40, Color.WHITE)
	elif not has_touched:
		_draw_label("Drag to move", H - 220.0, 40, Color.WHITE)
