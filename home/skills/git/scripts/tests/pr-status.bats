#!/usr/bin/env bats

setup() {
  script_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  script="$script_dir/../pr-status.sh"
  export PATH="$script_dir:$PATH"
  export FAKE_GH_FIXTURES="$BATS_TEST_TMPDIR/fixtures"
  mkdir -p "$FAKE_GH_FIXTURES"
  cat >"$FAKE_GH_FIXTURES/pr-status.json" <<'EOF'
{"data":{"repository":{"pullRequest":{
  "state":"OPEN","isDraft":false,"headRefOid":"abcdef1234567890",
  "reviewDecision":null,"mergeable":"MERGEABLE","mergeStateStatus":"CLEAN",
  "autoMergeRequest":null,
  "commits":{"nodes":[{"commit":{"statusCheckRollup":{"state":"SUCCESS"}}}]},
  "reviewRequests":{"nodes":[]},
  "latestReviews":{"nodes":[{"author":{"login":"someone"},"state":"COMMENTED",
    "submittedAt":"2026-01-01T00:00:00Z","commit":{"oid":"abcdef1234567890"},
    "body":"### verdict"}]},
  "reviews":{"nodes":[{"body":"### verdict"}]},
  "reviewThreads":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[]}
}}}}
EOF
}

@test "no args prints usage and exits 1" {
  run "$script"
  [ "$status" -eq 1 ]
  [[ "$output" == *"usage:"* ]]
}

@test "non-numeric pr number errors clearly" {
  run "$script" not-a-number owner/repo
  [ "$status" -eq 1 ]
  [[ "$output" == *"must be numeric"* ]]
}

@test "rejects owner/repo with no slash" {
  run "$script" 1 ownerrepo
  [ "$status" -eq 1 ]
  [[ "$output" == *"must be exactly 'owner/repo'"* ]]
}

@test "prints a compact status line with checks, reviewDecision, mergeable, mergeStateStatus" {
  run "$script" 1 owner/repo
  [ "$status" -eq 0 ]
  [[ "$output" == *"state=OPEN"* ]]
  [[ "$output" == *"head=abcdef12"* ]]
  [[ "$output" == *"reviewDecision=null"* ]]
  [[ "$output" == *"mergeable=MERGEABLE"* ]]
  [[ "$output" == *"mergeStateStatus=CLEAN"* ]]
  [[ "$output" == *"autoMerge=false"* ]]
  [[ "$output" == *"checks=SUCCESS"* ]]
}

@test "reports NONE checks state when there's no statusCheckRollup at all" {
  cat >"$FAKE_GH_FIXTURES/pr-status.json" <<'EOF'
{"data":{"repository":{"pullRequest":{
  "state":"OPEN","isDraft":false,"headRefOid":"abcdef1234567890",
  "reviewDecision":null,"mergeable":"MERGEABLE","mergeStateStatus":"CLEAN",
  "autoMergeRequest":null,
  "commits":{"nodes":[{"commit":{"statusCheckRollup":null}}]},
  "reviewRequests":{"nodes":[]},
  "latestReviews":{"nodes":[]},
  "reviews":{"nodes":[]},
  "reviewThreads":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[]}
}}}}
EOF
  run "$script" 1 owner/repo
  [ "$status" -eq 0 ]
  [[ "$output" == *"checks=NONE"* ]]
}

@test "an enabled auto-merge request is reported" {
  cat >"$FAKE_GH_FIXTURES/pr-status.json" <<'EOF'
{"data":{"repository":{"pullRequest":{
  "state":"OPEN","isDraft":false,"headRefOid":"abcdef1234567890",
  "reviewDecision":"APPROVED","mergeable":"MERGEABLE","mergeStateStatus":"CLEAN",
  "autoMergeRequest":{"enabledAt":"2026-01-01T00:00:00Z"},
  "commits":{"nodes":[{"commit":{"statusCheckRollup":{"state":"SUCCESS"}}}]},
  "reviewRequests":{"nodes":[]},
  "latestReviews":{"nodes":[]},
  "reviews":{"nodes":[]},
  "reviewThreads":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[]}
}}}}
EOF
  run "$script" 1 owner/repo
  [ "$status" -eq 0 ]
  [[ "$output" == *"autoMerge=true"* ]]
  [[ "$output" == *"reviewDecision=APPROVED"* ]]
}

