# My GTA World

An open-world driving/action game scaffold built with **Godot 4.7.2 (stable)**,
GDScript, Android-first and fully offline. This first milestone is the
**performance & compatibility foundation** Jalal asked for: selectable frame
rates (30/60/90/Auto), runtime graphics presets, battery saver, distance
culling, and a low-draw-call city — plus a walkable/drivable starter world to
prove it all works.

## What's implemented

| Area | Where | What it does |
|---|---|---|
| FPS modes 30/60/90/Auto | `scripts/settings.gd` | Sets `Engine.max_fps`. **Auto** reads `DisplayServer.screen_get_refresh_rate()` and targets the highest rate the display can actually show, capped at 90 — a 60 Hz phone is never told to chase 90. |
| Adaptive resolution | `scripts/settings.gd` (`_process`) | In Auto mode only: if the *measured* FPS stays below 80% of target, the 3D resolution scale steps down (floor 50% of the preset scale); it steps back up after ~6 s of holding the target. This is the "device capability" half of Auto. |
| Graphics presets | `scripts/settings.gd` (`PRESETS`) | Low / Balanced / High / Ultra applied **live, no restart**: viewport resolution scale (0.6 / 0.8 / 1.0 / 1.0), MSAA (off / off / 2x / 4x), directional shadow atlas (1024 / 2048 / 4096 / 4096), shadows on/off, city shadow-casting on/off, view distance (90 / 140 / 200 / 260 m), anisotropic filtering level. |
| Battery saver | `scripts/settings.gd` | One toggle: forces the Low preset + a 30 FPS cap. Turning it off restores your chosen preset/mode. |
| FPS / frame-time overlay | `scripts/settings_ui.gd` | Shows **measured** FPS, frame time, draw calls and object count (`Performance` monitors) — nothing is faked or estimated. Toggle it in Settings. |
| Settings UI | `scripts/settings_ui.gd` | Touch-sized controls (≥48 px): FPS mode, preset, battery saver, overlay toggle, view-distance slider. Choices persist to `user://my_gta_world_settings.cfg`. |
| Touch controls | `scripts/virtual_joystick.gd`, `scripts/player.gd` | Virtual joystick (bottom-left) for movement, touch-drag to orbit the camera. Keyboard/mouse (WASD, Space, Shift, E) for desktop testing. |
| City rendering | `scripts/main.gd` | 49 city blocks / 147 buildings as **MultiMesh** instances — one draw call per chunk×material (106 chunk meshes total) instead of hundreds. Chunks are distance-culled every 0.25 s against the view distance. Buildings use a 6-material palette with per-instance colour variation and rooftop detail boxes (see `GRAPHICS-UPGRADE-NOTES.md`). |
| Traffic | `scripts/traffic_car.gd` | 6 ambient cars on waypoint loops. **Kinematic, no physics bodies** — a fraction of the CPU cost. Cars also hide/pause beyond view distance. |
| Drivable car | `scripts/drivable_car.gd` | One arcade car (the only vehicle physics body): walk up, press E, drive, E to get out. Speed-scaled steering, all delta-based so it behaves the same at 30/60/90 FPS. |
| Physics | `project.godot` | Fixed **60 Hz** physics ticks on every device + physics interpolation, so gameplay feel is identical while rendering runs at 30/60/90. |

## How Jalal's requirements map

1. **FPS & smooth gameplay** — modes + Auto as above. Frame pacing is the
   engine's; physics is fixed-step so there are no per-frame physics spikes
   from the scaffold itself. *Not* claimed: any FPS number on any real phone —
   see "Honest limitations".
2. **Universal Android compatibility** — the project uses the **Mobile
   renderer** (Vulkan). For very old GPUs without Vulkan, the documented
   fallback is one line in `project.godot`:
   `renderer/rendering_method.mobile="gl_compatibility"` (Compatibility /
   OpenGL ES 3.0); the Low preset is tuned for it. Display: base resolution
   1152×648 with stretch mode `canvas_items` + aspect `expand`, so 16:9,
   19.5:9, 20:9 and tablet ratios all fill the screen by expanding the view.
   Input/audio/storage all use Godot's cross-platform APIs.
3. **Graphics presets** — table above; changes apply live because they only
   touch runtime-safe knobs (viewport scale/MSAA, shadow atlas, light
   toggles, culling distance). Texture *compression* is an import-time
   choice (ETC2/ASTC enabled in `project.godot`) and the anisotropic level is
   stored immediately but fully applies to textures loaded afterwards.
