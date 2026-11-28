"""Run: python3 -m unittest discover -s scripts/tests   (from the skill directory)"""

import importlib.util
import struct
import tempfile
import unittest
import zipfile
from pathlib import Path

_spec = importlib.util.spec_from_file_location(
    "check_model", Path(__file__).resolve().parent.parent / "check-model.py"
)
assert _spec and _spec.loader
cm = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(cm)

Point = tuple[float, float, float]
Solid = list[tuple[Point, Point, Point]]
NS = "http://schemas.microsoft.com/3dmanufacturing/core/2015/02"


def tetra(dx: float) -> Solid:
    a, b, c, d = (dx, 0, 0), (dx + 1, 0, 0), (dx, 1, 0), (dx, 0, 1)
    return [(a, b, c), (a, b, d), (a, c, d), (b, c, d)]


def write_3mf(path: Path, solids: list[Solid]) -> None:
    verts: list[Point] = []
    tris: list[tuple[int, int, int]] = []
    for solid in solids:
        for tri in solid:
            idx = []
            for v in tri:
                verts.append(v)  # deliberately not de-duplicated, like some exporters
                idx.append(len(verts) - 1)
            tris.append((idx[0], idx[1], idx[2]))
    vx = "".join(f'<vertex x="{x}" y="{y}" z="{z}"/>' for x, y, z in verts)
    tx = "".join(f'<triangle v1="{a}" v2="{b}" v3="{c}"/>' for a, b, c in tris)
    xml = (
        f'<model xmlns="{NS}"><resources><object id="1"><mesh><vertices>{vx}</vertices>'
        f"<triangles>{tx}</triangles></mesh></object></resources></model>"
    )
    with zipfile.ZipFile(path, "w") as z:
        z.writestr("3D/3dmodel.model", xml)


def write_binary_stl(path: Path, tris: Solid) -> None:
    body = b"".join(
        struct.pack("<12fH", 0, 0, 0, *[c for v in t for c in v], 0) for t in tris
    )
    path.write_bytes(b"\0" * 80 + struct.pack("<I", len(tris)) + body)


PROD = "http://schemas.microsoft.com/3dmanufacturing/production/2015/06"


def mesh_xml(solid: Solid) -> str:
    verts: list[Point] = []
    tris: list[tuple[int, int, int]] = []
    for tri in solid:
        idx = []
        for v in tri:
            verts.append(v)
            idx.append(len(verts) - 1)
        tris.append((idx[0], idx[1], idx[2]))
    vx = "".join(f'<vertex x="{x}" y="{y}" z="{z}"/>' for x, y, z in verts)
    tx = "".join(f'<triangle v1="{a}" v2="{b}" v3="{c}"/>' for a, b, c in tris)
    return f"<mesh><vertices>{vx}</vertices><triangles>{tx}</triangles></mesh>"


def write_qidi_3mf(
    path: Path, solids: list[Solid], offsets: list[tuple[float, float, float]]
) -> None:
    """Qidi Studio layout: meshes in 3D/Objects/*.model, wrapper objects with a
    component reference, and one build item per solid carrying its placement."""
    resources, items, files = "", "", {}
    for i, (solid, (dx, dy, dz)) in enumerate(zip(solids, offsets), start=1):
        files[f"3D/Objects/object_{i}.model"] = (
            f'<model xmlns="{NS}" xmlns:p="{PROD}"><resources>'
            f'<object id="1" type="model">{mesh_xml(solid)}</object></resources></model>'
        )
        resources += (
            f'<object id="{10 + i}" type="model"><components>'
            f'<component p:path="/3D/Objects/object_{i}.model" objectid="1" '
            f'transform="1 0 0 0 1 0 0 0 1 0 0 0"/></components></object>'
        )
        items += (
            f'<item objectid="{10 + i}" transform="1 0 0 0 1 0 0 0 1 {dx} {dy} {dz}"/>'
        )
    main = (
        f'<model xmlns="{NS}" xmlns:p="{PROD}"><resources>{resources}</resources>'
        f"<build>{items}</build></model>"
    )
    with zipfile.ZipFile(path, "w") as z:
        z.writestr("3D/3dmodel.model", main)
        for name, text in files.items():
            z.writestr(name, text)


