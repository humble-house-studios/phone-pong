extends Node2D
## Pong built for a phone held upright, that turns sideways on wide screens.
## You are the yellow paddle at the bottom (or on the right when sideways,
## where a right thumb sits):
## drag anywhere, or move the mouse, to move it. Arrow keys work too.
## Roguelike runs: score 3 on the CPU to clear a stage, then pick 1 of 3
## upgrades. Each goal against you costs a heart; lose them all and the run
## ends. The CPU gets faster every stage, and every 4th stage is one of four
## bosses with a health bar and a trick. Beating a boss earns a relic: a rare
## item that lasts the whole run.
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
const AI_SPEED := 360.0  # stage 1; grows each stage
const KEY_SPEED := 900.0
const FOLLOW_SPEED := 2400.0
const MAX_BOUNCE_ANGLE := 60.0
const STAGE_WIN := 3  # points to clear a stage
const START_HEARTS := 3
const BOSS_EVERY := 4
const SHIELD_Y := H - 30.0
const BOSS_HP := 5  # points to beat a boss
const TWIN_Y := AI_Y + 320.0
const FOG_TOP := H / 2.0 - 380.0
const FOG_BOTTOM := H / 2.0 + 120.0

# --- Bosses: [name, hint], cycled every BOSS_EVERY stages ---------------------
enum Boss { WALL, TWINS, PHANTOM, WOBBLER }
const BOSSES := [
	["THE WALL", "Giant paddle!"],
	["THE TWINS", "Two paddles!"],
	["PHANTOM", "The ball hides in the fog!"],
	["WOBBLER", "The ball wobbles!"],
]

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
const SAVE_VERSION := 2

# --- Roguelike upgrades: id -> [name, description, max level] ----------------
const UPGRADES := {
	"wide": ["WIDE PADDLE", "Your paddle grows", 5],
	"heart": ["EXTRA HEART", "+1 heart", 99],
	"perfect": ["SWEET SPOT", "Bigger PERFECT zone", 3],
	"mult": ["MULTIPLIER", "+50% points", 99],
	"shield": ["SHIELD", "Blocks one goal", 99],
	"magnet": ["MAGNET", "Ball bends toward you", 3],
	"slow": ["SLUGGISH CPU", "CPU moves slower", 4],
}
const MAX_HEARTS := 9

# --- Relics: rare items from bosses, one of each: id -> [name, description, colour]
const RELICS := {
	"phoenix": ["PHOENIX FEATHER", "Revive once with 1 heart", "#ff7b00"],
	"vampire": ["VAMPIRE FANG", "Every 10 combo heals 1 heart", "#e01e37"],
	"midas": ["MIDAS TOUCH", "PERFECT hits score x3", "#ffd700"],
	"warp": ["TIME WARP", "Ball slows down near you", "#9d4edd"],
	"dice": ["LUCKY DICE", "4 upgrade choices", "#06d6a0"],
	"crystal": ["CRYSTAL HEART", "Free shield every stage", "#4cc9f0"],
	"heavy": ["HEAVY HITTER", "Your goals count double", "#ff5d8f"],
}
const MAX_SHIELDS := 3

# --- 8-bit art ---------------------------------------------------------------
const PX := 8.0  # one "pixel" of art, in screen pixels
const OUTLINE := Color(0, 0, 0, 0.85)
const TRAIL_LEN := 10
const BALL_SHAPE := [".##.", "####", "####", ".##."]
const HEART_SHAPE := [".##.##.", "#######", "#######", ".#####.", "..###..", "...#..."]
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
var game_over := false  # the run has ended
var picking := false  # choosing an upgrade between stages
var input_lock := 0.0  # ignore taps briefly so a drag doesn't pick by accident
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

var stage := 1
var best_stage := 0
var hearts := START_HEARTS
var shields := 0
var levels := {}  # upgrade id -> level owned this run
var offers: Array[String] = []
var pick_index := 0
var stage_bonus := 0
var pick_relic := false  # the cards on offer are relics, not upgrades
var relics: Array[String] = []
var phoenix_used := false
var boss_intro := 0.0  # seconds left to show the boss's name

