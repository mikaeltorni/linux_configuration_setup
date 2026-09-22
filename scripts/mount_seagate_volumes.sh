#!/usr/bin/env bash
# Mount Seagate-labelled volumes once the graphical user session is active.
# UDisks keeps the same /media/$USER/<label> location as Files uses.
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/logging.sh"

label_dir="${SEAGATE_LABEL_DIR:-/dev/disk/by-label}"
found=0
failed=0
for label_path in "$label_dir"/Seagate*; do
  [ -e "$label_path" ] || continue
  found=1
  device="$(readlink -f "$label_path")"
  if findmnt -rn -S "$device" >/dev/null; then
    log info "Seagate volume already mounted: $device"
    continue
  fi
  if udisksctl mount --no-user-interaction -b "$device" >/dev/null; then
    log info "Mounted Seagate volume: $device"
  else
    log error "Could not mount Seagate volume: $device"
    failed=1
  fi
done

if [ "$found" -eq 0 ]; then
  log info "No Seagate-labelled volume present"
fi
exit "$failed"
