# Aberrant — Game Jam CSUI 2026

Roguelite 2D top-down dark-fantasy bertema **Underdark** (terinspirasi BG3). Player adalah slime anomali yang memberontak dari ritual.

**Core fantasy:** "Arena Brawler di mana arena itu sendiri adalah pertarungan." Player **tidak punya serangan langsung** — satu-satunya cara melawan adalah memanfaatkan environment (lempar item ke musuh).

## Tech Stack

- **Engine:** Godot 4.x, GDScript
- **Viewport:** 1280×720, `stretch/mode = canvas_items`, `aspect = keep`
- **Camera2D zoom:** 3.79 (di room_2.tscn — bukan 9 lagi)
- **OS dev:** Windows 11, bash (Git Bash) + PowerShell

## Diversifiers (sudah ditetapkan)

- **D8** Margo Meleduk — destructible environment
- **D69** John Wick — environment as weapon (lempar barang)
- **D47** Sis Puella Magica! — boss multi-phase

## Struktur Folder

```
tugas-proyek/
├── assets/sprites/
│   ├── characters/cult/    # spawn_spritesheet, walk frames, cast frames
│   ├── environment/room2/  # background image room 2
│   ├── items/iron_chain.png
│   └── slime_spritesheet.png
├── scenes/
│   ├── Slime.tscn          # Player (CharacterBody2D root)
│   ├── Enemies.tscn        # Cult enemy (CharacterBody2D root)
│   ├── room_2.tscn         # Current playable room
│   ├── IronChain.tscn      # Throwable item (Area2D)
│   ├── RedHeart.tscn       # Heal drop on cult death
│   ├── BlueHeart.tscn      # Alternative heart variant
│   ├── InventoryUI.tscn    # 5-slot HUD (CanvasLayer)
│   ├── CultProjectile.tscn # Cast spell projectile
│   └── Start.tscn          # Main menu
├── scripts/
│   ├── Player.gd           # WASD + Shift dash + inventory + heal
│   ├── Enemy.gd            # State machine + entangle + respawn
│   ├── ThrowableItem.gd    # Base class (pickup/throw/drop/respawn)
│   ├── IronChain.gd        # extends ThrowableItem, applies entangle
│   ├── HealthHeart.gd      # Pickup → heal +1 HP
│   ├── InventoryUI.gd      # HUD prosedural 5 slot
│   ├── PlayerHealthUI.gd   # Hearts row, BOTTOM_MARGIN=110 (atas inventory)
│   ├── HealthBar.gd        # Enemy HP bar
│   ├── StatusEffectBar.gd  # "ENTANGLED" timer bar above HP
│   ├── CultProjectile.gd   # Damaging projectile
│   └── Portal.gd           # Room transition Area2D
└── project.godot
```

## Sistem yang Sudah Diimplementasi

### Player (`Player.gd` — extends `CharacterBody2D`)
- Movement: **WASD** (via `Input.is_physical_key_pressed`)
- Dash: **Shift** key (`_dash_requested` flag, consumed di `_physics_process`)
- HP: 3 max, dengan invincibility frames saat dash
- Inventory: array max 5 slot, `active_slot` int
- Throw: **left click** ke arah cursor (item dari active slot)
- Drop: **G** key (di posisi player + random offset)
- Slot select: **1–5** keys atau scroll wheel
- Heal: `heal(amount)` clamps ke `max_hp`

### Enemy (`Enemy.gd` — extends `CharacterBody2D`)
- State machine: `DORMANT → SPAWNING → WALK ↔ IDLE → CAST`
- Detection via `DetectionArea` Area2D
- **Cast spell:** AnimationPlayer plays cast anim, charges projectile di `staff_tip`, releases on `animation_finished`
- **Entangle:** `apply_entangle(duration)` → freeze movement (move_speed=0), cancel cast, force IDLE, spawn `StatusEffectBar` di atas HP bar, restore setelah duration
- **Death + Respawn:** `_die_and_respawn()`:
  - drop loot (heart) di posisi mati
  - `animated_sprite.stop()` ← **PENTING:** prevent stale `animation_finished` dari pull state out of DORMANT
  - hide, await respawn_delay, reset HP, `spawn_at(home)` → play spawn anim → WALK
  - `respawn_count` per enemy (default 1, queue_free setelah habis)
- **Cull-of-stale-signals guard:** `_on_animation_finished` return early kalau `state == DORMANT`

