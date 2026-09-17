defmodule RapierLab.Screens.ConvexDiceScreen do
  @moduledoc """
  rapier_lab-qtk: three convex-hull dice — one d10 (pentagonal
  trapezohedron), one d12 (dodecahedron), one d20 (icosahedron) — dropped
  into the same arena and decoded independently. The shake shape mirrors
  MultiDiceScreen (rapier_lab-xs9); the difference is that these dice are
  built from the rapier_lab-ry2 vertex tables + face-normal tables in
  `MobRapier.Dice` instead of Rapier's built-in cuboid primitive.

  Face numerals aren't rendered on the mesh (out of scope per the bead) —
  the physics-decided face index shown in the readout is the demo.
  """

  use Mob.Screen

  alias Mob.Scene3d.IR
  alias Mob.Scene3d.IR.{Camera, Entity, Light, Model, Transform}
  alias MobRapier.Dice
  alias MobRapier.Physics
  alias RapierLab.Screens.PickerChips

  @tick_ms 33
  @world_name "convex_dice"

  # Table keyed by shape atom. Each row is {label, vertex-table getter,
  # face-up getter, spawn offset in xz, face-count for the readout}.
  @dice_by_shape %{
    d20: {"d20", :icosahedron_vertices, :face_up_d20, {-0.09, 0.0}, 20},
    d12: {"d12", :dodecahedron_vertices, :face_up_d12, {0.0, 0.0}, 12},
    d10: {"d10", :pentagonal_trapezohedron_vertices, :face_up_d10, {0.09, 0.0}, 10}
  }

  @default_shapes [:d20, :d12, :d10]

  # Bigger die + wider arena for single-shape mounts (D10 / D12 / D20
  # chips) — numerals need to be readable at demo distance and the die
  # needs room to settle flat, not balanced on a wall. The three-in-one
  # multi-shape mount stays smaller so the trio fits in a shared arena.
  @die_scale_single 0.09
  @die_scale_multi 0.03
  @arena_half_single 0.60
  @arena_half_multi 0.20
  # Lower drop for single-mode (dies are ~15 cm across so they don't need
  # a big drop, and a low drop keeps the settle in the camera frame).
  @drop_height_single 0.20
  @drop_height_multi 0.35

  @settle_frames 12
  @settle_lin_v 0.02
  @settle_ang_v 0.15

  @impl Mob.Screen
  def mount(params, _session, socket) do
    shapes = Map.get(params, :shapes, @default_shapes)
    active_chip = shapes_to_chip(shapes)
    die_scale = die_scale_for(shapes)
    arena_half = arena_half_for(shapes)

    :ok = Physics.new_world(@world_name)
    if length(shapes) > 1, do: build_arena(arena_half)
    dice = spawn_dice(shapes, die_scale)

    ref = make_ref()
    Process.send_after(self(), {:tick, ref}, @tick_ms)

    {:ok,
     Mob.Socket.assign(socket,
       shapes: shapes,
       active_chip: active_chip,
       die_scale: die_scale,
       arena_half: arena_half,
       dice: dice,
       tick_ref: ref,
       frame: 0,
       settled_all?: false,
       contact_count: 0
     )
     |> rebuild_scene()}
  end

  # Big scale for single-shape mounts (D10 / D12 / D20 chips); smaller
  # for the multi-shape default so the trio fits in the shared arena.
  defp die_scale_for([_only]), do: @die_scale_single
  defp die_scale_for(_multi), do: @die_scale_multi

  # A single-shape mount lights up that shape's chip; a multi-shape mount
  # (the default, [:d20, :d12, :d10]) doesn't correspond to any single
  # chip, so no chip is highlighted.
  defp shapes_to_chip([:d10]), do: :pick_d10
  defp shapes_to_chip([:d12]), do: :pick_d12
  defp shapes_to_chip([:d20]), do: :pick_d20
  defp shapes_to_chip(_multi), do: nil

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
      Enum.map(socket.assigns.dice, fn entry ->
        advance_die(entry, transforms, dt)
      end)

    settled_all? = Enum.all?(dice, & &1.settled?)

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
    if length(socket.assigns.shapes) > 1, do: build_arena(socket.assigns.arena_half)
    dice = spawn_dice(socket.assigns.shapes, socket.assigns.die_scale)

    {:noreply,
     Mob.Socket.assign(socket,
       dice: dice,
       frame: 0,
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
    faces_line =
      assigns.dice
      |> Enum.map(fn e -> "#{e.label}=#{e.face || "?"}" end)
      |> Enum.join("  ")

    total = length(assigns.dice)

    header_line =
      cond do
        assigns.settled_all? ->
          "SETTLED — #{faces_line}"

        true ->
          "TUMBLING (#{Enum.count(assigns.dice, & &1.settled?)}/#{total})"
      end

    stats_line = "FRAME #{assigns.frame}  hits=#{assigns.contact_count}"

    labels = Enum.map(assigns.dice, & &1.label)
    roll_label = "ROLL " <> Enum.join(labels, " · ")

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
                text: roll_label,
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
              id: :convex_dice,
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

  defp build_arena(half) do
    wall_h = 0.05
    wall_t = 0.02

    for {x, z} <- [{half, 0.0}, {-half, 0.0}, {0.0, half}, {0.0, -half}] do
      Physics.add_static_cuboid_in(@world_name, x, wall_h, z, wall_t, wall_h, half)
    end

    :ok
  end

  # Wide arena for single-die mounts so a 9cm die can settle flat instead
  # of balancing on a wall.
  defp arena_half_for([_only]), do: @arena_half_single
  defp arena_half_for(_multi), do: @arena_half_multi

  defp spawn_dice(shapes, die_scale) do
    drop_height = drop_height_for(shapes)
    solo? = length(shapes) == 1

    for shape <- shapes,
        {label, verts_fun, face_fun, {ox, oz}, face_count} = Map.fetch!(@dice_by_shape, shape) do
      # In solo mode, ignore the shape's arena offset — a single die
      # sits centred so the camera doesn't need to track it.
      {ox, oz} = if solo?, do: {0.0, 0.0}, else: {ox, oz}
      verts = apply(Dice, verts_fun, [])
      body = Physics.add_convex_hull_in(@world_name, ox, drop_height, oz, verts, die_scale)

      # Solo mode: no linear impulse (the die was rolling off screen),
      # just enough torque to break rotational symmetry so it lands on a
      # random face instead of the same one every roll. Trio mode keeps
      # the original bigger shake because 3 dice sharing an arena need to
      # tumble past each other.
      {lin_scale, torque_scale} = if solo?, do: {0.0, 0.3}, else: {1.0, 1.0}

      lx = (:rand.uniform() - 0.5) * 3.0e-4 * lin_scale
      lz = (:rand.uniform() - 0.5) * 3.0e-4 * lin_scale
      ly = (2.0e-5 + :rand.uniform() * 5.0e-5) * lin_scale
      :ok = Physics.apply_impulse_in(@world_name, body, lx, ly, lz)

      tx = (:rand.uniform() - 0.5) * 5.0e-6 * torque_scale
      ty = (:rand.uniform() - 0.5) * 5.0e-6 * torque_scale
      tz = (:rand.uniform() - 0.5) * 5.0e-6 * torque_scale
      :ok = Physics.apply_torque_impulse_in(@world_name, body, tx, ty, tz)

      %{
        label: label,
        body_id: body,
        face_fun: face_fun,
        face_count: face_count,
        pos: {ox, drop_height, oz},
        rot: {0.0, 0.0, 0.0, 1.0},
        settle_streak: 0,
        settled?: false,
        face: nil
      }
    end
  end

  defp drop_height_for([_only]), do: @drop_height_single
  defp drop_height_for(_multi), do: @drop_height_multi

  defp advance_die(entry, transforms, dt) do
    case Enum.find(transforms, fn {id, _, _} -> id == entry.body_id end) do
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
            {true, apply(Dice, entry.face_fun, [rot])}
          else
            {entry.settled?, entry.face}
          end

        %{entry | pos: pos, rot: rot, settle_streak: streak, settled?: settled?, face: face}
    end
  end

  # ── scene rebuild ──────────────────────────────────────────────────────

  defp rebuild_scene(socket) do
    die_scale = socket.assigns.die_scale
    die_entities = Enum.map(socket.assigns.dice, &die_entity(&1, die_scale))

    ir = IR.new([camera_for(socket.assigns.shapes), sun(), ground() | die_entities])
    Mob.Socket.assign(socket, :scene, ir)
  end

  # Single-die mounts (D10 / D12 / D20 chips) get a closer, higher-pitched
  # camera so numerals are big + the top face is nearly plan-view (easier
  # to read). Multi-shape default keeps the wider pulled-back angle so
  # three dice fit in the frame.
  defp camera_for([_only]) do
    %Entity{
      id: "camera",
      transform: Transform.from_euler({-45.0, 0.0, 0.0}, position: {0.0, 0.45, 0.32}),
      data: %Camera{fov_y: 55.0, near: 0.02, far: 20.0}
    }
  end

  defp camera_for(_multi) do
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

  # Per-shape .glb assets built by priv/assets/dice_gen/build_dice.py — the
  # mesh is unit-radius (Blender BODY_RADIUS = 1.0) so the visual scale
  # matches the physics collider scale exactly. Numeral positions match
  # MobRapier.Dice.face_up_dN so the readout label agrees with the top
  # face at rest.
  @asset_by_label %{"d20" => "d20.glb", "d12" => "d12.glb", "d10" => "d10.glb"}

  defp die_entity(entry, die_scale) do
    asset = Map.fetch!(@asset_by_label, entry.label)

    %Entity{
      id: "die_#{entry.label}",
      transform: %Transform{
        position: entry.pos,
        rotation: entry.rot,
        scale: {die_scale, die_scale, die_scale}
      },
      data: %Model{asset: asset}
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
