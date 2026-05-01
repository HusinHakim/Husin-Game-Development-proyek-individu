extends Node2D
# ShieldVisual — temporary buckler shield active for `duration` seconds.
# Spawned as a child of Player. Player updates `rotation` each frame to
# point toward the mouse. Each frame we scan for attacking enemies inside
# the shield's cone and stun them. The shield stays up for the full
# duration regardless of how many enemies are deflected; each enemy can
# only be deflected once per shield window.
#
# Visual: hex-core energy buckler floating in front of the player. A faint
# arc behind it hints at the parry zone. On a successful deflect, a white
# shockwave + radial spike-burst flashes outward from the shield core.

signal deflected(enemy: Node)
signal expired

@export var duration: float = 1.6               # active window — long enough to catch boss windup reliably
@export var radius: float = 55.0                # max distance from player center (also parry-arc visual radius)
@export var arc_half_span_deg: float = 75.0     # 150° forward cone
@export var stun_duration: float = 3.0

var elapsed: float = 0.0
var _deflected_ids: Dictionary = {}   # instance_id → true; prevents re-stunning same enemy
var _spin: float = 0.0                # rim-spark rotation
var _flash_t: float = 0.0             # 1.0 → 0.0 deflect shockwave intensity
var _spawn_t: float = 0.0             # 0.0 → 1.0 quick activation easing


func _ready() -> void:
	z_index = 50
	z_as_relative = false
	set_process(true)
	# Self-listen so the visual flashes when something is deflected.
	deflected.connect(_on_self_deflected)
	# Counter-scale the parent so the buckler renders at a consistent world
	# size regardless of how heavily the player is scaled in any given room.
	var parent := get_parent()
	if parent is Node2D:
		var s: Vector2 = (parent as Node2D).scale
		if absf(s.x) > 0.001 and absf(s.y) > 0.001:
			scale = Vector2(1.0 / s.x, 1.0 / s.y)
	print("[Shield] activated")


func _on_self_deflected(_enemy: Node) -> void:
	_flash_t = 1.0


func _process(delta: float) -> void:
	elapsed += delta
	_spawn_t = clampf(_spawn_t + delta * 9.0, 0.0, 1.0)
	_spin += delta * 4.5
	if _flash_t > 0.0:
		_flash_t = maxf(_flash_t - delta * 3.5, 0.0)
	if elapsed >= duration:
		expired.emit()
		_fade_and_free()
		return
	_check_deflect()
	queue_redraw()


func _check_deflect() -> void:
	# Pure timing-based parry: any enemy that transitions into the actual
	# swing/stomp (red telegraph just finished) while the shield is active
	# gets stunned, regardless of position or shield-arc direction. The
	# shield's cone is purely a visual cue. Each enemy can only be deflected
	# once per shield window (tracked via _deflected_ids).
	for n in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(n):
			continue
		var id: int = n.get_instance_id()
		if _deflected_ids.has(id):
			continue
		if not _is_attacking(n):
			continue
		if n.has_method("apply_stun"):
			n.apply_stun(stun_duration)
		_deflected_ids[id] = true
		deflected.emit(n)


func _is_attacking(enemy: Node) -> bool:
	# Only deflectable AFTER the red telegraph (WINDUP) finishes — i.e. when
	# the boss has committed to the actual swing/stomp. The classic parry
	# timing: see red area, hold off, click shield right as it ends.
	if "state" in enemy:
		var s = enemy.state
		if typeof(s) == TYPE_INT:
			return s == 5 or s == 6     # SWIPE (5) or STOMP (6)
	return false


func _fade_and_free() -> void:
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.18)
	tw.tween_callback(queue_free)


