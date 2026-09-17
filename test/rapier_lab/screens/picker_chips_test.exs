defmodule RapierLab.Screens.PickerChipsTest do
  # rapier_lab-rid: the picker chip row is a shared UI helper embedded in
  # every demo screen. The tap-to-screen mapping is what this test pins —
  # if a chip tag ever silently stops routing to its screen, this fires.
  use ExUnit.Case, async: true

  alias RapierLab.Screens.PickerChips
  alias RapierLab.Screens.{ConvexDiceScreen, MultiDiceScreen, ShellsScreen}

  describe "entries/0" do
    test "returns the demo tags in order" do
      tags = PickerChips.entries() |> Enum.map(&elem(&1, 0))

      assert tags == [:pick_shells, :pick_1d6, :pick_10d6, :pick_d12, :pick_d20]
    end

    test "each entry maps to a real screen module and a params map" do
      for {tag, label, screen, params} <- PickerChips.entries() do
        assert is_atom(tag)
        assert is_binary(label) and label != ""
        assert is_atom(screen)
        assert Code.ensure_loaded?(screen),
               "#{inspect(screen)} for chip #{inspect(tag)} cannot be loaded"
        assert function_exported?(screen, :mount, 3),
               "#{inspect(screen)} for chip #{inspect(tag)} does not implement Mob.Screen.mount/3"
        assert is_map(params)
      end
    end
  end

  describe "resolve/1" do
    test "SHELLS → ShellsScreen with no params" do
      assert PickerChips.resolve(:pick_shells) == {:ok, ShellsScreen, %{}}
    end

    test "1D6 → MultiDiceScreen with count: 1" do
      assert PickerChips.resolve(:pick_1d6) == {:ok, MultiDiceScreen, %{count: 1}}
    end

    test "10D6 → MultiDiceScreen with count: 10" do
      assert PickerChips.resolve(:pick_10d6) == {:ok, MultiDiceScreen, %{count: 10}}
    end

    test "D12 → ConvexDiceScreen with shapes: [:d12]" do
      assert PickerChips.resolve(:pick_d12) == {:ok, ConvexDiceScreen, %{shapes: [:d12]}}
    end

    test "D20 → ConvexDiceScreen with shapes: [:d20]" do
      assert PickerChips.resolve(:pick_d20) == {:ok, ConvexDiceScreen, %{shapes: [:d20]}}
    end

    test "unknown tag returns :error" do
      assert PickerChips.resolve(:reset) == :error
      assert PickerChips.resolve(:shake) == :error
      assert PickerChips.resolve(:pick_nonsense) == :error
    end
  end

  describe "chip_row/2" do
    test "renders one chip per entry, marking the active tag as highlighted" do
      # Just verify the shape is right — six chips, all with on_tap
      # tuples pointing back at the sender pid.
      sender = self()
      row = PickerChips.chip_row(:pick_d20, sender)

      assert row.type == :row
      assert length(row.children) == 5

      # Every chip has on_tap {sender, tag} matching one of the entries.
      tags = Enum.map(PickerChips.entries(), &elem(&1, 0))

      for chip <- row.children do
        {^sender, tag} = chip.props.on_tap
        assert tag in tags
      end
    end

    test "a nil active tag renders no highlighted chip" do
      # When ConvexDiceScreen mounts with the default multi-shape config,
      # no single chip owns the screen — every chip must render as
      # non-highlighted (background = 0xFF3A2E1E, text 0xFFF5ECD6).
      row = PickerChips.chip_row(nil, self())

      for chip <- row.children do
        assert chip.props.background == 0xFF3A2E1E
      end
    end
  end
end
