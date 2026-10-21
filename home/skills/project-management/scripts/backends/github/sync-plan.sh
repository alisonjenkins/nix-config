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

# Identity of the epic: a numbered spec directory, else the repo-relative path of
# the file, so two projects that both have a tasks.md or plan.md never share a marker.
abs_dir="$(cd "$(dirname "$file")" && pwd)"
dir_name="$(basename "$abs_dir")"
top="$(git -C "$abs_dir" rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -n $top && $abs_dir == "$top"/* ]]; then
  rel="${abs_dir#"$top"/}"
else
  rel="$dir_name"
fi
src="$rel/$(basename "$file")"
spec_re='^([0-9]{3})-(.+)$'
if [[ $dir_name =~ $spec_re ]]; then
  marker="pm:spec-${BASH_REMATCH[1]}"
  title="[spec-${BASH_REMATCH[1]}] ${BASH_REMATCH[2]}"
else
  slug="$(printf '%s' "$src" | sed -e 's/\.md$//' | tr 'A-Z_/ ' 'a-z---')"
  marker="pm:plan-$slug"
  title="[plan] $src"
fi

total="$(printf '%s\n' "$rows" | grep -c . || true)"
done_n="$(printf '%s\n' "$rows" | awk -F'\t' '$2 == "done" { n++ } END { print n + 0 }')"
body="$(
  printf '<!-- %s -->\n' "$marker"
  # shellcheck disable=SC2016 # the backticks are literal markdown code spans
  printf 'Source: `%s`\n' "$src"
  printf 'Progress: %s of %s done\n\n' "$done_n" "$total"
  printf '%s\n' "$rows" | awk -F'\t' '{ printf "- [%s] %s %s\n", ($2 == "done" ? "x" : " "), $1, $3 }'
)"

per_task="${per_task// /}"
# Which tasks get their own issue.
selected=""
if [[ -n $per_task && $per_task != all ]]; then
  for id in $(printf '%s' "$per_task" | tr ',' ' '); do
    printf '%s\n' "$rows" | cut -f1 | grep -qxF "$id" || pm_die "sync-plan: $id is not in $file"
  done
  selected=",$per_task,"
fi

pm_header github "repo=$GH_REPO"

# Look everything up first, so a truncated lookup refuses before any mutation.
epics="$(gh issue list -R "$GH_REPO" --label pm-epic --state all --limit "$GH_LIMIT" --json number,state,body)"
existing=""
if [[ -n $per_task ]]; then
  existing="$(gh issue list -R "$GH_REPO" --state all --limit "$GH_TASK_LIMIT" --json number,title,state,body)"
fi
if gh_truncated "$epics" "$GH_LIMIT"; then
  echo "# warning: epic lookup truncated at $GH_LIMIT issues" >&2
  if ((apply)); then
    pm_die "sync-plan: refusing --apply because the epic lookup is truncated"
  fi
fi
if [[ -n $per_task ]] && gh_truncated "$existing" "$GH_TASK_LIMIT"; then
  echo "# warning: issue lookup truncated at $GH_TASK_LIMIT issues" >&2
  if ((apply)); then
    pm_die "sync-plan: refusing --apply because the issue lookup is truncated"
  fi
fi

# Epic.
epic_match="$(jq -c --arg m "<!-- $marker -->" '[.[] | select((.body // "") | contains($m))]' <<<"$epics")"
epic_count="$(jq length <<<"$epic_match")"
epic_no="$(jq -r '.[0].number // ""' <<<"$epic_match")"
if ((epic_count > 1)); then
  emit drift epic "$marker" "duplicate epics $(jq -r '[.[].number | "#\(.)"] | join(" ")' <<<"$epic_match"); not touching them"
elif [[ -z $epic_no ]]; then
  if ((apply)); then
    gh label create pm-epic -R "$GH_REPO" --description "pm epic" --force >/dev/null
    url="$(printf '%s\n' "$body" | gh issue create -R "$GH_REPO" --title "$title" --body-file - --label pm-epic)"
    emit created epic "$marker" "#${url##*/}"
  else
    emit would-create epic "$marker" "$title"
  fi
else
  current="$(jq -r '.[0].body' <<<"$epic_match" | tr -d '\r')"
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
  seen=" "
  while IFS="$(printf '\t')" read -r id st tt _; do
    if [[ $per_task != all && $selected != *",$id,"* ]]; then
      continue
    fi
    case "$seen" in
      *" $id "*)
        emit exists task "$id" "duplicate id in file"
        continue
        ;;
    esac
    seen="$seen$id "
    exact="$id: $tt"
    hit="$(jq -r --arg id "$id" --arg exact "$exact" --arg src "$src" '
      [.[] | select(.title == $id or (.title | startswith($id + ":")) or (.title | startswith($id + " ")))] as $c
      | ([$c[] | select(((.body // "") | contains("Source: " + $src)) or .title == $exact)] | first) as $mine
      | if $mine then "\($mine.number) \($mine.state)"
        elif ([$c[] | select((.body // "") | contains("Source: ") | not)] | length) > 0 then "ambiguous"
        else "" end' <<<"$existing")"
    if [[ $hit == ambiguous ]]; then
      emit drift task "$id" "an issue starts with $id but is not tied to $src; not touching it"
      continue
    fi
    if [[ -z $hit ]]; then
      if ((apply)); then
        url="$(gh issue create -R "$GH_REPO" --title "$id: $tt" --body "Tracked in $title. Source: $src" </dev/null)"
        emit created task "$id" "#${url##*/}"
      else
        emit would-create task "$id" "$tt"
      fi
      continue
    fi
    n="${hit%% *}"
    istate="${hit##* }"
    if [[ $st == "done" && $istate == OPEN ]]; then
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
