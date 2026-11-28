"""Check a model is the number of solid pieces you expect, before slicing it.

  check-model.py MODEL.3mf|MODEL.stl [--parts N]

A leg that stops short of its plate prints as two loose parts, and a strength
calculation done on the joined shape says nothing about them. Each build item of
a 3mf counts separately, because the slicer rearranges items on the plate. Exit 0 when the
mesh has exactly N connected pieces (default 1), 1 when it has a different
number, 2 on bad input. Pieces are connected through shared vertex positions.
"""

import argparse
import struct
import sys
import xml.etree.ElementTree as ET
import zipfile
from pathlib import Path

Vertex = tuple[float, float, float]
Triangle = tuple[Vertex, Vertex, Vertex]
CORE_NS = "{http://schemas.microsoft.com/3dmanufacturing/core/2015/02}"
ROUND = 4  # decimals; vertices closer than this are the same point


Matrix = tuple[float, ...]  # 3mf "m00 m01 m02 m10 m11 m12 m20 m21 m22 m30 m31 m32"
IDENTITY: Matrix = (1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0)
PATH_ATTR = "{http://schemas.microsoft.com/3dmanufacturing/production/2015/06}path"
MAX_NESTING = 16


def _matrix(text: str | None) -> Matrix:
    if not text:
        return IDENTITY
    values = tuple(float(x) for x in text.split())
    if len(values) != 12:
        raise ValueError(f"transform needs 12 numbers, got {len(values)}")
    return values


def _apply(m: Matrix, v: Vertex) -> Vertex:
    x, y, z = v
    return (
        x * m[0] + y * m[3] + z * m[6] + m[9],
        x * m[1] + y * m[4] + z * m[7] + m[10],
        x * m[2] + y * m[5] + z * m[8] + m[11],
    )


def _mesh_triangles(mesh: ET.Element) -> list[Triangle]:
    verts = [
        (float(v.get("x", 0)), float(v.get("y", 0)), float(v.get("z", 0)))
        for v in mesh.iter(f"{CORE_NS}vertex")
    ]
    return [
        (
            verts[int(t.get("v1", 0))],
            verts[int(t.get("v2", 0))],
            verts[int(t.get("v3", 0))],
        )
        for t in mesh.iter(f"{CORE_NS}triangle")
    ]


UNIT_MM = {
    "micron": 0.001,
    "millimeter": 1.0,
    "centimeter": 10.0,
    "inch": 25.4,
    "foot": 304.8,
    "meter": 1000.0,
}


def _read_3mf(path: Path) -> list[list[Triangle]]:
    """One triangle list per build item, in millimetres, placed by its transforms.

    Qidi Studio keeps meshes in 3D/Objects/*.model and points at them from
    <component p:path=...> or <item p:path=...>; a plain 3mf (OpenSCAD) has the
    mesh in 3dmodel.model. Items stay separate: the slicer rearranges them, so
    touching in the file does not mean joined on the plate.
    """
    with zipfile.ZipFile(path) as z:
        models = {
            "/" + n: ET.fromstring(z.read(n))
            for n in z.namelist()
            if n.endswith(".model")
        }
    main_name = "/3D/3dmodel.model"
    if main_name not in models:
        raise ValueError("no 3D/3dmodel.model in the 3mf")
    unit = models[main_name].get("unit", "millimeter")
    if unit not in UNIT_MM:
        raise ValueError(f"unknown unit {unit!r}")
    scale = UNIT_MM[unit]
    to_mm: Matrix = (scale, 0, 0, 0, scale, 0, 0, 0, scale, 0, 0, 0)
    objects: dict[tuple[str, str], ET.Element] = {
        (name, str(o.get("id"))): o
        for name, root in models.items()
        for o in root.iter(f"{CORE_NS}object")
    }

    def visit(
        name: str, obj_id: str, chain: tuple[Matrix, ...], out: list[Triangle]
    ) -> None:
        if len(chain) > MAX_NESTING:
            raise ValueError("components nested too deeply (a cycle?)")
        obj = objects.get((name, obj_id))
        if obj is None:
            raise ValueError(f"object {obj_id} not found in {name}")
        if (
            obj.get("type", "model") != "model"
        ):  # support, solidsupport, other: never printed as a part
            return
        for mesh in obj.findall(f"{CORE_NS}mesh"):
            for tri in _mesh_triangles(mesh):
                placed = tri
                for m in chain:
                    placed = (
                        _apply(m, placed[0]),
                        _apply(m, placed[1]),
                        _apply(m, placed[2]),
                    )
                out.append(placed)
        for comp in obj.iter(f"{CORE_NS}component"):
            target = comp.get(PATH_ATTR) or name
            visit(
                target,
                str(comp.get("objectid")),
                (_matrix(comp.get("transform")),) + chain,
                out,
            )

    groups: list[list[Triangle]] = []
    all_items = list(models[main_name].iter(f"{CORE_NS}item"))
    if all_items:
        for item in all_items:
            if item.get("printable") == "0":
                continue
            group: list[Triangle] = []
            target = item.get(PATH_ATTR) or main_name
            visit(
                target,
                str(item.get("objectid")),
                (_matrix(item.get("transform")), to_mm),
                group,
            )
            groups.append(group)
    else:  # no <build>: every top-level object in the main file
        for name, obj_id in [k for k in objects if k[0] == main_name]:
            group = []
            visit(name, obj_id, (to_mm,), group)
            groups.append(group)
    return [g for g in groups if g]


