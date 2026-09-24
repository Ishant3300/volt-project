# Backend Deployment Runbook

Production backend for **apexlive-api.mynpe.in**.

- **Host:** `13.207.113.128` (EC2 c6i.large, 2 vCPU / 4 GB, ap-south-1 / Mumbai)
- **Storage:** 50 GB gp3 root volume
- **OS:** Amazon Linux 2023
- **SSH key:** `/Users/devarshukani/Work/Keys/apex/apex-backend-prod.pem`
- **User:** `ec2-user`
- **Remote app dir:** `/home/ec2-user/stocker-backend-node`
- **PM2 app name:** `stocker-backend-node`
- **App port:** `3000` (nginx proxies 80/443 → 127.0.0.1:3000)
- **DB:** MongoDB Atlas (external — not on this box)
- **Redis:** local, `127.0.0.1:6379`, capped at 1 GB / `noeviction`

---

## Scripts

| Script | What it does | When to run |
|--------|--------------|-------------|
| `configure-backend.sh` | One-time (idempotent) provisioning of a fresh box: Node 20, Redis, PM2 + log rotation, Chromium libs, swap, nginx, TLS. | Once on a new server (safe to re-run). |
| `backend-prod.sh` | Ships code + `npm install` + PM2 restart. | Every deploy. |
| `backend-logs.sh` | Tails PM2 app logs. | Debugging. |
| `redis-logs.sh` | Redis status / logs. | Debugging. |

---

## First-time setup (fresh server) — do these in order

### 1. Security group — open the required ports
In the AWS console, the instance's security group must allow **inbound**:
- **22** (SSH) — ideally restricted to your IP
- **80** (HTTP) — required for certbot's domain validation
- **443** (HTTPS) — the actual API traffic

Without 80/443 open, TLS issuance will fail.

### 2. DNS — confirm the A record
Already done in Hostinger: `apexlive-api` → `13.207.113.128` (A, TTL 60).
Confirm it has propagated before requesting the cert:
```bash
dig +short apexlive-api.mynpe.in     # should print 13.207.113.128
```

### 3. Set the certbot email
Edit `deploy/configure-backend.sh` and change:
```bash
CERTBOT_EMAIL="admin@mynpe.in"   # <-- use a real address you control
```
(Let's Encrypt sends renewal-failure warnings here.)

### 4. Provision the box
```bash
bash deploy/configure-backend.sh
```
This installs and configures everything. If certbot fails because DNS hadn't
propagated yet or a port was closed, fix that and just **re-run the script** —
it skips everything already done and retries only the cert.

### 5. Upload the production `.env`
`.env` is intentionally NOT synced by the deploy (it holds secrets). Copy it once:
```bash
scp -i /Users/devarshukani/Work/Keys/apex/apex-backend-prod.pem \
    apps/backend/.env \
    ec2-user@13.207.113.128:/home/ec2-user/stocker-backend-node/.env
```
Make sure it contains at minimum: `MONGO_URI`, `JWT_SECRET`, `KITE_API_KEY`,
`KITE_API_SECRET`, `MASSIVE_API_KEY`, `PORT=3000`, `NODE_ENV=production`,
`REDIS_URL=redis://127.0.0.1:6379`, and `DISABLE_BG_SERVICES=false`.

> ⚠️ **Critical:** `DISABLE_BG_SERVICES` must be `false` (or unset) in production.
> If it's `true`, the cron jobs, Kite feed, and live prices do NOT run.

### 6. Deploy the app
```bash
bash deploy/backend-prod.sh
```
This uploads code, installs deps, and starts the app under PM2 (with `pm2 save`
so it survives reboots).

### 7. Verify
```bash
curl -I https://apexlive-api.mynpe.in            # expect 200/301, valid TLS
bash deploy/backend-logs.sh                       # watch startup sequence
```
Watch for the `SERVER LISTENING on port 3000` line and `Redis ready: true`.

---

## Routine deploys (after first-time setup)

```bash
bash deploy/backend-prod.sh
```
That's it. The script refuses to run if `.env` or node/pm2 are missing.

---

## Guardrails installed (so the box won't crash on full disk / OOM)

These are configured by `configure-backend.sh` and re-asserted on every deploy:

- **Redis capped:** `maxmemory 1gb`, `maxmemory-policy noeviction`, `appendonly no`,
  `bind 127.0.0.1`. A BullMQ backlog can no longer fill the disk; Redis rejects
  new writes instead, and the app falls back to DB polling. The order book is
  rebuilt from Mongo on restart (`orderBookService.syncFromDatabase`).
- **PM2 log rotation:** each log file capped at 100 MB, 7 files retained,
  compressed. Prevents the log-heavy app from filling the disk.
- **2 GB swap:** OOM safety net for the hourly Puppeteer/Chromium spike during
  Kite auto-login (~300–400 MB transient).
- **journald capped:** `SystemMaxUse=200M`.

### Health checks
```bash
ssh -i <key> ec2-user@13.207.113.128
df -h /                                  # disk usage
free -h                                  # RAM + swap
pm2 status                               # app state
pm2 monit                                # live CPU/mem per process (watch at market open)
redis6-cli info memory | grep used_memory_human
du -sh ~/.pm2/logs ~/stocker-backend-node/scripts/downloads
```

---

## Rollback / troubleshooting

- **App won't start:** `bash deploy/backend-logs.sh` — usually a `.env` value
  (bad `MONGO_URI`, missing secret) or `DISABLE_BG_SERVICES=true`.
- **502 from nginx:** the Node app isn't up on :3000. Check `pm2 status`.
- **WebSocket won't connect:** confirm the nginx `/ws/live-prices` block exists
  (`sudo nginx -t && sudo cat /etc/nginx/conf.d/apexlive-api.mynpe.in.conf`).
- **Cert renewal:** automatic via the certbot systemd timer. Test with
  `sudo certbot renew --dry-run`.
- **`scripts/downloads` growing:** daily bhavcopy/instrument CSVs accumulate.
  Safe to prune: `find ~/stocker-backend-node/scripts/downloads -type f -mtime +30 -delete`.

---

## Migrating from the OLD server (13.204.61.199)

The old box used key `my-ec2-key`. Once the new box is verified serving traffic
on the domain, the old instance can be stopped/terminated. Nothing on it is
authoritative — MongoDB (Atlas) and the data live off-box; Redis state rebuilds
from Mongo on startup.
