#!/usr/bin/env bash
# Pushes a Frank status snapshot to github.com/chanolan20/frank-ops every run.
# Read-only telemetry: kubectl status, node health, AgentOps snapshot. No actions.
set -uo pipefail

NS=frank
DEPLOY=frank-backend-real
REPO_DIR="$HOME/frank-ops-repo"
KEY="$HOME/.ssh/frank_ops_deploy"
export GIT_SSH_COMMAND="ssh -i $KEY -o IdentitiesOnly=yes -o StrictHostKeyChecking=no"

[ -d "$REPO_DIR/.git" ] || git clone -q git@github.com:chanolan20/frank-ops.git "$REPO_DIR" 2>/dev/null
cd "$REPO_DIR" || exit 1
git fetch origin -q && git reset --hard origin/main -q 2>/dev/null || git reset --hard origin/master -q 2>/dev/null

sha="$(cd "$HOME/frank-src" 2>/dev/null && git rev-parse --short HEAD 2>/dev/null || echo '?')"
img="$(kubectl get deploy "$DEPLOY" -n "$NS" -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null || echo '?')"
ready="$(kubectl get deploy "$DEPLOY" -n "$NS" -o jsonpath='{.status.readyReplicas}/{.status.replicas}' 2>/dev/null || echo '?')"
pods_json="$(kubectl get pods -n "$NS" -o json 2>/dev/null | python3 -c "
import sys,json
try: d=json.load(sys.stdin)
except Exception: print('[]'); sys.exit()
out=[]
for p in d.get('items',[]):
    cs=p.get('status',{}).get('containerStatuses') or [{}]
    out.append({'name':p['metadata']['name'],'phase':p['status'].get('phase'),
                'ready':all(c.get('ready') for c in cs),
                'restarts':sum(c.get('restartCount',0) for c in cs)})
print(json.dumps(out))
" 2>/dev/null || echo '[]')"
disk="$(df -h / | awk 'NR==2{print $5}')"
load="$(cut -d' ' -f1-3 /proc/loadavg)"
up="$(uptime -p 2>/dev/null || echo '?')"
gpu="down"; ping -c1 -W2 192.168.1.171 >/dev/null 2>&1 && gpu="up"
agentops="$(kubectl exec -n "$NS" deploy/"$DEPLOY" -- python3 -c "from core.frank_agentops import snapshot; import json; print(json.dumps(snapshot(),default=str))" 2>/dev/null || echo '{}')"
health="$(kubectl exec -n "$NS" deploy/"$DEPLOY" -- curl -s -m5 localhost:8000/health 2>/dev/null | head -c 200 || echo 'unreachable')"

python3 - "$sha" "$img" "$ready" "$disk" "$load" "$up" "$gpu" "$health" <<PYEOF > status.json
import sys, json, datetime
sha,img,ready,disk,load,up,gpu,health = sys.argv[1:9]
print(json.dumps({
  "ts": datetime.datetime.now(datetime.timezone.utc).isoformat(),
  "oracle": {"git_sha": sha, "image": img, "backend_ready": ready, "node_disk_used": disk,
             "node_load": load, "node_uptime": up, "backend_health": health},
  "pods": json.loads('''$pods_json'''),
  "lan_gpu": gpu,
  "agentops": json.loads('''$agentops'''),
}, indent=2))
PYEOF

git add status.json
git -c user.email=ops@manhattanviral.com -c user.name="frank-ops" commit -q -m "status $(date -u +%FT%TZ)" 2>/dev/null && git push -q origin HEAD:main 2>/dev/null || git push -q origin HEAD:master 2>/dev/null
