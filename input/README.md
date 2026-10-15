# Input and training integration

This module implements `docs/interface-contract.md` v1 for Godot **4.6.3**.
It does not create nodes, modify project settings, draw the stage, or reset combat.

```gdscript
var controls = preload("res://input/input_source.gd").new()
var practice = preload("res://training/training_controller.gd").new()

# Once per 60 Hz _physics_process, before combat advances:
var physical_inputs: Array[Dictionary] = controls.sample_frame()
var applied_inputs: Array[Dictionary] = practice.apply(physical_inputs, combat.snapshot())
var snapshot: Dictionary = combat.step(applied_inputs)
```

`sample_frame()` must run on the physics tick, not `_process()`. Godot's
`is_action_just_pressed/released` physics-tick state retains short taps. Events
injected with `Input.parse_input_event()` belong before the consuming tick;
injecting during that same `_physics_process` is not an OS-event timing model.
Held state is independently read from physical keys/buttons/axes. Keyboard
autorepeat does not create additional attacks. Left+right and up+down are neutral;
south/A remains an independent jump button. Opposing stick/D-pad horizontal inputs
also resolve to neutral. Stick dead zone is `0.35`.

| Action | P1 | P2 | Controller position / Xbox label |
| --- | --- | --- | --- |
| Left/right | A / D | Left / Right | Left stick / D-pad |
| Crouch | S | Down | Stick down / D-pad down |
| Jump | W | Up | South / A |
| Light/heavy/throw | J / K / L | Numpad 1 / 2 / 3 | West / X, North / Y, East / B |
| Guard | U | Numpad 0 | Left shoulder / LB |

`DeviceReader` registers namespaced InputMap actions at construction and when a
controller is first observed; repeated registration is idempotent. No InputMap
entries are required in `project.godot`. Controller IDs are sorted each sample:
the first two occupy P1 and P2. Keyboard controls remain available for both.
Disconnecting releases that device's held contribution; if the first controller
disconnects, the remaining controller becomes P1, as required by the first-two
assignment rule. `assigned_devices()` exposes these IDs for optional UI labels.
Already-held buttons on a newly assigned controller do not create phantom attack
edges. Keyboard and controller holds for the same action are combined: pressing a
second source while the first remains held does not attack again, and releasing
one source does not release the other source's action.

`history(player)` returns at most 120 normalized samples, oldest first, with a
zero-based `frame` field. Frame 0 drives the first combat step after reset.
`raw_history(player)` additionally exposes bit masks for held/pressed/released
and per-bit held durations in ticks. All returned arrays/dictionaries are copies.

`replay_frames()` retains only the first 600 input pairs since reset and stops
recording when full; it never discards the beginning of that clip. Each record is
`{"frame": int, "inputs": Array[Dictionary]}`. This is a small in-memory input
test tape, with no file format, playback UI, or arbitrary combat-state restore.
History and tape are captured **before** training overrides. Replaying an actual
training match also requires its training settings and changes; this tape alone
does not claim to reproduce training-mode toggles or resets.

`controls.reset()` clears edge tracking, history, tape and frame numbering while
preserving bindings. A physically held button is observed as a new hold after
reset. Call it together with `combat.reset()` and `practice.reset()` for a fresh
round. Reset, refill, pause, F1/F2/F3/F4 and R are owned by the integrator.

Training starts disabled, with idle selected. `set_enabled(true)` activates P2's
dummy. `cycle_dummy_mode()` returns `guard`, `jump`, `manual`, `idle` in that order
from the initial idle mode. Guard holds the explicit guard input. Jump emits a
press followed by a release, waits while airborne, and can retry on the ground
if the preceding request was blocked. `reset()` only clears transient automation;
it preserves enabled/mode settings. `apply()` deep-copies inputs, including in
manual/disabled mode. `debug_view(snapshot)` optionally returns isolated world
space `hitboxes`, `hurtboxes`, and `frame`; rendering remains with the integrator.

## Reproduce checks

From the repository root, using Godot 4.6.3 on PATH:

```sh
godot --headless --path . --script input/tests/run_tests.gd
godot --headless --path . --script input/tests/engine_input_tests.gd
godot --headless --max-fps 30 --path . --script input/tests/engine_input_tests.gd
godot --headless --max-fps 144 --path . --script input/tests/engine_input_tests.gd
```

The first script tests normalization, edges, held durations, bounded/copy-isolated
history and tape, deterministic sampled streams, controller slot changes, and all
dummy modes. The second uses real Godot InputMap/InputEvent calls across actual
physics ticks, with synthetic keyboard and controller events. It tests keyboard
and numpad bindings, short taps, sustained holds, SOCD, stick dead zone, disconnect
cleanup and OS echo. Tests use preloads and do not require an editor class cache.

On restricted Linux runners, set `XDG_DATA_HOME`, `XDG_CACHE_HOME`, and
`XDG_CONFIG_HOME` to writable temporary directories before starting Godot. This
avoids engine user-data/log failures; it does not require package installation.

**Validation boundary:** headless checks ran on Linux with Godot 4.6.3. Physical
controllers, Windows hardware/keyboard layouts, display/input latency, and the
integrated playable scene still require integrator/local validation. Synthetic
controller events are not a physical controller test.
