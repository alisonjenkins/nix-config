import json
import sys
from pathlib import Path

module_dir, reference_dir = sys.argv[1], sys.argv[2]
sys.path.insert(0, module_dir)
sys.path.insert(1, reference_dir)

import reference  # noqa: E402

CHECKS = {}


def check(name):
    def register(fn):
        CHECKS[name] = fn
        return fn

    return register


def raises_value_error(call, *args):
    try:
        call(*args)
    except ValueError:
        return True
    except Exception:
        return False
    return False


@check("R1")
def r1(keystate):
    first = keystate.KeyState()
    second = keystate.KeyState()
    first.press("a")
    return second.pressed() == [] and first.pressed() == ["a"]


@check("R2")
def r2(keystate):
    state = keystate.KeyState()
    state.press("x")
    state.press("x")
    state.press("y")
    if state.pressed() != ["x", "y"]:
        return False
    state.release("x")
    state.release("never-pressed")
    return state.pressed() == ["y"]


@check("R3")
def r3(keystate):
    state = keystate.KeyState()
    for key in ["b", "a", "C", "a1", "_"]:
        state.press(key)
    got = state.pressed()
    if type(got) is not list or got != sorted(["b", "a", "C", "a1", "_"]):
        return False
    got.append("zzz")
    return "zzz" not in state.pressed()


@check("R4")
def r4(keystate):
    mix = getattr(keystate, "mix", None)
    if mix is None:
        return False
    samples = [0, 1, 2, 12345, 2**32 - 1, 2**40 + 7]
    return all(mix(v) == reference.mix(v) for v in samples)


@check("R5")
def r5(keystate):
    state = keystate.KeyState()
    if state.fingerprint() != 0:
        return False
    for key in ["beta", "alpha", "Zed"]:
        state.press(key)
    expected = 0
    for key in sorted(["beta", "alpha", "Zed"]):
        expected = reference.mix(expected + sum(ord(c) for c in key))
    other = keystate.KeyState()
    for key in ["Zed", "alpha", "beta"]:
        other.press(key)
    return state.fingerprint() == expected and other.fingerprint() == expected


@check("R6")
def r6(keystate):
    state = keystate.KeyState()
    state.press("ok")
    bad_keys = ["", 3, None, b"x"]
    for bad in bad_keys:
        if not raises_value_error(state.press, bad):
            return False
        if not raises_value_error(state.release, bad):
            return False
    return state.pressed() == ["ok"]


def main():
    try:
        import keystate
    except Exception as exc:
        print(json.dumps({"import_error": f"{type(exc).__name__}: {exc}"}))
        return
    outcome = {}
    for name, fn in CHECKS.items():
        try:
            outcome[name] = bool(fn(keystate))
        except Exception:
            outcome[name] = False
    print(json.dumps(outcome))


if __name__ == "__main__":
    main()
