import sys

from rates import parse_rate


def main(argv):
    values = list(map(parse_rate, argv))
    first = parse_rate(argv[0]) if argv else None
    print(values, first)
    return 0


def nested(text):
    return parse_rate(str(parse_rate(text)) + "/s")


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
