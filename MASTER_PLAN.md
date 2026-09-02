# Frank — Master Plan

_Generated 2026-09-02. One system, eight surfaces. This is the plan to make every
one of them better, and to give you a single command center for the whole thing._

---

## The shape of Frank today

Frank is one operator spread across eight surfaces. Right now they work, but they
drift apart — code lives in three places, observability lives in a dozen, and
there's no single screen that shows you the whole picture or lets you act on it.

| Surface | What it is | State |
|---|---|---|
| **Mac main drive** (`~/frank`) | The live runtime — supervisor, brain, autonomy loops, cron scheduler, Hermes gateway | ✅ running; ⚠️ git on a `backup/*` branch, disk 92% |
| **External drive** (`/Volumes/Devin On the Beat`) | Heavy assets, archives, the `.venv313` Python env, model files | ✅ 72% used, 263 GB free |
| **Frank.app** (desktop UI) | The Mac control-center UI + voice | ✅ running on :899 |
| **LAN GPU server** (`192.168.1.171`) | Home box for local image/video gen (RX 580) | 🔴 **down** since 2026-08-30 (amdgpu ring timeout) |
| **Oracle server** (K3s, `129.213.148.144`) | The canonical backend — `frank-backend-real` + postgres, redis, ollama, wireguard | ✅ all 6 pods healthy, on `master` |
| **Cloudflare** | `frank-worker` + Workers AI (free image gen), Pages | ✅ worker live (deployed 2026-08-21) |
| **GitHub** (`chanolan20/frank`) | Source of truth | ✅ `master` current; 🔴 Actions billing-blocked |
| **Vercel** (`frank` → `manhattanviral.com`) | Public site | ✅ production live, auto-deploying |

---

## Guiding principles

1. **One canonical path.** Master is the source of truth. K3s runs master. The Mac
   should run master. No more split-brain.
2. **Free-first.** Qwen (DashScope) → NVIDIA NIM → Groq → Mistral → DeepSeek-free →
   Gemini. Paid providers (xAI, OpenAI, Anthropic) only behind `FRANK_ALLOW_PAID`.
3. **Small, hard caps on anything that spends.** Trading $1/$10/$5. Ads $5/$30.
   Every campaign and trade PAUSED until explicitly enabled.
4. **One pane of glass.** `frank_agentops` already aggregates everything — the
   command center is its front door.
5. **Nothing silent.** A frozen scheduler, a dead provider, a bypassed allowlist —
   all of these hid for hours or days. Every failure gets surfaced.

---

## Priority 1 — Stability (this is what breaks the business)

| Item | Why | Action |
|---|---|---|
| **Cron scheduler hang guard** | It froze 5.5 h on one stuck LLM call and took every scheduled job down with it | ✅ **done** — `signal.alarm(600s)` per handler (`b640e4db`) |
| **LLM cascade health** | 26% success — a broken local model was tried first on every call | ✅ **done** — removed `nemotron-3-nano:4b`, pulled `qwen2.5-coder:3b`, demoted ollama |
| **xAI circuit breaker** | Out-of-credits endpoint hammered every cascade call | ✅ **done** — 30-min cooldown after any failure |
| **Reconcile the Mac onto `master`** | Mac runs off a divergent `backup/*` branch that Frank's own loops commit to; 55 ahead / 39 behind | Take a maintenance window: stash the autonomy-cycle noise, `git checkout master`, verify daemons, point the autonomy commit target at a dedicated branch |
| **Mac disk at 92%** | 39 GB left; a big render or model pull fills it | Move `logs/` rotation to 7 days, push `memory/*.jsonl` older than 30 d to the external drive, prune `content/` renders after upload |
| **chromadb reinstalled but empty** | Vector recall returned nothing for who knows how long | ✅ package fixed — now re-ingest: `migrate_json_to_chroma` over `memory/` + rebuild the rag index |
| **`com.frank.scheduler` LaunchAgent** flaky (stuck in xpcproxy) | Needed a manual bootout/bootstrap | Rewrite the plist with an explicit interpreter path + `ThrottleInterval`, add a watchdog check to `frank_agentops` |

