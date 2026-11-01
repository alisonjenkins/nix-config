# Project management skill Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the shared `project-management` skill: a stateless `pm` script with `github` and `local` backends, plus the docs a model loads on demand.

**Architecture:** `scripts/pm` is a dispatcher. It requires `-b <backend>` (case-sensitive alias or full name), then runs `scripts/backends/<name>/<verb>.sh`. All backends print the same eight-column TSV. Shared parsing lives in `scripts/lib/`. Spec: `docs/superpowers/specs/2026-10-21-project-management-skill-design.md`.

**Tech Stack:** bash (3.2 compatible, macOS), awk (POSIX), jq, `gh`, bats for tests.

## Global Constraints

- Bash 3.2 compatible: no associative arrays, no `mapfile`/`readarray`, no `${var,,}`. Guard possibly-empty arrays as `${arr[@]+"${arr[@]}"}` (set -u).
- Scripts are always run as `bash <script>` by the dispatcher and the tests. Never depend on a shebang resolving.
- No absolute machine paths in scripts (`lint-skills.sh` fails on `/home/<x>`, `/nix/store/...`, `/run/current-system`).
- Probe tools with `command -v` (`pm_need`). Never assume `gh`, `jq` exist.
- Times are ISO8601 UTC. `est` is integer minutes. `prio` is an integer, 1 highest.
- `list` rows are exactly 8 tab-separated fields: `id state title owner deps due est prio`. Empty = empty field.
- Line 1 of every verb output is `# backend=<full-name> k=v ...`.
- Mutations are dry-run unless `--apply`. `sync-plan` output lines are `action<TAB>kind<TAB>ref<TAB>detail` with action in `would-create|would-update|created|updated|exists|drift`.
- Aliases: one token matching `[A-Za-z]+`, case-sensitive. `g` = github, `l` = local.
- Commit messages: Conventional Commits, scope `project-management` (or `skills` for repo-level files). No `Co-Authored-By`, no "Generated with" footer (user mandate). One logical change per commit.
- Prose written for people follows the `writing` skill: front-load the point, no em dashes, sentence-case headings.

## Conventions used in this plan

Run every command from the worktree root. Tools come from nix, so define this in each shell call that needs it (shell state does not persist between calls):

```bash
T='nix shell nixpkgs#bats nixpkgs#jq nixpkgs#yq-go nixpkgs#shellcheck nixpkgs#gawk -c'
SK=home/skills/project-management
```

`$SK/scripts/tests` holds all bats files. "Run bats" means `$T bats $SK/scripts/tests/<file>.bats`.

Delegation: Tasks 3 to 9 are mechanical given the code below. Per the delegation skill, hand each task to a cheap worker (Gemini `write-workdir`, or a `haiku-worker`) with the task text verbatim, then review the diff and run the task's bats here.

## File structure

```text
home/skills/project-management/
  SKILL.md  triggers.json  tracking.md  breakdown.md  docs.md  github.md  local.md
  scripts/
    pm                          dispatcher
    lint-aliases.sh             alias lint for backends/*/alias
    lib/common.sh               die/need/header, backend table + resolution, URL routing, arg helper
    lib/tsv.sh                  pm_filter_tsv, pm_status_from_tsv, pm_row_to_kv
    lib/tasks-md.sh             speckit-style tasks.md parser and editor
    backends/local/             alias _local.sh list.sh status.sh show.sh update.sh sync-plan.sh
    backends/github/            alias _gh.sh rows.jq list.sh status.sh show.sh update.sh sync-plan.sh
    tests/                      helpers.bash fake-gh.sh *.bats
flake-modules/skills-project-management-tests.nix
docs/adr/0049-stateless-backend-selection-for-pm.md
```

---

### Task 0: Preflight

**Files:** none changed.

- [ ] **Step 1: Confirm the tools resolve and the baseline is green**

```bash
T='nix shell nixpkgs#bats nixpkgs#jq nixpkgs#yq-go nixpkgs#shellcheck nixpkgs#gawk -c'
$T bash -c 'bats --version && jq --version && yq --version && shellcheck --version | sed -n 2p'
$T bash home/skills/skill-authoring/scripts/lint-skills.sh home/skills
$T bash home/skills/skill-authoring/scripts/check-triggers.sh home/skills
```

Expected: tool versions print, then `all skills pass the convention lint` and a triggers pass line. If a baseline check already fails, stop and report it; do not fix unrelated skills here.

- [ ] **Step 2: Confirm the branch**

Run: `git branch --show-current` and `git status --short`
Expected: branch `worktree-quizzical-tinkering-liskov`, clean tree.

---

### Task 1: Amend the spec for two implementation decisions

Two things in the approved spec do not match what the plan builds. Fix the spec first so it stays the source of truth.

**Files:**
- Modify: `docs/superpowers/specs/2026-10-21-project-management-skill-design.md`

- [ ] **Step 1: Defer Projects v2**

In the `### github` section, replace the line

`- Issues, labels and milestones for tasks, with optional Projects v2 fields behind `-p <number>`.`

with

`- Issues, labels and milestones for tasks. Projects v2 fields are a follow-up (tracked in PENDING.md); v1 reads \`est\` and \`prio\` from labels and \`due\` from the milestone.`

and replace the line beginning `- \`due\` comes from the issue's milestone due date or a Projects v2 date field.` with

`- \`due\` comes from the issue's milestone due date. \`est\` and \`prio\` come from \`est:<minutes>\` and \`prio:<n>\` labels. Unset means an empty column.`

- [ ] **Step 2: Pin the read mechanism and the `--per-task` syntax**

In the same section, replace `- Uses \`gh\` only. No raw REST where \`gh\` has a subcommand.` with

`- Uses \`gh\` only, and \`gh issue list --json\` for reads (one paged GraphQL call under the hood, capped at 200 issues; a truncation warning goes to stderr). No raw REST where \`gh\` has a subcommand.`

In "Spec-kit interaction", replace `\`--per-task [T003,T007]\`` with `\`--per-task T003,T007\` (or \`--per-task all\`)`.

- [ ] **Step 3: Commit**

```bash
git add docs/superpowers/specs/2026-10-21-project-management-skill-design.md
git commit -m "docs(skills): defer Projects v2 and pin gh reads in the pm design"
```

---

### Task 2: Skill skeleton

**Files:**
- Create: `home/skills/project-management/SKILL.md`
- Create: `home/skills/project-management/triggers.json`

**Produces:** a skill that passes `lint-skills.sh` and `check-triggers.sh`. Later tasks append rows to the routing table; each row links only to a file that exists in that commit (the lint fails on dead links).

- [ ] **Step 1: Write `SKILL.md`**

````markdown
---
name: project-management
description: >-
  Use when breaking a project into epics and tasks, tracking tasks or progress in GitHub Issues or a markdown tracker, writing a project charter, plan, status report or retro, or checking what is blocked, overdue or next. Runs the `pm` script for compact task lists and status instead of many `gh` calls. Not for writing a feature spec (see speckit-specify), scheduling or calendars, or reviewing code.
metadata:
  summary: "Use for project breakdown, ticket tracking (GitHub Issues, markdown) and project docs via the pm script."
---

# Project management

## When to use

Use when planning or tracking work that spans more than one change: breaking a project down, creating or updating tickets, asking what is blocked or next, or writing the charter, plan, status report or retro. For one code feature, use the speckit skills; this skill tracks their tasks (see `tracking.md` once it is routed below).

## Rules

- **Name the tracker on every call.** `pm` keeps no state and detects nothing. Get the tracker from, in order: the user, a ticket URL they pasted, the repo's `CLAUDE.md`, `AGENTS.md` or README. Otherwise ask once, in one line, and reuse the answer. Never infer it from the git remote.
- **Mutations are dry-run first.** `sync-plan` prints what it would do. Run it with `--apply` only after the user has seen the dry run, because creating issues is outward-facing.
- **Read cheaply.** Run `pm status` first, then `pm list` with filters, then `pm show <id>` for one item. Never fetch bodies in bulk. These reads are mechanical: delegate them to a cheap worker (see the delegation skill) and keep breakdown judgement here.
- **Restate the project in one sentence** (what is wrong today, for whom) before breaking it down.

## Quick reference

`pm` lives in `scripts/` beside this file. Backends: `g` (github, needs `-r owner/name`) and `l` (local, needs `-d <dir>` holding `tasks.md`).

```
pm -b g -r owner/name status
pm -b g -r owner/name list --state open --due-before 2026-12-01T00:00:00Z
pm -b l -d docs/projects/foo show T003
pm -b g -r owner/name update 12 --state done
pm -b g -r owner/name sync-plan specs/002-x/tasks.md            # dry run
pm -b g -r owner/name sync-plan specs/002-x/tasks.md --apply
pm show https://github.com/owner/name/issues/12                 # a URL needs no -b
```

`list` prints `id state title owner deps due est prio`, tab separated, after a `# backend=...` line.

## Routing

| Doing | Read |
|---|---|
````

- [ ] **Step 2: Write `triggers.json`**

```json
{
  "fire": [
    "break this project down into epics and tasks",
    "what is blocked on the project right now",
    "write a project charter for this",
    "sync the speckit tasks to GitHub issues",
    "give me a status report for the project"
  ]
}
```

- [ ] **Step 3: Verify**

```bash
T='nix shell nixpkgs#bats nixpkgs#jq nixpkgs#yq-go nixpkgs#shellcheck nixpkgs#gawk -c'
$T bash home/skills/skill-authoring/scripts/lint-skills.sh home/skills
$T bash home/skills/skill-authoring/scripts/check-triggers.sh home/skills
```

Expected: lint passes (an empty routing table has no links). If `check-triggers.sh` reports an orphan phrase, add the missing content word to the `description`, not the phrase.

- [ ] **Step 4: Commit**

```bash
git add home/skills/project-management/SKILL.md home/skills/project-management/triggers.json
git commit -m "feat(project-management): add skill skeleton and triggers"
```

---

### Task 3: Shared library and the `pm` dispatcher

**Files:**
- Create: `scripts/lib/common.sh`, `scripts/pm`, `scripts/tests/helpers.bash`, `scripts/tests/dispatch.bats`

(All paths below are relative to `home/skills/project-management/`.)

**Interfaces:**
- Produces in `common.sh`: `PM_VERBS`, `pm_die msg...`, `pm_need tool...`, `pm_arg2 "$@"` (dies unless `$# >= 2`, naming `$1`), `pm_header backend [k=v...]`, `pm_backends_table dir` (lines `alias<TAB>name`, sorted by name), `pm_backends_usage dir` (`g|github l|local`), `pm_resolve_backend dir value`, `pm_url_route url` (prints `github<TAB>owner/name<TAB>number`).
- Produces: `pm` honours `PM_BACKENDS_DIR` (test seam) and `PM_BACKEND`.

- [ ] **Step 1: Write the failing test** `scripts/tests/helpers.bash`

```bash
# Shared bats helpers for the pm tests.

pm_setup() {
  tests_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  scripts_dir="$(cd "$tests_dir/.." && pwd)"
  pm="$scripts_dir/pm"
}

# Puts a fake gh first on PATH. fake-gh.sh holds its body; a shebang that
# resolves in this environment is prepended here. Fixtures live in
# $FAKE_GH_FIXTURES; every call is appended to calls.log.
install_fake_gh() {
  export FAKE_GH_FIXTURES="$BATS_TEST_TMPDIR/fixtures"
  mkdir -p "$FAKE_GH_FIXTURES" "$BATS_TEST_TMPDIR/bin"
  { printf '#!%s\n' "$(command -v bash)"; cat "$tests_dir/fake-gh.sh"; } >"$BATS_TEST_TMPDIR/bin/gh"
  chmod +x "$BATS_TEST_TMPDIR/bin/gh"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  : >"$FAKE_GH_FIXTURES/calls.log"
  echo '[]' >"$FAKE_GH_FIXTURES/list.json"
  echo '[]' >"$FAKE_GH_FIXTURES/epics.json"
  echo '{}' >"$FAKE_GH_FIXTURES/view.json"
}

# True if gh was asked to change anything.
gh_mutated() {
  grep -qE '^(issue (create|edit|close|reopen|comment)|label create)' "$FAKE_GH_FIXTURES/calls.log"
}

# Fails the test if gh was asked to change anything. Written with `if` because
# bats does not fail a test on a negated command (`! cmd`).
refute_mutated() {
  if gh_mutated; then
    echo "gh was asked to change something:"
    cat "$FAKE_GH_FIXTURES/calls.log"
    return 1
  fi
}

# refute_logged <pattern>: fails the test if a gh call matching the pattern was logged.
refute_logged() {
  if grep -q -- "$1" "$FAKE_GH_FIXTURES/calls.log"; then
    echo "unexpected gh call matching: $1"
    return 1
  fi
}
```

`scripts/tests/dispatch.bats`:

