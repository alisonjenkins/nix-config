def parse_rates(specs):
    return [parse_rate_text(s) for s in specs]


def parse_rate_text(spec):
    return spec.strip()