4. **Performance optimization** — MultiMesh batching (draw calls), chunk
   distance culling (a form of distance-based rendering), kinematic traffic
   (cheap AI), one shared unit-box mesh + 8 shared materials, no reflection
   probes, no real-time reflections, shadow atlas sized per preset.
5. **Display & thermal** — refresh-rate detection drives Auto mode; vsync is
   left to the OS/display (the engine cap sits under it); Battery Saver +
   adaptive resolution reduce load (and therefore heat) automatically.
   Godot exposes **no phone-temperature API** to GDScript, so the game
   respects OS thermal throttling instead of pretending to read a sensor.
6. **Testing & honest reporting** — see `TEST-REPORT.md`. Everything was
   verified headless on this Linux VM (import, scene run, and a 24-check
   automated smoke test). **No FPS figure for any real device is claimed
   anywhere** — that requires running the APK on the phone.

## Android export

Engine/toolchain actually installed on this machine (verified, see
`TEST-REPORT.md`): Godot 4.7.2.stable + official export templates,
OpenJDK 17, Android SDK cmdline-tools; SDK components (platform-tools,
platform android-36, build-tools 36.1.0, CMake 3.22.1, NDK 29.0.14206865)
laid out under `~/workspace/tools/android-sdk/`.

Real version numbers taken from the installed 4.7.2 template's
`config.gradle` (not from memory):

* **Minimum Android: API 24 (Android 7.0)** — `minSdk = 24`. Devices older
  than Android 7.0 are **not** supported by Godot 4.7 exports.
* Target/compile SDK: **API 36** (Android 16), build-tools **36.1.0**,
  Android Gradle Plugin 8.6.1, Java 17, NDK **29.0.14206865**.

Export steps (when ready to produce an APK):

1. Editor Settings → Export → Android paths are **already configured on
   this machine** (`~/.config/godot/editor_settings-4.7.tres`): Java SDK
   `/usr/lib/jvm/java-17-openjdk-amd64`, Android SDK
   `~/workspace/tools/android-sdk`, plus the debug keystore.
2. Generate a debug keystore once (Project → Tools → no; use `keytool` from
   the JDK) or let Godot use its default debug signing for test builds.
3. `export_presets.cfg` already contains an **Android** preset
   (package `com.jalal.mygtaworld`, arm64-v8a only, Gradle build on).
4. Project → Export → Android → Export Project. First Gradle build downloads
   Gradle + dependencies (needs network once; the game itself stays
   offline).

## NOT yet done (honest list)

* No APK has been built yet. The toolchain is complete (Godot, templates,
  JDK 17, full Android SDK, debug keystore, editor settings), but the
  Gradle build itself was not run: this VM had ~0.7 GiB free RAM (Gradle
  needs several GiB), and Gradle's first-run downloads go through Java's
  HTTP stack, which cannot use this VM's authenticated proxy. Exact
  details in `TEST-REPORT.md`. An export *pack* (PCK) was built
  successfully as a wiring check.
* **No real-device testing** (no phone is attached to this VM): no verified
  90 FPS, no per-device recommended settings yet. The first device pass
  should be: a 90 Hz+ phone (target Ultra/High + Auto), a mid-range 60 Hz
  phone (Balanced + Auto), and a low-end phone (Low + 30/60, Compatibility
  renderer build) — then fill in a per-device table from the FPS overlay.
* Occlusion culling (`OccluderInstance3D`) not added yet — chunk distance
  culling covers the open streets of this scaffold; add occluders when
  interiors/tall dense blocks arrive.
* True mesh LODs not needed yet (buildings are boxes). The chunk structure
  in `main.gd` is where a low-detail MultiMesh swap belongs later.
* Buildings have no collision (you can walk through them); only the ground,
  the player and the car collide. Traffic has no collision or avoidance.
* No missions, pedestrians, weapons, minimap, sound, or saving of game
  progress — this milestone is the performance foundation + starter world.

## Project layout

```
project.godot            engine config (Mobile renderer, 60 Hz physics)
export_presets.cfg       Android export preset
scenes/main.tscn         world root: sun, ground, player, UI (city built in code)
scripts/settings.gd      "Settings" autoload — FPS modes, presets, battery saver
scripts/settings_ui.gd   settings panel + FPS overlay + joystick host
scripts/main.gd          city (MultiMesh chunks), traffic, hero car, culling
scripts/player.gd        walker + orbit camera + car enter/exit
scripts/drivable_car.gd  arcade car (single physics vehicle)
scripts/traffic_car.gd   kinematic ambient traffic
scripts/virtual_joystick.gd  touch joystick
tests/smoke_test.gd      24-check automated test (see TEST-REPORT.md)
```