```bash
#!/usr/bin/env bats

load helpers

setup() {
  pm_setup
  export PM_BACKENDS_DIR="$BATS_TEST_TMPDIR/b"
  local b
  for b in demo other github; do
    mkdir -p "$PM_BACKENDS_DIR/$b"
  done
  echo d >"$PM_BACKENDS_DIR/demo/alias"
  echo O >"$PM_BACKENDS_DIR/other/alias"
  echo g >"$PM_BACKENDS_DIR/github/alias"
  for b in demo other; do
    printf 'echo "%s status $*"\n' "$b" >"$PM_BACKENDS_DIR/$b/status.sh"
  done
  echo 'echo "show $*"' >"$PM_BACKENDS_DIR/github/show.sh"
  unset PM_BACKEND
}

@test "a missing -b fails and lists the aliases" {
  run bash "$pm" status
  [ "$status" -eq 1 ]
  [[ "$output" == *"error: -b required: d|demo g|github O|other"* ]]
}

@test "-b accepts an alias in every spelling" {
  local form
  for form in "-b d" "-bd" "--backend d" "--backend=d" "-b demo" "--backend=demo"; do
    run bash "$pm" $form status a b
    [ "$status" -eq 0 ]
    [ "$output" = "demo status a b" ]
  done
}

@test "aliases are case sensitive" {
  run bash "$pm" -b O status
  [ "$output" = "other status " ]
  run bash "$pm" -b o status
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown backend 'o'; use d|demo g|github O|other"* ]]
}

@test "a backend without the verb fails by name" {
  run bash "$pm" -b d list
  [ "$status" -eq 1 ]
  [[ "$output" == *"backend demo has no verb list"* ]]
}

@test "PM_BACKEND is used when -b is absent and loses to -b" {
  PM_BACKEND=d run bash "$pm" status
  [ "$output" = "demo status " ]
  PM_BACKEND=O run bash "$pm" -b d status
  [ "$output" = "demo status " ]
}

@test "backend flags pass through untouched" {
  run bash "$pm" -b d -r x/y status 7
  [ "$output" = "demo status -r x/y 7" ]
}

@test "a GitHub issue URL routes to github without -b" {
  run bash "$pm" show https://github.com/owner/name/issues/12
  [ "$status" -eq 0 ]
  [ "$output" = "show -r owner/name 12" ]
}

@test "a verb is required" {
  run bash "$pm" -b d
  [ "$status" -eq 1 ]
  [[ "$output" == *"usage: pm"* ]]
}

@test "-h prints usage and exits 0" {
  run bash "$pm" -h
  [ "$status" -eq 0 ]
  [[ "$output" == *"verbs: status list show update sync-plan"* ]]
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `$T bats $SK/scripts/tests/dispatch.bats`
Expected: every test FAILS (`pm` does not exist).

- [ ] **Step 3: Implement** `scripts/lib/common.sh`

```bash
# shellcheck shell=bash
# Shared helpers for pm. Sourced, never executed.

PM_VERBS="status list show update sync-plan"

pm_die() {
  echo "error: $*" >&2
  exit 1
}

# pm_need tool...: die unless every tool is on PATH.
pm_need() {
  local t
  for t in "$@"; do
    command -v "$t" >/dev/null 2>&1 || pm_die "required tool not found: $t"
  done
}

