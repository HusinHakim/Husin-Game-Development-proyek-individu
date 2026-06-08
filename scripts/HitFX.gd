extends Node
# Autoload "HitFX" — game-feel "juice" saat thrown item mengenai enemy.
# Dipanggil dari ThrowableItem._hit_enemy() sehingga SEMUA enemy (Cult,
# CorruptedGolem, RockBoss) dapat efek yang sama lewat satu choke point.
#
# Tiga efek yang diimplement:
#   1. Hit-stop  — freeze waktu sesaat saat impact (rasa "berat").
#   4. Knockback — enemy tersentak mundur ke arah lempar.
#   6. Particle  — percikan kecil di titik kena.
#
# CATATAN PENTING: hit-stop dijalankan dari autoload (bukan dari item) karena
# IronChain di-queue_free() begitu kena. Kalau `await` time_scale ada di item
# yang keburu free, Engine.time_scale nyangkut di 0 dan game freeze selamanya.

# Tuning default — ubah di sini untuk menyetel "feel".
const HITSTOP_DURATION := 0.07     # detik (real-time, tidak terpengaruh freeze)
const HITSTOP_SCALE := 0.0         # 0.0 = freeze penuh
const KNOCKBACK_DISTANCE := 14.0   # px nudge mundur
const KNOCKBACK_DURATION := 0.12   # detik
const PARTICLE_AMOUNT := 14
const FLASH_DURATION := 0.09                 # detik
const FLASH_COLOR := Color(2.6, 2.6, 3.0)    # over-bright → tampak putih (modulate >1)

# Generasi hit-stop: kalau dua hit beruntun, hanya timer terbaru yang
# mengembalikan time_scale ke 1.0 supaya freeze tidak terputus di tengah.
var _hitstop_gen: int = 0


# Entry point tunggal. Panggil ini sekali per hit.
func on_hit(enemy: Node, hit_pos: Vector2, hit_dir: Vector2) -> void:
	hit_dir = hit_dir.normalized()
	# #2 Hit flash — tiap enemy meng-handle sprite-nya sendiri (struktur node
	# beda-beda) dan men-skip saat sekarat. Golem sudah punya flash internal.
	if enemy.has_method("flash_hit"):
		enemy.flash_hit()
	hit_stop()
	knockback(enemy, hit_dir)
	spawn_hit_particles(enemy, hit_pos, hit_dir)


# --- 1. Hit-stop --------------------------------------------------------------
func hit_stop(duration: float = HITSTOP_DURATION, scale: float = HITSTOP_SCALE) -> void:
	_hitstop_gen += 1
	var gen := _hitstop_gen
	Engine.time_scale = scale
	# create_timer(time, process_always, process_in_physics, ignore_time_scale)
	# ignore_time_scale=true → timer tetap jalan walau dunia ter-freeze.
	await get_tree().create_timer(duration, true, false, true).timeout
	# Hanya pulihkan kalau tidak ada hit-stop lebih baru yang sedang aktif.
	if gen == _hitstop_gen:
		Engine.time_scale = 1.0


# --- 2. Hit flash -------------------------------------------------------------
# Over-bright modulate sesaat → sprite "berkilat putih". Dipanggil oleh
# flash_hit() tiap enemy dengan node sprite-nya masing-masing.
func flash(sprite: CanvasItem, duration: float = FLASH_DURATION, color: Color = FLASH_COLOR) -> void:
	if not is_instance_valid(sprite):
		return
	var original: Color = sprite.modulate
	sprite.modulate = color
	# ignore_time_scale=true → restore tetap jalan walau dunia ter-freeze hit-stop.
	await get_tree().create_timer(duration, true, false, true).timeout
	if is_instance_valid(sprite):
		sprite.modulate = original


# --- 4. Knockback -------------------------------------------------------------
func knockback(body: Node, dir: Vector2, distance: float = KNOCKBACK_DISTANCE, duration: float = KNOCKBACK_DURATION) -> void:
	if not is_instance_valid(body) or not (body is Node2D):
		return
	# Optional per-enemy: properti `knockback_resist` (0..1) untuk mengurangi
	# dorongan (mis. boss berat). Default 0 = tanpa resist.
	var resist := 0.0
	if "knockback_resist" in body:
		resist = clampf(body.knockback_resist, 0.0, 1.0)
	var dist := distance * (1.0 - resist)
	if dist <= 0.0:
		return
	var node := body as Node2D
	var target := node.global_position + dir.normalized() * dist
	# Tween menghormati time_scale → selama freeze ia diam, lalu menyentak
	# saat waktu berjalan lagi. Itu justru pola juicy: freeze → snap.
	var tween := node.create_tween()
	tween.tween_property(node, "global_position", target, duration) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


# --- 6. Hit particles ---------------------------------------------------------
func spawn_hit_particles(enemy: Node, pos: Vector2, dir: Vector2) -> void:
	var parent: Node = null
	if is_instance_valid(enemy) and enemy is Node2D:
		parent = (enemy as Node2D).get_parent()
	if not is_instance_valid(parent):
		parent = get_tree().current_scene
	if not is_instance_valid(parent):
		return

	var p := CPUParticles2D.new()
	p.emitting = false
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = PARTICLE_AMOUNT
	p.lifetime = 0.45
	p.local_coords = false
	p.z_index = 50

	# Semburan mengarah berlawanan dengan arah lempar (memantul dari tubuh).
	p.direction = -dir.normalized()
	p.spread = 60.0
	p.initial_velocity_min = 120.0
	p.initial_velocity_max = 280.0
	p.gravity = Vector2(0, 520)
	p.damping_min = 40.0
	p.damping_max = 90.0

	# Pecahan kecil ala pixel-chunk.
	p.scale_amount_min = 2.0
	p.scale_amount_max = 4.0

	# Warna: percikan terang → fade ungu (tema Underdark) + serpihan abu rantai.
	# Set kedua endpoint dulu (Gradient default punya titik di offset 0 & 1),
	# baru tambah titik tengah — add_point() menggeser index, jadi urutan penting.
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.95, 0.8, 1.0))      # spark terang
	grad.set_color(1, Color(0.45, 0.45, 0.5, 0.0))     # abu rantai, fade out
	grad.add_point(0.45, Color(0.65, 0.35, 0.95, 1.0)) # ungu (titik tengah)
	p.color_ramp = grad

	parent.add_child(p)
	p.global_position = pos
	p.emitting = true

	# Bersihkan diri setelah burst selesai.
	p.finished.connect(p.queue_free)


# --- SFX -----------------------------------------------------------------------
# Suara rantai saat enemy ter-entangle (cult & final boss). Lazy-load supaya
# autoload tidak gagal compile kalau import audio belum siap.
const CHAIN_ENTANGLE_SFX_PATH := "res://assets/audio/sfx/chain_entangle.ogg"
var _chain_entangle_sfx: AudioStream = null


func play_entangle_sfx() -> void:
	if _chain_entangle_sfx == null:
		_chain_entangle_sfx = load(CHAIN_ENTANGLE_SFX_PATH)
	_play_sfx(_chain_entangle_sfx)


func _play_sfx(stream: AudioStream, volume_db: float = 0.0) -> void:
	if stream == null:
		return
	var parent: Node = get_tree().current_scene
	if not is_instance_valid(parent):
		parent = self
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = volume_db
	parent.add_child(p)
	p.play()
	p.finished.connect(p.queue_free)
