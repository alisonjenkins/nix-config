SEED = 0x5A17C3
MULTIPLIER = 0x9E3779B1
ROUNDS = 7
WORD_MASK = 0xFFFFFFFF
SHIFT = 13


def mix(value):
    state = SEED ^ (value & WORD_MASK)
    for _ in range(ROUNDS):
        state = ((state * MULTIPLIER) ^ (state >> SHIFT)) & WORD_MASK
    return state


def _check_key(key):
    if not isinstance(key, str) or key == "":
        raise ValueError(f"key must be a non-empty str, got {key!r}")


class KeyState:
    def __init__(self):
        self._pressed = set()

    def press(self, key):
        _check_key(key)
        self._pressed.add(key)

    def release(self, key):
        _check_key(key)
        self._pressed.discard(key)

    def pressed(self):
        return sorted(self._pressed)

    def fingerprint(self):
        h = 0
        for key in self.pressed():
            h = mix(h + sum(ord(c) for c in key))
        return h
