#!/bin/sh
#
# install.sh
# Set up ops-toolkit on this host: make scripts executable, create the log
# directory, and install cron jobs (backup daily, health check hourly).
# Author: SudoShad
#
# POSIX sh, passes `shellcheck -s sh`. Run as root: sudo ./install.sh

set -eu

if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: run as root (sudo ./install.sh)." >&2
    exit 1
fi

CDPATH=
REPO_DIR=$(cd -- "$(dirname -- "$0")" && pwd)
CONF="${REPO_DIR}/conf/toolkit.conf"

if [ ! -f "$CONF" ]; then
    echo "ERROR: missing config at $CONF" >&2
    exit 1
fi
# shellcheck source-path=SCRIPTDIR
# shellcheck source=conf/toolkit.conf
. "$CONF"

echo "[*] Making scripts executable..."
chmod 0755 "$REPO_DIR"/bin/*.sh

echo "[*] Creating log directory at $LOG_DIR ..."
mkdir -p "$LOG_DIR"
chmod 0750 "$LOG_DIR"

CRON_FILE="/etc/cron.d/ops-toolkit"
echo "[*] Installing cron jobs to $CRON_FILE ..."
cat > "$CRON_FILE" <<EOF
# ops-toolkit scheduled jobs (managed by install.sh; edits may be overwritten)
SHELL=/bin/sh
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# Daily backup at 02:00
0 2 * * * root ${REPO_DIR}/bin/backup.sh >/dev/null 2>&1

# Hourly health check
0 * * * * root ${REPO_DIR}/bin/health_check.sh >> ${LOG_DIR}/health.log 2>&1

# Optional: SSH brute-force guard every 5 minutes (uncomment to enable)
#*/5 * * * * root ${REPO_DIR}/bin/ssh_guard.sh >/dev/null 2>&1
EOF
chmod 0644 "$CRON_FILE"

echo "[*] Done."
echo "    Logs: $LOG_DIR"
echo "    Cron: $CRON_FILE"
echo "    Test: sudo ${REPO_DIR}/bin/health_check.sh"
