# shellcheck shell=bash
# TSV helpers shared by every backend. Rows have eight tab-separated fields:
# id state title owner deps due est prio. Sourced, never executed.

# pm_filter_tsv <state|all> <assignee> <due_before>: filter rows on stdin.
# Lines starting with # pass through. An empty assignee or due_before matches everything; state must be open, done or all.
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
