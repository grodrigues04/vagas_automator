#!/usr/bin/env bash
# Checks the wall clock every 30 seconds and starts the routine on Thursdays
# between 21:00 and 21:09. Using the wall clock (instead of a sleep until the
# next run) means a suspended or powered-off computer simply misses the window:
# there is no catch-up on another day.
#
# Runs as root: run.sh drops to the `node` user before Claude starts, and
# send_results.py (root, never Claude) queues finished results in personalWhats.
set -uo pipefail

echo "[scheduler] started at $(date '+%F %T %Z'), routine runs on Thursdays at 21:00"

while true; do
  day_of_week=$(date +%u)   # 4 = Thursday
  hour=$(date +%H)
  minute=$(date +%M)
  week=$(date +%G-W%V)

  if [ "$day_of_week" = "4" ] && [ "$hour" = "21" ] && [ "$((10#$minute))" -lt 10 ] \
     && [ ! -e "/data/state/$week.lock" ]; then
    /app/run.sh
  fi

  /opt/interface/bin/python /app/send_results.py

  sleep 30
done
