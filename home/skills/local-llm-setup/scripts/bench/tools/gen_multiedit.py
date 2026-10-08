"""Deterministically generate the multiedit fixture (input, solution, edits.md)."""
import sys
from pathlib import Path

NAMES = [
    "alpha", "beta", "gamma", "delta", "epsilon", "zeta", "eta", "theta",
    "iota", "kappa", "lambda", "mu", "nu", "xi", "omicron", "pi", "rho",
    "sigma", "tau", "upsilon", "phi", "chi", "psi", "omega", "ember", "flint",
    "grove", "harbor", "isle", "jade", "kestrel", "lagoon", "meadow", "nectar",
    "onyx", "prism", "quartz", "raven",
]
HEADER = '''import unittest


class Config:
    def __init__(self, name, retries, timeout, verbose, tags):
        self.name = name
        self.retries = retries
        self.timeout = timeout
        self.verbose = verbose
        self.tags = tags

    def describe(self):
        return f"{self.name}:{self.retries}:{self.timeout}"


'''


def values_for(index, name):
    return {
        "retries": 1 + index % 5,
        "timeout": 10 + 5 * (index % 7),
        "verbose": index % 2 == 0,
        "tags": [name[0]],
    }


def helper_source(index, name):
    v = values_for(index, name)
    tags = "[" + ", ".join(f'"{t}"' for t in v["tags"]) + "]"
    return (
        f"def make_config_{name}(**overrides):\n"
        f'    values = {{"name": "{name}", "retries": {v["retries"]}, "timeout": {v["timeout"]}, '
        f'"verbose": {v["verbose"]}, "tags": {tags}}}\n'
        f"    values.update(overrides)\n"
        f"    return Config(**values)\n"
    )


def tests_source(index, name):
    v = values_for(index, name)
    return (
        f"    def test_{name}_retries(self):\n"
        f"        cfg = make_config_{name}()\n"
        f"        self.assertEqual(cfg.retries, {v['retries']})\n"
        f"\n"
        f"    def test_{name}_timeout(self):\n"
        f"        cfg = make_config_{name}()\n"
        f"        self.assertEqual(cfg.timeout, {v['timeout']})\n"
        f"\n"
        f"    def test_{name}_describe(self):\n"
        f"        cfg = make_config_{name}()\n"
        f'        self.assertEqual(cfg.describe(), "{name}:{v["retries"]}:{v["timeout"]}")\n'
    )


def build_input():
    parts = [HEADER]
    for index, name in enumerate(NAMES):
        parts.append(helper_source(index, name) + "\n\n")
    parts.append("class ConfigTests(unittest.TestCase):\n")
    blocks = [tests_source(index, name) for index, name in enumerate(NAMES)]
    parts.append("\n".join(blocks))
    parts.append('\n\nif __name__ == "__main__":\n    unittest.main()\n')
    return "".join(parts)


def edit(source, old, new):
    if source.count(old) != 1:
        raise SystemExit(f"edit anchor not unique: {old!r}")
    return source.replace(old, new)


