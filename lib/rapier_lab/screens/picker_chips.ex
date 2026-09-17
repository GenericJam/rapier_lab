defmodule RapierLab.Screens.PickerChips do
  @moduledoc """
  rapier_lab-rid: shared chip row rendered at the top of every demo
  screen. Tapping a chip swaps the navigation stack (via
  `Mob.Socket.reset_to/3` in the receiving screen) so a chip tap goes
  straight to the target demo without a stacked history.

  The chip table (`entries/0`) is the single source of truth for which
  demos exist and how to open each one. Adding a new demo means adding
  one entry here and wiring the target screen's `handle_info(:pick, _)`
  event; the row + tap dispatch are otherwise identical.
  """

  alias RapierLab.Screens.{ConvexDiceScreen, MultiDiceScreen, ShellsScreen}

  @typedoc "One chip: {tag, label, target_screen, mount_params}"
  @type entry :: {atom(), String.t(), module(), map()}

  @doc """
  The picker's chip table, in display order. Head-most entries are the
  most-featured demos.
  """
  @spec entries() :: [entry()]
  def entries do
    [
      {:pick_shells, "SHELLS", ShellsScreen, %{}},
      {:pick_1d6, "1D6", MultiDiceScreen, %{count: 1}},
      {:pick_10d6, "10D6", MultiDiceScreen, %{count: 10}},
      {:pick_d10, "D10", ConvexDiceScreen, %{shapes: [:d10]}},
      {:pick_d12, "D12", ConvexDiceScreen, %{shapes: [:d12]}},
      {:pick_d20, "D20", ConvexDiceScreen, %{shapes: [:d20]}}
    ]
  end

  @doc """
  Given a tap `tag`, returns `{:ok, screen, params}` for the entry named
  by that tag, or `:error` if the tag is not one of the picker's.
  """
  @spec resolve(atom()) :: {:ok, module(), map()} | :error
  def resolve(tag) do
    case Enum.find(entries(), fn {t, _, _, _} -> t == tag end) do
      {_, _, screen, params} -> {:ok, screen, params}
      nil -> :error
    end
  end

  @doc """
  Renders a horizontally-scrollable row of chips. `active` is the chip
  tag currently owning the screen — its chip is highlighted so users
  see which demo they're in. `sender` is the pid the chip taps route
  back to (typically `self()` inside the screen's `render/1`).
  """
  @spec chip_row(atom(), pid()) :: map()
  def chip_row(active, sender) do
    chips =
      for {tag, label, _screen, _params} <- entries() do
        highlighted? = tag == active

        %{
          type: :box,
          props: %{
            id: tag,
            padding_horizontal: 12,
            padding_vertical: 6,
            background: if(highlighted?, do: 0xFFF5ECD6, else: 0xFF3A2E1E),
            corner_radius: 14,
            align: :center,
            accessibility_role: "button",
            accessibility_label: label,
            on_tap: {sender, tag}
          },
          children: [
            %{
              type: :text,
              props: %{
                text: label,
                text_size: 12,
                text_color: if(highlighted?, do: 0xFF1A1408, else: 0xFFF5ECD6),
                font_weight: "bold",
                letter_spacing: 2.0
              },
              children: []
            }
          ]
        }
      end

    %{
      type: :row,
      props: %{
        fill_width: true,
        height: 44,
        background: 0xFF241C10,
        align: :center,
        padding: 6,
        gap: 6,
        justify: :space_between
      },
      children: chips
    }
  end

  @doc """
  Screen convenience: given a `socket` and a tap `tag`, if `tag` is a
  chip the socket transitions to that demo (via `Mob.Socket.reset_to/3`),
  otherwise the socket is returned untouched so the caller can handle
  the tap as its own.

  Returns `{:handled, socket}` when the chip was recognized, `:passthrough`
  otherwise.
  """
  @spec handle_tap(Mob.Socket.t(), atom()) ::
          {:handled, Mob.Socket.t()} | :passthrough
  def handle_tap(socket, tag) do
    case resolve(tag) do
      {:ok, screen, params} -> {:handled, Mob.Socket.reset_to(socket, screen, params)}
      :error -> :passthrough
    end
  end
end