func _draw() -> void:
	var t: float = clampf(elapsed / maxf(duration, 0.001), 0.0, 1.0)
	var pulse: float = 0.65 + 0.35 * sin(elapsed * 9.0)
	var fade: float = 1.0 - smoothstep(0.7, 1.0, t) * 0.5
	# Activation easing: ease-out cubic so it pops into existence cleanly.
	var grow: float = 1.0 - pow(1.0 - _spawn_t, 3.0)

	# Buckler sits ~45% of radius forward from the player, perpendicular to facing.
	var center: Vector2 = Vector2(radius * 0.45, 0.0)
	var R_outer: float = 20.0 * grow
	var R_inner: float = 13.0 * grow

	# 1) Faint forward parry-arc (visual cue for the player; secondary to buckler)
	var n: int = 26
	var arc_rad: float = deg_to_rad(arc_half_span_deg)
	var arc_pts: PackedVector2Array = PackedVector2Array()
	for i in range(n + 1):
		var a: float = -arc_rad + (2.0 * arc_rad) * float(i) / float(n)
		arc_pts.append(Vector2(cos(a), sin(a)) * radius)
	# Translucent fan fill behind buckler — communicates the "parry zone"
	var fan_pts: PackedVector2Array = PackedVector2Array()
	fan_pts.append(Vector2.ZERO)
	for p in arc_pts:
		fan_pts.append(p)
	draw_colored_polygon(fan_pts, Color(0.30, 0.65, 1.00, 0.06 * pulse * fade))
	# Thin rim along the arc
	for i in range(arc_pts.size() - 1):
		draw_line(arc_pts[i], arc_pts[i + 1], Color(0.50, 0.85, 1.00, 0.32 * pulse * fade), 2.0)

	# 2) Outer aura — soft halo around the buckler core
	for i in range(4):
		var alpha: float = (0.10 - i * 0.022) * pulse * fade
		var r_layer: float = R_outer + 2.0 + i * 3.0
		draw_circle(center, r_layer, Color(0.30, 0.65, 1.00, alpha))

	# 3) Hex shield body — rotating slowly for "live energy" feel
	var hex_pts: PackedVector2Array = _hex_points(center, R_outer, _spin * 0.25)
	draw_colored_polygon(hex_pts, Color(0.18, 0.42, 0.72, 0.55 * pulse * fade))
	# Hex outline (bright cyan rim, multiple passes for thickness without AA gaps)
	for i in range(hex_pts.size()):
		var p1: Vector2 = hex_pts[i]
		var p2: Vector2 = hex_pts[(i + 1) % hex_pts.size()]
		draw_line(p1, p2, Color(0.20, 0.45, 0.80, 0.70 * fade), 3.5)
		draw_line(p1, p2, Color(0.65, 0.95, 1.00, 0.95 * fade), 2.0)
		draw_line(p1, p2, Color(0.95, 1.00, 1.00, 0.85 * fade), 0.8)

	# 4) Inner counter-rotating hex rune
	var hex_inner: PackedVector2Array = _hex_points(center, R_inner, -_spin * 0.4)
	for i in range(hex_inner.size()):
		var p1: Vector2 = hex_inner[i]
		var p2: Vector2 = hex_inner[(i + 1) % hex_inner.size()]
		draw_line(p1, p2, Color(0.85, 0.98, 1.00, 0.85 * fade), 2.0)

	# 5) Inner rune cross (looks like a magic circle)
	for i in range(3):
		var ang: float = -_spin * 0.4 + i * PI / 3.0
		var d: Vector2 = Vector2(cos(ang), sin(ang)) * R_inner
		draw_line(center - d, center + d, Color(0.65, 0.92, 1.00, 0.45 * fade), 1.0)

	# 6) Center crystal — bright core
	draw_circle(center, 4.0, Color(0.35, 0.75, 1.00, 0.60 * pulse * fade))
	draw_circle(center, 2.8, Color(0.90, 0.99, 1.00, 0.95 * fade))
	draw_circle(center, 1.4, Color(1.0, 1.0, 1.0, fade))

	# 7) Spinning rim sparks — three small dots orbiting the buckler
	for i in range(3):
		var ang2: float = _spin + i * TAU / 3.0
		var p: Vector2 = center + Vector2(cos(ang2), sin(ang2)) * (R_outer + 3.0)
		draw_circle(p, 2.5, Color(0.35, 0.75, 1.00, 0.5 * fade))
		draw_circle(p, 1.5, Color(0.95, 1.00, 1.00, 0.95 * fade))

	# 8) Deflect shockwave — white burst that expands outward from buckler core
	if _flash_t > 0.0:
		var prog: float = 1.0 - _flash_t
		var flash_r: float = R_outer + prog * 60.0
		var flash_a: float = _flash_t * 0.85
		# Expanding ring
		draw_arc(center, flash_r, 0.0, TAU, 36, Color(1.0, 1.0, 1.0, flash_a), 4.0)
		draw_arc(center, flash_r * 0.7, 0.0, TAU, 32, Color(0.85, 0.98, 1.00, flash_a * 0.7), 2.0)
		# Radial spike lines bursting outward
		for i in range(8):
			var ang3: float = i * TAU / 8.0 + _spin * 0.5
			var p1: Vector2 = center + Vector2(cos(ang3), sin(ang3)) * (R_outer + 2.0)
			var p2: Vector2 = center + Vector2(cos(ang3), sin(ang3)) * flash_r
			draw_line(p1, p2, Color(1.0, 1.0, 1.0, flash_a), 2.5)


static func _hex_points(c: Vector2, r: float, rot: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(6):
		var a: float = rot + i * TAU / 6.0
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	return pts
