# GRAPHICS UPGRADE — what changed

Date: 2026-10-20 · Scope: visuals only. No gameplay mechanics, physics,
input, traffic or driving code was changed. Everything below is cheap on
mobile: material properties, one shared unit-box mesh, instancing — no
textures, no extra light nodes, no post-processing passes beyond the
environment tonemap/adjustment the engine already runs.

## Sky, light and atmosphere (`scenes/main.tscn`)

- Flat blue background replaced by a **ProceduralSkyMaterial** gradient
  sky (deep blue zenith → pale horizon, warm ground bounce) in a `Sky`
  resource; the Environment now uses `background_mode = Sky`.
- **Ambient light now comes from the sky** (`ambient_light_source = Sky`,
  energy 0.85) instead of a flat colour, so buildings shade consistently
  with the sky.
- **ACES tonemapping** (`tonemap_mode = 3`) plus a mild colour adjustment
  (brightness 1.03, contrast 1.05, saturation 1.15) — richer, less washed
  out colours.
- **Depth fog enabled**, coloured like the horizon. Its range is *not*
  fixed in the scene: `Settings.apply_scene_settings()` sets
  `fog_depth_begin = view_distance × 0.55` and
  `fog_depth_end = view_distance + 80` on every settings change, so the
  fog always hugs the draw distance and hides chunk-culling pop-in.
- **Sun**: warmer colour (1, 0.95, 0.86), energy 1.1 → 1.25, shadow
  opacity 0.9, and a new angle (rotated −50° X, −30° Y) so late-afternoon
  shadows rake diagonally across the streets instead of lining up with
  the grid.

## Preset-scaled shadow quality (`scripts/settings.gd`)

Two new per-preset knobs, applied live in `apply_scene_settings()`:

| Preset   | shadow_splits | shadow_blur | (existing shadow atlas) |
|----------|---------------|-------------|-------------------------|
| Low      | off (shadows disabled, as before) | 1.0 | 1024 |
| Balanced | 2 splits      | 1.1         | 2048 |
| High     | 4 splits      | 1.4         | 4096 |
| Ultra    | 4 splits      | 1.6         | 4096 |

`directional_shadow_max_distance` is also set from the view distance
(+80 m) so shadow coverage matches what the player can actually see.
Low stays light exactly as before: shadows off, city shadow-casting off.

## City look (`scripts/main.gd`)

- Building palette grew from 4 flat greys/browns to **6 materials**:
  sandstone, brick red, light concrete, slate blue-grey, cream, and a
  semi-polished **teal glass** material (roughness 0.35, metallic 0.35)
  with a **faint emission** (energy 0.3) so glass towers read as sunlit
  windows with zero textures.
- **Per-building colour variation**: building MultiMeshes now use
  `use_colors`; every one of the 147 buildings gets a subtle tint
  (brightness 0.80–1.02 with a faint warm/cool shift), multiplied over
  its material colour (`vertex_color_use_as_albedo`). No two buildings
  look identical, at zero extra draw calls.
- **Rooftop detail**: buildings taller than 8 m get a small dark roof
  box (plant/stair housing) — breaks up the flat skyline from the orbit
  camera for one extra instanced box per tall building.
- **Road/pavement contrast**: pavement slabs lightened
  (0.32 → 0.40 grey) while the asphalt ground in the scene darkened
  (0.23 → 0.19), so the street grid reads clearly.
- Chunk mesh count rose 63 → **106** (still one draw call per
  chunk × material, still distance-culled as before).

Deliberately skipped: real window textures. A shared box mesh can't
scale UVs per instance, so a window texture would stretch differently
on every building and look worse than the clean palette + glass look.

## Cars and player

- Traffic cars (`scripts/traffic_car.gd`): paint roughness 0.55 → 0.38,
  metallic 0.25 → 0.45; cabin glass roughness 0.25 → 0.15, metallic
  0.4 → 0.6. Added tiny **emissive headlight/taillight strips** (warm
  front, red rear, emission-only — no light nodes).
- Hero car (`scripts/drivable_car.gd`): glossier paint (roughness
  0.35 → 0.26, metallic 0.35 → 0.5), same glass polish, same emissive
  light strips.
- Player capsule (`scenes/main.tscn`): slightly deeper orange,
  roughness 0.7 → 0.55, metallic 0.05.

## Verification (this VM, headless)

- Import: `godot --headless --editor --import --path .` — clean, exit 0.
- Scene run: `godot --headless --path . --quit-after 600` — exit 0, no
  errors/warnings.
- Smoke test: `godot --headless --path . -s res://tests/smoke_test.gd` —
  **24 / 24 PASS, exit 0** (city now reports 106 MultiMesh chunks).
- Extra runtime probe confirmed: 75 building MultiMeshes carry instance
  colours (147/147 buildings tinted); after switching to High, the
  environment fog reads 110 → 280 m and the sun shows 4 splits /
  blur 1.4 / max distance 280 m, exactly as the preset defines.

## Honest limits

- Headless runs use the dummy rendering driver: logic, settings and
  data paths are verified, **the actual pixels are not**. The new look
  still needs a visual once-over in a real build on a phone.
- No APK was built and nothing was pushed to GitHub (per instructions).
- As before, no FPS figure is claimed for any real device.
