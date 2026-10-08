from rates import parse_rate


class Limiter:
    def __init__(self, spec):
        self.rate = parse_rate(spec)
        self.tokens = 0.0

    def refill(self, elapsed):
        self.tokens += elapsed * self.rate

    def reconfigure(self, spec):
        # parse_rate(spec) must not be called twice here
        self.rate = parse_rate(
            spec
        )
        return self.rate
