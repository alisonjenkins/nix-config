# shellcheck shell=bash
# Reader and editor for speckit-style task lines:
#   - [ ] T001 [P] [US1] description owner:x deps:T001,T002 due:... est:30 prio:2
# An id is T<digits> or pm:<slug>. Sourced, never executed.

# tasks_md_tsv <file>: eight-column rows (id state title owner deps due est prio).
tasks_md_tsv() {
  awk '
    /^- \[[ xX]\] / {
      sub(/\r$/, "")
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
      sub(/\r$/, "")
      rest = substr($0, 7)
      id = rest; sub(/ .*/, "", id)
      if (id ~/^(T[0-9]+|pm:[a-z0-9-]+)$/) printf "%s\t%s\n", id, $0
    }' "$1"
}

# tasks_md_set_state <file> <id> <open|done>: set the checkbox. Returns 3 if
# the id is absent and 2 if the state is not open or done. Writes through cat
# so the file keeps its mode and links.
tasks_md_set_state() {
  local file="$1" id="$2" want="$3" mark=" " tmp rc=0
  case "$want" in
    open | done) ;;
    *) return 2 ;;
  esac
  [[ $want == "done" ]] && mark="X"
  tmp="$(mktemp "${file}.XXXXXX")"
  awk -v id="$id" -v mark="$mark" '
    /^- \[[ xX]\] / {
      rest = substr($0, 7); tok = rest; sub(/ .*/, "", tok); sub(/\r$/, "", tok)
      if (tok == id) { $0 = "- [" mark "] " rest; found = 1 }
    }
    { print }
    END { exit found ? 0 : 3 }' "$file" >"$tmp" || rc=$?
  if ((rc == 0)); then
    cat "$tmp" >"$file" || rc=$?
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