# Hidden test menu: triple-tap the stage/points box. Runs that use it don't
# count toward saved records.
const TEST_ITEMS := ["Next boss", "Skip this stage", "God mode", "Random relic", "Close"]
var test_menu := false
var title := true  # showing the start menu
var title_index := 0
const TITLE_ITEMS := ["PLAY", "MUSIC"]
var test_index := 0
var god_mode := false
var cheated := false
var hud_taps := 0
var hud_tap_time := 0.0

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
			if title:
				var button := _title_item_at(local_event.position)
				if button >= 0:
					_title_action(button)
				return
			if test_menu:
				var item := _test_item_at(local_event.position)
				if item >= 0:
					_test_action(item)
				return
			if not picking and not game_over and _hud_rect().has_point(local_event.position):
				hud_taps = hud_taps + 1 if art_time - hud_tap_time < 0.6 else 1
				hud_tap_time = art_time
				if hud_taps >= 3:
					hud_taps = 0
					test_menu = true
					test_index = 0
					return
			if picking:
				var card := _card_at(local_event.position)
				if card >= 0:
					_pick(card)
				return
			if game_over:
				if input_lock <= 0.0:
					_restart()
				return
		touch_target = _to_field(local_event.position).x
	elif event is InputEventMouseMotion:
		# On a computer the paddle follows the mouse without needing a click.
		var local_pos := make_input_local(event).position as Vector2
		touch_target = _to_field(local_pos).x
		if picking and _card_at(local_pos) >= 0:
			pick_index = _card_at(local_pos)
		if title and _title_item_at(local_pos) >= 0:
			title_index = _title_item_at(local_pos)
		if test_menu and _test_item_at(local_pos) >= 0:
			test_index = _test_item_at(local_pos)

	# Keyboard / gamepad for the menus and restarting.
	if title:
		if event.is_action_pressed("ui_up") or event.is_action_pressed("ui_down"):
			title_index = 1 - title_index
		elif event.is_action_pressed("ui_accept"):
			_title_action(title_index)
	elif test_menu:
		if event.is_action_pressed("ui_up"):
			test_index = posmod(test_index - 1, TEST_ITEMS.size())
		elif event.is_action_pressed("ui_down"):
			test_index = posmod(test_index + 1, TEST_ITEMS.size())
		elif event.is_action_pressed("ui_accept"):
			_test_action(test_index)
		elif event.is_action_pressed("ui_cancel"):
			test_menu = false
	elif picking:
		if event.is_action_pressed("ui_left") or event.is_action_pressed("ui_up"):
			pick_index = posmod(pick_index - 1, offers.size())
		elif event.is_action_pressed("ui_right") or event.is_action_pressed("ui_down"):
			pick_index = posmod(pick_index + 1, offers.size())
		elif event.is_action_pressed("ui_accept"):
			_pick(pick_index)
	elif game_over and event.is_action_pressed("ui_accept") and input_lock <= 0.0:
		_restart()


