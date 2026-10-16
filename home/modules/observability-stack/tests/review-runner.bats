#!/usr/bin/env bats
# The weekly review runner (ADR 0037): stage 1 builds the digest with a low-cost model,
# falling back to `cc-obs-query digest --baseline`; stage 2 turns the digest into a
# findings file. `claude` and `cc-obs-query` are fakes that record their arguments and
# environment; no model is ever called. RUNNER is the path of observability-stack-review.

setup() {
  work="$(mktemp -d)"
  mkdir -p "$work/bin" "$work/repo"
  export REVIEW_STATE_DIR="$work/state"
  export REVIEW_NOW="2026-10-16T06:00:00Z"
  export REVIEW_PACK="$work/questions.yaml"
  export REVIEW_DIGEST_MODEL=digest-model
  export REVIEW_ANALYSIS_MODEL=analysis-model
  export REVIEW_BUDGET_DIGEST=0.25
  export REVIEW_BUDGET_ANALYSIS=2
  : > "$REVIEW_PACK"

  calls="$work/calls"
  : > "$calls"
  export CALLS="$calls"
  export STAGE2_STDIN="$work/stage2-stdin"

  cat > "$work/claude" <<'FAKE'
#!/bin/sh
model=""
args=""
touch stray-from-claude
while [ $# -gt 0 ]; do
  [ "$1" = "--model" ] && model="$2"
  args="$args [$1]"
  shift
done
args="$(echo "$args" | tr '\n' ' ')"
echo "claude model=$model otel=${OTEL_RESOURCE_ATTRIBUTES:-} args=$args" >> "$CALLS"
if [ "$model" = digest-model ]; then
  [ -n "${STAGE1_EXIT:-}" ] && { echo '{"is_error":true,"total_cost_usd":0.25,"result":"budget"}'; exit "$STAGE1_EXIT"; }
  digest="$(printf '{"stage1":"model","host":"%s","period":{"start":"2026-10-09T06:00:00Z","end":"%s"},"pack":{"version":1}}' "${DIGEST_HOST:-fake-host}" "$REVIEW_NOW")"
  jq -n --arg r "$digest" '{is_error:false,total_cost_usd:0.1,result:("```json\n" + $r + "\n```")}'
else
  cat > "$STAGE2_STDIN"
  [ -n "${STAGE2_EXIT:-}" ] && { echo '{"is_error":true,"total_cost_usd":2,"result":"budget"}'; exit "$STAGE2_EXIT"; }
  finding='## 1. Trim Read results - est. saving 12k tokens/week (4%)
Evidence: tool=Read. Suggested action: configure. Status: proposed'
  case "${STAGE2_RESULT:-ok}" in
    ok) jq -n --arg r "$finding" '{is_error:false,total_cost_usd:0.2,result:$r}' ;;
    empty) echo '{"is_error":false,"total_cost_usd":0.2,"result":""}' ;;
    null) echo '{"is_error":false,"total_cost_usd":0.2,"result":null}' ;;
    prose) echo '{"is_error":false,"total_cost_usd":0.2,"result":"Sure, here are my thoughts."}' ;;
    big) jq -n --arg r "$finding $(head -c 20000 /dev/zero | tr '\0' x)" '{is_error:false,total_cost_usd:0.2,result:$r}' ;;
    many) jq -n --arg r "$(for n in 1 2 3 4 5 6; do printf '## %s. Finding %s\nEvidence: x.\n' "$n" "$n"; done)" '{is_error:false,total_cost_usd:0.2,result:$r}' ;;
  esac
fi
FAKE
  chmod +x "$work/claude"
  export REVIEW_CLAUDE="$work/claude"

  cat > "$work/bin/cc-obs-query" <<'FAKE'
#!/bin/sh
echo "query $*" >> "$CALLS"
mode="$2"; file=""; out=""
shift 1
while [ $# -gt 0 ]; do
  case "$1" in
    --write) file="$2"; shift ;;
    --out) out="$2"; shift ;;
  esac
  shift
done
if [ "$mode" = "--baseline" ]; then
  [ -n "${BASELINE_FAIL:-}" ] && exit 1
  printf '{"stage1":"baseline","host":"%s","period":{"start":"x","end":"%s"},"pack":{"version":1}}' "${DIGEST_HOST:-fake-host}" "$REVIEW_NOW" > "$out"
else
  [ -n "${WRITE_FAIL:-}" ] && { echo '{"error":"schema"}'; exit 1; }
  cp "$file" "$out"
fi
echo '{"valid":true}'
FAKE
  chmod +x "$work/bin/cc-obs-query"
  export REVIEW_QUERY="$work/bin/cc-obs-query"
  cd "$work/repo"
  git init -q .
}

teardown() {
  rm -rf "$work"
}

