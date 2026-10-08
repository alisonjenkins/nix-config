import rates

DOC = "call parse_rate(text) to convert a spec"


def load(section):
    out = {}
    for key, value in section.items():
        out[key] = rates.parse_rate(value)
    return out


def load_one(section, key):
    return rates.parse_rate_limit(section[key])


def describe():
    return DOC
