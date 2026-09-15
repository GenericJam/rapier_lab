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

  @impl Mob.Screen
  def mount(_params, _session, socket) do
    world = Physics.world_new()
    ball = Physics.add_ball(world, 0.0, 3.0, 0.0, 0.05)

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
    ball = Physics.add_ball(world, 0.0, 3.0, 0.0, 0.05)
    {:noreply, socket |> Mob.Socket.assign(world: world, ball: ball, frame: 0) |> rebuild_scene()}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  @impl Mob.Screen
  def render(assigns) do
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
        Mob.Scene3d.viewport(
          id: :world,
          ir: assigns.scene,
          width: 372,
          height: 500,
          background: 0xFF6B4A2D
        ),
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
    %Entity{
      id: "camera",
      transform: Transform.from_euler({-20.0, 0.0, 0.0}, position: {0.0, 2.0, 4.0}),
      data: %Camera{fov_y: 40.0, near: 0.05, far: 20.0}
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
        _ -> {{0.0, 3.0, 0.0}, {0.0, 0.0, 0.0, 1.0}}
      end

    %Entity{
      id: "ball",
      transform: %Transform{position: position, rotation: rotation, scale: {0.5, 0.5, 0.5}},
      data: %Model{asset: "probe.glb"}
    }
  end
end
