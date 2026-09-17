"""Blender headless script — builds d6/d10/d12/d20 meshes with numerals
whose face positions match MobRapier.Dice.face_up_dN, and writes each as
a .glb into priv/assets/.

Run:
    /Applications/Blender.app/Contents/MacOS/Blender \
        --background --python priv/assets/dice_gen/build_dice.py

Reads priv/assets/dice_gen/geometry.json (produced by dump_geometry.exs)
so face ordering is authoritative rather than reimplemented.

Design:
- Unit die (radius ~1.0 in mesh-space). Physics collider uses die_scale
  = 0.03 m via add_convex_hull's scale arg; the visual entity is scaled
  the same way from a mesh centred at the origin, so no per-glb scale
  math to keep in sync.
- Body: matte ivory PBR.
- Numerals: darker text objects positioned on each face and rotated so
  the numeral lies flat on the face, upright when the face points at
  world +y. On the d6 the numerals are replaced by classical pip clusters.
- Numerals sit *on* the surface (not carved into it) because boolean
  subtraction on convex hulls in headless Blender is finicky; a slight
  outward offset keeps them visible without z-fighting.
"""

import json
import math
import os
import sys

import bpy
import bmesh
from mathutils import Matrix, Vector

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
GEOMETRY_JSON = os.path.join(REPO_ROOT, "priv", "assets", "dice_gen", "geometry.json")
OUT_DIR = os.path.join(REPO_ROOT, "priv", "assets")

# ── colours ────────────────────────────────────────────────────────────
BODY_ALBEDO = (0.90, 0.86, 0.75, 1.0)  # warm ivory
BODY_ROUGHNESS = 0.42
NUMERAL_ALBEDO = (0.06, 0.05, 0.05, 1.0)  # near-black
NUMERAL_ROUGHNESS = 0.35

# Body scale — a unit-radius die (numerals are sized relative to this).
BODY_RADIUS = 1.0

# Numeral / pip sizing.
NUMERAL_DEPTH = 0.02   # extrusion depth
NUMERAL_OFFSET = 0.001  # outward push to avoid z-fighting
PIP_RADIUS = 0.09       # d6 pip radius
PIP_DEPTH = 0.02


def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for block in list(bpy.data.meshes):
        bpy.data.meshes.remove(block)
    for block in list(bpy.data.materials):
        bpy.data.materials.remove(block)
    for block in list(bpy.data.curves):
        bpy.data.curves.remove(block)


def make_material(name, albedo, roughness):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = albedo
        bsdf.inputs["Roughness"].default_value = roughness
    return mat


# ── body construction ─────────────────────────────────────────────────
def make_cube_body(name):
    bpy.ops.mesh.primitive_cube_add(size=2.0 * BODY_RADIUS)  # cube half-extent
    obj = bpy.context.active_object
    obj.name = name
    # Slight bevel so the die reads as a die, not a warehouse crate.
    mod = obj.modifiers.new(name="bevel", type="BEVEL")
    mod.width = 0.08
    mod.segments = 3
    bpy.ops.object.modifier_apply(modifier="bevel")
    return obj


def make_hull_body(name, vertices):
    """Build a convex hull from the given vertex cloud (list of [x, y, z]).
    Normalises so the vertex cloud fits inside a unit sphere.

    No bevel: bevel subdivides each face into sub-triangles whose
    normals no longer point exactly at the die's face-up direction, so
    `match_face_centroid` gets confused and places numerals on the wrong
    face. Sharp edges are fine for demo purposes."""
    max_r = max(math.sqrt(x * x + y * y + z * z) for x, y, z in vertices)
    scale = BODY_RADIUS / max_r

    mesh = bpy.data.meshes.new(name + "_mesh")
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    bpy.context.view_layer.objects.active = obj

    bm = bmesh.new()
    for x, y, z in vertices:
        bm.verts.new((x * scale, y * scale, z * scale))
    bm.verts.ensure_lookup_table()
    bmesh.ops.convex_hull(bm, input=bm.verts)
    bm.to_mesh(mesh)
    bm.free()

    return obj


def assign_material(obj, material):
    obj.data.materials.append(material)


# ── face annotation ────────────────────────────────────────────────────
def face_frame(normal):
    """Return a rotation matrix whose +Z axis is `normal`, +Y is a tangent
    that reads as 'up' when the face is oriented world-up (positive-Y in
    world space projected onto the face plane, falling back to +X when the
    face is horizontal)."""
    n = Vector(normal).normalized()
    # Prefer world +Y as the 'text-top' direction; if the face itself is
    # (anti)parallel to world Y, fall back to +X.
    ref = Vector((0.0, 1.0, 0.0))
    if abs(n.dot(ref)) > 0.99:
        ref = Vector((1.0, 0.0, 0.0))
    up = (ref - n * n.dot(ref)).normalized()
    right = up.cross(n).normalized()
    # Build a 3×3 rotation with columns (right, up, n).
    rot = Matrix((right, up, n)).transposed()
    return rot


