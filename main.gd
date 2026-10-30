extends Node2D
## Pong built for a phone held upright, that turns sideways on wide screens.
## You are the yellow paddle at the bottom (or on the right when sideways,
## where a right thumb sits):
## drag anywhere, or move the mouse, to move it. Arrow keys work too.
## First to 7 wins.
## The game logic always runs in an upright 720x1280 "field"; on a wide
## screen the field is simply drawn rotated, and input is rotated back.
## Every return builds a combo worth more points; middle-of-paddle hits are
## PERFECT and score double. Beat your best: it is saved between games.

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

const COLOR_PLAYER := Color("#ffd166")
const COLOR_AI := Color("#ef476f")
const COLOR_DIM := Color(1, 1, 1, 0.18)

# --- Combo and points --------------------------------------------------------
const PERFECT_ZONE := 0.25  # middle quarter of the paddle (as a fraction of half-width)
const COMBO_FOR_MAX_TRIP := 15  # combo at which the visuals go fully wild
const SAVE_PATH := "user://save.cfg"
const SAVE_VERSION := 1

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
var art_clock := 0.0
var popups := []

var points := 0
var best := 0
var combo := 0
var new_best := false

var landscape := false
var screen := Vector2(W, H)  # visible area in screen pixels
var field_rect := Rect2(0, 0, W, H)  # where the field sits on screen
var field_xform := Transform2D.IDENTITY  # field coordinates -> screen


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
	_load_best()
	_update_layout()
	get_tree().root.size_changed.connect(_update_layout)

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
			if _mute_rect().has_point(local_event.position):
				_toggle_music()
				return
			has_touched = true
			if game_over:
				_restart()
				return
		touch_target = _to_field(local_event.position).x
	elif event is InputEventMouseMotion:
		# On a computer the paddle follows the mouse without needing a click.
		touch_target = _to_field(make_input_local(event).position).x


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
		_on_player_return()
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
		if combo >= 3:
			_popup("COMBO LOST", Vector2(W / 2.0, H - 260.0), Color.WHITE)
		combo = 0
		_after_point(1.0)
		_play("lose" if game_over else "score_cpu")
	elif ball_pos.y < -BALL_R:
		_burst(Vector2(ball_pos.x, 10.0), COLOR_PLAYER, 40)
		score_player += 1
		var bonus := 5 + combo * 2
		points += bonus
		_popup("POINT! +%d" % bonus, Vector2(W / 2.0, 220.0), COLOR_PLAYER)
		_after_point(-1.0)
		_play("win" if game_over else "score_player")

	queue_redraw()


func _move_player(delta: float) -> void:
	# Sideways, the paddle runs up and down the screen.
	var axis := Input.get_axis("ui_down", "ui_up") if landscape \
		else Input.get_axis("ui_left", "ui_right")
	if axis != 0.0:
		touch_target = -1.0
		player_x += axis * KEY_SPEED * delta
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
		if points > best:
			best = points
			new_best = true
			_save_best()


func _restart() -> void:
	score_player = 0
	score_ai = 0
	points = 0
	combo = 0
	new_best = false
	game_over = false
	_after_point(1.0)
	serve_timer = 1.0
	_set_music_volume(MUSIC_VOLUME_DB)


# --- Combo and points --------------------------------------------------------

func _on_player_return() -> void:
	# Each return in a row is worth one more point; a middle hit doubles it.
	combo += 1
	var gain := combo
	var offset := absf(ball_pos.x - player_x) / (PADDLE_SIZE.x / 2.0)
	var at := Vector2(player_x, PLAYER_Y - 90.0)
	if offset <= PERFECT_ZONE:
		gain *= 2
		_popup("PERFECT +%d" % gain, at, _rainbow(0.0).lightened(0.3))
		_burst(ball_pos, Color.WHITE, 24)
		hue_shift += 0.1
	else:
		_popup("+%d" % gain, at, COLOR_PLAYER)
	points += gain


func _trip() -> float:
	# 0 = calm, 1 = full psychedelic. Rises with the combo.
	return minf(float(combo) / COMBO_FOR_MAX_TRIP, 1.0)


func _popup(text: String, at: Vector2, color: Color) -> void:
	popups.append({"text": text, "pos": at, "rise": 0.0, "life": 0.9, "color": color})


func _load_best() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	# Version 1 is the first format; migrate older versions here when it changes.
	best = int(cfg.get_value("stats", "best", 0))


func _save_best() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "save_version", SAVE_VERSION)
	cfg.set_value("stats", "best", best)
	cfg.save(SAVE_PATH)


# --- Layout ----------------------------------------------------------------

func _update_layout() -> void:
	# Wider than tall (monitor, Steam Deck, phone on its side): play sideways.
	var window := get_window()
	var real := Vector2(window.size)
	if real.x <= 0.0 or real.y <= 0.0:
		return
	landscape = real.x > real.y
	var base := Vector2(H, W) if landscape else Vector2(W, H)
	if window.content_scale_size != Vector2i(base):
		window.content_scale_size = Vector2i(base)
	# Stretch aspect "expand": the base area always fits, extra space is added around it.
	screen = real / minf(real.x / base.x, real.y / base.y)
	field_rect = Rect2(_snap((screen - base) / 2.0), base)
	if landscape:
		# Field "down" (toward the player) points right; field "right" points up.
		field_xform = Transform2D(Vector2(0, -1), Vector2(1, 0), field_rect.position + Vector2(0, W))
	else:
		field_xform = Transform2D(Vector2(1, 0), Vector2(0, 1), field_rect.position)
	backdrop.size = screen
	(backdrop.material as ShaderMaterial).set_shader_parameter("screen_size", screen)
	queue_redraw()


func _to_field(point: Vector2) -> Vector2:
	return field_xform.affine_inverse() * point