class CheckModel(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self._tmp.name)

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def test_joined_solid_passes(self) -> None:
        p = self.dir / "one.3mf"
        write_3mf(p, [tetra(0)])
        self.assertEqual(cm.main([str(p)]), 0)

    def test_two_separate_solids_fail(self) -> None:
        p = self.dir / "two.3mf"
        write_3mf(p, [tetra(0), tetra(10)])
        self.assertEqual(cm.main([str(p)]), 1)

    def test_two_solids_pass_when_two_are_expected(self) -> None:
        p = self.dir / "two.3mf"
        write_3mf(p, [tetra(0), tetra(10)])
        self.assertEqual(cm.main([str(p), "--parts", "2"]), 0)

    def test_solids_sharing_a_vertex_are_one_piece(self) -> None:
        p = self.dir / "touch.3mf"
        write_3mf(p, [tetra(0), tetra(1)])  # second starts where the first ends
        self.assertEqual(cm.main([str(p)]), 0)

    def test_binary_stl_is_read(self) -> None:
        p = self.dir / "two.stl"
        write_binary_stl(p, tetra(0) + tetra(10))
        self.assertEqual(cm.main([str(p)]), 1)
        self.assertEqual(cm.main([str(p), "--parts", "2"]), 0)

    def test_ascii_stl_is_read(self) -> None:
        p = self.dir / "one.stl"
        lines = ["solid s"]
        for tri in tetra(0):
            lines += ["facet normal 0 0 0", "outer loop"]
            lines += [f"vertex {x} {y} {z}" for x, y, z in tri]
            lines += ["endloop", "endfacet"]
        lines.append("endsolid s")
        p.write_text("\n".join(lines))
        self.assertEqual(cm.main([str(p)]), 0)

    def test_unreadable_input_is_exit_2(self) -> None:
        p = self.dir / "bad.3mf"
        p.write_text("not a zip")
        self.assertEqual(cm.main([str(p)]), 2)
        self.assertEqual(cm.main([str(self.dir / "missing.stl")]), 2)

    def test_unknown_extension_is_exit_2(self) -> None:
        p = self.dir / "m.obj"
        p.write_text("v 0 0 0")
        self.assertEqual(cm.main([str(p)]), 2)

    def test_qidi_studio_3mf_with_object_files_is_read(self) -> None:
        p = self.dir / "qidi.3mf"
        write_qidi_3mf(p, [tetra(0)], [(195, 195, 15)])
        self.assertEqual(cm.main([str(p)]), 0)

    def test_build_placement_separates_objects_that_share_local_coordinates(
        self,
    ) -> None:
        # Both solids sit at the origin in their own file; only the build
        # transforms move them apart. Ignoring transforms would merge them.
        p = self.dir / "plate.3mf"
        write_qidi_3mf(p, [tetra(0), tetra(0)], [(0, 0, 0), (50, 0, 0)])
        self.assertEqual(cm.main([str(p)]), 1)
        self.assertEqual(cm.main([str(p), "--parts", "2"]), 0)

    def test_touching_build_items_are_still_separate_pieces(self) -> None:
        # The slicer rearranges build items (--arrange), so two items that
        # touch in the file do not stay joined on the plate.
        p = self.dir / "join.3mf"
        write_qidi_3mf(
            p, [tetra(0), tetra(10)], [(0, 0, 0), (-9, 0, 0)]
        )  # second lands on x=1
        self.assertEqual(cm.main([str(p)]), 1)
        self.assertEqual(cm.main([str(p), "--parts", "2"]), 0)

    def test_item_can_reference_an_object_in_another_file_directly(self) -> None:
        p = self.dir / "direct.3mf"
        other = (
            f'<model xmlns="{NS}"><resources><object id="1" type="model">'
            f"{mesh_xml(tetra(0))}</object></resources></model>"
        )
        main = (
            f'<model xmlns="{NS}" xmlns:p="{PROD}"><resources/><build>'
            '<item objectid="1" p:path="/3D/Objects/object_1.model"/></build></model>'
        )
        with zipfile.ZipFile(p, "w") as z:
            z.writestr("3D/3dmodel.model", main)
            z.writestr("3D/Objects/object_1.model", other)
        self.assertEqual(cm.main([str(p)]), 0)

    def test_units_are_converted_to_millimetres(self) -> None:
        p = self.dir / "inch.3mf"
        main = (
            f'<model unit="inch" xmlns="{NS}"><resources><object id="1">{mesh_xml(tetra(0))}'
            '</object></resources><build><item objectid="1"/></build></model>'
        )
        with zipfile.ZipFile(p, "w") as z:
            z.writestr("3D/3dmodel.model", main)
        lo, hi = cm.bounding_box(cm.read_triangles(p))
        self.assertAlmostEqual(hi[0] - lo[0], 25.4, places=3)

    def test_unknown_unit_is_unreadable(self) -> None:
        p = self.dir / "furlong.3mf"
        main = (
            f'<model unit="furlong" xmlns="{NS}"><resources><object id="1">{mesh_xml(tetra(0))}'
            '</object></resources><build><item objectid="1"/></build></model>'
        )
        with zipfile.ZipFile(p, "w") as z:
            z.writestr("3D/3dmodel.model", main)
        self.assertEqual(cm.main([str(p)]), 2)

    def test_nested_component_without_path_uses_same_file(self) -> None:
        p = self.dir / "nested.3mf"
        main = (
            f'<model xmlns="{NS}"><resources>'
            f'<object id="1">{mesh_xml(tetra(0))}</object>'
            '<object id="2"><components><component objectid="1" transform="1 0 0 0 1 0 0 0 1 0 0 0"/>'
            '<component objectid="1" transform="1 0 0 0 1 0 0 0 1 20 0 0"/></components></object>'
            '</resources><build><item objectid="2"/></build></model>'
        )
        with zipfile.ZipFile(p, "w") as z:
            z.writestr("3D/3dmodel.model", main)
        self.assertEqual(cm.main([str(p)]), 1)

    def test_unreadable_is_not_the_same_as_wrong_piece_count(self) -> None:
        bad = self.dir / "bad.3mf"
        bad.write_text("nope")
        two = self.dir / "two.3mf"
        write_3mf(two, [tetra(0), tetra(10)])
        self.assertNotEqual(cm.main([str(bad)]), cm.main([str(two)]))

    def _two_objects(self, second_attrs: str, item_attrs: str) -> Path:
        p = self.dir / "extra.3mf"
        main = (
            f'<model xmlns="{NS}"><resources>'
            f'<object id="1" type="model">{mesh_xml(tetra(0))}</object>'
            f'<object id="2" {second_attrs}>{mesh_xml(tetra(30))}</object>'
            f'</resources><build><item objectid="1"/><item objectid="2" {item_attrs}/></build></model>'
        )
        with zipfile.ZipFile(p, "w") as z:
            z.writestr("3D/3dmodel.model", main)
        return p

    def test_unprintable_item_is_not_counted(self) -> None:
        p = self._two_objects('type="model"', 'printable="0"')
        self.assertEqual(cm.main([str(p)]), 0)

    def test_support_objects_are_not_counted(self) -> None:
        for kind in ("support", "solidsupport", "other"):
            with self.subTest(kind=kind):
                p = self._two_objects(f'type="{kind}"', "")
                self.assertEqual(cm.main([str(p)]), 0)

    def test_printable_second_model_object_still_counts(self) -> None:
        p = self._two_objects('type="model"', 'printable="1"')
        self.assertEqual(cm.main([str(p)]), 1)


if __name__ == "__main__":
    unittest.main()