def _read_stl(path: Path) -> list[Triangle]:
    data = path.read_bytes()
    if len(data) >= 84 and 84 + 50 * struct.unpack_from("<I", data, 80)[0] == len(data):
        tris: list[Triangle] = []
        for i in range(struct.unpack_from("<I", data, 80)[0]):
            f = struct.unpack_from("<12f", data, 84 + 50 * i)
            tris.append(((f[3], f[4], f[5]), (f[6], f[7], f[8]), (f[9], f[10], f[11])))
        return tris
    pts: list[Vertex] = []
    for line in data.decode("ascii", "replace").splitlines():
        parts = line.split()
        if parts[:1] == ["vertex"]:
            pts.append((float(parts[1]), float(parts[2]), float(parts[3])))
    return [(pts[i], pts[i + 1], pts[i + 2]) for i in range(0, len(pts) - 2, 3)]


def read_items(path: Path) -> list[list[Triangle]]:
    """Triangles grouped by what the slicer treats as one object."""
    suffix = path.suffix.lower()
    if suffix == ".3mf":
        return _read_3mf(path)
    if suffix == ".stl":
        tris = _read_stl(path)
        return [tris] if tris else []
    raise ValueError(f"unsupported model format {suffix!r}; use .3mf or .stl")


def read_triangles(path: Path) -> list[Triangle]:
    return [t for group in read_items(path) for t in group]


def count_pieces(tris: list[Triangle]) -> int:
    parent: dict[Vertex, Vertex] = {}

    def key(v: Vertex) -> Vertex:
        k = (round(v[0], ROUND), round(v[1], ROUND), round(v[2], ROUND))
        parent.setdefault(k, k)
        return k

    def find(k: Vertex) -> Vertex:
        while parent[k] != k:
            parent[k] = parent[parent[k]]
            k = parent[k]
        return k

    for a, b, c in tris:
        ka, kb, kc = key(a), key(b), key(c)
        parent[find(kb)] = find(ka)
        parent[find(kc)] = find(ka)
    return len({find(k) for k in parent})


def bounding_box(tris: list[Triangle]) -> tuple[Vertex, Vertex]:
    pts = [v for t in tris for v in t]
    return (
        (min(p[0] for p in pts), min(p[1] for p in pts), min(p[2] for p in pts)),
        (max(p[0] for p in pts), max(p[1] for p in pts), max(p[2] for p in pts)),
    )


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("model", type=Path)
    ap.add_argument(
        "--parts", type=int, default=1, help="expected number of separate pieces"
    )
    args = ap.parse_args(argv)
    try:
        groups = read_items(args.model)
    except (
        OSError,
        ValueError,
        KeyError,
        IndexError,
        ET.ParseError,
        zipfile.BadZipFile,
        struct.error,
    ) as e:
        print(f"cannot read {args.model}: {e}", file=sys.stderr)
        return 2
    tris = [t for g in groups for t in g]
    if not tris:
        print(f"{args.model} has no triangles", file=sys.stderr)
        return 2
    n = sum(count_pieces(g) for g in groups)
    lo, hi = bounding_box(tris)
    print(
        f"pieces={n} size_mm={hi[0] - lo[0]:.1f}x{hi[1] - lo[1]:.1f}x{hi[2] - lo[2]:.1f}"
    )
    if n != args.parts:
        print(
            f"expected {args.parts} piece(s), found {n}: parts that do not touch print as loose "
            "pieces. Fix the model (overlap the parts) or pass --parts if intended.",
            file=sys.stderr,
        )
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
