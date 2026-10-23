# Rank open tasks and place them in free working time. Needs lib/time.awk.
# Input: `pm list` rows (id state title owner deps due est prio, tab separated).
# Variables (-v): now (epoch seconds, required); days, hs, he, tz, chunk, gap,
# defest (minutes, except days); wdmin, wdmax (ISO weekdays); busyfile (lines of
# "start<TAB>end" in ISO8601 UTC, from lib/busy.awk). hs and he are minutes after
# local midnight and tz is the local offset from UTC in minutes.
# Output: slot, skip and unscheduled lines, then a "# scheduled=..." summary.

function free_stretch(from,   di, base, ws, we, wd, cur, k, moved, nxt) {
  for (di = 0; di < days; di++) {
    base = dayzero + di * 86400
    wd = weekday(base + tz * 60)
    if (wd < wdmin || wd > wdmax) continue
    ws = base + hs * 60
    we = base + he * 60
    cur = (from > ws ? from : ws)
    while (cur < we) {
      moved = 0
      for (k = 1; k <= nocc; k++) {
        if (occ_s[k] <= cur && cur < occ_e[k]) { cur = occ_e[k]; moved = 1 }
      }
      if (moved) continue
      nxt = we
      for (k = 1; k <= nocc; k++) {
        if (occ_s[k] > cur && occ_s[k] < nxt) nxt = occ_s[k]
      }
      FS = cur
      FE = nxt
      return 1
    }
  }
  return 0
}

# Open dependencies of row r (not itself) that have no slot yet, comma separated.
function unplaced_deps(r,   m, d, k, out) {
  m = split(deps[r], d, ",")
  for (k = 1; k <= m; k++) {
    if (d[k] != "" && d[k] != id[r] && (d[k] in is_open) && !(d[k] in dep_end)) out = out (out == "" ? "" : ",") d[k]
  }
  return out
}

function deps_placed(r) {
  return unplaced_deps(r) == ""
}

# Earliest start for row r: now, or the end of its latest dependency.
function dep_floor(r,   m, d, k, t) {
  t = from0
  m = split(deps[r], d, ",")
  for (k = 1; k <= m; k++) {
    if ((d[k] in dep_end) && dep_end[d[k]] > t) t = dep_end[d[k]]
  }
  return t
}

function before(a, b) {
  if (due_key[a] != due_key[b]) return due_key[a] < due_key[b]
  if (prio_key[a] != prio_key[b]) return prio_key[a] < prio_key[b]
  return a < b
}

BEGIN {
  FS = "\t"
  if (days == "") days = 14
  if (hs == "") hs = 540
  if (he == "") he = 1020
  if (tz == "") tz = 0
  if (wdmin == "") wdmin = 1
  if (wdmax == "") wdmax = 5
  if (chunk == "") chunk = 90
  if (gap == "") gap = 10
  if (defest == "") defest = 30
  days += 0; hs += 0; he += 0; tz += 0; wdmin += 0; wdmax += 0
  chunk += 0; gap += 0; defest += 0; now += 0
  min_chunk_secs = 15 * 60
  from0 = int((now + 299) / 300) * 300
  dayzero = int((now + tz * 60) / 86400) * 86400 - tz * 60
  nocc = 0
  if (busyfile != "") {
    while ((getline line < busyfile) > 0) {
      split(line, p, "\t")
      s = iso2epoch(p[1])
      e = iso2epoch(p[2])
      if (s >= 0 && e > s) { nocc++; occ_s[nocc] = s; occ_e[nocc] = e }
    }
    close(busyfile)
  }
}

/^#/ || NF < 3 { next }

{
  n++
  id[n] = $1; state[n] = $2; title[n] = $3; deps[n] = $5; due[n] = $6; est[n] = $7; prio[n] = $8
  if ($2 == "open") is_open[$1] = 1
}

END {
  nr = 0
  for (i = 1; i <= n; i++) {
    if (state[i] != "open") continue
    due_e[i] = (due[i] == "" ? -1 : iso2epoch(due[i]))
    # A date with no time of day is due at the end of that day.
    if (due_e[i] >= 0 && due[i] !~ /[Tt]/) due_e[i] += 86399
    due_key[i] = (due_e[i] >= 0 ? due_e[i] : 9e18)
    prio_key[i] = (prio[i] ~ /^[0-9]+$/ ? prio[i] + 0 : 99999)
    j = nr
    while (j >= 1 && before(i, rank[j])) { rank[j + 1] = rank[j]; j-- }
    rank[j + 1] = i
    nr++
  }

  nslot = 0
  # Best-ranked task whose open dependencies are all placed goes next, so a
  # dependent always lands after the end of its last dependency.
  for (;;) {
    i = 0
    for (r = 1; r <= nr; r++) {
      if (!(rank[r] in placed) && deps_placed(rank[r])) { i = rank[r]; break }
    }
    if (i == 0) break
    placed[i] = 1
    notes0 = ""
    if (est[i] ~ /^[0-9]+$/ && est[i] + 0 > 0) rem = est[i] * 60
    else { rem = defest * 60; notes0 = "est-default" }
    occ0 = nocc
    nch = 0
    t = dep_floor(i)
    ok = 1
    while (rem > 0) {
      if (!free_stretch(t)) { ok = 0; break }
      len = FE - FS
      if (len < min_chunk_secs && len < rem) { t = FE; continue }
      place = rem
      if (chunk * 60 < place) place = chunk * 60
      if (len < place) place = len
      nch++
      ch_s[nch] = FS
      ch_e[nch] = FS + place
      nocc++
      occ_s[nocc] = FS
      occ_e[nocc] = FS + place + gap * 60
      rem -= place
      t = FS + place
    }
    if (!ok) {
      nocc = occ0
      nun++
      un_line[nun] = "unscheduled\t" id[i] "\t" title[i] "\tno room in " days " days"
      continue
    }
    dep_end[id[i]] = ch_e[nch]
    late = (due_e[i] >= 0 && ch_e[nch] > due_e[i])
    ntasks++
    nchunks += nch
    if (late) nlate++
    for (c = 1; c <= nch; c++) {
      notes = notes0
      if (nch > 1) notes = notes (notes == "" ? "" : ",") "chunk " c "/" nch
      if (late) notes = notes (notes == "" ? "" : ",") "late"
      nslot++
      sl_start[nslot] = ch_s[c]
      sl_line[nslot] = "slot\t" id[i] "\t" epoch2iso(ch_s[c]) "\t" epoch2iso(ch_e[c]) "\t" title[i] "\t" notes
    }
  }

  # What is left depends, directly or through a cycle, on a task that never got a slot.
  for (a = 1; a <= n; a++) {
    if (state[a] != "open" || (a in placed)) continue
    nskip++
    skip_line[nskip] = "skip\t" id[a] "\t" title[a] "\tblocked by " unplaced_deps(a)
  }

  for (a = 2; a <= nslot; a++) {
    s = sl_start[a]; l = sl_line[a]
    b = a - 1
    while (b >= 1 && sl_start[b] > s) { sl_start[b + 1] = sl_start[b]; sl_line[b + 1] = sl_line[b]; b-- }
    sl_start[b + 1] = s
    sl_line[b + 1] = l
  }
  for (a = 1; a <= nslot; a++) print sl_line[a]
  for (a = 1; a <= nskip; a++) print skip_line[a]
  for (a = 1; a <= nun; a++) print un_line[a]
  printf "# scheduled=%d chunks=%d late=%d skipped=%d unscheduled=%d\n", ntasks, nchunks, nlate, nskip, nun
}