digest_file() { ls "$REVIEW_STATE_DIR"/digests/*.json; }

@test "stage 1 then stage 2 run in order with their models and budgets" {
  run "$RUNNER"
  [ "$status" -eq 0 ]
  claude_lines="$(grep '^claude' "$calls")"
  [ "$(echo "$claude_lines" | wc -l)" -eq 2 ]
  echo "$claude_lines" | sed -n 1p | grep -qF 'model=digest-model'
  echo "$claude_lines" | sed -n 1p | grep -qF -- '[--max-budget-usd] [0.25]'
  echo "$claude_lines" | sed -n 2p | grep -qF 'model=analysis-model'
  echo "$claude_lines" | sed -n 2p | grep -qF -- '[--max-budget-usd] [2]'
}

@test "each stage runs without settings, MCP or slash commands" {
  run "$RUNNER"
  [ "$status" -eq 0 ]
  [ "$(grep -c '^claude' "$calls")" -eq 2 ]
  for flag in '[--setting-sources] []' '[--strict-mcp-config]' '[--disable-slash-commands]' '[--output-format] [json]'; do
    [ "$(grep '^claude' "$calls" | grep -cF -- "$flag")" -eq 2 ]
  done
}

@test "stage 1 may only use Bash, limited to the cc-obs-query subcommands it needs" {
  run "$RUNNER"
  [ "$status" -eq 0 ]
  stage1="$(grep '^claude model=digest-model' "$calls")"
  echo "$stage1" | grep -qF -- '[--tools] [Bash]'
  echo "$stage1" | grep -qF -- '[--allowedTools] [Bash(cc-obs-query digest --baseline:*),Bash(cc-obs-query top:*),Bash(cc-obs-query tool:*),Bash(cc-obs-query session:*),Bash(cc-obs-query repeats:*)]'
}

@test "stage 2 has no tools at all" {
  run "$RUNNER"
  [ "$status" -eq 0 ]
  grep '^claude model=analysis-model' "$calls" | grep -qF -- '[--tools] []'
}

@test "each stage carries review.run=1 in OTEL_RESOURCE_ATTRIBUTES" {
  run "$RUNNER"
  [ "$status" -eq 0 ]
  [ "$(grep '^claude' "$calls" | grep -c 'otel=review.run=1 ')" -eq 2 ]
}

@test "an existing OTEL_RESOURCE_ATTRIBUTES is kept and review.run=1 appended" {
  OTEL_RESOURCE_ATTRIBUTES="host=h1" run "$RUNNER"
  [ "$status" -eq 0 ]
  [ "$(grep '^claude' "$calls" | grep -c 'otel=host=h1,review.run=1 ')" -eq 2 ]
}

@test "the validated stage 1 digest is kept and stage 2 reads only it" {
  run "$RUNNER"
  [ "$status" -eq 0 ]
  grep -q 'query digest --write' "$calls"
  [ "$(jq -r .stage1 "$(digest_file)")" = model ]
  [ "$(jq -r .stage1 "$STAGE2_STDIN")" = model ]
}

@test "the findings file has front matter with both stages' cost and the stage 2 body" {
  run "$RUNNER"
  [ "$status" -eq 0 ]
  f="$(ls "$REVIEW_STATE_DIR"/findings/*.md)"
  [ "$(basename "$f")" = "2026-10-16-fake-host.md" ]
  [ "$(sed -n 1p "$f")" = "---" ]
  grep -qx 'review: 2026-10-16-fake-host' "$f"
  grep -qx 'host: fake-host' "$f"
  grep -qx 'pack_version: 1' "$f"
  grep -qx 'own_cost_usd: 0.3' "$f"
  grep -q '^period: .*/2026-10-16' "$f"
  grep -q '^## 1\. Trim Read results' "$f"
}

@test "a stage 1 failure at the budget ceiling falls back to the baseline digest" {
  STAGE1_EXIT=1 run "$RUNNER"
  [ "$status" -eq 0 ]
  grep -q 'query digest --baseline' "$calls"
  [ "$(jq -r .stage1 "$(digest_file)")" = baseline ]
  [ "$(grep -c '^claude model=analysis-model' "$calls")" -eq 1 ]
}

@test "a digest that fails validation falls back to the baseline digest" {
  WRITE_FAIL=1 run "$RUNNER"
  [ "$status" -eq 0 ]
  [ "$(jq -r .stage1 "$(digest_file)")" = baseline ]
}

@test "a stage 2 failure leaves a failure record and no findings file" {
  STAGE2_EXIT=1 run "$RUNNER"
  [ "$status" -ne 0 ]
  f="$(ls "$REVIEW_STATE_DIR"/failures/*.json)"
  [ "$(jq -r .stage "$f")" = analysis ]
  [ "$(jq -r .exit "$f")" = 1 ]
  [ "$(jq -r .at "$f")" = "$REVIEW_NOW" ]
  [ ! -e "$REVIEW_STATE_DIR/findings" ] || [ -z "$(ls "$REVIEW_STATE_DIR/findings")" ]
}

