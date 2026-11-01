import importlib.util
import json
import pathlib
import unittest

HERE = pathlib.Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("oda", HERE.parent / "obs_desktop_audio.py")
assert spec is not None and spec.loader is not None
oda = importlib.util.module_from_spec(spec)
spec.loader.exec_module(oda)

SINK = "obs-desktop"
ELEMENT = {"media.name": "^Element Call"}


def node(nid, **props):
    return {"id": nid, "type": "PipeWire:Interface:Node", "info": {"props": props}}


def stream(nid, media="song", **props):
    return node(nid, **{"media.class": "Stream/Output/Audio", "media.name": media, "node.name": f"s{nid}", **props})


def port(pid, nid, direction, channel):
    return {
        "id": pid,
        "type": "PipeWire:Interface:Port",
        "info": {"direction": direction, "props": {"node.id": nid, "audio.channel": channel}},
    }


def link(lid, out_node, out_port, in_node, in_port):
    return {
        "id": lid,
        "type": "PipeWire:Interface:Link",
        "info": {
            "output-node-id": out_node, "output-port-id": out_port,
            "input-node-id": in_node, "input-port-id": in_port,
        },
    }


def base_graph(*objects):
    """A sink (node 1, ports 10/11), a speaker sink (node 2, ports 20/21), plus objects."""
    g = oda.Graph()
    g.apply([
        node(1, **{"node.name": SINK, "media.class": "Audio/Sink"}),
        port(10, 1, "input", "FL"), port(11, 1, "input", "FR"),
        node(2, **{"node.name": "speakers", "media.class": "Audio/Sink"}),
        port(20, 2, "input", "FL"), port(21, 2, "input", "FR"),
        *objects,
    ])
    return g


def playing(nid, media="song", **props):
    """A stereo stream already linked to the speakers, as the session manager leaves it."""
    base = nid * 100
    return [
        stream(nid, media, **props),
        port(base + 1, nid, "output", "FL"), port(base + 2, nid, "output", "FR"),
        link(base + 3, nid, base + 1, 2, 20), link(base + 4, nid, base + 2, 2, 21),
    ]


class MatchTests(unittest.TestCase):
    def test_every_property_in_a_rule_must_match(self):
        props = {"media.name": "Element Call | General", "application.name": "Zen"}
        self.assertTrue(oda.matches(props, {"media.name": "^Element Call", "application.name": "^Zen$"}))
        self.assertFalse(oda.matches(props, {"media.name": "^Element Call", "application.name": "^Chrome$"}))

    def test_an_empty_rule_matches_nothing(self):
        self.assertFalse(oda.matches({"media.name": "x"}, {}))

    def test_missing_property_does_not_match(self):
        self.assertFalse(oda.matches({}, {"media.name": "x"}))

    def test_builtins_skip_the_binaural_output_and_obs(self):
        self.assertTrue(oda.excluded({"node.name": "effect_output.binaural71"}, []))
        self.assertTrue(oda.excluded({"application.process.binary": ".obs-wrapped"}, []))
        self.assertTrue(oda.excluded({"application.process.binary": ".easyeffects-wrapped"}, []))
        self.assertFalse(oda.excluded({"application.process.binary": "zen"}, []))


class PlanTests(unittest.TestCase):
    def test_a_playing_stream_gets_a_link_per_channel(self):
        g = base_graph(*playing(5))
        p = oda.plan(g, SINK, [])
        self.assertEqual(p.add, ((501, 10), (502, 11)))
        self.assertEqual(p.remove, ())

    def test_a_matching_stream_is_left_out(self):
        g = base_graph(*playing(5, "Element Call | General 1"), *playing(6, "(1) video - YouTube"))
        p = oda.plan(g, SINK, [ELEMENT])
        self.assertEqual(p.add, ((601, 10), (602, 11)))

    def test_a_stream_nobody_has_linked_yet_is_waited_for(self):
        g = base_graph(stream(5), port(501, 5, "output", "FL"), port(502, 5, "output", "FR"))
        self.assertEqual(oda.plan(g, SINK, []).add, ())

    def test_a_retitled_stream_loses_its_link(self):
        g = base_graph(*playing(5, "Watch"))
        for pair in oda.plan(g, SINK, [ELEMENT]).add:
            g.apply([link(900 + pair[0], 5, pair[0], 1, pair[1])])
        self.assertEqual(oda.plan(g, SINK, [ELEMENT]), oda.Plan(add=(), remove=()))
        g.apply([node(5, **{"media.name": "Element Call | General 1"})])
        removed = oda.plan(g, SINK, [ELEMENT]).remove
        self.assertEqual(sorted(removed), [1401, 1402])

    def test_the_plan_is_empty_once_links_exist(self):
        g = base_graph(*playing(5))
        g.apply([link(801, 5, 501, 1, 10), link(802, 5, 502, 1, 11)])
        self.assertEqual(oda.plan(g, SINK, []), oda.Plan(add=(), remove=()))

    def test_mono_feeds_both_sides(self):
        g = base_graph(
            stream(5), port(501, 5, "output", "MONO"), link(503, 5, 501, 2, 20),
        )
        self.assertEqual(oda.plan(g, SINK, []).add, ((501, 10), (501, 11)))

    def test_surround_channels_without_a_target_are_dropped(self):
        g = base_graph(
            stream(5), port(501, 5, "output", "FL"), port(502, 5, "output", "RL"),
            link(503, 5, 501, 2, 20),
        )
        self.assertEqual(oda.plan(g, SINK, []).add, ((501, 10),))

    def test_no_sink_means_no_plan(self):
        g = oda.Graph()
        g.apply(playing(5))
        self.assertEqual(oda.plan(g, SINK, []), oda.Plan(add=(), remove=()))

    def test_a_removed_stream_forgets_its_ports(self):
        g = base_graph(*playing(5))
        g.apply([{"id": 5, "info": None}])
        self.assertNotIn(5, g.nodes)


class AttemptsTests(unittest.TestCase):
    def test_a_change_is_not_repeated_until_the_hold_passes(self):
        a = oda.Attempts(hold=2.0)
        self.assertTrue(a.due(("add", 1, 2), now=10.0))
        self.assertFalse(a.due(("add", 1, 2), now=11.0))
        self.assertTrue(a.due(("add", 1, 2), now=12.5))

    def test_different_changes_are_independent(self):
        a = oda.Attempts(hold=2.0)
        self.assertTrue(a.due(("add", 1, 2), now=10.0))
        self.assertTrue(a.due(("add", 1, 3), now=10.0))


class GraphTests(unittest.TestCase):
    def test_node_updates_merge_over_earlier_props(self):
        g = base_graph(stream(5, "old", **{"application.name": "Zen"}))
        g.apply([node(5, **{"media.name": "new"})])
        self.assertEqual(g.nodes[5]["media.name"], "new")
        self.assertEqual(g.nodes[5]["application.name"], "Zen")


class JsonStreamTests(unittest.TestCase):
    def test_each_pretty_printed_array_is_yielded_when_it_closes(self):
        first = json.dumps([{"id": 1, "props": {"a": [1, 2]}}], indent=2)
        second = json.dumps([{"id": 2}, {"id": 3}], indent=2)
        lines = (first + "\n" + second + "\n").splitlines(keepends=True)
        self.assertEqual(
            list(oda.json_arrays(lines)),
            [[{"id": 1, "props": {"a": [1, 2]}}], [{"id": 2}, {"id": 3}]],
        )

    def test_an_unfinished_array_is_not_yielded(self):
        self.assertEqual(list(oda.json_arrays(["[\n", "  {\n"])), [])


if __name__ == "__main__":
    unittest.main()
