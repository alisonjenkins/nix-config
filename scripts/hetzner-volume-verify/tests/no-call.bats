#!/usr/bin/env bats
# check-no-call.sh: exit 0 only when the SFU reports no participants (FR-009).
# It fails closed: an unreachable or unreadable endpoint is not "no call".

setup() {
  script="${BATS_TEST_DIRNAME}/../check-no-call.sh"
  export FIXTURES="${BATS_TEST_TMPDIR}/fixtures"
  mkdir -p "$FIXTURES"
  export PATH="${BATS_TEST_DIRNAME}/bin:${PATH}"
  export VERIFY_METRICS_URL="http://sfu.test/metrics"
}

metrics() {
  printf '# HELP livekit_participant_total Number of participants\nlivekit_participant_total{node_id="ND_a",node_type="SERVER"} %s\n' "$1" > "$FIXTURES/curl.out"
}

@test "zero participants prints calls=0 and exits 0" {
  metrics 0
  run "$script"
  [ "$status" -eq 0 ]
  [[ "$output" == *"calls=0"* ]]
}

@test "one participant prints calls=1 and exits 1" {
  metrics 1
  run "$script"
  [ "$status" -eq 1 ]
  [[ "$output" == *"calls=1"* ]]
}

@test "participants on several nodes are summed" {
  printf 'livekit_participant_total{node_id="a"} 0\nlivekit_participant_total{node_id="b"} 2\n' > "$FIXTURES/curl.out"
  run "$script"
  [ "$status" -eq 1 ]
  [[ "$output" == *"calls=2"* ]]
}

@test "an unreachable endpoint fails closed with the URL in the message" {
  echo 7 > "$FIXTURES/curl.rc"
  run "$script"
  [ "$status" -eq 3 ]
  [[ "$output" == *"http://sfu.test/metrics"* ]]
  [[ "$output" != *"calls=0"* ]]
}

@test "output without the participant metric fails closed" {
  echo 'livekit_room_total 0' > "$FIXTURES/curl.out"
  run "$script"
  [ "$status" -eq 3 ]
  [[ "$output" == *"livekit_participant_total"* ]]
  [[ "$output" != *"calls=0"* ]]
}