# pm_arg2 "$@": die unless a flag at $1 has a value at $2.
pm_arg2() {
  [[ $# -ge 2 ]] || pm_die "${1:-flag} needs a value"
}

# pm_header backend [k=v ...]: the first line of every verb's output.
pm_header() {
  local out="# backend=$1" kv
  shift
  for kv in "$@"; do
    out="$out $kv"
  done
  echo "$out"
}

# pm_backends_table <dir>: one "alias<TAB>name" line per backend, by name.
pm_backends_table() {
  local d name alias
  for d in "$1"/*/; do
    [[ -d $d ]] || continue
    name="$(basename "$d")"
    alias=""
    if [[ -f $d/alias ]]; then
      alias="$(tr -d '[:space:]' <"$d/alias")"
    fi
    printf '%s\t%s\n' "$alias" "$name"
  done | sort -t "$(printf '\t')" -k2,2
}

# pm_backends_usage <dir>: "g|github l|local".
pm_backends_usage() {
  pm_backends_table "$1" | awk -F'\t' '{ printf "%s%s|%s", sep, $1, $2; sep = " " } END { print "" }'
}

# pm_resolve_backend <dir> <value>: print the backend name for an alias or a
# full name. Alias wins; no prefix or fuzzy matching.
pm_resolve_backend() {
  local dir="$1" want="$2" alias name
  while IFS="$(printf '\t')" read -r alias name; do
    if [[ -n $alias && $alias == "$want" ]]; then
      echo "$name"
      return 0
    fi
  done < <(pm_backends_table "$dir")
  if [[ $want =~ ^[a-z][a-z0-9-]*$ && -d $dir/$want ]]; then
    echo "$want"
    return 0
  fi
  return 1
}

# pm_url_route <arg>: for a GitHub issue URL print
# "github<TAB>owner/name<TAB>number" and return 0; otherwise return 1.
pm_url_route() {
  local re='^https://github\.com/([^/]+)/([^/]+)/issues/([0-9]+)/?$'
  if [[ $1 =~ $re ]]; then
    printf 'github\t%s/%s\t%s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}"
    return 0
  fi
  return 1
}
```

`scripts/pm`:

```bash
#!/usr/bin/env bash
# pm: one entry point for project trackers. -b picks a backend; the verb runs
# backends/<name>/<verb>.sh. Holds no state and does no detection.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$script_dir/lib/common.sh"
backends_dir="${PM_BACKENDS_DIR:-$script_dir/backends}"

usage() {
  echo "usage: pm -b <backend> [backend flags] <verb> [args]"
  echo "verbs: $PM_VERBS"
  echo "backends: $(pm_backends_usage "$backends_dir")"
  echo "a GitHub issue URL as an argument needs no -b"
}

backend_arg=""
verb=""
rest=()
args=("$@")
i=0
while ((i < ${#args[@]})); do
  a="${args[$i]}"
  case "$a" in
    -b | --backend)
      i=$((i + 1))
      ((i < ${#args[@]})) || pm_die "$a needs a value"
      backend_arg="${args[$i]}"
      ;;
    --backend=*) backend_arg="${a#--backend=}" ;;
    -b?*) backend_arg="${a#-b}" ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      if [[ -z $verb && " $PM_VERBS " == *" $a "* ]]; then
        verb="$a"
      else
        rest+=("$a")
      fi
      ;;
  esac
  i=$((i + 1))
done

backend_arg="${backend_arg:-${PM_BACKEND:-}}"

# A ticket URL names its own backend and repo.
if [[ -z $backend_arg ]]; then
  routed=()
  for a in ${rest[@]+"${rest[@]}"}; do
    if [[ -z $backend_arg ]] && route="$(pm_url_route "$a")"; then
      IFS=$'\t' read -r backend_arg url_repo url_num <<<"$route"
      routed+=(-r "$url_repo" "$url_num")
    else
      routed+=("$a")
    fi
  done
  rest=(${routed[@]+"${routed[@]}"})
fi

[[ -n $backend_arg ]] || pm_die "-b required: $(pm_backends_usage "$backends_dir")"
backend="$(pm_resolve_backend "$backends_dir" "$backend_arg")" ||
  pm_die "unknown backend '$backend_arg'; use $(pm_backends_usage "$backends_dir")"
if [[ -z $verb ]]; then
  usage >&2
  exit 1
fi
target="$backends_dir/$backend/$verb.sh"
[[ -f $target ]] || pm_die "backend $backend has no verb $verb"
exec bash "$target" ${rest[@]+"${rest[@]}"}
```

- [ ] **Step 4: Run to verify it passes**

Run: `$T bats $SK/scripts/tests/dispatch.bats`
Expected: 9 tests PASS. Then `$T shellcheck -x $SK/scripts/pm $SK/scripts/lib/common.sh` prints nothing. If shellcheck flags SC2206 on `rest=(...)`, add `# shellcheck disable=SC2206` on the line above it (the expansion is intentionally unquoted around a quoted inner expansion).

- [ ] **Step 5: Commit**

```bash
chmod +x $SK/scripts/pm
git add $SK/scripts/lib/common.sh $SK/scripts/pm $SK/scripts/tests/helpers.bash $SK/scripts/tests/dispatch.bats
git commit -m "feat(project-management): add the pm dispatcher and shared helpers"
```

---

### Task 4: Alias lint

**Files:**
- Create: `scripts/lint-aliases.sh`, `scripts/tests/lint-aliases.bats`

- [ ] **Step 1: Write the failing test** `scripts/tests/lint-aliases.bats`

```bash
#!/usr/bin/env bats

load helpers

setup() {
  pm_setup
  lint="$scripts_dir/lint-aliases.sh"
  dir="$BATS_TEST_TMPDIR/b"
  mkdir -p "$dir"
}

mk() { # mk <name> <alias>
  mkdir -p "$dir/$1"
  printf '%s\n' "$2" >"$dir/$1/alias"
}

@test "distinct valid aliases pass" {
  mk github g
  mk local l
  mk gitlab G
  run bash "$lint" "$dir"
  [ "$status" -eq 0 ]
}

@test "the same alias on two backends fails" {
  mk github g
  mk gitlab g
  run bash "$lint" "$dir"
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL github: alias 'g' also used by gitlab"* ]]
}

@test "case differences are distinct aliases" {
  mk github g
  mk gitlab G
  run bash "$lint" "$dir"
  [ "$status" -eq 0 ]
}

@test "a non-letter alias fails" {
  mk github g1
  run bash "$lint" "$dir"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not [A-Za-z]+"* ]]
}

@test "an alias equal to another backend's name fails" {
  mk github local
  mk local l
  run bash "$lint" "$dir"
  [ "$status" -eq 1 ]
  [[ "$output" == *"equals backend name local"* ]]
}

@test "an alias longer than its backend name fails" {
  mk jira jiraxx
  run bash "$lint" "$dir"
  [ "$status" -eq 1 ]
  [[ "$output" == *"longer than the name"* ]]
}

@test "a backend without an alias file fails" {
  mkdir -p "$dir/github"
  run bash "$lint" "$dir"
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL github: no alias file"* ]]
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `$T bats $SK/scripts/tests/lint-aliases.bats`
Expected: FAIL (script missing).

- [ ] **Step 3: Implement** `scripts/lint-aliases.sh`

```bash
#!/usr/bin/env bash
# Alias lint for pm backends. Usage: lint-aliases.sh [backends_dir]
# Prints "FAIL <backend>: <reason>" per problem; exits 1 if any.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
backends_dir="${1:-$script_dir/backends}"
failures=0
names=()
aliases=()

fail() {
  echo "FAIL $1: $2"
  failures=$((failures + 1))
}

for d in "$backends_dir"/*/; do
  [[ -d $d ]] || continue
  name="$(basename "$d")"
  if [[ ! -f $d/alias ]]; then
    fail "$name" "no alias file"
    continue
  fi
  alias="$(tr -d '[:space:]' <"$d/alias")"
  if [[ ! $alias =~ ^[A-Za-z]+$ ]]; then
    fail "$name" "alias '$alias' is not [A-Za-z]+"
    continue
  fi
  if ((${#alias} > ${#name})); then
    fail "$name" "alias '$alias' is longer than the name"
  fi
  names+=("$name")
  aliases+=("$alias")
done

n=${#names[@]}
for ((i = 0; i < n; i++)); do
  for ((j = 0; j < n; j++)); do
    ((i == j)) && continue
    if ((i < j)) && [[ ${aliases[i]} == "${aliases[j]}" ]]; then
      fail "${names[i]}" "alias '${aliases[i]}' also used by ${names[j]}"
    fi
    if [[ ${aliases[i]} == "${names[j]}" ]]; then
      fail "${names[i]}" "alias '${aliases[i]}' equals backend name ${names[j]}"
    fi
  done
done

if ((failures > 0)); then
  echo "$failures alias problem(s)" >&2
  exit 1
fi
echo "backend aliases ok"
```

Note: `((i == j)) && continue` is safe under `set -e` because it is not the last command in the loop body.

- [ ] **Step 4: Run to verify it passes**

Run: `$T bats $SK/scripts/tests/lint-aliases.bats`
Expected: 7 PASS. `$T shellcheck -x $SK/scripts/lint-aliases.sh` clean.

- [ ] **Step 5: Commit**

```bash
chmod +x $SK/scripts/lint-aliases.sh
git add $SK/scripts/lint-aliases.sh $SK/scripts/tests/lint-aliases.bats
git commit -m "test(project-management): lint backend aliases for collisions"
```

---

### Task 5: TSV and tasks.md libraries

**Files:**
- Create: `scripts/lib/tsv.sh`, `scripts/lib/tasks-md.sh`, `scripts/tests/lib.bats`

**Interfaces:**
- `tsv.sh`: `pm_filter_tsv <state|all> <assignee> <due_before>` (stdin TSV, `#` lines pass through), `pm_status_from_tsv <stale>` (stdin TSV, prints `open=N done=N blocked=N stale=S` and `next<TAB>id<TAB>title` if any), `pm_row_to_kv` (stdin rows, prints `key<TAB>value` for the eight columns).
- `tasks-md.sh`: `tasks_md_tsv <file>` (8-column rows), `tasks_md_raw <file>` (`id<TAB>raw line`), `tasks_md_set_state <file> <id> <open|done>` (returns 3 if the id is absent; preserves file mode), `tasks_md_append <file> <line>`.

- [ ] **Step 1: Write the failing test** `scripts/tests/lib.bats`

```bash
#!/usr/bin/env bats

load helpers

setup() {
  pm_setup
  # shellcheck source=/dev/null
  source "$scripts_dir/lib/common.sh"
  source "$scripts_dir/lib/tsv.sh"
  source "$scripts_dir/lib/tasks-md.sh"
  tasks="$BATS_TEST_TMPDIR/tasks.md"
  cat >"$tasks" <<'EOF'
# Tasks
- [X] T001 [P] [US1] Set up repo owner:ali est:30 prio:1
- [ ] T002 Write docs deps:T001,T003 due:2026-11-01T00:00:00Z
- [ ] T003 [US2] Do thing with `code` prio:2
- [ ] pm:plan-x Plain item
- [ ] not a task line
text
EOF
}

tab() { printf '\t'; }

@test "tasks_md_tsv parses ids, markers, fields and titles" {
  run tasks_md_tsv "$tasks"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "$(printf 'T001\tdone\tSet up repo\tali\t\t\t30\t1')" ]
  [ "${lines[1]}" = "$(printf 'T002\topen\tWrite docs\t\tT001,T003\t2026-11-01T00:00:00Z\t\t')" ]
  [ "${lines[2]}" = "$(printf 'T003\topen\tDo thing with `code`\t\t\t\t\t2')" ]
  [ "${lines[3]}" = "$(printf 'pm:plan-x\topen\tPlain item\t\t\t\t\t')" ]
  [ "${#lines[@]}" -eq 4 ]
}

@test "tasks_md_raw keeps the original line" {
  run tasks_md_raw "$tasks"
  [ "${lines[0]}" = "$(printf 'T001\t- [X] T001 [P] [US1] Set up repo owner:ali est:30 prio:1')" ]
}

@test "pm_status_from_tsv counts, finds blocked and picks next" {
  run bash -c "source '$scripts_dir/lib/tasks-md.sh'; source '$scripts_dir/lib/tsv.sh'; tasks_md_tsv '$tasks' | pm_status_from_tsv n/a"
  [ "${lines[0]}" = "open=3 done=1 blocked=1 stale=n/a" ]
  [ "${lines[1]}" = "$(printf 'next\tT003\tDo thing with `code`')" ]
}

@test "pm_filter_tsv filters by state, assignee and due date and keeps # lines" {
  rows="$(printf '# backend=x\n'; tasks_md_tsv "$tasks")"
  run bash -c "source '$scripts_dir/lib/tsv.sh'; printf '%s\n' '$rows' | pm_filter_tsv done '' ''"
  [ "${lines[0]}" = "# backend=x" ]
  [ "${#lines[@]}" -eq 2 ]
  run bash -c "source '$scripts_dir/lib/tsv.sh'; printf '%s\n' '$rows' | pm_filter_tsv all ali ''"
  [ "${#lines[@]}" -eq 2 ]
  run bash -c "source '$scripts_dir/lib/tsv.sh'; printf '%s\n' '$rows' | pm_filter_tsv open '' 2026-12-01T00:00:00Z"
  [[ "${lines[1]}" == T002* ]]
  [ "${#lines[@]}" -eq 2 ]
}

@test "pm_row_to_kv labels the eight columns" {
  run bash -c "source '$scripts_dir/lib/tasks-md.sh'; source '$scripts_dir/lib/tsv.sh'; tasks_md_tsv '$tasks' | awk 'NR==2' | pm_row_to_kv"
  [ "${lines[0]}" = "$(printf 'id\tT002')" ]
  [ "${lines[4]}" = "$(printf 'deps\tT001,T003')" ]
  [ "${#lines[@]}" -eq 8 ]
}

@test "tasks_md_set_state flips the box, keeps mode, reports a missing id" {
  chmod 640 "$tasks"
  tasks_md_set_state "$tasks" T002 done
  grep -q '^- \[X\] T002 Write docs' "$tasks"
  tasks_md_set_state "$tasks" T001 open
  grep -q '^- \[ \] T001 \[P\]' "$tasks"
  [ "$(stat -c %a "$tasks" 2>/dev/null || stat -f %Lp "$tasks")" = "640" ]
  run tasks_md_set_state "$tasks" T999 done
  [ "$status" -eq 3 ]
}

@test "tasks_md_append adds a line even when the file lacks a final newline" {
  printf '%s' '- [ ] T001 One' >"$BATS_TEST_TMPDIR/n.md"
  tasks_md_append "$BATS_TEST_TMPDIR/n.md" '- [ ] T002 Two'
  [ "$(wc -l <"$BATS_TEST_TMPDIR/n.md" | tr -d ' ')" = "2" ]
  [ "$(tail -n1 "$BATS_TEST_TMPDIR/n.md")" = "- [ ] T002 Two" ]
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `$T bats $SK/scripts/tests/lib.bats`
Expected: FAIL (libs missing).

- [ ] **Step 3: Implement** `scripts/lib/tsv.sh`

```bash
# shellcheck shell=bash
# TSV helpers shared by every backend. Rows have eight tab-separated fields:
# id state title owner deps due est prio. Sourced, never executed.

# pm_filter_tsv <state|all> <assignee> <due_before>: filter rows on stdin.
# Lines starting with # pass through. An empty filter matches everything.
pm_filter_tsv() {
  awk -F'\t' -v s="$1" -v a="$2" -v b="$3" '
    $0 ~ /^#/ { print; next }
    (s == "all" || $2 == s) && (a == "" || $4 == a) && (b == "" || ($6 != "" && $6 < b)) { print }'
}

# pm_status_from_tsv <stale>: summarise rows on stdin. An open row is blocked
# when any id in its deps is itself open. "next" is the unblocked open row
# with the lowest prio, then the earliest due date, then file order.
pm_status_from_tsv() {
  local stale="${1:-n/a}"
  awk -F'\t' -v stale="$stale" '
    /^#/ { next }
    NF < 8 { next }
    { n++; id[n] = $1; st[n] = $2; ti[n] = $3; dp[n] = $5; du[n] = $6; pr[n] = $8
      if ($2 == "open") isopen[$1] = 1 }
    END {
      for (i = 1; i <= n; i++) {
        if (st[i] == "done") { ndone++; continue }
        nopen++
        blk = 0
        m = split(dp[i], d, ",")
        for (k = 1; k <= m; k++) if (d[k] != "" && (d[k] in isopen)) blk = 1
        if (blk) { nblocked++; continue }
        kp = (pr[i] == "") ? 99999 : pr[i] + 0
        kd = (du[i] == "") ? "9999" : du[i]
        if (!have || kp < bp || (kp == bp && kd < bd)) { have = 1; bp = kp; bd = kd; bid = id[i]; bti = ti[i] }
      }
      printf "open=%d done=%d blocked=%d stale=%s\n", nopen, ndone, nblocked, stale
      if (have) printf "next\t%s\t%s\n", bid, bti
    }'
}

# pm_row_to_kv: label each row on stdin as eight key<TAB>value lines.
pm_row_to_kv() {
  awk -F'\t' '
    BEGIN { split("id state title owner deps due est prio", k, " ") }
    { for (i = 1; i <= 8; i++) printf "%s\t%s\n", k[i], $i }'
}
```

`scripts/lib/tasks-md.sh`

```bash
# shellcheck shell=bash
# Reader and editor for speckit-style task lines:
#   - [ ] T001 [P] [US1] description owner:x deps:T001,T002 due:... est:30 prio:2
# An id is T<digits> or pm:<slug>. Sourced, never executed.

# tasks_md_tsv <file>: eight-column rows (id state title owner deps due est prio).
tasks_md_tsv() {
  awk '
    /^- \[[ xX]\] / {
      state = (substr($0, 4, 1) == " ") ? "open" : "done"
      rest = substr($0, 7)
      id = rest; sub(/ .*/, "", id)
      if (id !~ /^(T[0-9]+|pm:[a-z0-9-]+)$/) next
      rest = substr(rest, length(id) + 2)
      while (match(rest, /^\[(P|US[0-9]+)\] ?/)) rest = substr(rest, RLENGTH + 1)
      owner = deps = due = est = prio = ""
      title = ""
      n = split(rest, w, " ")
      for (i = 1; i <= n; i++) {
        if (w[i] ~ /^owner:/) owner = substr(w[i], 7)
        else if (w[i] ~ /^deps:/) deps = substr(w[i], 6)
        else if (w[i] ~ /^due:/) due = substr(w[i], 5)
        else if (w[i] ~ /^est:/) est = substr(w[i], 5)
        else if (w[i] ~ /^prio:/) prio = substr(w[i], 6)
        else title = (title == "" ? w[i] : title " " w[i])
      }
      printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n", id, state, title, owner, deps, due, est, prio
    }' "$1"
}

# tasks_md_raw <file>: "id<TAB>original line" for every task line.
tasks_md_raw() {
  awk '
    /^- \[[ xX]\] / {
      rest = substr($0, 7)
      id = rest; sub(/ .*/, "", id)
      if (id ~ /^(T[0-9]+|pm:[a-z0-9-]+)$/) printf "%s\t%s\n", id, $0
    }' "$1"
}

# tasks_md_set_state <file> <id> <open|done>: set the checkbox. Returns 3 if
# the id is absent. Writes through cat so the file keeps its mode and links.
tasks_md_set_state() {
  local file="$1" id="$2" want="$3" mark=" " tmp rc=0
  [[ $want == done ]] && mark="X"
  tmp="$(mktemp "${file}.XXXXXX")"
  awk -v id="$id" -v mark="$mark" '
    /^- \[[ xX]\] / {
      rest = substr($0, 7); tok = rest; sub(/ .*/, "", tok)
      if (tok == id) { $0 = "- [" mark "] " rest; found = 1 }
    }
    { print }
    END { exit found ? 0 : 3 }' "$file" >"$tmp" || rc=$?
  if ((rc == 0)); then
    cat "$tmp" >"$file"
  fi
  rm -f "$tmp"
  return "$rc"
}

# tasks_md_append <file> <line>: append a line, adding a newline first if the
# file does not end with one.
tasks_md_append() {
  local file="$1" line="$2"
  if [[ -s $file && -n "$(tail -c1 "$file")" ]]; then
    printf '\n' >>"$file"
  fi
  printf '%s\n' "$line" >>"$file"
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `$T bats $SK/scripts/tests/lib.bats`
Expected: 7 PASS. `$T shellcheck -x $SK/scripts/lib/*.sh` clean.

- [ ] **Step 5: Commit**

```bash
git add $SK/scripts/lib/tsv.sh $SK/scripts/lib/tasks-md.sh $SK/scripts/tests/lib.bats
git commit -m "feat(project-management): add TSV and tasks.md libraries"
```

---

### Task 6: Local backend

One commit per verb, each with tests. The shared test fixture and helper come first.

**Files:**
- Create: `scripts/backends/local/{alias,_local.sh,list.sh,status.sh,show.sh,update.sh,sync-plan.sh}`, `scripts/tests/local.bats`

**Interfaces:**
- `_local.sh`: `local_take_dir "$@"` sets `LOCAL_DIR`, `LOCAL_TASKS`, `LOCAL_REST` (array of the remaining args). It dies unless `-d`/`--dir` (or `PM_DIR`) is given and `$LOCAL_DIR/tasks.md` exists, except when `LOCAL_TASKS_OPTIONAL=1`.

- [ ] **Step 1: Alias, helper and the shared test setup (commit 6a)**

`scripts/backends/local/alias`: the single line `l`

`scripts/backends/local/_local.sh`:

```bash
# shellcheck shell=bash
# Shared argument handling for the local backend verbs. Sourced.

# local_take_dir "$@": take -d/--dir out of the arguments.
# Sets LOCAL_DIR, LOCAL_TASKS and LOCAL_REST (the other arguments).
local_take_dir() {
  LOCAL_DIR="${PM_DIR:-}"
  LOCAL_REST=()
  while (($#)); do
    case "$1" in
      -d | --dir)
        pm_arg2 "$@"
        LOCAL_DIR="$2"
        shift 2
        ;;
      --dir=*)
        LOCAL_DIR="${1#--dir=}"
        shift
        ;;
      *)
        LOCAL_REST+=("$1")
        shift
        ;;
    esac
  done
  [[ -n $LOCAL_DIR ]] || pm_die "the local backend needs -d <dir> (the directory holding tasks.md)"
  LOCAL_TASKS="$LOCAL_DIR/tasks.md"
  if [[ ${LOCAL_TASKS_OPTIONAL:-0} != 1 && ! -f $LOCAL_TASKS ]]; then
    pm_die "no tasks.md in $LOCAL_DIR"
  fi
}
```

`scripts/tests/local.bats` (grows with each verb; start with the setup and the dir test):

```bash
#!/usr/bin/env bats

load helpers

setup() {
  pm_setup
  dir="$BATS_TEST_TMPDIR/proj"
  mkdir -p "$dir"
  cat >"$dir/tasks.md" <<'EOF'
# Tasks
- [X] T001 [P] [US1] Set up repo owner:ali est:30 prio:1
- [ ] T002 Write docs deps:T001,T003 due:2026-11-01T00:00:00Z
- [ ] T003 [US2] Do thing prio:2
- [ ] pm:plan-x Plain item
EOF
  L=(bash "$pm" -b l -d "$dir")
}

@test "the local backend needs -d" {
  run bash "$pm" -b l list
  [ "$status" -eq 1 ]
  [[ "$output" == *"needs -d <dir>"* ]]
}

@test "the local backend reports a missing tasks.md" {
  run bash "$pm" -b l -d "$BATS_TEST_TMPDIR/empty" list
  [ "$status" -eq 1 ]
  [[ "$output" == *"no tasks.md in"* ]]
}
```

Run: `$T bats $SK/scripts/tests/local.bats` (the two tests FAIL: no `list.sh` yet for the second only; the first fails with "backend local has no verb list"). That is expected until Step 2. Do not commit yet: Task 6 commits per verb, starting with the verb that makes these pass.

- [ ] **Step 2: `list` (commit 6a)**

Append to `local.bats`:

```bash
@test "list defaults to open tasks and prints the header" {
  run "${L[@]}" list
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "# backend=local dir=$dir" ]
  [ "${lines[1]}" = "$(printf 'T002\topen\tWrite docs\t\tT001,T003\t2026-11-01T00:00:00Z\t\t')" ]
  [ "${#lines[@]}" -eq 4 ]
}

@test "list --state all and done" {
  run "${L[@]}" list --state all
  [ "${#lines[@]}" -eq 5 ]
  run "${L[@]}" list --state done
  [ "${#lines[@]}" -eq 2 ]
  [[ "${lines[1]}" == T001* ]]
}

@test "list --assignee and --due-before" {
  run "${L[@]}" list --state all --assignee ali
  [ "${#lines[@]}" -eq 2 ]
  run "${L[@]}" list --due-before 2026-12-01T00:00:00Z
  [ "${#lines[@]}" -eq 2 ]
  [[ "${lines[1]}" == T002* ]]
}

@test "list rejects a flag the local backend cannot honour" {
  run "${L[@]}" list --label x
  [ "$status" -eq 1 ]
  [[ "$output" == *"unsupported argument '--label' for the local backend"* ]]
}

@test "list rejects a bad --state" {
  run "${L[@]}" list --state bogus
  [ "$status" -eq 1 ]
  [[ "$output" == *"--state must be open, done or all"* ]]
}
```

`scripts/backends/local/list.sh`:

```bash
#!/usr/bin/env bash
# pm list (local): task rows from tasks.md.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$script_dir/../../lib/common.sh"
# shellcheck source=../../lib/tsv.sh
source "$script_dir/../../lib/tsv.sh"
# shellcheck source=../../lib/tasks-md.sh
source "$script_dir/../../lib/tasks-md.sh"
# shellcheck source=_local.sh
source "$script_dir/_local.sh"

local_take_dir "$@"
set -- ${LOCAL_REST[@]+"${LOCAL_REST[@]}"}

state=open
assignee=""
due_before=""
while (($#)); do
  case "$1" in
    --state)
      pm_arg2 "$@"
      state="$2"
      shift 2
      ;;
    --assignee)
      pm_arg2 "$@"
      assignee="$2"
      shift 2
      ;;
    --due-before)
      pm_arg2 "$@"
      due_before="$2"
      shift 2
      ;;
    *) pm_die "list: unsupported argument '$1' for the local backend" ;;
  esac
done
case "$state" in
  open | done | all) ;;
  *) pm_die "list: --state must be open, done or all" ;;
esac

pm_header local "dir=$LOCAL_DIR"
tasks_md_tsv "$LOCAL_TASKS" | pm_filter_tsv "$state" "$assignee" "$due_before"
```

Run bats: all local tests PASS. Commit:

```bash
git add $SK/scripts/backends/local $SK/scripts/tests/local.bats
git commit -m "feat(project-management): add the local backend list verb"
```

- [ ] **Step 3: `status` (commit 6b)**

Append to `local.bats`:

```bash
@test "status counts, blocked and next" {
  run "${L[@]}" status
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "# backend=local dir=$dir" ]
  [ "${lines[1]}" = "open=3 done=1 blocked=1 stale=n/a" ]
  [ "${lines[2]}" = "$(printf 'next\tT003\tDo thing')" ]
}
```

`scripts/backends/local/status.sh`:

```bash
#!/usr/bin/env bash
# pm status (local): counts, blocked and the next task to pick up.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$script_dir/../../lib/common.sh"
# shellcheck source=../../lib/tsv.sh
source "$script_dir/../../lib/tsv.sh"
# shellcheck source=../../lib/tasks-md.sh
source "$script_dir/../../lib/tasks-md.sh"
# shellcheck source=_local.sh
source "$script_dir/_local.sh"

local_take_dir "$@"
((${#LOCAL_REST[@]} == 0)) || pm_die "status: unexpected argument '${LOCAL_REST[0]}'"

pm_header local "dir=$LOCAL_DIR"
tasks_md_tsv "$LOCAL_TASKS" | pm_status_from_tsv "n/a"
```

Run bats, then commit: `git add ...; git commit -m "feat(project-management): add the local backend status verb"`.

- [ ] **Step 4: `show` (commit 6c)**

Append to `local.bats`:

```bash
@test "show prints labelled fields" {
  run "${L[@]}" show T002
  [ "$status" -eq 0 ]
  [ "${lines[1]}" = "$(printf 'id\tT002')" ]
  [ "${lines[5]}" = "$(printf 'deps\tT001,T003')" ]
  [ "${lines[6]}" = "$(printf 'due\t2026-11-01T00:00:00Z')" ]
}

@test "show fails for an unknown id" {
  run "${L[@]}" show T404
  [ "$status" -eq 1 ]
  [[ "$output" == *"no task T404"* ]]
}
```

(`lines[0]` is the header; `id` is line 1, `deps` is line 5 because the order is id state title owner deps due est prio, so `deps` is the 5th key and sits at index 5; `due` at 6.)

`scripts/backends/local/show.sh`:

```bash
#!/usr/bin/env bash
# pm show <id> (local): one task as key<TAB>value lines.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$script_dir/../../lib/common.sh"
# shellcheck source=../../lib/tsv.sh
source "$script_dir/../../lib/tsv.sh"
# shellcheck source=../../lib/tasks-md.sh
source "$script_dir/../../lib/tasks-md.sh"
# shellcheck source=_local.sh
source "$script_dir/_local.sh"

local_take_dir "$@"
id=""
for a in ${LOCAL_REST[@]+"${LOCAL_REST[@]}"}; do
  case "$a" in
    --full) ;; # the local backend has no long bodies
    -*) pm_die "show: unsupported argument '$a' for the local backend" ;;
    *) id="$a" ;;
  esac
done
[[ -n $id ]] || pm_die "show: need a task id"

row="$(tasks_md_tsv "$LOCAL_TASKS" | awk -F'\t' -v id="$id" '$1 == id')"
[[ -n $row ]] || pm_die "no task $id in $LOCAL_TASKS"

pm_header local "dir=$LOCAL_DIR"
printf '%s\n' "$row" | pm_row_to_kv
```

Run bats, commit `feat(project-management): add the local backend show verb`.

- [ ] **Step 5: `update` (commit 6d)**

Append to `local.bats`:

```bash
@test "update flips the checkbox and is idempotent" {
  run "${L[@]}" update T002 --state done
  [ "$status" -eq 0 ]
  [ "${lines[1]}" = "updated T002 state=done" ]
  grep -q '^- \[X\] T002 Write docs' "$dir/tasks.md"
  run "${L[@]}" update T002 --state done
  [ "${lines[1]}" = "unchanged T002 state=done" ]
  run "${L[@]}" update T001 --state open
  [ "${lines[1]}" = "updated T001 state=open" ]
  grep -q '^- \[ \] T001 \[P\]' "$dir/tasks.md"
}

@test "update fails for an unknown id, a bad state and unsupported flags" {
  run "${L[@]}" update T404 --state done
  [ "$status" -eq 1 ]
  [[ "$output" == *"no task T404"* ]]
  run "${L[@]}" update T002 --state bogus
  [ "$status" -eq 1 ]
  run "${L[@]}" update T002 --comment hi
  [ "$status" -eq 1 ]
  [[ "$output" == *"unsupported argument '--comment' for the local backend"* ]]
  run "${L[@]}" update T002
  [ "$status" -eq 1 ]
  [[ "$output" == *"--state is required"* ]]
}
```

`scripts/backends/local/update.sh`:

```bash
#!/usr/bin/env bash
# pm update <id> --state open|done (local): flip the checkbox in tasks.md.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$script_dir/../../lib/common.sh"
# shellcheck source=../../lib/tsv.sh
source "$script_dir/../../lib/tsv.sh"
# shellcheck source=../../lib/tasks-md.sh
source "$script_dir/../../lib/tasks-md.sh"
# shellcheck source=_local.sh
source "$script_dir/_local.sh"

local_take_dir "$@"
set -- ${LOCAL_REST[@]+"${LOCAL_REST[@]}"}

id=""
want=""
while (($#)); do
  case "$1" in
    --state)
      pm_arg2 "$@"
      want="$2"
      shift 2
      ;;
    -*) pm_die "update: unsupported argument '$1' for the local backend" ;;
    *)
      id="$1"
      shift
      ;;
  esac
done
[[ -n $id ]] || pm_die "update: need a task id"
[[ -n $want ]] || pm_die "update: --state is required for the local backend"
case "$want" in
  open | done) ;;
  *) pm_die "update: --state must be open or done" ;;
esac

current="$(tasks_md_tsv "$LOCAL_TASKS" | awk -F'\t' -v id="$id" '$1 == id { print $2 }')"
[[ -n $current ]] || pm_die "no task $id in $LOCAL_TASKS"

pm_header local "dir=$LOCAL_DIR"
if [[ $current == "$want" ]]; then
  echo "unchanged $id state=$want"
else
  tasks_md_set_state "$LOCAL_TASKS" "$id" "$want"
  echo "updated $id state=$want"
fi
```

Run bats, commit `feat(project-management): add the local backend update verb`.

- [ ] **Step 6: `sync-plan` (commit 6e)**

For the local backend, `sync-plan <file>` copies task lines from `<file>` into `tasks.md` when their id is absent. It is a dry run unless `--apply`. Epic and per-task options are GitHub-only.

Append to `local.bats`:

```bash
make_plan() {
  cat >"$BATS_TEST_TMPDIR/plan.md" <<'EOF'
- [ ] T003 [US2] Do thing prio:2
- [ ] T009 New task est:15
- [ ] pm:new-thing Another
EOF
}

@test "sync-plan dry run reports and changes nothing" {
  make_plan
  before="$(cat "$dir/tasks.md")"
  run "${L[@]}" sync-plan "$BATS_TEST_TMPDIR/plan.md"
  [ "$status" -eq 0 ]
  [ "${lines[1]}" = "$(printf 'exists\ttask\tT003\tDo thing')" ]
  [ "${lines[2]}" = "$(printf 'would-create\ttask\tT009\tNew task')" ]
  [ "${lines[3]}" = "$(printf 'would-create\ttask\tpm:new-thing\tAnother')" ]
  [ "$(cat "$dir/tasks.md")" = "$before" ]
}

@test "sync-plan --apply appends only missing tasks and is idempotent" {
  make_plan
  run "${L[@]}" sync-plan "$BATS_TEST_TMPDIR/plan.md" --apply
  [ "${lines[2]}" = "$(printf 'created\ttask\tT009\tNew task')" ]
  grep -q '^- \[ \] T009 New task est:15$' "$dir/tasks.md"
  [ "$(grep -c 'T003' "$dir/tasks.md")" -eq 2 ] # T003 plus the dep reference on T002
  run "${L[@]}" sync-plan "$BATS_TEST_TMPDIR/plan.md" --apply
  [ "${lines[2]}" = "$(printf 'exists\ttask\tT009\tNew task')" ]
}

@test "sync-plan on its own tasks.md changes nothing" {
  run "${L[@]}" sync-plan "$dir/tasks.md" --apply
  [ "$status" -eq 0 ]
  [[ "$output" != *"created"* ]]
}

@test "sync-plan creates tasks.md when the directory has none" {
  make_plan
  run bash "$pm" -b l -d "$BATS_TEST_TMPDIR/fresh" sync-plan "$BATS_TEST_TMPDIR/plan.md" --apply
  [ "$status" -eq 0 ]
  [ "$(grep -c '^- \[ \]' "$BATS_TEST_TMPDIR/fresh/tasks.md")" -eq 3 ]
}

@test "sync-plan rejects GitHub-only options" {
  run "${L[@]}" sync-plan "$dir/tasks.md" --per-task all
  [ "$status" -eq 1 ]
  [[ "$output" == *"unsupported argument '--per-task' for the local backend"* ]]
}
```

`scripts/backends/local/sync-plan.sh`:

```bash
#!/usr/bin/env bash
# pm sync-plan <file> [--apply] (local): add task lines from <file> to
# tasks.md when their id is absent. Dry run unless --apply.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$script_dir/../../lib/common.sh"
# shellcheck source=../../lib/tsv.sh
source "$script_dir/../../lib/tsv.sh"
# shellcheck source=../../lib/tasks-md.sh
source "$script_dir/../../lib/tasks-md.sh"
# shellcheck source=_local.sh
source "$script_dir/_local.sh"

LOCAL_TASKS_OPTIONAL=1
local_take_dir "$@"
set -- ${LOCAL_REST[@]+"${LOCAL_REST[@]}"}

apply=0
file=""
while (($#)); do
  case "$1" in
    --apply)
      apply=1
      shift
      ;;
    -*) pm_die "sync-plan: unsupported argument '$1' for the local backend" ;;
    *)
      [[ -z $file ]] || pm_die "sync-plan: takes one file"
      file="$1"
      shift
      ;;
  esac
done
[[ -n $file && -f $file ]] || pm_die "sync-plan: need an existing plan file"

existing=""
if [[ -f $LOCAL_TASKS ]]; then
  existing="$(tasks_md_tsv "$LOCAL_TASKS" | cut -f1)"
fi

pm_header local "dir=$LOCAL_DIR"
while IFS="$(printf '\t')" read -r id raw; do
  title="$(tasks_md_tsv <(printf '%s\n' "$raw") | cut -f3)"
  if printf '%s\n' "$existing" | grep -qxF "$id"; then
    printf 'exists\ttask\t%s\t%s\n' "$id" "$title"
  elif ((apply)); then
    mkdir -p "$LOCAL_DIR"
    tasks_md_append "$LOCAL_TASKS" "$raw"
    printf 'created\ttask\t%s\t%s\n' "$id" "$title"
  else
    printf 'would-create\ttask\t%s\t%s\n' "$id" "$title"
  fi
done < <(tasks_md_raw "$file")
```

`<(...)` process substitution is bash 3.2 safe. The title shown is the parsed one (markers and fields stripped), not the raw remainder.

Run bats; `$T shellcheck -x $SK/scripts/backends/local/*.sh` clean. Commit `feat(project-management): add the local backend sync-plan verb`.

---

### Task 7: GitHub backend

**Files:**
- Create: `scripts/backends/github/{alias,_gh.sh,rows.jq,list.sh,status.sh,show.sh,update.sh,sync-plan.sh}`, `scripts/tests/fake-gh.sh`, `scripts/tests/github.bats`

**Interfaces:**
- `_gh.sh`: `gh_take_repo "$@"` sets `GH_REPO` (from `-r`/`--repo` or `PM_REPO`; must be `owner/name`) and `GH_REST` (other args), and runs `pm_need gh jq`.
- `rows.jq`: turns a `gh issue list --json` array into the eight-column rows.
- `GH_FIELDS=number,title,state,assignees,labels,milestone,updatedAt,body`.

- [ ] **Step 1: Fake gh, alias, helpers, fixtures (commit 7a is bundled into the `list` commit)**

`scripts/tests/fake-gh.sh` (body only; `install_fake_gh` prepends the shebang; keep it non-executable):

```bash
# Body of a fake `gh`. Logs argv and answers from fixture files so the tests
# never touch the network.
set -euo pipefail
fx="${FAKE_GH_FIXTURES:?FAKE_GH_FIXTURES must be set}"
printf '%s\n' "$*" >>"$fx/calls.log"
case "${1:-} ${2:-}" in
  "issue list")
    if [[ "$*" == *"--label pm-epic"* ]]; then
      cat "$fx/epics.json"
    else
      cat "$fx/list.json"
    fi
    ;;
  "issue view") cat "$fx/view.json" ;;
  "issue create")
    cat >"$fx/created-body.txt" || true
    echo "https://github.com/owner/name/issues/99"
    ;;
  "issue edit")
    if [[ "$*" == *"--body-file -"* ]]; then cat >"$fx/edited-body.txt"; fi
    ;;
  "issue close" | "issue reopen" | "issue comment" | "label create") ;;
  *)
    echo "fake gh: unhandled call: $*" >&2
    exit 2
    ;;
esac
```

`scripts/backends/github/alias`: the single line `g`

`scripts/backends/github/_gh.sh`:

```bash
# shellcheck shell=bash
# Shared argument handling for the github backend verbs. Sourced.

GH_FIELDS="number,title,state,assignees,labels,milestone,updatedAt,body"
GH_LIMIT=200

# gh_take_repo "$@": take -r/--repo out of the arguments.
# Sets GH_REPO and GH_REST (the other arguments).
gh_take_repo() {
  GH_REPO="${PM_REPO:-}"
  GH_REST=()
  while (($#)); do
    case "$1" in
      -r | --repo)
        pm_arg2 "$@"
        GH_REPO="$2"
        shift 2
        ;;
      --repo=*)
        GH_REPO="${1#--repo=}"
        shift
        ;;
      *)
        GH_REST+=("$1")
        shift
        ;;
    esac
  done
  [[ -n $GH_REPO ]] || pm_die "the github backend needs -r owner/name"
  [[ $GH_REPO =~ ^[^/]+/[^/]+$ ]] || pm_die "-r must be owner/name, got '$GH_REPO'"
  pm_need gh jq
}

# gh_warn_truncated <json>: warn on stderr when a list hit the cap.
gh_warn_truncated() {
  local n
  n="$(jq length <<<"$1")"
  if ((n >= GH_LIMIT)); then
    echo "# warning: results truncated at $GH_LIMIT issues" >&2
  fi
}
```

`scripts/backends/github/rows.jq`:

```jq
# Rows for pm: id state title owner deps due est prio, tab separated.
def lab(p): ([.labels[].name | select(startswith(p))] | first // "") | sub("^" + p; "");
def deps: [(.body // "") | split("\n")[] | select(test("^deps:")) | sub("^deps:[ \t]*"; "") | gsub("[# \r]"; "")] | (first // "");
.[] | [
  (.number | tostring),
  (if .state == "OPEN" then "open" else "done" end),
  (.title | gsub("[\t\n\r]"; " ")),
  (.assignees[0].login // ""),
  deps,
  (.milestone.dueOn // ""),
  lab("est:"),
  lab("prio:")
] | join("\t")
```

`scripts/tests/github.bats` (setup and `list` tests):

```bash
#!/usr/bin/env bats

load helpers

setup() {
  pm_setup
  install_fake_gh
  fx="$FAKE_GH_FIXTURES"
  cat >"$fx/list.json" <<'EOF'
[
 {"number":1,"title":"Set up repo","state":"OPEN","assignees":[{"login":"ali"}],
  "labels":[{"name":"est:30"},{"name":"prio:1"}],"milestone":{"dueOn":"2026-11-01T00:00:00Z"},
  "updatedAt":"2020-01-01T00:00:00Z","body":"deps: #2, #3\nmore"},
 {"number":2,"title":"Write docs","state":"CLOSED","assignees":[],"labels":[],
  "milestone":null,"updatedAt":"2020-01-01T00:00:00Z","body":null},
 {"number":3,"title":"Third","state":"OPEN","assignees":[],"labels":[],
  "milestone":null,"updatedAt":"2099-01-01T00:00:00Z","body":""}
]
EOF
  G=(bash "$pm" -b g -r owner/name)
}

@test "the github backend needs a valid -r" {
  run bash "$pm" -b g list
  [ "$status" -eq 1 ]
  [[ "$output" == *"needs -r owner/name"* ]]
  run bash "$pm" -b g -r nope list
  [ "$status" -eq 1 ]
  [[ "$output" == *"-r must be owner/name"* ]]
}

@test "list defaults to open issues" {
  run "${G[@]}" list
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "# backend=github repo=owner/name" ]
  [ "${lines[1]}" = "$(printf '1\topen\tSet up repo\tali\t2,3\t2026-11-01T00:00:00Z\t30\t1')" ]
  [ "${lines[2]}" = "$(printf '3\topen\tThird\t\t\t\t\t')" ]
  [ "${#lines[@]}" -eq 3 ]
  grep -q 'issue list -R owner/name --state open --limit 200 --json' "$fx/calls.log"
}

@test "list --state done maps to closed and --state all keeps both" {
  run "${G[@]}" list --state done
  [ "${#lines[@]}" -eq 2 ]
  [[ "${lines[1]}" == 2* ]]
  grep -q -- '--state closed' "$fx/calls.log"
  run "${G[@]}" list --state all
  [ "${#lines[@]}" -eq 4 ]
}

@test "list passes label, milestone and assignee to gh and filters by due date" {
  run "${G[@]}" list --label bug --milestone M1 --assignee ali
  grep -q -- '--label bug' "$fx/calls.log"
  grep -q -- '--milestone M1' "$fx/calls.log"
  grep -q -- '--assignee ali' "$fx/calls.log"
  run "${G[@]}" list --due-before 2026-12-01T00:00:00Z
  [ "${#lines[@]}" -eq 2 ]
  run "${G[@]}" list --due-before 2026-01-01T00:00:00Z
  [ "${#lines[@]}" -eq 1 ]
}

@test "list warns when the result hit the cap" {
  jq -n '[range(0;200) | {number:., title:"t", state:"OPEN", assignees:[], labels:[], milestone:null, updatedAt:"2099-01-01T00:00:00Z", body:""}]' >"$fx/list.json"
  run "${G[@]}" list
  [[ "$output" == *"results truncated at 200 issues"* ]]
}
```

`scripts/backends/github/list.sh`:

```bash
#!/usr/bin/env bash
# pm list (github): issue rows from one paged gh call.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$script_dir/../../lib/common.sh"
# shellcheck source=../../lib/tsv.sh
source "$script_dir/../../lib/tsv.sh"
# shellcheck source=_gh.sh
source "$script_dir/_gh.sh"

gh_take_repo "$@"
set -- ${GH_REST[@]+"${GH_REST[@]}"}

state=open
assignee=""
due_before=""
extra=()
while (($#)); do
  case "$1" in
    --state)
      pm_arg2 "$@"
      state="$2"
      shift 2
      ;;
    --label)
      pm_arg2 "$@"
      extra+=(--label "$2")
      shift 2
      ;;
    --milestone)
      pm_arg2 "$@"
      extra+=(--milestone "$2")
      shift 2
      ;;
    --assignee)
      pm_arg2 "$@"
      assignee="$2"
      extra+=(--assignee "$2")
      shift 2
      ;;
    --due-before)
      pm_arg2 "$@"
      due_before="$2"
      shift 2
      ;;
    *) pm_die "list: unsupported argument '$1'" ;;
  esac
done
case "$state" in
  open) gh_state=open ;;
  done) gh_state=closed ;;
  all) gh_state=all ;;
  *) pm_die "list: --state must be open, done or all" ;;
esac

json="$(gh issue list -R "$GH_REPO" --state "$gh_state" --limit "$GH_LIMIT" --json "$GH_FIELDS" ${extra[@]+"${extra[@]}"})"
gh_warn_truncated "$json"

pm_header github "repo=$GH_REPO"
jq -r -f "$script_dir/rows.jq" <<<"$json" | pm_filter_tsv "$state" "$assignee" "$due_before"
```

Run `$T bats $SK/scripts/tests/github.bats` (PASS), shellcheck clean. Commit:

```bash
git add $SK/scripts/backends/github $SK/scripts/tests/fake-gh.sh $SK/scripts/tests/github.bats
git commit -m "feat(project-management): add the github backend list verb"
```

- [ ] **Step 2: `status` (commit 7b)**

Append to `github.bats`:

```bash
@test "status counts, stale, blocked and next" {
  run "${G[@]}" status
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "# backend=github repo=owner/name" ]
  [ "${lines[1]}" = "open=2 done=1 blocked=1 stale=1" ]
  [ "${lines[2]}" = "$(printf 'next\t3\tThird')" ]
}
```

`scripts/backends/github/status.sh`:

```bash
#!/usr/bin/env bash
# pm status (github): counts, stale (open, untouched for 14 days), blocked, next.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$script_dir/../../lib/common.sh"
# shellcheck source=../../lib/tsv.sh
source "$script_dir/../../lib/tsv.sh"
# shellcheck source=_gh.sh
source "$script_dir/_gh.sh"

gh_take_repo "$@"
((${#GH_REST[@]} == 0)) || pm_die "status: unexpected argument '${GH_REST[0]}'"

json="$(gh issue list -R "$GH_REPO" --state all --limit "$GH_LIMIT" --json "$GH_FIELDS")"
gh_warn_truncated "$json"
stale="$(jq -r '[.[] | select(.state == "OPEN" and .updatedAt < (now - 1209600 | strftime("%Y-%m-%dT%H:%M:%SZ")))] | length' <<<"$json")"

pm_header github "repo=$GH_REPO"
jq -r -f "$script_dir/rows.jq" <<<"$json" | pm_status_from_tsv "$stale"
```

Run bats, commit `feat(project-management): add the github backend status verb`.

- [ ] **Step 3: `show` (commit 7c)**

Append to `github.bats`:

```bash
make_view() { # make_view <state> <body-lines>
  jq -n --arg st "$1" --argjson n "$2" '{
    number:1, title:"Set up repo", state:$st, assignees:[{login:"ali"}],
    labels:[{name:"est:30"},{name:"prio:1"}], milestone:{dueOn:"2026-11-01T00:00:00Z"},
    updatedAt:"2020-01-01T00:00:00Z", url:"https://github.com/owner/name/issues/1",
    body:([range(0;$n) | "line \(.+1)"] | join("\n"))
  }' >"$fx/view.json"
}

@test "show prints labelled fields, url and a truncated body" {
  make_view OPEN 30
  run "${G[@]}" show 1
  [ "$status" -eq 0 ]
  [ "${lines[1]}" = "$(printf 'id\t1')" ]
  [ "${lines[2]}" = "$(printf 'state\topen')" ]
  [[ "$output" == *"url"*"https://github.com/owner/name/issues/1"* ]]
  [[ "$output" == *"line 20"* ]]
  [[ "$output" != *"line 21"* ]]
  [[ "$output" == *"truncated (30 lines); use --full"* ]]
}

@test "show --full prints the whole body" {
  make_view OPEN 30
  run "${G[@]}" show 1 --full
  [[ "$output" == *"line 30"* ]]
  [[ "$output" != *"truncated"* ]]
}

@test "show needs a numeric id" {
  run "${G[@]}" show abc
  [ "$status" -eq 1 ]
  [[ "$output" == *"need an issue number"* ]]
}
```

`scripts/backends/github/show.sh`:

```bash
#!/usr/bin/env bash
# pm show <number> [--full] (github): one issue as key<TAB>value lines.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$script_dir/../../lib/common.sh"
# shellcheck source=../../lib/tsv.sh
source "$script_dir/../../lib/tsv.sh"
# shellcheck source=_gh.sh
source "$script_dir/_gh.sh"

readonly BODY_LINES=20

gh_take_repo "$@"
full=0
num=""
for a in ${GH_REST[@]+"${GH_REST[@]}"}; do
  case "$a" in
    --full) full=1 ;;
    -*) pm_die "show: unsupported argument '$a'" ;;
    *) num="$a" ;;
  esac
done
[[ $num =~ ^[0-9]+$ ]] || pm_die "show: need an issue number"

json="$(gh issue view "$num" -R "$GH_REPO" --json "$GH_FIELDS,url")"

pm_header github "repo=$GH_REPO"
jq -c '[.]' <<<"$json" | jq -r -f "$script_dir/rows.jq" | pm_row_to_kv
jq -r '"url\t\(.url)\nupdated\t\(.updatedAt)"' <<<"$json"
echo "body"
body="$(jq -r '.body // ""' <<<"$json")"
if ((full)); then
  printf '%s\n' "$body"
else
  printf '%s\n' "$body" | awk -v n="$BODY_LINES" 'NR <= n'
  total="$(printf '%s\n' "$body" | wc -l | tr -d ' ')"
  if ((total > BODY_LINES)); then
    echo "... truncated ($total lines); use --full"
  fi
fi
```

Run bats, commit `feat(project-management): add the github backend show verb`.

- [ ] **Step 4: `update` (commit 7d)**

Append to `github.bats`:

```bash
@test "update --state done closes an open issue" {
  make_view OPEN 1
  run "${G[@]}" update 1 --state done
  [ "$status" -eq 0 ]
  [ "${lines[1]}" = "updated 1 state=done" ]
  grep -q '^issue close 1 -R owner/name' "$fx/calls.log"
}

@test "update --state done on a closed issue changes nothing" {
  make_view CLOSED 1
  run "${G[@]}" update 1 --state done
  [ "${lines[1]}" = "unchanged 1" ]
  refute_mutated
}

@test "update --state open reopens a closed issue" {
  make_view CLOSED 1
  run "${G[@]}" update 1 --state open
  [ "${lines[1]}" = "updated 1 state=open" ]
  grep -q '^issue reopen 1 -R owner/name' "$fx/calls.log"
}

@test "update adds and removes labels and comments" {
  run "${G[@]}" update 1 --label blocked --unlabel ready --comment "waiting on 2"
  [ "${lines[1]}" = "updated 1 +blocked -ready comment" ]
  grep -q '^issue edit 1 -R owner/name --add-label blocked' "$fx/calls.log"
  grep -q '^issue edit 1 -R owner/name --remove-label ready' "$fx/calls.log"
  grep -q '^issue comment 1 -R owner/name --body waiting on 2' "$fx/calls.log"
}

@test "update needs an id, an action and a valid state" {
  run "${G[@]}" update
  [ "$status" -eq 1 ]
  run "${G[@]}" update 1
  [ "$status" -eq 1 ]
  [[ "$output" == *"nothing to do"* ]]
  run "${G[@]}" update 1 --state bogus
  [ "$status" -eq 1 ]
}
```

`scripts/backends/github/update.sh`:

```bash
#!/usr/bin/env bash
# pm update <number> [--state open|done] [--label L] [--unlabel L] [--comment T] (github).
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$script_dir/../../lib/common.sh"
# shellcheck source=_gh.sh
source "$script_dir/_gh.sh"

gh_take_repo "$@"
set -- ${GH_REST[@]+"${GH_REST[@]}"}

num=""
state=""
comment=""
add=()
del=()
while (($#)); do
  case "$1" in
    --state)
      pm_arg2 "$@"
      state="$2"
      shift 2
      ;;
    --label)
      pm_arg2 "$@"
      add+=("$2")
      shift 2
      ;;
    --unlabel)
      pm_arg2 "$@"
      del+=("$2")
      shift 2
      ;;
    --comment)
      pm_arg2 "$@"
      comment="$2"
      shift 2
      ;;
    -*) pm_die "update: unsupported argument '$1'" ;;
    *)
      num="$1"
      shift
      ;;
  esac
done
[[ $num =~ ^[0-9]+$ ]] || pm_die "update: need an issue number"
case "$state" in
  "" | open | done) ;;
  *) pm_die "update: --state must be open or done" ;;
esac
if [[ -z $state && -z $comment && ${#add[@]} -eq 0 && ${#del[@]} -eq 0 ]]; then
  pm_die "update: nothing to do (give --state, --label, --unlabel or --comment)"
fi

did=()
if [[ -n $state ]]; then
  current="$(gh issue view "$num" -R "$GH_REPO" --json state | jq -r '.state')"
  if [[ $state == done && $current == OPEN ]]; then
    gh issue close "$num" -R "$GH_REPO" >/dev/null
    did+=("state=done")
  elif [[ $state == open && $current == CLOSED ]]; then
    gh issue reopen "$num" -R "$GH_REPO" >/dev/null
    did+=("state=open")
  fi
fi
for l in ${add[@]+"${add[@]}"}; do
  gh issue edit "$num" -R "$GH_REPO" --add-label "$l" >/dev/null
  did+=("+$l")
done
for l in ${del[@]+"${del[@]}"}; do
  gh issue edit "$num" -R "$GH_REPO" --remove-label "$l" >/dev/null
  did+=("-$l")
done
if [[ -n $comment ]]; then
  gh issue comment "$num" -R "$GH_REPO" --body "$comment" >/dev/null
  did+=("comment")
fi

pm_header github "repo=$GH_REPO"
if ((${#did[@]})); then
  echo "updated $num ${did[*]}"
else
  echo "unchanged $num"
fi
```

Run bats, commit `feat(project-management): add the github backend update verb`.

- [ ] **Step 5: `sync-plan` epic mode (commit 7e)**

Fixtures: a speckit-style tasks file under a `NNN-name` directory.

Append to `github.bats`:

```bash
make_spec() {
  spec="$BATS_TEST_TMPDIR/specs/002-demo"
  mkdir -p "$spec"
  cat >"$spec/tasks.md" <<'EOF'
# Tasks
- [X] T001 [P] [US1] Set up repo
- [ ] T002 Write docs
- [ ] T003 [US2] Do thing
EOF
  tasks="$spec/tasks.md"
}

@test "sync-plan dry run plans an epic and mutates nothing" {
  make_spec
  run "${G[@]}" sync-plan "$tasks"
  [ "$status" -eq 0 ]
  [ "${lines[1]}" = "$(printf 'would-create\tepic\tpm:spec-002\t[spec-002] demo')" ]
  refute_mutated
}

@test "sync-plan --apply creates the epic with a task list and the marker" {
  make_spec
  run "${G[@]}" sync-plan "$tasks" --apply
  [ "$status" -eq 0 ]
  [ "${lines[1]}" = "$(printf 'created\tepic\tpm:spec-002\t#99')" ]
  grep -q '^label create pm-epic' "$fx/calls.log"
  grep -q 'issue create -R owner/name --title \[spec-002\] demo --body-file - --label pm-epic' "$fx/calls.log"
  grep -q '^<!-- pm:spec-002 -->$' "$fx/created-body.txt"
  grep -q '^Progress: 1 of 3 done$' "$fx/created-body.txt"
  grep -q '^- \[x\] T001 Set up repo$' "$fx/created-body.txt"
  grep -q '^- \[ \] T002 Write docs$' "$fx/created-body.txt"
}

@test "sync-plan finds the epic by marker and reports exists" {
  make_spec
  "${G[@]}" sync-plan "$tasks" --apply >/dev/null
  jq -n --rawfile b "$fx/created-body.txt" '[{number:99,state:"OPEN",body:$b}]' >"$fx/epics.json"
  : >"$fx/calls.log"
  run "${G[@]}" sync-plan "$tasks" --apply
  [ "${lines[1]}" = "$(printf 'exists\tepic\tpm:spec-002\t#99')" ]
  refute_mutated
}

@test "sync-plan updates the epic body in place when a box changes" {
  make_spec
  "${G[@]}" sync-plan "$tasks" --apply >/dev/null
  jq -n --rawfile b "$fx/created-body.txt" '[{number:99,state:"OPEN",body:$b}]' >"$fx/epics.json"
  sed -i.bak 's/^- \[ \] T002/- [X] T002/' "$tasks"
  : >"$fx/calls.log"
  run "${G[@]}" sync-plan "$tasks"
  [ "${lines[1]}" = "$(printf 'would-update\tepic\tpm:spec-002\t#99')" ]
  refute_mutated
  run "${G[@]}" sync-plan "$tasks" --apply
  [ "${lines[1]}" = "$(printf 'updated\tepic\tpm:spec-002\t#99')" ]
  grep -q '^issue edit 99 -R owner/name --body-file -' "$fx/calls.log"
  grep -q '^- \[x\] T002 Write docs$' "$fx/edited-body.txt"
  refute_logged 'issue create'
}

@test "sync-plan never modifies the input file" {
  make_spec
  before="$(cat "$tasks")"
  "${G[@]}" sync-plan "$tasks" --apply >/dev/null
  [ "$(cat "$tasks")" = "$before" ]
}

@test "sync-plan uses a plan marker outside a numbered spec directory" {
  mkdir -p "$BATS_TEST_TMPDIR/misc"
  printf -- '- [ ] pm:one Do it\n' >"$BATS_TEST_TMPDIR/misc/Launch_Plan.md"
  run "${G[@]}" sync-plan "$BATS_TEST_TMPDIR/misc/Launch_Plan.md"
  [ "${lines[1]}" = "$(printf 'would-create\tepic\tpm:plan-launch-plan\t[plan] launch-plan')" ]
}
```

`scripts/backends/github/sync-plan.sh`:

```bash
#!/usr/bin/env bash
# pm sync-plan <tasks.md> [--apply] [--per-task <ids|all>] (github).
# Default: one epic issue per file, tasks as a GitHub task list, found again
# by a hidden marker. --per-task also tracks chosen tasks as "Tnnn: title"
# issues, the same titles speckit-taskstoissues writes. tasks.md is the
# source of truth: state flows file to issue only. Dry run unless --apply.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/common.sh
source "$script_dir/../../lib/common.sh"
# shellcheck source=../../lib/tasks-md.sh
source "$script_dir/../../lib/tasks-md.sh"
# shellcheck source=_gh.sh
source "$script_dir/_gh.sh"

gh_take_repo "$@"
set -- ${GH_REST[@]+"${GH_REST[@]}"}

apply=0
per_task=""
file=""
while (($#)); do
  case "$1" in
    --apply)
      apply=1
      shift
      ;;
    --per-task)
      pm_arg2 "$@"
      per_task="$2"
      shift 2
      ;;
    -*) pm_die "sync-plan: unsupported argument '$1'" ;;
    *)
      [[ -z $file ]] || pm_die "sync-plan: takes one file"
      file="$1"
      shift
      ;;
  esac
done
[[ -n $file && -f $file ]] || pm_die "sync-plan: need an existing tasks file"
rows="$(tasks_md_tsv "$file")"
[[ -n $rows ]] || pm_die "sync-plan: no task lines found in $file"

emit() { printf '%s\t%s\t%s\t%s\n' "$@"; }

# Identity of the epic: numbered spec directory, else the file name.
abs_dir="$(cd "$(dirname "$file")" && pwd)"
dir_name="$(basename "$abs_dir")"
spec_re='^([0-9]{3})-(.+)$'
if [[ $dir_name =~ $spec_re ]]; then
  marker="pm:spec-${BASH_REMATCH[1]}"
  title="[spec-${BASH_REMATCH[1]}] ${BASH_REMATCH[2]}"
else
  slug="$(basename "$file" .md | tr 'A-Z_ ' 'a-z--')"
  marker="pm:plan-$slug"
  title="[plan] $slug"
fi
top="$(git -C "$abs_dir" rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -n $top && $abs_dir == "$top"/* ]]; then
  rel="${abs_dir#"$top"/}"
else
  rel="$dir_name"
fi

total="$(printf '%s\n' "$rows" | grep -c . || true)"
done_n="$(printf '%s\n' "$rows" | awk -F'\t' '$2 == "done" { n++ } END { print n + 0 }')"
body="$(
  printf '<!-- %s -->\n' "$marker"
  printf 'Source: `%s/%s`\n' "$rel" "$(basename "$file")"
  printf 'Progress: %s of %s done\n\n' "$done_n" "$total"
  printf '%s\n' "$rows" | awk -F'\t' '{ printf "- [%s] %s %s\n", ($2 == "done" ? "x" : " "), $1, $3 }'
)"

# Which tasks get their own issue.
selected=""
if [[ -n $per_task && $per_task != all ]]; then
  for id in $(printf '%s' "$per_task" | tr ',' ' '); do
    printf '%s\n' "$rows" | cut -f1 | grep -qxF "$id" || pm_die "sync-plan: $id is not in $file"
  done
  selected=",$per_task,"
fi

pm_header github "repo=$GH_REPO"

# Epic.
epics="$(gh issue list -R "$GH_REPO" --label pm-epic --state all --limit "$GH_LIMIT" --json number,state,body)"
epic_no="$(jq -r --arg m "<!-- $marker -->" '[.[] | select((.body // "") | contains($m))][0].number // ""' <<<"$epics")"
if [[ -z $epic_no ]]; then
  if ((apply)); then
    gh label create pm-epic -R "$GH_REPO" --description "pm epic" --force >/dev/null
    url="$(printf '%s\n' "$body" | gh issue create -R "$GH_REPO" --title "$title" --body-file - --label pm-epic)"
    emit created epic "$marker" "#${url##*/}"
  else
    emit would-create epic "$marker" "$title"
  fi
else
  current="$(jq -r --arg m "<!-- $marker -->" '[.[] | select((.body // "") | contains($m))][0].body' <<<"$epics" | tr -d '\r')"
  if [[ "$current" == "$body" ]]; then
    emit exists epic "$marker" "#$epic_no"
  elif ((apply)); then
    printf '%s\n' "$body" | gh issue edit "$epic_no" -R "$GH_REPO" --body-file - >/dev/null
    emit updated epic "$marker" "#$epic_no"
  else
    emit would-update epic "$marker" "#$epic_no"
  fi
fi

# Per-task issues.
if [[ -n $per_task ]]; then
  existing="$(gh issue list -R "$GH_REPO" --state all --limit 500 --json number,title,state)"
  while IFS="$(printf '\t')" read -r id st tt _; do
    if [[ $per_task != all && $selected != *",$id,"* ]]; then
      continue
    fi
    hit="$(jq -r --arg id "$id" '[.[] | select(.title | test("^" + $id + "\\b"))][0] | if . then "\(.number) \(.state)" else "" end' <<<"$existing")"
    if [[ -z $hit ]]; then
      if ((apply)); then
        url="$(gh issue create -R "$GH_REPO" --title "$id: $tt" --body "Tracked in $title. Source: $rel/$(basename "$file")" </dev/null)"
        emit created task "$id" "#${url##*/}"
      else
        emit would-create task "$id" "$tt"
      fi
      continue
    fi
    n="${hit%% *}"
    istate="${hit##* }"
    if [[ $st == done && $istate == OPEN ]]; then
      if ((apply)); then
        gh issue close "$n" -R "$GH_REPO" </dev/null >/dev/null
        emit updated task "$id" "#$n closed"
      else
        emit would-update task "$id" "#$n close"
      fi
    elif [[ $st == open && $istate == CLOSED ]]; then
      emit drift task "$id" "issue closed, box open (#$n)"
    else
      emit exists task "$id" "#$n"
    fi
  done <<<"$rows"
fi
```

Run bats. If the "updates the epic body" test fails on `sed -i.bak`, that is the portable BSD/GNU form; keep it and delete the `.bak` file is not needed (temp dir). Commit `feat(project-management): add the github backend epic sync-plan`.

- [ ] **Step 6: `sync-plan` per-task mode (commit 7f)**

Append to `github.bats`:

```bash
per_task_fixture() {
  make_spec
  cat >"$fx/list.json" <<'EOF'
[{"number":10,"title":"T001: Set up repo","state":"OPEN"},
 {"number":11,"title":"T002: Write docs","state":"CLOSED"},
 {"number":12,"title":"T0010: Other thing","state":"OPEN"}]
EOF
}

@test "per-task all: closes finished, flags drift, creates missing (dry run first)" {
  per_task_fixture
  run "${G[@]}" sync-plan "$tasks" --per-task all
  [ "$status" -eq 0 ]
  [ "${lines[2]}" = "$(printf 'would-update\ttask\tT001\t#10 close')" ]
  [ "${lines[3]}" = "$(printf 'drift\ttask\tT002\tissue closed, box open (#11)')" ]
  [ "${lines[4]}" = "$(printf 'would-create\ttask\tT003\tDo thing')" ]
  refute_mutated
}

@test "per-task all --apply performs the changes but leaves drift alone" {
  per_task_fixture
  run "${G[@]}" sync-plan "$tasks" --per-task all --apply
  [ "${lines[2]}" = "$(printf 'updated\ttask\tT001\t#10 closed')" ]
  [ "${lines[3]}" = "$(printf 'drift\ttask\tT002\tissue closed, box open (#11)')" ]
  [ "${lines[4]}" = "$(printf 'created\ttask\tT003\t#99')" ]
  grep -q '^issue close 10 -R owner/name' "$fx/calls.log"
  grep -q 'issue create -R owner/name --title T003: Do thing' "$fx/calls.log"
  refute_logged 'issue reopen'
  refute_logged 'issue close 11'
}

@test "per-task title matching does not confuse T001 with T0010" {
  per_task_fixture
  run "${G[@]}" sync-plan "$tasks" --per-task T001
  [ "${lines[2]}" = "$(printf 'would-update\ttask\tT001\t#10 close')" ]
  [ "${#lines[@]}" -eq 3 ]
}

@test "per-task with an id that is not in the file fails before mutating" {
  per_task_fixture
  run "${G[@]}" sync-plan "$tasks" --per-task T777 --apply
  [ "$status" -eq 1 ]
  [[ "$output" == *"T777 is not in"* ]]
  refute_mutated
}
```

The code from Step 5 already implements this; this step only adds the tests, so they should pass on first run. Run bats; if one fails, fix `sync-plan.sh`, not the test. Commit `test(project-management): cover per-task sync-plan`.

---

### Task 8: Contract suite

**Files:**
- Create: `scripts/tests/contract.bats`

- [ ] **Step 1: Write the suite**

```bash
#!/usr/bin/env bats

# The same checks run against every backend. A backend that drifts from the
# verb contract fails here.

load helpers

setup() {
  pm_setup
  install_fake_gh
  fx="$FAKE_GH_FIXTURES"
  dir="$BATS_TEST_TMPDIR/proj"
  mkdir -p "$dir"
  cat >"$dir/tasks.md" <<'EOF'
- [X] T001 Set up repo owner:ali est:30 prio:1
- [ ] T002 Write docs deps:T001 due:2026-11-01T00:00:00Z
EOF
  cat >"$fx/list.json" <<'EOF'
[{"number":1,"title":"Set up repo","state":"OPEN","assignees":[],"labels":[],"milestone":null,"updatedAt":"2099-01-01T00:00:00Z","body":""},
 {"number":2,"title":"Write docs","state":"CLOSED","assignees":[],"labels":[],"milestone":null,"updatedAt":"2099-01-01T00:00:00Z","body":""}]
EOF
  jq -n '{number:1,title:"Set up repo",state:"OPEN",assignees:[],labels:[],milestone:null,updatedAt:"2099-01-01T00:00:00Z",url:"https://github.com/owner/name/issues/1",body:""}' >"$fx/view.json"
}

# be_args <local|github>: the -b and backend flags for that backend.
be_args() {
  case "$1" in
    local) echo "-b l -d $dir" ;;
    github) echo "-b g -r owner/name" ;;
  esac
}

# sample_id <backend>: an id that exists in that backend's fixture.
sample_id() {
  case "$1" in
    local) echo T002 ;;
    github) echo 1 ;;
  esac
}

check_header() {
  # shellcheck disable=SC2046
  run bash "$pm" $(be_args "$1") list --state all
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == "# backend=$2 "* ]]
}

check_list_columns() {
  # shellcheck disable=SC2046
  run bash "$pm" $(be_args "$1") list --state all
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -ge 2 ]
  printf '%s\n' "$output" | awk -F'\t' '!/^#/ && NF != 8 { bad = 1 } END { exit bad }'
}

check_status() {
  # shellcheck disable=SC2046
  run bash "$pm" $(be_args "$1") status
  [ "$status" -eq 0 ]
  [[ "${lines[1]}" =~ ^open=[0-9]+\ done=[0-9]+\ blocked=[0-9]+\ stale= ]]
}

check_show() {
  # shellcheck disable=SC2046
  run bash "$pm" $(be_args "$1") show "$(sample_id "$1")"
  [ "$status" -eq 0 ]
  local keys
  keys="$(printf '%s\n' "$output" | awk -F'\t' 'NR > 1 && NR <= 9 { printf "%s ", $1 }')"
  [ "$keys" = "id state title owner deps due est prio " ]
}

check_bad_update_flag() {
  # shellcheck disable=SC2046
  run bash "$pm" $(be_args "$1") update "$(sample_id "$1")" --bogus
  [ "$status" -ne 0 ]
}

@test "local: header names the backend" { check_header local local; }
@test "github: header names the backend" { check_header github github; }
@test "local: list rows have 8 columns" { check_list_columns local; }
@test "github: list rows have 8 columns" { check_list_columns github; }
@test "local: status line shape" { check_status local; }
@test "github: status line shape" { check_status github; }
@test "local: show key order" { check_show local; }
@test "github: show key order" { check_show github; }
@test "local: an unknown update flag fails" { check_bad_update_flag local; }
@test "github: an unknown update flag fails" { check_bad_update_flag github; }

@test "the real backends have collision-free aliases" {
  run bash "$scripts_dir/lint-aliases.sh"
  [ "$status" -eq 0 ]
}

@test "every backend implements every verb" {
  local b v
  for b in "$scripts_dir"/backends/*/; do
    for v in status list show update sync-plan; do
      [ -f "$b$v.sh" ] || { echo "missing: $b$v.sh"; return 1; }
    done
  done
}
```

- [ ] **Step 2: Run the whole suite**

Run: `$T bats $SK/scripts/tests`
Expected: all tests PASS (dispatch, lint-aliases, lib, local, github, contract). If a contract test fails, fix the backend, not the test.

- [ ] **Step 3: Commit**

```bash
git add $SK/scripts/tests/contract.bats
git commit -m "test(project-management): run one verb contract against every backend"
```

---

### Task 9: Nix check

**Files:**
- Create: `flake-modules/skills-project-management-tests.nix`

- [ ] **Step 1: Write the module** (haumea auto-discovers it)

```nix
{ self, ... }: {
  # bats suite and alias lint for the project-management skill's pm script.
  # Model-free and network-free (gh is faked). Run with:
  #   nix build .#checks.<system>.skills-project-management
  perSystem = { pkgs, ... }:
    {
      checks.skills-project-management = pkgs.runCommand "skills-project-management"
        {
          nativeBuildInputs = [ pkgs.bats pkgs.jq pkgs.gawk pkgs.coreutils pkgs.git ];
        } ''
        bash ${self + "/home/skills/project-management/scripts/lint-aliases.sh"} \
          ${self + "/home/skills/project-management/scripts/backends"}
        bats ${self + "/home/skills/project-management/scripts"}/tests
        touch $out
      '';
    };
}
```

- [ ] **Step 2: Build the check**

```bash
git add flake-modules/skills-project-management-tests.nix
nix build ".#checks.$(nix eval --raw --impure --expr builtins.currentSystem).skills-project-management" --no-link -L 2>&1 | tail -30
```

Expected: the build succeeds and bats prints all tests as `ok`. The files must be `git add`ed first (flakes only see tracked files). Likely failure: a test relies on something the sandbox lacks (`stat -c` fallback is handled; `sed -i.bak` works with GNU sed). Fix the test or script, not the module.

- [ ] **Step 3: Commit**

```bash
git commit -m "ci(skills): run the project-management bats suite as a flake check"
```

---

### Task 10: Documentation (one commit per file; each adds its routing row)

Each doc below follows the `writing` skill (conclusion first, short paragraphs, no em dashes). After creating a doc, append its row to the `## Routing` table in `SKILL.md`, then run `lint-skills.sh` (it checks the link). The rows, in order:

| Row appended | File |
|---|---|
| `\| Running pm: verbs, columns, flags, token rules, speckit tasks \| [tracking.md](tracking.md) \|` | `tracking.md` |
| `\| Breaking a project into epics and tasks \| [breakdown.md](breakdown.md) \|` | `breakdown.md` |
| `\| Writing a charter, plan, status report or retro \| [docs.md](docs.md) \|` | `docs.md` |
| `\| Using the GitHub backend (labels, milestones, epics, limits) \| [github.md](github.md) \|` | `github.md` |
| `\| Using the local markdown backend \| [local.md](local.md) \|` | `local.md` |

Also, in `SKILL.md` "When to use", replace "(see `tracking.md` once it is routed below)" with "(see [tracking.md](tracking.md))" in the same commit as `tracking.md`.

- [ ] **Step 1: `tracking.md`** (commit `docs(project-management): document pm tracking`)

````markdown
# Tracking with pm

`pm` reads and updates tasks in a tracker through one interface. Name the backend on every call with `-b`.

## Verbs

| Verb | Does | Output |
|---|---|---|
| `status` | counts, blocked, stale, next task | `open=N done=N blocked=N stale=N`, then `next<TAB>id<TAB>title` |
| `list` | task rows | `id state title owner deps due est prio` |
| `show <id>` | one task | `key<TAB>value` lines, then a body (github) |
| `update <id>` | change one task | `updated ...` or `unchanged ...` |
| `sync-plan <file>` | create or update tracker items from a tasks file | `action<TAB>kind<TAB>ref<TAB>detail` |

Every output starts with `# backend=<name> ...`. If that line names the wrong tracker, stop.

## Flags

| Flag | Backend | Meaning |
|---|---|---|
| `-b g` / `--backend github` | all | pick the backend (`l` = local) |
| `-r owner/name` | github | repository |
| `-d <dir>` | local | directory holding `tasks.md` |
| `--state open\|done\|all` | list | default `open` |
| `--assignee`, `--due-before <ISO8601 UTC>` | list | filters |
| `--label`, `--milestone` | list, github only | passed to gh |
| `--state`, `--label`, `--unlabel`, `--comment` | update | local supports `--state` only |
| `--apply` | sync-plan | mutate; without it you get a dry run |
| `--per-task <ids\|all>` | sync-plan, github | also track tasks as `Tnnn: title` issues |
| `--full` | show | whole body instead of 20 lines |

A GitHub issue URL as an argument needs no `-b` or `-r`.

## Reading cheaply

1. `pm status` first. It is one call and often answers the question.
2. `pm list` with filters next. Rows are tab separated and short.
3. `pm show <id>` for one item. Add `--full` only when the body matters.

These reads are mechanical. Hand them to a cheap worker and keep the judgement here.

## Changing things

`update` is idempotent: it checks the current state first and prints `unchanged` if there is nothing to do. `sync-plan` is a dry run until `--apply`, so show the user the dry run before applying to GitHub.

## Spec-kit tasks

A speckit `tasks.md` (`- [ ] T001 [P] [US1] description`) is valid input for both backends.

- `pm -b g -r o/n sync-plan specs/NNN-name/tasks.md --apply` creates or updates one epic issue per spec. Tasks appear as a GitHub task list with a progress count. Re-running edits the epic in place.
- Add `--per-task T003,T007` (or `all`) for tasks that need an assignee or discussion. The titles match `speckit-taskstoissues`, so either tool can run first.
- State flows from the file to the issue, never back. If an issue was closed by hand while its box is open, the output has a `drift` line and nothing changes. Ask the user which side is right.
- `tasks.md` has no dependency field, so speckit tasks never show as blocked.
````

- [ ] **Step 2: `breakdown.md`** (commit `docs(project-management): document the breakdown method`)

````markdown
# Breaking a project down

Turn one project into epics, then tasks small enough to finish in a day. Write the result as a plan file the tracker can ingest.

## Steps

1. **Restate the project in one sentence:** what is wrong today, and for whom. If you cannot, ask before breaking anything down.
2. **Define done.** Two to five outcomes someone could check. These become the epics' acceptance lines.
3. **Cut epics.** At most seven. Each ships something on its own. A code feature that needs a spec is one epic, and it hands off to `/speckit-specify`; do not copy its content here.
4. **Cut tasks** under each epic.
   - Start with a verb. One deliverable each.
   - Aim for 15 to 240 minutes. A task over a day is an epic.
   - Add `est:<minutes>`. Leave it off rather than guess wildly; unestimated tasks are visible in `list`.
   - Add `deps:T001,T002` only for real ordering. Do not chain tasks for neatness.
   - Add `prio:<n>` (1 highest) and `due:<ISO8601 UTC>` only where they differ from the epic.
   - Give each an acceptance line in the plan prose, not in the task line.
5. **Order and check.** Walk the dependency chain. The critical path should be the shortest list you can read aloud. Flag the riskiest task and do it early.
6. **Write it down.** Task lines use the tracker format, so `pm sync-plan` can ingest them:

```
- [ ] T001 [P] Set up the repo est:30 prio:1
- [ ] T002 Write the schema deps:T001 est:90
- [ ] pm:launch-checklist Draft the launch checklist est:60
```

Use `Tnnn` ids inside a speckit feature and `pm:<slug>` for plain plan items. `[P]` marks a task that can run in parallel.

## Sizing guide

| Estimate | Meaning |
|---|---|
| 15 to 60 min | one focused change |
| 60 to 240 min | a task; split if it has two verbs |
| over 240 min | an epic; cut further |

## Red flags

- A task whose title has "and" in it.
- An epic with no outcome you could check.
- Every task depending on the previous one.
- No estimate on the riskiest task.

## Hand-off

Show the user the plan before creating tickets. Then `pm sync-plan <file>` (dry run), then `--apply` once they agree.
````

- [ ] **Step 3: `docs.md`** (commit `docs(project-management): add project document templates`)

````markdown
# Project documents

Four short documents cover a project. Put the conclusion first in each. Lessons that should outlive the project go to `docs/adr/` in the same change.

## Charter

```markdown
# <Project>: charter

**Problem.** One sentence: what is wrong today, and for whom.
**Outcome.** What is true when this is done, checkable.
**Scope.** In: ... Out: ...
**People.** Owner, reviewers, who is told.
**Constraints.** Deadline, budget, tools, rules.
**Risks.** Top three, each with a first mitigation.
**Done when.** The acceptance list.
```

## Plan

```markdown
# <Project>: plan

**Tracker.** Backend and location, for example `pm -b g -r owner/name`.
**Epics.** One line each, with the speckit feature path if there is one.
**Task list.** Task lines in the pm format (see breakdown.md).
**Order.** The critical path in one sentence.
**Dates.** Milestones with ISO8601 UTC dates.
```

## Status report

```markdown
# <Project>: status, <ISO8601 UTC date>

**State.** On track, at risk, or blocked, and why in one sentence.
**Counts.** Paste the `pm status` line.
**Done since last report.** Three bullets at most.
**Next.** The `next` task and the next milestone.
**Blocked.** Each blocker, who can unblock it, since when.
**Asks.** Decisions needed from the reader.
```

Generate the numbers with `pm status`; do not retype them.

## Retro

```markdown
# <Project>: retro

**What happened.** Three sentences.
**What worked.** Keep doing.
**What did not.** Each with the cause, flat, no blame.
**Changes.** Each with an owner. Durable ones become an ADR or a skill edit.
```
````

- [ ] **Step 4: `github.md`** (commit `docs(project-management): document the github backend`)

````markdown
# GitHub backend

Selected with `-b g -r owner/name`. Uses the `gh` CLI, which must be authenticated (`gh auth status`). Issues must be enabled on the repository.

## How fields map

| Column | Source |
|---|---|
| `id` | issue number |
| `state` | `open` for open issues, `done` for closed |
| `owner` | first assignee |
| `deps` | a body line `deps: #12, #14` (stored as `12,14`) |
| `due` | milestone due date |
| `est` | label `est:<minutes>` |
| `prio` | label `prio:<n>` |

`stale` in `status` counts open issues untouched for 14 days.

## Epics

`sync-plan` writes one issue per tasks file, labelled `pm-epic`, with a hidden `<!-- pm:spec-NNN -->` marker as its first line and a task list below it. The marker, not the title, is how the next run finds it, so do not delete the first line. The title is `[spec-NNN] name` for a numbered spec directory and `[plan] name` otherwise.

Per-task issues (`--per-task`) are titled `Tnnn: description`. Matching is by the `Tnnn` prefix, so `T001` never matches `T0010`.

## Limits

- Reads are capped at 200 issues (500 for the per-task lookup). A truncation warning goes to stderr; narrow with `--label`, `--milestone` or `--assignee`.
- Projects v2 fields are not read yet (tracked in PENDING.md).
- `drift` lines mean the issue and `tasks.md` disagree. Nothing is changed; ask the user.

## Failure modes

- `gh: command not found` or `required tool not found: gh`: install it, or use the local backend.
- A 404 from gh on a private repository usually means the token lacks access, not that the repository is missing.
- `issues disabled`: enable Issues in repository settings, or track locally.
````

- [ ] **Step 5: `local.md`** (commit `docs(project-management): document the local backend`)

````markdown
# Local backend

Selected with `-b l -d <dir>`. Tasks live in `<dir>/tasks.md`; no account or network is needed. The directory can be anywhere, including outside a repository.

## Format

The same line format speckit uses, so a speckit feature directory works as `-d` unchanged:

```
- [ ] T001 [P] [US1] Description owner:ali deps:T002,T003 due:2026-11-01T00:00:00Z est:30 prio:2
- [X] pm:launch-checklist Draft the launch checklist
```

- `[ ]` is open, `[X]` is done. `update --state` flips it.
- The id is `T<digits>` or `pm:<slug>`. Lines without one are ignored.
- `[P]` and `[US#]` markers are skipped when reading titles.
- Optional fields anywhere after the id: `owner:`, `deps:`, `due:`, `est:`, `prio:`.

## What it cannot do

- `--label`, `--milestone`, `--comment` and `--unlabel` are not supported and fail with a clear error.
- `stale` is always `n/a` because the file has no timestamps.
- `sync-plan` copies missing task lines from the plan file into `tasks.md` (and creates the file). It has no epic or per-task mode.

## Using it for project docs

Keep `charter.md`, `plan.md` and `status.md` next to `tasks.md` in the same directory so the whole project is one folder.
````

---

### Task 11: ADR and pending items

**Files:**
- Create: `docs/adr/0049-stateless-backend-selection-for-pm.md`
- Modify: `docs/adr/README.md` (add the index line, matching the existing format), `PENDING.md`

- [ ] **Step 1: Read the format**

Run: `sed -n 1,40p docs/adr/README.md` and `sed -n 1,25p docs/adr/0048-*.md`. Match the heading, `Status`, `Date`, `Context`, `Decision`, `Consequences` layout and the README index style exactly.

- [ ] **Step 2: Write the ADR** `0049-stateless-backend-selection-for-pm.md`

Status: Accepted. Date: 2026-10-21. Context: the first design persisted the tracker choice in `.pm.json`, then git config, then an XDG file; the user rejected all three because config cannot be kept in repos or around. A GitHub remote also says nothing about where tickets live. Decision: `pm` holds no state and does no detection. The caller names the backend with `-b` on every call (case-sensitive alias or full name); a ticket URL names its own backend and repo; the skill tells the agent to get the tracker from the user, the repo's instructions, or one question. Backends are directories under `scripts/backends/` with an `alias` file; a dispatcher plus a contract bats suite keeps them uniform. Consequences: each call is a few tokens longer; adding Jira or Linear is purely additive (new directory, new doc, a free alias); a wrong guess is impossible because there is none, and line 1 of every output echoes the resolved target.

Link the spec path. State "Read first: `docs/superpowers/specs/2026-10-21-project-management-skill-design.md`".

- [ ] **Step 3: Add the follow-ups to `PENDING.md`**

Append a section `## project-management skill follow-ups` with: Projects v2 fields for the github backend; Jira and Linear backends (aliases `j`, `L` reserved); the `time-management` sibling skill (prioritise, timebox, calendar backends `ics` first, `google` stubbed, no Google tooling reachable on 2026-10-21); a `draft-from-spec` helper is NOT planned.

- [ ] **Step 4: Verify and commit**

```bash
T='nix shell nixpkgs#bats nixpkgs#jq nixpkgs#yq-go nixpkgs#shellcheck nixpkgs#gawk -c'
$T bash home/skills/skill-authoring/scripts/lint-skills.sh home/skills
git add docs/adr PENDING.md
git commit -m "docs(adr): record stateless backend selection for pm"
```

---

### Task 12: Final verification

- [ ] **Step 1: Everything green**

```bash
T='nix shell nixpkgs#bats nixpkgs#jq nixpkgs#yq-go nixpkgs#shellcheck nixpkgs#gawk -c'
SK=home/skills/project-management
$T bats $SK/scripts/tests
$T shellcheck -x $SK/scripts/pm $SK/scripts/lint-aliases.sh $SK/scripts/lib/*.sh $SK/scripts/backends/*/*.sh
$T bash home/skills/skill-authoring/scripts/lint-skills.sh home/skills
$T bash home/skills/skill-authoring/scripts/check-triggers.sh home/skills
nix build ".#checks.$(nix eval --raw --impure --expr builtins.currentSystem).skills-project-management" --no-link
```

Expected: every command exits 0.

- [ ] **Step 2: Smoke test against the real repo**

```bash
$T bash $SK/scripts/pm -b l -d specs/002-virtual-overview-column status
$T bash $SK/scripts/pm -b l -d specs/002-virtual-overview-column list --state done
```

Expected: a `# backend=local dir=...` header, then counts and rows from the real speckit `tasks.md`. This proves the shared format works on real data. Do not run a GitHub `--apply` as part of verification; only a dry run, and only with the user's go-ahead:

```bash
$T bash $SK/scripts/pm -b g -r alisonjenkins/nix-config sync-plan specs/002-virtual-overview-column/tasks.md
```

- [ ] **Step 3: Confirm commits are atomic**

Run: `git log --oneline origin/main..HEAD`
Expected: one commit per verb or document, none touching unrelated files. Fixups, if any, are autosquashed per the git skill before a PR.

---

## Self-review (spec coverage)

| Spec requirement | Task |
|---|---|
| Family layout, routing table, triggers | 2, 10 |
| Required `-b`, aliases `[A-Za-z]+`, resolution order, error text | 3 |
| URL routing, `PM_BACKEND`, header echo | 3, each verb |
| Alias lint rules (4 checks) | 4, 8 |
| Verb contract, 8-column `list`, `due`/`est`/`prio` | 5, 6, 7, 8 |
| `--due-before` | 5, 6, 7 |
| Local backend on speckit line format, optional fields | 5, 6 |
| GitHub: gh only, 200 cap + warning, labels, milestone, deps line | 7 |
| `sync-plan` dry run default, markers, idempotency, `drift` | 6e, 7e, 7f |
| Epic by default, `--per-task`, one-way truth, `Tnnn` title match | 7e, 7f |
| Contract suite across backends | 8 |
| Portability (bash 3.2, `command -v`, no machine paths) | Global constraints, 3, lint in 12 |
| Docs templates, tracking and backend docs | 10 |
| Nix check | 9 |
| ADR + pending items (Projects v2, Jira, time-management, gcal stub) | 1, 11 |
| Downstream time-management | recorded only (spec, PENDING.md); not built |

Known gaps accepted for v1: Projects v2; `stale` for the local backend (`n/a`); GitHub `show` of pull requests; no `--label`/`--milestone` on the local backend.
