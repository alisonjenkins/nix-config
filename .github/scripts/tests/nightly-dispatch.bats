#!/usr/bin/env bats
# Tests for .github/scripts/nightly-dispatch.sh. `curl` is a stub on PATH: it
# records its arguments and stdin config, writes $STUB_BODY to --output, and
# prints $STUB_STATUS as the HTTP code (or fails when STUB_CURL_FAIL is set).
#
# Run from repo root:
#   nix run nixpkgs#bats -- .github/scripts/tests/nightly-dispatch.bats

SCRIPT="${BATS_TEST_DIRNAME}/../nightly-dispatch.sh"

setup() {
  WORK="$(mktemp -d)"
  mkdir -p "$WORK/bin"
  cat >"$WORK/bin/curl" <<EOF
#!$BASH
printf '%s\n' "\$@" >"\$WORK/curl.args"
cat >"\$WORK/curl.config"
[ -z "\${STUB_CURL_FAIL:-}" ] || { echo "curl: (6) Could not resolve host" >&2; exit 6; }
out=""
prev=""
for a in "\$@"; do
  if [ "\$prev" = --output ]; then out="\$a"; fi
  prev="\$a"
done
printf '%s' "\${STUB_BODY:-}" >"\$out"
printf '%s' "\${STUB_STATUS:-204}"
EOF
  chmod +x "$WORK/bin/curl"
  printf 'github_pat_secret\n' >"$WORK/token"
  export PATH="$WORK/bin:$PATH" WORK TOKEN_FILE="$WORK/token"
}

teardown() {
  rm -rf "$WORK"
}

@test "dispatches update.yaml on main and reports success" {
  run "$BASH" "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"started update.yaml on alisonjenkins/nix-config@main"* ]]
  grep -qxF "https://api.github.com/repos/alisonjenkins/nix-config/actions/workflows/update.yaml/dispatches" "$WORK/curl.args"
  grep -qxF '{"ref":"main"}' "$WORK/curl.args"
  grep -qxF POST "$WORK/curl.args"
}

@test "the token is passed on stdin, never in argv" {
  run "$BASH" "$SCRIPT"
  grep -qF 'header = "Authorization: Bearer github_pat_secret"' "$WORK/curl.config"
  ! grep -qF github_pat_secret "$WORK/curl.args"
}

@test "repo, workflow, ref and API URL can be overridden" {
  REPO=o/r WORKFLOW=w.yaml REF=dev API_URL=http://api run "$BASH" "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -qxF "http://api/repos/o/r/actions/workflows/w.yaml/dispatches" "$WORK/curl.args"
  grep -qxF '{"ref":"dev"}' "$WORK/curl.args"
}

@test "each refusal names its likely cause and shows GitHub's message" {
  for case in "401:has expired" "403:Actions: read and write" "404:was not found" "422:workflow_dispatch trigger" "500:unexpected response"; do
    code="${case%%:*}"
    want="${case#*:}"
    STUB_STATUS="$code" STUB_BODY='{"message":"nope"}' run "$BASH" "$SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"GitHub answered HTTP $code"*"$want"* ]]
    [[ "$output" == *'response: {"message":"nope"}'* ]]
  done
}

@test "an unreachable API exits 2" {
  STUB_CURL_FAIL=1 run "$BASH" "$SCRIPT"
  [ "$status" -eq 2 ]
  [[ "$output" == *"could not reach https://api.github.com"* ]]
}

@test "a missing or empty token file exits 2 and names the file" {
  TOKEN_FILE="$WORK/nope" run "$BASH" "$SCRIPT"
  [ "$status" -eq 2 ]
  [[ "$output" == *"cannot read the token file $WORK/nope"* ]]
  : >"$WORK/token"
  run "$BASH" "$SCRIPT"
  [ "$status" -eq 2 ]
  [[ "$output" == *"is empty"* ]]
  [ ! -e "$WORK/curl.args" ]
}

@test "TOKEN_FILE unset is named" {
  unset TOKEN_FILE
  run "$BASH" "$SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"TOKEN_FILE (path to the dispatch token) is not set"* ]]
}
