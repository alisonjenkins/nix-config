# Busy intervals from an .ics on stdin or as a file argument. Needs lib/time.awk.
# Prints "start<TAB>end" in ISO8601 UTC for each VEVENT, in file order.
# Zone parameters are ignored and times are read as UTC. An event with no usable
# end, a cancelled event and a transparent (shown as free) event are skipped.
# A recurring event is expanded inside the window hfrom..hto (-v, epoch seconds;
# hto defaults to a year after the first occurrence). Supported: FREQ DAILY,
# WEEKLY (BYDAY), MONTHLY (BYMONTHDAY) and YEARLY, with INTERVAL, COUNT, UNTIL
# and EXDATE. Any other rule is reported on stderr and only its first occurrence
# is kept.

# duration_secs(v): seconds in an RFC 5545 duration such as PT1H30M or P1DT2H.
function duration_secs(v,   i, c, n, total, in_time, unit) {
  in_time = 0
  n = ""
  for (i = 2; i <= length(v); i++) {
    c = substr(v, i, 1)
    if (c == "T") { in_time = 1; continue }
    if (c ~ /[0-9]/) { n = n c; continue }
    unit = 0
    if (c == "W") unit = 604800
    else if (c == "D") unit = 86400
    else if (c == "H" && in_time) unit = 3600
    else if (c == "M" && in_time) unit = 60
    else if (c == "S" && in_time) unit = 1
    total += n * unit
    n = ""
  }
  return total
}

function days_in_month(y, m) {
  if (m == 2) return ((y % 4 == 0 && y % 100 != 0) || y % 400 == 0) ? 29 : 28
  return (m == 4 || m == 6 || m == 9 || m == 11) ? 30 : 31
}

# put(t): one occurrence starting at t. 1 to carry on, 0 once the series is over.
function put(t) {
  if (t < first) return 1
  if (r_until >= 0 && t > r_until) return 0
  if (t >= r_hto) return 0
  r_n++
  if (r_count > 0 && r_n > r_count) return 0
  if (!(t in ex) && t + r_len > r_hfrom) print epoch2iso(t) "\t" epoch2iso(t + r_len)
  return 1
}

# expand(len): every occurrence of the current RRULE, each len seconds long.
function expand(len,   n, parts, k, eq, key, val, freq, interval, wset, nw, mset, nm, items, i, pos, tod, day0, per, base, iso, y, m, dom, mm, yy, mo, dd, dim, wd, ok, stopped) {
  r_len = len
  r_hfrom = (hfrom == "" ? 0 : hfrom + 0)
  r_hto = (hto == "" ? first + 366 * 86400 : hto + 0)
  r_until = -1
  r_count = 0
  r_n = 0
  freq = ""
  interval = 1
  ok = 1
  nw = nm = 0
  # BYDAY and BYMONTHDAY mean different things per FREQ, and FREQ need not come first.
  if (match(rrule, /FREQ=[A-Z]+/)) freq = substr(rrule, RSTART + 5, RLENGTH - 5)
  n = split(rrule, parts, ";")
  for (k = 1; k <= n; k++) {
    eq = index(parts[k], "=")
    key = substr(parts[k], 1, eq - 1)
    val = substr(parts[k], eq + 1)
    if (key == "FREQ") freq = val
    else if (key == "INTERVAL" && val ~ /^[0-9]+$/ && val + 0 > 0) interval = val + 0
    else if (key == "COUNT" && val ~ /^[0-9]+$/) r_count = val + 0
    else if (key == "UNTIL") {
      r_until = iso2epoch(val)
      if (r_until >= 0 && length(val) == 8) r_until += 86399
      if (r_until < 0) ok = 0
    } else if (key == "BYDAY" && freq == "WEEKLY") {
      split(val, items, ",")
      for (i = 1; i in items; i++) {
        pos = index("MOTUWETHFRSASU", items[i])
        if (length(items[i]) == 2 && pos % 2 == 1) { wset[(pos + 1) / 2] = 1; nw++ }
        else ok = 0
      }
    } else if (key == "BYMONTHDAY" && freq == "MONTHLY") {
      split(val, items, ",")
      for (i = 1; i in items; i++) {
        if (items[i] ~ /^[0-9]+$/ && items[i] + 0 >= 1 && items[i] + 0 <= 31) { mset[items[i] + 0] = 1; nm++ }
        else ok = 0
      }
    } else if (key != "WKST") ok = 0
  }
  if (freq !~ /^(DAILY|WEEKLY|MONTHLY|YEARLY)$/) ok = 0
  if (!ok) {
    print "tm: cannot expand RRULE " rrule "; using the first occurrence only" > "/dev/stderr"
    if (first < r_hto && first + len > r_hfrom) print epoch2iso(first) "\t" epoch2iso(first + len)
    return
  }
  tod = first % 86400
  day0 = first - tod
  iso = epoch2iso(first)
  y = substr(iso, 1, 4) + 0
  m = substr(iso, 6, 2) + 0
  dom = substr(iso, 9, 2) + 0
  stopped = 0
  # The cap bounds a rule that never reaches hto, such as one whose day never exists.
  for (per = 0; per < 100000 && !stopped; per++) {
    if (freq == "DAILY") {
      if (!put(first + per * interval * 86400)) stopped = 1
    } else if (freq == "WEEKLY") {
      base = day0 - (weekday(first) - 1) * 86400 + per * interval * 7 * 86400
      for (wd = 1; wd <= 7 && !stopped; wd++) {
        if (nw == 0 ? wd == weekday(first) : (wd in wset)) {
          if (!put(base + (wd - 1) * 86400 + tod)) stopped = 1
        }
      }
    } else if (freq == "MONTHLY") {
      mm = (m - 1) + per * interval
      yy = y + int(mm / 12)
      mo = mm % 12 + 1
      dim = days_in_month(yy, mo)
      for (dd = 1; dd <= dim && !stopped; dd++) {
        if (nm == 0 ? dd == dom : (dd in mset)) {
          if (!put(days_from_civil(yy, mo, dd) * 86400 + tod)) stopped = 1
        }
      }
    } else {
      yy = y + per * interval
      if (dom <= days_in_month(yy, m) && !put(days_from_civil(yy, m, dom) * 86400 + tod)) stopped = 1
    }
  }
}