## Priority 2 — Money (Frank's revenue is $0 all-time)

| Item | State | Next |
|---|---|---|
| **Grokbot** | LIVE on Coinbase, $1/trade, running on Qwen/DeepSeek (xAI out of credits) | Fund xAI **or** accept the free models. Let the shadow log build a week, then judge edge before raising caps. |
| **E\*TRADE / Gemini exchange** | No API keys exist anywhere | You create keys → drop in `.env` → venue slots are already coded |
| **Instagram ads** | Built, PAUSED, account funded (VISA \*3591) | Set `FRANK_META_ADS_LIVE=1` when you want to start the $3/day test |
| **Content → FB + IG** | ✅ verified live, hourly, Qwen-written | Fix `_pick_nyc_topic()` — it's choosing off-brand headlines. Add a hard NYC-topic filter. |
| **The real bottleneck** | 124 FB / 128 IG followers, no product, no offer | This is a **business decision only you can make**: what does Manhattan Viral sell? Ads + content compound nothing without an offer at the end. |

## Priority 3 — Convergence

| Item | Action |
|---|---|
| **Unified observability** | ✅ `frank_agentops` built. Next: nightly digest is wired; add the failure/drift signals from the Brij-Pandey harness model. |
| **Hermes = the harness** | Wire `eval_scoreboard` + `cite_or_abstain` as the Hermes end-of-run gate. Wire ONE memory provider (Mem0) and retire the parallel Chroma path. Mine `awesome-hermes-skills`. |
| **LAN GPU server** | When you can get to the machine: reboot, check `dmesg` for amdgpu, consider disabling Vulkan compute and falling back to CPU/ROCm. Until then, image/video gen stays on Cloudflare Workers AI + Pollinations (already the case). |
| **GitHub Actions** | Billing-blocked. Either add a paid plan, or move the scheduled workflows to the Oracle host's cron (most already are, via `unified_cron_runner`). |
| **DeepSeek repos** | `awesome-deepseek-integration` has RAGFlow / KAG / Youtu-GraphRAG — evaluate against LightRAG if KG quality stays marginal. Everything else (harness, DeepGEMM) is skip. |

---

## The Command Center — BUILT & LIVE

**https://frank-flax.vercel.app/command · password `bahUeGAxw_E3`** — working now,
zero setup. Full doc: `COMMAND_CENTER.md`.

```
  phone ─▶ frank-flax.vercel.app/command   (PBKDF2 password hash in code)
            ↕  github.com/chanolan20/frank-ops   (public: status.json + queue/ + results/)
            ↕  core/cc_sync.py on the Mac, every 3 min (has gh auth + ssh to Oracle):
                 ssh Oracle → snapshot → push status.json
                 read queue/ → run whitelisted kubectl/pipeline cmd → push results/
            ▼  Oracle K3s
```

No open ports, no SSH keys on Vercel, no secrets to configure — GitHub is the bus
and the Mac is the executor.

**Sections:** Pulse (AgentOps digest + surface grid + pods) · Server (redeploy /
restart / rollback) · Pipelines (run any on demand + trading kill switch) · GPU
(LAN box status/wake/reboot) · Master Plan (this doc).

**Status:** ✅ done. Live status feed (3-min refresh, real merged data), actions
execute (verified). Action buttons open a 1-click GitHub commit; an optional
`GITHUB_OPS_TOKEN` in Vercel makes them instant.

---

## What needs you (and only you)

1. **Decide what Manhattan Viral sells.** Everything else is plumbing.
3. **Fund xAI** (or accept free-model grokbot).
4. **Create E\*TRADE + Gemini API keys** if you want those venues.
5. **Get to the LAN GPU box** to reboot it.
6. **Flip the switches when ready:** `FRANK_META_ADS_LIVE=1`, raise trading caps.