@test "reports requested reviewers, including bots, in the status line" {
  cat >"$FAKE_GH_FIXTURES/pr-status.json" <<'EOF'
{"data":{"repository":{"pullRequest":{
  "state":"OPEN","isDraft":false,"headRefOid":"abcdef1234567890",
  "reviewDecision":null,"mergeable":"MERGEABLE","mergeStateStatus":"CLEAN",
  "autoMergeRequest":null,
  "commits":{"nodes":[{"commit":{"statusCheckRollup":{"state":"SUCCESS"}}}]},
  "reviewRequests":{"nodes":[{"requestedReviewer":{"login":"copilot-pull-request-reviewer"}},
    {"requestedReviewer":{"login":"alice"}}]},
  "latestReviews":{"nodes":[]},
  "reviews":{"nodes":[]},
  "reviewThreads":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[]}
}}}}
EOF
  run "$script" 1 owner/repo
  [ "$status" -eq 0 ]
  [[ "$output" == *"reviewRequests=copilot-pull-request-reviewer,alice"* ]]
}

@test "drops a team reviewer's null login instead of a stray empty entry" {
  cat >"$FAKE_GH_FIXTURES/pr-status.json" <<'EOF'
{"data":{"repository":{"pullRequest":{
  "state":"OPEN","isDraft":false,"headRefOid":"abcdef1234567890",
  "reviewDecision":null,"mergeable":"MERGEABLE","mergeStateStatus":"CLEAN",
  "autoMergeRequest":null,
  "commits":{"nodes":[{"commit":{"statusCheckRollup":{"state":"SUCCESS"}}}]},
  "reviewRequests":{"nodes":[{"requestedReviewer":{}},{"requestedReviewer":{"login":"alice"}}]},
  "latestReviews":{"nodes":[]},
  "reviews":{"nodes":[]},
  "reviewThreads":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[]}
}}}}
EOF
  run "$script" 1 owner/repo
  [ "$status" -eq 0 ]
  [[ "$output" == *"reviewRequests=alice"* ]]
  [[ "$output" != *"reviewRequests=,alice"* ]]
}

@test "lists an unresolved thread with its comment id and path:line" {
  cat >"$FAKE_GH_FIXTURES/pr-status.json" <<'EOF'
{"data":{"repository":{"pullRequest":{
  "state":"OPEN","isDraft":false,"headRefOid":"abcdef1234567890",
  "reviewDecision":null,"mergeable":"MERGEABLE","mergeStateStatus":"CLEAN",
  "autoMergeRequest":null,
  "commits":{"nodes":[{"commit":{"statusCheckRollup":{"state":"SUCCESS"}}}]},
  "reviewRequests":{"nodes":[]},
  "latestReviews":{"nodes":[]},
  "reviews":{"nodes":[]},
  "reviewThreads":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[
    {"id":"THREAD_1","isResolved":false,"isOutdated":false,"path":"some/file.sh","line":42,
     "comments":{"nodes":[{"databaseId":1001,"author":{"login":"alice"},"body":"fix this"}]}}
  ]}
}}}}
EOF
  run "$script" 1 owner/repo
  [ "$status" -eq 0 ]
  [[ "$output" == *"[1001] some/file.sh:42 (thread THREAD_1)"* ]]
  [[ "$output" == *"alice: fix this"* ]]
}

@test "extracts a suppressed finding from the reviews list" {
  cat >"$FAKE_GH_FIXTURES/pr-status.json" <<'EOF'
{"data":{"repository":{"pullRequest":{
  "state":"OPEN","isDraft":false,"headRefOid":"abcdef1234567890",
  "reviewDecision":null,"mergeable":"MERGEABLE","mergeStateStatus":"CLEAN",
  "autoMergeRequest":null,
  "commits":{"nodes":[{"commit":{"statusCheckRollup":{"state":"SUCCESS"}}}]},
  "reviewRequests":{"nodes":[]},
  "latestReviews":{"nodes":[]},
  "reviews":{"nodes":[{"body":"**src/foo.sh:12**\n* the actual finding text here\n"}]},
  "reviewThreads":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[]}
}}}}
EOF
  run "$script" 1 owner/repo
  [ "$status" -eq 0 ]
  [[ "$output" == *"src/foo.sh:12"* ]]
  [[ "$output" == *"the actual finding text here"* ]]
}

