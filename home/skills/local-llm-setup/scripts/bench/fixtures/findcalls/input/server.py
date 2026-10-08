import rates
from limiter import Limiter

DEFAULT_SPEC = "5/s"


def build():
    limiter = Limiter(DEFAULT_SPEC)
    burst = rates.parse_rate("50/s")
    return limiter, burst


def handler_for(spec):
    def handle(request):
        return rates.parse_rate(spec) * request
    return handle
