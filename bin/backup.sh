#!/bin/sh
#
# backup.sh
# rsync snapshot backup with hardlink deduplication and age-based retention.
# Author: SudoShad
#
# All tunables come from conf/toolkit.conf. POSIX sh, passes `shellcheck -s sh`.

set -eu

# --- Load shared configuration ---
CDPATH=
SCRIPT_DIR=$(cd -- "$(dirname -- "$0")" && pwd)
: "${TOOLKIT_CONF:=${SCRIPT_DIR}/../conf/toolkit.conf}"
if [ ! -f "$TOOLKIT_CONF" ]; then
    echo "ERROR: config not found at $TOOLKIT_CONF" >&2
    exit 1
fi
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../conf/toolkit.conf
. "$TOOLKIT_CONF"

TIMESTAMP=$(date +%Y-%m-%d_%H-%M-%S)
DEST="${BACKUP_ROOT}/${TIMESTAMP}"
TMP_FILE=""

mkdir -p "$LOG_DIR" 2>/dev/null || true

# --- Logging ---
log() {
    _level="$1"
    shift
    printf '%s [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$_level" "$*" \
        | tee -a "$BACKUP_LOG"
}

# --- Cleanup on exit (release lock, remove temp file) ---
# shellcheck disable=SC2317  # invoked indirectly via trap, not dead code
cleanup() {
    rmdir "$LOCK_FILE" 2>/dev/null || true
    if [ -n "$TMP_FILE" ]; then
        rm -f "$TMP_FILE"
    fi
}
trap cleanup EXIT

# --- Preflight ---
if [ "$(id -u)" -ne 0 ]; then
    log ERROR "Must run as root to read $SOURCES."
    exit 1
fi

command -v rsync >/dev/null 2>&1 || { log ERROR "rsync is not installed."; exit 1; }

# Atomic lock: mkdir succeeds only if the directory does not already exist.
if ! mkdir "$LOCK_FILE" 2>/dev/null; then
    log ERROR "Another run holds the lock ($LOCK_FILE). Exiting."
    exit 1
fi

TMP_FILE=$(mktemp)
mkdir -p "$BACKUP_ROOT"

# --- Locate previous snapshot for hardlink reuse (before DEST exists) ---
LINK_DEST_BASE=""
# shellcheck disable=SC2012  # snapshot dirs are machine-generated timestamps (no odd chars); ls -t sorts by mtime
LATEST=$(ls -1dt "${BACKUP_ROOT}"/[0-9]*/ 2>/dev/null | head -n1 || true)
if [ -n "$LATEST" ]; then
    LINK_DEST_BASE="${LATEST%/}"
    log INFO "Reusing previous snapshot for hardlinks: $LINK_DEST_BASE"
fi
mkdir -p "$DEST"

# --- Backup each source into its own subfolder ---
log INFO "Starting backup into $DEST"
overall_rc=0

# shellcheck disable=SC2086  # SOURCES is an intentional space-separated list
for src in $SOURCES; do
    if [ ! -e "$src" ]; then
        log ERROR "Source $src does not exist, skipping."
        overall_rc=1
        continue
    fi

    name="${src##*/}"

    # Build rsync options in the positional parameters (POSIX has no arrays).
    set --
    if [ -n "$LINK_DEST_BASE" ] && [ -d "${LINK_DEST_BASE}/${name}" ]; then
        set -- --link-dest="${LINK_DEST_BASE}/${name}"
    fi

    log INFO "Syncing $src ..."
    set +e
    rsync -aAX --delete "$@" "${src}/" "${DEST}/${name}/" >>"$BACKUP_LOG" 2>&1
    rc=$?
    set -e

    # 0 = success, 24 = source files vanished mid-transfer (benign).
    if [ "$rc" -eq 0 ] || [ "$rc" -eq 24 ]; then
        log INFO "OK: $src (rsync exit $rc)."
    else
        log ERROR "FAILED: $src (rsync exit $rc)."
        overall_rc="$rc"
    fi
done

# --- Retention: prune snapshots older than RETENTION_DAYS ---
log INFO "Pruning snapshots older than ${RETENTION_DAYS} day(s)."
pruned=0
find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d \
    -mtime +"$RETENTION_DAYS" > "$TMP_FILE"
while read -r old; do
    if [ -n "$old" ]; then
        rm -rf -- "$old"
        log INFO "Removed old snapshot: $old"
        pruned=$((pruned + 1))
    fi
done < "$TMP_FILE"
log INFO "Retention done. Removed ${pruned} snapshot(s)."

# --- Result ---
if [ "$overall_rc" -eq 0 ]; then
    log INFO "Backup completed successfully."
else
    log ERROR "Backup completed WITH ERRORS (code ${overall_rc})."
fi
exit "$overall_rc"