func _process(delta: float) -> void:
	_update_art(delta)
	input_lock = maxf(input_lock - delta, 0.0)
	boss_intro = maxf(boss_intro - delta, 0.0)
	_move_player(delta)
	_move_ai(delta)

	if game_over or picking or test_menu or title:
		queue_redraw()
		return

	if serve_timer > 0.0:
		serve_timer -= delta
		if serve_timer <= 0.0:
			_launch()
		queue_redraw()
		return

	# Magnet upgrade: while the ball heads your way, it bends toward your paddle.
	var magnet: int = levels.get("magnet", 0)
	if magnet > 0 and ball_vel.y > 0.0 and ball_pos.y > H * 0.45:
		ball_vel.x += signf(player_x - ball_pos.x) * 260.0 * magnet * delta

	# Time Warp relic: the ball slows down as it nears you.
	var step := delta
	if _has("warp") and ball_vel.y > 0.0 and ball_pos.y > H * 0.7:
		step *= 0.6
	ball_pos += ball_vel * step
	if _boss() == Boss.WOBBLER:
		ball_pos.x += cos(art_time * 6.0) * 280.0 * delta

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
	if ball_vel.y > 0.0 and _ball_touches(player_x, PLAYER_Y, _player_width()):
		_on_player_return()
		_bounce(player_x, PLAYER_Y, -1.0, _player_width())
		_burst(ball_pos, COLOR_PLAYER, 14)
		_play("hit_player", _rally_pitch())
	elif ball_vel.y < 0.0 and _ball_touches(ai_x, AI_Y, _ai_width()):
		_bounce(ai_x, AI_Y, 1.0, _ai_width())
		_burst(ball_pos, COLOR_AI, 14)
		_play("hit_cpu", _rally_pitch())
	elif ball_vel.y < 0.0 and _boss() == Boss.TWINS \
			and _ball_touches(_twin_x(), TWIN_Y, PADDLE_SIZE.x):
		_bounce(_twin_x(), TWIN_Y, 1.0, PADDLE_SIZE.x)
		_burst(ball_pos, COLOR_AI, 14)
		_play("hit_cpu", _rally_pitch())

	# Shield upgrade: a barrier behind you that eats one goal per charge.
	if shields > 0 and ball_vel.y > 0.0 and ball_pos.y > SHIELD_Y - BALL_R:
		shields -= 1
		ball_vel.y = -absf(ball_vel.y)
		ball_pos.y = SHIELD_Y - BALL_R
		_burst(ball_pos, Color("#4cc9f0"), 30)
		_popup("SHIELD!", Vector2(W / 2.0, H - 260.0), Color("#4cc9f0"))
		_play("wall")
		shake = 0.15

	# Scoring
	if ball_pos.y > H + BALL_R:
		_burst(Vector2(ball_pos.x, H - 10.0), COLOR_AI, 40)
		score_ai += 1
		if not god_mode:
			hearts -= 1
		if combo >= 3:
			_popup("COMBO LOST", Vector2(W / 2.0, H - 260.0), Color.WHITE)
		combo = 0
		_after_point(1.0)
		_play("lose" if game_over else "score_cpu")
	elif ball_pos.y < -BALL_R:
		_burst(Vector2(ball_pos.x, 10.0), COLOR_PLAYER, 40)
		score_player += 2 if _has("heavy") else 1
		var bonus := _scaled(5 + combo * 2)
		points += bonus
		_popup("POINT! +%d" % bonus, Vector2(W / 2.0, 220.0), COLOR_PLAYER)
		_after_point(-1.0)
		_play("win" if picking else "score_player")

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
	player_x = clampf(player_x, _player_width() / 2.0, W - _player_width() / 2.0)


func _move_ai(delta: float) -> void:
	# Chase the ball only when it is heading up toward the AI; otherwise drift home.
	var goal := W / 2.0
	if ball_vel.y < 0.0:
		goal = ball_pos.x
	ai_x = move_toward(ai_x, goal, _ai_speed() * delta)
	ai_x = clampf(ai_x, _ai_width() / 2.0, W - _ai_width() / 2.0)


func _ball_touches(paddle_x: float, paddle_y: float, width: float) -> bool:
	return absf(ball_pos.y - paddle_y) <= PADDLE_SIZE.y / 2.0 + BALL_R \
		and absf(ball_pos.x - paddle_x) <= width / 2.0 + BALL_R


