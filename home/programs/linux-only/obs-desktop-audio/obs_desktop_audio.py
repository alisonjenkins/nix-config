"""Copy desktop audio into one sink for OBS, minus the streams that match a rule.

OBS can only match a stream by its binary and app name, and every browser tab
shares those. A stream's media.name is the tab title, so this watches the
PipeWire graph and adds a link from each playing stream to a null sink OBS
records, skipping streams whose properties match an exclude rule. Streams keep
their normal links, so nothing is rerouted or changes what is heard.

Configuration is JSON in OBS_DESKTOP_AUDIO_CONFIG:
  {"sink": "obs-desktop", "exclude": [{"media.name": "^Element Call"}, ...]}
Each rule is a map of node property -> regex; a stream matches a rule when
every listed property matches (re.search) and is skipped from the sink.
"""
import json
import logging
import os
import re
import subprocess
import sys
import time
from dataclasses import dataclass, field
from typing import Iterable, Iterator

log = logging.getLogger("obs-desktop-audio")

PW_DUMP = os.environ.get("OBS_DESKTOP_AUDIO_PW_DUMP", "pw-dump")
PW_LINK = os.environ.get("OBS_DESKTOP_AUDIO_PW_LINK", "pw-link")
PACTL = os.environ.get("OBS_DESKTOP_AUDIO_PACTL", "pactl")

# Streams that carry a mix of other streams or are not desktop audio. Linking
# them would put excluded audio back into the recording.
BUILTIN_EXCLUDES = (
    {"node.name": r"^effect_output\."},
    {"application.process.binary": r"^\.?easyeffects"},
    {"application.process.binary": r"^\.?obs"},
)

STREAM_CLASS = "Stream/Output/Audio"
MONO_TARGETS = ("FL", "FR")


@dataclass
class Port:
    id: int
    node: int
    direction: str
    channel: str


@dataclass
class Link:
    id: int
    out_node: int
    out_port: int
    in_node: int
    in_port: int


@dataclass
class Graph:
    nodes: dict[int, dict[str, object]] = field(default_factory=dict)
    ports: dict[int, Port] = field(default_factory=dict)
    links: dict[int, Link] = field(default_factory=dict)

    def apply(self, objects: Iterable[dict]) -> None:
        for obj in objects:
            self._apply_one(obj)

    def _apply_one(self, obj: dict) -> None:
        oid = obj.get("id")
        kind = obj.get("type", "")
        if oid is None:
            return
        info = obj.get("info")
        if info is None and "type" not in obj:
            # A removal carries only the id, so drop it from every table.
            self.nodes.pop(oid, None)
            self.ports.pop(oid, None)
            self.links.pop(oid, None)
            return
        if info is None:
            self._apply_removed(oid, kind)
            return
        if kind.endswith(":Node"):
            props = info.get("props", {})
            # An update carries only changed props; merge over what we hold.
            self.nodes[oid] = {**self.nodes.get(oid, {}), **props}
        elif kind.endswith(":Port"):
            props = info.get("props", {})
            direction = info.get("direction") or props.get("port.direction", "")
            previous = self.ports.get(oid)
            self.ports[oid] = Port(
                id=oid,
                node=props.get("node.id", previous.node if previous else -1),
                direction="out" if direction in ("output", "out") else "in",
                channel=props.get("audio.channel", previous.channel if previous else ""),
            )
        elif kind.endswith(":Link"):
            self.links[oid] = Link(
                id=oid,
                out_node=info["output-node-id"],
                out_port=info["output-port-id"],
                in_node=info["input-node-id"],
                in_port=info["input-port-id"],
            )

    def _apply_removed(self, oid: int, kind: str) -> None:
        if kind.endswith(":Node"):
            self.nodes.pop(oid, None)
        elif kind.endswith(":Port"):
            self.ports.pop(oid, None)
        elif kind.endswith(":Link"):
            self.links.pop(oid, None)


def matches(props: dict, rule: dict[str, str]) -> bool:
    """True when every property in the rule matches; an empty rule matches nothing."""
    if not rule:
        return False
    return all(re.search(pattern, str(props.get(key, ""))) for key, pattern in rule.items())


def excluded(props: dict, rules: Iterable[dict[str, str]]) -> bool:
    return any(matches(props, rule) for rule in (*BUILTIN_EXCLUDES, *rules))


def sink_node(graph: Graph, sink: str) -> int | None:
    for nid, props in graph.nodes.items():
        if props.get("node.name") == sink:
            return nid
    return None


def wanted_sources(graph: Graph, sink_id: int, rules: list[dict[str, str]]) -> set[int]:
    """Stream nodes that should feed the sink.

    A stream only counts once something else has linked it: the session
    manager decides a fresh stream's target from its own links, and a link
    from us arriving first could leave the stream unconnected to the speakers.
    """
    linked = {link.out_node for link in graph.links.values() if link.in_node != sink_id}
    wanted = set()
    for nid, props in graph.nodes.items():
        if props.get("media.class") != STREAM_CLASS or nid not in linked:
            continue
        if not excluded(props, rules):
            wanted.add(nid)
    return wanted


