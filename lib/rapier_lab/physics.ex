defmodule RapierLab.Physics do
  @moduledoc """
  Rustler entry point for the `lab_physics` crate — Rapier wrapped as
  an Elixir-side API. A world is a stateful resource handle; add
  bodies to it, step it forward each tick, read transforms back to
  drive the scene.

  Rustler 0.38+ carries the Bionic dlsym fix, so this NIF loads on
  Android without the 0.37-era crash (bead `rapier_lab-2ie`).
  """

  use Rustler, otp_app: :rapier_lab, crate: "lab_physics"

  @typedoc "A resource handle to a physics world."
  @opaque world :: reference()

  @typedoc "Elixir-side body id — the insertion index into the world."
  @type body_id :: non_neg_integer()

  @typedoc "One body's transform: `{id, {x, y, z}, {qx, qy, qz, qw}}`."
  @type transform :: {body_id(), {float(), float(), float()}, {float(), float(), float(), float()}}

  @doc "Returns `:ok` when the NIF is loaded."
  @spec ping() :: :ok
  def ping, do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Creates a new physics world. Comes pre-populated with gravity
  `{0, -9.81, 0}` and a static wide ground plane at `y = 0`.
  """
  @spec world_new() :: world()
  def world_new, do: :erlang.nif_error(:nif_not_loaded)

  @doc "Adds a dynamic ball to `world` at `{x, y, z}` with `radius`."
  @spec add_ball(world(), float(), float(), float(), float()) :: body_id()
  def add_ball(_world, _x, _y, _z, _radius), do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Adds a dynamic cuboid to `world` at `{x, y, z}` with half-extents
  `{hx, hy, hz}`. A unit d6 is `hx = hy = hz = 0.5`.
  """
  @spec add_cuboid(world(), float(), float(), float(), float(), float(), float()) :: body_id()
  def add_cuboid(_world, _x, _y, _z, _hx, _hy, _hz), do: :erlang.nif_error(:nif_not_loaded)

  @doc "Applies a linear impulse to `body_id`'s centre of mass."
  @spec apply_impulse(world(), body_id(), float(), float(), float()) :: :ok
  def apply_impulse(_world, _body_id, _ix, _iy, _iz), do: :erlang.nif_error(:nif_not_loaded)

  @doc "Steps `world` forward by `dt` seconds."
  @spec step(world(), float()) :: :ok
  def step(_world, _dt), do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Every body's transform as `[{id, {x, y, z}, {qx, qy, qz, qw}}]`, in
  insertion order.
  """
  @spec transforms(world()) :: [transform()]
  def transforms(_world), do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Legacy smoke: canned drop, returns the ball's final y. Kept for the
  boot-time NIF check on MainScreen until the demo takes its place.
  """
  @spec smoke_drop() :: float()
  def smoke_drop, do: :erlang.nif_error(:nif_not_loaded)
end