func _bounce(paddle_x: float, paddle_y: float, dir: float, width: float) -> void:
	# Where the ball hits the paddle decides the angle: edges send it wide.
	var offset := clampf((ball_pos.x - paddle_x) / (width / 2.0), -1.0, 1.0)
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
	var speed := minf(START_SPEED + 25.0 * (stage - 1), 1000.0)
	ball_vel = Vector2(sin(angle), cos(angle) * serve_dir) * speed


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
	if hearts <= 0 and _has("phoenix") and not phoenix_used:
		phoenix_used = true
		hearts = 1
		_popup("PHOENIX! REVIVED", Vector2(W / 2.0, H / 2.0 + 260.0), Color(RELICS["phoenix"][2]), 1.8)
	if hearts <= 0:
		game_over = true
		input_lock = 0.8
		_set_music_volume(MUSIC_VOLUME_DB - 14.0)
		if not cheated and (points > best or stage > best_stage):
			new_best = points > best
			best = maxi(best, points)
			best_stage = maxi(best_stage, stage)
			_save_best()
	elif score_player >= _stage_target():
		_clear_stage()


func _restart() -> void:
	# A fresh run: back to stage 1 with no upgrades.
	points = 0
	combo = 0
	new_best = false
	game_over = false
	stage = 1
	hearts = START_HEARTS
	shields = 0
	levels.clear()
	relics.clear()
	phoenix_used = false
	cheated = god_mode
	_start_stage()
	_set_music_volume(MUSIC_VOLUME_DB)


# --- Roguelike stages and upgrades -------------------------------------------

func _clear_stage() -> void:
	stage_bonus = _scaled(20 * stage * (2 if _is_boss() else 1))
	points += stage_bonus
	popups.clear()
	# Bosses drop a choice of relics you don't have yet; other stages offer
	# upgrades that aren't maxed out.
	var pool: Array[String] = []
	for id in RELICS:
		if _is_boss() and not _has(id):
			pool.append(id)
	pick_relic = not pool.is_empty()
	if not pick_relic:
		for id in UPGRADES:
			if _can_offer(id):
				pool.append(id)
	pool.shuffle()
	var count := 4 if _has("dice") and not pick_relic else 3
	offers.assign(pool.slice(0, count))
	pick_index = 0
	picking = true
	input_lock = 0.6
	_set_music_volume(MUSIC_VOLUME_DB - 8.0)


func _can_offer(id: String) -> bool:
	if id == "heart":
		return hearts < MAX_HEARTS
	if id == "shield":
		return shields < MAX_SHIELDS
	return levels.get(id, 0) < UPGRADES[id][2]


func _card_rects() -> Array[Rect2]:
	var rects: Array[Rect2] = []
	var center := screen / 2.0
	var n := offers.size()
	for i in n:
		if landscape:
			var gap := minf(400.0, (screen.x - 60.0) / n)
			var size := Vector2(gap - 40.0, 300)
			rects.append(Rect2(center + Vector2((i - (n - 1) / 2.0) * gap, 60.0) - size / 2.0, size))
		else:
			var gap := minf(230.0, 860.0 / n)
			var size := Vector2(560, gap - 40.0)
			rects.append(Rect2(center + Vector2(0.0, 120.0 + (i - (n - 1) / 2.0) * gap) - size / 2.0, size))
	return rects


func _card_at(point: Vector2) -> int:
	var rects := _card_rects()
	for i in rects.size():
		if rects[i].has_point(point):
			return i
	return -1


func _pick(index: int) -> void:
	if input_lock > 0.0 or index < 0 or index >= offers.size():
		return
	var id := offers[index]
	if pick_relic:
		relics.append(id)
		id = ""
	match id:
		"":
			pass
		"heart":
			hearts += 1
		"shield":
			shields += 1
		_:
			levels[id] = levels.get(id, 0) + 1
	picking = false
	stage += 1
	_start_stage()
	_set_music_volume(MUSIC_VOLUME_DB)


func _start_stage() -> void:
	score_player = 0
	score_ai = 0
	_after_point(1.0)
	serve_timer = 1.2
	if _has("crystal") and shields == 0:
		shields = 1
	if _is_boss():
		serve_timer = 2.0
		boss_intro = 2.0
	else:
		_popup("STAGE %d" % stage, Vector2(W / 2.0, H / 2.0 + 260.0), Color.WHITE)


# --- Start menu --------------------------------------------------------------