@test "shows the latest review with a summary body as the verdict" {
  run "$script" 1 owner/repo
  [ "$status" -eq 0 ]
  [[ "$output" == *$'[2026-01-01T00:00:00Z] someone on abcdef12:\n### verdict'* ]]
}


@test "reports no review yet when latestReviews has no summary body" {
  cat >"$FAKE_GH_FIXTURES/pr-status.json" <<'EOF'
{"data":{"repository":{"pullRequest":{
  "state":"OPEN","isDraft":false,"headRefOid":"abcdef1234567890",
  "reviewDecision":null,"mergeable":"MERGEABLE","mergeStateStatus":"CLEAN",
  "autoMergeRequest":null,
  "commits":{"nodes":[{"commit":{"statusCheckRollup":{"state":"SUCCESS"}}}]},
  "reviewRequests":{"nodes":[]},
  "latestReviews":{"nodes":[]},
  "reviews":{"nodes":[]},
  "reviewThreads":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[]}
}}}}
EOF
  run "$script" 1 owner/repo
  [ "$status" -eq 0 ]
  [[ "$output" == *"(no review with a summary yet)"* ]]
}

@test "pages through unresolved threads past the first 100" {
  cat >"$FAKE_GH_FIXTURES/pr-status.json" <<'EOF'
{"data":{"repository":{"pullRequest":{
  "state":"OPEN","isDraft":false,"headRefOid":"abcdef1234567890",
  "reviewDecision":null,"mergeable":"MERGEABLE","mergeStateStatus":"CLEAN",
  "autoMergeRequest":null,
  "commits":{"nodes":[{"commit":{"statusCheckRollup":{"state":"SUCCESS"}}}]},
  "reviewRequests":{"nodes":[]},
  "latestReviews":{"nodes":[]},
  "reviews":{"nodes":[]},
  "reviewThreads":{"pageInfo":{"hasNextPage":true,"endCursor":"CURSOR1"},"nodes":[
    {"id":"THREAD_1","isResolved":false,"isOutdated":false,"path":"a.sh","line":1,
     "comments":{"nodes":[{"databaseId":1,"author":{"login":"alice"},"body":"page one"}]}}
  ]}
}}}}
EOF
  cat >"$FAKE_GH_FIXTURES/pr-status-page2.json" <<'EOF'
{"data":{"repository":{"pullRequest":{
  "state":"OPEN","isDraft":false,"headRefOid":"abcdef1234567890",
  "reviewDecision":null,"mergeable":"MERGEABLE","mergeStateStatus":"CLEAN",
  "autoMergeRequest":null,
  "commits":{"nodes":[{"commit":{"statusCheckRollup":{"state":"SUCCESS"}}}]},
  "reviewRequests":{"nodes":[]},
  "latestReviews":{"nodes":[]},
  "reviews":{"nodes":[]},
  "reviewThreads":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[
    {"id":"THREAD_2","isResolved":false,"isOutdated":false,"path":"b.sh","line":2,
     "comments":{"nodes":[{"databaseId":2,"author":{"login":"bob"},"body":"page two"}]}}
  ]}
}}}}
EOF
  run "$script" 1 owner/repo
  [ "$status" -eq 0 ]
  [[ "$output" == *"[1] a.sh:1 (thread THREAD_1)"* ]]
  [[ "$output" == *"[2] b.sh:2 (thread THREAD_2)"* ]]
}

@test "fails loudly instead of misreporting when the GraphQL call fails" {
  touch "$FAKE_GH_FIXTURES/graphql-status-fails"
  run "$script" 1 owner/repo
  [ "$status" -eq 1 ]
  [[ "$output" == *"failed to fetch PR status via GraphQL"* ]]
}
