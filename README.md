# frank-ops

The message bus between the Frank command center (`manhattanviral.com/command`)
and the Oracle K3s server. No open ports, no SSH keys on Vercel — GitHub is the
channel.

- **`status.json`** — a Frank status snapshot. The Oracle host pushes a fresh one
  every 2 minutes (via `frank-status-export.sh` on cron). The command center reads
  it. Currently a **seed** — see setup below.
- **`queue/`** — the command center drops `<timestamp>-<action>.json` here. The
  Oracle host polls, runs the whitelisted action via `frank-ops.sh`, moves the
  file to `results/` with the output appended.
- **`frank-ops.sh`** — the ONLY thing the queue poller executes. Whitelisted
  actions: `status`, `redeploy`, `restart`, `rollback`, `logs`, `agentops`,
  `pipeline <name>`, `trading kill|resume`, `gpu status|wake|reboot`.
- **`frank-status-export.sh`** — read-only telemetry exporter for the cron.
- **`MASTER_PLAN.md`** — the Frank master plan (also rendered at `/command`).

## One-time Oracle-host setup (run these on `ubuntu@129.213.148.144`)

```bash
# 1. deploy key for this repo (write) — paste the private key you were given
mkdir -p ~/.ssh && nano ~/.ssh/frank_ops_deploy   # paste, then chmod 600
chmod 600 ~/.ssh/frank_ops_deploy

# 2. get the scripts
git clone git@github.com:chanolan20/frank-ops.git ~/frank-ops-repo   # or via https
cp ~/frank-ops-repo/frank-ops.sh ~/frank-ops.sh && chmod 755 ~/frank-ops.sh
cp ~/frank-ops-repo/frank-status-export.sh ~/frank-status-export.sh && chmod 755 ~/frank-status-export.sh

# 3. cron: export status every 2 min, run the queue every 2 min
( crontab -l 2>/dev/null; \
  echo '*/2 * * * * ~/frank-status-export.sh >/dev/null 2>&1'; \
  echo '*/2 * * * * ~/frank-ops-queue.sh >/dev/null 2>&1' ) | crontab -
```

The command center works read-only the moment step 2 runs; actions work after
step 3 + a `GITHUB_OPS_TOKEN` in the Vercel project env.
