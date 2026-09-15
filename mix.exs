defmodule RapierLab.MixProject do
  use Mix.Project

  def project do
    [
      app: :rapier_lab,
      version: "0.1.0",
      elixir: "~> 1.20",
      elixirc_paths: elixirc_paths(Mix.env()),
      erlc_paths: ["src"],
      erlc_options: [:debug_info],
      start_permanent: Mix.env() == :prod,
      elixirc_options: [warnings_as_errors: true],
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  defp deps do
    [
      {:mob, "~> 0.7.37"},
      {:mob_scene3d, path: System.get_env("MOB_SCENE3D_PATH", "/Users/kevin/code/mob_scene3d")},
      {:mob_dev, "~> 0.6.30", only: :dev, runtime: false},
      {:exqlite, "~> 0.27"},
      {:igniter, "~> 0.8", only: [:dev, :test]},
      # Rustler drives the `lab_physics` NIF crate at native/lab_physics/.
      # That crate wraps `rapier3d` — the physics engine this spike exists
      # to evaluate (bead rapier_lab-pkb).
      {:rustler, "~> 0.37"}
    ]
  end
end
