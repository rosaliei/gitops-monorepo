# ErrorBudgetBurnFast

**Meaning.** More than 14.4% of requests to a service have failed (5xx) over the last hour *and*
the last 5 minutes. At this rate the 30-day error budget (1% of requests, SLO 99%) would be used up
in about 2 days. Users are affected right now.

**Check**
1. Grafana → *Services (RED)* → error ratio: which service and which environment?
2. Grafana → *GitOps Delivery* → *What version runs where*: did the version change just before the errors started?
3. `kubectl -n demo-<env> logs deploy/<app> --since=15m`

**Fix**
- **Caused by a deploy** → roll back (fastest, safest):
  - prod: *Actions → Promote to production* → same app, previous version → approve → merge the PR.
  - by hand: `scripts/set-image.sh prod <app> <previous-version>` → commit → PR → merge.
- **Not caused by a deploy** (dependency down, bad data) → fix forward, keep the incident channel updated.

**Try it** (dev): `for i in $(seq 50); do curl -s -XPOST localhost:8081/api/orders/orders -H 'content-type: application/json' -d '{"item":"error","quantity":1}'; done`
(`make ui-shop ENV=dev` first. The frontend proxies `/api/orders/*` to orders-api.)