func _title_item_rects() -> Array[Rect2]:
	var center := screen / 2.0
	return [
		Rect2(center + Vector2(-220, 40), Vector2(440, 130)),
		Rect2(center + Vector2(-220, 200), Vector2(440, 96)),
	]


func _title_item_at(point: Vector2) -> int:
	var rects := _title_item_rects()
	for i in rects.size():
		if rects[i].has_point(point):
			return i
	return -1


func _title_action(index: int) -> void:
	if index == 0:
		title = false
		_restart()
	else:
		_toggle_music()


func _draw_title() -> void:
	draw_rect(Rect2(Vector2.ZERO, screen), Color(0, 0, 0, 0.6))
	var cy := screen.y / 2.0
	var top := cy - (250.0 if landscape else 380.0)
	_draw_label("PHONE PONG", top, 96, _rainbow(0.0).lightened(0.3))
	_draw_label("a psychedelic roguelike", top + 70.0, 34, Color.WHITE)
	if best_stage > 0:
		_draw_label("BEST %d  -  STAGE %d" % [best, best_stage], top + 150.0, 32, COLOR_PLAYER)
	var rects := _title_item_rects()
	for i in rects.size():
		if i == title_index:
			draw_rect(rects[i].grow(PX), _rainbow(0.0))
		_draw_block(rects[i], Color(0.08, 0.04, 0.16, 0.95))
	_draw_fitted("PLAY", rects[0], 0.68, 64, _rainbow(0.3).lightened(0.4))
	_draw_fitted("MUSIC: %s" % ("ON" if music_on else "OFF"), rects[1], 0.64, 34, Color.WHITE)
	if not landscape:
		_draw_label("Drag to move. Beat bosses for relics.", rects[1].end.y + 90.0, 28, Color(1, 1, 1, 0.8))


# --- Test menu ---------------------------------------------------------------

func _hud_rect() -> Rect2:
	return Rect2(screen.x - 390.0 if landscape else 10.0, 14.0, 380.0, 80.0)


func _test_item_rects() -> Array[Rect2]:
	var rects: Array[Rect2] = []
	var size := Vector2(520, 96)
	var gap := 112.0
	for i in TEST_ITEMS.size():
		var center := screen / 2.0 + Vector2(0.0, (i - (TEST_ITEMS.size() - 1) / 2.0) * gap + 30.0)
		rects.append(Rect2(center - size / 2.0, size))
	return rects


func _test_item_at(point: Vector2) -> int:
	var rects := _test_item_rects()
	for i in rects.size():
		if rects[i].has_point(point):
			return i
	return -1


func _test_action(index: int) -> void:
	match index:
		0:  # Jump to the next boss, picking up one random upgrade per skipped stage.
			var target := (stage / BOSS_EVERY + 1) * BOSS_EVERY
			while stage < target - 1:
				var pool: Array[String] = []
				for id in UPGRADES:
					if _can_offer(id):
						pool.append(id)
				if not pool.is_empty():
					var id: String = pool.pick_random()
					match id:
						"heart":
							hearts += 1
						"shield":
							shields += 1
						_:
							levels[id] = levels.get(id, 0) + 1
				stage += 1
			stage = target
			_start_stage()
		1:  # Win this stage straight away and go to the pick screen.
			score_player = _stage_target()
			_after_point(-1.0)
		2:
			# Leave the menu open so the new ON/OFF state is visible.
			god_mode = not god_mode
			cheated = cheated or god_mode
			return
		3:
			var pool: Array[String] = []
			for id in RELICS:
				if not _has(id):
					pool.append(id)
			if not pool.is_empty():
				relics.append(pool.pick_random())
		4:
			pass
	if index != 4:
		cheated = true
	test_menu = false


