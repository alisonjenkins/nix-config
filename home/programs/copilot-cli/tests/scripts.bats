#!/usr/bin/env bats
# Needs JSON_MERGE, TRUST_PROJECT and TRUST_PARENTS (paths to the scripts from
# ../scripts.nix) in the environment.

setup() {
  dir="$BATS_TEST_TMPDIR"
  echo '{"model":"gpt-x","nested":{"a":1,"b":[1,2]}}' > "$dir/patch.json"
}

# ---- json-merge (settings.json / mcp-config.json) --------------------------

@test "merge: comments and undeclared keys survive, declared keys land" {
  cat > "$dir/s.json" <<'EOF'
{
  // my theme
  "theme": "dark", /* keep */
  "nested": { "a": 0, "z": true },
}
EOF
  run "$JSON_MERGE" "$dir/s.json" "$dir/patch.json"
  [ "$status" -eq 0 ]
  grep -qF '// my theme' "$dir/s.json"
  grep -qF '/* keep */' "$dir/s.json"
  grep -q '"theme": "dark"' "$dir/s.json"
  grep -q '"z": true' "$dir/s.json"
  grep -q '"model": "gpt-x"' "$dir/s.json"
  grep -q '"a": 1' "$dir/s.json"
}

@test "merge: a second run changes nothing" {
  printf '{\n  // c\n  "theme": "dark"\n}\n' > "$dir/s.json"
  "$JSON_MERGE" "$dir/s.json" "$dir/patch.json"
  cp "$dir/s.json" "$dir/once.json"
  "$JSON_MERGE" "$dir/s.json" "$dir/patch.json"
  cmp "$dir/s.json" "$dir/once.json"
}

@test "merge: a missing file is created, including its directory" {
  "$JSON_MERGE" "$dir/new/dir/s.json" "$dir/patch.json"
  grep -q '"model": "gpt-x"' "$dir/new/dir/s.json"
}

@test "merge: an empty file is treated as {}" {
  : > "$dir/s.json"
  "$JSON_MERGE" "$dir/s.json" "$dir/patch.json"
  grep -q '"model": "gpt-x"' "$dir/s.json"
}

@test "merge: a file holding only comments keeps them and gets the patch" {
  printf '// only a comment\n' > "$dir/s.json"
  "$JSON_MERGE" "$dir/s.json" "$dir/patch.json"
  grep -qF '// only a comment' "$dir/s.json"
  grep -q '"model": "gpt-x"' "$dir/s.json"
}

@test "merge: a leading BOM is kept and the file is still patched" {
  printf '\xef\xbb\xbf{"a":1}\n' > "$dir/s.json"
  "$JSON_MERGE" "$dir/s.json" "$dir/patch.json"
  [ "$(head -c 3 "$dir/s.json" | od -An -tx1 | tr -d ' ')" = efbbbf ]
  grep -q '"model": "gpt-x"' "$dir/s.json"
}

@test "merge: a tab-indented file stays tab-indented" {
  printf '{\n\t"a": 1\n}\n' > "$dir/s.json"
  "$JSON_MERGE" "$dir/s.json" "$dir/patch.json"
  [ -z "$(grep '^  ' "$dir/s.json")" ]
  grep -qP '^\t"model"' "$dir/s.json"
}

@test "merge: invalid JSONC is left untouched with a warning and exit 0" {
  echo '{ "a": ' > "$dir/s.json"
  run "$JSON_MERGE" "$dir/s.json" "$dir/patch.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"not updating"* ]]
  [ "$(cat "$dir/s.json")" = '{ "a": ' ]
  [ -z "$(ls "$dir" | grep tmp || true)" ]
}

@test "merge: an unwritable directory warns and exits 0" {
  [ "$(id -u)" -ne 0 ] || skip "root ignores directory permissions"
  mkdir "$dir/ro"; echo '{}' > "$dir/ro/s.json"; chmod 555 "$dir/ro"
  run "$JSON_MERGE" "$dir/ro/s.json" "$dir/patch.json"
  chmod 755 "$dir/ro"
  [ "$status" -eq 0 ]
  [[ "$output" == *"not updating"* ]]
}