@dataclass(frozen=True)
class Plan:
    add: tuple[tuple[int, int], ...]
    remove: tuple[int, ...]


def plan(graph: Graph, sink: str, rules: list[dict[str, str]]) -> Plan:
    sink_id = sink_node(graph, sink)
    if sink_id is None:
        return Plan(add=(), remove=())
    inputs = {p.channel: p.id for p in graph.ports.values() if p.node == sink_id and p.direction == "in"}
    sources = wanted_sources(graph, sink_id, rules)

    desired: set[tuple[int, int]] = set()
    for port in graph.ports.values():
        if port.node not in sources or port.direction != "out":
            continue
        targets = MONO_TARGETS if port.channel == "MONO" else (port.channel,)
        for channel in targets:
            if channel in inputs:
                desired.add((port.id, inputs[channel]))

    existing = {
        (link.out_port, link.in_port): link.id
        for link in graph.links.values()
        if link.in_node == sink_id
    }
    add = tuple(sorted(desired - existing.keys()))
    remove = tuple(sorted(lid for pair, lid in existing.items() if pair not in desired))
    return Plan(add=add, remove=remove)


class Attempts:
    """Remembers what was just asked of PipeWire.

    A link takes a moment to show up in the monitor, and every event in that
    gap re-plans the same change. Without this each one would be retried.
    """

    def __init__(self, hold: float = 2.0) -> None:
        self.hold = hold
        self.seen: dict[object, float] = {}

    def due(self, key: object, now: float) -> bool:
        if now - self.seen.get(key, -self.hold) < self.hold:
            return False
        self.seen[key] = now
        return True


def apply_plan(p: Plan, attempts: Attempts, now: float) -> None:
    for out_port, in_port in p.add:
        if attempts.due(("add", out_port, in_port), now):
            run_link([str(out_port), str(in_port)])
    for link_id in p.remove:
        if attempts.due(("remove", link_id), now):
            run_link(["-d", str(link_id)])


def run_link(args: list[str]) -> None:
    result = subprocess.run([PW_LINK, *args], capture_output=True, text=True, check=False)
    # A port that vanished between planning and linking is routine churn.
    if result.returncode != 0:
        log.warning("pw-link %s failed: %s", " ".join(args), result.stderr.strip())
    else:
        log.info("pw-link %s", " ".join(args))


def ensure_sink(sink: str) -> None:
    listed = subprocess.run([PACTL, "list", "short", "sinks"], capture_output=True, text=True, check=True)
    if any(line.split("\t")[1:2] == [sink] for line in listed.stdout.splitlines()):
        return
    subprocess.run(
        [
            PACTL, "load-module", "module-null-sink",
            f"sink_name={sink}",
            "channels=2",
            "channel_map=front-left,front-right",
            "sink_properties=device.description=OBS-Desktop-Audio priority.session=1",
        ],
        check=True,
    )
    log.info("created sink %s", sink)


def json_arrays(lines: Iterable[str]) -> Iterator[list]:
    """Yield each top-level JSON array from pw-dump's pretty-printed output.

    pw-dump closes every array with a "]" alone on a line at column 0
    (nested ones are indented), so that line ends a document. Parsing only
    there keeps the cost linear; retrying a parse on every line is quadratic
    on the multi-megabyte first dump.
    """
    buffer: list[str] = []
    for line in lines:
        buffer.append(line)
        if line.rstrip("\n") == "]":
            yield json.loads("".join(buffer))
            buffer = []


def watch(sink: str, rules: list[dict[str, str]]) -> None:
    ensure_sink(sink)
    graph = Graph()
    attempts = Attempts()
    proc = subprocess.Popen([PW_DUMP, "--monitor"], stdout=subprocess.PIPE, text=True)
    stdout = proc.stdout
    assert stdout is not None
    # Line at a time: a fixed-size read would block until the buffer filled,
    # and the monitor only prints when something changes.
    for objects in json_arrays(stdout):
        graph.apply(objects)
        apply_plan(plan(graph, sink, rules), attempts, time.monotonic())
    raise RuntimeError(f"{PW_DUMP} exited with {proc.wait()}")


def load_config() -> tuple[str, list[dict[str, str]]]:
    raw = os.environ.get("OBS_DESKTOP_AUDIO_CONFIG")
    if not raw:
        raise SystemExit("OBS_DESKTOP_AUDIO_CONFIG is not set")
    config = json.loads(raw)
    return config["sink"], config.get("exclude", [])


def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
    sink, rules = load_config()
    for rule in rules:
        for pattern in rule.values():
            re.compile(pattern)  # fail at start on a bad pattern, not mid-call
    watch(sink, rules)


if __name__ == "__main__":
    sys.exit(main())
