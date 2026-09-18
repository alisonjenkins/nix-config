#!/usr/bin/env bats

setup() {
  script_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  script="$script_dir/../reply-threads.sh"
  export PATH="$script_dir:$PATH"
  export FAKE_GH_FIXTURES="$BATS_TEST_TMPDIR/fixtures"
  mkdir -p "$FAKE_GH_FIXTURES"
}

@test "too many args prints usage and exits 1" {
  run "$script" file1 file2
  [ "$status" -eq 1 ]
  [[ "$output" == *"usage:"* ]]
}

@test "missing input file errors clearly" {
  run "$script" "$BATS_TEST_TMPDIR/does-not-exist.tsv"
  [ "$status" -eq 1 ]
  [[ "$output" == *"input file not found"* ]]
}

@test "empty input reports nothing to do and makes no call" {
  run "$script" <<<""
  [ "$status" -eq 0 ]
  [[ "$output" == *"no threads to reply to"* ]]
  [ ! -f "$FAKE_GH_FIXTURES/graphql-reply-capture.txt" ]
}

@test "invalid resolve column errors clearly, before any call" {
  run "$script" <<<"$(printf 'THREAD_1\tmaybe\tsome body')"
  [ "$status" -eq 1 ]
  [[ "$output" == *"resolve column must be 'yes' or 'no'"* ]]
  [ ! -f "$FAKE_GH_FIXTURES/graphql-reply-capture.txt" ]
}

@test "a single reply without resolving builds one reply alias and no resolve alias" {
  run "$script" <<<"$(printf 'THREAD_1\tno\tfix applied')"
  [ "$status" -eq 0 ]
  [[ "$output" == *"replied to 1 thread(s)"* ]]
  [[ "$output" != *"resolved"* ]]
  run cat "$FAKE_GH_FIXTURES/graphql-reply-capture.txt"
  [[ "$output" == *"r0: addPullRequestReviewThreadReply"* ]]
  [[ "$output" != *"resolveReviewThread"* ]]
  [[ "$output" == *"t0=THREAD_1"* ]]
  [[ "$output" == *"b0=fix applied"* ]]
}

@test "a single reply with resolve=yes also builds a resolve alias" {
  run "$script" <<<"$(printf 'THREAD_1\tyes\tfix applied')"
  [ "$status" -eq 0 ]
  [[ "$output" == *"replied to 1 thread(s)"* ]]
  [[ "$output" == *"resolved 1 of them"* ]]
  run cat "$FAKE_GH_FIXTURES/graphql-reply-capture.txt"
  [[ "$output" == *"r0: addPullRequestReviewThreadReply"* ]]
  [[ "$output" == *"s0: resolveReviewThread"* ]]
}

@test "a whole wave of threads is one call with one aliased mutation field per thread" {
  input="$(printf 'THREAD_1\tyes\tfirst reply\nTHREAD_2\tno\tsecond reply\nTHREAD_3\tyes\tthird reply')"
  run "$script" <<<"$input"
  [ "$status" -eq 0 ]
  [[ "$output" == *"replied to 3 thread(s)"* ]]
  [[ "$output" == *"resolved 2 of them"* ]]
  run cat "$FAKE_GH_FIXTURES/graphql-reply-capture.txt"
  [[ "$output" == *"r0: addPullRequestReviewThreadReply"* ]]
  [[ "$output" == *"r1: addPullRequestReviewThreadReply"* ]]
  [[ "$output" == *"r2: addPullRequestReviewThreadReply"* ]]
  [[ "$output" == *"s0: resolveReviewThread"* ]]
  [[ "$output" != *"s1: resolveReviewThread"* ]]
  [[ "$output" == *"s2: resolveReviewThread"* ]]
  [[ "$output" == *"t1=THREAD_2"* ]]
  [[ "$output" == *"b1=second reply"* ]]
}

@test "reads from a file argument as well as stdin" {
  printf 'THREAD_1\tno\tfrom a file\n' >"$BATS_TEST_TMPDIR/input.tsv"
  run "$script" "$BATS_TEST_TMPDIR/input.tsv"
  [ "$status" -eq 0 ]
  [[ "$output" == *"replied to 1 thread(s)"* ]]
}

@test "an outright GraphQL failure exits nonzero and says so" {
  touch "$FAKE_GH_FIXTURES/graphql-reply-fails"
  run "$script" <<<"$(printf 'THREAD_1\tno\tfix applied')"
  [ "$status" -eq 1 ]
  [[ "$output" == *"nothing in this batch landed"* ]]
}

@test "a 200 response with a partial errors field is treated as a failure, not silently accepted" {
  touch "$FAKE_GH_FIXTURES/graphql-reply-partial-errors"
  run "$script" <<<"$(printf 'THREAD_1\tno\tfix applied')"
  [ "$status" -eq 1 ]
  [[ "$output" == *"partial errors"* ]]
}
