# linux-ops-toolkit

A small, dependency-light operations toolkit for Linux servers, written in
portable POSIX `sh`. Three scripts share one config file and install with a
single command.

All scripts pass `shellcheck -x -s sh` with zero findings and parse under
`dash`, so they are not tied to bash.

## What's inside

| Script                | Purpose                                                        |
|-----------------------|----------------------------------------------------------------|
| `bin/backup.sh`       | rsync snapshot backup with hardlink dedup + age-based retention |
| `bin/ssh_guard.sh`    | parses `auth.log`, bans brute-force IPs via ufw/iptables        |
| `bin/health_check.sh` | disk / memory / load / service report with webhook alerting     |

## Structure

```
ops-toolkit/
├── bin/
│   ├── backup.sh
│   ├── ssh_guard.sh
│   └── health_check.sh
├── conf/
│   └── toolkit.conf        # single source of truth for all settings
├── install.sh             # chmod + log dir + cron.d setup (run as root)
└── README.md
```

## Install

```sh
sudo ./install.sh
```

This makes the scripts executable, creates `/var/log/ops-toolkit/`, and writes
`/etc/cron.d/ops-toolkit` (backup daily at 02:00, health check hourly).

## Configure

Edit `conf/toolkit.conf`. Every path, IP, and threshold lives there, so the
scripts themselves never need editing. To point a script at a different config:

```sh
TOOLKIT_CONF=/etc/ops-toolkit.conf ./bin/health_check.sh
```

## Run manually

```sh
sudo ./bin/health_check.sh           # prints a report, exit 1 if unhealthy
sudo ./bin/backup.sh                 # logs to /var/log/ops-toolkit/backup.log
sudo ./bin/ssh_guard.sh              # bans offenders, logs to bans.log
```

## Enable alerts

```sh
export WEBHOOK_URL="https://hooks.slack.com/services/XXX/YYY/ZZZ"
sudo -E ./bin/health_check.sh
```

## Verify

```sh
shellcheck -x -s sh bin/*.sh install.sh conf/toolkit.conf
```

## Limitations and production notes

This toolkit is built for a single Linux server at homelab scale. Here is what
it intentionally does not handle, and what you would reach for in a larger
production environment. Knowing these tradeoffs is part of using it responsibly.

**The SSH guard only catches IPv4.** It pulls addresses like `203.0.113.5` out
of the log, but not IPv6 addresses like `2001:db8::1`. An attacker connecting
over IPv6 would slip past it. Widening the pattern to match IPv6 is the fix.

**SSH bans are permanent.** Once an IP is blocked it stays blocked until you
remove the rule by hand. There is no timer that lifts the ban later, so a real
user who fat-fingers their password a few times could lock themselves out for
good. This is the main reason to keep your own IP in the whitelist.

**The SSH guard expects a Debian/Ubuntu log.** It reads `/var/log/auth.log`.
Red Hat, CentOS, and Fedora log SSH events to `/var/log/secure` instead, and
some newer systems only log to the systemd journal with no flat file at all.
On those you would point it at the right source.

**fail2ban is the production version of this.** It does everything the SSH
guard does, plus timed bans, tunable detection windows, and support for many
services, and it is widely tested in the real world. The point of building this
one is to show you understand how that kind of tool works underneath, not to
replace it.

**A backup is only as safe as where it lands.** If `/backups` sits on the same
disk or the same machine as the data, a single disk failure loses both the
originals and the backups at once. A real disaster-recovery setup copies
snapshots to a second machine or offsite, following the 3-2-1 rule: three
copies, on two kinds of storage, with one offsite. The backups are also not
encrypted, so anything sensitive in them sits in plain text.

**Health checks are a snapshot, not a trend.** The report tells you how things
look the moment it runs. It keeps no history, so it cannot tell you that memory
has been creeping upward all week. Tools like Prometheus and Grafana exist for
that kind of trending and graphing.

**Everything runs as root.** These scripts need root to read protected logs and
change firewall rules, which is normal for this kind of work, but it also means
a bug here has real power. Worth a careful read before you schedule them.

---

## Related labs

- [helpdesk-graph-toolkit](https://github.com/SudoShad/helpdesk-graph-toolkit) — PowerShell + Microsoft Graph helpdesk automation
- [endpoint-hardening-baseline](https://github.com/SudoShad/endpoint-hardening-baseline) — CIS-inspired Intune / policy-as-code Windows hardening
- [linux-homelab](https://github.com/SudoShad/linux-homelab) — Proxmox + AD/GPO + WireGuard lab notes

---

## Connect

- Portfolio: [shadman.io](https://shadman.io)
- LinkedIn: [linkedin.com/in/shadman-bari](https://linkedin.com/in/shadman-bari)
- Email: shadman@shadman.io
- Related labs: [linux-homelab](https://github.com/SudoShad/linux-homelab) · [helpdesk-graph-toolkit](https://github.com/SudoShad/helpdesk-graph-toolkit) · [endpoint-hardening-baseline](https://github.com/SudoShad/endpoint-hardening-baseline)
