defmodule RapierLab.Screens.MainScreen do
  @moduledoc """
  Placeholder for the scaffold bead (`rapier_lab-hmd`). Renders a
  single ink-black box that fills the screen. Once the Rustler +
  Rapier build lands, this screen swaps for a `Mob.Scene3d` viewport
  driven by the physics NIF.
  """

  use Mob.Screen

  @impl Mob.Screen
  def mount(_params, _session, socket), do: {:ok, socket}

  @impl Mob.Screen
  def render(_assigns) do
    %{
      type: :box,
      props: %{
        id: :main,
        fill_width: true,
        fill_height: true,
        background: 0xFF1A1408,
        align: :center
      },
      children: [
        %{
          type: :text,
          props: %{
            text: "RAPIER LAB",
            text_size: 20,
            text_color: 0xFFF5ECD6,
            font_weight: "bold",
            letter_spacing: 4.0
          },
          children: []
        }
      ]
    }
  end
end
