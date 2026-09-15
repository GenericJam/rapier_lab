defmodule RapierLab.Physics do
  @moduledoc """
  Rustler entry point for the `lab_physics` crate — the physics NIF the
  spike builds on. Right now this is just a smoke surface (`ping/0` +
  `smoke_drop/0`); the real API (`world_new`, `add_body`, `apply_impulse`,
  `step`, `transforms`) lands in `rapier_lab-epu`.
  """

  use Rustler, otp_app: :rapier_lab, crate: "lab_physics"

  @doc "Returns `:ok` when the NIF is loaded."
  @spec ping() :: :ok
  def ping, do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Runs a canned Rapier smoke: drops a unit-radius ball from 5 m onto a
  ground plane, steps 120 frames at 1/60 s. Returns the ball's final
  y coordinate — should land near 1.0 (its radius; centre resting on
  the plane).
  """
  @spec smoke_drop() :: float()
  def smoke_drop, do: :erlang.nif_error(:nif_not_loaded)
end
