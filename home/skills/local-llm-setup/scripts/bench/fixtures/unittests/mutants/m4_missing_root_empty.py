import os

DEFAULT_SUFFIX = ".dev"


def scan(root, suffix=DEFAULT_SUFFIX):
    found = []
    for current, dirs, files in os.walk(root):
        dirs[:] = [d for d in dirs if not d.startswith(".")]
        for name in files:
            if name.endswith(suffix):
                relative = os.path.relpath(os.path.join(current, name), root)
                found.append(relative.replace(os.sep, "/"))
    return sorted(found)
