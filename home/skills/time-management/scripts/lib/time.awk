# UTC time helpers shared by the tm awk programs. Epochs are seconds.

# days_from_civil(y, m, d): days since 1970-01-01 (proleptic Gregorian).
function days_from_civil(y, m, d,   era, yoe, doy, doe) {
  if (m <= 2) y--
  era = int((y >= 0 ? y : y - 399) / 400)
  yoe = y - era * 400
  doy = int((153 * (m + (m > 2 ? -3 : 9)) + 2) / 5) + d - 1
  doe = yoe * 365 + int(yoe / 4) - int(yoe / 100) + doy
  return era * 146097 + doe - 719468
}

# iso2epoch(s): "2026-10-21T14:30:15Z", "20261021T143015Z", the same without
# the Z (read as UTC) or a bare date (midnight). -1 when s is not one of these.
function iso2epoch(s,   t, y, mo, d, h, mi, sec) {
  t = s
  gsub(/[-:]/, "", t)
  sub(/Z$/, "", t)
  if (t !~ /^[0-9]+(T[0-9]+)?$/ || (length(t) != 8 && length(t) != 15) || (length(t) == 15 && substr(t, 9, 1) != "T")) return -1
  y = substr(t, 1, 4) + 0
  mo = substr(t, 5, 2) + 0
  d = substr(t, 7, 2) + 0
  if (mo < 1 || mo > 12 || d < 1 || d > 31) return -1
  h = mi = sec = 0
  if (length(t) > 8) {
    h = substr(t, 10, 2) + 0
    mi = substr(t, 12, 2) + 0
    sec = substr(t, 14, 2) + 0
  }
  if (h > 23 || mi > 59 || sec > 60) return -1
  # A day the month does not have (Feb 31) would roll into the next month.
  if (substr(epoch2iso(days_from_civil(y, mo, d) * 86400), 1, 10) != sprintf("%04d-%02d-%02d", y, mo, d)) return -1
  return days_from_civil(y, mo, d) * 86400 + h * 3600 + mi * 60 + sec
}

# epoch2iso(e): "2026-10-21T14:30:15Z".
function epoch2iso(e,   days, rem, z, era, doe, yoe, y, doy, mp, d, m) {
  days = int(e / 86400)
  rem = e - days * 86400
  z = days + 719468
  era = int((z >= 0 ? z : z - 146096) / 146097)
  doe = z - era * 146097
  yoe = int((doe - int(doe / 1460) + int(doe / 36524) - int(doe / 146096)) / 365)
  y = yoe + era * 400
  doy = doe - (365 * yoe + int(yoe / 4) - int(yoe / 100))
  mp = int((5 * doy + 2) / 153)
  d = doy - int((153 * mp + 2) / 5) + 1
  m = mp + (mp < 10 ? 3 : -9)
  if (m <= 2) y++
  return sprintf("%04d-%02d-%02dT%02d:%02d:%02dZ", y, m, d, int(rem / 3600), int((rem % 3600) / 60), rem % 60)
}

# weekday(e): 1 for Monday through 7 for Sunday.
function weekday(e,   w) {
  w = (int(e / 86400) + 3) % 7
  return (w < 0 ? w + 7 : w) + 1
}