def edit_list():
    delta = NAMES.index("delta")
    kappa = NAMES.index("kappa")
    sigma = NAMES.index("sigma")
    dv = values_for(delta, "delta")
    sv = values_for(sigma, "sigma")
    new_retries = 9
    beta_new = (
        "    def test_beta_overrides(self):\n"
        "        cfg = make_config_beta(retries=9)\n"
        "        self.assertEqual(cfg.retries, 9)\n"
    )
    gamma_new = (
        "    def test_gamma_verbose_override(self):\n"
        "        cfg = make_config_gamma(verbose=True)\n"
        "        self.assertTrue(cfg.verbose)\n"
    )
    omega_new = (
        "    def test_omega_tags_override(self):\n"
        "        cfg = make_config_omega(tags=[])\n"
        "        self.assertEqual(cfg.tags, [])\n"
    )
    return [
        {
            "text": 'In the helper `make_config_delta`, change the value `"retries": %d` to `"retries": %d`.'
            % (dv["retries"], new_retries),
            "old": f'"name": "delta", "retries": {dv["retries"]},',
            "new": f'"name": "delta", "retries": {new_retries},',
        },
        {
            "text": 'In the helper `make_config_kappa`, change `"tags": ["k"]` to `"tags": ["k", "kappa"]`.',
            "old": f'"name": "kappa", "retries": {values_for(kappa, "kappa")["retries"]}, '
            f'"timeout": {values_for(kappa, "kappa")["timeout"]}, '
            f'"verbose": {values_for(kappa, "kappa")["verbose"]}, "tags": ["k"]}}',
            "new": f'"name": "kappa", "retries": {values_for(kappa, "kappa")["retries"]}, '
            f'"timeout": {values_for(kappa, "kappa")["timeout"]}, '
            f'"verbose": {values_for(kappa, "kappa")["verbose"]}, "tags": ["k", "kappa"]}}',
        },
        {
            "text": "In `test_delta_retries`, change the assertion to `self.assertEqual(cfg.retries, %d)`." % new_retries,
            "old": f"        cfg = make_config_delta()\n        self.assertEqual(cfg.retries, {dv['retries']})\n",
            "new": f"        cfg = make_config_delta()\n        self.assertEqual(cfg.retries, {new_retries})\n",
        },
        {
            "text": 'In `test_delta_describe`, change the expected string to `"delta:%d:%d"`.' % (new_retries, dv["timeout"]),
            "old": f'"delta:{dv["retries"]}:{dv["timeout"]}"',
            "new": f'"delta:{new_retries}:{dv["timeout"]}"',
        },
        {
            "text": "In `test_sigma_timeout`, change `self.assertEqual(cfg.timeout, %d)` to `self.assertGreaterEqual(cfg.timeout, %d)`."
            % (sv["timeout"], sv["timeout"]),
            "old": f"        cfg = make_config_sigma()\n        self.assertEqual(cfg.timeout, {sv['timeout']})\n",
            "new": f"        cfg = make_config_sigma()\n        self.assertGreaterEqual(cfg.timeout, {sv['timeout']})\n",
        },
        {
            "text": "Add this test to `ConfigTests` directly after `test_beta_describe`, with one blank line between methods:\n\n```\n%s```" % beta_new,
            "after": "beta",
            "added": beta_new,
        },
        {
            "text": "Add this test to `ConfigTests` directly after `test_gamma_describe`, with one blank line between methods:\n\n```\n%s```" % gamma_new,
            "after": "gamma",
            "added": gamma_new,
        },
        {
            "text": "Add this test to `ConfigTests` directly after `test_omega_describe`, with one blank line between methods:\n\n```\n%s```" % omega_new,
            "after": "omega",
            "added": omega_new,
        },
    ]


def apply_edits(source, edits):
    for item in edits:
        if "old" in item:
            source = edit(source, item["old"], item["new"])
        else:
            index = NAMES.index(item["after"])
            anchor = tests_source(index, item["after"]).split("\n\n")[-1]
            source = edit(source, anchor, anchor + "\n" + item["added"])
    return source


def edits_markdown(edits):
    lines = ["# Edits to apply to test_registry.py", "", "Apply all eight edits. Change nothing else.", ""]
    for number, item in enumerate(edits, start=1):
        lines.append(f"{number}. {item['text']}")
        lines.append("")
    return "\n".join(lines)


def main():
    fixture = Path(sys.argv[1])
    source = build_input()
    edits = edit_list()
    (fixture / "input").mkdir(parents=True, exist_ok=True)
    (fixture / "solution").mkdir(parents=True, exist_ok=True)
    (fixture / "input" / "test_registry.py").write_text(source, encoding="utf-8")
    (fixture / "input" / "edits.md").write_text(edits_markdown(edits), encoding="utf-8")
    (fixture / "solution" / "test_registry.py").write_text(apply_edits(source, edits), encoding="utf-8")
    print(f"{source.count(chr(10))} lines")


if __name__ == "__main__":
    main()
