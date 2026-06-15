#!/bin/sh
#
# ssh_guard.sh
# Detect SSH brute-force attempts in auth.log and block offending IPs.
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

TMP_FILE=""
mkdir -p "$LOG_DIR" 2>/dev/null || true

cleanup() {
    if [ -n "$TMP_FILE" ]; then
        rm -f "$TMP_FILE"
    fi
}
trap cleanup EXIT

# --- Helpers ---
log_ban() {
    printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" | tee -a "$BAN_LOG"
}

is_whitelisted() {
    # shellcheck disable=SC2086  # WHITELIST is an intentional space-separated list
    for w in $WHITELIST; do
        if [ "$1" = "$w" ]; then
            return 0
        fi
    done
    return 1
}

already_banned() {
    case "$FW" in
        ufw)      ufw status | grep -q "[[:space:]]DENY[[:space:]].*$1" ;;
        iptables) iptables -C INPUT -s "$1" -j DROP 2>/dev/null ;;
    esac
}

ban_ip() {
    case "$FW" in
        ufw)      ufw insert 1 deny from "$1" to any >/dev/null ;;
        iptables) iptables -I INPUT -s "$1" -j DROP ;;
    esac
}

# --- Preflight ---
if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: must run as root to modify firewall rules." >&2
    exit 1
fi

if [ ! -r "$AUTH_LOG" ]; then
    echo "ERROR: cannot read $AUTH_LOG" >&2
    exit 1
fi

# Pick a firewall backend. ufw must be present AND active.
if command -v ufw >/dev/null 2>&1 && ufw status >/dev/null 2>&1; then
    FW="ufw"
elif command -v iptables >/dev/null 2>&1; then
    FW="iptables"
else
    echo "ERROR: neither ufw nor iptables is available." >&2
    exit 1
fi
echo "[*] Firewall backend: $FW"
echo "[*] Scanning $AUTH_LOG (threshold: $THRESHOLD failed attempts)..."

# --- Build "count IP" pairs of failed logins into a temp file ---
TMP_FILE=$(mktemp)
grep -aE "Failed password" "$AUTH_LOG" \
    | grep -oE "from [0-9]+\.[0-9]+\.[0-9]+\.[0-9]+" \
    | awk '{print $2}' \
    | sort | uniq -c | sort -rn > "$TMP_FILE"

# --- Act on offenders ---
while read -r count ip; do
    if [ -z "$ip" ]; then
        continue
    fi
    if [ "$count" -lt "$THRESHOLD" ]; then
        continue
    fi
    if is_whitelisted "$ip"; then
        echo "[=] $ip ($count attempts) whitelisted, skipping."
        continue
    fi
    if already_banned "$ip"; then
        echo "[=] $ip already blocked, skipping."
        continue
    fi
    if ban_ip "$ip"; then
        log_ban "BANNED $ip after $count failed attempts via $FW"
        echo "[!] Banned $ip ($count failed attempts)."
    else
        echo "[x] Failed to ban $ip." >&2
    fi
done < "$TMP_FILE"

echo "[*] Scan complete."
