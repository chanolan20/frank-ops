#!/usr/bin/env bash
# Polls chanolan20/frank-ops/queue/ for pending actions, runs each through
# frank-ops.sh (the whitelist), writes output to results/, removes from queue.
set -uo pipefail
REPO_DIR="$HOME/frank-ops-repo"
KEY="$HOME/.ssh/frank_ops_deploy"
export GIT_SSH_COMMAND="ssh -i $KEY -o IdentitiesOnly=yes -o StrictHostKeyChecking=no"
OPS="$HOME/frank-ops.sh"

cd "$REPO_DIR" 2>/dev/null || exit 1
git fetch origin -q && git reset --hard origin/main -q 2>/dev/null || exit 0

shopt -s nullglob
changed=0
for f in queue/*.json; do
  [ -e "$f" ] || continue
  id="$(basename "$f" .json)"
  cmd="$(python3 -c "import json,sys; print(json.load(open('$f')).get('command',''))" 2>/dev/null)"
  [ -n "$cmd" ] || { git rm -q "$f"; changed=1; continue; }
  echo "[$(date -u +%FT%TZ)] running: $cmd"
  out="$(SSH_ORIGINAL_COMMAND="$cmd" bash "$OPS" 2>&1 | tail -c 6000 || true)"
  {
    echo "# $id"
    echo "action: $cmd"
    echo "ran_at: $(date -u +%FT%TZ)"
    echo '```'
    echo "$out"
    echo '```'
  } > "results/${id}.md"
  git rm -q "$f"
  git add "results/${id}.md"
  changed=1
done

if [ "$changed" = 1 ]; then
  git -c user.email=ops@manhattanviral.com -c user.name="frank-ops" commit -q -m "ran queued actions"
  git push -q origin HEAD:main
fi
