#!/usr/bin/env bash
# frank-ops.sh — the ONLY command the command-center SSH key may run.
# authorized_keys forces this script; the requested action arrives in
# $SSH_ORIGINAL_COMMAND as a single whitelisted word (+ optional arg).
set -euo pipefail

NS=frank
DEPLOY=frank-backend-real
SRC="$HOME/frank-src"
LAN_GPU="192.168.1.171"

req="${SSH_ORIGINAL_COMMAND:-status}"
action="$(printf '%s' "$req" | awk '{print $1}')"
arg="$(printf '%s' "$req" | awk '{print $2}')"

log(){ printf '%s\n' "$*"; }

case "$action" in
  status)
    sha="$(cd "$SRC" && git rev-parse --short HEAD 2>/dev/null || echo '?')"
    img="$(kubectl get deploy "$DEPLOY" -n "$NS" -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null || echo '?')"
    pods="$(kubectl get pods -n "$NS" --no-headers 2>/dev/null | awk '{print $1"="$3}' | paste -sd, -)"
    ready="$(kubectl get deploy "$DEPLOY" -n "$NS" -o jsonpath='{.status.readyReplicas}/{.status.replicas}' 2>/dev/null || echo '?')"
    disk="$(df -h / | awk 'NR==2{print $5" used, "$4" free"}')"
    up="$(uptime -p 2>/dev/null || uptime)"
    load="$(cut -d' ' -f1-3 /proc/loadavg)"
    health="$(kubectl exec -n "$NS" deploy/"$DEPLOY" -- curl -s -m5 localhost:8000/health 2>/dev/null | head -c 120 || echo 'unreachable')"
    gpu="down"; ping -c1 -W2 "$LAN_GPU" >/dev/null 2>&1 && gpu="up"
    cat <<EOF
{"ok":true,"git_sha":"$sha","image":"$img","ready":"$ready","pods":"$pods","node_disk":"$disk","node_uptime":"$up","node_load":"$load","backend_health":"$health","lan_gpu":"$gpu","ts":"$(date -u +%FT%TZ)"}
EOF
    ;;
  agentops)
    kubectl exec -n "$NS" deploy/"$DEPLOY" -- python3 -c "from core.frank_agentops import snapshot; import json; print(json.dumps(snapshot(),default=str))" 2>/dev/null || echo '{"ok":false,"error":"agentops unavailable"}'
    ;;
  logs)
    n="${arg:-80}"; case "$n" in ''|*[!0-9]*) n=80;; esac
    kubectl logs -n "$NS" deploy/"$DEPLOY" --tail="$n" 2>&1 | tail -n "$n"
    ;;
  restart)
    kubectl rollout restart deploy/"$DEPLOY" -n "$NS"
    kubectl rollout status deploy/"$DEPLOY" -n "$NS" --timeout=180s
    ;;
  rollback)
    kubectl rollout undo deploy/"$DEPLOY" -n "$NS"
    kubectl rollout status deploy/"$DEPLOY" -n "$NS" --timeout=180s
    ;;
  redeploy)
    cd "$SRC"
    git fetch origin -q && git reset --hard origin/master -q
    sha="$(git rev-parse --short HEAD)"
    log "building $sha ..."
    sudo docker build -q -f Dockerfile.k3s -t frank-backend:k3s . 2>&1 | tail -3
    sudo docker save frank-backend:k3s | sudo k3s ctr images import - 2>&1 | tail -1
    kubectl rollout restart deploy/"$DEPLOY" -n "$NS"
    kubectl rollout status deploy/"$DEPLOY" -n "$NS" --timeout=300s
    log "redeployed to $sha"
    ;;
  pipeline)
    # run one Frank pipeline handler inside the backend pod
    case "$arg" in
      nyc_news|agentops_digest|meta_ads_boost|grok_trade|youtube_automation_agent) : ;;
      *) echo "unknown pipeline: $arg"; exit 2;;
    esac
    kubectl exec -n "$NS" deploy/"$DEPLOY" -- python3 -c "
import datetime, importlib
m = importlib.import_module('scripts.unified_cron_runner')
getattr(m, 'h_${arg}')(datetime.datetime.now())
print('ran ${arg}')
" 2>&1 | tail -5
    ;;
  trading)
    case "$arg" in
      kill)   kubectl exec -n "$NS" deploy/"$DEPLOY" -- sh -c 'touch /tmp/FRANK_KILL_SWITCH && echo killed' ;;
      resume) kubectl exec -n "$NS" deploy/"$DEPLOY" -- sh -c 'rm -f /tmp/FRANK_KILL_SWITCH && echo released' ;;
      *) echo "trading: kill|resume"; exit 2;;
    esac
    ;;
  gpu)
    case "$arg" in
      status) ping -c2 -W2 "$LAN_GPU" >/dev/null 2>&1 && echo '{"lan_gpu":"up"}' || echo '{"lan_gpu":"down"}' ;;
      wake)   command -v wakeonlan >/dev/null && wakeonlan "${FRANK_GPU_MAC:-}" 2>&1 || echo "wakeonlan not configured (set FRANK_GPU_MAC)"; ;;
      reboot) ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "og@$LAN_GPU" 'sudo reboot' 2>&1 || echo "gpu unreachable" ;;
      *) echo "gpu: status|wake|reboot"; exit 2;;
    esac
    ;;
  *)
    echo "unknown action: $action"; exit 2 ;;
esac
