# Combat core

Original, adjustable prototype rules for Godot **4.6.3**. This module is pure
`RefCounted` state: it never reads `Input`, Nodes, render timing, or wall time.
It implements `docs/interface-contract.md` v1 without changing the shared API.

## Integration

```gdscript
var combat = preload("res://combat/combat_sim.gd").new()
var state: Dictionary = combat.step(frame_inputs) # exactly once per 60 Hz tick
combat.reset()                                    # fresh round
var copy: Dictionary = combat.snapshot()           # independent snapshot
```

`frame_inputs` is `Array[Dictionary]`, P1 then P2, with the contract's world-space
`move_x`, held `crouch`/`guard`, and rising-edge `jump`/`light`/`heavy`/`throw`.
Input normalization, physical button edges, pausing and practice resets belong
to the input/integration modules. The core neither changes caller inputs nor
exposes its mutable fighter objects.

Additional snapshot fields:

- Top level: `hitstop`, `pushboxes`, `throwboxes`.
- Per player: `velocity`, `crouching`, `move`, `phase`, `stun_remaining`,
  `attack_instance`, `throw_age`.
- `phase`: `startup`, `active`, `recovery`, or `none` for no current attack.
- Additional states: `low`, `air`, `landing`, `throwing`, `thrown`; the renderer
  may use its required fallback. A captured fighter stays in `thrown` during
  the tech window; `throw` events are emitted only when the result is known.
- Throw-result events contain `tech: bool`; successful tech has zero damage.
- Strike events include `move`, `attack_instance` and `combo`.

Events are emitted only on their resolution tick. Once KO is resolved, subsequent
steps preserve the frame, fighters and winner and return no repeated events.
The integrator's KO display delay must therefore use its own tick counter.

## Current rules and tuning

Each frame duration is a count of 60 Hz simulation ticks. All numbers below are
project-specific initial tuning, not parameters copied from a commercial game.
Tune attacks in `move_data.gd`; movement and input windows are constants in
`combat_sim.gd`. Frame zero is the first startup tick. For example, light is in
startup at frames 0..4, active at 5..6, recovery at 7..16.

| Move | Startup / active / recovery | Damage | Hitstun / blockstun | Hitstop |
| --- | --- | --- | --- | --- |
| light | 5 / 2 / 10 | 80 | 16 / 10 | 4 |
| heavy | 9 / 3 / 20 | 160 | 24 / 12 | 7 |
| low | 7 / 3 / 15 | 100 | 19 / 11 | 5 |
| air | 6 / 5 / 12 | 120 | 20 / 12 | 5 |
| throw | 5 / 2 / 24 | 150 | capture and tech window | 5 on damage |

- Standing light/heavy select those normals; either attack while crouching
  selects low, either while airborne selects air. Simultaneous attack edges
  prioritize throw, then heavy, then light. Jump is processed first when legal.
- Walk speed is 300 px/s. Jump sets y velocity to -780 px/s, gravity is
  2100 px/s² and horizontal jump speed is 260 px/s. Air momentum is committed
  at takeoff. Aerial attacks that reach the floor are removed and receive a
  four-tick landing recovery. Ground normals stop movement.
- Explicit guard holds position. Holding away from the opponent also guards
  while walking backward. Mids permit either stance, lows require crouch and
  aerial overheads require standing. No airborne guard or normal chip damage.
- Push, hurt, strike and throw boxes have separate roles. Push bodies prevent
  ground crossing but permit jumping over the opponent. Boxes are computed
  after both fighters move. Facing changes when free to turn; attack facing is
  committed. Mirroring transforms the entire box, including its width.
- Strikes collect from one shared world state, so same-tick hits trade. A strike
  connecting on a throw's active tick interrupts capture. Each attack instance
  records struck targets and may damage each target only once.
- Hitstop freezes movement, move frames, stun and command age for both fighters.
  The global frame still advances and edge input is received. Hitstun,
  blockstun, move recovery and hitstop are independent.
- Commands have five non-hitstop opportunities: age 0..4 is legal, age 5 is
  discarded before actions. Commands are consumed once; the queue is bounded.
  The only cancel is confirmed light hit into heavy in the next six non-hitstop
  ticks. Blocks and whiffs do not enable it. The defender remains in hitstun
  through the resulting close-range two-hit chain.
- Throw requires a grounded target outside stun and throw protection. Capture
  tick 0 and ticks 1..7 permit tech; tick 8 deals damage. Simultaneous active
  throws tech. Results separate fighters by at least 100 pixels, including at
  walls, and grant ten non-hitstop ticks of throw protection. No knockdown or
  wake-up mixup system is included in this first slice.
- Health starts at 1000; simultaneous zero health is a draw (`winner == -1`).
  There is no round timer. `reset()` clears all counters, commands and effects.

## Reproducible validation

From the repository root, with Godot 4.6.3 on PATH:

```sh
godot --headless --path . --script res://combat/combat_sim.gd --check-only
godot --headless --path . --script res://combat/tests/run.gd
```

The tests follow the contract's combat-owned `combat/tests/` location. They use
the public interface and actual input sequences, without editing internal state.
Coverage includes movement/corners/crossups, guard levels, attack windows and
deduplication, hitstop, buffer/cancel boundaries, throws and tech boundaries,
punishment, trades/double KO, rematch, snapshot isolation and a seeded 1800-tick
replay. They validate combat logic, not graphics, physical input latency,
Windows export or cross-platform floating-point determinism.

On sandboxed Linux hosts where user directories are read-only, use writable
temporary locations for `XDG_CACHE_HOME`, `XDG_DATA_HOME`, `XDG_CONFIG_HOME`.
This does not require any project configuration or software installation.
