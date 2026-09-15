defmodule RapierLab.Screens.MainScreen do
  @moduledoc """
  rapier_lab-0hf: a `Mob.Scene3d` viewport showing a single ball
  dropping onto a plane, driven by Rapier through
  `RapierLab.Physics`. Each screen tick steps the world 33 ms forward
  and rebuilds the scene from the physics transforms.

  Placeholder mesh: chopaat's probe.glb (a 10 cm beveled cube) stands
  in for the ball until we bake a real sphere. Chopaat's table.glb is
  the ground. Physics collider is still a unit ball on a wide plane;
  the mesh scale is cosmetic.
  """

  use Mob.Screen

  alias Mob.Scene3d.IR
  alias Mob.Scene3d.IR.{Camera, Entity, Light, Model, Transform}
  alias RapierLab.Physics

  @tick_ms 33

  # Physics ball radius (m) — big enough that the placeholder mesh
  # reads at a glance in the viewport.
  @ball_radius 0.3
  # Height the ball is dropped from each new world.
  @drop_height 2.0

  @impl Mob.Screen
  def mount(_params, _session, socket) do
    world = Physics.world_new()
    ball = Physics.add_ball(world, 0.0, @drop_height, 0.0, @ball_radius)

    ref = make_ref()
    Process.send_after(self(), {:tick, ref}, @tick_ms)

    socket =
      Mob.Socket.assign(socket,
        world: world,
        ball: ball,
        tick_ref: ref,
        frame: 0
      )
      |> rebuild_scene()

    {:ok, socket}
  end

  @impl Mob.Screen
  def handle_info({:tick, ref}, %{assigns: %{tick_ref: ref}} = socket) do
    Physics.step(socket.assigns.world, @tick_ms / 1000)
    next = make_ref()
    Process.send_after(self(), {:tick, next}, @tick_ms)

    socket =
      socket
      |> Mob.Socket.assign(tick_ref: next, frame: socket.assigns.frame + 1)
      |> rebuild_scene()

    {:noreply, socket}
  end

  def handle_info({:tick, _stale}, socket), do: {:noreply, socket}

  def handle_info({:tap, :reset}, socket) do
    world = Physics.world_new()
    ball = Physics.add_ball(world, 0.0, @drop_height, 0.0, @ball_radius)
    {:noreply, socket |> Mob.Socket.assign(world: world, ball: ball, frame: 0) |> rebuild_scene()}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  @impl Mob.Screen
  def render(assigns) do
    ball_y =
      case Physics.transforms(assigns.world) do
        [{_id, {_x, y, _z}, _rot} | _] -> y
        _ -> -999.0
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
        %{
          type: :box,
          props: %{
            id: :reset,
            fill_width: true,
            height: 60,
            align: :center,
            background: 0xFF9C3A2B,
            accessibility_role: "button",
            accessibility_label: "Reset",
            on_tap: {self(), :reset}
          },
          children: [
            %{
              type: :text,
              props: %{
                text: "RESET",
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
            background: 0xFF6B4A2D,
            align: :center
          },
          children: [
            Mob.Scene3d.viewport(
              id: :world,
              ir: assigns.scene,
              width: 372,
              height: 500,
              background: 0xFF6B4A2D
            )
          ]
        },
        %{
          type: :box,
          props: %{
            fill_width: true,
            height: 40,
            background: 0xFF2A2318,
            align: :center
          },
          children: [
            %{
              type: :text,
              props: %{
                text:
                  "BALL Y = #{:erlang.float_to_binary(ball_y, decimals: 3)} FRAME #{assigns.frame}",
                text_size: 12,
                text_color: 0xFFF0E442,
                font_weight: "bold"
              },
              children: []
            }
          ]
        }
      ]
    }
  end

  defp rebuild_scene(socket) do
    transforms = Physics.transforms(socket.assigns.world)

    ir =
      IR.new([
        camera(),
        sun(),
        ground(),
        ball_entity(transforms)
      ])

    Mob.Socket.assign(socket, :scene, ir)
  end

  defp camera do
    # Camera 1 m up, 2 m back, pitched 15° down. FOV 55° — wide enough
    # that the ball's whole fall from `@drop_height` sits in frame.
    %Entity{
      id: "camera",
      transform: Transform.from_euler({-15.0, 0.0, 0.0}, position: {0.0, 1.0, 2.0}),
      data: %Camera{fov_y: 55.0, near: 0.05, far: 20.0}
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

  defp ball_entity(transforms) do
    {position, rotation} =
      case transforms do
        [{_id, pos, rot} | _] -> {pos, rot}
        _ -> {{0.0, @drop_height, 0.0}, {0.0, 0.0, 0.0, 1.0}}
      end

    # probe.glb is a ~10 cm beveled cube; scale up to roughly match
    # the physics collider radius (0.3 m → 60 cm diameter object).
    s = @ball_radius * 6.0

    %Entity{
      id: "ball",
      transform: %Transform{position: position, rotation: rotation, scale: {s, s, s}},
      data: %Model{asset: "probe.glb"}
    }
  end
end
