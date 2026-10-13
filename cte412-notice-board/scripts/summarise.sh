#!/bin/sh
# scripts/summarise.sh
# Purpose : summarise a saved availability-monitor log (Task 4.2).
# Usage   : scripts/summarise.sh evidence/t5-recreate-monitor.txt
# Input   : the only argument is a log file whose lines look like
#             <ISO-8601 UTC timestamp> <OK|FAIL> <response body or error>
#           (written by the Pod `monitor`; any other line is ignored).
# Output  : total requests, failed requests, first and last timestamp, and the number of
#           responses per distinct "version" value. It also prints the first/last time each
#           version was seen, the first/last FAIL, and the mixed-version window, which is
#           only meaningful for a log that contains ONE release (two versions).
# Timestamps have one-second resolution, so every duration is accurate to +/- 1 s.
set -eu

if [ "$#" -ne 1 ] || [ ! -r "$1" ]; then
  echo "usage: $0 <monitor-log-file>" >&2
  exit 2
fi

awk '
# Seconds since 1970-01-01 for "YYYY-MM-DDTHH:MM:SSZ" (portable: no mktime()).
function epoch(ts,   y, m, d, hh, mi, ss, era, yoe, doy, doe, days) {
  y = substr(ts, 1, 4) + 0; m = substr(ts, 6, 2) + 0; d = substr(ts, 9, 2) + 0
  hh = substr(ts, 12, 2) + 0; mi = substr(ts, 15, 2) + 0; ss = substr(ts, 18, 2) + 0
  if (m <= 2) y -= 1
  era = int(y / 400)
  yoe = y - era * 400
  doy = int((153 * (m + (m > 2 ? -3 : 9)) + 2) / 5) + d - 1
  doe = yoe * 365 + int(yoe / 4) - int(yoe / 100) + doy
  days = era * 146097 + doe - 719468
  return days * 86400 + hh * 3600 + mi * 60 + ss
}

/^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z (OK|FAIL)( |$)/ {
  ts = $1
  total++
  if (first == "") first = ts
  last = ts
  if ($2 == "FAIL") {
    failed++
    if (firstfail == "") firstfail = ts
    lastfail = ts
  } else {
    v = ""
    if (match($0, /"version": *"[^"]*"/)) {
      v = substr($0, RSTART, RLENGTH)
      sub(/^"version": *"/, "", v)
      sub(/"$/, "", v)
    }
    if (v == "") v = "(no version in body)"
    count[v]++
    if (!(v in seenfirst)) { seenfirst[v] = ts; order[++nv] = v }
    seenlast[v] = ts
  }
}

END {
  if (total == 0) { print "no monitor lines found" > "/dev/stderr"; exit 1 }
  printf "Total requests       : %d\n", total
  printf "Failed requests      : %d\n", failed + 0
  printf "First timestamp      : %s\n", first
  printf "Last timestamp       : %s\n", last
  printf "Duration             : %d s\n", epoch(last) - epoch(first)
  if (failed > 0)
    printf "First / last FAIL    : %s / %s (%d s apart)\n", firstfail, lastfail, epoch(lastfail) - epoch(firstfail)
  else
    print  "First / last FAIL    : none"
  print "Responses per version:"
  for (i = 1; i <= nv; i++) {
    v = order[i]
    printf "  %-16s %6d   first %s   last %s\n", v, count[v], seenfirst[v], seenlast[v]
  }
  if (nv == 2) {
    w = epoch(seenlast[order[1]]) - epoch(seenfirst[order[2]])
    if (w < 0) w = 0
    printf "Mixed-version window : %d s (%s and %s both observed)\n", w, order[1], order[2]
  } else if (nv < 2) {
    print  "Mixed-version window : 0 s (only one version observed)"
  } else {
    print  "Mixed-version window : n/a (more than two versions in this log)"
  }
}
' "$1"
