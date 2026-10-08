# keystate.py specification

Create a new file `keystate.py` in this directory, standard library only.
It must satisfy all six requirements.

1. Define `class KeyState`. Its constructor takes no arguments. Each
   instance has its own set of pressed keys; two instances never share
   state.
2. `KeyState.press(key)` marks a key as pressed. Pressing a key that is
   already pressed changes nothing. `KeyState.release(key)` marks it as not
   pressed. Releasing a key that is not pressed changes nothing and raises
   nothing.
3. `KeyState.pressed()` returns a new `list` of the pressed keys in plain
   ascending string order (`sorted`). Changing the returned list never
   changes the state.
4. Copy the function `mix` from `reference.py` into `keystate.py` as a
   module-level function with the same name, the same constants and the
   same behaviour. Copy it; do not import `reference`, because `keystate.py`
   is shipped on its own.
5. `KeyState.fingerprint()` returns an integer. Start with `h = 0`. For each
   pressed key in the order returned by `pressed()`, set
   `h = mix(h + sum(ord(c) for c in key))`. Return `h`. With no pressed keys
   it returns `0`.
6. `press(key)` and `release(key)` raise `ValueError` when `key` is not a
   `str` or is the empty string. A rejected call changes nothing.
