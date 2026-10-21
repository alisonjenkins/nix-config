# Busy intervals from an .ics on stdin or as a file argument. Needs lib/time.awk.
# Prints "start<TAB>end" in ISO8601 UTC for each VEVENT, in file order.
# Zone parameters are ignored and times are read as UTC. Recurrence rules are
# not expanded. An event with no usable end, a cancelled event and a transparent
# (shown as free) event are skipped.

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

function emit(   end) {
  if (!inev || start < 0 || cancelled || transparent) return
  end = stop
  if (end < 0 && dur > 0) end = start + dur
  if (end < 0 && isdate) end = start + 86400
  if (end <= start) return
  print epoch2iso(start) "\t" epoch2iso(end)
}

function handle(line,   colon, head, value, semi, name, params) {
  if (line == "BEGIN:VEVENT") { inev = 1; inalarm = 0; start = -1; stop = -1; dur = 0; isdate = 0; cancelled = 0; transparent = 0; return }
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
  }
}

{
  sub(/\r$/, "")
  if ($0 ~ /^[ \t]/) { buf = buf substr($0, 2); next }
  handle(buf)
  buf = $0
}
END { handle(buf) }
