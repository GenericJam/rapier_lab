defmodule RapierLab.Screens.MultiDiceScreen do
  @moduledoc """
  rapier_lab-xs9: N × d6 rolling in a small arena, agent-verifiable end
  to end.

  Reuses the whole readback stack the single-die demo (rapier_lab-e4v)
  proved out — the point of this screen is to show the same instrumentation
  scales cleanly:

    * `MobRapier.Physics.transforms_in/1` returns every die each tick
    * `MobRapier.Physics.contacts_in/1` returns every collision event
    * `MobRapier.Dice.face_up_d6/1` decodes each settled quaternion
    * `Mob.Scene3d.Test.Physics.assert_scene_tracks_physics/3` (bead
      mob_scene3d-8oh) still returns `:ok` even with N entities

  Layout: `@die_count` dice dropped from a small height above a 60 cm
  arena walled on 4 sides (static cuboids). Each die gets a randomized
  linear + torque impulse so no two land the same way. When ALL are
  settled the readout switches from "TUMBLING" to "SETTLED" and shows
  the face for each die, followed by the sum and the count of 6s (the
  Risk-relevant stats).
  """

  use Mob.Screen

  alias Mob.Scene3d.IR
  alias Mob.Scene3d.IR.{Camera, Entity, Light, Model, Transform}
  alias MobRapier.Dice
  alias MobRapier.Physics
  alias RapierLab.Screens.PickerChips

  @tick_ms 33
  @world_name "risk_dice"
  @default_die_count 5

  @die_half 0.03
  @drop_height 0.5
  @arena_half 0.30

  @settle_frames 12
  @settle_lin_v 0.02
  @settle_ang_v 0.15

  @impl Mob.Screen
  def mount(params, _session, socket) do
    die_count = Map.get(params, :count, @default_die_count)

    active_chip =
      case die_count do
        1 -> :pick_1d6
        10 -> :pick_10d6
        _ -> nil
      end

    :ok = Physics.new_world(@world_name)
    _ = build_arena()
    die_ids = spawn_dice(die_count)

    ref = make_ref()
    Process.send_after(self(), {:tick, ref}, @tick_ms)

    {:ok,
     Mob.Socket.assign(socket,
       die_count: die_count,
       active_chip: active_chip,
       die_ids: die_ids,
       tick_ref: ref,
       frame: 0,
       dice: initial_dice(die_ids),
       settled_all?: false,
       contact_count: 0
     )
     |> rebuild_scene()}
  end

  @impl Mob.Screen
  def handle_info({:tick, ref}, %{assigns: %{tick_ref: ref}} = socket) do
    dt = @tick_ms / 1000

    {collisions, _forces, _dropped} =
      case Physics.step_with_contacts_in(@world_name, dt) do
        {c, f, d} -> {c, f, d}
        _ -> {[], [], 0}
      end

    transforms = Physics.transforms_in(@world_name) || []

    dice =
      socket.assigns.dice
      |> Map.new(fn {die_id, entry} ->
        {die_id, advance_die(die_id, entry, transforms, dt)}
      end)

    settled_all? = Enum.all?(dice, fn {_id, entry} -> entry.settled? end)

    contact_count =
      socket.assigns.contact_count +
        Enum.count(collisions, fn {_a, _b, kind} -> kind == :started end)

    next = make_ref()
    Process.send_after(self(), {:tick, next}, @tick_ms)

    {:noreply,
     Mob.Socket.assign(socket,
       tick_ref: next,
       frame: socket.assigns.frame + 1,
       dice: dice,
       settled_all?: settled_all?,
       contact_count: contact_count
     )
     |> rebuild_scene()}
  end

  def handle_info({:tick, _stale}, socket), do: {:noreply, socket}

  def handle_info({:tap, :reset}, socket) do
    :ok = Physics.destroy_world(@world_name)
    :ok = Physics.new_world(@world_name)
    _ = build_arena()
    die_ids = spawn_dice(socket.assigns.die_count)

    {:noreply,
     Mob.Socket.assign(socket,
       die_ids: die_ids,
       frame: 0,
       dice: initial_dice(die_ids),
       settled_all?: false,
       contact_count: 0
     )
     |> rebuild_scene()}
  end

  def handle_info({:tap, tag}, socket) do
    case PickerChips.handle_tap(socket, tag) do
      {:handled, socket} -> {:noreply, socket}
      :passthrough -> {:noreply, socket}
    end
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  @impl Mob.Screen
  def render(assigns) do
    faces =
      assigns.dice
      |> Enum.map(fn {_id, entry} -> entry.face end)

    header_line =
      cond do
        assigns.settled_all? ->
          "SETTLED — " <>
            (faces
             |> Enum.map(&(&1 || "?"))
             |> Enum.map(&to_string/1)
             |> Enum.join(" "))

        true ->
          "TUMBLING (#{Enum.count(assigns.dice, fn {_, e} -> e.settled? end)}/#{assigns.die_count})"
      end

    stats_line =
      cond do
        assigns.settled_all? ->
          sum = faces |> Enum.filter(&is_integer/1) |> Enum.sum()
          sixes = Enum.count(faces, &(&1 == 6))
          "SUM=#{sum}  SIXES=#{sixes}  FRAME #{assigns.frame}  hits=#{assigns.contact_count}"

        true ->
          "FRAME #{assigns.frame}  hits=#{assigns.contact_count}"
      end

    %{
      type: :column,
      props: %{
        id: :root,
        fill_width: true,
        fill_height: true,
        background: 0xFF1A1408,
        gap: 0
      },
      children: [
        PickerChips.chip_row(assigns.active_chip, self()),
        %{
          type: :box,
          props: %{
            id: :reset,
            fill_width: true,
            height: 60,
            align: :center,
            background: 0xFF9C3A2B,
            accessibility_role: "button",
            accessibility_label: "Roll",
            on_tap: {self(), :reset}
          },
          children: [
            %{
              type: :text,
              props: %{
                text: "ROLL #{assigns.die_count}",
                text_size: 18,
                text_color: 0xFFF5ECD6,
                font_weight: "bold",
                letter_spacing: 3.0
              },
              children: []
            }
          ]
        },
        %{
          type: :box,
          props: %{
            id: :viewport_wrap,
            fill_width: true,
            weight: 1,
            background: 0xFF102030,
            align: :center
          },
          children: [
            Mob.Scene3d.viewport(
              id: :risk_dice,
              ir: assigns.scene,
              width: 372,
              height: 500,
              background: 0xFF102030
            )
          ]
        },
        %{
          type: :box,
          props: %{
            fill_width: true,
            height: 84,
            background: 0xFF2A2318,
            align: :center,
            padding: 8
          },
          children: [
            %{
              type: :column,
              props: %{gap: 4, align: :center},
              children: [
                %{
                  type: :text,
                  props: %{
                    text: header_line,
                    text_size: 20,
                    text_color:
                      if(assigns.settled_all?, do: 0xFF57E389, else: 0xFFF5ECD6),
                    font_weight: "bold"
                  },
                  children: []
                },
                %{
                  type: :text,
                  props: %{
                    text: stats_line,
                    text_size: 11,
                    text_color: 0xFFF0E442
                  },
                  children: []
                }
              ]
            }
          ]
        }
      ]
    }
  end

  # ── world setup ─────────────────────────────────────────────────────────

  defp build_arena do
    wall_h = 0.05
    wall_t = 0.02
    half = @arena_half

    for {x, z} <- [{half, 0.0}, {-half, 0.0}, {0.0, half}, {0.0, -half}] do
      Physics.add_static_cuboid_in(@world_name, x, wall_h, z, wall_t, wall_h, half)
    end

    :ok
  end

  # Spread N dice in a small grid above the arena; each gets an
  # independent random impulse + torque. Returns [body_id] in spawn
  # order — that's what `handle_info` uses as the key for its
  # per-die entry map.
  defp spawn_dice(n) do
    for i <- 0..(n - 1) do
      spread = 0.08
      # Line them up along X, staggered in Z so they don't stack.
      x = (i - (n - 1) / 2) * spread
      z = if rem(i, 2) == 0, do: -0.02, else: 0.02
      y = @drop_height + i * 0.02

      die_id =
        Physics.add_cuboid_in(@world_name, x, y, z, @die_half, @die_half, @die_half)

      lx = (:rand.uniform() - 0.5) * 3.0e-4
      lz = (:rand.uniform() - 0.5) * 3.0e-4
      ly = 2.0e-5 + :rand.uniform() * 5.0e-5
      :ok = Physics.apply_impulse_in(@world_name, die_id, lx, ly, lz)

      tx = (:rand.uniform() - 0.5) * 2.0e-6
      ty = (:rand.uniform() - 0.5) * 2.0e-6
      tz = (:rand.uniform() - 0.5) * 2.0e-6
      :ok = Physics.apply_torque_impulse_in(@world_name, die_id, tx, ty, tz)

      die_id
    end
  end

  defp initial_dice(die_ids) do
    Map.new(die_ids, fn id ->
      {id,
       %{
         pos: {0.0, @drop_height, 0.0},
         rot: {0.0, 0.0, 0.0, 1.0},
         settle_streak: 0,
         settled?: false,
         face: nil
       }}
    end)
  end

  defp advance_die(die_id, entry, transforms, dt) do
    case Enum.find(transforms, fn {id, _, _} -> id == die_id end) do
      nil ->
        entry

      {_id, pos, rot} ->
        lin_speed = vec_dist(pos, entry.pos) / dt
        ang_speed = quat_speed(rot, entry.rot, dt)

        streak =
          if lin_speed < @settle_lin_v and ang_speed < @settle_ang_v do
            entry.settle_streak + 1
          else
            0
          end

        {settled?, face} =
          if streak >= @settle_frames do
            {true, Dice.face_up_d6(rot)}
          else
            {entry.settled?, entry.face}
          end

        %{entry | pos: pos, rot: rot, settle_streak: streak, settled?: settled?, face: face}
    end
  end

  # ── scene rebuild ──────────────────────────────────────────────────────

  defp rebuild_scene(socket) do
    dice_entities =
      Enum.map(socket.assigns.dice, fn {die_id, entry} ->
        die_entity(die_id, entry)
      end)

    ir = IR.new([camera(), sun(), ground() | dice_entities])
    Mob.Socket.assign(socket, :scene, ir)
  end

  defp camera do
    # Pulled back + higher so all 5 dice fit in frame.
    %Entity{
      id: "camera",
      transform: Transform.from_euler({-40.0, 0.0, 0.0}, position: {0.0, 0.9, 0.55}),
      data: %Camera{fov_y: 55.0, near: 0.02, far: 20.0}
    }
  end

  defp sun do
    %Entity{
      id: "sun",
      transform: Transform.from_euler({-55.0, 25.0, 0.0}),
      data: %Light{type: :directional, intensity: 100_000.0}
    }
  end

  defp ground do
    %Entity{
      id: "ground",
      transform: %Transform{position: {0.0, 0.0, 0.0}},
      data: %Model{asset: "table.glb"}
    }
  end

  # d6 mesh from priv/assets/dice_gen/build_dice.py: unit-half-extent cube
  # with classical pip clusters on each face, arranged to match
  # MobRapier.Dice.face_up_d6 (+Y=1, -Y=6, +X=2, -X=5, +Z=3, -Z=4). Scale by
  # @die_half to match the physics cuboid extents.
  defp die_entity(die_id, entry) do
    s = @die_half

    %Entity{
      id: "die_#{die_id}",
      transform: %Transform{position: entry.pos, rotation: entry.rot, scale: {s, s, s}},
      data: %Model{asset: "d6.glb"}
    }
  end

  # ── helpers ────────────────────────────────────────────────────────────

  defp vec_dist({ax, ay, az}, {bx, by, bz}) do
    :math.sqrt(:math.pow(ax - bx, 2) + :math.pow(ay - by, 2) + :math.pow(az - bz, 2))
  end

  defp quat_speed({ax, ay, az, aw}, {bx, by, bz, bw}, dt) do
    d = ax * bx + ay * by + az * bz + aw * bw
    abs_d = abs(d)
    sin_half = :math.sqrt(max(0.0, 1.0 - abs_d * abs_d))
    2.0 * sin_half / max(dt, 1.0e-6)
  end
end