### Throwable Item System (`ThrowableItem.gd` — base Area2D)
- States: `GROUND / HELD / FLYING`
- `throw_toward(origin, target_pos)` → bergerak ke arah target sampai `max_range`
- `on_pickup()` → hide + disable collision + schedule respawn timer (di parent room, bukan di item — supaya respawn fire walaupun item di-queue_free)
- `_spawn_pos` & `_spawn_scale` di-capture di `_ready()` — **respawn lambda explicit propagate ke instance baru** (karena `_ready` capture sebelum position/scale di-set)
- `destroy_on_hit: bool` — IronChain pakai true (chain disappear setelah hit)

### Hearts (`HealthHeart.gd`)
- Area2D, draw heart shape di `_draw()` (2 lingkaran + segitiga)
- Pulse animation via `_time` + `sin()`
- `body_entered` → call `body.heal(heal_amount)` jika player → queue_free
- Variants: `RedHeart.tscn` (merah, drop dari cult), `BlueHeart.tscn` (biru, future use)

### UI
- **Inventory** di `CanvasLayer` layer=5, 5 slot 58×80 di bottom-center, dibuild prosedural di `InventoryUI.gd`
- **Hearts player** di atas inventory, BOTTOM_MARGIN=110
- **Status effect bar** di-draw di atas HP bar enemy, 160×14, font_size 28 dengan outline 4px
- **Kill counter** di top-center, layer=6, 260×52 panel. Auto-scan group "enemy" dan sum (1 + respawn_count) per enemy. Listen ke signal `Enemy.died`. Di-instance per room (`KillCounterUI.tscn`).

## Collision Layers (PENTING)

| Layer | Untuk | Contoh |
|---|---|---|
| 1 | Walls + Player + Furniture | StaticBody2D, Player CharacterBody2D |
| 2 | Enemies | Cult CharacterBody2D |
| 3 | (unused) | |
| 4 | Items | Chain, Heart Area2D |

**Mask penting:**
- Player: layer=1, mask=1 (collides walls only, **passes through cult**)
- Cult: layer=2, mask=1 (collides walls only)
- Chain: layer=4, mask=3 (1\|2 — detects player AND cult)
- Heart: layer=4, mask=1 (detects player only)

Jangan ubah layer cult ke 1 — itu menyebabkan "invisible wall" dari cult yang respawn off-screen.

## Konvensi Coding

- **Bahasa komentar/dokumen:** Indonesia + English campuran OK
- **Style:** snake_case untuk vars/methods, PascalCase untuk classes, ALL_CAPS untuk constants
- **Tabs** untuk indent (Godot default), bukan spaces
- **Tidak pakai TaskCreate/Agent** kecuali user minta — ini single-dev project, scope kecil
- **Skip CLAUDE.md updates** kecuali user minta atau ada sistem baru yang substantial
- Verifikasi UI changes: tidak bisa run Godot dari CLI di sini, jadi sampaikan eksplisit kalau perlu user test di editor

## Gotchas yang Sudah Ketemu

1. **`_ready()` race condition saat respawn item:** instance baru capture `global_position` sebelum di-set → wrong `_spawn_pos`. Fix: explicit set `_spawn_pos`/`_spawn_scale` di lambda setelah `add_child`.
2. **Stale `animation_finished` saat death:** cast anim selesai mid-await → state ditarik ke IDLE → `spawn_at` early-return. Fix: `animated_sprite.stop()` + state guard di handler.
3. **Resolution scaling:** sebelumnya tidak ada stretch settings → camera "menjauh" saat resize. Fix: `canvas_items` + `keep`.
4. **Launch grace di chain:** awalnya 0.12s grace bikin moving cult skip hit (body_entered ignored, cult exit area, no re-entry). Fix: hapus launch_grace.
5. **Background furniture collision:** user prefer buat sendiri di editor (lebih presisi visual matching). **Jangan auto-generate furniture colliders** — user akan buat manual di `room_2.tscn` Walls/Furniture node.

## Status Progress (terakhir update 2026-04-27)

- ✅ Movement WASD + Shift dash
- ✅ Inventory 5 slot dengan icon + nama
- ✅ Iron chain throw mechanic + entangle effect
- ✅ Cult AI (walk/idle/cast) dengan respawn
- ✅ Heart drop on death (red), heal player +1
- ✅ HP UI + Inventory UI tidak overlap
- ✅ Status bar "ENTANGLED" di atas HP cult
- ⬜ Background collision shapes (user buat manual di editor)
- ⬜ Phase 2 cult abilities
- ⬜ Boss room (Raja Underdark, 3 phase)
- ⬜ Room generator (random shuffle)
- ⬜ Audio polish

## Workflow Notes

- Edit `.gd` script via Edit/Write tool langsung
- Edit `.tscn` text-based juga, hati-hati format `[ext_resource]`, `[sub_resource]`, `[node ...]`
- **JANGAN auto-commit** — user pegang git sendiri
- Untuk image assets: kalau perlu generate, pakai Python PIL via Bash
