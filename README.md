# Blue/Green Deployment Platform

A zero-downtime deployment platform with two persistent production environments, 
instant traffic switching, and sub-minute rollback.

## Architecture

```
                 ALB (port 80)
                      │
          ┌───────────┴───────────┐
     TG-blue (100%)          TG-green (0%)
          │                       │
  ECS service "blue"     ECS service "green"
    (ACTIVE: v1.1.0)       (IDLE: ready)

  Test listener :8443 ──► always points to IDLE
  (smoke tests run here — prod untouched)
```

## Quickstart

```bash
# 1. Bootstrap S3 state backend
./docs/SETUP_GUIDE.md  # follow Phase 1

# 2. Deploy infrastructure
cd terraform/envs/prod && terraform apply

# 3. Set GitHub secrets (see SETUP_GUIDE.md Phase 3)

# 4. Push to main → pipeline runs automatically
```

## Key files

| File | Purpose |
|---|---|
| `docs/SETUP_GUIDE.md` | Full step-by-step setup |
| `docs/INTERVIEW_TALKING_POINTS.md` | Prep for technical interviews |
| `scripts/get_active.sh` | Detect which color serves prod |
| `scripts/smoke_test.sh` | Health check idle env via test listener |
| `scripts/switch_traffic.sh` | ALB cutover (supports canary mode) |
| `scripts/rollback.sh` | Instant rollback, logs SLA |
| `scripts/measure_rollback_sla.sh` | Benchmark rollback, write docs/sla-results.md |
| `.github/workflows/deploy.yml` | Full pipeline: build→deploy→smoke→approve→switch→verify |
| `.github/workflows/rollback.yml` | Push-button manual rollback |

## Rollback SLA

Target: **< 60 seconds**. Typical: **~8–12 seconds**.

```bash
# Measure it yourself
export PROD_LISTENER_ARN=... TG_BLUE_ARN=... TG_GREEN_ARN=... ALB_DNS=...
./scripts/measure_rollback_sla.sh 5
cat docs/sla-results.md
```

## Pipeline stages

```
push → build → push-to-ECR → detect-idle → deploy-idle
     → smoke-test (:8443) → [APPROVAL] → switch-ALB
     → bake-window (5min) → auto-rollback-if-errors
```