# ---- trust-project (permissions-config.json) -------------------------------

@test "trust-project: dirs and commands are unioned across existing entries" {
  cat > "$dir/p.json" <<'EOF'
{"locations":{"/p":{"allowed_directories":["/old"],"tool_approvals":[
  {"kind":"commands","commandIdentifiers":["a"]},
  {"kind":"read"},
  {"kind":"commands","commandIdentifiers":["b"]}]}}}
EOF
  "$TRUST_PROJECT" "$dir/p.json" /p /new -- 'gh pr view:*'
  run jq -c '.locations["/p"] | [.allowed_directories, (.tool_approvals | map(select(.kind=="commands")) | length), (.tool_approvals[0].commandIdentifiers), (.tool_approvals | map(.kind))]' "$dir/p.json"
  [ "$output" = '[["/new","/old"],1,["a","b","gh pr view:*"],["commands","read"]]' ]
}

@test "trust-project: an empty or missing file is seeded" {
  : > "$dir/empty.json"
  "$TRUST_PROJECT" "$dir/empty.json" /p /d -- 'x:*'
  [ "$(jq -c '.locations["/p"].allowed_directories' "$dir/empty.json")" = '["/d"]' ]
  "$TRUST_PROJECT" "$dir/none/p.json" /p /d -- 'x:*'
  [ "$(jq -c '.locations["/p"].allowed_directories' "$dir/none/p.json")" = '["/d"]' ]
}

@test "trust-project: invalid JSON is left untouched with a warning and exit 0" {
  echo '{ nope' > "$dir/p.json"
  run "$TRUST_PROJECT" "$dir/p.json" /p /d -- 'x:*'
  [ "$status" -eq 0 ]
  [[ "$output" == *"not updating"* ]]
  [ "$(cat "$dir/p.json")" = '{ nope' ]
}

# ---- trust-parents ---------------------------------------------------------

keys() { jq -c '.locations | keys' "$1" | sed "s#$dir#D#g"; }

@test "parents: only git repos under a parent are trusted" {
  mkdir -p "$dir/org/repo/.git" "$dir/org/downloads"
  printf '%s\n' "$dir/org" > "$dir/parents"
  "$TRUST_PARENTS" "$dir/p.json" "$dir/parents" "" /skills -- 'gh pr view:*'
  [ "$(keys "$dir/p.json")" = '["D/org/repo"]' ]
}

@test "parents: an unterminated last line and a trailing slash both work" {
  mkdir -p "$dir/org/repo/.git"
  printf '%s/' "$dir/org" > "$dir/parents"
  "$TRUST_PARENTS" "$dir/p.json" "$dir/parents" "" /skills -- 'gh pr view:*'
  [ "$(keys "$dir/p.json")" = '["D/org/repo"]' ]
}

@test "parents: discovery finds groups of repos, not repos or plain dirs" {
  mkdir -p "$dir/git/grp/repo/.git" "$dir/git/solo/.git" "$dir/git/plain/sub"
  "$TRUST_PARENTS" "$dir/p.json" "$dir/absent" "$dir/git" /skills -- 'gh pr view:*'
  [ "$(keys "$dir/p.json")" = '["D/git/grp/repo"]' ]
}

@test "parents: nothing to trust leaves the file uncreated" {
  "$TRUST_PARENTS" "$dir/p.json" "$dir/absent" "$dir/none" /skills -- 'gh pr view:*'
  [ ! -e "$dir/p.json" ]
}

@test "parents: an invalid permissions file is left untouched" {
  mkdir -p "$dir/org/repo/.git"
  printf '%s\n' "$dir/org" > "$dir/parents"
  echo '{ nope' > "$dir/p.json"
  run "$TRUST_PARENTS" "$dir/p.json" "$dir/parents" "" /skills -- 'gh pr view:*'
  [ "$status" -eq 0 ]
  [ "$(cat "$dir/p.json")" = '{ nope' ]
}
