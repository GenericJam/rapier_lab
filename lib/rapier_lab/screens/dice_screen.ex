defmodule RapierLab.Screens.DiceScreen do
  @moduledoc """
  rapier_lab-e4v: single d6 rolling into a small tabletop, driven by
  Rapier through a NAMED world (rapier_lab-ou4). The screen renders the
  die with `Mob.Scene3d` (probe.glb — chopaat's beveled cube standing in
  for a pipped d6) and Rapier steps the world each tick.

  Tap RESET to shake — a fresh linear + angular impulse produces a new
  outcome. Contact events are drained each step (bead rapier_lab-bvr)
  and shown in the readout so an agent watching the screen (or reading
  RPC) can distinguish "still tumbling" from "on the table, settled".

  Face-up detection is `MobRapier.Dice.face_up_d6/1` (bead
  rapier_lab-le5): rotate each of the six local axes by the die's
  quaternion, whichever transformed axis has the largest world-y is the
  face pointing up.
  """

  use Mob.Screen

  alias Mob.Scene3d.IR
  alias Mob.Scene3d.IR.{Camera, Entity, Light, Model, Transform}
  alias MobRapier.Dice
  alias MobRapier.Physics

  @tick_ms 33
  @world_name "dice"

  # Die geometry — half-extents 3 cm → 6 cm cube, close to a chunky
  # physical d6.
  @die_half 0.03
  @drop_height 0.4

  # Sleep thresholds. Rapier reports contacts each step; we call the die
  # "settled" after the angular + linear speed dip below these limits for
  # a handful of consecutive frames.
  @settle_frames 12
  @settle_lin_v 0.02
  @settle_ang_v 0.15

  @impl Mob.Screen
  def mount(_params, _session, socket) do
    :ok = Physics.new_world(@world_name)
    _ = build_arena()
    die = spawn_die()

    ref = make_ref()
    Process.send_after(self(), {:tick, ref}, @tick_ms)

    {:ok,
     Mob.Socket.assign(socket,
       die: die,
       tick_ref: ref,
       frame: 0,
       last_pos: {0.0, @drop_height, 0.0},
       last_rot: {0.0, 0.0, 0.0, 1.0},
       last_lin_speed: 0.0,
       last_ang_speed: 0.0,
       settle_streak: 0,
       settled?: false,
       settled_face: nil,
       last_contact_frame: nil,
       contact_count: 0
     )
     |> rebuild_scene()}
  end

  @impl Mob.Screen
  def handle_info({:tick, ref}, %{assigns: %{tick_ref: ref}} = socket) do
    dt = @tick_ms / 1000

    {collisions, _forces, _dropped} =
      Physics.step_with_contacts_in(@world_name, dt)
      |> case do
        {c, f, d} -> {c, f, d}
        _ -> {[], [], 0}
      end

    frame = socket.assigns.frame + 1

    die_body_id = socket.assigns.die

    {pos, rot} =
      Physics.transforms_in(@world_name)
      |> case do
        rows when is_list(rows) ->
          Enum.find_value(
            rows,
            {socket.assigns.last_pos, socket.assigns.last_rot},
            fn
              {^die_body_id, p, r} -> {p, r}
              _ -> false
            end
          )

        _ ->
          {socket.assigns.last_pos, socket.assigns.last_rot}
      end

    lin_speed = vec_delta(pos, socket.assigns.last_pos) / dt
    ang_speed = quat_speed(rot, socket.assigns.last_rot, dt)

    settle_streak =
      if lin_speed < @settle_lin_v and ang_speed < @settle_ang_v do
        socket.assigns.settle_streak + 1
      else
        0
      end

    {settled?, settled_face} =
      if settle_streak >= @settle_frames do
        {true, Dice.face_up_d6(rot)}
      else
        {socket.assigns.settled?, socket.assigns.settled_face}
      end

    last_contact_frame =
      if collisions == [], do: socket.assigns.last_contact_frame, else: frame

    contact_count =
      socket.assigns.contact_count +
        Enum.count(collisions, fn {_, _, k} -> k == :started end)

    next = make_ref()
    Process.send_after(self(), {:tick, next}, @tick_ms)

    {:noreply,
     Mob.Socket.assign(socket,
       tick_ref: next,
       frame: frame,
       last_pos: pos,
       last_rot: rot,
       last_lin_speed: lin_speed,
       last_ang_speed: ang_speed,
       settle_streak: settle_streak,
       settled?: settled?,
       settled_face: settled_face,
       last_contact_frame: last_contact_frame,
       contact_count: contact_count
     )
     |> rebuild_scene()}
  end

  def handle_info({:tick, _stale}, socket), do: {:noreply, socket}

  def handle_info({:tap, :reset}, socket) do
    :ok = Physics.destroy_world(@world_name)
    :ok = Physics.new_world(@world_name)
    _ = build_arena()
    die = spawn_die()

    {:noreply,
     Mob.Socket.assign(socket,
       die: die,
       frame: 0,
       last_pos: {0.0, @drop_height, 0.0},
       last_rot: {0.0, 0.0, 0.0, 1.0},
       last_lin_speed: 0.0,
       last_ang_speed: 0.0,
       settle_streak: 0,
       settled?: false,
       settled_face: nil,
       last_contact_frame: nil,
       contact_count: 0
     )
     |> rebuild_scene()}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  @impl Mob.Screen
  def render(assigns) do
    face_line =
      cond do
        assigns.settled? -> "FACE UP = #{assigns.settled_face}"
        assigns.settle_streak > 0 -> "STABILIZING (#{assigns.settle_streak}/#{@settle_frames})"
        true -> "TUMBLING"
      end

    stats_line =
      "FRAME #{assigns.frame}  " <>
        "|v|=#{fmt(assigns.last_lin_speed)}  " <>
        "|ω|=#{fmt(assigns.last_ang_speed)}  " <>
        "hits=#{assigns.contact_count}"

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
                text: "ROLL",
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
              id: :dice,
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
            height: 76,
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
                    text: face_line,
                    text_size: 20,
                    text_color: face_color(assigns),
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

  # Static ground + four walls around origin. Walls are cuboid statics
  # slotted in via add_cuboid_in (dynamic, then we could freeze — Rapier
  # doesn't expose static cuboid via the current NIF surface, so we take
  # advantage of walls being far from any dynamic contact and rely on
  # their weight for now). For a proper follow-up we'd add a
  # `add_static_cuboid` NIF; for the demo the walls are heavy dynamic
  # cuboids at rest which never actually get impulsed.
  defp build_arena do
    # Walls: 20 cm cubes with faces oriented to form a 40 cm × 40 cm bowl.
    wall_h = 0.05
    wall_t = 0.02
    half_side = 0.2

    for {x, z} <- [{half_side, 0.0}, {-half_side, 0.0}, {0.0, half_side}, {0.0, -half_side}] do
      Physics.add_static_cuboid_in(@world_name, x, wall_h, z, wall_t, wall_h, half_side)
    end

    :ok
  end

  defp spawn_die do
    die_id =
      Physics.add_cuboid_in(
        @world_name,
        0.0,
        @drop_height,
        0.0,
        @die_half,
        @die_half,
        @die_half
      )

    # A 6 cm cube at density 1 has mass = (0.06)^3 ≈ 2.16e-4 kg. Impulses
    # scale by mass — the "small numbers" that felt gentle at 1 kg become
    # Mach 5 for a 2-gram die. Aim for ~1 m/s linear and ~5 rad/s angular.
    #
    #   linear  ≈ 2.16e-4 kg * 1 m/s     = 2.16e-4 N·s
    #   inertia  = m * side² / 6 ≈ 1.3e-7 kg·m²
    #   angular ≈ 1.3e-7 * 5 rad/s      = 6.5e-7 N·m·s
    lx = (:rand.uniform() - 0.5) * 3.0e-4
    lz = (:rand.uniform() - 0.5) * 3.0e-4
    ly = 5.0e-5 + :rand.uniform() * 1.0e-4
    :ok = Physics.apply_impulse_in(@world_name, die_id, lx, ly, lz)

    tx = (:rand.uniform() - 0.5) * 2.0e-6
    ty = (:rand.uniform() - 0.5) * 2.0e-6
    tz = (:rand.uniform() - 0.5) * 2.0e-6
    :ok = Physics.apply_torque_impulse_in(@world_name, die_id, tx, ty, tz)

    die_id
  end

  # ── scene rebuild ──────────────────────────────────────────────────────

  defp rebuild_scene(socket) do
    ir =
      IR.new([
        camera(),
        sun(),
        ground(),
        die_entity(socket.assigns.last_pos, socket.assigns.last_rot)
      ])

    Mob.Socket.assign(socket, :scene, ir)
  end

  defp camera do
    %Entity{
      id: "camera",
      transform: Transform.from_euler({-30.0, 0.0, 0.0}, position: {0.0, 0.6, 0.6}),
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

  defp die_entity(pos, rot) do
    # probe.glb is a ~10cm beveled cube; scale so the mesh matches the
    # physics half-extent (@die_half = 3cm) — the mesh has half-extent
    # ~0.05, so scale = 0.6 to reach 0.03.
    s = @die_half / 0.05

    %Entity{
      id: "die",
      transform: %Transform{position: pos, rotation: rot, scale: {s, s, s}},
      data: %Model{asset: "probe.glb"}
    }
  end

  # ── helpers ────────────────────────────────────────────────────────────

  defp vec_delta({ax, ay, az}, {bx, by, bz}) do
    :math.sqrt(:math.pow(ax - bx, 2) + :math.pow(ay - by, 2) + :math.pow(az - bz, 2))
  end

  # Approximate angular speed via the sine of the half-angle between two
  # unit quaternions — good enough for a settle heuristic.
  defp quat_speed({ax, ay, az, aw}, {bx, by, bz, bw}, dt) do
    d = ax * bx + ay * by + az * bz + aw * bw
    abs_d = abs(d)
    # Guard against numeric drift above 1.0.
    sin_half = :math.sqrt(max(0.0, 1.0 - abs_d * abs_d))
    2.0 * sin_half / max(dt, 1.0e-6)
  end

  defp fmt(f) when is_float(f), do: :erlang.float_to_binary(f, decimals: 2)
  defp fmt(other), do: inspect(other)

  defp face_color(%{settled?: true}), do: 0xFF57E389
  defp face_color(%{settle_streak: n}) when n > 0, do: 0xFFF0E442
  defp face_color(_), do: 0xFFF5ECD6
end