def face_center(normal, radius):
    """Approximate face centre for a face whose outward normal is
    `normal` on a die of circumradius `radius`. This is a fallback for
    the d6 (cube) where the face centre IS along the normal at the
    half-extent. For hulled dice the actual face centroid comes from
    the built mesh via `hull_face_centroids/1`."""
    return Vector(normal).normalized() * radius


def hull_face_centroids(body_obj):
    """After the hull is built, return a list of `(centroid, normal,
    area)` tuples in world-ish space (die centred at origin,
    circumradius 1).

    `bmesh.ops.convex_hull` always outputs triangles, so a pentagonal
    dodec face arrives as three triangles that share an outward
    normal — a naive centroid-per-poly puts the numeral on ONE of the
    triangles, not the pentagon centre. Coplanar triangles are merged
    here by grouping polygons whose normals point within a small
    tolerance, then averaging vertex positions across the whole
    group. Trapezohedron (d10) has kite faces that hull to two
    triangles per kite; same treatment covers them."""
    mesh = body_obj.data
    # Group polygons by binned normal direction. Bin resolution is
    # ~5° (dot > 0.996), tight enough that no two distinct face
    # normals on a d20/d12/d10 collide but loose enough that all
    # triangles sharing a face — even ones whose normals differ
    # slightly from float noise (the pentagonal-trapezohedron kites
    # in particular) — merge together.
    groups = []  # list of {"normal": Vector, "vert_ids": set(int), "area": float}
    for poly in mesh.polygons:
        if poly.area < 1.0e-4:
            continue
        n = Vector(poly.normal).normalized()
        matched = None
        for g in groups:
            if g["normal"].dot(n) > 0.996:
                matched = g
                break
        if matched is None:
            matched = {"normal": n, "vert_ids": set(), "area": 0.0}
            groups.append(matched)
        # Accumulate area-weighted normal so the group's normal reflects
        # the whole face (a large triangle contributes more than the
        # small sliver that snuck in due to bevel or float noise).
        matched["normal"] = (matched["normal"] * matched["area"] + n * poly.area).normalized()
        matched["vert_ids"].update(poly.vertices)
        matched["area"] += poly.area

    faces = []
    for g in groups:
        centroid = Vector((0.0, 0.0, 0.0))
        for vi in g["vert_ids"]:
            centroid += mesh.vertices[vi].co
        centroid /= len(g["vert_ids"])
        faces.append((centroid, g["normal"], g["area"]))
    return faces


def match_face_centroid(hull_faces, target_normal, min_area=0.05):
    """Find the hull polygon whose outward normal aligns most closely
    with `target_normal`. Returns `(centroid, normal)` of the best match.

    `min_area` skips small bevel-edge polygons that happen to point
    roughly the right direction but are not the face we want. It's an
    absolute mesh-space area (unit-circumradius body) — the primary
    face polygons on all four dice are well above 0.1."""
    target = Vector(target_normal).normalized()
    best = None
    best_dot = -2.0
    for centroid, normal, area in hull_faces:
        if area < min_area:
            continue
        dot = normal.dot(target)
        if dot > best_dot:
            best_dot = dot
            best = (centroid, normal)
    return best


def add_numeral(die_obj, face, radius, size_scale=0.42, numeral_material=None,
                hull_faces=None, outward_offset=None):
    """Add a numeric text mesh on the die's face.

    When `hull_faces` is given, the numeral is placed at the matched
    hull polygon's centroid (accurate — sits ON the face). Otherwise
    falls back to circumradius × normal (correct for a cube but too
    far out for the icosahedron/dodecahedron/trapezohedron)."""
    if outward_offset is None:
        outward_offset = NUMERAL_OFFSET

    n = Vector(face["normal"]).normalized()
    if hull_faces is not None:
        match = match_face_centroid(hull_faces, n)
        if match is not None:
            centroid, face_normal = match
            center = centroid + face_normal * outward_offset
            rot = face_frame(face_normal)
        else:
            center = face_center(n, radius) + n * outward_offset
            rot = face_frame(n)
    else:
        center = face_center(n, radius) + n * outward_offset
        rot = face_frame(n)

    bpy.ops.object.text_add()
    txt = bpy.context.active_object
    txt.name = f"{die_obj.name}_numeral_{face['index']}"
    txt.data.body = str(face["index"])
    txt.data.align_x = "CENTER"
    txt.data.align_y = "CENTER"
    txt.data.extrude = NUMERAL_DEPTH
    txt.data.size = size_scale

    # Convert curve -> mesh so glTF export handles it as geometry.
    bpy.ops.object.convert(target="MESH")

    # Position + orient
    txt.matrix_world = Matrix.Translation(center) @ rot.to_4x4()

    if numeral_material is not None:
        assign_material(txt, numeral_material)

    # Parent to the die body so exporter groups them.
    txt.parent = die_obj


