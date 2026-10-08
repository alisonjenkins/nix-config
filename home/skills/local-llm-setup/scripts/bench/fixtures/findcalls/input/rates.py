import re

RATE_PATTERN = re.compile(r"^(\d+(?:\.\d+)?)/(s|m|h)$")
UNIT_SECONDS = {"s": 1, "m": 60, "h": 3600}


def parse_rate(text):
    match = RATE_PATTERN.match(text.strip())
    if match is None:
        raise ValueError(f"bad rate: {text!r}")
    return float(match.group(1)) / UNIT_SECONDS[match.group(2)]


def parse_rate_limit(text):
    return min(parse_rate(text), 1000.0)


def default_rate():
    return parse_rate("10/m")
