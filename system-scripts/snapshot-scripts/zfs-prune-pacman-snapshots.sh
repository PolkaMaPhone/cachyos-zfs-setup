#!/usr/bin/env bash
# Keeps only the most recent N pacman snapshots on the root BE; deletes older ones.
# If a snapshot is held/used by a clone, ZFS will refuse to destroy it (safe).
# default retention is 8 snapshots
set -euo pipefail

KEEP="${KEEP:-8}"   # change via /etc/pacman.d/hooks/99-zfs-prune-snapshots.hook
BE="$(findmnt -no SOURCE /)"
if [[ -z "$BE" ]]; then
  echo "[zfs-prune] Could not detect root dataset" >&2
  exit 1
fi

# List @pacman-* snapshots sorted oldest->newest
mapfile -t SNAPS < <(zfs list -H -t snapshot -o name -s creation -r "$BE" \
  | awk -F@ '/@pacman-/ {print $0}')

COUNT="${#SNAPS[@]}"
if (( COUNT <= KEEP )); then
  echo "[zfs-prune] Nothing to prune (have $COUNT, keep $KEEP)"
  exit 0
fi

TO_DELETE=$(( COUNT - KEEP ))
echo "[zfs-prune] Deleting $TO_DELETE old pacman snapshots (keeping $KEEP newest)"
for (( i=0; i<TO_DELETE; i++ )); do
  snap="${SNAPS[$i]}"
  echo "[zfs-prune] zfs destroy ${snap}"
  if ! zfs destroy "$snap"; then
    echo "[zfs-prune] Skipped (in use?): $snap" >&2
  fi
done
