#!/bin/sh
#
# health_check.sh
# System health report with threshold checks and webhook alerting.
# Author: SudoShad
#
# All tunables come from conf/toolkit.conf. POSIX sh, passes `shellcheck -s sh`.
# No `set -e`: a single failing check must not abort the whole report.

set -u

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

TMP_FILE=$(mktemp) || { echo "ERROR: mktemp failed" >&2; exit 1; }
trap 'rm -f "$TMP_FILE"' EXIT

# --- Colors only when stdout is an interactive terminal ---
if [ -t 1 ]; then
    RED=$(printf '\033[0;31m'); YEL=$(printf '\033[0;33m')
    GRN=$(printf '\033[0;32m'); BLD=$(printf '\033[1m'); RST=$(printf '\033[0m')
else
    RED=""; YEL=""; GRN=""; BLD=""; RST=""
fi

ISSUE_COUNT=0
ISSUES_MSG=""

add_issue() {
    ISSUE_COUNT=$((ISSUE_COUNT + 1))
    if [ -z "$ISSUES_MSG" ]; then
        ISSUES_MSG="$1"
    else
        ISSUES_MSG="${ISSUES_MSG}; $1"
    fi
}

status_line() {
    case "$2" in
        OK)   sl_color="$GRN" ;;
        WARN) sl_color="$YEL" ;;
        CRIT) sl_color="$RED" ;;
        *)    sl_color="$RST" ;;
    esac
    printf '  %-20s [%s%-4s%s] %s\n' "$1" "$sl_color" "$2" "$RST" "$3"
}

check_disk() {
    printf '%sDisk usage%s\n' "$BLD" "$RST"
    df -hP -x tmpfs -x devtmpfs -x squashfs | awk 'NR > 1 {print $5, $6}' > "$TMP_FILE"
    while read -r pct mount; do
        num="${pct%\%}"
        if [ "$num" -ge "$DISK_THRESHOLD" ]; then
            status_line "$mount" "WARN" "$pct used, $mount"
            add_issue "disk $mount at $pct"
        else
            status_line "$mount" "OK" "$pct used"
        fi
    done < "$TMP_FILE"
}

check_memory() {
    printf '%sMemory%s\n' "$BLD" "$RST"
    mem_total=$(awk '/^MemTotal:/{print $2}' /proc/meminfo)
    mem_avail=$(awk '/^MemAvailable:/{print $2}' /proc/meminfo)
    mem_used=$((mem_total - mem_avail))
    mem_pct=$((mem_used * 100 / mem_total))
    mem_detail="${mem_pct}% used ($((mem_used / 1024))MB of $((mem_total / 1024))MB)"
    if [ "$mem_pct" -ge "$MEM_THRESHOLD" ]; then
        status_line "RAM" "WARN" "$mem_detail"
        add_issue "memory at ${mem_pct}%"
    else
        status_line "RAM" "OK" "$mem_detail"
    fi
}

check_load() {
    printf '%sCPU load%s\n' "$BLD" "$RST"
    cores=$(nproc 2>/dev/null || getconf _NPROCESSORS_ONLN)
    load1=$(awk '{print $1}' /proc/loadavg)
    # Float compare inside awk: exit 0 (success) when load1 > cores.
    if awk -v l="$load1" -v c="$cores" 'BEGIN { exit !(l > c) }'; then
        status_line "Load (1 min)" "WARN" "$load1 over $cores core(s)"
        add_issue "load $load1 over $cores cores"
    else
        status_line "Load (1 min)" "OK" "$load1 on $cores core(s)"
    fi
}

check_services() {
    printf '%sCritical services%s\n' "$BLD" "$RST"
    # shellcheck disable=SC2086  # SERVICES is an intentional space-separated list
    for svc in $SERVICES; do
        if systemctl is-active --quiet "$svc"; then
            status_line "$svc" "OK" "active"
        else
            status_line "$svc" "CRIT" "not running"
            add_issue "service $svc down"
        fi
    done
}

send_alert() {
    # -----------------------------------------------------------------
    # PLACEHOLDER: wire up your Slack or Discord webhook here.
    #   Slack   payload: {"text": "..."}
    #   Discord payload: {"content": "..."}
    # Enable with:  export WEBHOOK_URL="https://hooks.slack.com/..."
    # -----------------------------------------------------------------
    if [ -z "$WEBHOOK_URL" ]; then
        printf '%s[alert] WEBHOOK_URL not set, notification skipped.%s\n' "$YEL" "$RST"
        return 0
    fi
    payload=$(printf '{"text":"%s"}' "$1")
    if curl -fsS -X POST -H 'Content-Type: application/json' \
            --data "$payload" "$WEBHOOK_URL" >/dev/null 2>&1; then
        echo "[alert] Notification sent."
    else
        echo "[alert] Notification FAILED to send." >&2
    fi
}

main() {
    printf '%s=== System Health Report ===%s\n' "$BLD" "$RST"
    echo "Host: $(uname -n)    $(date '+%Y-%m-%d %H:%M:%S')"
    echo
    check_disk
    check_memory
    check_load
    check_services
    echo

    if [ "$ISSUE_COUNT" -gt 0 ]; then
        printf '%s%sStatus: %s issue(s) detected.%s\n' "$RED" "$BLD" "$ISSUE_COUNT" "$RST"
        send_alert "Health alert on $(uname -n): $ISSUES_MSG"
        exit 1
    fi
    printf '%s%sStatus: all systems healthy.%s\n' "$GRN" "$BLD" "$RST"
    exit 0
}

main "$@"
