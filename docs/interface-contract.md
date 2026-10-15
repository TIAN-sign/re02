# Shared interface v1 — first playable slice

This contract is frozen for concurrent implementation. Changes go through the integrator before either module changes its public API. Godot **4.6.3**, GDScript, Windows, fixed **60 Hz**. No networking or final art in this slice.

## Ownership and files

| Owner | Exclusive paths / entry point |
| --- | --- |
| Combat author | `combat/`, entry `combat/combat_sim.gd`, own tests under `combat/tests/` |
| Input/training author | `input/`, `training/`, entries `input/input_source.gd`, `training/training_controller.gd`, own tests inside these directories |
| Integrator | `shared/`, `project.godot`, `scenes/`, `presentation/`, `tests/`, docs, CI and root configuration |

All three entry scripts extend **RefCounted**, not Node. Instantiate with `load(path).new()`. Combat must never read `Input`, wall-clock time, scene Nodes or rendering state. Inputs and snapshots use Dictionaries, not custom resources. Preload `res://shared/fighter_contract.gd` as needed; do not require editor-generated class caches.

## Frame input

One `Array[Dictionary]` of exactly two items, indexed **0 = P1**, **1 = P2**. Each dictionary contains:

```gdscript
{"move_x": 0, "crouch": false, "guard": false,
 "jump": false, "light": false, "heavy": false, "throw": false}
```

`move_x` is -1, 0 or 1 in world coordinates; crouch and guard are held. Jump/light/heavy/throw are rising edges, true on one simulation tick per press. The input module detects edges independently of rendered frames. Combat may buffer these edge commands internally. Sampling and stepping happen exactly once in `_physics_process`, with physics ticks set to 60. `shared/fighter_contract.gd` supplies constants and fresh neutral inputs.

## Combat entry point

```gdscript
func reset() -> void
func step(inputs: Array[Dictionary]) -> Dictionary
func snapshot() -> Dictionary
```

Construction or `reset()` creates a ready match. `step` advances one simulation tick and returns the new snapshot. `snapshot` is read-only access via a deep copy; callers must not mutate combat state. `reset` resets all state, pending commands, effects and counters. Once a round is over, further steps preserve the outcome until reset. Deterministic identical input streams must yield identical snapshots.

Required snapshot keys:

```gdscript
{
 "frame": 0, "round_over": false, "winner": -1,
 "players": [
   {"id": 0, "pos": Vector2(400, 600), "hp": 1000, "max_hp": 1000,
    "facing": 1, "state": "idle", "state_frame": 0,
    "grounded": true, "combo": 0},
   # same schema for P2; initial facing -1
 ],
 "events": [], "hitboxes": [], "hurtboxes": []
}
```

Position is the fighter's feet in a **1280×720** world, x right/y down. Floor y=600; center limits x=80..1200. Standing visual body is approximately 64×140 px; combat author owns exact collision dimensions. Winner is -1 for none/draw, otherwise 0 or 1. States use `idle`, `walk`, `jump`, `crouch`, `light`, `heavy`, `throw`, `guard`, `hitstun`, `blockstun`, `knockdown`, `ko` as applicable. Additional keys/states are allowed; rendering must have a fallback.

Each active box: `{"owner": 0, "rect": Rect2(...)}` in world coordinates. Each event: `{"type": "hit", "actor": 0, "target": 1, "damage": 80}`. Supported event types are `hit`, `block`, `throw`, `ko`; extra event fields are allowed. Events contain only the most recent tick; boxes represent current active geometry. Combo is consecutive hits dealt by that player, reset when its combo opportunity expires. The combat author owns frame data, short light-to-heavy chains, defense and throws, including throw range and airborne validity.

## Input entry point

```gdscript
func sample_frame() -> Array[Dictionary]
func history(player: int) -> Array[Dictionary]
func reset() -> void
```

`history` returns at most 120 oldest-to-newest normalized frame inputs. It may add a `frame` key to each entry. `reset` clears history/edge tracking without changing input bindings. Gameplay bindings are configured inside this module, or read directly by key/button; do not edit `project.godot`. Neutralize opposing keyboard directions. The first two connected controllers map to P1/P2, refreshed safely on connect/disconnect. Keyboard and that player's controller both remain usable. A disconnected controller must not leave a held action latched.

| Action | P1 keyboard | P2 keyboard | Controller |
| --- | --- | --- | --- |
| Move/crouch/jump | A/D, S, W | Left/Right, Down, Up | left stick or D-pad, down crouch; south/A jump |
| Light/heavy/throw | J/K/L | numpad 1/2/3 | west/X, north/Y, east/B |
| Guard | U | numpad 0 | left shoulder/LB |

Use a stick dead zone, and label physical gamepad buttons by position as well as Xbox names. No implicit OS or background input services.

## Training entry point

```gdscript
func set_enabled(enabled: bool) -> void
func apply(inputs: Array[Dictionary], snapshot: Dictionary) -> Array[Dictionary]
func cycle_dummy_mode() -> String
func label() -> String
func reset() -> void
```

Disabled: `apply` preserves both players' inputs. Enabled: supports dummy modes `manual`, `idle`, `guard`, `jump` (initial `idle`), replacing P2 input as appropriate. Guard mode may move away from P1 if back-guard is implemented; explicit guard remains available. Jump uses valid rising edges. It must not mutate caller inputs or combat snapshots. `label` returns a displayable mode label; reset clears transient automation state. Practice round reset/refill is owned by the integrator: a KO resets both combat/input after a short displayed delay; R resets immediately.

## Integrator controls and rendering

F1 toggles local versus/training, F2 toggles boxes, F3 toggles input history, F4 cycles the training dummy, R resets, Escape pauses. The integrator consumes the snapshot and its events; no rendering logic is placed in combat. Input history and boxes can be shown in either mode. Tests must use the public contract; each author supplies meaningful headless tests for their own module and reports the exact commit.

Branches start from this contract commit. Authors push their own branch/commit; only the integrator merges into `feat/playable-slice`. Preserve `diyide` byte-for-byte. Do not send source ZIPs or write another author's paths.
