defmodule RapierLab.Screens.MainScreen do
  @moduledoc """
  Placeholder for the scaffold bead (`rapier_lab-hmd`). Renders a
  single ink-black box that fills the screen. Once the Rustler +
  Rapier build lands, this screen swaps for a `Mob.Scene3d` viewport
  driven by the physics NIF.
  """

  use Mob.Screen

  @impl Mob.Screen
  def mount(_params, _session, socket) do
    ping_result =
      try do
        RapierLab.Physics.ping()
      rescue
        e -> {:error, Exception.message(e)}
      end

    drop_result =
      try do
        RapierLab.Physics.smoke_drop()
      rescue
        e -> {:error, Exception.message(e)}
      end

    {:ok, Mob.Socket.assign(socket, ping: ping_result, drop: drop_result)}
  end

  @impl Mob.Screen
  def render(%{ping: ping, drop: drop}) do
    line1 =
      case ping do
        :ok -> "NIF LOADED"
        other -> "PING = #{inspect(other)}"
      end

    line2 =
      case drop do
        y when is_float(y) -> "BALL RESTED AT Y=#{:erlang.float_to_binary(y, decimals: 3)} m"
        other -> "DROP = #{inspect(other)}"
      end

    %{
      type: :column,
      props: %{
        id: :main,
        fill_width: true,
        fill_height: true,
        background: 0xFF1A1408,
        align: :center,
        gap: 12
      },
      children: [
        %{
          type: :text,
          props: %{
            text: "RAPIER LAB",
            text_size: 24,
            text_color: 0xFFF5ECD6,
            font_weight: "bold",
            letter_spacing: 4.0
          },
          children: []
        },
        %{
          type: :text,
          props: %{
            text: line1,
            text_size: 12,
            text_color: 0xFFF0E442,
            font_weight: "semibold",
            letter_spacing: 2.0
          },
          children: []
        },
        %{
          type: :text,
          props: %{
            text: line2,
            text_size: 11,
            text_color: 0xFF9C9078,
            font_weight: "semibold",
            letter_spacing: 1.5
          },
          children: []
        }
      ]
    }
  end
end
