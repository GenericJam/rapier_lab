# rapier_lab

A [Mob][mob] demo app that shakes cowrie shells and dice in a 3D arena
on your phone. Physics by [Rapier 3D][rapier] via
[`mob_rapier`][mob_rapier]; rendering by [Filament][filament] via
[`mob_scene3d`][mob_scene3d]. Both platforms — iOS (Metal) and Android
(GLES/Vulkan) — from one description.

[mob]: https://mobframework.com
[rapier]: https://github.com/dimforge/rapier
[mob_rapier]: https://github.com/GenericJam/mob_rapier
[filament]: https://github.com/google/filament
[mob_scene3d]: https://github.com/GenericJam/mob_scene3d

Built as the spike that produced the two libraries above: the physics
API and the scene IR started here, stabilised across the five demos
below, and shipped as separate Hex packages. `rapier_lab` is what's
left after that extraction — the demo screens themselves — and it
doubles as the reference consumer showing how to wire a Rapier-backed
3D scene into a Mob app.

## What's in the app

Five picker tabs across the top of the screen; each is one screen:

| Tab      | Screen                           | What it shows                                                                       |
| -------- | -------------------------------- | ----------------------------------------------------------------------------------- |
| SHELLS   | `RapierLab.Screens.ShellsScreen` | 7 cowrie shells dropped into a wooden arena. Up / down decoded via `MobRapier.Dice.face_up_cowrie/1`. This is the on-device version of the crosscourt / chopaat divination that motivated the whole spike. |
| 1D6      | `MultiDiceScreen` (count: 1)     | One d6 rolling. Face-up read via `MobRapier.Dice.face_up_d6/1`.                     |
| 10D6     | `MultiDiceScreen` (count: 10)    | Ten d6s at once — the "N × d6" stress test for the readback pipeline.               |
| D12      | `ConvexDiceScreen` ([:d12])      | Regular dodecahedron, numerals baked into a glTF asset. Face-up via `face_up_d12/1`.|
| D20      | `ConvexDiceScreen` ([:d20])      | Regular icosahedron, same story.                                                    |

The tab row is a shared `PickerChips` component. The SHAKE button
resets the world and re-drops the bodies with randomised impulses so no
two shakes settle identically.

## What ships that isn't the demos themselves

The demo screens are thin — the interesting Elixir + Rust lives in
`mob_rapier` and `mob_scene3d`. `rapier_lab` keeps:

- `priv/assets/*.glb` — cowrie shell variants (`cowrie_a1..a7.glb`, from
  chopaat), a table, the d6 / d12 / d20 meshes with baked numerals.
- `priv/assets/dice_gen/build_dice.py` — the Blender headless script
  that builds the numeraled dice meshes from vertex + face-normal
  tables emitted by `MobRapier.Dice`. Regenerate with
  `python priv/assets/dice_gen/build_dice.py` inside Blender's Python.
- `lib/rapier_lab/screens/picker_chips.ex` — the shared top-of-screen
  tab row with `weight: 1` flex-tabs (the mob Android renderer doesn't
  honour `justify: :space_between`).

## Running it

Requires a working [mob][mob] setup (Elixir 1.20+, Xcode / Android
Studio, a booted iOS simulator or connected Android device). See
[`mob/AGENTS.md`][mob-agents] for first-time setup.

[mob-agents]: https://github.com/GenericJam/mob/blob/master/AGENTS.md

```bash
mix mob.deploy --native
mix mob.connect                # tunnel + IEx into the running app
```

On device, the SHELLS tab opens on launch. Tap SHAKE to drop the
shells; watch the readout at the bottom flip from `SHAKING (n/7)` to
`SETTLED — △ ▲ ▲ ▲ △ ▲ ▲` when Rapier's own `is_sleeping()` flag
goes true for every body.

Every screen ticks the world at ~30 Hz via
`MobRapier.Physics.step_with_contacts_in/2`, reads transforms per body
via `transforms_in/1`, decodes face-up when settled via the matching
`MobRapier.Dice` function, and rebuilds a `Mob.Scene3d.viewport` IR
each tick.

## Watching the physics from IEx

The debugging tooling that produced the current tuning is on
`mob_rapier`, and works fine from a `mix mob.connect` IEx session:

```elixir
# Snapshot: BodyState per body — pos, quat, linvel, angvel, speed,
# ang_speed, euler, up_axis, is_sleeping.
MobRapier.Physics.body_states_in("shells_cup")

# Stream: a light GenServer pushes {:mob_rapier_telemetry, world_name,
# %{frame, states}} every interval_ms to the caller.
{:ok, _} = MobRapier.Physics.Telemetry.stream("shells_cup",
  interval_ms: 100)

receive do
  {:mob_rapier_telemetry, "shells_cup", %{states: states}} ->
    Enum.count(states, & &1.sleeping)
after
  200 -> :timeout
end
```

See [`mob_rapier`'s physics_tuning guide][physics-tuning] for a full
diagnostic-session recipe.

[physics-tuning]: https://github.com/GenericJam/mob_rapier/blob/master/guides/physics_tuning.md

## Layout

```
lib/rapier_lab/
  application.ex            — mob boot + Rustler NIF init
  screens/
    main_screen.ex          — the launch screen (used to be the demo)
    shells_screen.ex        — SHELLS
    multi_dice_screen.ex    — 1D6 / 10D6
    convex_dice_screen.ex   — D12 / D20
    picker_chips.ex         — shared tab row

priv/assets/                — .glb models + dice-generation script
priv/generated/             — mob_plugins.exs (regenerated on deploy)

native/lab_physics          — symlink into deps/mob_rapier/native/lab_physics
                              until MobDev.NativeBuild.classify_project_nif/2
                              gains a :source option and can find plugin
                              crates through deps/ directly (MOB-254).
```

## Related repos

- [`mob_rapier`][mob_rapier] — the `MobRapier.Physics` Rustler NIF +
  named-world registry + `MobRapier.Dice` face-up decode. Extracted
  from this repo at bead `rapier_lab-d00`.
- [`mob_scene3d`][mob_scene3d] — the declarative Filament-backed scene
  IR. This is the plugin `rapier_lab` renders through.
- [`chopaat`][chopaat] — the cowrie-shell divination board game that
  motivated the SHELLS screen; ships the cowrie assets this repo
  reuses.
- [`mob`][mob] — the underlying BEAM-on-device app framework.

[chopaat]: https://github.com/GenericJam/chopaat

## License

MIT.