# ── d6 pips ────────────────────────────────────────────────────────────
# Classical pip layouts for each face (in face-plane coordinates, where
# (0,0) is the face centre and ±1 corresponds to the die's edge). The
# layouts follow standard Western dice: 1 in centre, 2 diagonal, 3
# diagonal + centre, 4 corners, 5 corners + centre, 6 in two columns.
PIP_LAYOUTS = {
    1: [(0.0, 0.0)],
    2: [(-0.5, 0.5), (0.5, -0.5)],
    3: [(-0.55, 0.55), (0.0, 0.0), (0.55, -0.55)],
    4: [(-0.5, 0.5), (0.5, 0.5), (-0.5, -0.5), (0.5, -0.5)],
    5: [(-0.55, 0.55), (0.55, 0.55), (0.0, 0.0), (-0.55, -0.55), (0.55, -0.55)],
    6: [
        (-0.55, 0.6), (0.55, 0.6),
        (-0.55, 0.0), (0.55, 0.0),
        (-0.55, -0.6), (0.55, -0.6),
    ],
}


def add_pips(die_obj, face, radius, numeral_material=None):
    """Add classic pip cylinders to a d6 face."""
    n = Vector(face["normal"]).normalized()
    rot = face_frame(n)
    center = face_center(n, radius)

    for u, v in PIP_LAYOUTS[face["index"]]:
        # face-plane u = right, v = up
        offset = rot @ Vector((u * 0.55, v * 0.55, 0.0))
        loc = center + offset + n * NUMERAL_OFFSET
        bpy.ops.mesh.primitive_cylinder_add(
            radius=PIP_RADIUS, depth=PIP_DEPTH, location=loc
        )
        pip = bpy.context.active_object
        pip.name = f"{die_obj.name}_pip_{face['index']}_{u}_{v}"
        # Align cylinder axis to face normal
        pip.matrix_world = Matrix.Translation(loc) @ rot.to_4x4() @ Matrix.Rotation(
            math.pi / 2.0, 4, "X"
        )
        if numeral_material is not None:
            assign_material(pip, numeral_material)
        pip.parent = die_obj


# ── export ─────────────────────────────────────────────────────────────
def export_glb(die_obj, out_name):
    # Select the die and every child mesh.
    bpy.ops.object.select_all(action="DESELECT")
    die_obj.select_set(True)
    for child in die_obj.children:
        child.select_set(True)
    bpy.context.view_layer.objects.active = die_obj

    out_path = os.path.join(OUT_DIR, out_name)
    bpy.ops.export_scene.gltf(
        filepath=out_path,
        export_format="GLB",
        use_selection=True,
        export_apply=True,
    )
    print(f"wrote {out_path}")


# ── main ───────────────────────────────────────────────────────────────
def build_d6(geometry):
    clear_scene()
    body_material = make_material("die_body", BODY_ALBEDO, BODY_ROUGHNESS)
    numeral_material = make_material("die_numeral", NUMERAL_ALBEDO, NUMERAL_ROUGHNESS)
    body = make_cube_body("d6")
    assign_material(body, body_material)
    for face in geometry["d6"]["faces"]:
        add_pips(body, face, BODY_RADIUS, numeral_material=numeral_material)
    export_glb(body, "d6.glb")


