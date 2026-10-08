"""Reference helpers copied between modules in this project."""

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


def unrelated_helper(text):
    return text.strip().lower()