@test "a baseline that also fails leaves a failure record for the digest stage" {
  STAGE1_EXIT=1 BASELINE_FAIL=1 run "$RUNNER"
  [ "$status" -ne 0 ]
  [ "$(jq -r .stage "$(ls "$REVIEW_STATE_DIR"/failures/*.json)")" = digest ]
  [ "$(grep -c '^claude model=analysis-model' "$calls")" -eq 0 ]
}

@test "the first run covers a week" {
  run "$RUNNER"
  [ "$status" -eq 0 ]
  grep -q -- '--since 7d' "$calls"
}

seed_findings() {
  # seed_findings <start>/<end> : a findings file covering that period
  mkdir -p "$REVIEW_STATE_DIR/findings"
  printf -- '---\nreview: seeded\nperiod: %s\n---\n## 1. Seeded\n' "$1" > "$REVIEW_STATE_DIR/findings/${1#*/}-fake-host.md"
}

@test "a missed period is covered by the next run" {
  seed_findings 2026-09-18/2026-09-25
  run "$RUNNER"
  [ "$status" -eq 0 ]
  grep -q -- '--since 21d' "$calls"
  [[ "$output" == *event=review_catchup* ]]
}

@test "a recent findings file does not shrink the window below a week" {
  seed_findings 2026-10-06/2026-10-13
  run "$RUNNER"
  [ "$status" -eq 0 ]
  grep -q -- '--since 7d' "$calls"
  ! grep -q -- '--since 3d' "$calls"
}

@test "a week whose stage 2 failed is covered again by the next run" {
  seed_findings 2026-10-02/2026-10-09
  STAGE2_EXIT=1 run "$RUNNER"
  [ "$status" -ne 0 ]
  [ -n "$(ls "$REVIEW_STATE_DIR"/digests)" ]
  REVIEW_NOW="2026-10-23T06:00:00Z" run "$RUNNER"
  [ "$status" -eq 0 ]
  grep -q -- '--since 14d' "$calls"
}

@test "stage 1 spend still counts when it fell back to the baseline" {
  STAGE1_EXIT=1 run "$RUNNER"
  [ "$status" -eq 0 ]
  grep -qx 'own_cost_usd: 0.45' "$REVIEW_STATE_DIR"/findings/*.md
}

@test "a stage cannot write into the directory the runner was started from" {
  run "$RUNNER"
  [ "$status" -eq 0 ]
  [ "$(grep -c '^claude' "$calls")" -eq 2 ]
  [ -z "$(git status --porcelain --ignored)" ]
  [ -z "$(find "$work/repo" -mindepth 1 -not -path '*/.git' -not -path '*/.git/*')" ]
}

@test "stage 2 output that is empty, null or prose is a failure and writes no findings" {
  for mode in empty null prose; do
    rm -rf "$REVIEW_STATE_DIR"
    STAGE2_RESULT=$mode run "$RUNNER"
    [ "$status" -ne 0 ]
    [ "$(jq -r .stage "$(ls "$REVIEW_STATE_DIR"/failures/*.json)")" = analysis ]
    [ ! -e "$REVIEW_STATE_DIR/findings" ] || [ -z "$(ls "$REVIEW_STATE_DIR/findings")" ]
  done
}

@test "stage 2 output over the byte limit is a failure" {
  STAGE2_RESULT=big run "$RUNNER"
  [ "$status" -ne 0 ]
  [ "$(jq -r .stage "$(ls "$REVIEW_STATE_DIR"/failures/*.json)")" = analysis ]
  [ -z "$(ls "$REVIEW_STATE_DIR/findings" 2>/dev/null)" ]
}

@test "stage 2 output with more than five findings is a failure" {
  STAGE2_RESULT=many run "$RUNNER"
  [ "$status" -ne 0 ]
  [ "$(jq -r .stage "$(ls "$REVIEW_STATE_DIR"/failures/*.json)")" = analysis ]
  [ -z "$(ls "$REVIEW_STATE_DIR/findings" 2>/dev/null)" ]
}

@test "a digest host that is not a safe file name is rejected before anything is saved" {
  for host in '../../escape' 'a/b' '..' '.hidden'; do
    rm -rf "$REVIEW_STATE_DIR"
    DIGEST_HOST=$host run "$RUNNER"
    [ "$status" -ne 0 ]
    [ "$(jq -r .stage "$(ls "$REVIEW_STATE_DIR"/failures/*.json)")" = digest ]
    [ -z "$(ls "$REVIEW_STATE_DIR/digests")" ]
    [ ! -e "$work/escape.json" ]
  done
}

@test "with no claude command only the baseline digest is built" {
  REVIEW_CLAUDE="" run "$RUNNER"
  [ "$status" -eq 0 ]
  [ "$(jq -r .stage1 "$(digest_file)")" = baseline ]
  [ "$(grep -c '^claude' "$calls")" -eq 0 ]
  [ ! -e "$REVIEW_STATE_DIR/findings" ] || [ -z "$(ls "$REVIEW_STATE_DIR/findings")" ]
}