def build_hulled(shape_key, out_name, geometry, numeral_scale=0.42):
    clear_scene()
    body_material = make_material("die_body", BODY_ALBEDO, BODY_ROUGHNESS)
    numeral_material = make_material("die_numeral", NUMERAL_ALBEDO, NUMERAL_ROUGHNESS)
    body = make_hull_body(shape_key, geometry[shape_key]["vertices"])
    assign_material(body, body_material)

    # For d10 the kite faces are not planar under our specific
    # trapezohedron vertex placement, so hull_face_centroids can't merge
    # them into 10 groups. Analytic kite centroids from the vertex
    # table stand in — and, because the kite's centroid sits slightly
    # BEHIND the triangulated mesh surface, we pass a larger outward
    # offset for d10 to lift the numeral above that surface.
    if shape_key == "d10":
        hull_faces = trapezohedron_kite_centroids(geometry["d10"]["vertices"], body)
        # Centroid is now ON the mesh surface (raycast hit), so the
        # standard tiny outward push is enough.
        numeral_offset = NUMERAL_OFFSET
    else:
        hull_faces = hull_face_centroids(body)
        numeral_offset = NUMERAL_OFFSET

    print(f"[{shape_key}] using {len(hull_faces)} face-centroid records")

    for face in geometry[shape_key]["faces"]:
        add_numeral(
            body,
            face,
            BODY_RADIUS,
            size_scale=numeral_scale,
            numeral_material=numeral_material,
            hull_faces=hull_faces,
            outward_offset=numeral_offset,
        )
    export_glb(body, out_name)


def trapezohedron_kite_centroids(vertices, body_obj):
    """For MobRapier.Dice.pentagonal_trapezohedron_vertices structure —
    2 apexes + 5 upper ring + 5 lower ring (upper offset by 36° from
    lower) — return 10 (centroid, normal, area) records.

    Our specific vertex placement produces non-planar kites (the two
    triangles Blender's convex_hull emits per kite have non-parallel
    normals), so hull_face_centroids can't merge them into 10 groups
    by normal. Instead we compute the analytic kite centroid and then
    project it OUTWARD along the centroid direction until it hits one
    of the mesh's triangles for that kite — so the numeral sits ON
    the visible surface instead of behind it (where the 4-vertex
    average lands inside the mesh).

    The resulting centroid is on the mesh surface; the returned
    normal is the mesh triangle's normal at that point (not the
    average kite direction) so numeral orientation reflects the
    actual face plane."""
    # Normalise the same way make_hull_body did.
    max_r = max(math.sqrt(x * x + y * y + z * z) for x, y, z in vertices)
    scale = BODY_RADIUS / max_r
    v = [Vector((x * scale, y * scale, z * scale)) for x, y, z in vertices]

    apex_top = v[0]
    apex_bot = v[1]
    upper = v[2:7]
    lower = v[7:12]

    faces = []
    # Top kites (face 1..5): apex_top, upper_k, lower_k, upper_{k+1}
    for k in range(5):
        verts = [apex_top, upper[k], lower[k], upper[(k + 1) % 5]]
        centroid_analytic = sum(verts, Vector()) / len(verts)
        direction = centroid_analytic.normalized()
        surface_pt, surface_n = raycast_from_origin(body_obj, direction)
        if surface_pt is not None:
            faces.append((surface_pt, surface_n, 1.0))
        else:
            faces.append((centroid_analytic, direction, 1.0))
    # Bottom kites (face 6..10): apex_bot, lower_k, upper_{k+1}, lower_{k+1}
    for k in range(5):
        verts = [apex_bot, lower[k], upper[(k + 1) % 5], lower[(k + 1) % 5]]
        centroid_analytic = sum(verts, Vector()) / len(verts)
        direction = centroid_analytic.normalized()
        surface_pt, surface_n = raycast_from_origin(body_obj, direction)
        if surface_pt is not None:
            faces.append((surface_pt, surface_n, 1.0))
        else:
            faces.append((centroid_analytic, direction, 1.0))
    return faces


def raycast_from_origin(body_obj, direction):
    """Ray from origin in `direction`, return the (hit_point,
    face_normal) of the first mesh polygon hit. Uses Blender's
    ray_cast on the object."""
    origin = Vector((0.0, 0.0, 0.0))
    # Blender's obj.ray_cast expects a start point and direction in
    # object-local coordinates. Body is at origin identity for now.
    hit, location, normal, index = body_obj.ray_cast(origin, direction)
    if hit:
        return location, Vector(normal).normalized()
    return None, None


def main():
    with open(GEOMETRY_JSON) as f:
        geometry = json.load(f)

    build_d6(geometry)
    # Numeral sizing tuned per shape so digits fill each face — d20 has
    # 20 small triangles, d12 has 12 pentagons, d10 has 10 tall kites.
    build_hulled("d20", "d20.glb", geometry, numeral_scale=0.42)
    build_hulled("d12", "d12.glb", geometry, numeral_scale=0.55)
    # d10 numeral scale 0.55 fits a two-digit number ("10") inside the
    # kite bounds without clipping, and reads at the demo camera
    # distance without needing a magnifier.
    build_hulled("d10", "d10.glb", geometry, numeral_scale=0.55)


if __name__ == "__main__":
    main()
