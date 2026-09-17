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
      # :mob_rapier hosts the physics NIF loaded via Rustler on_load, which
      # calls Application.app_dir/1 — the app must be in the boot manifest
      # or the load raises "unknown application: :mob_rapier" (bead
      # rapier_lab-d00 first-boot failure).
      extra_applications: [:logger, :mob_rapier]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  defp deps do
    [
      # MOB-226: link mob's fix locally until published. The worktree path
      # points at the MOB-226-android-libc-decl branch; when the fix ships
      # in a mob release, revert this line back to the hex tilde-pin.
      {:mob,
       path: System.get_env("MOB_PATH", "/Users/kevin/code/mob/.claude/worktrees/mob-226-libc-android"),
       override: true},
      {:mob_scene3d, path: System.get_env("MOB_SCENE3D_PATH", "/Users/kevin/code/mob_scene3d")},
      # rapier_lab-d00: physics primitives (Rapier NIF + registry + face-up
      # rules) extracted into a reusable Hex-shaped plugin. rapier_lab now
      # keeps only the demo screens; every other physics-facing app can
      # consume mob_rapier the same way.
      {:mob_rapier, path: System.get_env("MOB_RAPIER_PATH", "/Users/kevin/code/mob_rapier")},
      {:mob_dev, "~> 0.7.1", only: :dev, runtime: false},
      {:exqlite, "~> 0.27"},
      {:igniter, "~> 0.8", only: [:dev, :test]}
    ]
  end
end
