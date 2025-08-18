#!/usr/bin/env bash
# Snapshots the current root boot environment (and optionally selected children)
# before any pacman transaction. Snapshots are named @pacman-YYYYmmdd-HHMMSS.
# Smart batching: skips if recent snapshot exists (within BATCH_WINDOW minutes)
set -euo pipefail

# Configuration
BATCH_WINDOW="${BATCH_WINDOW:-3}"  # minutes - consider operations within this window as batch

# Detect the BE mounted at /
BE="$(findmnt -no SOURCE /)"
if [[ -z "$BE" ]]; then
  echo "[zfs-pre-snap] Could not detect root dataset" >&2
  exit 1
fi

# Check for recent snapshots to avoid spam during batch operations
echo "[zfs-pre-snap] Checking for recent snapshots..."
RECENT_SNAP=$(zfs list -H -t snapshot -o name,creation -s creation -r "$BE" 2>/dev/null | \
  grep "@pacman-" | tail -1 || true)

if [[ -n "$RECENT_SNAP" ]]; then
  SNAP_NAME=$(echo "$RECENT_SNAP" | awk '{print $1}')
  # ZFS creation format: "Sun Aug 17 19:37 2025" - need to reconstruct properly
  SNAP_TIME=$(echo "$RECENT_SNAP" | awk '{$1=""; print $0}' | sed 's/^ *//')
  
  echo "[zfs-pre-snap] Found recent snapshot: $SNAP_NAME created at: $SNAP_TIME"
  
  # Convert snapshot time to epoch seconds
  # Try multiple date parsing approaches for ZFS format
  SNAP_EPOCH=$(date -d "$SNAP_TIME" +%s 2>/dev/null || \
               date -d "$(echo "$SNAP_TIME" | sed 's/ \([0-9]\{4\}\)$/ \1/' | sed 's/^\([A-Za-z]*\) //')" +%s 2>/dev/null || \
               echo "0")
  
  CURRENT_EPOCH=$(date +%s)
  WINDOW_SECONDS=$((BATCH_WINDOW * 60))
  
  #echo "[zfs-pre-snap] Debug - Snap epoch: $SNAP_EPOCH, Current: $CURRENT_EPOCH, Window: $WINDOW_SECONDS"
  
  if [[ $SNAP_EPOCH -gt 0 ]] && [[ $((CURRENT_EPOCH - SNAP_EPOCH)) -lt $WINDOW_SECONDS ]]; then
    AGE_SEC=$(( CURRENT_EPOCH - SNAP_EPOCH ))
    AGE_MIN=$(( AGE_SEC / 60 ))
    echo "[zfs-pre-snap] Recent snapshot exists: $SNAP_NAME (${AGE_SEC}s/${AGE_MIN}m ago)"
    echo "[zfs-pre-snap] Skipping snapshot - assuming batch operation"
    exit 0
  else
    echo "[zfs-pre-snap] Snapshot is older than ${BATCH_WINDOW} minutes, proceeding"
  fi
fi

# Proceed with snapshot creation
STAMP="$(date +%Y%m%d-%H%M%S)"
TAG="pacman-${STAMP}"

echo "[zfs-pre-snap] Creating snapshot ${BE}@${TAG}"
zfs snapshot "${BE}@${TAG}"
zfs set custom:pacman_version="$(pacman -Q pacman | cut -d' ' -f2)" "${BE}@${TAG}"
zfs set custom:kernel_version="$(uname -r)" "${BE}@${TAG}"
zfs set custom:package_count="$(pacman -Q | wc -l)" "${BE}@${TAG}"

# OPTIONAL: also snapshot a few OS state datasets (but not /home)
# Uncomment lines below if you want them:
# for ds in "${BE%/root}/varlog" "${BE%/root}/varcache"; do
#   if zfs list -H -o name "$ds" >/dev/null 2>&1; then
#     echo "[zfs-pre-snap] Creating snapshot ${ds}@${TAG}"
#     zfs snapshot "${ds}@${TAG}"
#   fi
# done

echo "[zfs-pre-snap] Snapshot created successfully"
exit 0