func _to_screen(point: Vector2) -> Vector2:
	return field_xform * point


func _mute_rect() -> Rect2:
	# Sideways, the player's thumb is on the right, so the button moves left.
	if landscape:
		return Rect2(0.0, 0.0, 230.0, 70.0)
	return Rect2(screen.x - 230.0, 0.0, 230.0, 70.0)


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
	var trip := _trip()
	art_clock += delta * (1.0 + trip * 2.5)
	music_player.pitch_scale = lerpf(music_player.pitch_scale, 1.0 + trip * 0.12, delta * 2.0)
	pulse = move_toward(pulse, 0.0, delta * 1.5)
	shake = maxf(shake - delta, 0.0)
	var mat := backdrop.material as ShaderMaterial
	mat.set_shader_parameter("pulse", pulse)
	mat.set_shader_parameter("hue_shift", hue_shift)
	mat.set_shader_parameter("clock", art_clock)
	mat.set_shader_parameter("trip", trip)

	for popup in popups:
		popup.rise += 90.0 * delta
		popup.life -= delta
	popups = popups.filter(func(popup): return popup.life > 0.0)

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
	draw_rect(Rect2(0, y - size * 1.05, screen.x, size * 1.45), Color(0, 0, 0, 0.6))
	draw_string(font, Vector2(0, y), text, HORIZONTAL_ALIGNMENT_CENTER, screen.x, size, color)


func _draw_centered(text: String, center: Vector2, size: int, color: Color) -> void:
	var font := ThemeDB.fallback_font
	draw_string(font, center + Vector2(-200.0 + 3.0, 3.0), text,
		HORIZONTAL_ALIGNMENT_CENTER, 400.0, size, Color(0, 0, 0, color.a))
	draw_string(font, center - Vector2(200.0, 0.0), text,
		HORIZONTAL_ALIGNMENT_CENTER, 400.0, size, color)


func _draw() -> void:
	# Dim anything outside the field, so the walls are clear on odd screen shapes.
	var dim := Color(0, 0, 0, 0.5)
	draw_rect(Rect2(0, 0, field_rect.position.x, screen.y), dim)
	draw_rect(Rect2(field_rect.end.x, 0, screen.x - field_rect.end.x, screen.y), dim)
	draw_rect(Rect2(field_rect.position.x, 0, field_rect.size.x, field_rect.position.y), dim)
	draw_rect(Rect2(field_rect.position.x, field_rect.end.y,
		field_rect.size.x, screen.y - field_rect.end.y), dim)

	# Everything in the field is drawn in field coordinates.
	var xform := field_xform
	if shake > 0.0:
		var amount := shake * 40.0
		xform.origin += _snap(Vector2(randf_range(-amount, amount), randf_range(-amount, amount)))
	draw_set_transform_matrix(xform)

	# Center line
	var x := 0.0
	while x < W:
		_draw_block(Rect2(x + 8.0, H / 2.0 - PX / 2.0, 24.0, PX), Color(1, 1, 1, 0.7))
		x += 48.0

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

	# Scores stay upright, so they are placed on screen rather than in the field.
	_draw_number(score_ai, _to_screen(Vector2(W / 2.0, H / 2.0 - 110.0)), 16.0, COLOR_AI)
	_draw_number(score_player, _to_screen(Vector2(W / 2.0, H / 2.0 + 110.0)), 16.0, COLOR_PLAYER)

	# Points (opposite corner to the music button) and combo
	var cy := screen.y / 2.0
	var font := ThemeDB.fallback_font
	var pts_x := screen.x - 260.0 if landscape else 10.0
	draw_rect(Rect2(pts_x, 14, 250, 50), Color(0, 0, 0, 0.55))
	draw_string(font, Vector2(pts_x + 14.0, 50.0), "PTS %d  BEST %d" % [points, best],
		HORIZONTAL_ALIGNMENT_LEFT, 230, 26, Color(1, 1, 1, 0.9))
	if combo >= 2 and not game_over:
		var size := 36 + mini(combo, 20) * 2
		_draw_label("COMBO x%d" % combo, cy + (220.0 if landscape else 260.0), size, _rainbow(0.0).lightened(0.2 + 0.4 * (1.0 - _trip())))
	for popup in popups:
		var c: Color = popup.color
		c.a = clampf(popup.life * 2.0, 0.0, 1.0)
		_draw_centered(popup.text, _to_screen(popup.pos) - Vector2(0, popup.rise), 40, c)

	# Music toggle (top corner)
	var mute := _mute_rect()
	draw_rect(Rect2(mute.position + Vector2(20, 14), Vector2(mute.size.x - 30, 50)),
		Color(0, 0, 0, 0.55))
	draw_string(font, Vector2(mute.position.x, 50.0),
		"MUSIC: ON" if music_on else "MUSIC: OFF",
		HORIZONTAL_ALIGNMENT_CENTER, mute.size.x, 28, Color(1, 1, 1, 0.8))

	# Messages
	if game_over:
		var msg := "YOU WIN!" if score_player > score_ai else "CPU WINS"
		_draw_label(msg, cy - 230.0, 72, _rainbow(0.0).lightened(0.3))
		_draw_label("%d POINTS" % points, cy - 140.0, 48, Color.WHITE)
		if new_best:
			_draw_label("NEW BEST!", cy + 200.0, 56, _rainbow(0.5).lightened(0.3))
		else:
			_draw_label("BEST %d" % best, cy + 200.0, 40, Color.WHITE)
		_draw_label("Tap to play again", cy + 300.0, 40, Color.WHITE)
	elif not has_touched:
		_draw_label("Drag to move", field_rect.end.y - (120.0 if landscape else 220.0), 40, Color.WHITE)