function emit(   end) {
  if (!inev || start < 0 || cancelled || transparent) return
  end = stop
  if (end < 0 && dur > 0) end = start + dur
  if (end < 0 && isdate) end = start + 86400
  if (end <= start) return
  if (rrule == "") { print epoch2iso(start) "\t" epoch2iso(end); return }
  first = start
  expand(end - start)
}

function handle(line,   colon, head, value, semi, name, params, xs, nx, k, e) {
  if (line == "BEGIN:VEVENT") {
    inev = 1; inalarm = 0; start = -1; stop = -1; dur = 0; isdate = 0; cancelled = 0; transparent = 0
    rrule = ""
    delete ex
    return
  }
  if (line == "END:VEVENT") { emit(); inev = 0; return }
  if (!inev) return
  # An alarm has its own DURATION; none of its properties describe the event.
  if (line == "BEGIN:VALARM") { inalarm = 1; return }
  if (line == "END:VALARM") { inalarm = 0; return }
  if (inalarm) return
  colon = index(line, ":")
  if (colon == 0) return
  head = substr(line, 1, colon - 1)
  value = substr(line, colon + 1)
  semi = index(head, ";")
  name = (semi ? substr(head, 1, semi - 1) : head)
  params = (semi ? substr(head, semi + 1) : "")
  if (name == "DTSTART") {
    start = iso2epoch(value)
    isdate = (params ~ /VALUE=DATE($|;)/ || length(value) == 8)
  } else if (name == "DTEND") {
    stop = iso2epoch(value)
  } else if (name == "DURATION") {
    dur = duration_secs(value)
  } else if (name == "STATUS") {
    cancelled = (toupper(value) == "CANCELLED")
  } else if (name == "TRANSP") {
    transparent = (toupper(value) == "TRANSPARENT")
  } else if (name == "RRULE") {
    rrule = value
  } else if (name == "EXDATE") {
    nx = split(value, xs, ",")
    for (k = 1; k <= nx; k++) {
      e = iso2epoch(xs[k])
      if (e >= 0) ex[e] = 1
    }
  }
}

{
  sub(/\r$/, "")
  if ($0 ~ /^[ \t]/) { buf = buf substr($0, 2); next }
  handle(buf)
  buf = $0
}
END { handle(buf) }