func _draw_test_menu() -> void:
	draw_rect(Rect2(Vector2.ZERO, screen), Color(0, 0, 0, 0.7))
	var rects := _test_item_rects()
	_draw_label("TEST MENU", rects[0].position.y - 40.0, 48, Color.WHITE)
	for i in rects.size():
		var rect := rects[i]
		if i == test_index:
			draw_rect(rect.grow(PX), _rainbow(0.0))
		_draw_block(rect, Color(0.08, 0.04, 0.16, 0.95))
		var text: String = TEST_ITEMS[i]
		if i == 2:
			text = "God mode: %s" % ("ON" if god_mode else "OFF")
		_draw_fitted(text, rect, 0.64, 36, Color.WHITE)


func _is_boss() -> bool:
	return stage % BOSS_EVERY == 0


func _boss() -> int:
	# Which boss this stage is, or -1 for a normal stage.
	if not _is_boss():
		return -1
	return (stage / BOSS_EVERY - 1) % BOSSES.size()


func _stage_target() -> int:
	return BOSS_HP if _is_boss() else STAGE_WIN


func _twin_x() -> float:
	# The second Twin mirrors the first, covering the other side.
	return W - ai_x


func _has(relic: String) -> bool:
	return relic in relics


func _player_width() -> float:
	return PADDLE_SIZE.x + 32.0 * levels.get("wide", 0)


func _ai_width() -> float:
	return PADDLE_SIZE.x * (1.6 if _boss() == Boss.WALL else 1.0)


func _ai_speed() -> float:
	var speed := minf(AI_SPEED + 50.0 * (stage - 1), 1100.0)
	return speed * pow(0.85, levels.get("slow", 0))


func _scaled(value: int) -> int:
	# Multiplier upgrade: +50% points per level.
	return int(round(value * (1.0 + 0.5 * levels.get("mult", 0))))


# --- Combo and points --------------------------------------------------------

func _on_player_return() -> void:
	# Each return in a row is worth one more point; a middle hit doubles it.
	combo += 1
	var gain := combo
	if _has("vampire") and combo % 10 == 0 and hearts < MAX_HEARTS:
		hearts += 1
		_popup("+1 HEART", Vector2(W / 2.0, H - 330.0), Color(RELICS["vampire"][2]))
	var offset := absf(ball_pos.x - player_x) / (_player_width() / 2.0)
	var at := Vector2(player_x, PLAYER_Y - 90.0)
	gain = _scaled(gain)
	if offset <= PERFECT_ZONE + 0.12 * levels.get("perfect", 0):
		gain *= 3 if _has("midas") else 2
		_popup("PERFECT +%d" % gain, at, _rainbow(0.0).lightened(0.3))
		_burst(ball_pos, Color.WHITE, 24)
		hue_shift += 0.1
	else:
		_popup("+%d" % gain, at, COLOR_PLAYER)
	points += gain


func _trip() -> float:
	# 0 = calm, 1 = full psychedelic. Rises with the combo.
	return minf(float(combo) / COMBO_FOR_MAX_TRIP, 1.0)


func _popup(text: String, at: Vector2, color: Color, life: float = 0.9) -> void:
	popups.append({"text": text, "pos": at, "rise": 0.0, "life": life, "color": color})


func _load_best() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	# Version 1 only stored best points; best_stage was added in version 2,
	# so older saves simply start it at 0.
	best = int(cfg.get_value("stats", "best", 0))
	best_stage = int(cfg.get_value("stats", "best_stage", 0))


func _save_best() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "save_version", SAVE_VERSION)
	cfg.set_value("stats", "best", best)
	cfg.set_value("stats", "best_stage", best_stage)
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


func _draw_paddle(x: float, y: float, width: float, color: Color) -> void:
	var size := Vector2(width, PADDLE_SIZE.y)
	var rect := Rect2(_snap(Vector2(x, y) - size / 2.0), size)
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


func _draw_heart(origin: Vector2, cell: float, color: Color) -> void:
	for row in HEART_SHAPE.size():
		for col in HEART_SHAPE[row].length():
			if HEART_SHAPE[row][col] == "#":
				draw_rect(Rect2(origin + Vector2(col, row) * cell, Vector2(cell, cell)), color)


