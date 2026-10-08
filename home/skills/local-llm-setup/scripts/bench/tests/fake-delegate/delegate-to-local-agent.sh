#!/usr/bin/env bash
# Stand-in for delegate-to-local-agent.sh: same argv and env contract, no model.
# FAKE_MODE=solution applies the fixture's solution overlay, null applies nothing.
# It refuses to run if the edit flag does not match the task kind, so the
# runner's edit/read-only wiring is tested too.
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
fixtures=$here/../../fixtures
work=$1
task_text=$2
mode=${FAKE_MODE:?FAKE_MODE must be solution or null}

[[ "$work" == /* && ! -L "$work" ]] || { echo "work dir must be absolute and not a symlink" >&2; exit 1; }
[[ -n "$task_text" ]] || { echo "empty task text" >&2; exit 1; }

task=$(basename "$work")
task=${task%-*}
overlay=$fixtures/$task/$mode

case "$task" in
  newmodule | unittests | fixturefix | multiedit) want_edit=1 ;;
  *) want_edit=0 ;;
esac
[[ "${LOCAL_LLM_AGENT_EDIT:-}" == "$want_edit" ]] || { echo "edit flag ${LOCAL_LLM_AGENT_EDIT:-unset} wrong for $task" >&2; exit 1; }

echo 'tool read completed: {"filePath":"x"}' >&2
echo 'tool edit error: {"filePath":"y"}' >&2
echo 'tool grep completed: {"pattern":"z"}' >&2

if [[ "$want_edit" == 1 && -d "$overlay" ]]; then
  find "$overlay" -mindepth 1 -maxdepth 1 ! -name reply.txt -exec cp -a {} "$work"/ \;
fi
if [[ -f "$overlay/reply.txt" ]]; then
  cat "$overlay/reply.txt"
else
  echo "fake reply for $task"
fi
