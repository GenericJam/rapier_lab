defmodule RapierLab.Screens.ShellsScreen do
  @moduledoc """
  rapier_lab-yyv: the chopaat cup, ported to Rapier — 7 oblate cowries
  are dropped into a small arena, given randomized shake impulses, and
  their settled orientations decoded to `:up | :down` via
  `MobRapier.Dice.face_up_cowrie/1`. The tally of `:up` shells is the
  roll (0..7), same shape as chopaat's DIY sim (rapier_lab-dz0 will
  compare distributions).

  Reuses every readback the dice demos already have:
    * `MobRapier.Physics.transforms_in/1` per tick
    * `MobRapier.Physics.contacts_in/1` for shake instrumentation
    * `Mob.Scene3d.Test.Physics.assert_scene_tracks_physics/3` for
      agent-verifiable coherence between physics and viewport

  The oblate collider itself came from rapier_lab-gmx.
  """

  use Mob.Screen

  alias Mob.Scene3d.IR
  alias Mob.Scene3d.IR.{Camera, Entity, Light, Model, Transform}
  alias MobRapier.Dice
  alias MobRapier.Physics
  alias RapierLab.Screens.PickerChips

  @tick_ms 33
  @world_name "shells_cup"
  @shell_count 7

  # Cowrie proportions (metres): a squat ~2.5 : 1 oblate. Physics uses
  # (equatorial_r, polar_r) directly; the visual model is scaled
  # non-uniformly to match. Values chosen so 7 fit comfortably inside
  # the @arena_half box without pre-stacking too tightly.
  @equatorial_r 0.03
  @polar_r 0.012

  @drop_height 0.15
  @arena_half 0.20

  @settle_frames 12
  @settle_lin_v 0.02
  @settle_ang_v 0.15

  @impl Mob.Screen
  def mount(_params, _session, socket) do
    :ok = Physics.new_world(@world_name)
    _ = build_arena()
    shell_ids = spawn_shells(@shell_count)

    ref = make_ref()
    Process.send_after(self(), {:tick, ref}, @tick_ms)

    {:ok,
     Mob.Socket.assign(socket,
       shell_ids: shell_ids,
       tick_ref: ref,
       frame: 0,
       shells: initial_shells(shell_ids),
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

    shells =
      socket.assigns.shells
      |> Map.new(fn {shell_id, entry} ->
        {shell_id, advance_shell(shell_id, entry, transforms, dt)}
      end)

    settled_all? = Enum.all?(shells, fn {_id, entry} -> entry.settled? end)

    contact_count =
      socket.assigns.contact_count +
        Enum.count(collisions, fn {_a, _b, kind} -> kind == :started end)

    next = make_ref()
    Process.send_after(self(), {:tick, next}, @tick_ms)

    {:noreply,
     Mob.Socket.assign(socket,
       tick_ref: next,
       frame: socket.assigns.frame + 1,
       shells: shells,
       settled_all?: settled_all?,
       contact_count: contact_count
     )
     |> rebuild_scene()}
  end

  def handle_info({:tick, _stale}, socket), do: {:noreply, socket}

  def handle_info({:tap, :shake}, socket) do
    :ok = Physics.destroy_world(@world_name)
    :ok = Physics.new_world(@world_name)
    _ = build_arena()
    shell_ids = spawn_shells(@shell_count)

    {:noreply,
     Mob.Socket.assign(socket,
       shell_ids: shell_ids,
       frame: 0,
       shells: initial_shells(shell_ids),
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
    faces = for {_id, entry} <- assigns.shells, do: entry.face
    ups = Enum.count(faces, &(&1 == :up))

    header_line =
      cond do
        assigns.settled_all? ->
          "SETTLED — " <>
            (faces
             |> Enum.map(fn
               :up -> "▲"
               :down -> "▽"
               _ -> "?"
             end)
             |> Enum.join(" "))

        true ->
          "SHAKING (#{Enum.count(assigns.shells, fn {_, e} -> e.settled? end)}/#{@shell_count})"
      end

    stats_line =
      cond do
        assigns.settled_all? ->
          "UPS=#{ups}/#{@shell_count}  FRAME #{assigns.frame}  hits=#{assigns.contact_count}"

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
        PickerChips.chip_row(:pick_shells, self()),
        %{
          type: :box,
          props: %{
            id: :shake,
            fill_width: true,
            height: 60,
            align: :center,
            background: 0xFF9C3A2B,
            accessibility_role: "button",
            accessibility_label: "Shake",
            on_tap: {self(), :shake}
          },
          children: [
            %{
              type: :text,
              props: %{
                text: "SHAKE #{@shell_count}",
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
              id: :shells_cup,
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

  # Spread 7 shells across the arena in a rough 3-2-2 pattern with small
  # jitter so no two share exactly the same drop point. Each shell gets an
  # independent random impulse + torque so the settle is not
  # symmetry-degenerate.
  defp spawn_shells(n) do
    positions =
      [
        {-0.06, -0.06}, {0.0, -0.06}, {0.06, -0.06},
        {-0.04, 0.0}, {0.04, 0.0},
        {-0.02, 0.05}, {0.02, 0.05}
      ]
      |> Enum.take(n)

    for {{x, z}, i} <- Enum.with_index(positions) do
      jitter_x = (:rand.uniform() - 0.5) * 0.01
      jitter_z = (:rand.uniform() - 0.5) * 0.01
      y = @drop_height + i * 0.015

      shell_id =
        Physics.add_oblate_in(
          @world_name,
          x + jitter_x,
          y,
          z + jitter_z,
          @equatorial_r,
          @polar_r
        )

      # Small linear + a bigger torque — cowries need to tumble in the air
      # to actually pick between :up and :down when they land, not to fly
      # apart. Torque values sized so a settled shell has visibly rotated.
      lx = (:rand.uniform() - 0.5) * 3.0e-4
      lz = (:rand.uniform() - 0.5) * 3.0e-4
      ly = 2.0e-5 + :rand.uniform() * 5.0e-5
      :ok = Physics.apply_impulse_in(@world_name, shell_id, lx, ly, lz)

      tx = (:rand.uniform() - 0.5) * 4.0e-6
      ty = (:rand.uniform() - 0.5) * 4.0e-6
      tz = (:rand.uniform() - 0.5) * 4.0e-6
      :ok = Physics.apply_torque_impulse_in(@world_name, shell_id, tx, ty, tz)

      shell_id
    end
  end

  defp initial_shells(shell_ids) do
    Map.new(shell_ids, fn id ->
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

  defp advance_shell(shell_id, entry, transforms, dt) do
    case Enum.find(transforms, fn {id, _, _} -> id == shell_id end) do
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
            {true, Dice.face_up_cowrie(rot)}
          else
            {entry.settled?, entry.face}
          end

        %{entry | pos: pos, rot: rot, settle_streak: streak, settled?: settled?, face: face}
    end
  end

  # ── scene rebuild ──────────────────────────────────────────────────────

  defp rebuild_scene(socket) do
    shell_entities =
      Enum.map(socket.assigns.shells, fn {shell_id, entry} ->
        shell_entity(shell_id, entry)
      end)

    ir = IR.new([camera(), sun(), ground() | shell_entities])
    Mob.Socket.assign(socket, :scene, ir)
  end

  defp camera do
    # Same pull-back as MultiDiceScreen — the arena is a similar size and
    # the readback works at the same tilt.
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

  # Non-uniform scale on the die probe mesh — no cowrie art yet, so a
  # flattened probe reads as oblate on-screen while the physics uses the
  # real oblate collider from rapier_lab-gmx.
  defp shell_entity(shell_id, entry) do
    equatorial_s = @equatorial_r / 0.05
    polar_s = @polar_r / 0.05

    %Entity{
      id: "shell_#{shell_id}",
      transform: %Transform{
        position: entry.pos,
        rotation: entry.rot,
        scale: {equatorial_s, polar_s, equatorial_s}
      },
      data: %Model{asset: "probe.glb"}
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