func _draw_cards() -> void:
	var font := ThemeDB.fallback_font
	draw_rect(Rect2(Vector2.ZERO, screen), Color(0, 0, 0, 0.55))
	var cy := screen.y / 2.0
	var top := cy - (250.0 if landscape else 400.0)
	var title := "BOSS DEFEATED!" if pick_relic else "STAGE %d CLEAR!" % stage
	_draw_label(title, top, 64, _rainbow(0.0).lightened(0.3))
	_draw_label("+%d bonus  -  pick %s" % [stage_bonus, "a relic" if pick_relic else "an upgrade"],
		top + 64.0, 36, Color.WHITE)
	var rects := _card_rects()
	for i in rects.size():
		var rect := rects[i]
		var id := offers[i]
		var info: Array = RELICS[id] if pick_relic else UPGRADES[id]
		if i == pick_index:
			draw_rect(rect.grow(PX * 1.5), _rainbow(0.0))
		_draw_block(rect, Color(0.08, 0.04, 0.16, 0.95))
		var name_color := Color(info[2]) if pick_relic else _rainbow(i * 0.33).lightened(0.3)
		_draw_fitted(info[0], rect, 0.4, 40, name_color)
		_draw_fitted(info[1], rect, 0.66, 28, Color.WHITE)
		var note := "RELIC"
		if not pick_relic:
			var owned: int = hearts if id == "heart" else (shields if id == "shield" else levels.get(id, 0))
			note = "have %d" % owned
		_draw_fitted(note, rect, 0.88, 22, Color(1, 1, 1, 0.6))


