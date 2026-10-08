"""Assert on one grade.py JSON line read from stdin; exit 1 and say why if it does not hold."""
import argparse
import json
import sys


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--expect", choices=["pass", "not-full"], required=True)
    parser.add_argument("--label", required=True)
    parser.add_argument("--detail", action="append", default=[], metavar="KEY=VALUE")
    args = parser.parse_args()
    line = sys.stdin.read().strip().splitlines()[-1]
    grade = json.loads(line)
    problems = []
    if args.expect == "pass":
        if not grade["pass"] or grade["score"] != 1.0:
            problems.append("expected PASS with score 1.0")
    elif grade["pass"] and grade["score"] >= 1.0:
        problems.append("expected FAIL or score below 1.0")
    for item in args.detail:
        key, _, wanted = item.partition("=")
        if str(grade.get("details", {}).get(key)) != wanted:
            problems.append(f"details.{key} is {grade.get('details', {}).get(key)!r}, wanted {wanted}")
    verdict = "PASS" if grade["pass"] else "FAIL"
    status = "BAD" if problems else "ok "
    print(f"{status} {args.label:<22} {verdict} score={grade['score']:.2f} review={str(grade['needs_review']).lower()} {grade['reason'][:90]}")
    for problem in problems:
        print(f"    -> {problem}")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
