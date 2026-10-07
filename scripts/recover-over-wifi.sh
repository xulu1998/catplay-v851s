#!/bin/sh
# Car image has no USB debug channel. From the Mac (box powered on its USB port, car image running):
# join the box AP, fetch logs over SSH, send the box to FEL by software, install the bench image (keeps
# /persist), then rejoin the home Wi-Fi. The Mac is offline in between; the trap always restores Wi-Fi.
# macOS only (networksetup). Usage: sh scripts/recover-over-wifi.sh <home-ssid> [--logs-only | --ota <bundle.bin>]
#   --logs-only: fetch the logs and leave the car image running (no FEL, no install)
#   --ota:       fetch the logs, then upload the bundle to the settings page (box keeps running; replug it)
#   env U5A_WAIT_JOIN=<s> waits for a manual join from the Wi-Fi menu; U5A_BOX_PASS if the password changed
set -u
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
# Box network: the defaults from settings-defaults.conf; override with U5A_BOX_SSID / U5A_BOX_PASS when they
# were changed on the settings page (an SSID with a quote must be passed this way, not as a ${x:-...} default)
HOME_SSID="$1"; BOX_SSID="${U5A_BOX_SSID:-CatPlay-V851S}"; BOX_PASS="${U5A_BOX_PASS:-catplay123}"; BOX=192.168.50.2
TS=$(date +%Y%m%d-%H%M%S); OUT="$ROOT/backups/car-logs-$TS"; mkdir -p "$OUT"; LOG="$OUT/recover.log"
note() { echo "[host $(date +%H:%M:%S)] $*" >> "$LOG"; }
restore() {
  # Forget the box network first (the bench image runs the same AP), then rejoin home. Right after leaving
  # the box AP the scan list can be stale ("Could not find network"), so retry and cycle Wi-Fi if needed.
  networksetup -removepreferredwirelessnetwork en0 "$BOX_SSID" >> "$LOG" 2>&1
  w=0
  until ping -c1 -t2 1.1.1.1 >/dev/null 2>&1 || [ $w -ge 120 ]; do
    case $w in 0|20|45|75|100) networksetup -setairportnetwork en0 "$HOME_SSID" >> "$LOG" 2>&1 ;; esac
    case $w in 30|60|90) networksetup -setairportpower en0 off; sleep 3; networksetup -setairportpower en0 on ;; esac
    w=$((w+1)); sleep 1
  done
  note "home Wi-Fi restore: $(ping -c1 -t2 1.1.1.1 >/dev/null 2>&1 && echo ONLINE || echo OFFLINE) after ${w}s"
}
trap restore EXIT
sshx() {   # run a command on the box; dropbear -B allows the blank root password
  expect -c "set timeout $1; log_user 1; spawn ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=8 root@$BOX {$2}; expect { -re {assword:} { send \"\r\"; exp_continue } timeout { exit 2 } eof }" 2>&1
}
note "join $BOX_SSID"
# U5A_WAIT_JOIN=<s>: wait that long for the user to join the box AP from the Wi-Fi menu (the Mac, and any
# remote session driving it, is offline from then until the restore)
if [ -n "${U5A_WAIT_JOIN:-}" ]; then
  w=0; until ifconfig en0 | grep -q 'inet 192.168.50.' || [ $w -ge "$U5A_WAIT_JOIN" ]; do w=$((w+1)); sleep 1; done
  note "waited ${w}s for a manual join"
fi
# newer macOS hides scan results from the command line, so joining by name can fail (-3925); if the user
# already joined the box AP from the Wi-Fi menu, skip the join
ifconfig en0 | grep -q 'inet 192.168.50.' || networksetup -setairportnetwork en0 "$BOX_SSID" "$BOX_PASS" >> "$LOG" 2>&1
w=0; until ifconfig en0 | grep -q 'inet 192.168.50.' || [ $w -ge 40 ]; do w=$((w+1)); sleep 1; done
ifconfig en0 | grep -q 'inet 192.168.50.' || { note "no address from the box AP after ${w}s"; exit 3; }
note "on box AP: $(ifconfig en0 | grep 'inet ' | awk '{print $2}') after ${w}s"
sshx 40 'for f in /persist/bootcount /persist/log/* /run/u5a/boot.log; do echo "=== $f"; tail -c 120000 $f; done; echo "=== /run/u5a/catplay.log"; tail -c 300000 /run/u5a/catplay.log; echo "=== dmesg"; dmesg | grep -v RTW: | tail -n 300; echo "=== ps"; ps; echo END_OF_LOGS' > "$OUT/box-logs.txt"
note "logs: $(wc -c < "$OUT/box-logs.txt") bytes, END marker $(grep -c END_OF_LOGS "$OUT/box-logs.txt")"
[ "${2:-}" = --logs-only ] && { note "logs only: car image left running"; exit 0; }
if [ "${2:-}" = --ota ]; then   # upload an OTA bundle (scripts/make-ota.py) to the box settings page
  note "OTA upload $3 ($(wc -c < "$3") bytes)"
  curl -s -m 600 -H "Content-Type: application/octet-stream" --data-binary @"$3" "http://$BOX/cgi-bin/update" > "$OUT/ota-result.json" 2>> "$LOG"
  note "OTA result: $(cat "$OUT/ota-result.json")"
  exit 0
fi
sshx 10 'devmem 0x07090108 32 0x5aa5a55a; sync; devmem 0x020500a8 32 0x16aa0001' > /dev/null
w=0; until perl -e 'alarm 6; exec @ARGV' "${XFEL:-xfel}" version 2>/dev/null | grep -q AWUSBFEX || [ $w -ge 40 ]; do w=$((w+1)); sleep 1; done
if perl -e 'alarm 6; exec @ARGV' "${XFEL:-xfel}" version 2>/dev/null | grep -q AWUSBFEX; then
  note "box in FEL after ${w}s; installing bench (keeps /persist)"
  sh "$ROOT/scripts/nor-install.sh" "$ROOT/out/bench" >> "$LOG" 2>&1; note "install rc=$?"
else
  note "box did not reach FEL"
fi
