import os

DEFAULT_SUFFIX = ".dev"


def scan(root, suffix=DEFAULT_SUFFIX):
    if not os.path.isdir(root):
        raise FileNotFoundError(f"scan root does not exist: {root}")
    found = []
    for current, dirs, files in os.walk(root):
        for name in files:
            if name.endswith(suffix):
                relative = os.path.relpath(os.path.join(current, name), root)
                found.append(relative.replace(os.sep, "/"))
    return sorted(found)
