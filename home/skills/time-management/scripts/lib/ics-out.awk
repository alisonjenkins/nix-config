# Slot lines (from lib/schedule.awk) on stdin -> an .ics on stdout. Needs
# lib/time.awk and -v now=<epoch> for DTSTAMP. Run under LC_ALL=C: lines are
# folded at 75 octets and never inside a UTF-8 sequence.

function esc(s) {
  gsub(/\\/, "\\\\", s)
  gsub(/;/, "\\;", s)
  gsub(/,/, "\\,", s)
  return s
}

function stamp(iso,   t) {
  t = iso
  gsub(/[-:]/, "", t)
  return t
}

# put(line): print a content line with CRLF, folded at 75 octets.
function put(line,   cut) {
  while (length(line) > 75) {
    cut = 75
    while (cut > 1 && (substr(line, cut + 1, 1) in cont)) cut--
    printf "%s\r\n", substr(line, 1, cut)
    line = " " substr(line, cut + 1)
  }
  printf "%s\r\n", line
}

BEGIN {
  FS = "\t"
  for (c = 128; c < 192; c++) cont[sprintf("%c", c)] = 1
  put("BEGIN:VCALENDAR")
  put("VERSION:2.0")
  put("PRODID:-//time-management//tm//EN")
  put("CALSCALE:GREGORIAN")
  dtstamp = stamp(epoch2iso(now + 0))
}

$1 == "slot" {
  k = 1
  total = 1
  if (match($6, /chunk [0-9]+\/[0-9]+/)) {
    split(substr($6, RSTART + 6, RLENGTH - 6), kn, "/")
    k = kn[1]
    total = kn[2]
  }
  put("BEGIN:VEVENT")
  put("UID:tm-" $2 "-" k "@time-management")
  put("DTSTAMP:" dtstamp)
  put("DTSTART:" stamp($3))
  put("DTEND:" stamp($4))
  put("SUMMARY:" esc($2 " " $5 (total > 1 ? " (" k "/" total ")" : "")))
  if ($6 != "") put("DESCRIPTION:" esc($6))
  put("END:VEVENT")
}

END { put("END:VCALENDAR") }
