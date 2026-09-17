# Dumps MobRapier.Dice's vertex tables + face-normal tables to
# priv/assets/dice_gen/geometry.json so the Blender build script can
# consume them authoritatively (single source of truth for face order).
#
# Run: mix run priv/assets/dice_gen/dump_geometry.exs

alias MobRapier.Dice

d10_normals = Dice.d10_face_normals()
d12_normals = Dice.d12_face_normals()
d20_normals = Dice.d20_face_normals()

geometry = %{
  d6: %{
    # Cube: 6 face normals in the exact order MobRapier.Dice.face_up_d6
    # decodes to face 1..6.
    #   +Y -> 1, -Y -> 6, +X -> 2, -X -> 5, +Z -> 3, -Z -> 4
    faces: [
      %{index: 1, normal: [0.0, 1.0, 0.0]},
      %{index: 6, normal: [0.0, -1.0, 0.0]},
      %{index: 2, normal: [1.0, 0.0, 0.0]},
      %{index: 5, normal: [-1.0, 0.0, 0.0]},
      %{index: 3, normal: [0.0, 0.0, 1.0]},
      %{index: 4, normal: [0.0, 0.0, -1.0]}
    ]
  },
  d10: %{
    vertices: Enum.map(Dice.pentagonal_trapezohedron_vertices(), &Tuple.to_list/1),
    faces:
      d10_normals
      |> Enum.with_index(1)
      |> Enum.map(fn {n, i} -> %{index: i, normal: Tuple.to_list(n)} end)
  },
  d12: %{
    vertices: Enum.map(Dice.dodecahedron_vertices(), &Tuple.to_list/1),
    faces:
      d12_normals
      |> Enum.with_index(1)
      |> Enum.map(fn {n, i} -> %{index: i, normal: Tuple.to_list(n)} end)
  },
  d20: %{
    vertices: Enum.map(Dice.icosahedron_vertices(), &Tuple.to_list/1),
    faces:
      d20_normals
      |> Enum.with_index(1)
      |> Enum.map(fn {n, i} -> %{index: i, normal: Tuple.to_list(n)} end)
  }
}

path =
  Path.join([
    File.cwd!(),
    "priv",
    "assets",
    "dice_gen",
    "geometry.json"
  ])

File.write!(path, Jason.encode!(geometry, pretty: true))
IO.puts("wrote #{path}")