func _draw_fitted(text: String, rect: Rect2, height: float, size: int, color: Color) -> void:
	# Centred in the card at a fraction of its height, shrunk until it fits.
	var font := ThemeDB.fallback_font
	while size > 16 and font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > rect.size.x - 24.0:
		size -= 2
	draw_string(font, Vector2(rect.position.x, rect.position.y + rect.size.y * height), text,
		HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, size, color)


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
	_draw_paddle(ai_x, AI_Y, _ai_width(), COLOR_AI)
	if _boss() == Boss.TWINS:
		_draw_paddle(_twin_x(), TWIN_Y, PADDLE_SIZE.x, COLOR_AI.darkened(0.2))
	_draw_paddle(player_x, PLAYER_Y, _player_width(), COLOR_PLAYER)
	# Shield charges: stacked glowing bars behind the player.
	for i in shields:
		var y := SHIELD_Y + i * PX * 1.5
		draw_rect(Rect2(0, y, W, PX / 2.0), Color("#4cc9f0", 0.85 - i * 0.25))
	for spark in sparks:
		var size := PX * clampf(spark.life * 2.0, 0.5, 1.0)
		draw_rect(Rect2(_snap(spark.pos), Vector2(size, size)), spark.color)
	if not game_over and not picking:
		for i in range(trail.size() - 1, 0, -1):
			var fade := 1.0 - float(i) / TRAIL_LEN
			draw_rect(Rect2(trail[i] - Vector2(PX, PX), Vector2(PX, PX) * 2.0),
				Color(_rainbow(i * 0.08), fade * 0.8))
		_draw_ball(ball_pos, Color.WHITE, true)
		_draw_ball(ball_pos, _rainbow(0.0).lightened(0.6), false)

	if _boss() == Boss.PHANTOM:
		# A band of flickering fog the ball disappears into.
		draw_rect(Rect2(0, FOG_TOP, W, FOG_BOTTOM - FOG_TOP), Color(0.12, 0.0, 0.18, 0.93))
		var flicker := int(art_time * 12.0)
		for i in 40:
			var h := posmod(hash(flicker * 97 + i), 1 << 30)
			var cell := Vector2(h % 90, (h / 90) % int((FOG_BOTTOM - FOG_TOP) / PX)) * PX
			draw_rect(Rect2(Vector2(0, FOG_TOP) + cell, Vector2(PX, PX)), _rainbow(i * 0.05).darkened(0.5))

	if _is_boss():
		# Boss health: one block per point still needed.
		var left := _stage_target() - score_player
		var seg := Vector2(64, 16)
		var start := W / 2.0 - (BOSS_HP * (seg.x + PX) - PX) / 2.0
		for i in BOSS_HP:
			var rect := Rect2(Vector2(start + i * (seg.x + PX), AI_Y + 50.0), seg)
			_draw_block(rect, COLOR_AI if i < left else Color(0.2, 0.2, 0.2, 0.8))

	draw_set_transform(Vector2.ZERO)

	# Scores stay upright, so they are placed on screen rather than in the field.
	_draw_number(score_ai, _to_screen(Vector2(W / 2.0, H / 2.0 - 110.0)), 16.0, COLOR_AI)
	_draw_number(score_player, _to_screen(Vector2(W / 2.0, H / 2.0 + 110.0)), 16.0, COLOR_PLAYER)

	# Points (opposite corner to the music button) and combo
	var cy := screen.y / 2.0
	var font := ThemeDB.fallback_font
	# Stage, points and hearts share one box.
	var hud_x := screen.x - 390.0 if landscape else 10.0
	draw_rect(Rect2(hud_x, 14, 380, 50), Color(0, 0, 0, 0.55))
	if god_mode:
		draw_string(font, Vector2(hud_x + 300.0, 92.0), "GOD", HORIZONTAL_ALIGNMENT_RIGHT, 70, 22, COLOR_PLAYER)
	draw_string(font, Vector2(hud_x + 14.0, 50.0), "ST %d  PTS %d" % [stage, points],
		HORIZONTAL_ALIGNMENT_LEFT, 220, 26, Color(1, 1, 1, 0.9))
	var heart_x := hud_x + 226.0
	for i in mini(hearts, 5):
		_draw_heart(Vector2(heart_x + i * 30.0, 28.0), 3.0, COLOR_AI)
	if hearts > 5:
		draw_string(font, Vector2(heart_x + 150.0, 50.0), "+%d" % (hearts - 5),
			HORIZONTAL_ALIGNMENT_LEFT, 40, 22, COLOR_AI)
	# Relics owned this run: little gems under the box.
	for i in relics.size():
		var gem := Rect2(hud_x + 14.0 + i * 30.0, 72.0, 22.0, 22.0)
		draw_rect(gem.grow(3.0), OUTLINE)
		draw_rect(gem, Color(RELICS[relics[i]][2]))
		draw_string(font, gem.position + Vector2(0, 18), RELICS[relics[i]][0].left(1),
			HORIZONTAL_ALIGNMENT_CENTER, gem.size.x, 18, Color.BLACK)
	if combo >= 2 and not game_over and not picking and boss_intro <= 0.0:
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
	if picking:
		_draw_cards()
	elif game_over:
		_draw_label("RUN OVER", cy - 230.0, 72, _rainbow(0.0).lightened(0.3))
		_draw_label("STAGE %d  -  %d POINTS" % [stage, points], cy - 140.0, 44, Color.WHITE)
		if new_best:
			_draw_label("NEW BEST!", cy + 200.0, 56, _rainbow(0.5).lightened(0.3))
		else:
			_draw_label("BEST %d  -  STAGE %d" % [best, best_stage], cy + 200.0, 40, Color.WHITE)
		_draw_label("Tap to play again", cy + 300.0, 40, Color.WHITE)
		if cheated:
			_draw_label("Test run - records not saved", cy + 380.0, 30, Color(1, 1, 1, 0.7))
	elif boss_intro > 0.0:
		var info: Array = BOSSES[_boss()]
		_draw_label("BOSS: %s" % info[0], cy + 150.0, 56, COLOR_AI.lightened(0.2))
		_draw_label(info[1], cy + 215.0, 34, Color.WHITE)
	elif not has_touched and not title:
		_draw_label("Drag to move", field_rect.end.y - (120.0 if landscape else 220.0), 40, Color.WHITE)

	if test_menu:
		_draw_test_menu()
	if title:
		_draw_title()
